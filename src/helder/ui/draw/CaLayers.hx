package helder.ui.draw;

#if ((!helder.os || helder.os == "macos" || helder.os == "ios") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.metal.MetalBackend;
import helder.os.objc.*;
import hxmc.unsafe.*;
import sys.thread.Mutex;

// The system's compositor on macOS and iOS (Layers' step 5): a window's
// layers handed to Core Animation. Each frame, the program's and the
// compositor's alike, is composed from the compositor's state
// (CompositeFrame) and split into layers in paint order: the window's
// CAMetalLayer at the bottom; a CAMetalLayer of its own for each top-level
// scroller's content, under a CALayer clipping to the scroller's clip
// (whole pixels; a rounded one masked by its coverage, drawn by UiShader:
// mask), and for each top-level layer that moves on its own
// (helder.ui.Mover: of no scroller, nothing nested moving, its clips its
// own); each node's system layer (LayerSlot: a CALayer, or a native view
// in its host, CaViews) at its place, in its scroller's clip or one of its
// own; over each of those, a CAMetalLayer of what is drawn over it (only
// what overlaps it, or what overlaps that: the rest stays below, so a
// scrollbar is the layer over its list, not the window's whole). A layer
// is drawn again only where its quads, its size or what it samples
// (CompositeFrame.fresh) changed: a scroll moves its content's layer and a
// mover's transform and opacity are its layer's, so neither draws. A frame
// that changes the tree is one transaction: what it drew presented with it
// (presentsWithTransaction), the layers and views placed, on the main
// thread where views are in it (an NSView's, a UIView's), else on the
// render thread; one that only draws presents at once, waiting for no
// transaction, and one split into the window's layer alone (a scene over
// the window) is the textured compositor's (single), as costly as it is.
// A layer is drawn as the compositor draws (UiShader, its quads moved to
// the layer's pixels by whole pixels: the same pixels), single-sampled,
// onto a clear target, and blended by the system over what is under it, so
// the pixels are the textured compositor's within a level where
// translucent things meet. Nothing NaN or infinite reaches Core Animation,
// which throws at it (fine). On iOS the content's layer and what is in it
// follow its UIScrollView on the main thread as UIKit moves it (scrolled).
// HELDER_SYSTEM_LAYERS=0 keeps the window's one CAMetalLayer and the
// textured compositor; frames read back (a window's capture, headless
// runs, screenshots, golden images) never use these.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.Node)
class CaLayers {
	public static function wanted(device:Device):Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && device.backend == Metal && device.surface.kind == Cocoa;

	final root:Ptr; // the window's CAMetalLayer
	final view:Ptr; // its view
	var stack = Ptr.nil(); // over its contents, the layers in order
	final ios:Bool;
	// (the display's period: commits no closer)
	final period:Float;
	var committed = -1e9;
	// (the frame split: whether it is the one adopted last)
	var adopted = 0;
	var split = -1;
	var splitFrame:Null<CompositeFrame> = null;
	var consumed = -1;
	// (per quad of the frame its layer's place in order, per tile group too;
	// the units (scrollers' and movers' layers) in order; their places; per
	// frame whether on a layer of its own; per mover whether held)
	final quadPlace:Array<Int> = [];
	final groupPlace:Array<Int> = [];
	final units:Array<Plane> = [];
	final free:Array<Bool> = [];
	final held:Array<Bool> = [];
	// (the layers by place: 0 the window's, 2j + 1 unit j's, 2j + 2 what is over it; kept by their keys)
	final order:Array<Null<Plane>> = [];
	final base:Plane;
	final kept = new haxe.ds.ObjectMap<Dynamic, Plane>();
	final overs = new haxe.ds.ObjectMap<Dynamic, Plane>();
	var shownOrder:Array<Ptr> = [];
	// (the layers let go since the last frame: removed in its transaction, after its order)
	final gone:Array<Void->Void> = [];
	// (compose's: its quads, their sources, the offsets scrolls move by, runs)
	var out = Bytes.alloc(0);
	final sources:Array<Int> = [];
	final shifts:Array<Float> = [];
	final runTextures:Array<Null<Texture>> = [];
	final runs:Array<Int> = [];
	final quadTextures:Array<Null<Texture>> = [];
	final commands = new Commands();
	var ring = 0;
	// (main-thread commits not yet run: what follows waits its turn)
	var pending = 0;
	// (iOS: the stack put into the window's UIView's layer this frame. Its
	// commit lays that view out, which UIKit allows on the main thread alone)
	var rooted = false;
	final lock = new Mutex();
	// (iOS: the scrollers' content layers by node, for scrolled)
	final contents = new Map<Node, Plane>();
	// frames committed
	public var frames(default, null) = 0;
	// layers and quads drawn in all (a scroll that only moves layers draws none)
	public var drawnTotal(default, null) = 0;
	public var quadsTotal(default, null) = 0;
	// (why each top-level scroller not on a layer of its own is not, at the last split: tests)
	@:noCompletion public var reasons(default, null):Array<String> = [];
	// (HELDER_SYSTEM_LAYERS=flat: all of it on the window's layer, as the
	// textured compositor draws it: the split's own check, SystemLayersWindow)
	static final flat = Sys.getEnv("HELDER_SYSTEM_LAYERS") == "flat";

	public function new(device:Device) {
		root = device.surface.display;
		view = device.surface.handle;
		ios = hxmc.Platform.apple() >= 1;
		var fps = helder.os.OsThread.get(() -> {
			var v = device.surface.handle, s = ios ? Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")) : Msg.id(Msg.id(v, ObjC.sel("window")), ObjC.sel("screen"));
			s.isNull() ? 60 : Msg.i(s, ObjC.sel("maximumFramesPerSecond")).toInt();
		});
		period = 1 / (fps > 0 ? fps : 60);
		base = new Plane(BASE, null);
		base.layer = root;
	}

	// whether the nodes' system layers and views go in the tree (not flat's)
	public static function slots():Bool
		return !flat;

	// whether the last frame split into the window's layer alone: the
	// frames are then drawn and presented as the textured compositor's, a
	// scene covering the window costing what it costs there (nothing to
	// compose again, no other drawable, no transaction)
	public var single(default, null) = false;

	// (a frame drawn onto the window's layer: split, whether the next is single)
	public function check(f:CompositeFrame) {
		if (f.buffers.length == 0 || f.pipeline == null) return;
		if (split != adopted || splitFrame != f) splitUp(f);
	}

	// (a new frame of the program's: split again)
	public function adopt()
		adopted++;

	// the bytes of the layers' drawables (each kept up to two), beside the window's own
	public function bytes():Float {
		var b = 0.0;
		for (p in kept)
			b += p.pw * p.ph * 4.0 * 2;
		for (p in overs)
			b += p.pw * p.ph * 4.0 * 2;
		return b;
	}

	// f's frame at the offsets now (per frame, x then y) and time t, its
	// overlay bars shown as shown has them (null: as drawn), drawn and
	// committed; drawn: the program's own frame (its movers as drawn).
	// moves: the native views moved with it (on the main thread)
	public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null) return;
		var mb:MetalBackend = cast r.impl, pool = Runtime.objc_autoreleasePoolPush();
		if (split != adopted || splitFrame != f) splitUp(f);
		// (composed: the scrollers and movers on layers of their own as drawn, the system moves them)
		shifts.resize(0);
		for (v in now)
			shifts.push(v);
		for (u in units)
			if (u.kind == SCROLL) {
				shifts[2 * u.index] = f.offsets[2 * u.index];
				shifts[2 * u.index + 1] = f.offsets[2 * u.index + 1];
			}
		var need = f.quads() * CompositeFrame.STRIDE;
		if (out.length < need) out = Bytes.alloc(need * 2);
		sources.resize(0);
		f.sources = sources;
		f.scrolled = shifts;
		f.free = free;
		f.held = held;
		f.asDrawn = drawn;
		function unset() {
			f.sources = null;
			f.scrolled = null;
			f.free = null;
			f.held = null;
			f.asDrawn = false;
		}
		var n = try f.compose(now, t, shown, out, runTextures, runs) catch (e:haxe.Exception) {
			unset();
			Runtime.objc_autoreleasePoolPop(pool);
			throw e;
		}
		unset();
		quadTextures.resize(n);
		for (k in 0...Std.int(runs.length / 2))
			for (q in runs[2 * k]...runs[2 * k] + runs[2 * k + 1])
				quadTextures[q] = runTextures[k];
		for (p in order)
			if (p != null) p.begin();
		for (w in 0...n) {
			var s = sources[w], p = order[s >= 0 ? quadPlace[s] : groupPlace[-1 - s]];
			p.add(w, out);
		}
		var fresh = consumed != adopted ? f.fresh : null;
		consumed = adopted;
		var cs = Msg.f(root, S.contentsScale), ops:Array<Void->Void> = [];
		var b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0, toDraw:Array<Plane> = [];
		CATransaction.begin();
		for (p in order) {
			if (p == null) continue;
			// (a system layer: its clip and its mask; placed by geometry)
			if (p.kind == SLOT) {
				p.makeSlot(cs, ops);
				if (at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, p, b, at, ops)) at += CompositeFrame.STRIDE;
				continue;
			}
			for (sp in p.slots) {
				sp.makeSlot(cs, ops);
				if (at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, sp, b, at, ops)) at += CompositeFrame.STRIDE;
			}
			if (p.kind == BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != BASE) {
				p.show(false, ops);
				continue;
			}
			p.show(true, ops);
			p.make(root, cs, ops);
			if (p.kind == SCROLL && at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, p, b, at, ops)) at += CompositeFrame.STRIDE;
			if (p.local(out, quadTextures, fresh)) toDraw.push(p);
		}
		var views = geometry(f, now, cs, ops);
		for (g in gone)
			ops.push(g);
		gone.resize(0);
		// (nothing of the tree changes: what is drawn presented at once, as
		// the window's frames are, waiting for no transaction)
		lock.acquire();
		var direct = ops.length == 0 && moves.length == 0 && !views && pending == 0;
		lock.release();
		for (p in toDraw) {
			p.presenting(!direct);
			if (at + p.len <= f.capacity && draw(r, mb, f, p.layer, p.bytes, p.len, p.runs, p.runTextures, p.kind == BASE, b, at, direct)) {
				at += p.len;
				drawnTotal++;
				quadsTotal += p.quads.length;
			} else
				p.invalidate();
		}
		CATransaction.commit();
		var presents = mb.takePresents();
		// (one commit a period where nothing waited for a drawable: the display's pace)
		var wait = committed + period * 0.9 - haxe.Timer.stamp();
		if (wait > 0 && toDraw.length == 0) Sys.sleep(wait);
		if (ops.length > 0 || presents.length > 0 || moves.length > 0) commit(ops, presents, moves, views);
		committed = haxe.Timer.stamp();
		frames++;
		Runtime.objc_autoreleasePoolPop(pool);
		// (the window's layer alone from now: the next frames drawn onto it as the textured compositor draws)
		if (single) suspend();
	}

	// (a rounded scroller's mask: its clip's coverage, as UiShader clips the
	// content the layer has whole, drawn by UiShader (a white quad under that
	// clip) so that the corners are its own; only its corners and a pixel
	// between them, the middle stretched (contentsCenter, nearest): its
	// edges and middle are whole pixels of 1. Drawn again when its size,
	// radii or scale change)
	function mask(r:Replay, mb:MetalBackend, f:CompositeFrame, p:Plane, b:Buffer, at:Int, ops:Array<Void->Void>):Bool {
		var rr = p.radii, big = Math.max(Math.max(rr[0], rr[1]), Math.max(rr[2], rr[3]));
		if (big <= 1e-3 || p.kind == SLOT && !p.slot.view && p.attached >= 0) {
			p.unmask(ops);
			return false;
		}
		// (the corners' radii are capped by the clip's half sizes: a stretched
		// axis keeps a half over every radius, so the coverage there is the same)
		var w = p.cx1 - p.cx0, h = p.cy1 - p.cy0, m = Math.ceil(big) + 1, sw = Math.min(w, 2 * m + 1), sh = Math.min(h, 2 * m + 1);
		if (!p.masking(root, sw, sh, w, h, m, ops)) return false;
		var q = maskQuad;
		writeMask(q, sw, sh, rr);
		maskRuns[0] = 0;
		maskRuns[1] = 1;
		if (draw(r, mb, f, p.maskLayer, q, CompositeFrame.STRIDE, maskRuns, maskTextures, false, b, at)) return true;
		p.maskStale = true;
		return false;
	}

	final maskQuad = Bytes.alloc(CompositeFrame.STRIDE);
	final maskRuns = [0, 1];
	final maskTextures:Array<Null<Texture>> = [null];

	// (UiShader's quad of white over w x h pixels, clipped to them with corners' radii r)
	static function writeMask(b:Bytes, w:Float, h:Float, r:Array<Float>) {
		b.fill(0, b.length, 0);
		inline function corner(at:Int, x:Float, y:Float) {
			b.setFloat(at, x / w * 2 - 1);
			b.setFloat(at + 4, 1 - y / h * 2);
			b.setFloat(at + 8, x);
			b.setFloat(at + 12, y);
		}
		corner(0, -1, -1);
		corner(16, w + 1, -1);
		corner(32, -1, h + 1);
		b.setFloat(64, w / 2);
		b.setFloat(68, h / 2);
		b.setFloat(72, w / 2 + 1);
		b.setFloat(76, h / 2 + 1);
		for (i in 0...4)
			b.setFloat(80 + i * 4, 1);
		b.setFloat(168, w);
		b.setFloat(172, h);
		for (i in 0...4)
			b.setFloat(176 + i * 4, r[i]);
		var cx = w / 2, cy = h / 2, ix = Math.ffloor(cx), iy = Math.ffloor(cy);
		b.setFloat(192, ix);
		b.setFloat(196, iy);
		b.setFloat(200, cx - ix);
		b.setFloat(204, cy - iy);
		b.setFloat(208, -1e9);
		b.setFloat(212, -1e9);
		b.setFloat(216, 1e9);
		b.setFloat(220, 1e9);
	}

	// (quads drawn onto a layer's next drawable, at buffer b's offset at)
	function draw(r:Replay, mb:MetalBackend, f:CompositeFrame, layer:Ptr, bytes:Bytes, len:Int, runs:Array<Int>, runTextures:Array<Null<Texture>>,
			opaque:Bool, b:Buffer, at:Int, direct = false):Bool {
		var c = commands;
		mb.planeFrame(layer, direct);
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		if (!r.began) return false;
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(at);
		c.bytes(bytes, 0, len);
		c.end();
		var bg = f.background;
		c.begin(Replay.BEGIN_PASS);
		c.int(1);
		c.int(cast LoadOp.Clear);
		c.float(opaque ? (bg >> 16 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg >> 8 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg & 0xFF) / 255 : 0);
		c.float(opaque ? 1 : 0);
		c.int(0);
		c.int(0);
		c.int(Replay.NONE);
		c.int(0);
		c.end();
		three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
		three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
		three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
		three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
		var k = 0;
		while (k < runs.length) {
			var t = runTextures[k >> 1];
			three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at + runs[k] * CompositeFrame.STRIDE, 3);
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

	// (where the layers go now: a scroller's content by its offset, a
	// mover's by its transform and opacity sampled, a system layer by its
	// scroller's and its mover's; the layers' order, a view's host between
	// those under it and those over it (CaViews): whether a view is in it)
	function geometry(f:CompositeFrame, now:Array<Float>, cs:Float, ops:Array<Void->Void>):Bool {
		var s = f.scale;
		var sb = Msg.rect(root, S.bounds), sw = sb.size.width, sh = sb.size.height;
		for (u in units) {
			if (u.kind == SLOT) {
				slotAt(f, u, null, now, cs, sh, ops);
				continue;
			}
			if (u.quads.length == 0) continue;
			if (u.kind == SCROLL) {
				var k = u.index, dx = (f.offsets[2 * k] - now[2 * k]) * s, dy = (f.offsets[2 * k + 1] - now[2 * k + 1]) * s;
				u.clipTo(u.cx0 / cs, u.cy0 / cs, (u.cx1 - u.cx0) / cs, (u.cy1 - u.cy0) / cs, ops);
				u.move(u.geomX = (u.ox - u.cx0 + dx) / cs, u.geomY = (u.oy - u.cy0 + dy) / cs, 1, 0, 0, 1, 1, cs, ops);
				for (sp in u.slots)
					slotAt(f, sp, u, now, cs, sh, ops);
				u.inClip(ops);
			} else {
				var m = f.heldMoved, q = u.index * 7, a = m[q], b = m[q + 1], c = m[q + 2], d = m[q + 3];
				var px = u.ox / cs, py = u.oy / cs;
				u.move(a * px + c * py + m[q + 4] / cs, b * px + d * py + m[q + 5] / cs, a, b, c, d, m[q + 6], cs, ops);
			}
		}
		for (p in order)
			if (p != null && p.kind == OVER && p.quads.length > 0) p.move(p.ox / cs, p.oy / cs, 1, 0, 0, 1, 1, cs, ops);
		// (in order, split at each view: the layers under it, then those over it, up to the next)
		var segments:Array<Array<Ptr>> = [[]], hosts:Array<Ptr> = [], hits:Array<Array<Float>> = [];
		for (i in 1...order.length) {
			var p = order[i];
			if (p == null) continue;
			if (p.kind == SLOT && p.slot.view) {
				hosts.push(p.slot.handle);
				segments.push([]);
				hits.push([]);
				continue;
			}
			if (!p.made()) continue;
			segments[segments.length - 1].push(p.top());
			if (hits.length > 0) p.hits(hits[hits.length - 1], cs);
			for (sp in p.slots)
				if (sp.slot.view) {
					hosts.push(sp.slot.handle);
					segments.push([]);
					hits.push([]);
				}
		}
		var list = [for (g in segments) for (l in g) l].concat(hosts), same = list.length == shownOrder.length && segments.length == shownSegments;
		if (same) for (i in 0...list.length)
			if (list[i] != shownOrder[i]) same = false;
		var st = stack;
		if (hiddenStack && !st.isNull()) {
			hiddenStack = false;
			ops.push(() -> Msg.vBool(st, ObjC.sel("setHidden:"), false));
		}
		if (st.isNull()) {
			st = stack = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), S.layer));
			CaLayers.setPoint(st, S.setAnchorPoint, 0, 0);
			// (macOS: the hosting view's layer is y up; the layers are placed top down)
			if (!ios) Msg.vBool(st, ObjC.sel("setGeometryFlipped:"), true);
			var r = root;
			ops.push(() -> CaMsg.vPtrInt(r, ObjC.sel("insertSublayer:atIndex:"), st, 0));
			rooted = ios;
		}
		if (sw != stackW || sh != stackH) {
			stackW = sw;
			stackH = sh;
			ops.push(() -> {
				CaLayers.setPoint(st, S.setPosition, 0, 0);
				CaLayers.setRect(st, S.setBounds, 0, 0, sw, sh);
			});
		}
		// (the views: an over view for each host, sized, what it takes presses on; main thread)
		var views = hosts.length > 0 || overViews > 0, n = hosts.length;
		if (views) {
			overViews = n;
			ops.push(() -> {
				var v = cocoaViews();
				v.ensure(n);
				v.size(sw, sh);
				for (i in 0...n)
					v.hitsOf(i, hits[i]);
			});
		}
		if (!same) {
			shownOrder = list;
			shownSegments = segments.length;
			ops.push(() -> {
				var v = views ? cocoaViews() : null;
				for (i in 0...segments.length) {
					var a = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
					for (l in segments[i])
						Msg.vPtr(a, ObjC.sel("addObject:"), l);
					Msg.vPtr(i == 0 ? st : v.stacks[i - 1], ObjC.sel("setSublayers:"), a);
				}
				if (v != null) v.arrange(hosts);
			});
		}
		return views;
	}

	var shownSegments = 1;
	var overViews = 0;
	// (the main thread's)
	var caViews:Null<CaViews> = null;

	function cocoaViews():CaViews {
		if (caViews == null) caViews = new CaViews(view);
		return caViews;
	}

	// (system layer p where it is now: at its box as drawn, moved by its
	// scroller's offsets and its mover's change as sampled, under its clip
	// (its scroller's, in: the unit it is in, its clip that one's), points)
	function slotAt(f:CompositeFrame, p:Plane, in_:Null<Plane>, now:Array<Float>, cs:Float, sh:Float, ops:Array<Void->Void>) {
		var d = f.slotData, o = p.index * CompositeFrame.SLOT, s = f.scale;
		var fr = Std.int(d[o + 2]), c = Std.int(d[o + 3]), m = Std.int(d[o + 4]);
		var ax = d[o + 6], ay = d[o + 7], bx = d[o + 8], by = d[o + 9], qx = d[o + 10], qy = d[o + 11], alpha = 1.0;
		if (m >= 0) {
			var mv = f.moved, k = m * 7;
			inline function tx(x:Float, y:Float):Float
				return mv[k] * x + mv[k + 2] * y + mv[k + 4];
			inline function ty(x:Float, y:Float):Float
				return mv[k + 1] * x + mv[k + 3] * y + mv[k + 5];
			var nax = tx(ax, ay), nay = ty(ax, ay), nbx = tx(bx, by), nby = ty(bx, by), nqx = tx(qx, qy), nqy = ty(qx, qy);
			ax = nax;
			ay = nay;
			bx = nbx;
			by = nby;
			qx = nqx;
			qy = nqy;
			alpha = mv[k + 6];
		}
		inline function snapped(v:Float):Float
			return f.snap ? Math.fround(v) : v;
		var dx = fr >= 0 ? snapped(f.shift(fr, now, true) * s) : 0.0, dy = fr >= 0 ? snapped(f.shift(fr, now, false) * s) : 0.0;
		var cx0 = p.cx0, cy0 = p.cy0, cx1 = p.cx1, cy1 = p.cy1;
		if (in_ == null && c >= 0) {
			var ex = snapped(f.shift(c, now, true) * s), ey = snapped(f.shift(c, now, false) * s);
			cx0 += ex;
			cy0 += ey;
			cx1 += ex;
			cy1 += ey;
		}
		// (a window's clip: the window)
		cx0 = Math.max(cx0, -1e6);
		cy0 = Math.max(cy0, -1e6);
		cx1 = Math.min(cx1, 1e6);
		cy1 = Math.min(cy1, 1e6);
		var w = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)), h = Math.sqrt((qx - ax) * (qx - ax) + (qy - ay) * (qy - ay));
		if (!(w > 0) || !(h > 0) || !fine(w) || !fine(h)) return;
		var a = (bx - ax) / w, b = (by - ay) / w, cc = (qx - ax) / h, dd = (qy - ay) / h;
		var x = (ax + dx - cx0) / cs, y = (ay + dy - cy0) / cs;
		var hw = (cx1 - cx0) / cs, hh = (cy1 - cy0) / cs;
		if (in_ == null && !p.slot.view) p.clipTo(cx0 / cs, cy0 / cs, hw, hh, ops);
		p.placeSlot(x, y, w / cs, h / cs, a, b, cc, dd, alpha, cx0 / cs, ios ? cy0 / cs : sh - cy1 / cs, hw, hh, ops);
	}
	// (the frame's changes in one transaction: here, the layers being ours,
	// or on the main thread where a native view moves with them, and after
	// it while one runs there)
	function commit(ops:Array<Void->Void>, presents:Array<Ptr>, moves:Array<Void->Void>, views:Bool) {
		function apply() {
			var pool = Runtime.objc_autoreleasePoolPush();
			CATransaction.begin();
			for (o in ops)
				o();
			for (m in moves)
				m();
			for (d in presents)
				Msg.v(d, ObjC.sel("present"));
			CATransaction.commit();
			for (d in presents)
				Runtime.objc_release(d);
			Runtime.objc_autoreleasePoolPop(pool);
		}
		lock.acquire();
		var main = moves.length > 0 || views || pending > 0 || rooted;
		rooted = false;
		if (main) pending++;
		lock.release();
		if (!main) {
			apply();
			return;
		}
		helder.os.OsThread.post(() -> {
			apply();
			lock.acquire();
			pending--;
			lock.release();
		});
	}

	// iOS: a UIScrollView moved the program's n to x, y (its offsets, UI
	// pixels), on the main thread: its content's layer follows in UIKit's
	// own transaction, as the scroll view moves
	public function scrolled(n:Node, x:Float, y:Float) {
		if (!ios) return;
		lock.acquire();
		var p = contents.get(n), busy = pending > 0, follow = p == null ? [] : p.follow;
		lock.release();
		if (p == null || busy || p.layer.isNull()) return;
		var dx = (p.drawnX - x) * p.scale, dy = (p.drawnY - y) * p.scale;
		var nx = (p.ox - p.cx0 + dx) / p.cs, ny = (p.oy - p.cy0 + dy) / p.cs;
		p.move(nx, ny, 1, 0, 0, 1, 1, p.cs, null);
		if (follow.length == 0) return;
		CATransaction.begin();
		for (sp in follow)
			sp.shiftSlot(nx - p.geomX, ny - p.geomY);
		CATransaction.commit(false);
	}

	// the window's own frames drawn onto its layer for now (a frame read
	// back: the textured compositor's): the layers hidden, its drawables
	// presented as before; the next show draws it again (render thread)
	public function suspend() {
		if (stack.isNull() && base.layer.isNull()) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		lock.acquire();
		var busy = pending > 0;
		lock.release();
		CATransaction.begin();
		Msg.vBool(root, S.setPresentsWithTransaction, false);
		CATransaction.commit();
		var st = stack;
		if (!st.isNull()) {
			var hide = () -> {
				CATransaction.begin();
				Msg.vBool(st, ObjC.sel("setHidden:"), true);
				CATransaction.commit();
			}
			if (busy) helder.os.OsThread.post(hide) else hide();
			hiddenStack = true;
		}
		base.reset();
		Runtime.objc_autoreleasePoolPop(pool);
	}

	var hiddenStack = false;
	var stackW = -1.0;
	var stackH = -1.0;

	// the layers gone, the window's own frames shown as before (on the
	// render thread, in order; after the main thread's commits still to run)
	public function dispose() {
		var st = stack, r = root, all = gone.splice(0, gone.length);
		for (p in kept)
			all.push(p.free());
		for (p in overs)
			all.push(p.free());
		kept.clear();
		overs.clear();
		shownOrder = [];
		stack = Ptr.nil();
		function apply() {
			var pool = Runtime.objc_autoreleasePoolPush();
			CATransaction.begin();
			for (f in all)
				f();
			if (!st.isNull()) {
				Msg.v(st, ObjC.sel("removeFromSuperlayer"));
				Runtime.objc_release(st);
			}
			Msg.vBool(r, S.setPresentsWithTransaction, false);
			CATransaction.commit();
			Runtime.objc_autoreleasePoolPop(pool);
		}
		// (iOS: the stack taken out of the UIView's layer on the main thread, as rooted)
		lock.acquire();
		var main = pending > 0 || ios && !st.isNull();
		lock.release();
		if (main) helder.os.OsThread.post(apply) else apply();
	}

	// (f split into layers: the units, whole and in one run of paint order,
	// each quad and tile group to its layer's place)
	function splitUp(f:CompositeFrame) {
		split = adopted;
		splitFrame = f;
		var n = f.batch.count, nf = f.nodes.length, nm = f.movers.length, src = f.batch.bytes, S = CompositeFrame.STRIDE;
		var top = [for (k in 0...nf) {
			var x = k;
			while (f.parents[x] >= 0)
				x = f.parents[x];
			x;
		}];
		inline function topMover(m:Int):Int {
			while (f.moverParent(m) >= 0)
				m = f.moverParent(m);
			return m;
		}
		// (each item's candidate: a scroller's top frame k, a mover nf + m, -1 none)
		var cands = nf + nm, first = [for (_ in 0...cands) -1], last = [for (_ in 0...cands) -1], count = [for (_ in 0...cands) 0];
		var ok = [for (c in 0...cands) c < nf ? f.parents[c] < 0 : f.moverParent(c - nf) < 0 && f.moverData[(c - nf) * CompositeFrame.MOVER + 2] == 0
			&& f.moverData[(c - nf) * CompositeFrame.MOVER + 1] < 0];
		// (a scroller's clip: x0, y0, x1, y1, its corners' radii, set once seen)
		var clips = [for (_ in 0...cands * 8) 0.0], clipped = [for (_ in 0...cands) false], why = [for (_ in 0...cands) ""];
		inline function clipOf(c:Int, x0:Float, y0:Float, x1:Float, y1:Float, r0:Float, r1:Float, r2:Float, r3:Float) {
			var k = 8 * c;
			if (!whole(x0) || !whole(y0) || !whole(x1) || !whole(y1) || x1 <= x0 || y1 <= y0) {
				if (ok[c]) why[c] = 'clip $x0 $y0 $x1 $y1';
				ok[c] = false;
			} else if (!clipped[c]) {
				clipped[c] = true;
				for (j => v in [x0, y0, x1, y1, r0, r1, r2, r3])
					clips[k + j] = v;
			} else {
				var same = true;
				for (j => v in [x0, y0, x1, y1, r0, r1, r2, r3])
					if (Math.abs(clips[k + j] - v) > 1e-3) same = false;
				if (!same && ok[c]) why[c] = 'clips ${clips.slice(k, k + 8)} and $x0 $y0 $x1 $y1 $r0 $r1 $r2 $r3';
				if (!same) ok[c] = false;
			}
		}
		var quadCand = [for (_ in 0...n) -1], groupCand = [for (_ in 0...f.groups.length) -1];
		var item = 0, g = 0, W = f.width, H = f.height;
		inline function seen(c:Int) {
			if (first[c] < 0) first[c] = item;
			last[c] = item;
			count[c]++;
		}
		// (the nodes' system layers: the item each is before, its scroller's
		// candidate; one in a mover moves as sampled, so that one is drawn)
		var ns = f.slots.length, sd = f.slotData, SD = CompositeFrame.SLOT, si = 0;
		var slotItem = [for (_ in 0...ns) 0], slotCand = [for (_ in 0...ns) -1];
		function slotsTo(i:Int, g:Int)
			while (si < ns && (sd[si * SD] < i || sd[si * SD] == i && sd[si * SD + 1] <= g)) {
				var o = si * SD, fr = Std.int(sd[o + 2]), m = Std.int(sd[o + 4]);
				slotItem[si] = item;
				if (m >= 0) {
					var k = nf + topMover(m);
					if (ok[k]) why[k] = "a system layer";
					ok[k] = false;
				} else if (fr >= 0) slotCand[si] = top[fr];
				si++;
			}
		for (i in 0...n + 1) {
			while (g < f.groups.length && f.groups[g] == i) {
				slotsTo(i, g);
				var o = g * CompositeFrame.GROUP, fr = Std.int(f.groupData[o]), c = Std.int(f.groupData[o + 1]);
				var k = top[fr];
				groupCand[g] = k;
				seen(k);
				if (c < 0 || top[c] != k) {
					var d = f.groupData;
					clipOf(k, d[o + 2], d[o + 3], d[o + 4], d[o + 5], d[o + 6], d[o + 7], d[o + 8], d[o + 9]);
				}
				item++;
				g++;
			}
			slotsTo(i, g);
			if (i == n) break;
			var fr = f.content[i], m = f.mover[i], c = f.clip[i], q = i * S;
			if (fr >= 0) {
				var k = top[fr];
				quadCand[i] = k;
				seen(k);
				if (c < 0 || top[c] != k)
					clipOf(k, src.getFloat(q + 160), src.getFloat(q + 164), src.getFloat(q + 168), src.getFloat(q + 172), src.getFloat(q + 176), src.getFloat(q + 180),
						src.getFloat(q + 184), src.getFloat(q + 188));
			} else if (m >= 0) {
				var tm = topMover(m), k = nf + tm;
				quadCand[i] = k;
				seen(k);
				// (nothing nested moving; a clip from outside it would not move with it: none but the window's)
				if (m != tm) ok[k] = false;
				if (f.clipMover[i] != tm
					&& (src.getFloat(q + 160) > 0 || src.getFloat(q + 164) > 0 || src.getFloat(q + 168) < W || src.getFloat(q + 172) < H
						|| src.getFloat(q + 176) > 0 || src.getFloat(q + 180) > 0 || src.getFloat(q + 184) > 0 || src.getFloat(q + 188) > 0)) ok[k] = false;
			}
			item++;
		}
		for (c in 0...cands)
			if (first[c] < 0 || last[c] - first[c] + 1 != count[c] || c < nf && !clipped[c]) {
				if (ok[c]) why[c] = first[c] < 0 ? "nothing" : !clipped[c] ? "no clip" : 'not one run (${count[c]} of ${last[c] - first[c] + 1})';
				ok[c] = false;
			}
		reasons = [for (c in 0...nf) if (!ok[c] && f.parents[c] < 0) why[c]];
		// (the units in paint order, their layers kept by their keys: the
		// scrollers' and movers' on layers of their own, the system layers
		// in none of theirs; one before an item before it)
		var ids = [for (c in 0...cands) if (ok[c] && !flat) c];
		// (a system layer in a scroller of a layer of its own, under its clip: in that one's)
		var attachedTo = [for (s in 0...ns) {
			var k = slotCand[s], o = s * SD, c = Std.int(sd[o + 3]), at = -1;
			if (!flat && k >= 0 && ok[k] && (c < 0 || top[c] != k)) {
				at = k;
				for (j in 0...8)
					if (Math.abs(sd[o + 12 + j] - clips[8 * k + j]) > 1e-3) at = -1;
			}
			at;
		}];
		var entries = ids.copy();
		if (!flat) for (s in 0...ns)
			if (attachedTo[s] < 0) entries.push(-1 - s);
		inline function startOf(e:Int):Float
			return e >= 0 ? first[e] : slotItem[-1 - e] - 0.5;
		entries.sort((a, b) -> startOf(a) < startOf(b) ? -1 : startOf(a) > startOf(b) ? 1 : 0);
		units.resize(0);
		free.resize(nf);
		for (k in 0...nf)
			free[k] = false;
		held.resize(nm);
		for (m in 0...nm)
			held[m] = false;
		var unitOf = [for (_ in 0...cands) -1];
		lock.acquire();
		contents.clear();
		lock.release();
		var keep = new haxe.ds.ObjectMap<Dynamic, Bool>();
		function slotPlane(s:Int):Plane {
			var sl = f.slots[s], p = kept.get(sl);
			if (p == null) kept.set(sl, p = new Plane(SLOT, sl));
			keep.set(sl, true);
			p.slot = sl;
			p.index = s;
			p.attached = -1;
			p.scale = f.scale;
			return p;
		}
		for (e in entries) {
			if (e < 0) {
				var p = slotPlane(-1 - e), o = (-1 - e) * SD;
				p.cx0 = sd[o + 12];
				p.cy0 = sd[o + 13];
				p.cx1 = sd[o + 14];
				p.cy1 = sd[o + 15];
				for (j in 0...4)
					p.radii[j] = sd[o + 16 + j];
				units.push(p);
				continue;
			}
			var c = e;
			var key:Dynamic = c < nf ? f.nodes[c] : f.movers[c - nf];
			var p = kept.get(key);
			if (p == null) kept.set(key, p = new Plane(c < nf ? SCROLL : MOVER, key));
			keep.set(key, true);
			p.index = c < nf ? c : c - nf;
			p.slots.resize(0);
			if (c < nf) {
				p.cx0 = clips[8 * c];
				p.cy0 = clips[8 * c + 1];
				p.cx1 = clips[8 * c + 2];
				p.cy1 = clips[8 * c + 3];
				for (j in 0...4)
					p.radii[j] = clips[8 * c + 4 + j];
				p.drawnX = f.offsets[2 * c];
				p.drawnY = f.offsets[2 * c + 1];
				p.scale = f.scale;
				lock.acquire();
				contents.set(f.nodes[c], p);
				lock.release();
			} else
				held[c - nf] = true;
			unitOf[c] = units.length;
			units.push(p);
		}
		for (s in 0...ns)
			if (attachedTo[s] >= 0) {
				var p = slotPlane(s), u = units[unitOf[attachedTo[s]]];
				p.attached = unitOf[attachedTo[s]];
				p.cx0 = u.cx0;
				p.cy0 = u.cy0;
				p.cx1 = u.cx1;
				p.cy1 = u.cy1;
				for (j in 0...4)
					p.radii[j] = u.radii[j];
				u.slots.push(p);
			}
		lock.acquire();
		for (u in units)
			u.follow = u.slots.copy();
		lock.release();
		single = units.length == 0 && !flat;
		for (k in 0...nf)
			free[k] = unitOf[top[k]] >= 0;
		for (key in [for (k in kept.keys()) k])
			if (!keep.exists(key)) {
				gone.push(kept.get(key).free());
				kept.remove(key);
				var o = overs.get(key);
				if (o != null) {
					gone.push(o.free());
					overs.remove(key);
				}
			}
		// (the places: the window's, each unit's and what is over it)
		order.resize(units.length * 2 + 1);
		order[0] = base;
		for (j in 0...units.length) {
			order[2 * j + 1] = units[j];
			order[2 * j + 2] = null;
		}
		// (what is drawn of no unit: over the units before it that it
		// overlaps, and over what over them it overlaps; else as low as
		// can be, as the system blends a layer's translucent edges in the
		// display's colours, not quite as UiShader does. What moves (a
		// thumb, a scroller's content or a mover's that is not a unit's)
		// is bounded by its clip where that stays, else overlaps everything)
		var unitStart = [for (u in 0...units.length) startOf(entries[u])];
		var unitBox = [for (u in 0...units.length) {
			var c = entries[u];
			if (c >= 0) c < nf ? [clips[8 * c], clips[8 * c + 1], clips[8 * c + 2], clips[8 * c + 3]] : [-1e9, -1e9, 1e9, 1e9] else {
				// (a system layer's: its box in its clip, the clip where it scrolls, everywhere where it moves)
				var o = (-1 - c) * SD;
				if (sd[o + 4] >= 0) [-1e9, -1e9, 1e9, 1e9] else if (sd[o + 2] >= 0) [sd[o + 12], sd[o + 13], sd[o + 14], sd[o + 15]] else [
					Math.max(sd[o + 12], Math.min(Math.min(sd[o + 6], sd[o + 8]), sd[o + 10])),
					Math.max(sd[o + 13], Math.min(Math.min(sd[o + 7], sd[o + 9]), sd[o + 11])),
					Math.min(sd[o + 14], Math.max(Math.max(sd[o + 6], sd[o + 8]), sd[o + 10] + sd[o + 8] - sd[o + 6])),
					Math.min(sd[o + 15], Math.max(Math.max(sd[o + 7], sd[o + 9]), sd[o + 11] + sd[o + 9] - sd[o + 7]))
				];
			}
		}];
		var boxes = [for (_ in 0...order.length * 4) 0.0], filled = [for (_ in 0...order.length) false];
		quadPlace.resize(n);
		groupPlace.resize(f.groups.length);
		item = 0;
		g = 0;
		function place(x0:Float, y0:Float, x1:Float, y1:Float):Int {
			var z = 0;
			for (u in 0...units.length)
				if (unitStart[u] < item && meets(unitBox[u], x0, y0, x1, y1)) z = 2 * u + 2;
			var zz = order.length - 1;
			while (zz > z) {
				if (filled[zz] && x0 < boxes[4 * zz + 2] && x1 > boxes[4 * zz] && y0 < boxes[4 * zz + 3] && y1 > boxes[4 * zz + 1]) {
					z = zz;
					break;
				}
				zz -= 2;
			}
			if (!filled[z]) {
				filled[z] = true;
				boxes[4 * z] = x0;
				boxes[4 * z + 1] = y0;
				boxes[4 * z + 2] = x1;
				boxes[4 * z + 3] = y1;
			} else {
				boxes[4 * z] = Math.min(boxes[4 * z], x0);
				boxes[4 * z + 1] = Math.min(boxes[4 * z + 1], y0);
				boxes[4 * z + 2] = Math.max(boxes[4 * z + 2], x1);
				boxes[4 * z + 3] = Math.max(boxes[4 * z + 3], y1);
			}
			return z;
		}
		for (i in 0...n + 1) {
			while (g < f.groups.length && f.groups[g] == i) {
				var k = groupCand[g];
				if (unitOf[k] >= 0) groupPlace[g] = 2 * unitOf[k] + 1 else {
					var o = g * CompositeFrame.GROUP, d = f.groupData, c = Std.int(d[o + 1]);
					groupPlace[g] = c < 0 ? place(d[o + 2], d[o + 3], d[o + 4], d[o + 5]) : place(-1e9, -1e9, 1e9, 1e9);
				}
				item++;
				g++;
			}
			if (i == n) break;
			var k = quadCand[i];
			if (k >= 0 && unitOf[k] >= 0) quadPlace[i] = 2 * unitOf[k] + 1 else {
				var q = i * S;
				// (what moves stays inside a clip that does not: a thumb in its scroller's, a scroller's content in its view)
				var fixed = f.clip[i] < 0 && (f.mover[i] < 0 || f.clipMover[i] < 0), b = f.thumb[i];
				// (a thumb on a unit's track: moving along it, over the unit and its own place)
				var k = b >= 0 && f.mover[i] < 0 && f.content[i] < 0 ? top[b >> 1] : -1;
				if (k >= 0 && unitOf[k] >= 0) {
					var ax = src.getFloat(q + 8), ay = src.getFloat(q + 12), bx = src.getFloat(q + 24), cy = src.getFloat(q + 44);
					quadPlace[i] = place(Math.min(ax + 1, clips[8 * k]), Math.min(ay + 1, clips[8 * k + 1]), Math.max(bx - 1, clips[8 * k + 2]),
						Math.max(cy - 1, clips[8 * k + 3]));
				} else if (!fixed && (f.thumb[i] >= 0 || f.mover[i] >= 0 || f.content[i] >= 0)) quadPlace[i] = place(-1e9, -1e9, 1e9, 1e9)
				else if (f.thumb[i] >= 0 || f.mover[i] >= 0 || f.content[i] >= 0)
					quadPlace[i] = place(src.getFloat(q + 160), src.getFloat(q + 164), src.getFloat(q + 168), src.getFloat(q + 172))
				else {
					var ax = src.getFloat(q + 8), ay = src.getFloat(q + 12), bx = src.getFloat(q + 24), by = src.getFloat(q + 28);
					var cx = src.getFloat(q + 40), cy = src.getFloat(q + 44), dx = bx + cx - ax, dy = by + cy - ay;
					// (less the pixel each quad is grown by for its anti-aliased edge, which covers nothing)
					quadPlace[i] = place(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + 1, Math.min(Math.min(ay, by), Math.min(cy, dy)) + 1,
						Math.max(Math.max(ax, bx), Math.max(cx, dx)) - 1, Math.max(Math.max(ay, by), Math.max(cy, dy)) - 1);
				}
			}
			item++;
		}
		// (what is over a unit: a layer of its own, kept by the unit's key)
		var keepOver = new haxe.ds.ObjectMap<Dynamic, Bool>();
		for (j in 0...units.length) {
			if (!filled[2 * j + 2]) continue;
			var key = units[j].key, p = overs.get(key);
			if (p == null) overs.set(key, p = new Plane(OVER, key));
			keepOver.set(key, true);
			order[2 * j + 2] = p;
		}
		for (key in [for (k in overs.keys()) k])
			if (!keepOver.exists(key)) {
				gone.push(overs.get(key).free());
				overs.remove(key);
			}
		// (a quad placed on a layer not made: none is, the window's has room)
		for (i in 0...n)
			if (order[quadPlace[i]] == null) quadPlace[i] = 0;
		for (k in 0...groupPlace.length)
			if (order[groupPlace[k]] == null) groupPlace[k] = 0;
	}

	static inline function whole(v:Float):Bool
		return Math.abs(v - Math.fround(Math.round(v))) < 1e-3 || Math.abs(v) >= 1e8;

	static inline function meets(b:Array<Float>, x0:Float, y0:Float, x1:Float, y1:Float):Bool
		return x0 < b[2] && x1 > b[0] && y0 < b[3] && y1 > b[1];

	// (whether v is a number Core Animation takes: a NaN or an infinity in a
	// layer's geometry is an exception it throws, out of a layout gone wrong)
	static inline function fine(v:Float):Bool
		return v == v && v > -1e15 && v < 1e15;

	// (a point, a rect, a size, an affine transform set on l by value: left
	// as it was for the frame where one is not fine)
	static function setPoint(l:Ptr, sel:Ptr, x:Float, y:Float)
		if (fine(x) && fine(y)) Arena.scoped(a -> {
			var p = a.make(CGPoint);
			p.value.x = x;
			p.value.y = y;
			Msg.vPoint(l, sel, p.value);
		});

	static function setRect(l:Ptr, sel:Ptr, x:Float, y:Float, w:Float, h:Float)
		if (fine(x) && fine(y) && fine(w) && fine(h) && w >= 0 && h >= 0) Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = y;
			r.value.size.width = w;
			r.value.size.height = h;
			Msg.vRect(l, sel, r.value);
		});

	static function setSize(l:Ptr, sel:Ptr, w:Float, h:Float)
		if (fine(w) && fine(h) && w >= 0 && h >= 0) Arena.scoped(a -> {
			var z = a.make(CGSize);
			z.value.width = w;
			z.value.height = h;
			Msg.vSize(l, sel, z.value);
		});

	static function setAffine(l:Ptr, a0:Float, b:Float, c:Float, d:Float)
		if (fine(a0) && fine(b) && fine(c) && fine(d)) Arena.scoped(a -> {
			var t = a.make(CGAffineTransform);
			t.value.a = a0;
			t.value.b = b;
			t.value.c = c;
			t.value.d = d;
			t.value.tx = 0;
			t.value.ty = 0;
			CaMsg.vAffine(l, ObjC.sel("setAffineTransform:"), t.value);
		});

	static inline var BASE = 0;
	static inline var OVER = 1;
	static inline var SCROLL = 2;
	static inline var MOVER = 3;
	static inline var SLOT = 4;
}

// (a layer: what it is (the window's, what is over a unit, a scroller's
// content, a mover), its key, its CAMetalLayer and a scroller's clip; its
// quads this frame and their bounds; its drawable's size and where it is in
// the frame's pixels; what it drew last, its quads in its pixels and runs)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CaLayers)
private class Plane {
	public final kind:Int;
	public final key:Dynamic;
	public var layer = Ptr.nil();
	public var clip = Ptr.nil();
	public var index = -1;
	// (a scroller's: its clip in the frame's pixels; its offsets as drawn, the UI's scale)
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	public var drawnX = 0.0;
	public var drawnY = 0.0;
	public var scale = 1.0;
	public var cs = 1.0;
	// (a system layer's: its slot, the unit it is in (-1: one of its own); a scroller's: those in it)
	public var slot:Null<helder.ui.LayerSlot> = null;
	public var attached = -1;
	public final slots:Array<Plane> = [];
	public var follow:Array<Plane> = [];
	// (a scroller's clip's corners' radii, its mask's layer and what it was drawn for)
	public final radii = [0.0, 0.0, 0.0, 0.0];
	public var maskLayer = Ptr.nil();
	final maskSet:Array<Float> = [for (_ in 0...6) -1];
	public final quads:Array<Int> = [];
	// (what its quads cover, in the frame's pixels: x0, y0, x1, y1 each)
	final rects:Array<Float> = [];
	// (a scroller's content's place as geometry set it, points)
	public var geomX = 0.0;
	public var geomY = 0.0;
	var x0 = 0.0;
	var y0 = 0.0;
	var x1 = 0.0;
	var y1 = 0.0;
	public var pw = 0;
	public var ph = 0;
	public var ox = 0.0;
	public var oy = 0.0;
	public var bytes = Bytes.alloc(0);
	public var len = 0;
	public final runs:Array<Int> = [];
	public final runTextures:Array<Null<Texture>> = [];
	var last = Bytes.alloc(0);
	var lastLen = -1;
	final lastRuns:Array<Int> = [];
	final lastTextures:Array<Null<Texture>> = [];
	var lastW = 0;
	var lastH = 0;
	// (what was set: hidden, the clip's frame, the layer's place, transform, opacity)
	var hidden = false;
	final set:Array<Float> = [for (_ in 0...16) -1e300];

	public function new(kind:Int, key:Dynamic) {
		this.kind = kind;
		this.key = key;
	}

	public function made():Bool
		return !layer.isNull() || !clip.isNull();

	// (what goes in the stack: a scroller's clip, a system layer's, else the layer)
	public function top():Ptr
		return clip.isNull() ? layer : clip;

	// (what it draws, where a press on it is not a view's under it: points, into r)
	public function hits(r:Array<Float>, cs:Float) {
		if (hidden) return;
		if (kind == CaLayers.OVER) {
			for (i in 0...rects.length)
				r.push(rects[i] / cs);
			return;
		}
		if (kind == CaLayers.SCROLL || kind == CaLayers.SLOT) {
			for (i in 0...4)
				r.push(i < 2 ? set[8 + i] : set[6 + i] + set[8 + i]);
			return;
		}
		if (kind == CaLayers.MOVER && quads.length > 0)
			for (v in [set[0], set[1], set[0] + pw / cs, set[1] + ph / cs])
				r.push(v);
	}

	// (a scroller's clip's layers: its content's, the system layers in it)
	public function inClip(ops:Array<Void->Void>) {
		var list = [layer].concat([for (sp in slots) if (!sp.slot.view) sp.slot.handle]), same = list.length == inside.length;
		if (same) for (i in 0...list.length)
			if (list[i] != inside[i]) same = false;
		if (same) return;
		inside = list;
		var c = clip;
		ops.push(() -> {
			var a = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
			for (l in list)
				Msg.vPtr(a, ObjC.sel("addObject:"), l);
			Msg.vPtr(c, ObjC.sel("setSublayers:"), a);
		});
	}

	var inside:Array<Ptr> = [];

	// (a system layer's own clip, made the first time, its layer in it)
	public function makeSlot(cs:Float, ops:Array<Void->Void>) {
		this.cs = cs;
		if (slot.view || attached >= 0 || !clip.isNull()) return;
		clip = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), S.layer));
		CaLayers.setPoint(clip, S.setAnchorPoint, 0, 0);
		Msg.vBool(clip, ObjC.sel("setMasksToBounds:"), true);
		var c = clip, l = slot.handle;
		ops.push(() -> Msg.vPtr(c, ObjC.sel("addSublayer:"), l));
	}

	// (what its mask masks: its clip, or a view's host)
	function masked():Ptr
		return slot != null && slot.view ? Msg.id(slot.handle, S.layer) : clip;

	// (a system layer at x, y points from its clip's, w x h, under a, b, c, d
	// and opacity alpha; a view at x, y, its host at its clip, hy: the host's
	// top from below (macOS' y up), or -1)
	public function placeSlot(x:Float, y:Float, w:Float, h:Float, a:Float, b:Float, c:Float, d:Float, alpha:Float, hx:Float, hy:Float, hw:Float,
			hh:Float, ops:Array<Void->Void>) {
		var sl = slot, on = sl.shown;
		var key = [x, y, w, h, a, b, c, d, alpha, hx, hy, hw, hh, on ? 1 : 0], same = true;
		for (i in 0...key.length)
			if (slotSet[i] != key[i]) same = false;
		if (same) return;
		for (i in 0...key.length)
			slotSet[i] = key[i];
		if (sl.view) {
			var host = sl.handle;
			ops.push(() -> {
				var v = sl.inner;
				CaLayers.setRect(host, S.setFrame, hx, hy, hw, hh);
				if (!v.isNull()) {
					CaLayers.setRect(v, S.setFrame, x, y, w, h);
					Msg.vBool(v, S.setHidden, !on);
				}
				Msg.vBool(host, S.setHidden, !on);
			});
			return;
		}
		var l = sl.handle;
		ops.push(() -> {
			CaLayers.setPoint(l, S.setAnchorPoint, 0, 0);
			CaLayers.setPoint(l, S.setPosition, x, y);
			CaLayers.setRect(l, S.setBounds, 0, 0, w, h);
			CaLayers.setAffine(l, a, b, c, d);
			if (CaLayers.fine(alpha)) CaMsg.vFloat32(l, ObjC.sel("setOpacity:"), alpha);
			Msg.vBool(l, S.setHidden, !on);
		});
	}

	final slotSet:Array<Float> = [for (_ in 0...14) -1e300];

	// (a system layer's view or layer, at where it was placed, moved by dx, dy points: a UIScrollView's, at once)
	public function shiftSlot(dx:Float, dy:Float) {
		var x = slotSet[0] + dx, y = slotSet[1] + dy, sl = slot;
		if (sl.view) {
			if (!sl.inner.isNull()) CaLayers.setRect(sl.inner, S.setFrame, x, y, slotSet[2], slotSet[3]);
		} else
			CaLayers.setPoint(sl.handle, S.setPosition, x, y);
	}

	public function begin() {
		quads.resize(0);
		rects.resize(0);
		x0 = y0 = 1e300;
		x1 = y1 = -1e300;
	}

	public function add(w:Int, out:Bytes) {
		quads.push(w);
		var q = w * CompositeFrame.STRIDE;
		var ax = out.getFloat(q + 8), ay = out.getFloat(q + 12), bx = out.getFloat(q + 24), by = out.getFloat(q + 28);
		var cx = out.getFloat(q + 40), cy = out.getFloat(q + 44), dx = bx + cx - ax, dy = by + cy - ay;
		// (a quad of a layout gone wrong: drawn as the GPU draws it, nothing, bounding nothing)
		if (!CaLayers.fine(ax) || !CaLayers.fine(ay) || !CaLayers.fine(bx) || !CaLayers.fine(by) || !CaLayers.fine(cx) || !CaLayers.fine(cy)) return;
		if (kind == CaLayers.OVER || kind == CaLayers.BASE) {
			// (less the pixel each is grown by, inside its clip)
			rects.push(Math.max(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + 1, out.getFloat(q + 160)));
			rects.push(Math.max(Math.min(Math.min(ay, by), Math.min(cy, dy)) + 1, out.getFloat(q + 164)));
			rects.push(Math.min(Math.max(Math.max(ax, bx), Math.max(cx, dx)) - 1, out.getFloat(q + 168)));
			rects.push(Math.min(Math.max(Math.max(ay, by), Math.max(cy, dy)) - 1, out.getFloat(q + 172)));
		}
		x0 = Math.min(x0, Math.min(Math.min(ax, bx), Math.min(cx, dx)));
		y0 = Math.min(y0, Math.min(Math.min(ay, by), Math.min(cy, dy)));
		x1 = Math.max(x1, Math.max(Math.max(ax, bx), Math.max(cx, dx)));
		y1 = Math.max(y1, Math.max(Math.max(ay, by), Math.max(cy, dy)));
	}

	public function place(x:Float, y:Float, w:Int, h:Int) {
		ox = x;
		oy = y;
		pw = w;
		ph = h;
	}

	// (its drawable around its quads, on whole pixels: grown by 64 at a
	// time, kept while they fit in half of it, so that it is seldom made again)
	public function fit() {
		if (quads.length == 0 || x1 < x0 || y1 < y0) return;
		var nx = Math.ffloor(x0), ny = Math.ffloor(y0);
		var w = Std.int(Math.min(8192, Math.fceil(x1) - nx)), h = Std.int(Math.min(8192, Math.fceil(y1) - ny));
		inline function grown(v:Int):Int
			return Std.int(Math.min(8192, Math.ceil(v / 64) * 64));
		if (w > pw || w * 2 < pw) pw = grown(w);
		if (h > ph || h * 2 < ph) ph = grown(h);
		ox = nx;
		oy = ny;
	}

	// (its CAMetalLayer, and a scroller's clip, made the first time; its drawable's size)
	public function make(root:Ptr, scale:Float, ops:Array<Void->Void>) {
		cs = scale;
		if (layer.isNull()) {
			layer = Runtime.objc_retain(Msg.id(ObjC.cls("CAMetalLayer"), S.layer));
			Msg.vPtr(layer, ObjC.sel("setDevice:"), Msg.id(root, ObjC.sel("device")));
			Msg.vInt(layer, ObjC.sel("setPixelFormat:"), 80); // (BGRA8Unorm)
			Msg.vBool(layer, ObjC.sel("setOpaque:"), false);
			CaLayers.setPoint(layer, S.setAnchorPoint, 0, 0);
			if (kind == CaLayers.SCROLL) {
				clip = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), S.layer));
				CaLayers.setPoint(clip, S.setAnchorPoint, 0, 0);
				Msg.vBool(clip, ObjC.sel("setMasksToBounds:"), true);
				var l = layer, c = clip;
				ops.push(() -> Msg.vPtr(c, ObjC.sel("addSublayer:"), l));
			}
		}
		if (kind == CaLayers.BASE) return;
		if (set[14] != cs) {
			set[14] = cs;
			Msg.vFloat(layer, ObjC.sel("setContentsScale:"), cs);
		}
		if (set[12] != pw || set[13] != ph) {
			set[12] = pw;
			set[13] = ph;
			CaLayers.setSize(layer, ObjC.sel("setDrawableSize:"), pw, ph);
			var l = layer, w = pw / cs, h = ph / cs;
			ops.push(() -> CaLayers.setRect(l, S.setBounds, 0, 0, w, h));
		}
	}

	// (its drawables presented in the frame's transaction, else at once)
	public function presenting(on:Bool) {
		if (withTransaction == on) return;
		withTransaction = on;
		Msg.vBool(layer, S.setPresentsWithTransaction, on);
	}

	var withTransaction = false;

	public function show(on:Bool, ops:Array<Void->Void>) {
		if (kind == CaLayers.BASE || hidden == !on || layer.isNull()) {
			hidden = !on;
			return;
		}
		hidden = !on;
		var l = top();
		ops.push(() -> Msg.vBool(l, ObjC.sel("setHidden:"), !on));
	}

	// (its quads in its pixels, its runs; whether to draw them: other than drawn last, or sampling what was drawn into since)
	public function local(out:Bytes, textures:Array<Null<Texture>>, fresh:Null<Array<Texture>>):Bool {
		var S = CompositeFrame.STRIDE, n = quads.length * S;
		if (bytes.length < n) bytes = Bytes.alloc(n * 2);
		runs.resize(0);
		runTextures.resize(0);
		var w = pw, h = ph, k = 0;
		for (j in 0...quads.length) {
			var q = quads[j], o = j * S, t = textures[q];
			bytes.blit(o, out, q * S, S);
			for (c in 0...3) {
				var p = o + c * 16, X = bytes.getFloat(p + 8) - ox, Y = bytes.getFloat(p + 12) - oy;
				bytes.setFloat(p, X / w * 2 - 1);
				bytes.setFloat(p + 4, 1 - Y / h * 2);
				bytes.setFloat(p + 8, X);
				bytes.setFloat(p + 12, Y);
			}
			for (a in [160, 168, 208, 216]) {
				bytes.setFloat(o + a, bytes.getFloat(o + a) - ox);
				bytes.setFloat(o + a + 4, bytes.getFloat(o + a + 4) - oy);
			}
			if (bytes.getFloat(o + 192) != -1e9) {
				bytes.setFloat(o + 192, bytes.getFloat(o + 192) - ox);
				bytes.setFloat(o + 196, bytes.getFloat(o + 196) - oy);
			}
			if (runs.length == 0 || runTextures[runTextures.length - 1] != t) {
				runs.push(j);
				runs.push(1);
				runTextures.push(t);
			} else
				runs[runs.length - 1]++;
		}
		len = n;
		var same = n == lastLen && w == lastW && h == lastH && runs.length == lastRuns.length;
		if (same) {
			var i = 0;
			while (i < n) {
				if (last.getInt32(i) != bytes.getInt32(i)) {
					same = false;
					break;
				}
				i += 4;
			}
		}
		if (same) for (i in 0...runs.length)
			if (runs[i] != lastRuns[i] || i % 2 == 0 && runTextures[i >> 1] != lastTextures[i >> 1]) same = false;
		if (same && fresh != null) for (t in runTextures)
			if (t != null && fresh.indexOf(t) >= 0) same = false;
		if (same) return false;
		if (last.length < n) last = Bytes.alloc(bytes.length);
		last.blit(0, bytes, 0, n);
		lastLen = n;
		lastW = w;
		lastH = h;
		lastRuns.resize(0);
		for (v in runs)
			lastRuns.push(v);
		lastTextures.resize(0);
		for (t in runTextures)
			lastTextures.push(t);
		return true;
	}

	// (drawn again next frame: its drawable not drawn, or drawn by another)
	public function invalidate()
		lastLen = -1;

	// (the window's: drawn onto by the textured compositor meanwhile)
	public function reset() {
		lastLen = -1;
		withTransaction = false;
	}

	// (its mask's drawable sw x sh pixels for its clip of w x h, its corners
	// m pixels: whether to draw it, made or resized)
	public function masking(root:Ptr, sw:Float, sh:Float, w:Float, h:Float, m:Float, ops:Array<Void->Void>):Bool {
		var key = [sw, sh, w, h, m, cs], same = !maskLayer.isNull();
		for (i in 0...6)
			if (maskSet[i] != key[i]) same = false;
		if (same && !maskStale) return false;
		maskStale = false;
		if (maskLayer.isNull()) {
			var l = maskLayer = Runtime.objc_retain(Msg.id(ObjC.cls("CAMetalLayer"), S.layer));
			Msg.vPtr(l, ObjC.sel("setDevice:"), Msg.id(root, ObjC.sel("device")));
			Msg.vInt(l, ObjC.sel("setPixelFormat:"), 80);
			Msg.vBool(l, ObjC.sel("setOpaque:"), false);
			Msg.vBool(l, S.setPresentsWithTransaction, true);
			CaLayers.setPoint(l, S.setAnchorPoint, 0, 0);
			var nearest = ObjC.str("nearest");
			Msg.vPtr(l, ObjC.sel("setMagnificationFilter:"), nearest);
			Msg.vPtr(l, ObjC.sel("setMinificationFilter:"), nearest);
			ObjC.release(nearest);
			ops.push(() -> Msg.vPtr(masked(), ObjC.sel("setMask:"), l));
		}
		for (i in 0...6)
			maskSet[i] = key[i];
		var l = maskLayer, k = cs;
		Msg.vFloat(l, ObjC.sel("setContentsScale:"), k);
		CaLayers.setSize(l, ObjC.sel("setDrawableSize:"), sw, sh);
		// (the middle: a pixel's column and row, else the axis whole)
		var cx = sw < w ? m / sw : 0, cw = sw < w ? 1 / sw : 1, cy = sh < h ? m / sh : 0, ch = sh < h ? 1 / sh : 1;
		ops.push(() -> {
			CaLayers.setRect(l, ObjC.sel("setContentsCenter:"), cx, cy, cw, ch);
			CaLayers.setPoint(l, S.setPosition, 0, 0);
			CaLayers.setRect(l, S.setBounds, 0, 0, w / k, h / k);
		});
		return true;
	}

	public var maskStale = false;

	// (square again: no mask)
	public function unmask(ops:Array<Void->Void>) {
		if (maskLayer.isNull()) return;
		var l = maskLayer;
		maskLayer = Ptr.nil();
		maskSet[0] = -1;
		ops.push(() -> {
			Msg.vPtr(masked(), ObjC.sel("setMask:"), Ptr.nil());
			Runtime.objc_release(l);
		});
	}

	// (a scroller's clip at x, y, w x h points)
	public function clipTo(x:Float, y:Float, w:Float, h:Float, ops:Array<Void->Void>) {
		if (set[8] == x && set[9] == y && set[10] == w && set[11] == h) return;
		set[8] = x;
		set[9] = y;
		set[10] = w;
		set[11] = h;
		var c = clip;
		ops.push(() -> {
			CaLayers.setPoint(c, S.setPosition, x, y);
			CaLayers.setRect(c, S.setBounds, 0, 0, w, h);
		});
	}

	// (the layer at x, y points, under the transform a, b, c, d and opacity
	// alpha; ops null: at once, on the main thread's transaction)
	public function move(x:Float, y:Float, a:Float, b:Float, c:Float, d:Float, alpha:Float, cs:Float, ops:Null<Array<Void->Void>>) {
		var l = layer;
		if (set[0] != x || set[1] != y) {
			set[0] = x;
			set[1] = y;
			var f = () -> CaLayers.setPoint(l, S.setPosition, x, y);
			if (ops == null) {
				CATransaction.begin();
				f();
				CATransaction.commit(false);
			} else
				ops.push(f);
		}
		if (ops == null) return;
		if (set[2] != a || set[3] != b || set[4] != c || set[5] != d) {
			set[2] = a;
			set[3] = b;
			set[4] = c;
			set[5] = d;
			ops.push(() -> CaLayers.setAffine(l, a, b, c, d));
		}
		if (set[6] != alpha) {
			set[6] = alpha;
			var v = alpha;
			if (CaLayers.fine(v)) ops.push(() -> CaMsg.vFloat32(l, ObjC.sel("setOpacity:"), v));
		}
	}

	// (its layers let go: what removes and releases them, run in a
	// transaction after any that still names them)
	public function free():Void->Void {
		var c = clip, l = kind == CaLayers.BASE ? Ptr.nil() : layer, m = maskLayer, sl = slot;
		layer = clip = maskLayer = Ptr.nil();
		for (i in 0...slotSet.length)
			slotSet[i] = -1e300;
		return () -> {
			var host = sl != null && sl.view ? Msg.id(sl.handle, S.layer) : c;
			if (!m.isNull()) {
				Msg.vPtr(host, ObjC.sel("setMask:"), Ptr.nil());
				Runtime.objc_release(m);
			}
			// (a node's layer out of ours, if still in it; a view's host hidden, its platform's)
			if (sl != null && sl.view) Msg.vBool(sl.handle, S.setHidden, true);
			else if (sl != null && (c.isNull() || Msg.id(sl.handle, ObjC.sel("superlayer")) == c)) Msg.v(sl.handle, ObjC.sel("removeFromSuperlayer"));
			if (!c.isNull()) {
				Msg.v(c, ObjC.sel("removeFromSuperlayer"));
				Runtime.objc_release(c);
			} else if (!l.isNull()) Msg.v(l, ObjC.sel("removeFromSuperlayer"));
			if (!l.isNull()) Runtime.objc_release(l);
		}
	}
}

// (Core Animation's transactions)
@:hxmc.unsafe(gc)
private class CATransaction {
	public static function begin() {
		var t = ObjC.cls("CATransaction");
		Msg.v(t, ObjC.sel("begin"));
		Msg.vBool(t, ObjC.sel("setDisableActions:"), true);
	}

	// (flushed: a thread with no run loop, the render thread's, would leave
	// it for the next that has one; not inside UIKit's, which commits with its own)
	public static function commit(flush = true) {
		var t = ObjC.cls("CATransaction");
		Msg.v(t, ObjC.sel("commit"));
		if (flush) Msg.v(t, ObjC.sel("flush"));
	}
}

@:hxmc.unsafe(gc)
private class S {
	public static final layer = ObjC.sel("layer");
	public static final contentsScale = ObjC.sel("contentsScale");
	public static final bounds = ObjC.sel("bounds");
	public static final setBounds = ObjC.sel("setBounds:");
	public static final setPosition = ObjC.sel("setPosition:");
	public static final setAnchorPoint = ObjC.sel("setAnchorPoint:");
	public static final setPresentsWithTransaction = ObjC.sel("setPresentsWithTransaction:");
	public static final setFrame = ObjC.sel("setFrame:");
	public static final setHidden = ObjC.sel("setHidden:");
}

// (the message shapes beside Msg's: helder.os.objc.Sender)
@:build(helder.os.objc.Sender.build())
@:hxmc.unsafe(gc)
private class CaMsg {
	static function vAffine(self:Ptr, sel:Ptr, t:CGAffineTransform):Void;
	static function vFloat32(self:Ptr, sel:Ptr, a:Float32):Void;
	static function vPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64):Void;
}
#end
