package helder.view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// Jotai's vanilla store tests (MIT, Copyright (c) 2020 Poimandres,
// github.com/pmndrs/jotai: tests/vanilla/store.test.tsx, dependency.test.tsx
// and effect.test.ts) as atly ported them (github.com/benmerckx/atly,
// test/jotai.test.ts), each under its Jotai name, on helder's atoms: each
// test a store of its own (Jotai's createStore), current while it runs: its
// atoms made at home there (a count of a memo's runs is the store's alone;
// atoms read through another store: the view-stores lane's foreign mode).
//
// Translation: store.get is a read in the store, untracked; store.set a
// write there, then a flush; a writable derived atom a function writing in
// the store (batch); store.sub an effect whose first run is not reported;
// an async atom a memo answering a Later the fake timers resolve; onUnmount
// the signal's unobserved. Where helder differs by design (Solid 2's
// deferred writes, writes in a computation refused, lazy memos), the test
// asserts helder's and says how Jotai's differs. Lazy: a memo nothing
// observes asks again when it is read, not when its inputs are written
// (Solid 2's memos ask at the write); meanwhile a read serves its last
// answer (Solid 2's read of a memo pending again), the new one a read
// after it lands. Left out: onMount (Solid 2 and
// helder have unobserved alone): "should unmount with store.get" and
// "...dependencies with store.get" (their mount event), #2098, #2314, "should
// mount sibling dependencies in read order", "...flushPending ... with mount",
// the onMount cases of "should mount and trigger listeners even when an
// error is thrown" (in asynchronous read, in read promise on settled, in
// onmount/onunmount asynchronous setAtom, in synchronous onmount), "should
// call subscribers after setAtom ... on mount", "allows subscribing to atoms
// during mount", "responds to changes to atoms when mounted with get"; and
// "surfaces a stack overflow..." (a native stack overflow is not an
// exception helder catches)
var store:Atoms;

function get<T>(read:Void->T):T
	return store.run(() -> untrack(read));

function set<T>(s:Signal<T>, v:T) {
	store.run(() -> s(v));
	flush();
}

function update<T>(s:Signal<T>, f:T->T) {
	store.run(() -> s(f));
	flush();
}

// (a writable derived atom's write: f in the store, then the flush)
function batch<T>(f:Void->T):T {
	var r = store.run(f);
	flush();
	return r;
}

// Jotai's store.sub: the listener on changes, not on subscribe (an async
// atom's first answer after it a change)
function sub(read:Void->Dynamic, listener:Void->Void):Void->Void {
	var subscribing = true;
	var dispose = store.run(() -> root(d -> {
		effect(_ -> read(), (_, _) -> if (!subscribing) listener());
		d;
	}));
	flush();
	subscribing = false;
	return () -> {
		store.run(dispose);
		flush();
	};
}

// an effect in the store (atly's effect, jotai-effect's syncEffect): its
// body the compute, its cleanup returned by the apply
function watch(body:Void->Null<Void->Void>):Void->Void {
	var dispose = store.run(() -> root(d -> {
		effect(_ -> body(), (c:Null<Void->Void>, _) -> c);
		d;
	}));
	flush();
	return () -> {
		store.run(dispose);
		flush();
	};
}

// what f throws, or "not thrown"
function thrown(f:Void->Void):Dynamic
	return try {
		f();
		"not thrown";
	} catch (e:haxe.Exception) e.message;

// fake timers (vitest's in Jotai's suite): sleep's answers in time order, a
// flush after each
var now = 0;
var timers:Array<{at:Int, fn:Void->Void}> = [];

function later(ms:Int, fn:Void->Void)
	timers.push({at: now + ms, fn: fn});

function sleep<T>(ms:Int, value:T):Later<T> {
	var l = new Later<T>();
	later(ms, () -> if (!l.cancelled) l.resolve(value));
	return l;
}

function advance(ms:Int) {
	var end = now + ms;
	flush();
	while (true) {
		var next = -1;
		for (k => t in timers)
			if (t.at <= end && (next < 0 || t.at < timers[next].at)) next = k;
		if (next < 0) break;
		var t = timers.splice(next, 1)[0];
		now = t.at;
		t.fn();
		flush();
	}
	now = end;
	flush();
}

// an async atom's value in the store once settled, else "pending"
function settled(read:Void->Dynamic):Dynamic
	return store.run(() -> try untrack(read) catch (e:NotReady) "pending");

function calls():{n:Int, fn:Void->Void} {
	var c:{n:Int, fn:Void->Void} = {n: 0, fn: null};
	c.fn = () -> {
		c.n++;
	};
	return c;
}

function tests() {
	beforeEach(() -> {
		store = new Atoms("jotai");
		Atoms.current = store;
		now = 0;
		timers = [];
	});
	afterEach(() -> {
		Atoms.current = null;
		store.dispose();
		flush();
	});
	describe("store.test.tsx", () -> {
		test("should not fire on subscribe", () -> {
			var count = signal(0), a = calls(), b = calls();
			// (design difference: an effect runs once as made, a Jotai listener not on subscribe)
			watch(() -> {
				count();
				a.fn();
				null;
			});
			watch(() -> {
				count();
				b.fn();
				null;
			});
			equals([a.n, b.n], [1, 1]);
		});
		test("should not fire subscription if primitive atom value is the same", () -> {
			var count = signal(0), cb = calls();
			sub(() -> count(), cb.fn);
			set(count, 0);
			equals(cb.n, 0);
		});
		test("should not fire subscription if derived atom value is the same", () -> {
			var count = signal(0), derived = memo(() -> count() - count()), cb = calls();
			sub(() -> derived(), cb.fn);
			set(count, 1);
			equals(cb.n, 0);
		});
		test("should update async atom with delay (#1813)", () -> {
			var count = signal(0);
			var delayed = memo(() -> (sleep(100, count()) : Dynamic));
			get(() -> settled(() -> delayed()));
			set(count, 1);
			advance(100);
			// (lazy: Jotai's 1 here)
			equals(settled(() -> delayed()), 0);
			advance(100);
			equals(settled(() -> delayed()), 1);
		});
		test("should update async atom with deps after await (#1905)", () -> {
			// (a read after an await is not tracked, in Solid 2 nor helder: the count read before it)
			var count = signal(0);
			var delayed = memo(() -> (sleep(100, count()) : Dynamic));
			var derived = memo(() -> delayed());
			var last:Dynamic = null;
			var unsub = sub(() -> derived(), () -> last = settled(() -> derived()));
			for (n in 1...4) {
				set(count, n);
				advance(100);
				equals([last, settled(() -> derived())], [n, n]);
			}
			unsub();
		});
		test("should not fire subscription when async atom promise is the same", () -> {
			var promise = new Later<Int>();
			promise.resolve(0);
			var promiseAtom = signal(promise);
			var getter = calls();
			var derived = memo(() -> {
				getter.fn();
				promiseAtom();
			});
			// (a memo computes as it is made, Solid 2's; Jotai's atom when first read: 0)
			equals(getter.n, 1);
			var promiseListener = calls(), derivedListener = calls();
			var u1 = sub(() -> promiseAtom(), promiseListener.fn);
			var u2 = sub(() -> derived(), derivedListener.fn);
			equals([getter.n, promiseListener.n, derivedListener.n], [1, 0, 0]);
			get(() -> promiseAtom());
			get(() -> derived());
			equals([getter.n, promiseListener.n, derivedListener.n], [1, 0, 0]);
			set(promiseAtom, promise);
			set(promiseAtom, promise);
			equals([getter.n, promiseListener.n, derivedListener.n], [1, 0, 0]);
			u1();
			u2();
		});
		test("should notify subscription with tree dependencies with bail-out", () -> {
			var value = signal(1);
			var dep1 = memo(() -> value() * 2), dep2 = memo(() -> value() - value());
			var dep3 = memo(() -> dep1() + dep2());
			var cb = calls();
			sub(() -> dep1(), () -> {});
			sub(() -> dep3(), cb.fn);
			equals([cb.n, get(() -> dep3())], [0, 2]);
			update(value, c -> c + 1);
			equals([cb.n, get(() -> dep3())], [1, 4]);
		});
		test("should bail out with the same value with chained dependency (#2014)", () -> {
			var obj = signal({count: 1});
			var count = memo(() -> obj().count);
			var derive = calls(), further = calls();
			var derived = memo(() -> {
				derive.fn();
				count();
			});
			var derivedFurther = memo(() -> {
				further.fn();
				obj();
				derived();
			});
			var cb = calls();
			sub(() -> derivedFurther(), cb.fn);
			equals([get(() -> derived()), get(() -> derivedFurther()), cb.n, derive.n, further.n], [1, 1, 0, 1, 1]);
			update(obj, o -> {count: o.count});
			equals([cb.n, derive.n, further.n], [0, 1, 2]);
		});
		test("should update with conditional dependencies (#2084)", () -> {
			var f1 = signal(false), f2 = signal(false);
			var f3 = memo(() -> f1() && f2());
			sub(() -> f1(), () -> {});
			sub(() -> f2(), () -> {});
			sub(() -> f3(), () -> {});
			batch(() -> {
				f1(true);
				f2(true);
			});
			equals(get(() -> f3()), true);
		});
		test("should update derived atoms during write (#2107)", () -> {
			// (design difference, Solid 2's deferred writes: a read in the write
			// sees the committed value until the flush; Jotai's sees the new one)
			var base = signal(1), count = memo(() -> base());
			sub(() -> count(), () -> {});
			equals(get(() -> count()), 1);
			var seen = batch(() -> {
				base(2);
				count();
			});
			equals([seen, get(() -> count())], [1, 2]);
		});
		test("resolves dependencies reliably after a delay (#2192)", () -> {
			var count = signal(0), result:Dynamic = null;
			var async = memo(() -> (sleep(100, count()) : Dynamic));
			var derived = memo(() -> {
				count();
				(sleep(50, null) : Dynamic);
			});
			var reader = memo(() -> {
				derived();
				result = async();
			});
			sub(() -> reader(), () -> {});
			update(count, c -> c + 1);
			update(count, c -> c + 1);
			advance(150);
			equals(result, 2);
			update(count, c -> c + 1);
			update(count, c -> c + 1);
			advance(150);
			equals([get(() -> count()), result], [4, 4]);
		});
		test("should not recompute a derived atom value if unchanged (#2168)", () -> {
			var count = signal(1), derived1 = memo(() -> count() - count());
			var derive2 = calls();
			var derived2 = memo(() -> {
				derive2.fn();
				derived1();
			});
			equals(get(() -> derived2()), 0);
			update(count, c -> c + 1);
			// (design difference, Solid 2's write clock: an unobserved memo read
			// outside a computation computes again after a write, its inputs
			// pulled; Jotai checks them first: 1 call)
			equals([get(() -> derived2()), derive2.n], [0, 2]);
		});
		test("should flush pending write triggered asynchronously and indirectly (#2451)", () -> {
			var an = signal("initial"), seen = [];
			var unsub = sub(() -> an(), () -> seen.push(get(() -> an())));
			later(0, () -> batch(() -> an("next")));
			advance(0);
			equals(seen, ["next"]);
			unsub();
		});
		test("async atom with subtle timing: case 1", () -> {
			// (a read after the await: not tracked; the value read before it)
			var a = signal(1);
			var b = memo(() -> (sleep(100, a()) : Dynamic));
			get(() -> settled(() -> b()));
			set(a, 2);
			advance(100);
			// (lazy: Jotai's 2 here)
			equals(settled(() -> b()), 1);
			advance(100);
			equals(settled(() -> b()), 2);
		});
		test("async atom with subtle timing: case 2", () -> {
			var a = signal(1);
			var b = memo(() -> (sleep(100, a()) : Dynamic));
			get(() -> settled(() -> b()));
			set(a, 2);
			advance(100);
			// (lazy: Jotai's later read 2 here, its first 1)
			equals(settled(() -> b()), 1);
			advance(100);
			equals(settled(() -> b()), 2);
		});
		test("aborting atoms: should abort the signal when dependencies change", () -> {
			var a = signal(1), asks:Array<Later<Int>> = [];
			var derived = memo(() -> {
				var l = sleep(100, a() + 1);
				asks.push(l);
				(l : Dynamic);
			});
			get(() -> settled(() -> derived()));
			set(a, 3);
			get(() -> settled(() -> derived()));
			advance(100);
			equals(settled(() -> derived()), 4);
			equals([for (l in asks) l.cancelled], [true, false]);
		});
		test("aborting atoms: should abort the signal when dependencies change and the atom is mounted", () -> {
			var a = signal(1), asks:Array<Later<Int>> = [];
			var derived = memo(() -> {
				var l = sleep(100, a() + 1);
				asks.push(l);
				(l : Dynamic);
			});
			sub(() -> derived(), () -> {});
			set(a, 3);
			advance(100);
			equals([for (l in asks) l.cancelled], [true, false]);
		});
		test("aborting atoms: should not abort the signal when unsubscribed", () -> {
			var a = signal(1), asks:Array<Later<Int>> = [];
			var derived = memo(() -> {
				var l = sleep(100, a() + 1);
				asks.push(l);
				(l : Dynamic);
			});
			sub(() -> derived(), () -> {})();
			advance(100);
			equals(settled(() -> derived()), 2);
			// (its run not aborted; nothing observing it, the read asks again: Solid 2's, Jotai's one ask)
			equals([for (l in asks) l.cancelled], [false, false]);
		});
		test("Unmount an atom that is no longer dependent within a derived atom (#2658)", () -> {
			var cond = signal(true), unmounted = calls();
			var base = signal(0, {unobserved: unmounted.fn});
			var derived = memo(() -> if (cond()) base() else 0);
			sub(() -> derived(), () -> {});
			set(cond, false);
			equals(unmounted.n, 1);
		});
		test("should update derived atom even if dependencies changed (#2697)", () -> {
			var primitive = signal((null : Null<Int>));
			var derived = memo(() -> primitive());
			var conditional = memo(() -> {
				var base = primitive();
				base == null ? null : derived();
			});
			var changed = calls();
			sub(() -> derived(), changed.fn);
			sub(() -> conditional(), () -> {});
			equals(changed.n, 0);
			set(primitive, 1);
			equals(changed.n, 1);
		});
		test("should invoke flushPending only after all atoms are updated with set (#2804)", () -> {
			var a = signal(0), result = [];
			sub(() -> a(), () -> result.push('a value changed - ${get(() -> a())}'));
			result.push("before store.set");
			batch(() -> {
				result.push("before set");
				a(1);
				result.push("after set");
			});
			result.push("after store.set");
			equals(result, ["before store.set", "before set", "after set", "a value changed - 1", "after store.set"]);
		});
		test("should flush only after all atoms are updated with unmount (#2804)", () -> {
			var result = [], a = signal(0);
			var b = signal((null : Null<Int>), {
				unobserved: () -> {
					result.push("onUmount: before setAtom");
					store.run(() -> a(1));
					result.push("onUmount: after setAtom");
				}
			});
			var c = signal(true);
			var d = memo(() -> c() ? (b() : Dynamic) : (false : Dynamic));
			sub(() -> a(), () -> result.push('a value changed - ${get(() -> a())}'));
			sub(() -> d(), () -> {});
			equals(get(() -> d()), null);
			set(c, false);
			flush();
			equals(result, ["onUmount: before setAtom", "onUmount: after setAtom", "a value changed - 1"]);
		});
		test("should mount and trigger listeners even when an error is thrown: in asynchronous write", () -> {
			var a = signal(0), e = memo(() -> (throw "error" : Int)), listener = calls();
			sub(() -> a(), listener.fn);
			later(0, () -> try batch(() -> {
				a(1);
				e();
			}) catch (_:Dynamic) {});
			advance(0);
			equals(listener.n, 1);
		});
		test("should mount and trigger listeners even when an error is thrown: in synchronous write", () -> {
			var a = signal(0), e = memo(() -> (throw "error" : Int)), listener = calls();
			sub(() -> a(), listener.fn);
			try batch(() -> {
				a(1);
				e();
			}) catch (_:Dynamic) {}
			flush();
			equals(listener.n, 1);
		});
		test("should mount and trigger listeners even when an error is thrown: in synchronous onunmount", () -> {
			var aUnmount = calls();
			var a = signal(0, {unobserved: aUnmount.fn});
			var b = signal(0, {unobserved: () -> throw "error"});
			var d = memo(() -> {
				b();
				a();
			});
			var unsub = sub(() -> d(), () -> {});
			try unsub() catch (_:Dynamic) {}
			flush();
			equals(aUnmount.n, 1);
		});
		test("should mount and trigger listeners even when an error is thrown: in synchronous listener", () -> {
			var a = signal(0), e = signal(0), listener = calls();
			sub(() -> e(), () -> throw "error");
			sub(() -> a(), listener.fn);
			try batch(() -> {
				a(1);
				e(1);
			}) catch (_:Dynamic) {}
			flush();
			equals(listener.n, 1);
		});
		test("throws falsy errors in onUnmount and listeners", () -> {
			var b = signal(0, {unobserved: () -> throw ""});
			var unsub = sub(() -> b(), () -> {});
			equals(thrown(unsub), "");
			var c = signal(0);
			sub(() -> c(), () -> throw "");
			equals(thrown(() -> set(c, 1)), "");
		});
		test("should use the correct pending on unmount", () -> {
			var a = signal(0);
			var b = signal(0, {unobserved: () -> store.run(() -> a(1))});
			var listener = calls();
			sub(() -> a(), listener.fn);
			var unsub = sub(() -> b(), () -> {});
			unsub();
			flush();
			equals([get(() -> a()), listener.n], [1, 1]);
		});
		test("mounted atom should be recomputed eagerly", () -> {
			var result = [], a = signal(0);
			var b = memo(() -> {
				result.push("bRead");
				a();
			});
			sub(() -> a(), () -> result.push("aCallback"));
			sub(() -> b(), () -> result.push("bCallback"));
			equals(result, ["bRead"]);
			result.resize(0);
			set(a, 1);
			equals(result, ["bRead", "aCallback", "bCallback"]);
		});
		test("should notify subscription even with reading atom in write", () -> {
			var a = signal(1), b = memo(() -> a() * 2), c = memo(() -> b() + 1), cb = calls();
			sub(() -> c(), cb.fn);
			batch(() -> {
				a(2);
				b();
			});
			equals(cb.n, 1);
		});
		test("should process all atom listeners even if some of them throw errors", () -> {
			var a = signal(0), la = calls(), lb = calls(), lc = calls();
			sub(() -> a(), la.fn);
			sub(() -> a(), () -> {
				lb.fn();
				throw "error";
			});
			sub(() -> a(), lc.fn);
			try set(a, 1) catch (_:Dynamic) {}
			flush();
			equals([la.n, lb.n, lc.n], [1, 1, 1]);
		});
		test("recomputes dependents of unmounted atoms", () -> {
			var a = signal(0), bRead = calls();
			var b = memo(() -> {
				bRead.fn();
				a();
			});
			var c = memo(() -> b());
			batch(() -> {
				a(1);
				c();
				a(2);
				bRead.n = 0;
			});
			equals(bRead.n, 0);
		});
		test("recomputes all changed atom dependents together", () -> {
			var a = signal([0]), b = signal([0]);
			var a0 = memo(() -> a()[0]), b0 = memo(() -> b()[0]);
			var a0b0 = memo(() -> [a0(), b0()]);
			sub(() -> a0b0(), () -> {});
			batch(() -> {
				a([0]);
				b([1]);
			});
			equals([get(() -> a0()), get(() -> b0())], [0, 1]);
			equals(get(() -> a0b0()), [0, 1]);
		});
		test("supports recursion in an atom subscriber", () -> {
			var a = signal(0);
			sub(() -> a(), () -> if (get(() -> a()) < 3) update(a, v -> v + 1));
			set(a, 1);
			equals(get(() -> a()), 3);
		});
		test("updates with reading derived atoms (#2959)", () -> {
			var count = signal(0), derived = memo(() -> count());
			sub(() -> derived(), () -> {});
			batch(() -> {
				count(1);
				derived();
				count(2);
			});
			equals(get(() -> derived()), 2);
		});
		test("updates dependents when it eagerly recomputes dirty atoms", () -> {
			var count = signal(0), active = signal(false);
			var activeCount = memo(() -> active() ? count() : null);
			sub(() -> activeCount(), () -> {});
			batch(() -> {
				active(true);
				activeCount();
			});
			set(count, 1);
			equals(get(() -> activeCount()), 1);
		});
		test("should keep reactivity when a derived atom returns a function that calls get (#3240)", () -> {
			var stable = signal(0);
			var closure = memo(() -> (x:Int) -> x + stable());
			var changing = signal(0);
			var upstream = memo(() -> {
				var n = changing();
				closure()(n);
			});
			var downstream = memo(() -> upstream() * 2);
			var cb = calls();
			sub(() -> downstream(), cb.fn);
			equals([get(() -> upstream()), get(() -> downstream())], [0, 0]);
			set(changing, 1);
			equals([get(() -> upstream()), get(() -> downstream()), cb.n], [1, 2, 1]);
			set(changing, 2);
			equals([get(() -> upstream()), get(() -> downstream()), cb.n], [2, 4, 2]);
		});
		// (Jotai's store.set on a write-only atom in a read, returning a value
		// and writing nothing: a flush around it, in a computation)
		test("notifies derived-atom subscriber when read calls store.set", () -> {
			var counter = signal(0);
			var data = memo(() -> {
				var v = counter();
				flush(() -> v * 2);
			});
			var listener = calls();
			sub(() -> data(), listener.fn);
			equals([get(() -> data()), listener.n], [0, 0]);
			set(counter, 1);
			equals([get(() -> data()), listener.n], [2, 1]);
			set(counter, 2);
			equals([get(() -> data()), listener.n], [4, 2]);
		});
		test("notifies subscriber through chain of derived atoms when root calls store.set", () -> {
			var counter = signal(0);
			var base = memo(() -> {
				var v = counter();
				flush(() -> v * 2);
			});
			var derived = memo(() -> base() * 2);
			var listener = calls();
			sub(() -> derived(), listener.fn);
			equals([get(() -> derived()), listener.n], [0, 0]);
			set(counter, 1);
			equals([get(() -> derived()), listener.n], [4, 1]);
		});
		test("notifies subscriber when nested write uses get to read atom with store.set", () -> {
			var counter = signal(0);
			var middle = memo(() -> {
				var v = counter();
				flush(() -> v * 3);
			});
			var data = memo(() -> {
				var v = counter();
				flush(() -> v * 2 + middle());
			});
			var listener = calls();
			sub(() -> data(), listener.fn);
			equals([get(() -> data()), listener.n], [0, 0]);
			set(counter, 1);
			equals([get(() -> data()), listener.n], [5, 1]);
			set(counter, 2);
			equals([get(() -> data()), listener.n], [10, 2]);
		});
		test("notifies async derived-atom subscriber when read calls store.set before await", () -> {
			var counter = signal(0);
			var data = memo(() -> {
				var v = counter();
				var r = flush(() -> v * 2);
				(sleep(0, r) : Dynamic);
			});
			var last:Dynamic = null;
			sub(() -> data(), () -> last = settled(() -> data()));
			advance(10);
			equals(settled(() -> data()), 0);
			set(counter, 1);
			advance(10);
			equals(last, 2);
			set(counter, 2);
			advance(10);
			equals(last, 4);
		});
		test("store.set before get(dep) causes deep recursion but recovers", () -> {
			var counter = signal(0);
			var data = memo(() -> {
				var r = flush(() -> 1);
				r + counter();
			});
			var listener = calls();
			sub(() -> data(), listener.fn);
			equals(get(() -> data()), 1);
			set(counter, 1);
			equals(get(() -> data()), 2);
			assert(listener.n >= 1, 'notified: ${listener.n}');
		});
		test("notifies subscriber when read calls store.set multiple times", () -> {
			var counter = signal(0);
			var data = memo(() -> {
				var v = counter();
				flush(() -> v) + flush(() -> v * 10);
			});
			var listener = calls();
			sub(() -> data(), listener.fn);
			equals([get(() -> data()), listener.n], [0, 0]);
			set(counter, 1);
			equals([get(() -> data()), listener.n], [11, 1]);
			set(counter, 2);
			equals([get(() -> data()), listener.n], [22, 2]);
		});
		test("does not recompute derived atom redundantly when store.set in read uses return value without setting atoms", () -> {
			var counter = signal(0), baseReads = 0, derivedReads = 0;
			var base = memo(() -> {
				baseReads++;
				var v = counter();
				flush(() -> v * 2);
			});
			var base2 = memo(() -> {
				var v = counter();
				flush(() -> v * 2);
			});
			var derived = memo(() -> {
				derivedReads++;
				base();
				base2();
				counter();
			});
			var listener = calls();
			sub(() -> derived(), listener.fn);
			equals([get(() -> derived()), baseReads, derivedReads], [0, 1, 1]);
			baseReads = derivedReads = 0;
			set(counter, 1);
			equals([get(() -> derived()), listener.n, baseReads, derivedReads], [1, 1, 1, 1]);
		});
		test("notifies subscriber when a nested no-op store.set and a subscription happen inside the outer write (#3353)", () -> {
			var a = signal(0), derived = memo(() -> a()), b = signal(0), listener = calls();
			sub(() -> derived(), listener.fn);
			batch(() -> {
				a(1);
				set(b, get(() -> b()));
				sub(() -> b(), () -> {})();
			});
			equals([get(() -> derived()), listener.n], [1, 1]);
		});
		test("notifies subscriber of interrupt-derived atom after a synchronous event cascade of nested store.set (#3353)", () -> {
			var interrupt = signal((null : Null<{resume:Void->Void}>));
			var interrupted = memo(() -> interrupt() != null);
			var data = signal(0);
			var emitter:Array<Void->Void> = [];
			var unsub = sub(() -> data(), () -> {});
			emitter.push(() -> {
				set(data, 0);
				unsub();
				unsub = sub(() -> data(), () -> {});
			});
			var listener = calls();
			sub(() -> interrupted(), listener.fn);
			batch(() -> interrupt({resume: () -> for (l in emitter) l()}));
			equals(listener.n, 1);
			var i = get(() -> interrupt());
			batch(() -> interrupt(null));
			i.resume();
			equals(get(() -> interrupted()), false);
			equals(listener.n, 2);
		});
	});
	describe("dependency.test.tsx", () -> {
		test("can get async atom with deps more than once before resolving (#1668)", () -> {
			var count = signal(0);
			var async = memo(() -> (sleep(100, count()) : Dynamic));
			update(count, c -> c + 1);
			get(() -> settled(() -> async()));
			update(count, c -> c + 1);
			advance(100);
			// (lazy: Jotai's 2 here)
			equals(settled(() -> async()), 1);
			advance(100);
			equals(settled(() -> async()), 2);
		});
		test("correctly updates async derived atom after get/set update", () -> {
			var base = signal(0);
			var derived = memo(() -> {
				var l = new Later<Int>();
				l.resolve(base() + 1);
				(l : Dynamic);
			});
			advance(0);
			equals(settled(() -> derived()), 1);
			batch(() -> base(2));
			equals(get(() -> base()), 2);
			// (lazy: Jotai's 3 here)
			equals(settled(() -> derived()), 1);
			advance(0);
			equals(settled(() -> derived()), 3);
		});
		test("handles complex dependency chains", () -> {
			var base = signal(1);
			var d1 = memo(() -> base() * 2), d2 = memo(() -> d1() + 1);
			var async = memo(() -> (sleep(100, d2() * 2) : Dynamic));
			get(() -> settled(() -> async()));
			advance(100);
			equals(settled(() -> async()), 6);
			set(base, 2);
			get(() -> settled(() -> async()));
			advance(100);
			equals(settled(() -> async()), 10);
		});
		test("can read sync derived atom in write without initializing", () -> {
			// (design difference, deferred writes: Jotai's second write reads 1, its own first)
			var a = signal(0), b = memo(() -> a() + 1);
			batch(() -> a(b()));
			equals(get(() -> a()), 1);
			batch(() -> a(b()));
			equals(get(() -> a()), 2);
		});
		test("can cache reading an atom in write function (without mounting)", () -> {
			var reads = 0;
			var a = memo(() -> {
				reads++;
				"a";
			});
			batch(() -> a());
			equals(reads, 1);
			batch(() -> a());
			equals(reads, 1);
		});
		test("can cache reading an atom in write function (with mounting)", () -> {
			var reads = 0;
			var a = memo(() -> {
				reads++;
				"a";
			});
			sub(() -> a(), () -> {});
			batch(() -> a());
			equals(reads, 1);
			batch(() -> a());
			equals(reads, 1);
		});
		test("batches sync writes", () -> {
			var a = signal(0), b = memo(() -> a()), fetched = [];
			var c = memo(() -> fetched.push(a()));
			sub(() -> b(), () -> {});
			sub(() -> c(), () -> {});
			fetched.resize(0);
			// (design difference, deferred writes: b reads 0 in the write, Jotai's 1)
			var inWrite = batch(() -> {
				a(1);
				[b(), fetched.length];
			});
			equals(inWrite, [0, 0]);
			equals([fetched, [get(() -> a())]], [[1], [1]]);
		});
	});
	describe("effect.test.ts", () -> {
		test("responds to changes to atoms when subscribed", () -> {
			var a = signal(1), b = signal(1), results = [], cleanup = calls(), runs = calls();
			var unsub = watch(() -> {
				runs.fn();
				results.push(a() * 10 + b());
				cleanup.fn;
			});
			equals(runs.n, 1);
			equals(results, [11]);
			set(a, 2);
			equals(results, [11, 21]);
			set(b, 2);
			equals(results, [11, 21, 22]);
			batch(() -> {
				a(3);
				b(3);
			});
			equals(results, [11, 21, 22, 33]);
			equals([cleanup.n, runs.n], [3, 4]);
			unsub();
			equals([cleanup.n, runs.n], [4, 4]);
			set(a, 4);
			equals([results.length, runs.n], [4, 4]);
		});
		test("sets values to atoms without causing infinite loop", () -> {
			// (design difference: a write in an effect's compute is refused, Solid
			// 2's; in its apply it runs again after its own write, Jotai's
			// syncEffect ignores it: here the apply stops itself)
			var a = signal(1), runs = 0;
			watch(() -> {
				runs++;
				a();
				null;
			});
			store.run(() -> root(_ -> effect(_ -> a(), (v:Int, _) -> if (v < 3) a(v + 1))));
			flush();
			equals([get(() -> a()), runs], [3, 3]);
		});
	});
}
