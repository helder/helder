package helder.media.ui;

import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import hxmc.Platform;
#if (!helder.os || helder.os == "macos" || helder.os == "ios")
import helder.media.apple.CoreMedia;
import helder.os.objc.*;
import hxmc.unsafe.*;
#end

// A video's frames shown by the system in a layer of its own (VideoNode's,
// in a window of system layers): Apple's AVSampleBufferDisplayLayer in a
// LayerSlot, each frame enqueued as it falls due with its time, the layer's
// control timebase kept at the player's clock (a frame shows once the
// timebase is at its time; stopped, so the clock alone moves it), on the
// main thread (OsThread: posted, the sample buffers made on the program's). Fit is
// the layer's video gravity, the layer clipping to its bounds. make: null
// where the system has none.
@:hxmc.unsafe(gc)
class SampleLayer {
	public final slot:LayerSlot;
	#if (!helder.os || helder.os == "macos" || helder.os == "ios")
	final layer:Ptr;
	final timebase:Ptr;
	#end
	var last:Null<VideoFrame>;
	var at = -1.0;

	public static function make(owner:VideoNode):Null<SampleLayer> {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1) return new SampleLayer();
		#end
		return null;
	}

	function new() {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		Posix.dlopen(Mem.cstr("/System/Library/Frameworks/AVFoundation.framework/AVFoundation"), 2);
		var l = layer = helder.os.OsThread.get(() -> {
			var l = Msg.id(Msg.id(ObjC.cls("AVSampleBufferDisplayLayer"), ObjC.sel("alloc")), ObjC.sel("init"));
			Msg.vBool(l, ObjC.sel("setMasksToBounds:"), true);
			l;
		});
		timebase = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			CoreMedia.CMTimebaseCreateWithSourceClock(Ptr.nil(), CoreMedia.CMClockGetHostTimeClock(), out);
			out.value;
		});
		CoreMedia.CMTimebaseSetRate(timebase, 0);
		var tb = timebase;
		helder.os.OsThread.run(() -> Msg.vPtr(l, ObjC.sel("setControlTimebase:"), tb));
		slot = new LayerSlot(layer);
		#else
		slot = new LayerSlot(hxmc.unsafe.Ptr.nil());
		#end
	}

	public function fit(f:ImageFit) {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var name = switch f {
			case Cover: "AVLayerVideoGravityResizeAspectFill";
			case Fill: "AVLayerVideoGravityResize";
			case _: "AVLayerVideoGravityResizeAspect";
		}, l = layer;
		helder.os.OsThread.post(() -> {
			var g = ObjC.str(name);
			Msg.vPtr(l, ObjC.sel("setVideoGravity:"), g);
			ObjC.release(g);
		});
		#end
	}

	// (each tick: the frame due enqueued once, the timebase at the clock)
	public function feed(p:Player):Null<VideoFrame> {
		var f = p.update();
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (f != null && f != last) {
			last = f;
			enqueue(f);
		}
		var t = p.time;
		if (f != null && t < f.time) t = f.time;
		if (t != at) {
			at = t;
			Arena.scoped(a -> {
				var c = a.make(CMTime);
				c.value.value = (cast haxe.Int64.fromFloat(Math.round(t * 90000)) : Int64);
				c.value.timescale = 90000;
				c.value.flags = 1;
				c.value.epoch = 0;
				CoreMedia.CMTimebaseSetTime(timebase, c.value);
			});
		}
		#end
		return f;
	}

	#if (!helder.os || helder.os == "macos" || helder.os == "ios")
	function enqueue(f:VideoFrame) {
		var image = f.image;
		if (image.isNull()) return;
		var sample = Arena.scopedValue(a -> {
			var fd:Ptr<Ptr> = a.alloc(8), out:Ptr<Ptr> = a.alloc(8);
			if (CoreMedia.CMVideoFormatDescriptionCreateForImageBuffer(Ptr.nil(), image, fd) != 0) return Ptr.nil();
			// (CMSampleTimingInfo: duration and dts invalid, the pts)
			var timing = a.alloc(72);
			LibC.memset(timing, 0, 72);
			Mem.setI64(timing, 24, (cast haxe.Int64.fromFloat(Math.round(f.time * 90000)) : Int64));
			Mem.setI32(timing, 32, 90000);
			Mem.setI32(timing, 36, 1);
			var s = CoreMedia.CMSampleBufferCreateReadyWithImageBuffer(Ptr.nil(), image, fd.value, timing, out);
			CF.CFRelease(fd.value);
			s == 0 ? out.value : Ptr.nil();
		});
		if (sample.isNull()) return;
		var l = layer;
		helder.os.OsThread.post(() -> {
			Msg.vPtr(l, ObjC.sel("enqueueSampleBuffer:"), sample);
			CF.CFRelease(sample);
		});
	}
	#end

	// what it shows dropped (a seek: the frames due from there come)
	public function flush() {
		last = null;
		at = -1;
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer;
		helder.os.OsThread.post(() -> Msg.v(l, ObjC.sel("flush")));
		#end
	}

	// nothing shown (another file)
	public function clear() {
		last = null;
		at = -1;
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer;
		helder.os.OsThread.post(() -> Msg.v(l, ObjC.sel("flushAndRemoveImage")));
		#end
	}

	public function dispose() {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer, tb = timebase;
		helder.os.OsThread.post(() -> {
			Msg.vPtr(l, ObjC.sel("setControlTimebase:"), Ptr.nil());
			Msg.v(l, ObjC.sel("removeFromSuperlayer"));
			ObjC.release(l);
			CF.CFRelease(tb);
		});
		#end
	}
}
