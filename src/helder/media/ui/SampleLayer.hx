package helder.media.ui;

import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import hxmc.Platform;
#if (!helder.os || helder.os == "macos" || helder.os == "ios")
import helder.media.apple.CoreMedia;
import helder.os.apple.objc.*;
import hxmc.unsafe.*;
#end

// A video's frames shown by the system in a layer of its own (VideoNode's,
// in a window of system layers): Apple's AVSampleBufferDisplayLayer in a
// LayerSlot, each frame enqueued as it falls due with its time, the layer's
// control timebase kept at the player's clock (a frame shows once the
// timebase is at its time; stopped, so the clock alone moves it), on the
// main thread (OsThread: posted, the sample buffers made on the program's). Fit is
// the layer's video gravity, the layer clipping to its bounds. On Android
// a SurfaceLayer (MediaCodec onto a SurfaceControl in the slot), on Windows
// a WinLayer (a DirectComposition surface in the slot's visual), in a
// browser a WebSample (a canvas of the page). make: null where the system
// has none.
@:hxmc.unsafe(gc)
class SampleLayer {
	public final slot:LayerSlot;
	#if (!helder.os || helder.os == "macos" || helder.os == "ios")
	final layer:Ptr;
	final timebase:Ptr;
	#end
	var last:Null<VideoFrame>;
	var at = -1.0;
	#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
	var android:Null<SurfaceLayer>;
	#end
	#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
	var windows:Null<WinLayer>;
	#end
	#if (hxmc.target == "wasm32-wasi")
	var web:Null<WebSample>;
	#end

	public static function make(owner:VideoNode):Null<SampleLayer> {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (Platform.os() == 1) return new SampleLayer();
		#end
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (Platform.target() >= 9) {
			var s = SurfaceLayer.make(owner);
			if (s == null) return null;
			var l = new SampleLayer(s.slot);
			l.android = s;
			return l;
		}
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
		if (Platform.os() == 2) {
			var w = WinLayer.make(owner);
			if (w == null) return null;
			var l = new SampleLayer(w.slot);
			l.windows = w;
			return l;
		}
		#end
		#if (hxmc.target == "wasm32-wasi")
		var s = WebSample.make(owner);
		if (s == null) return null;
		var l = new SampleLayer(s.slot);
		l.web = s;
		return l;
		#else
		return null;
		#end
	}

	function new(?slot:LayerSlot) {
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (slot != null) {
			this.slot = slot;
			layer = timebase = Ptr.nil();
			return;
		}
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
		this.slot = new LayerSlot(layer);
		#else
		this.slot = slot ?? new LayerSlot(hxmc.unsafe.Ptr.nil());
		#end
	}

	public function fit(f:ImageFit) {
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (android != null) android.fit = f;
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
		if (windows != null) windows.fit = f;
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) web.fit(f);
		#end
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

	// whether it shows the frames (Android's once one was rendered onto it;
	// until then the node draws them)
	public var showing(get, never):Bool;

	function get_showing():Bool {
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (android != null) return android.showing;
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
		if (windows != null) return windows.showing;
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) return web.showing;
		#end
		return true;
	}

	// (each tick: the frame due enqueued once, the timebase at the clock)
	public function feed(p:Player):Null<VideoFrame> {
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (android != null) return android.feed(p);
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
		if (windows != null) return windows.feed(p);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) return web.feed(p);
		#end
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
		tag(f);
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

	#if (!helder.os || helder.os == "macos" || helder.os == "ios")
	// (the colours the system converts the frame with, as helder's pass
	// does: the frame's matrix, its values shown as sRGB's, so BT.709's
	// primaries and sRGB's transfer, no gamut or HDR conversion; VideoToolbox
	// tags what the stream says, often nothing, and the system's own guess
	// was 16 levels off helder's over a frame, CI's window captures)
	function tag(f:VideoFrame) {
		var b = f.image;
		var matrix = f.matrix == "709" ? "ITU_R_709_2" : f.matrix == "2020" ? "ITU_R_2020" : "ITU_R_601_4";
		for (kv in [["CVImageBufferYCbCrMatrix", matrix], ["CVImageBufferColorPrimaries", "ITU_R_709_2"], ["CVImageBufferTransferFunction", "IEC_sRGB"]]) {
			var k = ObjC.str(kv[0]), v = ObjC.str(kv[1]);
			// (kCVAttachmentMode_ShouldPropagate)
			CoreVideo.CVBufferSetAttachment(b, k, v, 1);
			ObjC.release(k);
			ObjC.release(v);
		}
		for (key in ["CVImageBufferGammaLevel", "CVImageBufferICCProfile"]) {
			var k = ObjC.str(key);
			CoreVideo.CVBufferRemoveAttachment(b, k);
			ObjC.release(k);
		}
	}
	#end

	// what it shows dropped (a seek: the frames due from there come)
	public function flush() {
		last = null;
		at = -1;
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer;
		if (!l.isNull()) helder.os.OsThread.post(() -> Msg.v(l, ObjC.sel("flush")));
		#end
	}

	// nothing shown (another file)
	public function clear() {
		last = null;
		at = -1;
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) web.clear();
		#end
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer;
		if (!l.isNull()) helder.os.OsThread.post(() -> Msg.v(l, ObjC.sel("flushAndRemoveImage")));
		#end
	}

	// (its layer out of the tree by apple.Layers, in a transaction after the
	// frame that no longer has the slot, which still names it: let go of a
	// second later, not before)
	public function dispose() {
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (android != null) {
			android.dispose();
			return;
		}
		#end
		#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi" && !helder.soft)
		if (windows != null) {
			windows.dispose();
			return;
		}
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) web.dispose();
		#end
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		var l = layer, tb = timebase;
		helder.os.OsThread.post(() -> Msg.v(l, ObjC.sel("flushAndRemoveImage")));
		helder.ui.Clock.after(1, () -> helder.os.OsThread.post(() -> {
			Msg.vPtr(l, ObjC.sel("setControlTimebase:"), Ptr.nil());
			ObjC.release(l);
			CF.CFRelease(tb);
		}));
		#end
	}
}
