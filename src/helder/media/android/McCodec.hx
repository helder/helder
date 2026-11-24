package helder.media.android;

import haxe.io.Bytes;
import helder.media.android.MediaNdk;
import hxmc.unsafe.*;

// An AMediaCodec decoder of a track's in synchronous mode, on the
// program's thread: no callbacks, so nothing of the codec's threads
// touches the heap. The system's decoder of the MIME type (the hardware's
// where it has one), else the one it ships in software (c2.android's).
// Packets wait here while it has no input buffer free (an AVCC's NAL
// lengths made start codes as they are copied in: MediaCodec takes Annex
// B); times are microseconds.
@:hxmc.unsafe(gc)
class McCodec {
	public final codec:Ptr;
	// the system's name of it (c2.android.avc.decoder)
	public final name:String;
	// dequeue's AMediaCodecBufferInfo
	public final info:Ptr;
	final queue:Array<Null<Bytes>> = [];
	final times:Array<Float> = [];
	final flags:Array<Int> = [];
	// (an AVCC's or HVCC's NAL length size: 0, the packets as they are)
	final lengths:Int;

	// (tests) the software decoders first, the system's own on every device
	public static var software = false;

	public static function mime(c:Codec):Null<String>
		return switch c {
			case H264: "video/avc";
			case Hevc: "video/hevc";
			case Vp9: "video/x-vnd.on2.vp9";
			case Av1: "video/av01";
			case Aac: "audio/mp4a-latm";
			case Mp3: "audio/mpeg";
			case Opus: "audio/opus";
			case Flac: "audio/flac";
			case _: null;
		}

	// (the system's own in software, where the first refuses the track)
	static function soft(c:Codec):String {
		var n = switch c {
			case H264: "avc";
			case Hevc: "hevc";
			case Vp9: "vp9";
			case Av1: "av1";
			case Aac: "aac";
			case Mp3: "mp3";
			case Opus: "opus";
			case _: "flac";
		}
		return 'c2.android.$n.decoder';
	}

	// t's decoder, configured by format (its keys set: AMediaFormat) onto
	// surface (nil: buffers), started
	public static function open(t:MediaTrack, format:Ptr->Void, surface:Ptr, lengths:Int):McCodec {
		var m = mime(t.codec);
		if (m == null || !MediaNdk.loaded()) throw new MediaError('no decoder for ${t.codec}');
		var f = MediaNdk.AMediaFormat_new();
		set(f, "mime", m);
		format(f);
		var made = Ptr.nil(), name = "";
		for (soft in (software ? [true, false] : [false, true])) {
			var c = Arena.scopedValue(a -> soft ? MediaNdk.AMediaCodec_createCodecByName(a.cstring(McCodec.soft(t.codec))) : MediaNdk.AMediaCodec_createDecoderByType(a.cstring(m)));
			if (c.isNull()) continue;
			if (MediaNdk.AMediaCodec_configure(c, f, surface, Ptr.nil(), 0) == 0 && MediaNdk.AMediaCodec_start(c) == 0) {
				made = c;
				name = Arena.scopedValue(a -> {
					var out:Ptr<Ptr> = a.alloc(8);
					if (MediaNdk.AMediaCodec_getName(c, out) != 0) return m;
					var n = (cast out.value : CString).toString();
					MediaNdk.AMediaCodec_releaseName(c, out.value);
					n;
				});
				break;
			}
			MediaNdk.AMediaCodec_delete(c);
		}
		MediaNdk.AMediaFormat_delete(f);
		if (made.isNull()) throw new MediaError('the system does not decode this ${t.codec}');
		return new McCodec(made, name, lengths);
	}

	function new(codec:Ptr, name:String, lengths:Int) {
		this.codec = codec;
		this.name = name;
		this.lengths = lengths;
		info = LibC.malloc(MediaNdk.INFO);
	}

	public static function set(f:Ptr, key:String, v:String)
		Arena.scoped(a -> MediaNdk.AMediaFormat_setString(f, a.cstring(key), a.cstring(v)));

	public static function int(f:Ptr, key:String, v:Int)
		Arena.scoped(a -> MediaNdk.AMediaFormat_setInt32(f, a.cstring(key), v));

	public static function buffer(f:Ptr, key:String, b:Bytes)
		Arena.scoped(a -> MediaNdk.AMediaFormat_setBuffer(f, a.cstring(key), a.copyBytes(b), b.length));

	// a key of the codec's output format (-1: none)
	public function output(key:String):Int {
		var f = MediaNdk.AMediaCodec_getOutputFormat(codec);
		if (f.isNull()) return -1;
		var v = Arena.scopedValue(a -> {
			var out:Ptr<Int32> = a.alloc(4);
			MediaNdk.AMediaFormat_getInt32(f, a.cstring(key), out) ? out.value : -1;
		});
		MediaNdk.AMediaFormat_delete(f);
		return v;
	}

	// a packet given (null: the stream's end), at time microseconds
	public function push(bytes:Null<Bytes>, time:Float, key:Bool) {
		queue.push(bytes);
		times.push(time);
		flags.push(bytes == null ? MediaNdk.END : key ? MediaNdk.KEY : 0);
		feed();
	}

	public var waiting(get, never):Int;

	function get_waiting():Int
		return queue.length;

	// what waits given while the codec has input buffers free
	public function feed() {
		while (queue.length > 0) {
			var idx = MediaNdk.AMediaCodec_dequeueInputBuffer(codec, 0);
			if (idx < 0) return;
			var b = queue.shift(), t = times.shift(), fl = flags.shift();
			var n = Arena.scopedValue(a -> {
				var size:Ptr<Int64> = a.alloc(8);
				var at = MediaNdk.AMediaCodec_getInputBuffer(codec, idx, size);
				b == null ? 0 : copy(b, at, size.value.toInt());
			});
			if (n < 0) {
				MediaNdk.AMediaCodec_queueInputBuffer(codec, idx, 0, 0, (cast haxe.Int64.fromFloat(t) : Int64), 0);
				throw new MediaError('a packet larger than the decoder\'s buffers (${b.length} bytes)');
			}
			MediaNdk.AMediaCodec_queueInputBuffer(codec, idx, 0, n, (cast haxe.Int64.fromFloat(t) : Int64), fl);
		}
	}

	// (b into the input buffer at, room bytes: its size, -1 where it does not fit)
	function copy(b:Bytes, at:Ptr, room:Int):Int {
		var n = b.length;
		if (lengths == 0) {
			if (n > room) return -1;
			LibC.memcpy(at, BytesPtr.of(b, 0, n), (n : Int64));
			return n;
		}
		var i = 0, o = 0;
		while (i + lengths <= n) {
			var size = 0;
			for (k in 0...lengths) size = size << 8 | b.get(i + k);
			i += lengths;
			if (size > n - i) size = n - i;
			if (o + 4 + size > room) return -1;
			Mem.setI32(at, o, 0x01000000);
			LibC.memcpy(at.add(o + 4), BytesPtr.of(b, i, size), (size : Int64));
			o += 4 + size;
			i += size;
		}
		return o;
	}

	// an output buffer's index (else TRY_AGAIN, FORMAT_CHANGED, ...), its
	// info's, waiting up to timeout microseconds
	public function next(timeout = 0):Int
		return MediaNdk.AMediaCodec_dequeueOutputBuffer(codec, info, timeout).toInt();

	// the output's presentation time, its size and flags
	public var time(get, never):Float;
	public var size(get, never):Int;
	public var ending(get, never):Bool;

	function get_time():Float {
		var lo = Mem.getI32(info, 8), hi = Mem.getI32(info, 12);
		return hi * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
	}

	function get_size():Int
		return Mem.getI32(info, 4);

	function get_ending():Bool
		return Mem.getI32(info, 16) & MediaNdk.END != 0;

	// what is in flight dropped (a seek)
	public function flush() {
		queue.resize(0);
		times.resize(0);
		flags.resize(0);
		MediaNdk.AMediaCodec_flush(codec);
	}

	public function close() {
		MediaNdk.AMediaCodec_stop(codec);
		MediaNdk.AMediaCodec_delete(codec);
		LibC.free(info);
	}
}
