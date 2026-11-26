package view.graph;

import helder.test.Test;
import helder.view.graph.Atoms;

// The graph's tests through stores (helder.view.graph.Atoms), by
// HELDER_GRAPH_STORES: "home", each test's body run in a fresh store, its
// nodes made at home there; "foreign", its signals and unowned memos made
// at home in the default store (a top level's) and every read, write and
// computation in a fresh store, through that store's nodes of them; unset,
// as always (tests/README.md, view-stores)
class Stores {
	public static final mode = Sys.getEnv("HELDER_GRAPH_STORES") ?? "";

	static var store:Null<Atoms> = null;

	// a test that counts a top-level memo's runs, left out in foreign mode:
	// there the memo's default node computes once as it is made (as a top
	// level's does at a program's start), the store's node again, and the
	// count sees one run more; the values are the same
	public static function counted(t:helder.test.Runner.Entry)
		if (mode == "foreign") t.skip();

	// (a file's tests: its hooks)
	public static function hooks() {
		if (mode == "") return;
		if (mode != "home" && mode != "foreign") throw 'HELDER_GRAPH_STORES: home or foreign, not $mode';
		beforeEach(() -> {
			store = new Atoms("test");
			Atoms.current = store;
			Atoms.homeless = mode == "foreign";
		});
		afterEach(() -> {
			Atoms.current = null;
			Atoms.homeless = false;
			store?.dispose();
			store = null;
		});
	}
}
