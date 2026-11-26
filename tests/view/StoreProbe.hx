// A store (helder.view.graph.Atoms) for the TypeScript tests
// (tests/typescript/helder/stores.ts): what runs in it, and what it sets
// running later (a timer, a promise's continuation), reads its nodes
class StoreProbe {
	final store:helder.view.graph.Atoms;

	public function new(name:String)
		store = new helder.view.graph.Atoms(name);

	public function run(f:Void->Void)
		store.run(f);

	public function dispose()
		store.dispose();
}
