package helder.scenario;

// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, set, time, seed, size, dark, loop, play}), the real
// program (its main) at a moment of its named data signals' values
// (helder.view.Named), a screen of the studio's preview host beside the
// stories (helder/story's screens(stories, scenarios, main))
@:typescript("helder/scenario")
@:typescript.types(helder.scenario.Scenario)
@:typescript.functions(scenario = helder.scenario.Scenario.define)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
