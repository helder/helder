package helder.media.android;

import hxmc.unsafe.*;

// The NDK's media (libmediandk.so: AMediaCodec, AMediaFormat, AImageReader,
// AImage; API 26's), loaded at run time (helder.os.Dl), as libandroid's
// AHardwareBuffer_describe. Statuses are media_status_t (0 OK).
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class MediaNdk {
	static function AMediaFormat_new():Ptr;
	static function AMediaFormat_delete(f:Ptr):Int;
	static function AMediaFormat_setInt32(f:Ptr, name:Ptr, v:Int):Void;
	static function AMediaFormat_setInt64(f:Ptr, name:Ptr, v:Int64):Void;
	static function AMediaFormat_setString(f:Ptr, name:Ptr, v:Ptr):Void;
	static function AMediaFormat_setBuffer(f:Ptr, name:Ptr, data:Ptr, size:Int64):Void;
	static function AMediaFormat_getInt32(f:Ptr, name:Ptr, out:Ptr<Int32>):Bool;
	static function AMediaCodec_createDecoderByType(mime:Ptr):Ptr;
	static function AMediaCodec_createCodecByName(name:Ptr):Ptr;
	static function AMediaCodec_configure(c:Ptr, format:Ptr, surface:Ptr, crypto:Ptr, flags:Int):Int;
	static function AMediaCodec_start(c:Ptr):Int;
	static function AMediaCodec_stop(c:Ptr):Int;
	static function AMediaCodec_flush(c:Ptr):Int;
	static function AMediaCodec_delete(c:Ptr):Int;
	static function AMediaCodec_dequeueInputBuffer(c:Ptr, timeoutUs:Int64):Int64;
	static function AMediaCodec_getInputBuffer(c:Ptr, idx:Int64, size:Ptr<Int64>):Ptr;
	static function AMediaCodec_queueInputBuffer(c:Ptr, idx:Int64, offset:Int64, size:Int64, time:Int64, flags:Int):Int;
	static function AMediaCodec_dequeueOutputBuffer(c:Ptr, info:Ptr, timeoutUs:Int64):Int64;
	static function AMediaCodec_getOutputBuffer(c:Ptr, idx:Int64, size:Ptr<Int64>):Ptr;
	static function AMediaCodec_getOutputFormat(c:Ptr):Ptr;
	static function AMediaCodec_releaseOutputBuffer(c:Ptr, idx:Int64, render:Bool):Int;
	static function AMediaCodec_releaseOutputBufferAtTime(c:Ptr, idx:Int64, ns:Int64):Int;
	static function AMediaCodec_setOutputSurface(c:Ptr, surface:Ptr):Int;
	static function AMediaCodec_getName(c:Ptr, out:Ptr<Ptr>):Int;
	static function AMediaCodec_releaseName(c:Ptr, name:Ptr):Void;
	static function AImageReader_newWithUsage(w:Int, h:Int, format:Int, usage:Int64, max:Int, out:Ptr<Ptr>):Int;
	static function AImageReader_getWindow(r:Ptr, out:Ptr<Ptr>):Int;
	static function AImageReader_acquireNextImage(r:Ptr, out:Ptr<Ptr>):Int;
	static function AImageReader_delete(r:Ptr):Void;
	static function AImage_delete(i:Ptr):Void;
	static function AImage_getTimestamp(i:Ptr, ns:Ptr<Int64>):Int;
	static function AImage_getHardwareBuffer(i:Ptr, out:Ptr<Ptr>):Int;
	static function AImage_getCropRect(i:Ptr, rect:Ptr<Int32>):Int;
	static function AImage_getPlaneData(i:Ptr, plane:Int, data:Ptr<Ptr>, size:Ptr<Int32>):Int;
	static function AImage_getPlanePixelStride(i:Ptr, plane:Int, out:Ptr<Int32>):Int;
	static function AImage_getPlaneRowStride(i:Ptr, plane:Int, out:Ptr<Int32>):Int;

	static var tried = false;
	static var ok = false;

	// whether this Android has them (null: not looked up yet)
	public static function loaded():Bool {
		if (!tried) {
			tried = true;
			ok = load("libmediandk.so") == null && Hb.load("libandroid.so") == null;
		}
		return ok;
	}

	// (dequeueOutputBuffer's AMediaCodecBufferInfo: offset, size, pts, flags)
	public static inline var INFO = 24;
	public static inline var TRY_AGAIN = -1;
	public static inline var FORMAT_CHANGED = -2;
	public static inline var KEY = 1;
	public static inline var END = 4;
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Hb {
	// AHardwareBuffer_Desc: width, height, layers, format (4 each), usage (8), stride
	static function AHardwareBuffer_describe(b:Ptr, desc:Ptr):Void;
}
