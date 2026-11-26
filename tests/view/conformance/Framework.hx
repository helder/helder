import helder.view.graph.Atoms;
import helder.view.graph.Graph;

// helder.view's graph as reactive-framework-test-suite's ReactiveFramework
// (conformance.mjs), as atly's conformance adapter is. The graph defers
// writes to a flush (Solid 2's): a write outside a batch flushes at once,
// a batch at its end, an effect made outside one runs its first time at
// once. An effect's function is its compute (tracked); what it returns is
// its cleanup, given back by apply. begin(mode): "plain"; "home", the
// case's nodes made, read, written and computed in a fresh store;
// "foreign", made at home in the default store, read, written and computed
// in a fresh store through its nodes of them (tests/view/graph/Stores.hx)
@:expose("helderGraph")
class Framework {
	static var depth = 0;
	static var store:Null<Atoms> = null;
	// (foreign: the computations run in the default store, the nodes' home: as made)
	static var homeRuns = 0;

	public static function home():Int
		return homeRuns;

	static function settle()
		if (depth == 0) Graph.flush();

	public static function begin(mode:String) {
		homeRuns = 0;
		if (mode == "plain") return;
		store = new Atoms("case");
		Atoms.current = store;
		Atoms.homeless = mode == "foreign";
	}

	public static function end() {
		Atoms.current = null;
		Atoms.homeless = false;
		store?.dispose();
		store = null;
		depth = 0;
	}

	public static function signal(init:Dynamic):Dynamic {
		var s = Graph.signalValue(init);
		return {
			read: () -> s(),
			write: (v:Dynamic) -> {
				s(v);
				settle();
			}
		};
	}

	public static function computed(fn:Void->Dynamic):Dynamic {
		var m = Graph.memo(_ -> {
			if (store != null && Atoms.current == null) homeRuns++;
			fn();
		});
		return {read: () -> m()};
	}

	public static function effect(fn:Void->Dynamic):Void->Void {
		var dispose = Graph.root(d -> {
			Graph.effect(_ -> fn(), (cleanup:Dynamic, _) -> Reflect.isFunction(cleanup) ? cleanup : null);
			d;
		});
		settle();
		return () -> {
			dispose();
			settle();
		};
	}

	public static function run(fn:Void->Void)
		fn();

	public static function batch(fn:Void->Void) {
		depth++;
		try fn() catch (e:Dynamic) {
			depth--;
			settle();
			throw e;
		}
		depth--;
		settle();
	}

	public static function untracked(fn:Void->Dynamic):Dynamic
		return Graph.untrack(fn);

	// (the graph's warnings, an effect's error skipped: not the suite's output)
	static function main()
		haxe.Log.trace = (_, ?_) -> {};
}
