package helder.ui.layers;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.ui.Node;
import sys.thread.Mutex;
import helder.async.Errors;

// A window's frame split into the system's layers (Layers' step 5), as
// apple.Layers hands them to Core Animation, android.Layers to SurfaceControl,
// windows.Layers to DirectComposition and linux.Layers to Wayland's subsurfaces:
// each frame, the program's and the compositor's alike, composed from the
// compositor's state (CompositeFrame) and split in paint order: the
// window's layer at the bottom; a layer of its own for each top-level
// scroller's content (its clip on whole pixels, rounded where the system
// can: rounds) and each top-level layer that moves on its own
// (helder.ui.Mover: of no scroller, nothing nested moving, its clips its
// own; one the system cannot move as it moves left out: unfit); each
// node's system layer (LayerSlot) at its place, in its scroller's clip or
// a clip of its own; over each of those, a layer of what is drawn over it
// (only what overlaps it, or what overlaps that: the rest stays below).
// The system's half (the layers, their buffers, the transaction) is the
// subclass's; HELDER_SYSTEM_LAYERS=flat puts all of it on the window's layer.
@:hxmc.unsafe(gc)
@:access(helder.ui.layers.CompositeFrame)
@:access(helder.ui.Node)
class LayerSplit {
	// (the frame split: whether it is the one adopted last)
	var adopted = 0;
	var split = -1;
	var splitFrame:Null<CompositeFrame> = null;
	var consumed = -1;
	// (per quad of the frame its layer's place in order, per tile group too;
	// the units (scrollers' and movers' layers) in order; per frame whether
	// on a layer of its own; per mover whether held)
	final quadPlace:Array<Int> = [];
	final groupPlace:Array<Int> = [];
	final units:Array<LayerPlane> = [];
	final free:Array<Bool> = [];
	final held:Array<Bool> = [];
	// (the layers by place: 0 the window's, 2j + 1 unit j's, 2j + 2 what is over it; kept by their keys)
	final order:Array<Null<LayerPlane>> = [];
	final base:LayerPlane;
	final kept = new haxe.ds.ObjectMap<Dynamic, LayerPlane>();
	final overs = new haxe.ds.ObjectMap<Dynamic, LayerPlane>();
	// (the layers let go since the last frame: removed with it, after its order)
	final gone:Array<Void->Void> = [];
	// (compose's: its quads, their sources, the offsets scrolls move by, runs;
	// the textures drawn into since the last split's frame)
	var out = Bytes.alloc(0);
	final sources:Array<Int> = [];
	final shifts:Array<Float> = [];
	final runTextures:Array<Null<Texture>> = [];
	final runs:Array<Int> = [];
	final quadTextures:Array<Null<Texture>> = [];
	var fresh:Null<Array<Texture>> = null;
	final lock = new Mutex();
	// (the scrollers' content layers by node: iOS's UIScrollViews follow them)
	final contents = new Map<Node, LayerPlane>();
	// (whether the system clips to rounded corners; the movers it cannot move
	// as they move, by key; off: the window's layer alone, for good)
	var rounds = true;
	var off = false;
	// (the pixels a clip's edges fall on a multiple of: Wayland's, whose
	// subsurfaces sit on whole points)
	var grid = 1.0;
	final unfit = new haxe.ds.ObjectMap<Dynamic, Bool>();
	// (a mover's layer kept by its node's key: a program's frame has Movers of its own)
	final moverKeys = new haxe.ds.ObjectMap<Node, MoverKey>();
	// (why each top-level scroller not on a layer of its own is not, at the last split: tests)
	@:noCompletion public var reasons(default, null):Array<String> = [];
	// (HELDER_SYSTEM_LAYERS=flat: all of it on the window's layer, as the
	// textured compositor draws it: the split's own check, SystemLayersWindow)
	static final flat = Sys.getEnv("HELDER_SYSTEM_LAYERS") == "flat";

	function new(base:LayerPlane) {
		this.base = base;
	}

	// whether the nodes' system layers and views go in the tree (not flat's)
	public static function slots():Bool
		return !flat;

	// whether the last frame split into the window's layer alone: the
	// frames are then drawn and presented as the textured compositor's, a
	// scene covering the window costing what it costs there (nothing to
	// compose again, no other buffer, no transaction)
	public var single(default, null) = false;

	// (the next frame onto the window's own layer whatever its split: a
	// new window's first, which the system waits for: Android's)
	public var priming(default, null) = false;

	// why the system's layers turned off for good while running (null: they
	// did not); a frame of the window's own wanted meanwhile (redraw)
	public var fell(default, null):Null<String> = null;
	public var redraw(default, null) = false;

	// (a frame drawn onto the window's layer: split, whether the next is single)
	public function check(f:CompositeFrame) {
		if (f.buffers.length == 0 || f.pipeline == null) return;
		if (split != adopted || splitFrame != f) splitUp(f);
	}

	// (a new frame of the program's: split again)
	public function adopt()
		adopted++;

	// frames shown
	public var frames(default, null) = 0;
	// layers and quads drawn in all (a scroll that only moves layers draws none)
	public var drawnTotal(default, null) = 0;
	public var quadsTotal(default, null) = 0;

	// (a layer of the system's, of kind and key)
	function plane(kind:Int, key:Dynamic):LayerPlane
		throw "helder.ui: LayerSplit.plane";

	// f's frame at the offsets now (per frame, x then y) and time t, its
	// overlay bars shown as shown has them (null: as drawn), drawn and
	// shown in one transaction; drawn: the program's own frame (its movers
	// as drawn). moves: the native views moved with it (render thread)
	public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {}

	// (the window's frames onto its own layer (off) or only into targets, the layers drawn from them (on))
	public function quiet(r:Replay, on:Bool) {}

	// the window's own frames drawn onto its layer for now (a frame read
	// back, or single): the layers hidden; the next show draws them again
	public function suspend() {}

	// (the program's thread, before its frame: what the system's layers need
	// made first; single where they cannot be)
	public function prepare() {}

	// (a frame of the window's own queued, on the render thread: what waited for it)
	public function windowShown() {}

	// the layers gone, the window's own frames shown as before (render thread)
	public function dispose() {}

	// a platform's scroll view moved the program's n to x, y, on the main thread (iOS)
	public function scrolled(n:Node, x:Float, y:Float) {}

	// the bytes of the layers' buffers, beside the window's own
	public function bytes():Float
		return 0;

	// (f composed at the offsets now (per frame, x then y) and time t, its
	// overlay bars shown as shown has them (null: as drawn), split: each
	// layer's quads this frame, the scrollers and movers on layers of their
	// own as drawn (drawn: the program's own frame, its movers as drawn),
	// the system moving them. The quads' count; fresh: what was drawn into
	// since the last frame split, null if nothing new)
	function compose(f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool):Int {
		if (split != adopted || splitFrame != f) splitUp(f);
		shifts.resize(0);
		for (v in now)
			shifts.push(v);
		for (u in units)
			if (u.kind == LayerPlane.SCROLL) {
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
			throw Errors.kept(e);
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
		fresh = consumed != adopted ? f.fresh : null;
		consumed = adopted;
		return n;
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
		var ok = [for (c in 0...cands) c < nf ? f.parents[c] < 0 && fits(f, c) : f.moverParent(c - nf) < 0 && f.moverData[(c - nf) * CompositeFrame.MOVER + 2] == 0
			&& f.moverData[(c - nf) * CompositeFrame.MOVER + 1] < 0 && !unfit.exists(moverKeys.get(f.movers[c - nf].node))];
		// (a scroller's clip: x0, y0, x1, y1, its corners' radii, set once seen)
		var clips = [for (_ in 0...cands * 8) 0.0], clipped = [for (_ in 0...cands) false], why = [for (_ in 0...cands) ""];
		inline function clipOf(c:Int, x0:Float, y0:Float, x1:Float, y1:Float, r0:Float, r1:Float, r2:Float, r3:Float) {
			var k = 8 * c;
			if (!whole(x0 / grid) || !whole(y0 / grid) || !whole(x1 / grid) || !whole(y1 / grid) || x1 <= x0 || y1 <= y0) {
				if (ok[c]) why[c] = 'clip $x0 $y0 $x1 $y1';
				ok[c] = false;
			} else if (!rounds && (r0 > 1e-3 || r1 > 1e-3 || r2 > 1e-3 || r3 > 1e-3)) {
				if (ok[c]) why[c] = "rounded";
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
		function slotPlane(s:Int):LayerPlane {
			var sl = f.slots[s], p = kept.get(sl);
			if (p == null) kept.set(sl, p = plane(LayerPlane.SLOT, sl));
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
			var key:Dynamic = c < nf ? f.nodes[c] : moverKey(f.movers[c - nf].node);
			var p = kept.get(key);
			if (p == null) kept.set(key, p = plane(c < nf ? LayerPlane.SCROLL : LayerPlane.MOVER, key));
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
				for (j in 0...4)
					p.ranges[j] = f.ranges[4 * c + j];
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
		single = off || units.length == 0 && !flat || f.backdrops > 0;
		for (k in 0...nf)
			free[k] = unitOf[top[k]] >= 0;
		for (key in [for (k in kept.keys()) k])
			if (!keep.exists(key)) {
				gone.push(kept.get(key).free());
				kept.remove(key);
				var mk = Std.downcast(key, MoverKey);
				// (one that turned stays drawn: it may turn again)
				if (mk != null && !unfit.exists(mk)) moverKeys.remove(mk.node);
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
			if (p == null) overs.set(key, p = plane(LayerPlane.OVER, key));
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

	// (whether the system can take top-level scroller frame c's content as a layer of its own)
	function fits(f:CompositeFrame, c:Int):Bool
		return true;

	function moverKey(n:Node):MoverKey {
		var k = moverKeys.get(n);
		if (k == null) moverKeys.set(n, k = new MoverKey(n));
		return k;
	}

	static inline function whole(v:Float):Bool
		return Math.abs(v - Math.fround(Math.round(v))) < 1e-3 || Math.abs(v) >= 1e8;

	static inline function meets(b:Array<Float>, x0:Float, y0:Float, x1:Float, y1:Float):Bool
		return x0 < b[2] && x1 > b[0] && y0 < b[3] && y1 > b[1];
}

// (a mover's node, as the key of its layer)
private class MoverKey {
	public final node:Node;

	public function new(n:Node)
		node = n;
}
