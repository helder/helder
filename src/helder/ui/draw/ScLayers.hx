package helder.ui.draw;

#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
import helder.gfx.*;
import helder.gfx.egl.Egl;
import helder.gfx.gl.GLBackend;
import helder.os.android.Jni;
import helder.os.android.MainThread;
import helder.os.android.Native;
import hxmc.unsafe.*;

// The system's compositor on Android (Layers' step 5): a window's layers
// handed to SurfaceFlinger as SurfaceControls (the NDK's ASurfaceControl
// and ASurfaceTransaction), split as LayerSplit splits them. The window's
// own surface has no handle for ASurfaceControl_createFromWindow (a
// view's root's is made without one), so a SurfaceControl of Java's is
// put under the window (AttachedSurfaceControl's reparent, API 33: made on
// the main thread before the program's frame, prepare) and the native
// tree goes under a Surface of it: a stack, the window's
// layer, each unit's (a scroller's content inside a clip of its own, a
// layer of no buffer cropped to the scroller's clip; a mover), each node's
// system layer (LayerSlot: a SurfaceControl, reparented into its clip),
// what is over each. Each has buffers of its own (AHardwareBuffers, two,
// three for a small one, drawn by GLES through an EGLImage and fenced, not finished),
// drawn again only where its quads, its size or what they sample changed,
// and then only its rectangles that changed since that buffer was drawn
// (LayerPlane.cut: buffer age; told the system, setDamageRegion):
// a scroll moves its content's layer and a mover's translation, scale and
// opacity are its layer's (setPosition, setScale, setBufferAlpha), so
// neither draws. A frame that changes anything is one transaction, its
// buffers in it, and the next waits until that one was presented
// (setOnComplete: one in flight, the display's pace, the replaced buffers'
// release fences); one that changes nothing sends none. A frame split into
// the window's layer alone (a scene over the window: single) is drawn onto
// the window as before, the stack hidden once that frame is queued (in
// order with it: one process's transactions apply in order). The NDK has
// no rounded clip (a corner radius is not its API), no turn and no
// fraction of a pixel: rounded scrollers and movers that turn, skew or
// flip stay drawn (rounds, unfit), and layers sit on whole pixels (a
// scroller resting at a fraction of one is half a pixel at most from where
// the textured compositor replays it). It needs API 33 (the reparent;
// setPosition, setCrop, setScale are 31's: looked up, never linked) and
// falls back to the textured compositor where that, a buffer or an EGL
// extension is missing or a call fails; while running, where the system
// misbehaves (stalled, released), its next frame drawn onto the window. HELDER_SYSTEM_LAYERS=0 keeps the textured compositor;
// frames read back never use these.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.Node)
class ScLayers extends LayerSplit {
	public static function wanted(device:Device):Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && device.surface.kind == Android && Sc.load();

	public static function make(device:Device):ScLayers
		return new ScLayers(device);

	final device:Device;
	// (the program's: the window ours is under, ours; under the lock, its
	// Surface's ANativeWindow, the render thread's parent)
	var javaFor = Ptr.nil();
	var java:Null<JavaRoot> = null;
	var host = Ptr.nil();
	// (the window the root was made on, the root, the stack of layers over it)
	var window = Ptr.nil();
	var root = Ptr.nil();
	var stack = Ptr.nil();
	var stackShown = false;
	// (the stack to hide once the window's own frame is queued: single, a frame read back)
	var hide = false;
	// (the frame's transaction; transactions applied, the last presented)
	@:allow(helder.ui.draw.ScPlane) var tx = Ptr.nil();
	var sent = 0;
	final scratch:Ptr;
	final commands = new Commands();
	var ring = 0;
	// (the display's period: how long a transaction may take to be presented)
	@:allow(helder.ui.draw.ScPlane) var period = 1 / 60;
	// (off for good: a buffer or a call failed; buffers taken back unreleased in a row)
	var broken = false;
	@:allow(helder.ui.draw.ScPlane) var gl:Null<GLBackend> = null;

	function new(device:Device) {
		super(new ScPlane(LayerPlane.BASE, null));
		this.device = device;
		(cast base : ScPlane).owner = this;
		scratch = LibC.malloc(64);
		rounds = false;
		// (the window gone (the program's thread): ours made again on the
		// next, whose ANativeWindow may be at the same address)
		var lost = device.surface.lost;
		device.surface.lost = () -> {
			javaFor = Ptr.nil();
			if (lost != null) lost();
		}
	}

	override function plane(kind:Int, key:Dynamic):LayerPlane {
		var p = new ScPlane(kind, key);
		p.owner = this;
		return p;
	}

	override public function quiet(r:Replay, on:Bool)
		(cast r.impl : GLBackend).quiet = on;

	// (each buffer kept)
	override public function bytes():Float {
		var b = 0.0;
		for (p in all())
			b += (cast p : ScPlane).memory();
		return b;
	}

	function all():Array<LayerPlane>
		return [base].concat([for (p in kept) p]).concat([for (p in overs) p]);

	override public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null || broken) return;
		var began = haxe.Timer.stamp();
		gl = cast r.impl;
		if (!attach()) return;
		compose(f, now, t, shown, drawn);
		// (a mover that turns, skews or flips: drawn from now, split again)
		if (turned(f)) compose(f, now, t, shown, drawn);
		released();
		tx = Sc.create();
		var changes = 0, b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0, toDraw:Array<ScPlane> = [];
		if (!stackShown) {
			stackShown = true;
			Sc.visible(tx, stack, true);
			changes++;
		}
		for (q in order) {
			if (q == null) continue;
			var p:ScPlane = cast q;
			if (p.kind == LayerPlane.SLOT) {
				if (p.makeSlot()) changes++;
				continue;
			}
			if (p.kind == LayerPlane.BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != LayerPlane.BASE) {
				if (p.show(false)) changes++;
				continue;
			}
			if (p.make()) changes++;
			if (p.show(true)) changes++;
			for (s in p.slots)
				if ((cast s : ScPlane).makeSlot()) changes++;
			if (p.local(out, quadTextures, fresh)) toDraw.push(p);
		}
		changes += geometry(f, now);
		// (Android's views are their own windows: moved as they were, on the main thread)
		for (m in moves)
			m();
		for (g in gone)
			g();
		changes += gone.length;
		gone.resize(0);
		for (p in toDraw) {
			var buf = p.next(), t0 = haxe.Timer.stamp();
			// (only what it misses of what changed since it was drawn: its buffer age)
			var cut = buf != null && p.cut(buf.at, p.kind == LayerPlane.BASE ? f.background | 0xFF000000 : 0);
			var len = cut ? p.cutLen : p.len;
			// (no buffer let go in time: drawn next frame, what it missed in its history still)
			if (buf == null && p.allocated) {
				p.retry();
				continue;
			}
			if (buf == null || at + len > f.capacity || !draw(r, f, buf.texture, p, b, at, cut)) {
				p.invalidate();
				if (!p.allocated) fail("no buffer");
				continue;
			}
			timing[1] += haxe.Timer.stamp() - t0;
			at += len;
			drawnTotal++;
			quadsTotal += cut ? Std.int(p.cutLen / CompositeFrame.STRIDE) - p.clears : p.quads.length;
			if (cut) cutTotal++;
			pixelsTotal += cut ? p.cutArea() : p.pw * p.ph;
			buf.at = p.serial;
			p.queue(buf, gl.fence(), sent + 1);
			changes++;
		}
		if (changes > 0) {
			// (one in flight: the last one presented first, or long enough)
			var until = haxe.Timer.stamp() + period * 2;
			var t0 = haxe.Timer.stamp();
			while (Sc.presented() < sent && haxe.Timer.stamp() < until)
				Sys.sleep(0.0005);
			timing[3] += haxe.Timer.stamp() - t0;
			stalled();
			Sc.apply(tx, ++sent);
		}
		Sc.delete(tx);
		tx = Ptr.nil();
		frames++;
		timing[0] += haxe.Timer.stamp() - began;
		if (single) suspend();
	}

	// (seconds on the render thread in all: showing, drawing, waiting for a
	// buffer, waiting for the last transaction's presentation: tests)
	@:noCompletion public final timing = [0.0, 0.0, 0.0, 0.0];

	// (ours under the window the surface has now, on the main thread: none
	// where this Android has no reparent, the layers off then)
	override public function prepare() {
		var w = device.surface.handle;
		if (w == javaFor || w.isNull() && java == null || broken) return;
		javaFor = w;
		var old = java, made:Null<JavaRoot> = null;
		java = null;
		MainThread.run(() -> {
			if (old != null) old.release();
			if (!w.isNull()) made = JavaRoot.make();
		});
		java = made;
		// (a window whose own surface never had a buffer is not drawn to Android: no input reaches it)
		priming = true;
		lock.acquire();
		host = made == null ? Ptr.nil() : made.window;
		lock.release();
		if (!w.isNull() && made == null) fail("no SurfaceControl under the window (API 33's reparent)");
	}

	// a SurfaceControl for a node's LayerSlot (a video's: its owner sets its
	// buffers), under ours, hidden until a frame places it (uncropped, a
	// layer of one colour would fill the window); nil before the first frame
	// or where there are no system layers (the program's thread)
	public function surface():Ptr {
		prepare();
		lock.acquire();
		var h = host;
		lock.release();
		if (h.isNull() || broken) return Ptr.nil();
		var l = Sc.fromWindow(h);
		if (l.isNull()) return l;
		var t = Sc.create();
		Sc.visible(t, l, false);
		Sc.apply(t, -1);
		Sc.delete(t);
		lock.acquire();
		surfaces.push(l);
		lock.release();
		return l;
	}

	// (what surface() made: hidden with the layers when they turn off)
	final surfaces:Array<Ptr> = [];

	// a surface() its node no longer has let go (once no transaction of
	// ours names it: a frame after the node lost it)
	public function letGo(l:Ptr) {
		lock.acquire();
		var had = surfaces.remove(l);
		lock.release();
		if (had) Sc.release(l);
	}

	// (a surface() of one colour, 0xRRGGBB: tests)
	@:noCompletion public function solid(rgb:Int):Ptr {
		var l = surface();
		if (l.isNull()) return l;
		var t = Sc.create();
		Sc.color(t, l, (rgb >> 16 & 0xFF) / 255, (rgb >> 8 & 0xFF) / 255, (rgb & 0xFF) / 255);
		Sc.apply(t, -1);
		Sc.delete(t);
		return l;
	}

	// (the root and its stack under ours there is now: made again on a
	// new one, everything made on the last let go; false: none now)
	function attach():Bool {
		lock.acquire();
		var w = host;
		lock.release();
		if (w != window) {
			lose();
			window = w;
			if (w.isNull()) return false;
			root = Sc.fromWindow(w);
			if (root.isNull()) {
				fail("no SurfaceControl of ours");
				return false;
			}
			stack = Sc.child(root);
			stackShown = false;
		}
		return !w.isNull() && !stack.isNull();
	}

	// (the layers made on a window gone let go: each made again on the next)
	function lose() {
		var t = Sc.create();
		for (p in all())
			(cast p : ScPlane).lose(t);
		if (!stack.isNull()) Sc.reparent(t, stack, Ptr.nil());
		Sc.apply(t, -1);
		Sc.delete(t);
		if (!stack.isNull()) Sc.release(stack);
		if (!root.isNull()) Sc.release(root);
		stack = root = Ptr.nil();
	}

	// (off for good, the textured compositor's from the next frame, which
	// the program is asked for: what is on the layers may never have shown)
	function fail(why:String) {
		if (broken) return;
		broken = true;
		off = true;
		single = true;
		fell = why;
		redraw = true;
		Sys.println("helder.ui: system layers off: " + why);
		hide = true;
	}

	// (a system whose transactions are never reported presented (a driver's
	// fences that never signal, a compositor that drops the callbacks)
	// shows nothing of them, or shows them late: off once none was for
	// STALL seconds while some were waiting)
	function stalled() {
		var p = Sc.presented(), t = haxe.Timer.stamp();
		if (p != seen || p >= sent) {
			seen = p;
			progress = t;
		} else if (t - progress > STALL) fail('no transaction presented in $STALL s');
	}

	var seen = 0;
	var progress = 0.0;

	static inline var STALL = 1.5;

	// (a unit's mover whose transform is not a translation and a scale:
	// SurfaceControl has neither turns nor flips; its layer drawn as the
	// rest is from now: whether f is split again)
	function turned(f:CompositeFrame):Bool {
		var any = false, m = f.heldMoved;
		for (u in units)
			if (u.kind == LayerPlane.MOVER) {
				var q = u.index * 7;
				if (Math.abs(m[q + 1]) > 1e-6 || Math.abs(m[q + 2]) > 1e-6 || !(m[q] > 0) || !(m[q + 3] > 0)) {
					unfit.set(u.key, true);
					any = true;
				}
			}
		if (any) split = -1;
		return any;
	}

	// (the release fences of the transactions presented since: each buffer they replaced free once its fence is)
	function released() {
		var planes = all();
		Sc.drain((sc, seq, fd) -> {
			for (p in planes)
				if ((cast p : ScPlane).sc == sc) {
					(cast p : ScPlane).release(seq, fd);
					return;
				}
			if (fd >= 0) Posix.close(fd);
		});
	}

	// (where the layers go now, in pixels: a scroller's content by its
	// offset, a mover's by its transform and opacity sampled, a system layer
	// by its scroller's and its mover's; their order: the changes)
	function geometry(f:CompositeFrame, now:Array<Float>):Int {
		var s = f.scale, n = 0;
		for (q in units) {
			var u:ScPlane = cast q;
			if (u.kind == LayerPlane.SLOT) {
				n += slotAt(f, u, null, now);
				continue;
			}
			if (u.quads.length == 0) continue;
			if (u.kind == LayerPlane.SCROLL) {
				var k = u.index, dx = (f.offsets[2 * k] - now[2 * k]) * s, dy = (f.offsets[2 * k + 1] - now[2 * k + 1]) * s;
				n += u.clipTo(u.cx0, u.cy0, u.cx1 - u.cx0, u.cy1 - u.cy0);
				n += u.move(u.ox - u.cx0 + dx, u.oy - u.cy0 + dy, 1, 1, 1);
				for (sp in u.slots)
					n += slotAt(f, cast sp, u, now);
			} else {
				var m = f.heldMoved, k = u.index * 7, a = m[k], b = m[k + 1], c = m[k + 2], d = m[k + 3];
				n += u.move(a * u.ox + c * u.oy + m[k + 4], b * u.ox + d * u.oy + m[k + 5], a, d, m[k + 6]);
			}
		}
		for (q in order)
			if (q != null && q.kind == LayerPlane.OVER && q.quads.length > 0) n += (cast q : ScPlane).move(q.ox, q.oy, 1, 1, 1);
		// (the order: the stack's children, a scroller's clip's inside it)
		var z = 0;
		for (q in order) {
			var p:ScPlane = cast q;
			if (p == null || !p.made()) continue;
			n += p.stackAt(z++);
			var inner = 1;
			for (sp in p.slots)
				n += (cast sp : ScPlane).stackAt(inner++);
		}
		return n;
	}

	// (system layer p where it is now: at its box as drawn, moved by its
	// scroller's offsets and its mover's change as sampled, cut to its clip
	// (its scroller's, in: the unit it is in, its clip that one's); square:
	// SurfaceControl has no rounded clip)
	function slotAt(f:CompositeFrame, p:ScPlane, in_:Null<ScPlane>, now:Array<Float>):Int {
		var d = f.slotData, o = p.index * CompositeFrame.SLOT, s = f.scale;
		var fr = Std.int(d[o + 2]), c = Std.int(d[o + 3]), m = Std.int(d[o + 4]);
		var ax = d[o + 6], ay = d[o + 7], bx = d[o + 8], by = d[o + 9], qx = d[o + 10], qy = d[o + 11], alpha = 1.0;
		if (m >= 0) {
			var mv = f.moved, k = m * 7;
			var nax = mv[k] * ax + mv[k + 2] * ay + mv[k + 4], nay = mv[k + 1] * ax + mv[k + 3] * ay + mv[k + 5];
			var nbx = mv[k] * bx + mv[k + 2] * by + mv[k + 4], nqy = mv[k + 1] * qx + mv[k + 3] * qy + mv[k + 5];
			ax = nax;
			ay = nay;
			bx = nbx;
			qy = nqy;
			alpha = mv[k + 6];
		}
		var dx = fr >= 0 ? Math.fround(f.shift(fr, now, true) * s) : 0.0, dy = fr >= 0 ? Math.fround(f.shift(fr, now, false) * s) : 0.0;
		var cx0 = p.cx0, cy0 = p.cy0, cx1 = p.cx1, cy1 = p.cy1;
		if (in_ == null && c >= 0) {
			var ex = Math.fround(f.shift(c, now, true) * s), ey = Math.fround(f.shift(c, now, false) * s);
			cx0 += ex;
			cy0 += ey;
			cx1 += ex;
			cy1 += ey;
		}
		cx0 = Math.max(cx0, 0);
		cy0 = Math.max(cy0, 0);
		cx1 = Math.min(cx1, f.width);
		cy1 = Math.min(cy1, f.height);
		var w = bx - ax, h = qy - ay;
		if (!(w > 0) || !(h > 0) || !LayerPlane.fine(w) || !LayerPlane.fine(h)) return 0;
		var n = 0, x = ax + dx, y = ay + dy;
		if (in_ == null) {
			n += p.clipTo(cx0, cy0, Math.max(0, cx1 - cx0), Math.max(0, cy1 - cy0));
			x -= cx0;
			y -= cy0;
		} else {
			x -= in_.cx0;
			y -= in_.cy0;
		}
		return n + p.placeSlot(x, y, w, h, alpha);
	}

	// layers drawn in part, and the pixels drawn in all (tests)
	@:noCompletion public var cutTotal(default, null) = 0;
	@:noCompletion public var pixelsTotal(default, null) = 0.0;

	// (quads drawn into texture, a layer's buffer, at buffer b's offset at:
	// all of them over it cleared; cut, only its rectangles that changed,
	// cleared without blending, then what meets them, the rest as it was)
	function draw(r:Replay, f:CompositeFrame, texture:Int, p:ScPlane, b:Buffer, at:Int, cut:Bool):Bool {
		var c = commands, gl = this.gl;
		gl.frameInto(texture);
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		if (!r.began) {
			gl.frameInto(0);
			return false;
		}
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(at);
		if (cut) c.bytes(p.cutBytes, 0, p.cutLen) else c.bytes(p.bytes, 0, p.len);
		c.end();
		var bg = f.background, opaque = p.kind == LayerPlane.BASE;
		c.begin(Replay.BEGIN_PASS);
		c.int(1);
		c.int(cast(cut ? LoadOp.Load : LoadOp.Clear));
		c.float(opaque ? (bg >> 16 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg >> 8 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg & 0xFF) / 255 : 0);
		c.float(opaque ? 1 : 0);
		c.int(0);
		c.int(0);
		c.int(Replay.NONE);
		c.int(0);
		c.end();
		three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
		three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
		three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
		var k = 0, runs = cut ? p.cutRuns : p.runs, textures = cut ? p.cutTextures : p.runTextures, from = at;
		if (cut) {
			three(Replay.SET_PIPELINE, f.clearPipeline.id(), -1, -1, 1);
			three(Replay.SET_TEXTURE, f.imageSlot, f.blank.id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(p.clears);
			c.int(0);
			c.int(0);
			c.end();
			from += p.clears * CompositeFrame.STRIDE;
		}
		three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
		while (k < runs.length) {
			var t = textures[k >> 1];
			three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), from + runs[k] * CompositeFrame.STRIDE, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(runs[k + 1]);
			c.int(0);
			c.int(0);
			c.end();
			k += 2;
		}
		c.begin(Replay.END_PASS);
		c.end();
		c.begin(Replay.END_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		gl.frameInto(0);
		return true;
	}

	inline function three(op:Int, a:Int, b:Int, d:Int, n:Int) {
		var c = commands;
		c.begin(op);
		c.int(a);
		if (n > 1) c.int(b);
		if (n > 2) c.int(d);
		c.end();
	}

	// (the stack hidden once the window's own frame is queued: windowShown)
	override public function suspend() {
		hide = true;
		base.reset();
	}

	override public function windowShown() {
		priming = false;
		redraw = false;
		if (!hide || stack.isNull()) return;
		hide = false;
		var t = Sc.create();
		if (stackShown) Sc.visible(t, stack, false);
		stackShown = false;
		// (off for good: the nodes' layers too, which are not under the stack until placed)
		if (broken) {
			lock.acquire();
			var all = surfaces.copy();
			lock.release();
			for (l in all)
				Sc.visible(t, l, false);
			Sys.println("helder.ui: system layers off: the window's own frame shown, the layers hidden");
		}
		Sc.apply(t, -1);
		Sc.delete(t);
	}

	override public function dispose() {
		for (p in all())
			(cast p : ScPlane).dispose();
		kept.clear();
		overs.clear();
		lose();
		window = Ptr.nil();
		LibC.free(scratch);
		var j = java;
		java = null;
		if (j != null) MainThread.post(j.release);
	}
}

// (the main thread's: a SurfaceControl of Java's under the activity's
// window, shown above its own surface; a Surface of it, whose ANativeWindow
// has the handle ASurfaceControl_createFromWindow needs)
@:hxmc.unsafe(gc)
private class JavaRoot {
	final sc:Ptr;
	final surface:Ptr;
	public final window:Ptr;

	function new(sc:Ptr, surface:Ptr, window:Ptr) {
		this.sc = sc;
		this.surface = surface;
		this.window = window;
	}

	// (null: no window's root yet, or an Android before 33)
	public static function make():Null<JavaRoot> {
		return try {
			var b = Jni.cls("android.view.SurfaceControl$Builder"), scc = Jni.cls("android.view.SurfaceControl"),
				txc = Jni.cls("android.view.SurfaceControl$Transaction");
			var builder = Jni.newObject(b, Jni.method(b, "<init>", "()V"));
			var name = Jni.string("helder");
			Jni.obj(builder, Jni.method(b, "setName", "(Ljava/lang/String;)Landroid/view/SurfaceControl$Builder;"), name.toI64());
			var sc = Jni.obj(builder, Jni.method(b, "build", "()Landroid/view/SurfaceControl;"));
			var win = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"));
			var root = Jni.obj(win, Jni.method(Jni.cls("android.view.Window"), "getRootSurfaceControl", "()Landroid/view/AttachedSurfaceControl;"));
			if (root.isNull()) return null;
			var t = Jni.obj(root, Jni.method(Jni.cls("android.view.AttachedSurfaceControl"), "buildReparentTransaction",
				"(Landroid/view/SurfaceControl;)Landroid/view/SurfaceControl$Transaction;"), sc.toI64());
			if (t.isNull()) return null;
			Jni.obj(t, Jni.method(txc, "setVisibility", "(Landroid/view/SurfaceControl;Z)Landroid/view/SurfaceControl$Transaction;"), sc.toI64(), 1);
			Jni.call(t, Jni.method(txc, "apply", "()V"));
			var sf = Jni.cls("android.view.Surface");
			var surface = Jni.newObject(sf, Jni.method(sf, "<init>", "(Landroid/view/SurfaceControl;)V"), sc.toI64());
			var w = Android.ANativeWindow_fromSurface(Jni.env, surface);
			if (w.isNull()) return null;
			new JavaRoot(Jni.global(sc), Jni.global(surface), w);
		} catch (e:Dynamic) {
			Sys.println("helder.ui: no system layers: " + Std.string(e));
			null;
		}
	}

	public function release() {
		Android.ANativeWindow_release(window);
		Jni.call(surface, Jni.method(Jni.cls("android.view.Surface"), "release", "()V"));
		Jni.call(sc, Jni.method(Jni.cls("android.view.SurfaceControl"), "release", "()V"));
		Jni.deleteGlobal(surface);
		Jni.deleteGlobal(sc);
	}
}

// (a layer as SurfaceFlinger's: its SurfaceControl, a scroller's or a
// system layer's clip (a parent of no buffer, cropped); its buffers, the
// one shown, those queued in transactions not yet presented; what was set)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.ScLayers)
private class ScPlane extends LayerPlane {
	public var owner:ScLayers;
	public var sc = Ptr.nil();
	public var clip = Ptr.nil();
	final buffers:Array<ScBuffer> = [];
	var bufW = 0;
	var bufH = 0;
	var shownBuffer:Null<ScBuffer> = null;
	// (per transaction a buffer was set in: its number, the buffer it replaced)
	final queued:Array<{seq:Int, was:Null<ScBuffer>}> = [];
	var hidden = true;
	var parented = Ptr.nil();
	final set:Array<Float> = [for (_ in 0...12) -1e300];

	public function made():Bool
		return !sc.isNull() || !clip.isNull();

	// (what goes in the stack: a clip, else the layer)
	function top():Ptr
		return clip.isNull() ? (kind == LayerPlane.SLOT ? slot.handle : sc) : clip;

	// (its layer, and a scroller's clip, made the first time: whether made now)
	public function make():Bool {
		if (!sc.isNull()) return false;
		var o = owner;
		if (kind == LayerPlane.SCROLL) clip = Sc.child(o.stack);
		sc = Sc.child(clip.isNull() ? o.stack : clip);
		Sc.opaque(o.tx, sc, kind == LayerPlane.BASE);
		hidden = false;
		return true;
	}

	// (a system layer in its clip: a clip of its own made the first time, or
	// its scroller's; the node's layer moved into it)
	public function makeSlot():Bool {
		var o = owner, n = false, into = clip;
		if (attached >= 0) {
			var u:ScPlane = cast o.units[attached];
			into = u.clip;
		} else if (clip.isNull()) {
			into = clip = Sc.child(o.stack);
			n = true;
		}
		if (into.isNull() || parented == into) return n;
		parented = into;
		Sc.reparent(o.tx, slot.handle, into);
		Sc.visible(o.tx, slot.handle, slot.shown);
		return true;
	}

	public function show(on:Bool):Bool {
		if (kind == LayerPlane.BASE || hidden == !on || sc.isNull()) {
			hidden = !on;
			return false;
		}
		hidden = !on;
		Sc.visible(owner.tx, top(), on);
		return true;
	}

	// (its place among its parent's children)
	public function stackAt(z:Int):Int {
		if (set[11] == z) return 0;
		set[11] = z;
		Sc.order(owner.tx, top(), z);
		return 1;
	}

	// (its clip at x, y, w x h pixels)
	public function clipTo(x:Float, y:Float, w:Float, h:Float):Int {
		var x = Math.round(x), y = Math.round(y), w = Math.round(w), h = Math.round(h);
		if (set[6] == x && set[7] == y && set[8] == w && set[9] == h) return 0;
		set[6] = x;
		set[7] = y;
		set[8] = w;
		set[9] = h;
		var t = owner.tx;
		Sc.position(t, clip, x, y);
		Sc.crop(t, clip, owner.scratch, 0, 0, w, h);
		return 1;
	}

	// (the layer at x, y pixels (whole ones: SurfaceControl's), scaled by
	// sx, sy and of opacity alpha)
	public function move(x:Float, y:Float, sx:Float, sy:Float, alpha:Float):Int {
		if (!LayerPlane.fine(x) || !LayerPlane.fine(y)) return 0;
		var x = Math.round(x), y = Math.round(y), n = 0, t = owner.tx;
		if (set[0] != x || set[1] != y) {
			set[0] = x;
			set[1] = y;
			Sc.position(t, sc, x, y);
			n++;
		}
		if ((set[2] != sx || set[3] != sy) && LayerPlane.fine(sx) && LayerPlane.fine(sy)) {
			set[2] = sx;
			set[3] = sy;
			Sc.scale(t, sc, sx, sy);
			n++;
		}
		if (set[4] != alpha && LayerPlane.fine(alpha)) {
			set[4] = alpha;
			Sc.alpha(t, sc, alpha);
			n++;
		}
		return n;
	}

	// (a system layer at x, y in its clip, cut to w x h: its buffer at its own size)
	public function placeSlot(x:Float, y:Float, w:Float, h:Float, alpha:Float):Int {
		var x = Math.round(x), y = Math.round(y), w = Math.round(w), h = Math.round(h), on = slot.shown ? 1 : 0, l = slot.handle, t = owner.tx;
		if (set[0] == x && set[1] == y && set[2] == w && set[3] == h && set[4] == alpha && set[5] == on) return 0;
		set[0] = x;
		set[1] = y;
		set[2] = w;
		set[3] = h;
		set[4] = alpha;
		set[5] = on;
		Sc.position(t, l, x, y);
		Sc.crop(t, l, owner.scratch, 0, 0, w, h);
		if (LayerPlane.fine(alpha)) Sc.alpha(t, l, alpha);
		Sc.visible(t, l, on == 1);
		return 1;
	}

	// (its buffer's size: what it has while its quads fit and fill half of
	// it: a buffer made again costs more than a CAMetalLayer's drawable)
	override public function fit() {
		super.fit();
		if (kind == LayerPlane.BASE || quads.length == 0) return;
		if (bufW >= pw && bufH >= ph && bufW * bufH <= 2 * pw * ph) {
			pw = bufW;
			ph = bufH;
		}
	}

	// (a buffer to draw into: of its size now (those of another let go), one
	// the system let go of, its release fence waited for, else a new one, up
	// to two (one shown, one drawn: the last transaction is presented before
	// the next applies), three for a small one (a thumb's, drawn each frame);
	// null while none is let go within a display period: drawn next frame,
	// the frame's moves not held back by it. Off once one waited 1.5 s: the
	// system never lets go of what it was given. allocated: false where a
	// buffer could not be made)
	public function next():Null<ScBuffer> {
		var gl = owner.gl;
		allocated = true;
		if (pw != bufW || ph != bufH) {
			for (b in buffers)
				b.free(gl);
			buffers.resize(0);
			queued.resize(0);
			shownBuffer = null;
			bufW = pw;
			bufH = ph;
		}
		var t0 = haxe.Timer.stamp(), until = t0 + owner.period;
		while (true) {
			for (b in buffers)
				if (!b.busy && b.ready()) {
					waiting = -1;
					owner.timing[2] += haxe.Timer.stamp() - t0;
					return b;
				}
			if (buffers.length < (pw * ph * 4 <= owner.device.width * owner.device.height ? 3 : 2)) {
				var b = ScBuffer.make(gl, pw, ph);
				if (b != null) buffers.push(b) else allocated = false;
				waiting = -1;
				return b;
			}
			if (haxe.Timer.stamp() > until) break;
			Sys.sleep(0.0005);
			owner.released();
		}
		var t = haxe.Timer.stamp();
		owner.timing[2] += t - t0;
		if (waiting < 0) waiting = t0 else if (t - waiting > 1.5) owner.fail("buffers never released");
		return null;
	}

	public var allocated = true;
	var waiting = -1.0;

	// (buffer b drawn, done once fence is (-1: done), set in transaction seq)
	public function queue(b:ScBuffer, fence:Int, seq:Int) {
		b.busy = true;
		Sc.buffer(owner.tx, sc, b.handle, fence);
		// (what changed from the buffer shown before, where the system takes it: API 29's)
		if (!damage.all && damage.count > 0) Sc.damage(owner.tx, sc, owner.scratch, damage);
		queued.push({seq: seq, was: shownBuffer});
		shownBuffer = b;
	}

	// (transaction seq presented: the buffer it replaced here let go once fence is)
	public function release(seq:Int, fence:Int) {
		var i = 0;
		while (i < queued.length && queued[i].seq != seq)
			i++;
		if (i == queued.length) {
			if (fence >= 0) Posix.close(fence);
			return;
		}
		var was = queued[i].was;
		queued.splice(0, i + 1);
		if (was == null || was == shownBuffer) {
			if (fence >= 0) Posix.close(fence);
			return;
		}
		was.released(fence);
	}

	public function memory():Float
		return buffers.length * pw * ph * 4.0;

	// (made on a window gone: made again on the next, drawn again)
	public function lose(t:Ptr) {
		if (kind == LayerPlane.SLOT && !slot.handle.isNull()) Sc.reparent(t, slot.handle, Ptr.nil());
		for (l in [sc, clip])
			if (!l.isNull()) {
				Sc.reparent(t, l, Ptr.nil());
				Sc.release(l);
			}
		sc = clip = parented = Ptr.nil();
		for (i in 0...set.length)
			set[i] = -1e300;
		hidden = true;
		for (b in buffers)
			b.busy = false;
		queued.resize(0);
		shownBuffer = null;
		invalidate();
	}

	public function dispose() {
		var gl = owner.gl;
		if (gl != null) for (b in buffers)
			b.free(gl);
		buffers.resize(0);
	}

	override public function free():Void->Void {
		var o = owner, s = sc, c = clip, sl = kind == LayerPlane.SLOT ? slot.handle : Ptr.nil(), bs = buffers.copy();
		sc = clip = parented = Ptr.nil();
		buffers.resize(0);
		return () -> {
			var t = o.tx;
			if (!sl.isNull()) Sc.reparent(t, sl, Ptr.nil());
			for (l in [s, c])
				if (!l.isNull()) {
					Sc.reparent(t, l, Ptr.nil());
					Sc.release(l);
				}
			if (o.gl != null) for (b in bs)
				b.free(o.gl);
		}
	}
}

// (a layer's buffer: an AHardwareBuffer, GLES's texture of it; whether
// the system may still read it, the fence of its release)
@:hxmc.unsafe(gc)
private class ScBuffer {
	public final handle:Ptr;
	public final texture:Int;
	public var busy = false;
	// (the draw of its layer it holds: LayerPlane.serial, -1 none)
	public var at = -1;
	var fence = -1;

	function new(handle:Ptr, texture:Int) {
		this.handle = handle;
		this.texture = texture;
	}

	// (RGBA8, sampled, rendered to, an overlay's: a texture of its EGLImage)
	public static function make(gl:GLBackend, w:Int, h:Int):Null<ScBuffer> {
		var d:Ptr = LibC.malloc(64);
		LibC.memset(d, 0, 64);
		Mem.setI32(d, 0, w);
		Mem.setI32(d, 4, h);
		Mem.setI32(d, 8, 1);
		Mem.setI32(d, 12, 1); // AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM
		// (GPU_SAMPLED_IMAGE, GPU_COLOR_OUTPUT, COMPOSER_OVERLAY)
		Mem.setI64(d, 16, (1 << 8) | (1 << 9) | (1 << 11));
		var hb = Sc.allocate(d, d.add(48));
		LibC.free(d);
		if (hb.isNull()) return null;
		var t = Sc.texture(gl, hb, w, h);
		if (t == 0) {
			Sc.unref(hb);
			return null;
		}
		return new ScBuffer(hb, t);
	}

	// (let go by the system, once fence is)
	public function released(f:Int) {
		if (fence >= 0) Posix.close(fence);
		fence = f;
		busy = false;
	}

	// (whether its release fence signalled (a little waited for): drawn into only then)
	public function ready():Bool {
		if (fence < 0) return true;
		if (!Sc.wait(fence)) return false;
		Posix.close(fence);
		fence = -1;
		return true;
	}

	public function free(gl:GLBackend) {
		if (fence >= 0) Posix.close(fence);
		fence = -1;
		gl.destroyTexture(texture);
		Sc.unref(handle);
	}
}

// (the NDK's SurfaceControl, AHardwareBuffer and EGL's functions for them,
// looked up in libandroid at first: API 31's are not there before it;
// transactions presented and their release fences, from the system's
// callback on a binder thread, in plain memory under a lock)
@:hxmc.unsafe(gc)
private class Sc {
	static var lib = Ptr.nil();
	static var looked = false;
	static var ok = false;
	static var fFromWindow = Ptr.nil();
	static var fCreate = Ptr.nil();
	static var fRelease = Ptr.nil();
	static var fTxCreate = Ptr.nil();
	static var fTxDelete = Ptr.nil();
	static var fTxApply = Ptr.nil();
	static var fOnComplete = Ptr.nil();
	static var fBuffer = Ptr.nil();
	static var fVisibility = Ptr.nil();
	static var fZOrder = Ptr.nil();
	static var fTransparency = Ptr.nil();
	static var fAlpha = Ptr.nil();
	static var fColor = Ptr.nil();
	static var fReparent = Ptr.nil();
	static var fPosition = Ptr.nil();
	static var fCrop = Ptr.nil();
	static var fScale = Ptr.nil();
	static var fControls = Ptr.nil();
	static var fReleaseControls = Ptr.nil();
	static var fPreviousFence = Ptr.nil();
	static var fAllocate = Ptr.nil();
	static var fUnref = Ptr.nil();
	static var fDamage = Ptr.nil();
	// (EGL's, on the render thread)
	static var fClientBuffer = Ptr.nil();
	static var fCreateImage = Ptr.nil();
	// (the callback's: a lock, the last transaction presented, a ring of
	// (surface control, transaction, release fence) of RING entries)
	static var lock = Ptr.nil();
	static var done = 0;
	static var ring = Ptr.nil();
	static var count = 0;

	static inline var RING = 256;
	// (HELDER_SYSTEM_LAYERS=stall: no transaction reported presented, as a
	// misbehaving system's; tests the fallback)
	static var stall = false;

	// whether this Android has what system layers need (API 31's calls)
	public static function load():Bool {
		if (looked) return ok;
		looked = true;
		stall = Sys.getEnv("HELDER_SYSTEM_LAYERS") == "stall";
		lib = Posix.dlopen(Mem.cstr("libandroid.so"), 2);
		if (lib.isNull()) return false;
		inline function f(name:String):Ptr
			return Posix.dlsym(lib, Mem.cstr(name));
		fFromWindow = f("ASurfaceControl_createFromWindow");
		fCreate = f("ASurfaceControl_create");
		fRelease = f("ASurfaceControl_release");
		fTxCreate = f("ASurfaceTransaction_create");
		fTxDelete = f("ASurfaceTransaction_delete");
		fTxApply = f("ASurfaceTransaction_apply");
		fOnComplete = f("ASurfaceTransaction_setOnComplete");
		fBuffer = f("ASurfaceTransaction_setBuffer");
		fVisibility = f("ASurfaceTransaction_setVisibility");
		fZOrder = f("ASurfaceTransaction_setZOrder");
		fTransparency = f("ASurfaceTransaction_setBufferTransparency");
		fAlpha = f("ASurfaceTransaction_setBufferAlpha");
		fColor = f("ASurfaceTransaction_setColor");
		fReparent = f("ASurfaceTransaction_reparent");
		fPosition = f("ASurfaceTransaction_setPosition");
		fCrop = f("ASurfaceTransaction_setCrop");
		fScale = f("ASurfaceTransaction_setScale");
		fControls = f("ASurfaceTransactionStats_getASurfaceControls");
		fReleaseControls = f("ASurfaceTransactionStats_releaseASurfaceControls");
		fPreviousFence = f("ASurfaceTransactionStats_getPreviousReleaseFenceFd");
		fAllocate = f("AHardwareBuffer_allocate");
		fUnref = f("AHardwareBuffer_release");
		// (optional: without it, the whole buffer is the damage)
		fDamage = f("ASurfaceTransaction_setDamageRegion");
		for (p in [
			fFromWindow, fCreate, fRelease, fTxCreate, fTxDelete, fTxApply, fOnComplete, fBuffer, fVisibility, fZOrder, fTransparency, fAlpha, fColor, fReparent,
			fPosition, fCrop, fScale, fControls, fReleaseControls, fPreviousFence, fAllocate, fUnref
		])
			if (p.isNull()) return false;
		lock = LibC.malloc(64);
		Threads.pthread_mutex_init(lock, Ptr.nil());
		ring = LibC.malloc(RING * 16);
		return ok = true;
	}

	public static function fromWindow(w:Ptr):Ptr
		return ScCall.pp(fFromWindow, w, Mem.cstr("helder"));

	public static function child(parent:Ptr):Ptr
		return ScCall.pp(fCreate, parent, Mem.cstr("helder.layer"));

	public static function release(sc:Ptr)
		ScCall.p(fRelease, sc);

	public static function create():Ptr
		return ScCall.r(fTxCreate);

	public static function delete(t:Ptr)
		ScCall.p(fTxDelete, t);

	// (t applied as transaction seq: presented() is seq once the system
	// presented it; -1: no transaction to wait for)
	public static function apply(t:Ptr, seq:Int) {
		if (seq >= 0 && !stall) ScCall.ppp(fOnComplete, t, Ptr.ofI64(seq), Callback.addr(presentedNow));
		ScCall.p(fTxApply, t);
	}

	public static function buffer(t:Ptr, sc:Ptr, b:Ptr, fence:Int)
		ScCall.pppi(fBuffer, t, sc, b, fence);

	public static function visible(t:Ptr, sc:Ptr, on:Bool)
		ScCall.ppi(fVisibility, t, sc, on ? 1 : 0);

	public static function order(t:Ptr, sc:Ptr, z:Int)
		ScCall.ppi(fZOrder, t, sc, z);

	// (ASURFACE_TRANSACTION_TRANSPARENCY_OPAQUE 2, _TRANSLUCENT 1)
	public static function opaque(t:Ptr, sc:Ptr, on:Bool)
		ScCall.ppi(fTransparency, t, sc, on ? 2 : 1);

	// (ADATASPACE_UNKNOWN: the buffers' own)
	public static function color(t:Ptr, sc:Ptr, r:Float, g:Float, b:Float)
		ScCall.ppffffi(fColor, t, sc, r, g, b, 1, 0);

	public static function alpha(t:Ptr, sc:Ptr, a:Float)
		ScCall.ppf(fAlpha, t, sc, a);

	public static function reparent(t:Ptr, sc:Ptr, parent:Ptr)
		ScCall.ppp(fReparent, t, sc, parent);

	public static function position(t:Ptr, sc:Ptr, x:Int, y:Int)
		ScCall.ppii(fPosition, t, sc, x, y);

	public static function scale(t:Ptr, sc:Ptr, x:Float, y:Float)
		ScCall.ppff(fScale, t, sc, x, y);

	// (an ARect: left, top, right, bottom, in scratch)
	public static function crop(t:Ptr, sc:Ptr, scratch:Ptr, x:Int, y:Int, w:Int, h:Int) {
		Mem.setI32(scratch, 0, x);
		Mem.setI32(scratch, 4, y);
		Mem.setI32(scratch, 8, x + w);
		Mem.setI32(scratch, 12, y + h);
		ScCall.ppp(fCrop, t, sc, scratch);
	}

	// (d's rectangles as ARects in scratch (64 bytes: four at most, else
	// their bounds), the damage of sc's buffer in t)
	public static function damage(t:Ptr, sc:Ptr, scratch:Ptr, d:Damage) {
		if (fDamage.isNull()) return;
		var n = d.count <= 4 ? d.count : 1;
		for (i in 0...n) {
			var o = i * 16;
			var x0 = d.x0(i), y0 = d.y0(i), x1 = d.x1(i), y1 = d.y1(i);
			if (n == 1 && d.count > 1) for (k in 1...d.count) {
				x0 = Math.min(x0, d.x0(k));
				y0 = Math.min(y0, d.y0(k));
				x1 = Math.max(x1, d.x1(k));
				y1 = Math.max(y1, d.y1(k));
			}
			Mem.setI32(scratch, o, Std.int(x0));
			Mem.setI32(scratch, o + 4, Std.int(y0));
			Mem.setI32(scratch, o + 8, Std.int(x1));
			Mem.setI32(scratch, o + 12, Std.int(y1));
		}
		ScCall.pppi(fDamage, t, sc, scratch, n);
	}

	// (an AHardwareBuffer of the AHardwareBuffer_Desc at d; out: its pointer's room)
	public static function allocate(d:Ptr, out:Ptr):Ptr {
		Mem.setPtr(out, 0, Ptr.nil());
		return ScCall.ppI(fAllocate, d, out) == 0 ? Mem.getPtr(out, 0) : Ptr.nil();
	}

	public static function unref(b:Ptr)
		ScCall.p(fUnref, b);

	// (GLES's texture of buffer b, w x h: through an EGLImage; 0 where EGL cannot)
	public static function texture(gl:GLBackend, b:Ptr, w:Int, h:Int):Int {
		if (fClientBuffer.isNull()) fClientBuffer = gl.proc("eglGetNativeClientBufferANDROID");
		if (fCreateImage.isNull()) fCreateImage = gl.proc("eglCreateImageKHR");
		if (fClientBuffer.isNull() || fCreateImage.isNull()) return 0;
		var client = EglSync.clientBuffer(fClientBuffer, b);
		if (client.isNull()) return 0;
		var image = Arena.scopedValue(a -> {
			var at:Ptr<Int32> = a.alloc(16);
			at[0] = EGL.IMAGE_PRESERVED_KHR;
			at[1] = 1;
			at[2] = EGL.NONE;
			EglImage.create(fCreateImage, gl.egl(), Ptr.nil(), EGL.NATIVE_BUFFER_ANDROID, client, at);
		});
		return image.isNull() ? 0 : gl.imageTexture(image, w, h);
	}

	// (whether a fence signalled, waited for 4 ms at most: next's loop waits on)
	public static function wait(fd:Int):Bool {
		var p = Mem.stack(8);
		Mem.setI32(p, 0, fd);
		Mem.setI32(p, 4, 1); // POLLIN
		return FencePoll.poll(p, 1, 4) > 0;
	}

	// the last transaction the system presented
	public static function presented():Int {
		Threads.pthread_mutex_lock(lock);
		var d = done;
		Threads.pthread_mutex_unlock(lock);
		return d;
	}

	// each (surface control, transaction, release fence) the callback kept, taken
	public static function drain(f:(sc:Ptr, seq:Int, fd:Int) -> Void) {
		Threads.pthread_mutex_lock(lock);
		var n = count, copy = LibC.malloc(n * 16 + 16);
		LibC.memcpy(copy, ring, n * 16);
		count = 0;
		Threads.pthread_mutex_unlock(lock);
		for (i in 0...n)
			f(Mem.getPtr(copy, i * 16), Mem.getI32(copy, i * 16 + 8), Mem.getI32(copy, i * 16 + 12));
		LibC.free(copy);
	}

	// (the system's, on a binder thread: transaction context presented, the
	// release fences of the buffers its own replaced)
	@:hxmc.callback @:hxmc.noGc static function presentedNow(context:Ptr, stats:Ptr):Void {
		var seq = context.toI64().toInt();
		var out = Mem.stack(16);
		ScCall.ppp(fControls, stats, out, out.add(8));
		var list = Mem.getPtr(out, 0), n = Mem.getI64(out, 8).toInt();
		Threads.pthread_mutex_lock(lock);
		var i = 0;
		while (i < n) {
			var sc = Mem.getPtr(list, i * 8), fd = ScCall.ppI(fPreviousFence, stats, sc);
			if (count < RING) {
				var e = ring.add(count * 16);
				Mem.setPtr(e, 0, sc);
				Mem.setI32(e, 8, seq);
				Mem.setI32(e, 12, fd);
				count++;
			} else if (fd >= 0) Posix.close(fd);
			i++;
		}
		if (seq > done) done = seq;
		Threads.pthread_mutex_unlock(lock);
		if (n > 0) ScCall.p(fReleaseControls, list);
	}
}

// (the calls' shapes through their pointers: their arguments' kinds)
@:hxmc.c @:hxmc.fast private extern class ScCall {
	@:hxmc.indirect static function r(f:Ptr):Ptr;
	@:hxmc.indirect static function p(f:Ptr, a:Ptr):Void;
	@:hxmc.indirect static function pp(f:Ptr, a:Ptr, b:Ptr):Ptr;
	@:hxmc.indirect static function ppI(f:Ptr, a:Ptr, b:Ptr):Int;
	@:hxmc.indirect static function ppp(f:Ptr, a:Ptr, b:Ptr, c:Ptr):Void;
	@:hxmc.indirect static function pppi(f:Ptr, a:Ptr, b:Ptr, c:Ptr, d:Int):Void;
	@:hxmc.indirect static function ppi(f:Ptr, a:Ptr, b:Ptr, c:Int):Void;
	@:hxmc.indirect static function ppii(f:Ptr, a:Ptr, b:Ptr, c:Int, d:Int):Void;
	@:hxmc.indirect static function ppf(f:Ptr, a:Ptr, b:Ptr, c:Float32):Void;
	@:hxmc.indirect static function ppff(f:Ptr, a:Ptr, b:Ptr, c:Float32, d:Float32):Void;
	@:hxmc.indirect static function ppffffi(f:Ptr, a:Ptr, b:Ptr, c:Float32, d:Float32, e:Float32, g:Float32, h:Int):Void;
}

// (poll(2) on a fence's descriptor: as the runtime's own, fast: its waits are short)
@:hxmc.c @:hxmc.fast private extern class FencePoll {
	static function poll(fds:Ptr, n:Int64, timeout:Int):Int;
}
#end
