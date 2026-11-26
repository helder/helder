package helder.media.windows;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.media.windows.Mf;
import helder.os.windows.Com;
#if !helder.soft
import helder.gfx.d3d11.D3D11;
#end
import hxmc.unsafe.*;

// helder.media's VideoDecoder on Windows: Media Foundation's decoder of the
// codec (MfTransform: Microsoft's H.264 decoder, HEVC, VP9 and AV1 where
// their extensions are installed), H.264's and HEVC's NAL lengths made
// start codes and their parameter sets before each keyframe (av1C's OBUs
// before AV1's). With a hardware device of helder.gfx's
// (D3D11Backend.decoding) it decodes on the GPU (DXVA through an
// IMFDXGIDeviceManager on that device, its frames NV12 or P010 textures
// sampled where they are: plane "d3d11:", copied on the GPU out of the
// decoder's array); else in software, into samples of ours in memory
// (plane "mem:", copied into a texture as it is opened). Times go in as
// 100 ns units (from BASE: never below 0), each output found by its time.
@:hxmc.unsafe(gc)
class MfVideo implements VideoDecoder {
	// (tests) software decoding, the GPU's never asked
	public static var software = false;
	static inline var BASE = 1000.0;
	// (a frame's record: its sample, buffer (locked: software's), the
	// address, pitch, rows, texture (DXVA's: ours, copied out), serial, a
	// 2D buffer locked, a staging copy mapped)
	static inline var RECORD = 80;
	static var serials = 0;

	public var pending(get, never):Int;
	// the decoder: on the GPU (DXVA), else in software; why not the GPU (tests)
	public var hardware(default, null) = false;
	@:noCompletion public var why(default, null) = "";

	final track:MediaTrack;
	var mft:Null<MfTransform>;
	var manager = Ptr.nil();
	final lengths:Int;
	final prefix:Null<Bytes>;
	final keys:Array<Float> = [];
	final times:Array<Float> = [];
	final shows:Array<Bool> = [];
	final ready:Array<VideoFrame> = [];
	var matrix = "601";
	var full = false;
	var bits = 8;
	// (the stream's, its config's; bits is the output's)
	var depth = 8;
	var codedWidth = 0;
	var codedHeight = 0;
	var stride = 0;
	var width = 0;
	var height = 0;

	public static function supports(c:Codec):Bool
		return switch c {
			case H264 | Hevc | Vp9 | Av1: Mf.loaded();
			case _: false;
		}

	static function subtype(c:Codec):String
		return switch c {
			case H264: "H264";
			case Hevc: "HEVC";
			case Vp9: "VP90";
			case _: "AV01";
		}

	public function new(track:MediaTrack) {
		this.track = track;
		if (!supports(track.codec)) throw new MediaError('no decoder for ${track.codec}');
		lengths = CodecConfig.lengths(track);
		var sets = CodecConfig.sets(track), c = track.config;
		prefix = sets != null ? join(sets[0], sets[1]) : track.codec == Av1 && c != null && c.length > 4 ? c.sub(4, c.length - 4) : null;
		depth = CodecConfig.depth(track);
		bits = depth;
		width = track.width;
		height = track.height;
	}

	static function join(a:Bytes, b:Bytes):Bytes {
		var out = Bytes.alloc(a.length + b.length);
		out.blit(0, a, 0, a.length);
		out.blit(a.length, b, 0, b.length);
		return out;
	}

	function get_pending():Int
		return keys.length + (mft == null ? 0 : mft.waiting);

	function open() {
		var sub = Mf.subtype(Mf.fourcc(subtype(track.codec)));
		// (a build drawn on the CPU (helder.soft) links no Direct3D: decoded in memory)
		var device = #if helder.soft Ptr.nil() #else software ? Ptr.nil() : helder.gfx.d3d11.D3D11Backend.decoding #end;
		mft = MfTransform.open(MfId.VIDEO_DECODER, MfId.VIDEO, sub, t -> {
			// (on the GPU where it is D3D11-aware and takes the device and the types; else in software)
			why = device.isNull() ? software ? "asked for software" : "no hardware device" : !aware(t) ? "the decoder is not D3D11-aware" : "";
			if (why == "") {
				var hr = gpu(t, device);
				if (hr >= 0) {
					if (types(t, sub)) return hardware = true;
					why = 'its types refused with the device (${MfTransform.found})';
					IMFTransform.ProcessMessage(t, Mf.SET_D3D_MANAGER, Ptr.nil());
				} else
					why = 'the device refused (${MfTransform.hex(hr)})';
			}
			hardware = false;
			types(t, sub);
		});
		LibC.free(sub);
		if (mft == null) throw new MediaError('the system does not decode this ${track.codec} (${MfTransform.found})');
		mft.changed = t -> {
			codedWidth = 0;
			output(t);
		};
		formats();
	}

	static function aware(t:Ptr):Bool
		return Arena.scopedValue(a -> {
			var at:Ptr<Ptr> = a.alloc(8);
			if (IMFTransform.GetAttributes(t, at) < 0) return false;
			var v = MfTransform.read(at.value, MfId.D3D11_AWARE);
			Com.release(at.value);
			v == 1;
		});

	// (the device's manager given the decoder; its context's calls made safe
	// across threads: the decoder's on ours, helder.gfx's on its render thread)
	function gpu(t:Ptr, device:Ptr):Int {
		if (manager.isNull()) {
			var m = Arena.scopedValue(a -> {
				var token:Ptr<Int32> = a.alloc(4), out:Ptr<Ptr> = a.alloc(8);
				if (Mf.MFCreateDXGIDeviceManager(token, out) < 0) return Ptr.nil();
				if (IMFDXGIDeviceManager.ResetDevice(out.value, device, token.value) < 0) {
					Com.release(out.value);
					return Ptr.nil();
				}
				var mt:Ptr<Ptr> = a.alloc(8);
				if (IUnknown.QueryInterface(device, MfId.ID3D10Multithread, mt) >= 0) {
					ID3D10Multithread.SetMultithreadProtected(mt.value, 1);
					Com.release(mt.value);
				}
				out.value;
			});
			if (m.isNull()) return -1;
			manager = m;
		}
		return IMFTransform.ProcessMessage(t, Mf.SET_D3D_MANAGER, manager);
	}

	function types(t:Ptr, sub:Ptr):Bool {
		var w = track.width, h = track.height;
		var input = MfTransform.type(i -> {
			MfTransform.guid(i, MfId.MAJOR_TYPE, MfId.VIDEO);
			MfTransform.guid(i, MfId.SUBTYPE, sub);
			if (w > 0 && h > 0) IMFAttributes.SetUINT64(i, MfId.FRAME_SIZE, (cast haxe.Int64.make(w, h) : Int64));
			// (MFVideoInterlace_Progressive)
			MfTransform.int(i, MfId.INTERLACE_MODE, 2);
		});
		var hr = IMFTransform.SetInputType(t, 0, input, 0);
		Com.release(input);
		if (hr < 0) MfTransform.note('SetInputType ${MfTransform.hex(hr)}');
		return hr >= 0 && output(t);
	}

	// (NV12, P010 at 10 bits: the decoder's own layout, nothing converted;
	// the other where it offers only that: a DXVA decoder offers NV12 until
	// it has read a 10-bit stream, then P010 with a format change)
	function output(t:Ptr):Bool {
		var nv12 = Mf.fourcc("NV12"), p010 = Mf.fourcc("P010"), want = depth > 8 ? p010 : nv12;
		return MfTransform.choose(t, o -> MfTransform.subtypeOf(o) == want)
			|| MfTransform.choose(t, o -> MfTransform.subtypeOf(o) == (want == nv12 ? p010 : nv12));
	}

	// (the output's size, stride, picture and colours, as its type says;
	// colours unnamed: BT.601's video range, as ffmpeg reads them)
	function formats() {
		var c = mft;
		if (c == null) return;
		var t = c.current();
		if (t.isNull()) return;
		var size = MfTransform.pair(t, MfId.FRAME_SIZE);
		bits = MfTransform.subtypeOf(t) == Mf.fourcc("P010") ? 10 : 8;
		if (size != null) {
			codedWidth = size[0];
			codedHeight = size[1];
		}
		var s = MfTransform.read(t, MfId.DEFAULT_STRIDE);
		stride = s > 0 ? s : codedWidth * (bits > 8 ? 2 : 1);
		Arena.scoped(a -> {
			// (MFVideoArea: offsets as fixed point, then the size)
			var area:Ptr<Int32> = a.alloc(16);
			if (IMFAttributes.GetBlob(t, MfId.APERTURE, area, 16, Ptr.nil()) >= 0 && area[2] > 0 && area[3] > 0) {
				width = area[2];
				height = area[3];
			} else if (size != null && (width <= 0 || width > codedWidth || height > codedHeight)) {
				width = codedWidth;
				height = codedHeight;
			}
		});
		var m = MfTransform.read(t, MfId.YUV_MATRIX), r = MfTransform.read(t, MfId.NOMINAL_RANGE);
		matrix = m == 1 ? "709" : m == 4 || m == 5 ? "2020" : "601";
		full = r == 1;
		// (what it does not name, the stream's SPS does (its HEVC decoder names
		// no matrix: BT.2020 shown as 601, 4 levels off))
		var named = CodecConfig.colours(track);
		if (named != null && m <= 0) matrix = named.matrix;
		if (named != null && r <= 0) full = named.full;
		Com.release(t);
	}

	static function key(t:Float):Float
		return Math.round((t + BASE) * 1e7);

	public function decode(p:Packet, bytes:Bytes, show:Bool) {
		if (mft == null) open();
		var k = key(p.time);
		keys.push(k);
		times.push(p.time);
		shows.push(show);
		var d = p.duration > 0 ? p.duration / track.timescale * 1e7 : 0;
		mft.push(CodecConfig.annexB(bytes, lengths), k, d, p.key ? prefix : null);
		pump();
	}

	// (what it has out: frames where shown, the others let go)
	function pump() {
		var c = mft;
		if (c == null) return;
		var s;
		while (!(s = c.next()).isNull()) {
			if (codedWidth == 0) formats();
			var at = find(time(s));
			if (at < 0) {
				Com.release(s);
				continue;
			}
			var t = times[at], show = shows[at];
			keys.splice(at, 1);
			times.splice(at, 1);
			shows.splice(at, 1);
			if (show) {
				var f = frame(s, t);
				if (f != null) ready.push(f);
			} else
				Com.release(s);
		}
	}

	static function time(s:Ptr):Float
		return Arena.scopedValue(a -> {
			var t:Ptr<Int32> = a.alloc(8);
			if (IMFSample.GetSampleTime(s, t.raw()) < 0) return -1.0;
			t[1] * 4294967296.0 + (t[0] < 0 ? t[0] + 4294967296.0 : t[0]);
		});

	// (the entry an output's time is; else the earliest: a decoder that
	// times its outputs anew gives them in presentation order)
	function find(k:Float):Int {
		if (keys.length == 0) return -1;
		var best = 0;
		for (i in 0...keys.length) {
			if (Math.abs(keys[i] - k) < 1) return i;
			if (keys[i] < keys[best]) best = i;
		}
		return best;
	}

	// (s's record: a DXGI buffer's texture and slice, else its memory locked
	// while the frame is held; null where it has neither)
	function frame(s:Ptr, t:Float):Null<VideoFrame> {
		var r:Ptr = LibC.malloc(RECORD);
		LibC.memset(r, 0, RECORD);
		Mem.setPtr(r, 0, s);
		var ok = Arena.scopedValue(a -> {
			var b:Ptr<Ptr> = a.alloc(8), q:Ptr<Ptr> = a.alloc(8), n:Ptr<Int32> = a.alloc(4);
			if (IMFSample.GetBufferByIndex(s, 0, b) < 0) return false;
			Mem.setPtr(r, 8, b.value);
			#if !helder.soft
			if (IUnknown.QueryInterface(b.value, MfId.IMFDXGIBuffer, q) >= 0) {
				var tex:Ptr<Ptr> = a.alloc(8);
				var got = IMFDXGIBuffer.GetResource(q.value, IID.ID3D11Texture2D, tex) >= 0;
				IMFDXGIBuffer.GetSubresourceIndex(q.value, n);
				Com.release(q.value);
				if (got) {
					// (copied out on the GPU and the sample let go at once: a
					// synchronous decoder whose pool is held by its frames waits
					// in ProcessOutput for one back, for good where they are all held)
					var own = copyOut(tex.value, n.value);
					Com.release(tex.value);
					if (own.isNull()) return false;
					Mem.setPtr(r, 32, own);
					Com.release(b.value);
					Com.release(s);
					Mem.setPtr(r, 8, Ptr.nil());
					Mem.setPtr(r, 0, Ptr.nil());
					return true;
				}
			}
			#end
			return lock(r);
		});
		if (!ok) {
			free(r);
			return null;
		}
		Mem.setI32(r, 48, ++serials);
		return new VideoFrame(this, t, width, height, matrix, full, bits, r);
	}

	// (r's buffer locked: its address and pitch; a 2D buffer's own pitch)
	function lock(r:Ptr):Bool
		return Arena.scopedValue(a -> {
			var b = Mem.getPtr(r, 8), q:Ptr<Ptr> = a.alloc(8), data:Ptr<Ptr> = a.alloc(8), pitch:Ptr<Int32> = a.alloc(4);
			if (IUnknown.QueryInterface(b, MfId.IMF2DBuffer, q) >= 0) {
				var hr = IMF2DBuffer.Lock2D(q.value, data, pitch);
				if (hr >= 0) {
					Mem.setPtr(r, 56, q.value);
					Mem.setPtr(r, 16, data.value);
					Mem.setI32(r, 24, pitch.value);
					Mem.setI32(r, 28, codedHeight);
					return true;
				}
				Com.release(q.value);
			}
			if (IMFMediaBuffer.Lock(b, data, Ptr.nil(), Ptr.nil()) < 0) return false;
			Mem.setPtr(r, 16, data.value);
			Mem.setI32(r, 24, stride);
			Mem.setI32(r, 28, codedHeight);
			true;
		});

#if !helder.soft
	// (src's slice into a texture of ours of the picture's size, its format,
	// sampled: helder.gfx's views of its planes; nil where it fails)
	function copyOut(src:Ptr, slice:Int):Ptr
		return Arena.scopedValue(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC), out:Ptr<Ptr> = a.alloc(8), box:Ptr<Int32> = a.alloc(24);
			ID3D11Texture2D.GetDesc(src, d);
			var w = (width + 1) & ~1, h = (height + 1) & ~1;
			if (w > d.value.Width) w = d.value.Width;
			if (h > d.value.Height) h = d.value.Height;
			d.value.Width = w;
			d.value.Height = h;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_SHADER_RESOURCE;
			d.value.CPUAccessFlags = 0;
			d.value.MiscFlags = 0;
			var dev = device(src);
			if (dev.isNull()) return Ptr.nil();
			var hr = ID3D11Device.CreateTexture2D(dev, d, Ptr.nil(), out);
			if (hr < 0) {
				Com.release(dev);
				return Ptr.nil();
			}
			var own = out.value;
			ID3D11Device.GetImmediateContext(dev, out);
			var ctx = out.value;
			box[0] = 0;
			box[1] = 0;
			box[2] = 0;
			box[3] = w;
			box[4] = h;
			box[5] = 1;
			ID3D11DeviceContext.CopySubresourceRegion(ctx, own, 0, 0, 0, 0, src, slice, cast box);
			Com.release(ctx);
			Com.release(dev);
			own;
		});

	static function device(tex:Ptr):Ptr
		return Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			out.value = Ptr.nil();
			ID3D11Texture2D.GetDevice(tex, out);
			out.value;
		});

	// (a DXVA frame's texture read back: a staging copy mapped, kept while the frame is held)
	function readBack(r:Ptr):Bool
		return Arena.scopedValue(a -> {
			var tex = Mem.getPtr(r, 32), d = a.make(D3D11_TEXTURE2D_DESC), out:Ptr<Ptr> = a.alloc(8);
			ID3D11Texture2D.GetDesc(tex, d);
			d.value.Usage = D3D.USAGE_STAGING;
			d.value.BindFlags = 0;
			d.value.CPUAccessFlags = D3D.CPU_ACCESS_READ;
			var dev = device(tex);
			if (dev.isNull()) return false;
			var hr = ID3D11Device.CreateTexture2D(dev, d, Ptr.nil(), out);
			if (hr < 0) {
				Com.release(dev);
				return false;
			}
			var st = out.value;
			ID3D11Device.GetImmediateContext(dev, out);
			var ctx = out.value, m = a.make(D3D11_MAPPED_SUBRESOURCE);
			ID3D11DeviceContext.CopyResource(ctx, st, tex);
			hr = ID3D11DeviceContext.Map(ctx, st, 0, D3D.MAP_READ, 0, m);
			Com.release(ctx);
			Com.release(dev);
			if (hr < 0) {
				Com.release(st);
				return false;
			}
			Mem.setPtr(r, 64, st);
			Mem.setPtr(r, 16, m.value.pData);
			Mem.setI32(r, 24, m.value.RowPitch);
			Mem.setI32(r, 28, d.value.Height);
			true;
		});

#end

	function unlock(r:Ptr) {
		#if !helder.soft
		var st = Mem.getPtr(r, 64);
		if (!st.isNull()) {
			var dev = device(st);
			if (!dev.isNull()) Arena.scoped(a -> {
				var out:Ptr<Ptr> = a.alloc(8);
				ID3D11Device.GetImmediateContext(dev, out);
				ID3D11DeviceContext.Unmap(out.value, st, 0);
				Com.release(out.value);
				Com.release(dev);
			});
			Com.release(st);
			Mem.setPtr(r, 64, Ptr.nil());
			Mem.setPtr(r, 16, Ptr.nil());
			return;
		}
		#end
		if (Mem.getPtr(r, 16).isNull()) return;
		var q = Mem.getPtr(r, 56);
		if (!q.isNull()) {
			IMF2DBuffer.Unlock2D(q);
			Com.release(q);
		} else
			IMFMediaBuffer.Unlock(Mem.getPtr(r, 8));
		Mem.setPtr(r, 16, Ptr.nil());
		Mem.setPtr(r, 56, Ptr.nil());
	}

	function free(r:Ptr) {
		unlock(r);
		Com.release(Mem.getPtr(r, 32));
		Com.release(Mem.getPtr(r, 8));
		Com.release(Mem.getPtr(r, 0));
		LibC.free(r);
	}

	public function take(into:Array<VideoFrame>) {
		pump();
		for (f in ready) into.push(f);
		ready.resize(0);
	}

	public function flush() {
		var c = mft;
		if (c == null) return;
		c.drain();
		pump();
		// (drained: what never came will not)
		keys.resize(0);
		times.resize(0);
		shows.resize(0);
	}

	public function reset() {
		if (mft != null) mft.flush();
		keys.resize(0);
		times.resize(0);
		shows.resize(0);
		for (f in ready) f.dispose();
		ready.resize(0);
	}

	public function release(f:VideoFrame)
		free(f.image);

	// (the frame's planes in memory, locked: address, pitch, coded height;
	// a DXVA frame's read back by Media Foundation; null: none)
	public function mapped(f:VideoFrame):Null<{at:Ptr, pitch:Int, rows:Int}> {
		var r = f.image;
		if (r.isNull()) return null;
		if (Mem.getPtr(r, 16).isNull() && !(Mem.getPtr(r, 32).isNull() ? lock(r) : #if helder.soft false #else readBack(r) #end)) return null;
		return {at: Mem.getPtr(r, 16), pitch: Mem.getI32(r, 24), rows: Mem.getI32(r, 28)};
	}

	// (D3D11Backend.openShared's: a DXVA frame's texture and slice; else its
	// plane's memory, copied into a texture as it is opened; each frame its
	// own handle: the decoder's pool reuses textures and memory)
	public function plane(f:VideoFrame, plane:Int):Null<String> {
		var r = f.image;
		if (r.isNull()) return null;
		var format = plane == 0 ? (f.bits > 8 ? "r16" : "r8") : f.bits > 8 ? "rg16" : "rg8";
		var serial = Mem.getI32(r, 48), tex = Mem.getPtr(r, 32);
		if (!tex.isNull()) return 'd3d11:${hex(tex)}:0:$format:${f.width}:${f.height}:$serial';
		var m = mapped(f);
		if (m == null) return null;
		return 'mem:${hex(m.at.add(plane == 0 ? 0 : m.pitch * m.rows))}:${m.pitch}:$format:$serial';
	}

	static function hex(p:Ptr):String {
		var v:haxe.Int64 = cast p.toI64();
		return StringTools.hex(v.high, 8) + StringTools.hex(v.low, 8);
	}

	// (luma, then Cb and Cr interleaved, rows packed; P010 16 bits a sample)
	public function pixels(f:VideoFrame):Bytes {
		var m = mapped(f);
		if (m == null) return Bytes.alloc(0);
		var w = f.width, h = f.height, cw = (w + 1) >> 1, ch = (h + 1) >> 1;
		var bs = f.bits > 8 ? 2 : 1, out = Bytes.alloc((w * h + cw * ch * 2) * bs);
		var luma = w * bs, chroma = cw * 2 * bs, uv = m.at.add(m.pitch * m.rows);
		for (y in 0...h)
			BytesPtr.copyIn(out, y * luma, m.at.add(y * m.pitch), luma);
		for (y in 0...ch)
			BytesPtr.copyIn(out, w * h * bs + y * chroma, uv.add(y * m.pitch), chroma);
		return out;
	}

	public function close() {
		reset();
		if (mft != null) mft.close();
		mft = null;
		Com.release(manager);
		manager = Ptr.nil();
	}
}
#end
