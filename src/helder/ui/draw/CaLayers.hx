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
// scroller's content, under a CALayer masking to the scroller's clip (whole
// pixels, square: a rounded clip's corners are UiShader's, which Core
// Animation's would not match, so that scroller stays drawn), and for each
// top-level layer that moves on its own (helder.ui.Mover: of no scroller,
// nothing nested moving, its clips its own); over each of those, a
// CAMetalLayer of what is drawn over it (only what overlaps it, or what
// overlaps that: the rest stays below, so a scrollbar is the layer over its
// list, not the window's whole). A layer is drawn again only where its
// quads, its size or what it samples (CompositeFrame.fresh) changed: a
// scroll moves its content's layer and a mover's transform and opacity are
// its layer's, so neither draws. Each frame is one transaction: what it
// drew presented with it (presentsWithTransaction), the layers placed, the
// native views over its scrollers moved (where they move, on the main
// thread, an NSView's and a UIView's; on the render thread otherwise, the
// layers being ours), in order. A layer is drawn as the compositor draws
// (UiShader, its quads moved to the layer's pixels by whole pixels: the
// same pixels), single-sampled, onto a clear target, and blended by the
// system over what is under it, so the pixels are the textured
// compositor's within a level where translucent things meet. On iOS the
// content's layer follows its UIScrollView on the main thread as UIKit
// moves it (scrolled). HELDER_SYSTEM_LAYERS=0 keeps the window's one
// CAMetalLayer and the textured compositor; frames read back (a window's
// capture, headless runs, screenshots, golden images) never use these.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.Node)
class CaLayers {
	// (opt-in on iOS for now, HELDER_SYSTEM_LAYERS=1: a game's full-window
	// scene there, little-skies on the simulator, went from 5.6 to 18 ms a
	// frame with them; on by default on macOS)
	public static function wanted(device:Device):Bool {
		var env = Sys.getEnv("HELDER_SYSTEM_LAYERS");
		if (env == "0" || hxmc.Platform.apple() >= 1 && env != "1" && env != "flat") return false;
		return device.backend == Metal && device.surface.kind == Cocoa;
	}

	final root:Ptr; // the window's CAMetalLayer
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
		ios = hxmc.Platform.apple() >= 1;
		var fps = helder.os.OsThread.get(() -> {
			var v = device.surface.handle, s = ios ? Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")) : Msg.id(Msg.id(v, ObjC.sel("window")), ObjC.sel("screen"));
			s.isNull() ? 60 : Msg.i(s, ObjC.sel("maximumFramesPerSecond")).toInt();
		});
		period = 1 / (fps > 0 ? fps : 60);
		base = new Plane(BASE, null);
		base.layer = root;
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
		var b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0;
		CATransaction.begin();
		for (p in order) {
			if (p == null) continue;
			if (p.kind == BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != BASE) {
				p.show(false, ops);
				continue;
			}
			p.show(true, ops);
			p.make(root, cs, ops);
			if (!p.local(out, quadTextures, fresh)) continue;
			if (at + p.len <= f.capacity && draw(r, mb, f, p, b, at)) {
				at += p.len;
				drawnTotal++;
				quadsTotal += p.quads.length;
			} else
				p.invalidate();
		}
		geometry(f, now, cs, ops);
		for (g in gone)
			ops.push(g);
		gone.resize(0);
		CATransaction.commit();
		var presents = mb.takePresents();
		// (one commit a period: the display's pace where nothing waited for a drawable)
		var wait = committed + period * 0.9 - haxe.Timer.stamp();
		if (wait > 0) Sys.sleep(wait);
		commit(ops, presents, moves);
		committed = haxe.Timer.stamp();
		frames++;
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// (p's quads drawn onto its layer's next drawable, at buffer b's offset at)
	function draw(r:Replay, mb:MetalBackend, f:CompositeFrame, p:Plane, b:Buffer, at:Int):Bool {
		var c = commands;
		mb.planeFrame(p.layer);
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		if (!r.began) return false;
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(at);
		c.bytes(p.bytes, 0, p.len);
		c.end();
		var bg = f.background, opaque = p.kind == BASE;
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
		while (k < p.runs.length) {
			var t = p.runTextures[k >> 1];
			three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at + p.runs[k] * CompositeFrame.STRIDE, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(p.runs[k + 1]);
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
	// mover's by its transform and opacity sampled; the layers' order)
	function geometry(f:CompositeFrame, now:Array<Float>, cs:Float, ops:Array<Void->Void>) {
		var s = f.scale;
		for (u in units) {
			if (u.quads.length == 0) continue;
			if (u.kind == SCROLL) {
				var k = u.index, dx = (f.offsets[2 * k] - now[2 * k]) * s, dy = (f.offsets[2 * k + 1] - now[2 * k + 1]) * s;
				u.clipTo(u.cx0 / cs, u.cy0 / cs, (u.cx1 - u.cx0) / cs, (u.cy1 - u.cy0) / cs, ops);
				u.move((u.ox - u.cx0 + dx) / cs, (u.oy - u.cy0 + dy) / cs, 1, 0, 0, 1, 1, cs, ops);
			} else {
				var m = f.heldMoved, q = u.index * 7, a = m[q], b = m[q + 1], c = m[q + 2], d = m[q + 3];
				var px = u.ox / cs, py = u.oy / cs;
				u.move(a * px + c * py + m[q + 4] / cs, b * px + d * py + m[q + 5] / cs, a, b, c, d, m[q + 6], cs, ops);
			}
		}
		for (p in order)
			if (p != null && p.kind == OVER && p.quads.length > 0) p.move(p.ox / cs, p.oy / cs, 1, 0, 0, 1, 1, cs, ops);
		var list = [for (i in 1...order.length) if (order[i] != null && order[i].made()) order[i].top()];
		var same = list.length == shownOrder.length;
		if (same) for (i in 0...list.length)
			if (list[i] != shownOrder[i]) same = false;
		var sb = Msg.rect(root, S.bounds), sw = sb.size.width, sh = sb.size.height, st = stack;
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
		}
		ops.push(() -> {
			CaLayers.setPoint(st, S.setPosition, 0, 0);
			CaLayers.setRect(st, S.setBounds, 0, 0, sw, sh);
		});
		if (!same) {
			shownOrder = list;
			ops.push(() -> {
				var a = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
				for (l in list)
					Msg.vPtr(a, ObjC.sel("addObject:"), l);
				Msg.vPtr(st, ObjC.sel("setSublayers:"), a);
			});
		}
	}

	// (the frame's changes in one transaction: here, the layers being ours,
	// or on the main thread where a native view moves with them, and after
	// it while one runs there)
	function commit(ops:Array<Void->Void>, presents:Array<Ptr>, moves:Array<Void->Void>) {
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
		var main = moves.length > 0 || pending > 0;
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
		var p = contents.get(n), busy = pending > 0;
		lock.release();
		if (p == null || busy || p.layer.isNull()) return;
		var dx = (p.drawnX - x) * p.scale, dy = (p.drawnY - y) * p.scale;
		p.move((p.ox - p.cx0 + dx) / p.cs, (p.oy - p.cy0 + dy) / p.cs, 1, 0, 0, 1, 1, p.cs, null);
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
		lock.acquire();
		var busy = pending > 0;
		lock.release();
		if (busy) helder.os.OsThread.post(apply) else apply();
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
		// (a scroller's clip: x0, y0, x1, y1, set once seen)
		var clips = [for (_ in 0...cands * 4) 0.0], clipped = [for (_ in 0...cands) false], why = [for (_ in 0...cands) ""];
		inline function clipOf(c:Int, x0:Float, y0:Float, x1:Float, y1:Float, r0:Float, r1:Float, r2:Float, r3:Float) {
			if (r0 > 1e-3 || r1 > 1e-3 || r2 > 1e-3 || r3 > 1e-3 || !whole(x0) || !whole(y0) || !whole(x1) || !whole(y1) || x1 <= x0 || y1 <= y0) {
				if (ok[c]) why[c] = 'clip $x0 $y0 $x1 $y1 radii $r0 $r1 $r2 $r3';
				ok[c] = false;
			}
			else if (!clipped[c]) {
				clipped[c] = true;
				clips[4 * c] = x0;
				clips[4 * c + 1] = y0;
				clips[4 * c + 2] = x1;
				clips[4 * c + 3] = y1;
			} else if (Math.abs(clips[4 * c] - x0) > 1e-3 || Math.abs(clips[4 * c + 1] - y0) > 1e-3 || Math.abs(clips[4 * c + 2] - x1) > 1e-3
				|| Math.abs(clips[4 * c + 3] - y1) > 1e-3) {
				if (ok[c]) why[c] = 'clips ${clips.slice(4 * c, 4 * c + 4)} and $x0 $y0 $x1 $y1';
				ok[c] = false;
			}
		}
		var quadCand = [for (_ in 0...n) -1], groupCand = [for (_ in 0...f.groups.length) -1];
		var item = 0, g = 0, W = f.width, H = f.height;
		inline function seen(c:Int) {
			if (first[c] < 0) first[c] = item;
			last[c] = item;
			count[c]++;
		}
		for (i in 0...n + 1) {
			while (g < f.groups.length && f.groups[g] == i) {
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
		// (the units in paint order, their layers kept by their keys)
		var ids = [for (c in 0...cands) if (ok[c] && !flat) c];
		ids.sort((a, b) -> first[a] - first[b]);
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
		for (c in ids) {
			var key:Dynamic = c < nf ? f.nodes[c] : f.movers[c - nf];
			var p = kept.get(key);
			if (p == null) kept.set(key, p = new Plane(c < nf ? SCROLL : MOVER, key));
			keep.set(key, true);
			p.index = c < nf ? c : c - nf;
			if (c < nf) {
				p.cx0 = clips[4 * c];
				p.cy0 = clips[4 * c + 1];
				p.cx1 = clips[4 * c + 2];
				p.cy1 = clips[4 * c + 3];
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
		var unitStart = [for (u in 0...units.length) first[ids[u]]];
		var unitBox = [for (u in 0...units.length) {
			var c = ids[u];
			c < nf ? [clips[4 * c], clips[4 * c + 1], clips[4 * c + 2], clips[4 * c + 3]] : [-1e9, -1e9, 1e9, 1e9];
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
					quadPlace[i] = place(Math.min(ax + 1, clips[4 * k]), Math.min(ay + 1, clips[4 * k + 1]), Math.max(bx - 1, clips[4 * k + 2]),
						Math.max(cy - 1, clips[4 * k + 3]));
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

	// (a point, a rect, a size, an affine transform set on l by value)
	static function setPoint(l:Ptr, sel:Ptr, x:Float, y:Float)
		Arena.scoped(a -> {
			var p = a.make(CGPoint);
			p.value.x = x;
			p.value.y = y;
			Msg.vPoint(l, sel, p.value);
		});

	static function setRect(l:Ptr, sel:Ptr, x:Float, y:Float, w:Float, h:Float)
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = y;
			r.value.size.width = w;
			r.value.size.height = h;
			Msg.vRect(l, sel, r.value);
		});

	static function setSize(l:Ptr, sel:Ptr, w:Float, h:Float)
		Arena.scoped(a -> {
			var z = a.make(CGSize);
			z.value.width = w;
			z.value.height = h;
			Msg.vSize(l, sel, z.value);
		});

	static function setAffine(l:Ptr, a0:Float, b:Float, c:Float, d:Float)
		Arena.scoped(a -> {
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
	public final quads:Array<Int> = [];
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
		return !layer.isNull();

	// (what goes in the stack: a scroller's clip, else the layer)
	public function top():Ptr
		return clip.isNull() ? layer : clip;

	public function begin() {
		quads.resize(0);
		x0 = y0 = 1e300;
		x1 = y1 = -1e300;
	}

	public function add(w:Int, out:Bytes) {
		quads.push(w);
		var q = w * CompositeFrame.STRIDE;
		var ax = out.getFloat(q + 8), ay = out.getFloat(q + 12), bx = out.getFloat(q + 24), by = out.getFloat(q + 28);
		var cx = out.getFloat(q + 40), cy = out.getFloat(q + 44), dx = bx + cx - ax, dy = by + cy - ay;
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
		if (quads.length == 0) return;
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
			Msg.vBool(layer, S.setPresentsWithTransaction, true);
			CaLayers.setPoint(layer, S.setAnchorPoint, 0, 0);
			if (kind == CaLayers.SCROLL) {
				clip = Runtime.objc_retain(Msg.id(ObjC.cls("CALayer"), S.layer));
				CaLayers.setPoint(clip, S.setAnchorPoint, 0, 0);
				Msg.vBool(clip, ObjC.sel("setMasksToBounds:"), true);
				var l = layer, c = clip;
				ops.push(() -> Msg.vPtr(c, ObjC.sel("addSublayer:"), l));
			}
		}
		if (kind == CaLayers.BASE) {
			if (set[15] != 1) {
				set[15] = 1;
				Msg.vBool(layer, S.setPresentsWithTransaction, true);
			}
			return;
		}
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
		set[15] = -1;
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
			ops.push(() -> CaMsg.vFloat32(l, ObjC.sel("setOpacity:"), v));
		}
	}

	// (its layers let go: what removes and releases them, run in a
	// transaction after any that still names them)
	public function free():Void->Void {
		var c = clip, l = kind == CaLayers.BASE ? Ptr.nil() : layer;
		layer = clip = Ptr.nil();
		return () -> {
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
