package viewer;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import viewer.Decode.Decoded;

// DecodeCache: the wanted decoded nearest first, a few at a time; over
// the budget the farthest go (the unwanted first), never the one shown;
// a budget too small for every neighbour does not decode them again and
// again; a dropped file decoded again; and against a map (a stateful
// property: wants, decodes landing, drops and budgets)
function tests() {
	test("DecodeCache against a map: the same decodes, promotions and evictions", () -> stateful({
		setup: () -> new Model(),
		steps: [
			{name: "want", run: (m, c) -> m.want(c.draw(array(pick(PATHS), 0, 6)))},
			{name: "land", run: (m, c) -> m.land(c.draw(int(0, 1 << 20))), when: m -> m.pending.length > 0},
			{name: "drop", run: (m, c) -> m.drop(c.draw(pick(PATHS)))},
			{name: "budget", run: (m, c) -> m.budget(c.draw(int(1, 16)) * 50)}
		],
		check: m -> m.check()
	}, {cases: 150, steps: 40}));

	describe("DecodeCache", () -> {
		// (decodes that land when told: each a frame of size bytes)
		var pending:Array<{path:String, done:Decoded->Void}> = [];
		var decoded:Array<String> = [];
		function decode(path:String, side:Int, done:Decoded->Void) {
			decoded.push(path);
			pending.push({path: path, done: done});
		}
		function land(?path:String) {
			var i = 0;
			if (path != null) for (k in 0...pending.length) if (pending[k].path == path) i = k;
			var p = pending.splice(i, 1)[0];
			p.done(image(100));
		}
		beforeEach(() -> {
			pending = [];
			decoded = [];
		});
		test("a key's path with a line break in its name: kept whole, its page apart", () -> {
			var name = "a\r\nb 2.jpg";
			equals(Decode.parseKey(Decode.key(name)), {path: name, page: 0});
			equals(Decode.parseKey(Decode.key(name, 3)), {path: name, page: 3});
		});
		test("nearest first, two at a time", () -> {
			var c = new DecodeCache(decode, 1000);
			c.want(["a", "b", "c", "d"]);
			equals(decoded, ["a", "b"]);
			land("a");
			equals(decoded, ["a", "b", "c"]);
			land();
			land();
			equals(decoded, ["a", "b", "c", "d"]);
			assert(c.get("a") != null);
		});
		test("over the budget: the unwanted, then the farthest; never the one shown", () -> {
			var c = new DecodeCache(decode, 350);
			c.want(["a", "b", "c"]);
			land();
			land();
			land();
			equals(c.used, 300.0);
			// (the next image: a is now the farthest, x the one shown)
			c.want(["b", "c", "x", "a"]);
			land("x");
			equals(c.used, 300.0);
			equals(c.get("a"), null);
			assert(c.get("b") != null && c.get("c") != null && c.get("x") != null);
			// (an unwanted one goes before a far wanted one)
			c.want(["b", "x"]);
			c.budget = 250;
			c.want(["b", "x"]);
			equals(c.get("c"), null);
			assert(c.get("b") != null && c.get("x") != null);
			// (the one shown stays even alone over the budget)
			c.budget = 50;
			c.want(["x"]);
			assert(c.get("x") != null);
			equals(c.get("b"), null);
		});
		test("a budget too small for the neighbours: no decode loop", () -> {
			var c = new DecodeCache(decode, 250);
			c.want(["a", "b", "c"]);
			land();
			land();
			land();
			equals(decoded, ["a", "b", "c"]);
			equals(pending.length, 0);
			equals(c.used <= 250, true);
		});
		test("refine: decoded again at a larger side, the smaller one kept meanwhile", () -> {
			var sides = [];
			var c = new DecodeCache((path, side, done) -> {
				sides.push(side);
				var w = side == 0 ? 1000 : side;
				done({width: 1000, height: 1000, pixelsWidth: w, pixelsHeight: w, frames: [{pixels: new hxmc.Buffer(16), delay: 0.0}], repetitions: 0, format: "JPEG", fileSize: 1, page: 0, pages: 1, error: null, errorKind: ""});
			}, 1000);
			c.side = 250;
			c.want(["a"]);
			equals(c.get("a").pixelsWidth, 250);
			equals(c.refine("a", 200), false);
			equals(c.refine("a", 500), true);
			equals(c.get("a").pixelsWidth, 500);
			equals(c.refine("a", 0), true);
			equals(c.get("a").pixelsWidth, 1000);
			equals(c.refine("a", 0), false);
			equals(sides, [250, 500, 0]);
		});
		test("the one shown alone over the budget: those no longer wanted, not started, forgotten", () -> {
			var c = new DecodeCache(decode, 50);
			c.parallel = 1;
			c.want(["b", "a", "c", "d"]);
			land("b");
			c.want(["b"]);
			equals([c.has("c"), c.has("d")], [false, false]);
		});
		test("dropped (changed on disk): decoded again when wanted", () -> {
			var c = new DecodeCache(decode, 1000);
			c.want(["a"]);
			land();
			c.drop("a");
			equals(c.get("a"), null);
			c.want(["a"]);
			equals(decoded, ["a", "a"]);
		});
	});
}

private function image(bytes:Int):Decoded
	return {
		width: 1, height: 1, pixelsWidth: 1, pixelsHeight: 1, frames: [{pixels: new hxmc.Buffer(bytes), delay: 0.0}], repetitions: 0,
		format: "PNG", fileSize: bytes, page: 0, pages: 1, error: null, errorKind: ""
	};

private final PATHS = ["a", "b", "c", "d", "e", "f", "g"];

// (an entry of the model: waiting to start, running, decoded, or evicted
// while wanted (not decoded again until the order changes))
private enum State {
	Waiting;
	Running;
	Decoded;
	Evicted;
}

// (the cache and its model: each path's state, the decodes under way in
// the order they started, every image 100 bytes)
private class Model {
	public final pending:Array<{path:String, done:Decoded->Void}> = [];
	final real:DecodeCache;
	final states = new Map<String, State>();
	// (the model's decodes under way: their path, still the entry's)
	final running:Array<{path:String, live:Bool}> = [];
	var order:Array<String> = [];
	var limit = 350.0;

	public function new()
		real = new DecodeCache((path, side, done) -> pending.push({path: path, done: done}), 350);

	public function want(paths:Array<String>) {
		var unique = [];
		for (p in paths)
			if (!unique.contains(p)) unique.push(p);
		real.want(unique);
		order = unique;
		for (p => s in states)
			if (s == Evicted) states.remove(p);
		for (p in order)
			if (!states.exists(p)) states.set(p, Waiting);
		evict();
		pump();
	}

	public function land(k:Int) {
		k %= pending.length;
		var p = pending.splice(k, 1)[0], r = running.splice(k, 1)[0];
		p.done(image(100));
		if (r.live) {
			states.set(r.path, Decoded);
			evict();
		}
		pump();
	}

	public function drop(path:String) {
		real.drop(path);
		states.remove(path);
		for (r in running)
			if (r.path == path) r.live = false;
	}

	public function budget(b:Float) {
		real.budget = limit = b;
		want(order);
	}

	public function check() {
		equals([for (p in pending) p.path], [for (r in running) r.path], "the decodes started");
		// (which of the unwanted goes first is the map's order: their count the same, the real's taken)
		var unwanted = [for (p => s in states) if (s == Decoded && !order.contains(p)) p];
		var kept = [for (p in PATHS) if (real.get(p) != null && !order.contains(p)) p];
		equals(kept.length, unwanted.length, "the unwanted decoded kept");
		for (p in unwanted)
			states.remove(p);
		for (p in kept)
			states.set(p, Decoded);
		for (p in PATHS) {
			var s = states.get(p);
			equals(real.has(p), s != null, '$p kept');
			equals(real.get(p) != null, s == Decoded, '$p decoded');
		}
		equals(real.used, 100.0 * Lambda.count(states, s -> s == Decoded), "used");
		var shown = order.length > 0 && states.get(order[0]) == Decoded ? 1 : 0;
		assert(real.used <= limit || real.used == 100 * shown, 'used ${real.used} over ${limit}');
	}

	// (the farthest decoded over the budget, the unwanted first; the one shown never)
	function evict() {
		while (100.0 * Lambda.count(states, s -> s == Decoded) > limit) {
			var victim:Null<String> = null, rank = -1;
			for (p => s in states) {
				if (s != Decoded) continue;
				var r = order.indexOf(p);
				if (r == 0) continue;
				var k = r < 0 ? 1 << 30 : r;
				if (k > rank) {
					rank = k;
					victim = p;
				}
			}
			if (victim == null) break;
			if (rank < 1 << 30) states.set(victim, Evicted) else states.remove(victim);
		}
		for (p => s in states)
			if (s == Waiting && !order.contains(p)) states.remove(p);
	}

	// (the next wanted waiting, two at a time)
	function pump() {
		for (p in order) {
			if (running.length >= 2) return;
			if (states.get(p) != Waiting) continue;
			states.set(p, Running);
			running.push({path: p, live: true});
		}
	}
}

