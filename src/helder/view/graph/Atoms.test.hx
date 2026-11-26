package helder.view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// (made at the module's top level: the default store their home)
final count = signal(0);
final double = memo(() -> count() * 2);
// (an answer each store asks for: the first answered by hand, the next never)
final loads:Array<Later<Int>> = [];
final slow = memo(() -> {
	var l = new Later<Int>();
	if (count() == 0) l.resolve(0) else loads.push(l);
	l;
});

// (f with top-level effects recorded for the stores made in it, let go after)
function recording(f:Void->Void) {
	Atoms.record = true;
	try f() catch (e:haxe.Exception) {
		Atoms.forget();
		throw e;
	}
	Atoms.forget();
}

// (stores a and b, let go after f)
function two(f:(Atoms, Atoms) -> Void) {
	var a = new Atoms("a"), b = new Atoms("b");
	f(a, b);
	a.dispose();
	b.dispose();
	flush();
}

// (what f returns, or the message it throws)
function attempt(f:Void->Dynamic):Dynamic
	return try f() catch (e:haxe.Exception) e.message;

// atoms in stores (Jotai's): each store its own nodes of them, the default
// the atoms themselves; one graph, a flush's transactions a store each
function tests() {
	afterEach(() -> {
		count(0);
		flush();
	});
	test("a store's writes, unseen by another and the default", () -> two((a, b) -> {
		a.run(() -> count(3));
		flush();
		equals([a.run(() -> count()), b.run(() -> count()), count()], [3, 0, 0]);
		count(1);
		flush();
		equals([a.run(() -> count()), b.run(() -> count()), count()], [3, 0, 1]);
	}));
	test("update reads what was written before it in the store", () -> two((a, b) -> {
		a.run(() -> {
			count(c -> c + 1);
			count(c -> c + 1);
		});
		flush();
		equals([a.run(() -> count()), b.run(() -> count())], [2, 0]);
	}));
	test("a memo a store's, computed from its nodes", () -> two((a, b) -> {
		var shown = [];
		a.run(() -> root(_ -> renderEffect(() -> double(), v -> shown.push(v))));
		flush();
		a.run(() -> count(5));
		flush();
		equals(shown, [0, 10]);
		equals([a.run(() -> double()), b.run(() -> double()), double()], [10, 0, 0]);
	}));
	test("one store held on its async, another's write in the same flush committed", () -> two((a, b) -> {
		var inA = [], inB = [];
		a.run(() -> root(_ -> renderEffect(() -> '${count()}:${slow()}', v -> inA.push(v))));
		b.run(() -> root(_ -> renderEffect(() -> count(), v -> inB.push(v))));
		flush();
		a.run(() -> count(1));
		b.run(() -> count(1));
		flush();
		equals(inA, ["0:0"]);
		equals(inB, [0, 1]);
		equals([a.run(() -> count.peek()), b.run(() -> count.peek())], [0, 1]);
	}));
	test("isPending and latest per store", () -> two((a, b) -> {
		a.run(() -> root(_ -> renderEffect(() -> slow(), _ -> {})));
		b.run(() -> root(_ -> renderEffect(() -> slow(), _ -> {})));
		flush();
		a.run(() -> count(1));
		flush();
		equals([a.run(() -> isPending(() -> slow())), b.run(() -> isPending(() -> slow()))], [true, false]);
		equals([a.run(() -> latest(() -> count())), b.run(() -> latest(() -> count()))], [1, 0]);
	}));
	test("two stores' answers land each in its own, out of order", () -> two((a, b) -> {
		loads.resize(0);
		var inA = [], inB = [];
		a.run(() -> root(_ -> renderEffect(() -> slow(), v -> inA.push(v))));
		b.run(() -> root(_ -> renderEffect(() -> slow(), v -> inB.push(v))));
		flush();
		a.run(() -> count(1));
		b.run(() -> count(2));
		flush();
		equals(loads.length, 2);
		loads[1].resolve(20);
		flush();
		equals([inA, inB], [[0], [0, 20]]);
		loads[0].resolve(10);
		flush();
		equals([inA, inB], [[0, 10], [0, 20]]);
		equals([a.run(() -> count()), b.run(() -> count())], [1, 2]);
	}));
	test("a loading boundary per store", () -> two((a, b) -> {
		loads.resize(0);
		var shown = [[], []];
		for (k => s in [a, b])
			s.run(() -> root(_ -> {
				var l = loadingBoundary(() -> 'v${slow()}', () -> "loading");
				renderEffect(() -> l(), v -> shown[k].push(v));
			}));
		flush();
		a.run(() -> count(1));
		flush();
		equals(shown, [["loading", "v0"], ["loading", "v0"]]);
		loads[0].resolve(5);
		flush();
		equals(shown, [["loading", "v0", "v5"], ["loading", "v0"]]);
	}));
	test("an error in one store's memo never reaches another's boundary", () -> two((a, b) -> {
		var bad = signal(false);
		var risky = memo(() -> bad() ? throw "boom" : "fine");
		var shown = ["", ""];
		for (k => s in [a, b])
			s.run(() -> root(_ -> {
				var e = errorBoundary(() -> risky(), (error, _) -> 'caught ${error()}');
				renderEffect(() -> e(), v -> shown[k] = v);
			}));
		flush();
		a.run(() -> bad(true));
		flush();
		equals(shown, ["caught boom", "fine"]);
	}));
	test("equals and unobserved carried to a store's nodes", () -> two((a, b) -> {
		var runs = 0, gone = [];
		var same = signalOf(1, {equals: (x, y) -> true});
		var watched = memo(() -> same() + 1, {unobserved: () -> gone.push(Atoms.current?.name)});
		a.run(() -> {
			var d = root(dispose -> {
				effect(() -> watched(), (_, _) -> {
					runs++;
					null;
				});
				dispose;
			});
			flush();
			same(2);
			flush();
			equals([same(), runs], [1, 1]);
			d();
			flush();
		});
		equals(gone, ["a"]);
	}));
	test("a derived signal written in a store, then its source changing there", () -> two((a, b) -> {
		var src = signal(1);
		var d = signalOf((_ -> src() * 10 : Null<Int>->Int));
		a.run(() -> d(5));
		flush();
		equals([a.run(() -> d()), b.run(() -> d())], [5, 10]);
		a.run(() -> src(2));
		flush();
		equals([a.run(() -> d()), b.run(() -> d())], [20, 10]);
	}));
	test("ownedWrite carried: written in a computation in a store", () -> two((a, b) -> {
		var log = signalOf(0, {ownedWrite: true});
		a.run(() -> root(_ -> renderEffect(() -> {
			log(7);
			0;
		}, _ -> {})));
		flush();
		equals([a.run(() -> log()), b.run(() -> log()), log()], [7, 0, 0]);
	}));
	test("clear: values back to their start, top-level effects made again once, their cleanups run", () -> recording(() -> {
		var runs = [], cleaned = 0;
		effect(() -> count(), (v, _) -> {
			runs.push(v);
			() -> cleaned++;
		});
		flush();
		var a = new Atoms("a");
		flush();
		a.run(() -> count(4));
		flush();
		equals(runs, [0, 0, 4]);
		a.clear();
		flush();
		equals([cleaned, a.run(() -> count())], [2, 0]);
		equals(runs, [0, 0, 4, 0]);
		a.dispose();
		flush();
		equals(cleaned, 3);
	}));
	test("stores made and let go: the atoms keep nothing of them, their effects never run again", () -> recording(() -> {
		var seen = 0;
		effect(() -> double(), (_, _) -> {
			seen++;
			null;
		});
		flush();
		var node = @:privateAccess count.node(), observers = @:privateAccess node.observers?.length ?? 0;
		for (k in 0...200) {
			var a = new Atoms("a" + k);
			a.run(() -> root(_ -> renderEffect(() -> double(), _ -> {})));
			a.run(() -> count(k));
			flush();
			a.dispose();
		}
		equals(@:privateAccess node.observers?.length ?? 0, observers);
		var runs = seen;
		count(1000);
		flush();
		equals(seen, runs + 1);
	}));
	test("a store let go: running, reading or writing in it is an error", () -> {
		var a = new Atoms("gone");
		a.dispose();
		equals(attempt(() -> a.run(() -> 1)), "a store let go (gone) run");
		var was = Atoms.current;
		Atoms.current = a;
		var read = attempt(() -> count());
		var wrote = attempt(() -> {
			count(1);
			0;
		});
		Atoms.current = was;
		equals([read, wrote], ["a store let go (gone) read or written", "a store let go (gone) read or written"]);
	});
	test("two stores' transactions never merge: the guard names it", () -> two((a, b) -> {
		var y = signal(0), x = a.run(() -> signal(0));
		var waits = memo(() -> {
			var l = new Later<Int>();
			if (y() == 0) l.resolve(0);
			l;
		});
		var both = memo(() -> x() + y());
		root(_ -> {
			renderEffect(() -> waits(), _ -> {});
			renderEffect(() -> both(), _ -> {});
		});
		flush();
		y(1);
		flush();
		a.run(() -> x(1));
		equals(attempt(() -> {
			flush();
			0;
		}), "two screens' transactions merged: a node of one store read another's (helder.view.graph.Atoms)");
	}));
	test("an effect's error handler runs in its store", () -> two((a, b) -> {
		var bad = signal(false), seen = [];
		a.run(() -> root(_ -> effect(() -> bad() ? throw "boom" : 0, (_, _) -> null, e -> seen.push(Atoms.current?.name))));
		flush();
		a.run(() -> bad(true));
		flush();
		equals(seen, ["a"]);
	}));
	test("an effect's cleanup runs in its store, again and as it is let go", () -> two((a, b) -> {
		var seen = [];
		var d = a.run(() -> root(dispose -> {
			effect(() -> count(), (_, _) -> () -> seen.push(Atoms.current?.name));
			dispose;
		}));
		flush();
		a.run(() -> count(1));
		flush();
		d();
		equals(seen, ["a", "a"]);
	}));
	test("boundaries made at the top level: each store's its own, its error its own", () -> two((a, b) -> {
		var bad = signal(0);
		var caught = errorBoundary(() -> bad() > 0 ? throw 'bad ${bad()}' : "fine", (error, _) -> 'caught ${error()}');
		var loaded = loadingBoundary(() -> 'v${slow()}', () -> "loading");
		a.run(() -> bad(2));
		flush();
		equals([a.run(() -> caught()), b.run(() -> caught()), caught()], ["caught bad 2", "fine", "fine"]);
		equals([a.run(() -> loaded()), b.run(() -> loaded())], ["loading", "loading"]);
		flush();
		equals([a.run(() -> loaded()), b.run(() -> loaded())], ["v0", "v0"]);
	}));
	test("a write in one store does not make another's unobserved memo run again", () -> two((a, b) -> {
		var asks = 0, later:Later<Int> = null;
		var async = memo(() -> {
			asks++;
			later = new Later<Int>();
			(later : Dynamic);
		});
		// (a memo made in each run reads it: for a moment nothing observes it)
		var reader = memo(() -> {
			var inner = memo(() -> async() + 1);
			inner();
		});
		var shown = [];
		b.run(() -> root(_ -> effect(() -> reader(), (v, _) -> {
			shown.push(v);
			null;
		})));
		flush();
		a.run(() -> count(5));
		flush();
		later.resolve(1);
		flush();
		// (once as it was made, in the default store; once in b)
		equals(asks, 2);
		equals(shown, [2]);
	}));
	test("a write not flushed when its store is cleared is let go with it", () -> two((a, b) -> {
		var asks = 0;
		var async = memo(() -> {
			asks++;
			count();
			(new Later<Int>() : Dynamic);
		});
		a.run(() -> count(5));
		a.clear();
		a.run(() -> try async() catch (_:Dynamic) null);
		var made = asks;
		flush();
		a.run(() -> try async() catch (_:Dynamic) null);
		equals([asks - made, a.run(() -> count())], [0, 0]);
	}));
	test("a signal made in a store: its home there, the default seeing through to it", () -> two((a, b) -> {
		var local = a.run(() -> signal(1));
		local(2);
		flush();
		equals([local(), a.run(() -> local()), b.run(() -> local())], [2, 2, 1]);
	}));
}
