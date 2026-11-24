package helder.media.ui;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
import helder.gfx.d3d11.D3D11;
import helder.gfx.d3d11.D3D11Backend;
import helder.gfx.d3d11.DComp;
import helder.os.win32.Com;
import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import helder.ui.draw.DcLayers;
import helder.ui.draw.UiWindow;
import hxmc.unsafe.*;

// A video shown by Windows' compositor (SampleLayer's on Windows, in a
// window of system layers: helder.ui.draw.DcLayers): a DirectComposition
// surface of the picture's size (as DcLayers' own layers are: a swap
// chain's flip presents were black in the window's captures, CI's), the
// content of a visual under the node's slot (DcLayers.visualFor), scaled
// and centred as fit says, cut by the slot's clip. Each frame is drawn into
// it and committed as it falls due on the player's clock, so DWM shows it
// at its next composition and helder draws nothing for it. The frame is turned to RGB on the CPU (as VideoShader
// turns it: its matrix, range and depth) from its planes, Media
// Foundation's in memory (a DXVA frame's read back: the GPU's video
// processor would save that, later). Until a frame was presented the node
// draws them (showing). null where the window has no system layers or
// before they showed a frame.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.DcLayers)
class WinLayer {
	public final slot:LayerSlot;
	public var fit:ImageFit = Contain;
	// whether a frame was presented on it (until then the node draws)
	public var showing(default, null) = false;

	final owner:VideoNode;
	final layers:DcLayers;
	final device:helder.gfx.Device;
	// (the render thread's: the visual in the slot's, its surface, its size)
	var inner = Ptr.nil();
	var surface = Ptr.nil();
	var failed = false;
	var width = 0;
	var height = 0;
	var last:Null<VideoFrame>;
	final placed = [-1.0, -1.0, -1.0, -1.0];
	var presents = 0;

	// (tests: what the layer did on the render thread, its calls' HRESULTs,
	// the first frames' centre read back; WinVideoStill says them)
	@:noCompletion public static final log:Array<String> = [];

	static function note(s:String)
		if (log.length < 40) log.push(s);

	static function hr(v:Int):String
		return "0x" + StringTools.hex(v, 8);

	public static function make(owner:VideoNode):Null<WinLayer> {
		var p = owner.player, ui = owner.ui;
		if (p == null || p.video == null || ui == null) return null;
		var layers:Null<DcLayers> = null;
		for (w in @:privateAccess UiWindow.open)
			if (w.ui == ui && w.compositor != null) layers = Std.downcast(w.compositor.layers, DcLayers);
		if (layers == null || layers.frames == 0) return null;
		var v = layers.visualFor();
		if (v.isNull()) return null;
		return new WinLayer(owner, layers, v);
	}

	function new(owner:VideoNode, layers:DcLayers, visual:Ptr) {
		this.owner = owner;
		this.layers = layers;
		device = layers.device;
		slot = new LayerSlot(visual);
	}

	// (each tick: the frame due presented once, the picture placed in the box)
	public function feed(p:Player):Null<VideoFrame> {
		var f = p.update();
		if (f != null && f != last) {
			last = f;
			if (present(f)) showing = true;
		}
		place(p);
		return f;
	}

	// (f in RGBA onto the surface on the render thread, committed: the
	// surface (made, or made again at its size, the first time) drawn whole)
	function present(f:VideoFrame):Bool {
		var px = f.pixels(), w = f.width, h = f.height;
		if (px.length == 0 || w <= 0 || h <= 0) return false;
		var rgba:Ptr<UInt8> = LibC.malloc(w * h * 4);
		convert(f, px, rgba);
		var visual = slot.handle, dc = layers.dev;
		device.inOrder(r -> {
			var d3d:D3D11Backend = cast r.impl;
			if (surface.isNull() || w != width || h != height) made(dc, visual, w, h);
			if (!surface.isNull()) Arena.scoped(a -> {
				var out:Ptr<Ptr> = a.alloc(8), at:Ptr<Int32> = a.alloc(8), box:Ptr<Int32> = a.alloc(24);
				var hr = IDCompositionSurface.BeginDraw(surface, Ptr.nil(), IID.ID3D11Texture2D, out, at);
				var n = ++presents;
				if (n <= 3) note('present $n: BeginDraw ${WinLayer.hr(hr)} at ${at[0]},${at[1]}, the frame ${w}x$h, its centre ${rgba[(h >> 1) * w * 4 + (w >> 1) * 4]} ${rgba[(h >> 1) * w * 4 + (w >> 1) * 4 + 1]} ${rgba[(h >> 1) * w * 4 + (w >> 1) * 4 + 2]} ${rgba[(h >> 1) * w * 4 + (w >> 1) * 4 + 3]}');
				if (hr < 0) {
					if (!failed) Sys.println('helder.media: the video\'s layer not drawn (BeginDraw 0x${StringTools.hex(hr, 8)})');
					failed = true;
					return;
				}
				// (D3D11_BOX: where the update is in the surface's texture, which may be an atlas)
				box[0] = at[0];
				box[1] = at[1];
				box[2] = 0;
				box[3] = at[0] + w;
				box[4] = at[1] + h;
				box[5] = 1;
				var ctx = @:privateAccess d3d.context, dev = @:privateAccess d3d.device;
				ID3D11DeviceContext.UpdateSubresource(ctx, out.value, 0, cast box, rgba, w * 4, 0);
				if (n <= 3) note('present $n: the texture at the frame\'s centre ${readBack(dev, ctx, out.value, at[0] + (w >> 1), at[1] + (h >> 1))}');
				Com.release(out.value);
				var e = IDCompositionSurface.EndDraw(surface), c = IDCompositionDevice.Commit(dc);
				if (n <= 3) note('present $n: EndDraw ${WinLayer.hr(e)}, Commit ${WinLayer.hr(c)}');
			});
			LibC.free(rgba);
		});
		return true;
	}

	// (the surface of w x h, opaque, the content of a visual in the slot's)
	function made(dc:Ptr, visual:Ptr, w:Int, h:Int) {
		drop(visual, dc);
		Arena.scoped(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			// (premultiplied, as DcLayers' layers are, every pixel opaque: one
			// of its alpha ignored (and a swap chain's) showed black, CI's)
			var hr = IDCompositionDevice.CreateSurface(dc, w, h, D3D.FORMAT_R8G8B8A8_UNORM, D3D.ALPHA_MODE_PREMULTIPLIED, out);
			note('made: CreateSurface ${w}x$h RGBA8 premultiplied: ${WinLayer.hr(hr)}');
			if (hr < 0) {
				Sys.println('helder.media: no surface for the video\'s layer (CreateSurface 0x${StringTools.hex(hr, 8)})');
				return;
			}
			surface = out.value;
			var v = IDCompositionDevice.CreateVisual(dc, out);
			if (v < 0) {
				note('made: CreateVisual ${WinLayer.hr(v)}');
				return;
			}
			inner = out.value;
			var c = IDCompositionVisual.SetContent(inner, surface), a = IDCompositionVisual.AddVisual(visual, inner, 1, Ptr.nil());
			note('made: SetContent ${WinLayer.hr(c)}, AddVisual to the slot\'s ${WinLayer.hr(a)}');
			width = w;
			height = h;
			placed[0] = -1;
		});
	}

	// (tests: one pixel of tex read back through a staging texture, "r g b a")
	static function readBack(dev:Ptr, ctx:Ptr, tex:Ptr, x:Int, y:Int):String
		return Arena.scopedValue(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC), out:Ptr<Ptr> = a.alloc(8), box:Ptr<Int32> = a.alloc(24);
			d.value.Width = 1;
			d.value.Height = 1;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			d.value.SampleCount = 1;
			d.value.Usage = D3D.USAGE_STAGING;
			d.value.CPUAccessFlags = D3D.CPU_ACCESS_READ;
			var hr = ID3D11Device.CreateTexture2D(dev, d, Ptr.nil(), out);
			if (hr < 0) return 'no staging (${WinLayer.hr(hr)})';
			var st = out.value;
			box[0] = x;
			box[1] = y;
			box[2] = 0;
			box[3] = x + 1;
			box[4] = y + 1;
			box[5] = 1;
			ID3D11DeviceContext.CopySubresourceRegion(ctx, st, 0, 0, 0, 0, tex, 0, cast box);
			var m = a.make(D3D11_MAPPED_SUBRESOURCE);
			hr = ID3D11DeviceContext.Map(ctx, st, 0, D3D.MAP_READ, 0, m);
			var s = hr < 0 ? 'not mapped (${WinLayer.hr(hr)})' : {
				var p:Ptr<UInt8> = m.value.pData;
				'${p[0]} ${p[1]} ${p[2]} ${p[3]}';
			};
			if (hr >= 0) ID3D11DeviceContext.Unmap(ctx, st, 0);
			Com.release(st);
			s;
		});

	// (tests: where a black still comes from, the render thread's: 1 the
	// surface also on a visual at the top of the window's root, at the box;
	// 2 the slot's visual unscaled; 3 a colour of DcLayers' own (solid) in
	// the slot's visual; 4 the surface on top of the stack; 5 and 6 the
	// colour in the slot's clip visual, in its box; 0 each undone)
	var probed = Ptr.nil();
	var probedIn = Ptr.nil();

	@:noCompletion public function probe(mode:Int, x:Float, y:Float) {
		var dc = layers.dev, root = layers.dc.root, visual = slot.handle, k = placed[2], solid = mode == 3 || mode >= 5 ? layers.solid(0x00FF00) : Ptr.nil();
		if (mode == 7) note('the box as placed: ${layers.placedOf(slot).join(", ")} (x, y, w, h, alpha, shown)');
		var levels = layers.visualsOf(slot);
		device.inOrder(_ -> Arena.scoped(a -> {
			var out:Ptr<Ptr> = a.alloc(8), m:Ptr<Float32> = a.alloc(24);
			if (!probed.isNull()) {
				IDCompositionVisual.RemoveVisual(probedIn.isNull() ? root : probedIn, probed);
				IDCompositionVisual.RemoveVisual(visual, probed);
				Com.release(probed);
				probed = probedIn = Ptr.nil();
			}
			m[1] = m[2] = 0;
			m[0] = m[3] = mode == 2 ? 1 : k;
			m[4] = m[5] = 0;
			if (!inner.isNull()) IDCompositionVisual.SetTransform(inner, m);
			if (mode == 1 && IDCompositionDevice.CreateVisual(dc, out) >= 0) {
				probed = out.value;
				IDCompositionVisual.SetContent(probed, surface);
				m[0] = m[3] = k;
				m[4] = x;
				m[5] = y;
				IDCompositionVisual.SetTransform(probed, m);
				note('probe: on the root ${hr(IDCompositionVisual.AddVisual(root, probed, 0, Ptr.nil()))}');
			}
			if (mode == 4 && levels.length >= 3 && IDCompositionDevice.CreateVisual(dc, out) >= 0) {
				probed = out.value;
				probedIn = levels[2];
				IDCompositionVisual.SetContent(probed, surface);
				m[0] = m[3] = k;
				m[4] = x;
				m[5] = y;
				IDCompositionVisual.SetTransform(probed, m);
				note('probe: on top of the stack ${hr(IDCompositionVisual.AddVisual(probedIn, probed, 0, Ptr.nil()))}');
			}
			if (mode >= 7 && levels.length == 4 && !levels[1].isNull()) {
				// (7: the box's clip all of the window; 8: its effect let go)
				if (mode == 7) {
					var f:Ptr<Float32> = a.alloc(16);
					f[0] = -1e6;
					f[1] = -1e6;
					f[2] = 1e6;
					f[3] = 1e6;
					note('probe: the box unclipped ${hr(IDCompositionVisual.SetClip(levels[1], f))}');
				} else note('probe: the box without its effect (it had one: ${!levels[3].isNull()}) ${hr(IDCompositionVisual.SetEffect(levels[1], Ptr.nil()))}');
			}
			if (mode >= 5 && levels.length >= 3 && !solid.isNull()) {
				probed = solid;
				probedIn = levels[mode == 5 ? 0 : 1];
				if (mode >= 7) probedIn = levels[1];
				note('probe: a solid colour in the slot\'s ${mode == 5 ? "clip" : "box"} (${!probedIn.isNull()}) ${probedIn.isNull() ? "" : hr(IDCompositionVisual.AddVisual(probedIn, solid, 0, Ptr.nil()))}');
			}
			if (mode == 3 && !solid.isNull()) {
				probed = solid;
				note('probe: a solid colour in the slot ${hr(IDCompositionVisual.AddVisual(visual, solid, 0, Ptr.nil()))}');
			}
			note('probe $mode: Commit ${hr(IDCompositionDevice.Commit(dc))}');
		}));
		device.settle();
	}

	// (tests: its state now, said by WinVideoStill)
	@:noCompletion public function state():String
		return 'inner ${!inner.isNull()}, surface ${!surface.isNull()}, ${width}x$height, placed ${placed.join(",")}, presents $presents, showing $showing';

	// (the render thread's: the visual and the surface let go)
	function drop(visual:Ptr, dc:Ptr) {
		if (!inner.isNull()) IDCompositionVisual.RemoveVisual(visual, inner);
		Com.release(inner);
		Com.release(surface);
		inner = surface = Ptr.nil();
		IDCompositionDevice.Commit(dc);
	}

	// (Y'CbCr to RGBA as VideoShader turns it: the frame's matrix over the
	// samples read as a texture reads them, chroma sited left (between two
	// across, on the odd columns))
	static function convert(f:VideoFrame, px:haxe.io.Bytes, out:Ptr<UInt8>) {
		var m = VideoTexture.matrix(f), w = f.width, h = f.height, cw = (w + 1) >> 1;
		var deep = f.bits > 8, scale = deep ? 1 / 65535 : 1 / 255, bs = deep ? 2 : 1, base = w * h * bs;
		inline function sample(i:Int):Float
			return (deep ? px.getUInt16(i * 2) : px.get(i)) * scale;
		inline function chroma(x:Int, y:Int, c:Int):Float
			return sample(Std.int(base / bs) + (y * cw + x) * 2 + c);
		inline function level(v:Float):Int
			return v <= 0 ? 0 : v >= 1 ? 255 : Std.int(v * 255 + 0.5);
		var r = m[0], g = m[1], b = m[2];
		for (y in 0...h) {
			var cy = y >> 1;
			for (x in 0...w) {
				var l = sample(y * w + x), cx = x >> 1, u = chroma(cx, cy, 0), v = chroma(cx, cy, 1);
				if (x & 1 == 1 && cx + 1 < cw) {
					u = (u + chroma(cx + 1, cy, 0)) / 2;
					v = (v + chroma(cx + 1, cy, 1)) / 2;
				}
				var o = (y * w + x) * 4;
				out[o] = level(r.x * l + r.y * u + r.z * v + r.w);
				out[o + 1] = level(g.x * l + g.y * u + g.z * v + g.w);
				out[o + 2] = level(b.x * l + b.y * u + b.z * v + b.w);
				out[o + 3] = 255;
			}
		}
	}

	// (the picture in the slot's box, in pixels: scaled and centred as fit says)
	function place(p:Player) {
		var v = p.video, u = owner.ui;
		if (v == null || u == null || width == 0 || height == 0) return;
		var bw = owner.box[0] * u.scale, bh = owner.box[1] * u.scale;
		var kx = bw / width, ky = bh / height;
		switch fit {
			case Contain: kx = ky = Math.min(kx, ky);
			case Cover: kx = ky = Math.max(kx, ky);
			case _:
		}
		var x = Math.round((bw - width * kx) / 2), y = Math.round((bh - height * ky) / 2);
		if (placed[0] == x && placed[1] == y && placed[2] == kx && placed[3] == ky) return;
		placed[0] = x;
		placed[1] = y;
		placed[2] = kx;
		placed[3] = ky;
		var dc = layers.dev;
		device.inOrder(_ -> {
			if (inner.isNull()) return;
			Arena.scoped(a -> {
				var m:Ptr<Float32> = a.alloc(24);
				m[0] = kx;
				m[1] = 0;
				m[2] = 0;
				m[3] = ky;
				m[4] = x;
				m[5] = y;
				var t = IDCompositionVisual.SetTransform(inner, m);
				note('placed: scale $kx, $ky at $x, $y: SetTransform ${WinLayer.hr(t)}');
			});
			IDCompositionDevice.Commit(dc);
		});
	}

	// (the visual out of the slot's and the surface let go; the slot's
	// visual a second later, once DcLayers' commit no longer names it)
	public function dispose() {
		var visual = slot.handle, dc = layers.dev, d = device;
		d.inOrder(_ -> drop(visual, dc));
		helder.ui.Clock.after(1, () -> d.inOrder(_ -> Com.release(visual)));
	}
}
#end
