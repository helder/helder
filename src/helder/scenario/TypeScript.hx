package helder.scenario;

// helder.scenario for TypeScript programs (helder.typescript):
// scenario({name, boot, time, zone, locale, settings, http, steps, seed, size, dark,
// loop, play}), the real program at a moment: its root rendered in a screen
// with a store of its own, boot writing the app's signals first, its steps
// (tap, type, press, scroll, drag, waitFor) after (helder/story's
// screens(stories, scenarios), the studio's preview host)
@:typescript("helder/scenario")
@:typescript.types(helder.scenario.Scenario, helder.scenario.Steps.Step, helder.scenario.Steps.Query)
@:typescript.functions(scenario = helder.scenario.Scenario.define, hold = helder.scenario.Player.hold, play = helder.scenario.Player.run,
	tap = helder.scenario.Steps.tap, type = helder.scenario.Steps.type, press = helder.scenario.Steps.press, scroll = helder.scenario.Steps.scroll,
	drag = helder.scenario.Steps.drag, waitFor = helder.scenario.Steps.waitFor)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
