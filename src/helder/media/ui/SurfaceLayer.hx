package helder.media.ui;

#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
import helder.media.android.McVideo;
import helder.os.android.Jni;
import helder.os.android.MainThread;
import helder.os.android.Native;
import helder.ui.ImageFit;
import helder.ui.LayerSlot;
import helder.ui.draw.ScLayers;
import helder.ui.draw.UiWindow;
import hxmc.unsafe.*;

// A video shown by Android's compositor (SampleLayer's on Android, in a
// window of system layers: helder.ui.draw.ScLayers): MediaCodec renders
// straight onto the Surface of a SurfaceControl of its own (a Java one: the
// NDK has no Surface of an ASurfaceControl), whose native handle
// (ASurfaceControl_fromJava, API 34) goes under the node's slot, scaled
// and centred as fit says, cut by the slot's crop. Each frame is released
// to it as it falls due on the player's clock (releaseOutputBufferAtTime:
// System.nanoTime's), so the compositor shows it at the next refresh;
// frames decoded before (images, drawn) are not shown there. null where
// the window has no system layers, before they showed a frame, or where
// Android is older.
@:hxmc.unsafe(gc)
class SurfaceLayer {
	public final slot:LayerSlot;
	public var fit:ImageFit = Contain;

	final owner:VideoNode;
	final layers:ScLayers;
	final java:Ptr;
	final surface:Ptr;
	final window:Ptr;
	final sc:Ptr;
	var decoder:Null<McVideo>;
	var last:Null<VideoFrame>;
	final placed = [-1.0, -1.0, -1.0, -1.0, -1.0];

	public static function make(owner:VideoNode):Null<SurfaceLayer> {
		var p = owner.player, ui = owner.ui;
		if (p == null || p.video == null || ui == null || !Tx.loaded()) return null;
		var layers:Null<ScLayers> = null;
		for (w in @:privateAccess UiWindow.open)
			if (w.ui == ui && w.compositor != null) layers = Std.downcast(w.compositor.layers, ScLayers);
		// (not before the layers showed a frame: a slot in the window's first
		// frames kept them from starting; drawn by helder until then)
		if (layers == null || layers.frames == 0) return null;
		var host = layers.surface();
		if (host.isNull()) return null;
		var w = p.video.width, h = p.video.height, made:Null<Array<Ptr>> = null;
		MainThread.run(() -> made = javaLayer(w, h));
		if (made == null) {
			layers.letGo(host);
			return null;
		}
		return new SurfaceLayer(owner, layers, host, made);
	}

	// (on the main thread: a SurfaceControl of the video's size, a Surface
	// of it, its window and native handle; null where it fails)
	static function javaLayer(w:Int, h:Int):Null<Array<Ptr>> {
		return try {
			var b = Jni.cls("android.view.SurfaceControl$Builder"), sb = "Landroid/view/SurfaceControl$Builder;";
			var builder = Jni.newObject(b, Jni.method(b, "<init>", "()V"));
			var name = Jni.string("helder.video");
			Jni.obj(builder, Jni.method(b, "setName", '(Ljava/lang/String;)$sb'), name.toI64());
			Jni.obj(builder, Jni.method(b, "setBufferSize", '(II)$sb'), w, h);
			var sc = Jni.obj(builder, Jni.method(b, "build", "()Landroid/view/SurfaceControl;"));
			var sf = Jni.cls("android.view.Surface");
			var surface = Jni.newObject(sf, Jni.method(sf, "<init>", "(Landroid/view/SurfaceControl;)V"), sc.toI64());
			var window = Android.ANativeWindow_fromSurface(Jni.env, surface);
			var native = Tx.ASurfaceControl_fromJava(Jni.env, sc);
			if (window.isNull() || native.isNull()) null else [Jni.global(sc), Jni.global(surface), window, native];
		} catch (_:Dynamic) null;
	}

	function new(owner:VideoNode, layers:ScLayers, host:Ptr, made:Array<Ptr>) {
		this.owner = owner;
		this.layers = layers;
		java = made[0];
		surface = made[1];
		window = made[2];
		sc = made[3];
		slot = new LayerSlot(host);
		var t = Tx.ASurfaceTransaction_create();
		Tx.ASurfaceTransaction_reparent(t, sc, host);
		Tx.ASurfaceTransaction_setVisibility(t, sc, 1);
		Tx.ASurfaceTransaction_apply(t);
		Tx.ASurfaceTransaction_delete(t);
	}

	// (each tick: the decoder onto the layer's surface once it has one, the
	// frame due released to it, its geometry the box's)
	public function feed(p:Player):Null<VideoFrame> {
		if (decoder == null) {
			decoder = Std.downcast(@:privateAccess p.vdec, McVideo);
			if (decoder != null) decoder.output(window);
		}
		var f = p.update();
		if (f != null && f != last) {
			last = f;
			if (decoder != null) decoder.render(f, now());
		}
		place(p);
		return f;
	}

	static function now():Float
		return Arena.scopedValue(a -> {
			var ts = a.alloc(16);
			PosixClock.clock_gettime(1, ts);
			Mem.getI64(ts, 0).toInt() * 1e9 + Mem.getI64(ts, 8).toInt();
		});

	// (the picture in the slot's box, in pixels: scaled and centred as fit says)
	function place(p:Player) {
		var v = p.video, u = owner.ui;
		if (v == null || u == null || v.width == 0 || v.height == 0) return;
		var bw = owner.box[0] * u.scale, bh = owner.box[1] * u.scale;
		var kx = bw / v.width, ky = bh / v.height;
		switch fit {
			case Contain: kx = ky = Math.min(kx, ky);
			case Cover: kx = ky = Math.max(kx, ky);
			case _:
		}
		var x = Math.round((bw - v.width * kx) / 2), y = Math.round((bh - v.height * ky) / 2);
		if (placed[0] == x && placed[1] == y && placed[2] == kx && placed[3] == ky) return;
		placed[0] = x;
		placed[1] = y;
		placed[2] = kx;
		placed[3] = ky;
		var t = Tx.ASurfaceTransaction_create();
		Tx.ASurfaceTransaction_setPosition(t, sc, x, y);
		Tx.ASurfaceTransaction_setScale(t, sc, kx, ky);
		Tx.ASurfaceTransaction_apply(t);
		Tx.ASurfaceTransaction_delete(t);
	}

	// (the decoder back onto its images, the layer out of the slot; the
	// slot let go a second later, once ScLayers' transaction no longer names it)
	public function dispose() {
		var p = owner.player;
		if (decoder != null && p != null && @:privateAccess p.vdec == decoder) decoder.output(Ptr.nil());
		decoder = null;
		var t = Tx.ASurfaceTransaction_create();
		Tx.ASurfaceTransaction_reparent(t, sc, Ptr.nil());
		Tx.ASurfaceTransaction_apply(t);
		Tx.ASurfaceTransaction_delete(t);
		Tx.ASurfaceControl_release(sc);
		Android.ANativeWindow_release(window);
		var j = java, s = surface, l = layers, host = slot.handle;
		MainThread.post(() -> {
			Jni.call(s, Jni.method(Jni.cls("android.view.Surface"), "release", "()V"));
			Jni.call(j, Jni.method(Jni.cls("android.view.SurfaceControl"), "release", "()V"));
			Jni.deleteGlobal(s);
			Jni.deleteGlobal(j);
		});
		helder.ui.Clock.after(1, () -> l.letGo(host));
	}
}

// (libandroid's transactions, API 29 and 31's, and ASurfaceControl_fromJava, 34's)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
private class Tx {
	static function ASurfaceControl_fromJava(env:Ptr, sc:Ptr):Ptr;
	static function ASurfaceControl_release(sc:Ptr):Void;
	static function ASurfaceTransaction_create():Ptr;
	static function ASurfaceTransaction_delete(t:Ptr):Void;
	static function ASurfaceTransaction_apply(t:Ptr):Void;
	static function ASurfaceTransaction_reparent(t:Ptr, sc:Ptr, parent:Ptr):Void;
	static function ASurfaceTransaction_setVisibility(t:Ptr, sc:Ptr, on:Int):Void;
	static function ASurfaceTransaction_setPosition(t:Ptr, sc:Ptr, x:Int, y:Int):Void;
	static function ASurfaceTransaction_setScale(t:Ptr, sc:Ptr, x:Float32, y:Float32):Void;

	static var tried = false;
	static var ok = false;

	public static function loaded():Bool {
		if (!tried) {
			tried = true;
			ok = load("libandroid.so") == null;
		}
		return ok;
	}
}
#end
