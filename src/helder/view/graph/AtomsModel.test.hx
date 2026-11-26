package helder.view.graph;

import helder.test.Gen;
import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// Atoms against a model (atly's fuzz test's way): a random graph of
// signals, memos (sums, diamonds, conditional reads, async ones answered
// by hand) and effects, made once at the top level, then random ops over
// stores: a write or an update in one, a flush, an answer or a failure of
// one's pending ask, a store made, let go, cleared, reads anywhere. The
// model: the same graph made afresh for each store, no stores at all.
// Every store's reads, isPending and latest, and effect logs equal its
// copy's. HELDER_PROPERTY_SEED replays a run's cases. (A new store reads
// each memo once: a fresh graph computes its memos as they are made, a
// store its node of one when first read there; an async memo's ask is a
// side effect of that computing, the values are the same either way.)
function tests() {
	test("stores against fresh copies of the graph", () -> property(gen(), run, {cases: 150}));
}

enum Made {
	Sum(a:Int, b:Int);
	Cond(c:Int, a:Int, b:Int);
	Async(a:Int);
}

enum Op {
	Write(store:Int, signal:Int, value:Int);
	Update(store:Int, signal:Int, by:Int);
	Flush;
	Answer(store:Int, ask:Int, value:Int, fail:Bool);
	Make(store:Int);
	Dispose(store:Int);
	Clear(store:Int);
	Read(store:Int, node:Int, how:Int);
}

typedef Spec = {signals:Int, memos:Array<Made>, effects:Array<{render:Bool, node:Int, how:Int}>, ops:Array<Op>};

// (stores 0 the default, 1 to 3 made by the ops)
inline var STORES = 4;

function gen():Gen<Spec>
	return c -> {
		var signals = c.draw(int(1, 3)), memos = [];
		for (k in 0...c.draw(int(1, 5))) {
			var n = signals + k;
			memos.push(switch c.draw(int(0, 2)) {
				case 0: Sum(c.draw(int(0, n - 1)), c.draw(int(0, n - 1)));
				case 1: Cond(c.draw(int(0, n - 1)), c.draw(int(0, n - 1)), c.draw(int(0, n - 1)));
				case _: Async(c.draw(int(0, n - 1)));
			});
		}
		var nodes = signals + memos.length;
		var effects = [for (_ in 0...c.draw(int(1, 3))) {render: c.draw(bool()), node: c.draw(int(0, nodes - 1)), how: c.draw(int(0, 2))}];
		var ops = [for (_ in 0...c.draw(int(1, 30))) switch c.draw(int(0, 9)) {
			case 0 | 1: Write(c.draw(int(0, STORES - 1)), c.draw(int(0, signals - 1)), c.draw(int(0, 5)));
			case 2: Update(c.draw(int(0, STORES - 1)), c.draw(int(0, signals - 1)), c.draw(int(1, 3)));
			case 3 | 4: Flush;
			case 5: Answer(c.draw(int(0, STORES - 1)), c.draw(int(0, 3)), c.draw(int(0, 9)), c.draw(int(0, 3)) == 0);
			case 6: Make(c.draw(int(1, STORES - 1)));
			case 7: c.draw(bool()) ? Dispose(c.draw(int(1, STORES - 1))) : Clear(c.draw(int(1, STORES - 1)));
			case _: Read(c.draw(int(0, STORES - 1)), c.draw(int(0, nodes - 1)), c.draw(int(0, 2)));
		}];
		{signals: signals, memos: memos, effects: effects, ops: ops};
	};

// (one graph: its nodes, what its effects logged and its asks, by store)
class Built {
	public final nodes:Array<Void->Dynamic> = [];
	public final signals:Array<Signal<Int>> = [];

	public function new() {}
}

// what each store's effects logged, and its asks not answered yet (in the order asked)
class Seen {
	public final logs = [for (_ in 0...STORES) new Array<String>()];
	// (the flush the logs are of: within one, effects' order is not compared)
	public var round = 0;

	// a store's log, each flush's entries sorted
	public function log(store:Int):Array<String> {
		var l = logs[store].copy();
		l.sort(Reflect.compare);
		return l;
	}
	public final asks = [for (_ in 0...STORES) new Array<{later:Later<Int>, of:Int, memo:Int}>()];

	public function new() {}

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

// (the graph made, ownerless: its effects in an owner given, or none; store: whose it is now)
function build(spec:Spec, seen:Seen, store:Void->Int, ?owner:Owner):Built {
	var b = new Built();
	for (k in 0...spec.signals) {
		var s:Signal<Int> = signalOf(k);
		b.signals.push(s);
		b.nodes.push(() -> s());
	}
	for (i => m in spec.memos) {
		var ns = b.nodes;
		var f:Memo<Dynamic> = switch m {
			case Sum(x, y): memo(() -> (ns[x]() : Int) + (ns[y]() : Int));
			case Cond(c, x, y): memo(() -> (ns[c]() : Int) % 2 == 0 ? ns[x]() : ns[y]());
			case Async(x): memo(() -> (seen.ask(store(), i, ns[x]()) : Dynamic));
		}
		b.nodes.push(() -> f());
	}
	runWithOwner(owner, () -> for (k => e in spec.effects) {
		var n = b.nodes[e.node];
		var log = (v:Dynamic) -> seen.logs[store()].push(StringTools.lpad('${seen.round}', "0", 4) + ' e$k: $v');
		var compute = (_ -> read(n, e.how) : Compute<Dynamic>), apply = ((v:Dynamic, _) -> {
			log(v);
			null;
		} : Apply<Dynamic>);
		var error = (x:Dynamic) -> log('error $x');
		if (e.render) renderEffect(compute, apply, error) else effect(compute, apply, error);
	});
	return b;
}

// a node read as it is, as isPending, as latest (what it throws: its message)
function read(n:Void->Dynamic, how:Int):Dynamic
	return switch how {
		case 0: n();
		case 1: isPending(() -> n());
		case _: latest(() -> n());
	}

function attempt(f:Void->Dynamic):String
	return try Std.string(f()) catch (e:haxe.Exception) "throws " + e.message catch (e:Dynamic) "throws " + Std.string(e);

function run(spec:Spec) {
	var real = new Seen(), model = new Seen();
	// (the real: made at the top level, its effects made again in each store)
	Atoms.record = true;
	var top = build(spec, real, () -> Atoms.current == null ? 0 : Std.parseInt(Atoms.current.name));
	var stores:Array<Null<Atoms>> = [for (_ in 0...STORES) null];
	// (the model: a fresh graph a store, its effects owned by a root of its own)
	var copies:Array<Null<{built:Built, dispose:Void->Void, writes:Array<Void->Void>}>> = [for (_ in 0...STORES) null];
	function copy(k:Int) {
		var d:Void->Void = null;
		var owner = root(dispose -> {
			d = dispose;
			getOwner();
		});
		copies[k] = {built: build(spec, model, () -> k, owner), dispose: d, writes: []};
	}
	copy(0);
	// (a flush: the real's, then each copy's writes flushed apart, its transactions its own as a store's)
	function flushed() {
		real.round++;
		model.round++;
		flush();
		for (c in copies)
			if (c != null && c.writes.length > 0) {
				for (w in c.writes)
					w();
				c.writes.resize(0);
				flush();
			}
	}
	// (a store's nodes of the memos made at once, as a fresh graph's memos
	// are computed as they are made: a store makes its node of one when it
	// is first read there, and an ask is that computing's side effect)
	function made(k:Int)
		stores[k].run(() -> for (n in top.nodes.slice(spec.signals))
			attempt(n));
	function inStore<T>(k:Int, f:Void->T):T {
		var s = stores[k];
		return k == 0 ? f() : s.run(f);
	}
	try {
		flush();
		for (op in spec.ops) {
			switch op {
				case Write(k, i, v) | Update(k, i, v) if (copies[k] != null):
					var add = op.match(Update(_, _, _));
					inStore(k, () -> add ? top.signals[i](x -> x + v) : top.signals[i](v));
					var s = copies[k].built.signals[i];
					copies[k].writes.push(() -> add ? s(x -> x + v) : s(v));
				case Flush:
					flushed();
				case Answer(k, j, v, fail) if (copies[k] != null):
					var a = real.open(k, j), b = model.open(k, j);
					equals(a?.of, b?.of, 'store $k\'s ask $j');
					// (the copy's answered with its writes: one flush takes both, as the store's)
					if (a != null && b != null)
						if (fail) {
							a.later.reject('e$v');
							copies[k].writes.push(() -> b.later.reject('e$v'));
						} else {
							a.later.resolve(a.of * 10 + v);
							copies[k].writes.push(() -> b.later.resolve(b.of * 10 + v));
						}
				case Make(k) if (copies[k] == null):
					stores[k] = new Atoms('$k');
					made(k);
					copy(k);
					// (its effects' first applies: before anything is written in it, on both sides)
					flushed();
				case Dispose(k) if (copies[k] != null):
					stores[k].dispose();
					stores[k] = null;
					copies[k].dispose();
					copies[k] = null;
					real.asks[k].resize(0);
					model.asks[k].resize(0);
				case Clear(k) if (copies[k] != null):
					stores[k].clear();
					made(k);
					copies[k].dispose();
					copy(k);
					flushed();
					real.asks[k].resize(0);
					model.asks[k].resize(0);
				case Read(k, n, how) if (copies[k] != null):
					equals(inStore(k, () -> attempt(() -> read(top.nodes[n], how))), attempt(() -> read(copies[k].built.nodes[n], how)), 'store $k reads node $n ($how)');
				case _:
			}
			for (k in 0...STORES)
				equals(real.log(k), model.log(k), 'store $k\'s effects after $op');
		}
	} catch (e:haxe.Exception) {
		cleanup(stores, copies);
		throw e;
	}
	cleanup(stores, copies);
}

function cleanup(stores:Array<Null<Atoms>>, copies:Array<Dynamic>) {
	for (s in stores)
		if (s != null) s.dispose();
	for (c in copies)
		if (c != null) c.dispose();
	Atoms.forget();
	try flush() catch (_:haxe.Exception) {}
}
