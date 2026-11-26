package helder.view.graph;

import helder.test.Gen;
import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// The graph fuzzed, two ways (atly's fuzz test's):
//
// - against plain evaluation: random graphs of signals and memos (sums,
//   conditional reads that switch dependencies, clamps that often keep
//   their value, memos made inside memos), random writes, flushes, reads
//   and effects; every read and every effect's view equal to the graph's
//   functions evaluated plainly, an effect never applied again without a
//   change. Run plain, in a store, and through a store's nodes of the
//   default's.
// - stores against a model: the same graphs and async memos (answered,
//   failed, superseded), writable derived signals, effects with cleanups
//   and writes, loading and error boundaries, made once at the top level;
//   then ops over up to 8 stores (made, let go, cleared mid-flight). The
//   model: the graph made afresh for each store, at home in a store of its
//   own (no copies of another's nodes). Every store's
//   reads (plain, untracked, isPending, latest) and effect logs equal its
//   copy's.
//
// Quick here; HELDER_FUZZ_SECONDS=<n> runs random seeds for n seconds each,
// printing every failure's seed and its case shrunk (the fuzz lane);
// HELDER_FUZZ_REPLAY=stores:<choices> (or plain:) replays one.
function tests() {
	// (a failure's choices as printed: that case alone, HELDER_FUZZ_REPLAY=plain:... or stores:...)
	var replay = Sys.getEnv("HELDER_FUZZ_REPLAY") ?? "";
	if (replay != "") {
		var at = replay.indexOf(":"), choices = replay.substr(at + 1);
		test("replay", () -> StringTools.startsWith(replay, "plain") ? property(plainGen(), plain, {replay: choices}) : property(modelGen(), model, {replay: choices}));
		return;
	}
	var budget = Std.parseFloat(Sys.getEnv("HELDER_FUZZ_SECONDS") ?? "");
	if (budget > 0) {
		test("fuzz: the graph against plain evaluation", () -> fuzz(plainGen(), plain, budget, "plain"));
		test("fuzz: stores against fresh copies", () -> fuzz(modelGen(), model, budget, "stores"));
		return;
	}
	test("the graph against plain evaluation", () -> property(plainGen(), plain, {cases: 200}));
	// (cases the fuzzer found, shrunk: a store's node ran in another store's
	// transaction, a commit's stale frame readers in the next store's drain)
	test("stores: found by the fuzzer", () -> for (r in FOUND)
		property(modelGen(), model, {replay: r}));
	test("stores against fresh copies of the graph", () -> property(modelGen(), model, {cases: 120}));
}

// (random seeds until the budget is spent; each failure printed, its seed to replay)
function fuzz<T>(gen:Gen<T>, body:T->Void, seconds:Float, name:String) {
	var end = haxe.Timer.stamp() + seconds, cases = 0, runs = 0, failed = 0;
	while (haxe.Timer.stamp() < end) {
		var seed = Std.random(0x3FFFFFFF);
		var r = @:privateAccess helder.test.Property.search(gen, body, {cases: 1000, seconds: Math.min(60, end - haxe.Timer.stamp()), seed: seed}, 'fuzz $name');
		cases += r.cases;
		runs++;
		if (r.failed != null) {
			failed++;
			Sys.println('fuzz $name: seed $seed failed\n' + @:privateAccess helder.test.Property.report(r, null));
			@:privateAccess helder.test.Property.remove('fuzz $name');
		}
	}
	Sys.println('fuzz $name: $cases cases, $runs seeds, $failed failed');
	equals(failed, 0);
}

final FOUND = [
	"0 36 0 0 0 0 0 0 0 6 0 0 0 0 0 0 0 4 0 0 0 0 4 0 4 4 4 0 0 0 0 4 0 4 0 4 0 4 0 0 0 10 0 0 0 4 0 4 0 4 0 4 0 4 0 4 0 4 0 0 0 0 4 0 4 0 0 0 0 4 0 4 0 4 0 4 0 0 0 0 4 0 7 0 7 0 3 17 0 0 0 0 0 1 1 38 3 0 0 0 0 0 0 0 88 0 0 0 0 0 0 0 0 0 0 0 0 4 4 4 0 0 0 4 4 4 0 0 0 4 0 0 0 0 0 0 4 4 4 4 4 0 0 0 4 0 0 0 4 0 0 0 4 4 4 0 0 0 0 0 0 0 0 0 4 8 0 0 0 0 8 0 0 0 0 4 4 0 0 0 4 4 4 0 0 0 0 0 0 0 0 0 4 4 4 0 0 0 4 4 0 0 0 0 0 0 4 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 0 4 4 4 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 4 4 0 0 0 0 0 0 0 0 0 4 0 0 1 3 1 0 0 4",
	"2 33 0 0 0 0 0 0 4 0 0 0 0 4 0 4 0 4 0 4 0 4 0 4 0 4 0 4 0 0 0 0 4 0 4 0 4 0 6 0 0 0 0 4 0 4 0 0 0 0 4 0 4 19 0 0 0 0 0 0 4 0 4 0 4 0 4 0 4 0 0 2 19 0 0 0 0 0 0 4 0 0 5 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 33 0 0 0 1 25 3 0 0 0 0 0 0 0 36 0 0 0 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 3 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 3 3 3 8 6 0 0 0 0 0 0 0 0 0 0 0 0 3 0 0 0 0 3 3 0 7 0 1 0 0 2 0 3"
];

// --- graphs

enum Made {
	Sum(a:Int, b:Int);
	// (reads b or c by a: its dependencies switch)
	Cond(a:Int, b:Int, c:Int, k:Int);
	// (often the same as its input changes: what reads it stays)
	Clamp(a:Int, k:Int);
	Gate(a:Int, b:Int, k:Int);
	// (a memo made inside it, owned, each run)
	Inner(a:Int);
	// (throws when its input is 3)
	Throws(a:Int);
	Async(a:Int);
	// (a signal derived from a, writable)
	Derived(a:Int);
}

// a node's plain value from its inputs'
function value(m:Made, get:Int->Dynamic):Dynamic
	return switch m {
		case Sum(a, b): num(get(a)) + num(get(b));
		case Cond(a, b, c, k): num(get(a)) % 2 == 0 ? num(get(b)) : num(get(c)) + k;
		case Clamp(a, k): Std.int(Math.min(num(get(a)), k));
		case Gate(a, b, k): num(get(a)) > k ? num(get(b)) * 2 : k;
		case Inner(a): (num(get(a)) + 1) * 2;
		case Throws(a): num(get(a)) == 3 ? throw "three" : num(get(a));
		case Async(_) | Derived(_): throw "not plain";
	}

inline function num(v:Dynamic):Int
	return v;

// (a node made: a function reading it)
function made(m:Made, i:Int, ns:Array<Void->Dynamic>, ask:(Int, Int) -> Later<Int>):{read:Void->Dynamic, ?derived:Signal<Int>} {
	return switch m {
		case Inner(a):
			var f = memo(() -> {
				var inner = memo(() -> num(ns[a]()) + 1);
				inner() * 2;
			});
			{read: () -> f()};
		case Async(a):
			var f = memo(() -> (ask(i, num(ns[a]())) : Dynamic));
			{read: () -> f()};
		case Derived(a):
			var s:Signal<Int> = signalOf((_ -> num(ns[a]()) + 1 : Null<Int>->Int));
			{read: () -> s(), derived: s};
		case _:
			var f = memo(() -> value(m, k -> ns[k]()));
			{read: () -> f()};
	}
}

// (memos over earlier nodes)
function memosGen(signals:Int, most:Int, kinds:Int):Gen<Array<Made>>
	return c -> {
		var out = [];
		for (k in 0...c.draw(int(1, most))) {
			var n = signals + k;
			out.push(switch c.draw(int(0, kinds - 1)) {
				case 0: Sum(c.draw(int(0, n - 1)), c.draw(int(0, n - 1)));
				case 1: Cond(c.draw(int(0, n - 1)), c.draw(int(0, n - 1)), c.draw(int(0, n - 1)), c.draw(int(0, 2)));
				case 2: Clamp(c.draw(int(0, n - 1)), c.draw(int(0, 3)));
				case 3: Gate(c.draw(int(0, n - 1)), c.draw(int(0, n - 1)), c.draw(int(0, 3)));
				case 4: Inner(c.draw(int(0, n - 1)));
				case 5: Throws(c.draw(int(0, n - 1)));
				case 6: Async(c.draw(int(0, n - 1)));
				case _: Derived(c.draw(int(0, n - 1)));
			});
		}
		out;
	};

// a node read as it is, as isPending, as latest, untracked (what it throws: its message)
function read(n:Void->Dynamic, how:Int):Dynamic
	return switch how {
		case 0: n();
		case 1: isPending(() -> n());
		case 2: latest(() -> n());
		case _: untrack(() -> n());
	}

function attempt(f:Void->Dynamic):String
	return try Std.string(f()) catch (e:haxe.Exception) "throws " + e.message catch (e:Dynamic) "throws " + Std.string(e);

// --- the graph against plain evaluation

enum PlainOp {
	PWrite(signal:Int, value:Int);
	PFlush;
	PRead(node:Int, untracked:Bool);
	PWatch(nodes:Array<Int>, render:Bool);
	PUnwatch(k:Int);
}

typedef PlainSpec = {signals:Array<Int>, memos:Array<Made>, where:Int, ops:Array<PlainOp>};

function plainGen():Gen<PlainSpec>
	return c -> {
		var signals = [for (_ in 0...c.draw(int(1, 20))) c.draw(int(0, 4))];
		var memos = c.draw(memosGen(signals.length, 40, 6));
		var nodes = signals.length + memos.length;
		var ops = [for (_ in 0...c.draw(int(1, 120))) switch c.draw(int(0, 9)) {
			case 0 | 1 | 2: PWrite(c.draw(int(0, signals.length - 1)), c.draw(int(0, 5)));
			case 3 | 4: PFlush;
			case 5 | 6: PRead(c.draw(int(0, nodes - 1)), c.draw(bool()));
			case 7 | 8: PWatch([for (_ in 0...c.draw(int(1, 3))) c.draw(int(0, nodes - 1))], c.draw(bool()));
			case _: PUnwatch(c.draw(int(0, 5)));
		}];
		// (0 plain, 1 in a store, 2 through a store's nodes of the default's)
		{signals: signals, memos: memos, where: c.draw(int(0, 2)), ops: ops};
	};

typedef Watched = {dispose:Void->Void, check:Void->Void};

function plain(spec:PlainSpec) {
	var store = spec.where == 0 ? null : new Atoms("fuzz");
	var was = Atoms.current;
	Atoms.current = store;
	Atoms.homeless = spec.where == 2;
	var watches:Array<Watched> = [];
	try {
		var values = spec.signals.copy(), committed = spec.signals.copy();
		function expected(i:Int):String
			return attempt(() -> {
				function get(k:Int):Dynamic
					return k < values.length ? committed[k] : value(spec.memos[k - values.length], get);
				get(i);
			});
		var ns:Array<Void->Dynamic> = [], signals:Array<Signal<Int>> = [];
		for (v in spec.signals) {
			var s:Signal<Int> = signalOf(v);
			signals.push(s);
			ns.push(() -> s());
		}
		for (i => m in spec.memos)
			ns.push(made(m, i, ns, (_, _) -> null).read);
		for (op in spec.ops)
			switch op {
				case PWrite(i, v):
					signals[i](v);
					values[i] = v;
				case PFlush:
					flush();
					committed = values.copy();
					for (w in watches)
						w.check();
				case PRead(n, untracked):
					equals(attempt(() -> read(ns[n], untracked ? 3 : 0)), expected(n), 'node $n read');
				case PWatch(targets, render):
					var seen:Null<String> = null, problems = [];
					var shown = () -> [for (t in targets) attempt(ns[t])].join(",");
					var dispose = root(d -> {
						var compute = (_ -> shown() : Compute<String>), apply = ((v:String, _) -> {
							if (v == seen) problems.push('applied again without a change: $v');
							seen = v;
							null;
						} : Apply<String>);
						if (render) renderEffect(compute, apply) else effect(compute, apply);
						d;
					});
					flush();
					committed = values.copy();
					watches.push({
						dispose: dispose,
						check: () -> {
							equals(seen, [for (t in targets) expected(t)].join(","), 'an effect on $targets');
							equals(problems, [], 'an effect on $targets');
						}
					});
					for (x in watches)
						x.check();
				case PUnwatch(k) if (k < watches.length):
					watches.splice(k, 1)[0].dispose();
				case _:
			}
	} catch (e:haxe.Exception) {
		done(watches, store, was);
		throw e;
	}
	done(watches, store, was);
}

function done(watches:Array<Watched>, store:Null<Atoms>, was:Null<Atoms>) {
	for (w in watches)
		w.dispose();
	Atoms.current = was;
	Atoms.homeless = false;
	store?.dispose();
	try flush() catch (_:haxe.Exception) {}
}

// --- stores against a model

enum Op {
	Write(store:Int, signal:Int, value:Int);
	Update(store:Int, signal:Int, by:Int);
	WriteDerived(store:Int, node:Int, value:Int);
	Flush;
	Answer(store:Int, ask:Int, value:Int, fail:Bool);
	Make(store:Int);
	Dispose(store:Int);
	Clear(store:Int);
	Read(store:Int, node:Int, how:Int);
}

typedef Watch = {render:Bool, node:Int, how:Int, cleanup:Bool, writes:Bool};
typedef ModelSpec = {signals:Int, memos:Array<Made>, boundaries:Array<{node:Int, loading:Bool}>, effects:Array<Watch>, ops:Array<Op>};

// (store 0 the default, 1 to 7 made by the ops)
inline var STORES = 8;

function modelGen():Gen<ModelSpec>
	return c -> {
		var signals = c.draw(int(1, 20));
		var memos = c.draw(memosGen(signals, 40, 8));
		var numbers = signals + memos.length;
		var boundaries = [for (_ in 0...c.draw(int(0, 3))) {node: c.draw(int(0, numbers - 1)), loading: c.draw(bool())}];
		var nodes = numbers + boundaries.length;
		var effects = [for (_ in 0...c.draw(int(1, 6))) {render: c.draw(bool()), node: c.draw(int(0, nodes - 1)), how: c.draw(int(0, 3)), cleanup: c.draw(bool()), writes: c.draw(int(0, 3)) == 0}];
		var derived = [for (i => m in memos) if (m.match(Derived(_))) signals + i];
		var ops = [for (_ in 0...c.draw(int(1, 300))) switch c.draw(int(0, 12)) {
			case 0 | 1: Write(c.draw(int(0, STORES - 1)), c.draw(int(0, signals - 1)), c.draw(int(0, 5)));
			case 2: Update(c.draw(int(0, STORES - 1)), c.draw(int(0, signals - 1)), c.draw(int(1, 3)));
			case 3 if (derived.length > 0): WriteDerived(c.draw(int(0, STORES - 1)), derived[c.draw(int(0, derived.length - 1))], c.draw(int(0, 9)));
			case 3 | 4 | 5: Flush;
			case 6 | 7: Answer(c.draw(int(0, STORES - 1)), c.draw(int(0, 3)), c.draw(int(0, 9)), c.draw(int(0, 3)) == 0);
			case 8: Make(c.draw(int(1, STORES - 1)));
			case 9: c.draw(bool()) ? Dispose(c.draw(int(1, STORES - 1))) : Clear(c.draw(int(1, STORES - 1)));
			case _: Read(c.draw(int(0, STORES - 1)), c.draw(int(0, nodes)), c.draw(int(0, 3)));
		}];
		{signals: signals, memos: memos, boundaries: boundaries, effects: effects, ops: ops};
	};

// (one graph: its nodes, its signals, its writable derived signals by node, its sink)
class Built {
	public final nodes:Array<Void->Dynamic> = [];
	public final signals:Array<Signal<Int>> = [];
	public final derived = new Map<Int, Signal<Int>>();
	// (what effects write: an owned-write signal nothing reads but the ops)
	public final sink:Signal<Int> = signalOf(0, {ownedWrite: true});

	public function new() {}
}

// what each store's effects logged, and its asks (in the order asked)
class Seen {
	public final logs = [for (_ in 0...STORES) new Array<String>()];
	public final asks = [for (_ in 0...STORES) new Array<{later:Later<Int>, of:Int, memo:Int}>()];
	// (the flush the logs are of: within one, effects' order is not compared)
	public var round = 0;

	public function new() {}

	// a store's log, each flush's entries sorted
	public function log(store:Int):Array<String> {
		var l = logs[store].copy();
		l.sort(Reflect.compare);
		return l;
	}

	public function ask(store:Int, memo:Int, of:Int):Later<Int> {
		var l = new Later<Int>();
		asks[store].push({later: l, of: of, memo: memo});
		return l;
	}

	// (the k-th open ask of a store, by its memo, then as asked: a store
	// makes its memos' nodes in the order they are read, a fresh graph as
	// they are made; cancelled ones left out)
	public function open(store:Int, k:Int):Null<{later:Later<Int>, of:Int, memo:Int}> {
		var l = [for (a in asks[store]) if (!a.later.cancelled) a];
		haxe.ds.ArraySort.sort(l, (a, b) -> a.memo - b.memo);
		return k < l.length ? l[k] : null;
	}
}

// (the graph made, ownerless; its effects in an owner given, or none; store: whose it is now)
function build(spec:ModelSpec, seen:Seen, store:Void->Int, ?owner:Owner):Built {
	var b = new Built();
	for (k in 0...spec.signals) {
		var s:Signal<Int> = signalOf(k % 5);
		b.signals.push(s);
		b.nodes.push(() -> s());
	}
	for (i => m in spec.memos) {
		var n = made(m, i, b.nodes, (memo, of) -> seen.ask(store(), memo, of));
		b.nodes.push(n.read);
		if (n.derived != null) b.derived.set(spec.signals + i, n.derived);
	}
	for (x in spec.boundaries) {
		var n = b.nodes[x.node];
		var f:Memo<Dynamic> = x.loading ? loadingBoundary(() -> n(), () -> ("loading" : Dynamic)) : errorBoundary(() -> n(), (e, _) -> ('caught ${e()}' : Dynamic));
		b.nodes.push(() -> f());
	}
	var sink = b.sink;
	b.nodes.push(() -> sink());
	runWithOwner(owner, () -> for (k => e in spec.effects) {
		var n = b.nodes[e.node];
		var log = (v:Dynamic) -> seen.logs[store()].push(StringTools.lpad('${seen.round}', "0", 4) + ' e$k: $v');
		var compute = (_ -> read(n, e.how) : Compute<Dynamic>), apply = ((v:Dynamic, _) -> {
			log(v);
			if (e.writes && Std.isOfType(v, Int)) sink(v);
			e.cleanup ? () -> log('cleanup $v') : null;
		} : Apply<Dynamic>);
		var error = (x:Dynamic) -> log('error $x');
		if (e.render) renderEffect(compute, apply, error) else effect(compute, apply, error);
	});
	return b;
}

function model(spec:ModelSpec) {
	var real = new Seen(), copies = new Seen();
	// (the real: made at the top level, its effects made again in each store)
	Atoms.record = true;
	var top = build(spec, real, () -> Atoms.current == null ? 0 : Std.parseInt(Atoms.current.name));
	var stores:Array<Null<Atoms>> = [for (_ in 0...STORES) null];
	// (the model: a fresh graph a store, made at home in a store of its own
	// (as a screen's component's), its effects owned by a root of its own;
	// its writes and answers queued, taken by a flush of its own)
	var copy:Array<Null<{built:Built, dispose:Void->Void, queued:Array<Void->Void>, store:Atoms}>> = [for (_ in 0...STORES) null];
	function fresh(k:Int) {
		// (the real's top-level effects not made again in it: it has its own)
		var recorded = @:privateAccess Atoms.effects;
		@:privateAccess Atoms.effects = [];
		var home = new Atoms('model $k'), d:Void->Void = null;
		@:privateAccess Atoms.effects = recorded;
		var built = home.run(() -> {
			var owner = root(dispose -> {
				d = dispose;
				getOwner();
			});
			build(spec, copies, () -> k, owner);
		});
		copy[k] = {
			built: built,
			dispose: () -> {
				d();
				home.dispose();
			},
			queued: [],
			store: home
		};
	}
	// (a new store's nodes of the memos made at once, as a fresh graph's are
	// computed as they are made: an ask is a side effect of that computing)
	function madeIn(k:Int)
		stores[k].run(() -> for (n in top.nodes.slice(spec.signals))
			attempt(n));
	function flushed() {
		real.round++;
		copies.round++;
		flush();
		for (c in copy)
			if (c != null && c.queued.length > 0) {
				c.store.run(() -> for (q in c.queued)
					q());
				c.queued.resize(0);
				flush();
			}
	}
	function inStore<T>(k:Int, f:Void->T):T
		return k == 0 ? f() : stores[k].run(f);
	fresh(0);
	try {
		flushed();
		for (op in spec.ops) {
			switch op {
				case Write(k, i, v) | Update(k, i, v) if (copy[k] != null):
					var add = op.match(Update(_, _, _));
					inStore(k, () -> add ? top.signals[i](x -> x + v) : top.signals[i](v));
					var s = copy[k].built.signals[i];
					copy[k].queued.push(() -> add ? s(x -> x + v) : s(v));
				case WriteDerived(k, n, v) if (copy[k] != null):
					inStore(k, () -> top.derived.get(n)(v));
					var s = copy[k].built.derived.get(n);
					copy[k].queued.push(() -> s(v));
				case Flush:
					flushed();
				case Answer(k, j, v, fail) if (copy[k] != null):
					var a = real.open(k, j), b = copies.open(k, j);
					equals(a?.of, b?.of, 'store $k\'s ask $j');
					if (a != null && b != null)
						if (fail) {
							a.later.reject('e$v');
							copy[k].queued.push(() -> b.later.reject('e$v'));
						} else {
							a.later.resolve(a.of * 10 + v);
							copy[k].queued.push(() -> b.later.resolve(b.of * 10 + v));
						}
				case Make(k) if (copy[k] == null):
					stores[k] = new Atoms('$k');
					madeIn(k);
					fresh(k);
					// (its effects' first applies before anything is written in it, on both sides)
					flushed();
				case Dispose(k) if (copy[k] != null && k > 0):
					stores[k].dispose();
					stores[k] = null;
					copy[k].dispose();
					copy[k] = null;
					real.asks[k].resize(0);
					copies.asks[k].resize(0);
					flushed();
				case Clear(k) if (copy[k] != null && k > 0):
					stores[k].clear();
					madeIn(k);
					copy[k].dispose();
					fresh(k);
					real.asks[k].resize(0);
					copies.asks[k].resize(0);
					flushed();
				case Read(k, n, how) if (copy[k] != null):
					equals(inStore(k, () -> attempt(() -> read(top.nodes[n], how))), copy[k].store.run(() -> attempt(() -> read(copy[k].built.nodes[n], how))), 'store $k reads node $n ($how)');
				case _:
			}
			for (k in 0...STORES)
				equals(real.log(k), copies.log(k), 'store $k\'s effects after $op');
		}
	} catch (e:haxe.Exception) {
		cleanup(stores, copy);
		throw e;
	}
	cleanup(stores, copy);
}

function cleanup(stores:Array<Null<Atoms>>, copies:Array<Dynamic>) {
	for (s in stores)
		if (s != null) s.dispose();
	for (c in copies)
		if (c != null) c.dispose();
	Atoms.forget();
	try flush() catch (_:haxe.Exception) {}
}
