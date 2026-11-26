package helder.test;

import helder.test.Gen;
import helder.test.Property;
import helder.test.Test;

using StringTools;

// Properties on themselves: the classic failures shrunk to their smallest,
// a seed's cases the same on every run (and target: the snapshot is
// shared by host, wasm and interp), the store's failure replayed first,
// rejections' limit, a stateful case's steps shrunk, the report
function tests() {
	describe("shrinking", () -> {
		test("a list with an item over 100: [101]", () -> {
			equals(smallest(array(int(0, 1000)), xs -> assert(!Lambda.exists(xs, x -> x > 100))), [101]);
		});
		test("a string containing ab: \"ab\"", () -> {
			equals(smallest(string(pick(["a", "b", "c"])), s -> assert(!s.contains("ab"))), "ab");
		});
		test("a pair with a < b: {a: 0, b: 1}", () -> {
			var pair:Gen<{a:Int, b:Int}> = c -> {a: c.draw(int(0, 1000)), b: c.draw(int(0, 1000))};
			equals(smallest(pair, p -> assert(p.a >= p.b)), {a: 0, b: 1});
		});
		test("ints to the boundary, floats to round numbers, strings to a's", () -> {
			equals(smallest(int(-1000, 1000), x -> assert(x < 10)), 10);
			equals(smallest(int(-1000, -5), x -> assert(x > -100)), -100);
			equals(smallest(float(0, 100), x -> assert(x < 12.5)), 12.5);
			equals(smallest(string(), s -> assert(s.split("a").length < 4)), "aaa");
		});
		test("a sum: moved onto the last", () -> {
			var pair:Gen<Array<Int>> = c -> [c.draw(int(0, 9)), c.draw(int(0, 9))];
			equals(smallest(pair, p -> assert(p[0] + p[1] < 10)), [1, 9]);
		});
		test("a list's items: sorted", () -> {
			equals(smallest(array(int(0, 9)), xs -> assert(!(xs.contains(0) && xs.contains(5)))), [0, 5]);
		});
		test("a recursive value: the smallest tree", () -> {
			var tree = recursive(int(0, 9).map(Leaf), t -> c -> Node(c.draw(t), c.draw(t)), 4);
			equals(smallest(tree, t -> assert(depth(t) < 2)), Node(Leaf(0), Node(Leaf(0), Leaf(0))));
		});
		test("a throw is a failure too", () -> {
			equals(smallest(int(0, 100), x -> if (x > 41) throw new haxe.Exception("big")), 42);
		});
	});

	describe("replaying", () -> {
		test("a seed's cases and shrinking: the same", () -> {
			function run() {
				var r = Property.search(array(int(0, 100)), xs -> assert(xs.length < 4), {seed: 7}, "replaying 1");
				Property.remove("replaying 1");
				return {value: r.failed.value, choices: r.failed.choices.values, cases: r.cases};
			}
			var a = run();
			equals(run(), a);
			var again = Property.search(array(int(0, 100)), xs -> assert(xs.length < 4), {replay: a.choices.join(" ")}, "replaying 2");
			equals(again.failed.value, [0, 0, 0, 0]);
			Property.remove("replaying 2");
		});
		test("a seed's values: the snapshot's, on every target", () -> {
			var c = new Choices([], true, 12345);
			snapshot("values", {
				ints: [for (_ in 0...8) c.draw(int(-1000, 1000))],
				bools: [for (_ in 0...8) c.draw(bool())],
				picks: [for (_ in 0...4) c.draw(pick(["x", "y", "z"]))],
				lists: [for (_ in 0...3) c.draw(array(int(0, 9), 0, 6))],
				strings: [for (_ in 0...4) c.draw(string(null, 0, 8))],
				choices: c.values.length
			});
		});
		test("the store: a failure replayed first, gone once it passes", () -> {
			var key = "the store";
			var failing = int(0, 1000);
			var first = Property.search(failing, x -> assert(x < 500), {}, key);
			equals(first.failed.value, 500);
			equals(first.stored, false);
			var again = Property.search(failing, x -> assert(x < 500), {seed: 99}, key);
			equals(again.stored, true);
			equals(again.failed.value, 500);
			var fixed = Property.search(failing, x -> assert(x < 5000), {}, key);
			equals(fixed.failed, null);
			equals(Property.load(key), null);
		});
	});

	describe("outcomes", () -> {
		test("a generator rejecting everything fails the property", () -> {
			property(int(0, 9), x -> assume(false));
			property(int(0, 9).filter(x -> x > 100), x -> {});
			var f = Runner.take();
			equals(f.length, 2);
			for (s in f) assert(s.contains("the generator rejects too much"), s);
		});
		// (a soak's watchdog and its environment: natively)
		#if (hxmc.target != "wasm32-wasi")
		test("some rejected in a soak, past four for each case asked but not for each run: passes", () -> {
			Sys.putEnv("HELDER_PROPERTY_SOAK", "0.2");
			property(int(0, 9), x -> assume(x != 0), {cases: 2, limit: 5});
			Sys.putEnv("HELDER_PROPERTY_SOAK", "");
		});
		#end
		test("some rejected: passes", () -> {
			property(int(0, 9), x -> {
				assume(x % 2 == 0);
				equals(x % 2, 0);
			});
		});
		test("a property's failure: the smallest case, its failure, how to replay it", () -> {
			property(array(int(0, 1000)), xs -> assert(xs.length < 2, "two or more"));
			var f = Runner.take();
			equals(f.length, 1);
			var lines = f[0].split("\n");
			assert(lines[0].contains("Property.test.hx:"), lines[0]);
			assert(lines[0].contains(": property failed after "), lines[0]);
			equals(lines[1], "  [0, 0]");
			assert(lines[2].endsWith(": two or more"), lines[2]);
			assert(lines[3].startsWith('  replay: {replay: "1 0 1 0 0"}, or {seed: 0}'), lines[3]);
			forget();
		});
	});

	describe("stateful", () -> {
		test("a stack that drops its fourth item: four pushes", () -> {
			var m:Machine<{real:Array<Int>, model:Array<Int>}> = {
				setup: () -> {real: [], model: []},
				steps: [
					{name: "push", run: (s, c) -> {
						var v = c.draw(int(0, 9));
						if (s.real.length < 3) s.real.push(v);
						s.model.push(v);
					}},
					{name: "pop", run: (s, c) -> equals(s.real.pop(), s.model.pop()), when: s -> s.model.length > 0}
				],
				check: s -> equals(s.real.length, s.model.length)
			};
			var r = Property.search(c -> c, c -> Property.steps(m, c, 50, Equal.show), {}, "stateful 1");
			Property.remove("stateful 1");
			equals(r.failed.choices.notes, ["push(0)", "push(0)", "push(0)", "push(0)"]);
		});
		test("teardown after each case, a failing one too", () -> {
			var open = 0;
			stateful({
				setup: () -> ++open,
				steps: [{name: "fail", run: (s, c) -> assert(c.draw(int(0, 3)) < 3)}],
				teardown: s -> open--
			});
			equals(Runner.take().length, 1);
			equals(open, 0);
			forget();
		});
	});
}

private enum Tree {
	Leaf(v:Int);
	Node(a:Tree, b:Tree);
}

private function depth(t:Tree):Int
	return switch t {
		case Leaf(_): 0;
		case Node(a, b): 1 + Std.int(Math.max(depth(a), depth(b)));
	}

// (the running test's first property left out of the store)
private function forget()
	Property.remove("src/helder/test/Property.test.hx > " + Runner.running().fullName() + " #0");

// (the smallest failing value of a property that must fail, its key left out of the store)
private function smallest<T>(gen:Gen<T>, body:T->Void):Dynamic {
	var r = Property.search(gen, body, {}, "smallest");
	Property.remove("smallest");
	if (r.failed == null) fail("the property passed");
	return r.failed.value;
}
