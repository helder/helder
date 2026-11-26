package helder.view.graph;

// A store of values, Jotai's: every signal and memo is an atom whose value
// is per store. Each keeps the node of the store it was made in inline (its
// home: the default store, null, during a program's start; a screen's
// store when made in a screen); read or written in another store it
// resolves that store's node, made then from its initial value (a memo's,
// its function, computed from that store's nodes) and owned by the store's
// root. The current store is the current screen's (helder.ui.ScreenContext:
// a preview host's screen, a scenario's); the default store sees through to
// a node's home, so a program without stores runs as it always has, and a
// signal made in a screen (a component's) never grows another node. An
// effect made with no owner in the default store (a top level's) is made
// again in each store as the store is made, owned by its root.
//
// The graph is not made again per store: two stores' nodes are disjoint
// parts of the one graph (a store's nodes read only that store's), so the
// one Scheduler and its transactions (Tx) stay right for all of them. A
// computation runs in its home; a flush stages each store's writes in a
// transaction of its own (Scheduler: an async read pending in one screen
// never holds another's commit; Tx.merge refuses two stores'). No node is
// shared between stores, a memo's either (an async memo's request is each
// screen's). A signal's node starts at its initial value, the same object
// in every store: right for immutable data, which a value should be.
// (Solid 2 has no instances of the graph, only layers over it that come
// and go: transactions, optimistic lanes, hydration's snapshot scopes; a
// store is atly's view that never closes.)
@:allow(helder.view.graph)
class Atoms {
	// the store values resolve in now (null: the default)
	public static var current:Null<Atoms> = null;
	// (a screen's context current: what it makes is not a top level's)
	@:noCompletion public static var screen = false;
	// (the default store's top-level effects, made again in each store)
	static final effects:Array<Node<Dynamic>> = [];

	// its name (a screen's: fast refresh's scope of its values)
	public final name:String;
	// (what owns its nodes of other homes' atoms, and those atoms)
	var root = new Owner(null);
	final atoms:Array<Node<Dynamic>> = [];

	public function new(name:String) {
		this.name = name;
		replay();
	}

	// its nodes let go: every value as it started (top-level effects made again)
	public function clear() {
		drop();
		root = new Owner(null);
		replay();
	}

	// its nodes let go (a screen's, gone)
	public function dispose()
		drop();

	function drop() {
		for (a in atoms) {
			var l = a.others;
			if (l != null) for (n in l.copy())
				if (n.home == this) l.remove(n);
		}
		atoms.resize(0);
		root.dispose();
	}

	function replay() {
		if (effects.length == 0) return;
		run(() -> {
			var saved = Owner.current;
			Owner.current = root;
			for (e in effects)
				if (!e.disposed) try Node.effect(e.fn, e.apply, e.onFailure, e.kind == Node.RENDER) catch (x:haxe.Exception) {
					Owner.current = saved;
					throw helder.async.Errors.kept(x);
				}
			Owner.current = saved;
		});
	}

	// (atom's node here)
	function make<T>(atom:Node<T>):Node<T> {
		var n = atom.copy(this);
		atoms.push(cast atom);
		var f = atom.copied;
		if (f != null) f(cast n, this);
		if (n.kind == Node.COMPUTED) n.recompute();
		return n;
	}

	// f run with this store current
	public function run<R>(f:Void->R):R {
		var was = current;
		current = this;
		try {
			var r = f();
			current = was;
			return r;
		} catch (e:haxe.Exception) {
			current = was;
			throw helder.async.Errors.kept(e);
		}
	}
}
