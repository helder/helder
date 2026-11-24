package helder.media.apple;

import hxmc.unsafe.*;

// The C calls of Apple's media frameworks the decoders make: CoreMedia's
// format descriptions, block and sample buffers and timebases,
// VideoToolbox's decompression sessions, CoreVideo's pixel buffers,
// AudioToolbox's converters. Objects are Ptr (CF types), OSStatus Int.
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreMedia.framework/CoreMedia") extern class CoreMedia {
	static function CMVideoFormatDescriptionCreate(alloc:Ptr, codec:Int, width:Int, height:Int, extensions:Ptr, out:Ptr<Ptr>):Int;
	static function CMVideoFormatDescriptionCreateFromH264ParameterSets(alloc:Ptr, count:Int64, sets:Ptr, sizes:Ptr, nalLength:Int, out:Ptr<Ptr>):Int;
	static function CMVideoFormatDescriptionCreateFromHEVCParameterSets(alloc:Ptr, count:Int64, sets:Ptr, sizes:Ptr, nalLength:Int, extensions:Ptr,
		out:Ptr<Ptr>):Int;
	static function CMFormatDescriptionGetExtension(f:Ptr, key:Ptr):Ptr;
	static function CMVideoFormatDescriptionCreateForImageBuffer(alloc:Ptr, image:Ptr, out:Ptr<Ptr>):Int;
	static function CMBlockBufferCreateWithMemoryBlock(alloc:Ptr, memory:Ptr, length:Int64, blockAlloc:Ptr, source:Ptr, offset:Int64, size:Int64, flags:Int,
		out:Ptr<Ptr>):Int;
	static function CMBlockBufferGetDataPointer(b:Ptr, offset:Int64, lengthAt:Ptr, total:Ptr, data:Ptr<Ptr>):Int;
	static function CMSampleBufferCreateReady(alloc:Ptr, data:Ptr, format:Ptr, samples:Int64, timings:Int64, timing:Ptr, sizes:Int64, size:Ptr,
		out:Ptr<Ptr>):Int;
	static function CMSampleBufferCreateReadyWithImageBuffer(alloc:Ptr, image:Ptr, format:Ptr, timing:Ptr, out:Ptr<Ptr>):Int;
	static function CMSampleBufferGetSampleAttachmentsArray(b:Ptr, create:Bool):Ptr;
	static function CMClockGetHostTimeClock():Ptr;
	static function CMTimebaseCreateWithSourceClock(alloc:Ptr, clock:Ptr, out:Ptr<Ptr>):Int;
	static function CMTimebaseSetTime(tb:Ptr, time:CMTime):Int;
	static function CMTimebaseSetRate(tb:Ptr, rate:Float):Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox") extern class VideoToolbox {
	static function VTDecompressionSessionCreate(alloc:Ptr, format:Ptr, decoder:Ptr, attributes:Ptr, callback:Ptr, out:Ptr<Ptr>):Int;
	static function VTDecompressionSessionDecodeFrame(s:Ptr, sample:Ptr, flags:Int, refCon:Ptr, info:Ptr):Int;
	static function VTDecompressionSessionFinishDelayedFrames(s:Ptr):Int;
	static function VTDecompressionSessionWaitForAsynchronousFrames(s:Ptr):Int;
	static function VTDecompressionSessionInvalidate(s:Ptr):Void;
	static function VTIsHardwareDecodeSupported(codec:Int):Bool;
	static function VTPixelTransferSessionCreate(alloc:Ptr, out:Ptr<Ptr>):Int;
	static function VTPixelTransferSessionTransferImage(s:Ptr, from:Ptr, to:Ptr):Int;
	static function VTPixelTransferSessionInvalidate(s:Ptr):Void;
	// (macOS 11: VP9 and AV1's decoders are loaded on request)
	static function VTRegisterSupplementalVideoDecoderIfAvailable(codec:Int):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreVideo.framework/CoreVideo") extern class CoreVideo {
	static function CVPixelBufferGetIOSurface(b:Ptr):Ptr;
	static function CVPixelBufferGetPixelFormatType(b:Ptr):Int;
	static function CVPixelBufferGetWidth(b:Ptr):Int64;
	static function CVPixelBufferGetHeight(b:Ptr):Int64;
	static function CVPixelBufferLockBaseAddress(b:Ptr, flags:Int64):Int;
	static function CVPixelBufferUnlockBaseAddress(b:Ptr, flags:Int64):Int;
	static function CVPixelBufferGetBaseAddressOfPlane(b:Ptr, plane:Int64):Ptr;
	static function CVPixelBufferGetBytesPerRowOfPlane(b:Ptr, plane:Int64):Int64;
	static function CVPixelBufferGetHeightOfPlane(b:Ptr, plane:Int64):Int64;
	static function CVPixelBufferGetWidthOfPlane(b:Ptr, plane:Int64):Int64;
	static function CVBufferCopyAttachment(b:Ptr, key:Ptr, mode:Ptr):Ptr;
	static function CVPixelBufferCreate(alloc:Ptr, width:Int64, height:Int64, format:Int, attributes:Ptr, out:Ptr<Ptr>):Int;
	static function CVBufferSetAttachment(b:Ptr, key:Ptr, value:Ptr, mode:Int):Void;
	static function CVBufferRemoveAttachment(b:Ptr, key:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/IOSurface.framework/IOSurface") extern class Surfaces {
	static function IOSurfaceGetID(s:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox") extern class Converter {
	static function AudioConverterNew(from:Ptr, to:Ptr, out:Ptr<Ptr>):Int;
	static function AudioConverterSetProperty(c:Ptr, id:Int, size:Int, data:Ptr):Int;
	static function AudioConverterFillComplexBuffer(c:Ptr, input:Ptr, user:Ptr, packets:Ptr<Int32>, list:Ptr, descs:Ptr):Int;
	static function AudioConverterReset(c:Ptr):Int;
	static function AudioConverterDispose(c:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFRelease(o:Ptr):Void;
	static function CFStringGetCString(s:Ptr, buffer:Ptr, size:Int64, encoding:Int):Bool;
}

// (VideoToolbox's output callback runs on its threads: this, and nothing
// that may collect, there)
@:hxmc.c @:hxmc.fast @:hxmc.lib("/System/Library/Frameworks/CoreVideo.framework/CoreVideo") extern class FastCV {
	static function CVPixelBufferRetain(b:Ptr):Ptr;
}

@:hxmc.struct @:publicFields class CMTime {
	var value:Int64;
	var timescale:Int32;
	var flags:UInt32;
	var epoch:Int64;
}
