package helder.ui.draw;

#if ((!helder.os || helder.os == "macos" || helder.os == "ios") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.metal.MetalBackend;
import helder.os.objc.*;
import hxmc.unsafe.*;

// The system's compositor on macOS and iOS (Layers' step 5): a window's
// layers handed to Core Animation. Each frame, the program's and the
// compositor's alike, is composed from the compositor's state
// (CompositeFrame) and split into layers in paint order (LayerSplit): the
// window's CAMetalLayer at the bottom; a CAMetalLayer of its own for each
// top-level scroller's content, under a CALayer clipping to the scroller's clip
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
class CaLayers extends LayerSplit {
	public static function wanted(device:Device):Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && device.backend == Metal && device.surface.kind == Cocoa;

	final root:Ptr; // the window's CAMetalLayer
	final view:Ptr; // its view
	var stack = Ptr.nil(); // over its contents, the layers in order
	final ios:Bool;
	// (the display's period: commits no closer)
	final period:Float;
	var committed = -1e9;
	var shownOrder:Array<Ptr> = [];
	final commands = new Commands();
	var ring = 0;
	// (main-thread commits not yet run: what follows waits its turn)
	var pending = 0;
	// (iOS: the stack put into the window's UIView's layer this frame. Its
	// commit lays that view out, which UIKit allows on the main thread alone)
	var rooted = false;

	public function new(device:Device) {
		super(new Plane(LayerPlane.BASE, null));
		root = device.surface.display;
		view = device.surface.handle;
		ios = hxmc.Platform.apple() >= 1;
		var fps = helder.os.OsThread.get(() -> {
			var v = device.surface.handle, s = ios ? Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")) : Msg.id(Msg.id(v, ObjC.sel("window")), ObjC.sel("screen"));
			s.isNull() ? 60 : Msg.i(s, ObjC.sel("maximumFramesPerSecond")).toInt();
		});
		period = 1 / (fps > 0 ? fps : 60);
		(cast base : Plane).layer = root;
	}

	override function plane(kind:Int, key:Dynamic):LayerPlane
		return new Plane(kind, key);

	override public function quiet(r:Replay, on:Bool)
		(cast r.impl : MetalBackend).quiet = on;

	// (each drawable kept up to two)
	override public function bytes():Float {
		var b = 0.0;
		for (p in kept)
			b += p.pw * p.ph * 4.0 * 2;
		for (p in overs)
			b += p.pw * p.ph * 4.0 * 2;
		return b;
	}

	// (moves on the main thread)
	override public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null) return;
		var mb:MetalBackend = cast r.impl, pool = Runtime.objc_autoreleasePoolPush();
		try compose(f, now, t, shown, drawn) catch (e:haxe.Exception) {
			Runtime.objc_autoreleasePoolPop(pool);
			throw e;
		}
		var cs = Msg.f(root, S.contentsScale), ops:Array<Void->Void> = [];
		var b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0, toDraw:Array<Plane> = [];
		CATransaction.begin();
		for (q in order) {
			if (q == null) continue;
			var p:Plane = cast q;
			// (a system layer: its clip and its mask; placed by geometry)
			if (p.kind == LayerPlane.SLOT) {
				p.makeSlot(cs, ops);
				if (at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, p, b, at, ops)) at += CompositeFrame.STRIDE;
				continue;
			}
			for (s in p.slots) {
				var sp:Plane = cast s;
				sp.makeSlot(cs, ops);
				if (at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, sp, b, at, ops)) at += CompositeFrame.STRIDE;
			}
			if (p.kind == LayerPlane.BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != LayerPlane.BASE) {
				p.show(false, ops);
				continue;
			}
			p.show(true, ops);
			p.make(root, cs, ops);
			if (p.kind == LayerPlane.SCROLL && at + CompositeFrame.STRIDE <= f.capacity && mask(r, mb, f, p, b, at, ops)) at += CompositeFrame.STRIDE;
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
			if (at + p.len <= f.capacity && draw(r, mb, f, p.layer, p.bytes, p.len, p.runs, p.runTextures, p.kind == LayerPlane.BASE, b, at, direct)) {
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
		if (big <= 1e-3 || p.kind == LayerPlane.SLOT && !p.slot.view && p.attached >= 0) {
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
		for (q in units) {
			var u:Plane = cast q;
			if (u.kind == LayerPlane.SLOT) {
				slotAt(f, u, null, now, cs, sh, ops);
				continue;
			}
			if (u.quads.length == 0) continue;
			if (u.kind == LayerPlane.SCROLL) {
				var k = u.index, dx = (f.offsets[2 * k] - now[2 * k]) * s, dy = (f.offsets[2 * k + 1] - now[2 * k + 1]) * s;
				u.clipTo(u.cx0 / cs, u.cy0 / cs, (u.cx1 - u.cx0) / cs, (u.cy1 - u.cy0) / cs, ops);
				u.move(u.geomX = (u.ox - u.cx0 + dx) / cs, u.geomY = (u.oy - u.cy0 + dy) / cs, 1, 0, 0, 1, 1, cs, ops);
				for (sp in u.slots)
					slotAt(f, cast sp, u, now, cs, sh, ops);
				u.inClip(ops);
			} else {
				var m = f.heldMoved, q = u.index * 7, a = m[q], b = m[q + 1], c = m[q + 2], d = m[q + 3];
				var px = u.ox / cs, py = u.oy / cs;
				u.move(a * px + c * py + m[q + 4] / cs, b * px + d * py + m[q + 5] / cs, a, b, c, d, m[q + 6], cs, ops);
			}
		}
		for (q in order)
			if (q != null && q.kind == LayerPlane.OVER && q.quads.length > 0) (cast q : Plane).move(q.ox / cs, q.oy / cs, 1, 0, 0, 1, 1, cs, ops);
		// (in order, split at each view: the layers under it, then those over it, up to the next)
		var segments:Array<Array<Ptr>> = [[]], hosts:Array<Ptr> = [], hits:Array<Array<Float>> = [];
		for (i in 1...order.length) {
			var p:Plane = cast order[i];
			if (p == null) continue;
			if (p.kind == LayerPlane.SLOT && p.slot.view) {
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
		if (!(w > 0) || !(h > 0) || !LayerPlane.fine(w) || !LayerPlane.fine(h)) return;
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
	override public function scrolled(n:Node, x:Float, y:Float) {
		if (!ios) return;
		lock.acquire();
		var p:Plane = cast contents.get(n), busy = pending > 0, follow = p == null ? [] : p.follow;
		lock.release();
		if (p == null || busy || p.layer.isNull()) return;
		var dx = (p.drawnX - x) * p.scale, dy = (p.drawnY - y) * p.scale;
		var nx = (p.ox - p.cx0 + dx) / p.cs, ny = (p.oy - p.cy0 + dy) / p.cs;
		p.move(nx, ny, 1, 0, 0, 1, 1, p.cs, null);
		if (follow.length == 0) return;
		CATransaction.begin();
		for (sp in follow)
			(cast sp : Plane).shiftSlot(nx - p.geomX, ny - p.geomY);
		CATransaction.commit(false);
	}

	// (its drawables presented as before, the textured compositor's)
	override public function suspend() {
		if (stack.isNull() && (cast base : Plane).layer.isNull()) return;
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

	// (after the main thread's commits still to run)
	override public function dispose() {
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

	// (a point, a rect, a size, an affine transform set on l by value: left
	// as it was for the frame where one is not fine)
	static function setPoint(l:Ptr, sel:Ptr, x:Float, y:Float)
		if (LayerPlane.fine(x) && LayerPlane.fine(y)) Arena.scoped(a -> {
			var p = a.make(CGPoint);
			p.value.x = x;
			p.value.y = y;
			Msg.vPoint(l, sel, p.value);
		});

	static function setRect(l:Ptr, sel:Ptr, x:Float, y:Float, w:Float, h:Float)
		if (LayerPlane.fine(x) && LayerPlane.fine(y) && LayerPlane.fine(w) && LayerPlane.fine(h) && w >= 0 && h >= 0) Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = y;
			r.value.size.width = w;
			r.value.size.height = h;
			Msg.vRect(l, sel, r.value);
		});

	static function setSize(l:Ptr, sel:Ptr, w:Float, h:Float)
		if (LayerPlane.fine(w) && LayerPlane.fine(h) && w >= 0 && h >= 0) Arena.scoped(a -> {
			var z = a.make(CGSize);
			z.value.width = w;
			z.value.height = h;
			Msg.vSize(l, sel, z.value);
		});

	static function setAffine(l:Ptr, a0:Float, b:Float, c:Float, d:Float)
		if (LayerPlane.fine(a0) && LayerPlane.fine(b) && LayerPlane.fine(c) && LayerPlane.fine(d)) Arena.scoped(a -> {
			var t = a.make(CGAffineTransform);
			t.value.a = a0;
			t.value.b = b;
			t.value.c = c;
			t.value.d = d;
			t.value.tx = 0;
			t.value.ty = 0;
			CaMsg.vAffine(l, ObjC.sel("setAffineTransform:"), t.value);
		});

}

// (a layer as Core Animation's: its CAMetalLayer, a scroller's clip and its
// mask, what was set on them)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CaLayers)
private class Plane extends LayerPlane {
	public var layer = Ptr.nil();
	public var clip = Ptr.nil();
	// (a scroller's clip's mask's layer and what it was drawn for)
	public var maskLayer = Ptr.nil();
	final maskSet:Array<Float> = [for (_ in 0...6) -1];
	// (what was set: hidden, the clip's frame, the layer's place, transform, opacity)
	var hidden = false;
	final set:Array<Float> = [for (_ in 0...16) -1e300];

	public function made():Bool
		return !layer.isNull() || !clip.isNull();

	// (what goes in the stack: a scroller's clip, a system layer's, else the layer)
	public function top():Ptr
		return clip.isNull() ? layer : clip;

	// (what it draws, where a press on it is not a view's under it: points, into r)
	public function hits(r:Array<Float>, cs:Float) {
		if (hidden) return;
		if (kind == LayerPlane.OVER) {
			for (i in 0...rects.length)
				r.push(rects[i] / cs);
			return;
		}
		if (kind == LayerPlane.SCROLL || kind == LayerPlane.SLOT) {
			for (i in 0...4)
				r.push(i < 2 ? set[8 + i] : set[6 + i] + set[8 + i]);
			return;
		}
		if (kind == LayerPlane.MOVER && quads.length > 0)
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
			if (LayerPlane.fine(alpha)) CaMsg.vFloat32(l, ObjC.sel("setOpacity:"), alpha);
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

	// (the window's: drawn onto by the textured compositor meanwhile)
	override public function reset() {
		super.reset();
		withTransaction = false;
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
			if (kind == LayerPlane.SCROLL) {
				clip = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), S.layer));
				CaLayers.setPoint(clip, S.setAnchorPoint, 0, 0);
				Msg.vBool(clip, ObjC.sel("setMasksToBounds:"), true);
				var l = layer, c = clip;
				ops.push(() -> Msg.vPtr(c, ObjC.sel("addSublayer:"), l));
			}
		}
		if (kind == LayerPlane.BASE) return;
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
		if (kind == LayerPlane.BASE || hidden == !on || layer.isNull()) {
			hidden = !on;
			return;
		}
		hidden = !on;
		var l = top();
		ops.push(() -> Msg.vBool(l, ObjC.sel("setHidden:"), !on));
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
			if (LayerPlane.fine(v)) ops.push(() -> CaMsg.vFloat32(l, ObjC.sel("setOpacity:"), v));
		}
	}

	// (its layers let go: what removes and releases them, run in a
	// transaction after any that still names them)
	override public function free():Void->Void {
		var c = clip, l = kind == LayerPlane.BASE ? Ptr.nil() : layer, m = maskLayer, sl = slot;
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
