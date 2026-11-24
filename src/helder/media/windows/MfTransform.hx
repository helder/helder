package helder.media.windows;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.media.windows.Mf;
import helder.os.win32.Com;
import hxmc.unsafe.*;

// A Media Foundation decoder (an MFT of the system's, synchronous) driven
// directly, on the program's thread: no callbacks, so no thread of the
// system's touches the heap. Found by its input subtype (MFTEnumEx: the
// system's ranking, the codec extensions' too), the first that takes the
// track's types (setup). Packets go in as samples timed in 100 ns units,
// waiting here while it does not accept them; outputs come as it has them
// (next: a sample of its own where it provides them, else one of ours of
// its size); a format change asks setup's output again (changed).
@:hxmc.unsafe(gc)
class MfTransform {
	public final mft:Ptr;
	// whether it gives samples of its own (DXVA's textures); else ours
	public var provides(default, null) = false;

	final queue:Array<Ptr> = [];
	final buffers:Ptr;
	final status:Ptr<Int32>;
	final got:Ptr<Ptr>;
	final info:Ptr<Int32>;
	var size = 0;
	var align = 0;
	// what the last open found and each step's HRESULT (a decoder's error
	// says it): the transforms enumerated, activated, the types set
	public static var found(default, null) = "";

	public static function note(s:String)
		found += "; " + s;

	public static function hex(hr:Int):String
		return "0x" + StringTools.hex(hr, 8);
	// (asked again after a format change: the output type set; false, failed)
	public var changed:Ptr->Bool = _ -> true;

	// the system's transform of category for subtype sub (Mf.subtype's),
	// the first setup accepts (its types set: true); null where none does
	public static function open(category:Ptr, major:Ptr, sub:Ptr, setup:Ptr->Bool):Null<MfTransform> {
		if (!Mf.loaded()) return null;
		// (COM on this thread, which may not be the one that loaded Media Foundation)
		var co = helder.os.audio.Wasapi.Ole32.CoInitializeEx(Ptr.nil(), 0);
		var made = Ptr.nil();
		Arena.scoped(a -> {
			var type:Ptr<Ptr> = a.alloc(32), list:Ptr<Ptr> = a.alloc(8), n:Ptr<Int32> = a.alloc(4), out:Ptr<Ptr> = a.alloc(8);
			LibC.memcpy(type, major, 16);
			LibC.memcpy(type.raw().add(16), sub, 16);
			var cat:Ptr<MfGuid> = category;
			n.value = 0;
			list.value = Ptr.nil();
			var hr = Mf.MFTEnumEx(cat.value, Mf.ENUM, type, Ptr.nil(), list, n);
			found = '${n.value} transforms (MFTEnumEx ${hex(hr)}, CoInitializeEx ${hex(co)})';
			if (hr < 0) return;
			var all:Ptr<Ptr> = list.value;
			for (i in 0...n.value) {
				var act = all[i];
				if (made.isNull()) {
					var hr = IMFActivate.ActivateObject(act, MfId.IMFTransform, out);
					if (hr < 0) note('ActivateObject ${hex(hr)}') else {
						var t = out.value;
						if (setup(t)) made = t else Com.release(t);
					}
				}
				Com.release(act);
			}
			if (!all.isNull()) helder.os.audio.Wasapi.Ole32.CoTaskMemFree(all);
		});
		return made.isNull() ? null : new MfTransform(made);
	}

	function new(mft:Ptr) {
		this.mft = mft;
		buffers = LibC.malloc(32);
		status = LibC.malloc(4);
		got = LibC.malloc(8);
		info = LibC.malloc(12);
		streams();
		IMFTransform.ProcessMessage(mft, Mf.BEGIN_STREAMING, Ptr.nil());
		IMFTransform.ProcessMessage(mft, Mf.START_OF_STREAM, Ptr.nil());
	}

	// (what its output stream gives: its own samples, or the size of ours)
	function streams() {
		LibC.memset(info, 0, 12);
		IMFTransform.GetOutputStreamInfo(mft, 0, info);
		provides = info[0] & (Mf.PROVIDES_SAMPLES | Mf.CAN_PROVIDE_SAMPLES) != 0;
		size = info[1];
		align = info[2] > 0 ? info[2] - 1 : 0;
	}

	// a media type made by f (its attributes set), set as the output (or input) type
	public static function type(f:Ptr->Void):Ptr {
		var t = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			Mf.MFCreateMediaType(out) >= 0 ? out.value : Ptr.nil();
		});
		if (!t.isNull()) f(t);
		return t;
	}

	public static function guid(t:Ptr, key:Ptr, v:Ptr)
		IMFAttributes.SetGUID(t, key, v);

	public static function int(t:Ptr, key:Ptr, v:Int)
		IMFAttributes.SetUINT32(t, key, v);

	public static function blob(t:Ptr, key:Ptr, b:Bytes)
		Arena.scoped(a -> IMFAttributes.SetBlob(t, key, a.copyBytes(b), b.length));

	// a UINT32 attribute of t (-1: none)
	public static function read(t:Ptr, key:Ptr):Int
		return Arena.scopedValue(a -> {
			var v:Ptr<Int32> = a.alloc(4);
			IMFAttributes.GetUINT32(t, key, v) >= 0 ? v.value : -1;
		});

	// a UINT64 attribute's halves, high first (a frame size: width, height); null: none
	public static function pair(t:Ptr, key:Ptr):Null<Array<Int>>
		return Arena.scopedValue(a -> {
			var v:Ptr<Int32> = a.alloc(8);
			IMFAttributes.GetUINT64(t, key, v.raw()) >= 0 ? [v[1], v[0]] : null;
		});

	// the output types t offers, the first pick takes set (true); false where none
	public static function choose(t:Ptr, pick:Ptr->Bool):Bool {
		var i = 0, offered = [];
		while (true) {
			var hr = 0;
			var o = Arena.scopedValue(a -> {
				var out:Ptr<Ptr> = a.alloc(8);
				hr = IMFTransform.GetOutputAvailableType(t, 0, i, out);
				hr >= 0 ? out.value : Ptr.nil();
			});
			if (o.isNull()) {
				note('GetOutputAvailableType ${hex(hr)} after ${i} offered (${offered.join(" ")}), none taken');
				return false;
			}
			offered.push(StringTools.hex(subtypeOf(o), 8));
			var ok = false;
			if (pick(o)) {
				hr = IMFTransform.SetOutputType(t, 0, o, 0);
				ok = hr >= 0;
				if (!ok) note('SetOutputType ${hex(hr)}');
			}
			Com.release(o);
			if (ok) return true;
			i++;
		}
	}

	// a type's subtype: its first four bytes (a FOURCC, a WAVE_FORMAT tag)
	public static function subtypeOf(t:Ptr):Int
		return Arena.scopedValue(a -> {
			var g:Ptr<Int32> = a.alloc(16);
			IMFAttributes.GetGUID(t, MfId.SUBTYPE, g) >= 0 ? g[0] : 0;
		});

	// its output type now (released by the caller)
	public function current():Ptr
		return Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			IMFTransform.GetOutputCurrentType(mft, 0, out) >= 0 ? out.value : Ptr.nil();
		});

	// a packet given at time (100 ns units), its duration (null bytes: none)
	public function push(bytes:Bytes, time:Float, duration:Float, ?prefix:Bytes) {
		var n = bytes.length + (prefix == null ? 0 : prefix.length);
		var s = sample(n, 16);
		if (s.isNull()) throw new MediaError("no memory for a packet");
		Arena.scoped(a -> {
			var b:Ptr<Ptr> = a.alloc(8), data:Ptr<Ptr> = a.alloc(8);
			IMFSample.GetBufferByIndex(s, 0, b);
			IMFMediaBuffer.Lock(b.value, data, Ptr.nil(), Ptr.nil());
			var at = 0;
			if (prefix != null) {
				LibC.memcpy(data.value, BytesPtr.of(prefix, 0, prefix.length), (prefix.length : Int64));
				at = prefix.length;
			}
			LibC.memcpy(data.value.raw().add(at), BytesPtr.of(bytes, 0, bytes.length), (bytes.length : Int64));
			IMFMediaBuffer.Unlock(b.value);
			IMFMediaBuffer.SetCurrentLength(b.value, n);
			Com.release(b.value);
		});
		IMFSample.SetSampleTime(s, (cast haxe.Int64.fromFloat(Math.round(time)) : Int64));
		if (duration > 0) IMFSample.SetSampleDuration(s, (cast haxe.Int64.fromFloat(Math.round(duration)) : Int64));
		queue.push(s);
		feed();
	}

	// (a sample of one buffer of n bytes, aligned)
	static function sample(n:Int, align:Int):Ptr
		return Arena.scopedValue(a -> {
			var s:Ptr<Ptr> = a.alloc(8), b:Ptr<Ptr> = a.alloc(8);
			if (Mf.MFCreateSample(s) < 0) return Ptr.nil();
			if (Mf.MFCreateAlignedMemoryBuffer(n, align, b) < 0) {
				Com.release(s.value);
				return Ptr.nil();
			}
			IMFSample.AddBuffer(s.value, b.value);
			Com.release(b.value);
			s.value;
		});

	public var waiting(get, never):Int;

	function get_waiting():Int
		return queue.length;

	// what waits given while it accepts (true: any)
	public function feed():Bool {
		var any = false;
		while (queue.length > 0) {
			var hr = IMFTransform.ProcessInput(mft, 0, queue[0], 0);
			if (hr == Mf.NOT_ACCEPTING) return any;
			Com.release(queue.shift());
			if (hr < 0) throw new MediaError('the decoder refused a packet (HRESULT 0x${StringTools.hex(hr, 8)})');
			any = true;
		}
		return any;
	}

	// its next output (a sample: the caller's to release), nil where it has none now
	public function next():Ptr {
		while (true) {
			var own = provides ? Ptr.nil() : sample(size > 0 ? size : 1 << 18, align);
			LibC.memset(buffers, 0, 32);
			Mem.setPtr(buffers, 8, own);
			var hr = IMFTransform.ProcessOutput(mft, 0, 1, buffers, status);
			var s = Mem.getPtr(buffers, 8), events = Mem.getPtr(buffers, 24);
			Com.release(events);
			if (hr >= 0) {
				if (s != own) Com.release(own);
				feed();
				return s;
			}
			if (!s.isNull() && s != own) Com.release(s);
			Com.release(own);
			if (hr == Mf.STREAM_CHANGE) {
				if (!changed(mft)) throw new MediaError("the decoder's new format is not one helder shows");
				streams();
				continue;
			}
			if (hr == Mf.NEED_MORE_INPUT) {
				if (feed()) continue;
				return Ptr.nil();
			}
			throw new MediaError('the decoder failed (HRESULT 0x${StringTools.hex(hr, 8)})');
		}
	}

	// the stream's end: what it holds put out by next
	public function drain() {
		feed();
		IMFTransform.ProcessMessage(mft, Mf.DRAIN, Ptr.nil());
	}

	// what is in flight dropped (a seek)
	public function flush() {
		for (s in queue) Com.release(s);
		queue.resize(0);
		IMFTransform.ProcessMessage(mft, Mf.FLUSH, Ptr.nil());
	}

	// a message with a pointer (MFT_MESSAGE_SET_D3D_MANAGER's)
	public function message(m:Int, p:Ptr):Int
		return IMFTransform.ProcessMessage(mft, m, p);

	public function close() {
		flush();
		Com.release(mft);
		LibC.free(buffers);
		LibC.free(status);
		LibC.free(got);
		LibC.free(info);
	}
}
#end
