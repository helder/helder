package helder.view.graph;

// A store of values, Jotai's: every signal and memo is an atom whose value
// is per store. Each keeps the node of the store it was made in inline (its
// home: the default store, null, during a program's start; a screen's
// store when made in a screen); read or written in another store it
// resolves that store's node, made then from its initial value (a memo's,
// its function, computed from that store's nodes), owned by the store's
// root and kept in the store's map, by the atom: a store let go drops all
// of it, an atom keeps nothing of other stores, no weak reference needed. The current store is the current screen's (helder.ui.ScreenContext:
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
	// (tests only, tests/view/graph's foreign mode: signals and unowned memos
	// made at home in the default store whatever store is current, as a top
	// level's are, so that every read in a store goes through its node of them)
	@:noCompletion public static var homeless = false;
	// (the default store's top-level effects, made again in each store; kept
	// where stores are made, -D helder.scenarios: else nothing is kept)
	@:noCompletion public static var record = #if helder.scenarios true #else false #end;
	static var effects:Array<Node<Dynamic>> = [];

	// its name (a screen's: fast refresh's scope of its values)
	public final name:String;
	// (what owns its nodes; its node of each atom read here not at home, by the atom)
	var root = new Owner(null);
	var nodes = new haxe.ds.ObjectMap<Node<Dynamic>, Node<Dynamic>>();

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

	// its nodes let go (a screen's, gone); nothing of it is left on the atoms,
	// and a read or write in it after is an error
	public function dispose() {
		drop();
		disposed = true;
	}

	var disposed = false;
	// (bumped as it is cleared or let go: what was set going before, a timer, is let go too)
	public var generation(default, null) = 0;

	// whether what was set going in store at generation still runs (the default's always)
	public static function live(store:Null<Atoms>, generation:Int):Bool
		return store == null || !store.disposed && store.generation == generation;

	function drop() {
		generation++;
		root.dispose();
		nodes = new haxe.ds.ObjectMap();
	}

	// (tests: the top-level effects recorded let go and forgotten, none recorded after)
	@:noCompletion public static function forget() {
		for (e in effects)
			e.dispose();
		effects = [];
		record = #if helder.scenarios true #else false #end;
	}

	// (atom's node here)
	inline function of<T>(atom:Node<T>):Node<T> {
		var n:Null<Node<T>> = cast nodes.get(cast atom);
		return n != null ? n : make(atom);
	}

	function replay() {
		effects = [for (e in effects) if (!e.disposed) e];
		if (effects.length == 0) return;
		run(() -> {
			var saved = Owner.current;
			Owner.current = root;
			for (e in effects)
				try Node.effect(e.fn, e.apply, e.onFailure, e.kind == Node.RENDER) catch (x:haxe.Exception) {
					Owner.current = saved;
					throw helder.async.Errors.kept(x);
				}
			Owner.current = saved;
		});
	}

	function make<T>(atom:Node<T>):Node<T> {
		if (disposed) throw new Owner.GraphError('a store let go ($name) read or written');
		var n = atom.copy(this);
		nodes.set(cast atom, cast n);
		var f = atom.copied;
		if (f != null) f(cast n, this);
		if (n.kind == Node.COMPUTED && atom.remake == null) n.recompute();
		return n;
	}

	// f run with this store current
	public function run<R>(f:Void->R):R {
		if (disposed) throw new Owner.GraphError('a store let go ($name) run');
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
