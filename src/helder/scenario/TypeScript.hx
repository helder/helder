package helder.scenario;

// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, boot, time, seed, size, dark, loop, play}), the real
// program at a moment: its root rendered in a screen with a store of its
// own, boot writing the app's signals first (helder/story's
// screens(stories, scenarios), the studio's preview host)
@:typescript("helder/scenario")
@:typescript.types(helder.scenario.Scenario)
@:typescript.functions(scenario = helder.scenario.Scenario.define, hold = helder.scenario.Player.hold, play = helder.scenario.Player.run)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
