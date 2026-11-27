package viewer;

import helder.scenario.Scenario.scenario;
import helder.scenario.Steps.tap;
import helder.scenario.Steps.press;
import helder.scenario.Steps.resize;

// What the UI monkey found in the viewer (tests/viewer/Monkey.test.hx), as
// it wrote them: each replayed by the monkey's invariants
// (Monkey.test.hx's "found" test), a bug fixed kept as its regression test,
// one still open skipped there with its reason. Open in the studio as any
// scenario.

// an audio file playing on a phone, the window resized past the phone's width and back: two players
final twoPlayers = scenario({
	name: "Found/Two players",
	size: [390, 844],
	dark: true,
	time: "2045-09-12T00:00:01Z",
	locale: "ar-EG",
	settings: {textScale: 1.3},
	boot: () -> {
		viewer.Monkey_test.madePhone.boot();
		viewer.Sandbox.made([{name: "", kind: viewer.Sandbox.MadeKind.Audio}, {name: "ma\ttpé!عaéa`اﬁna8^\"\r\"&i‮🇧🇪ωi&éhyY‮ea\t文 b`ṇ̃ﬁ", kind: viewer.Sandbox.MadeKind.Folder}, {name: "", kind: viewer.Sandbox.MadeKind.Folder}, {name: "Name", kind: viewer.Sandbox.MadeKind.Folder}, {name: "Name", kind: viewer.Sandbox.MadeKind.Folder}, {name: "\r\nωm-𝔸]\raא‮$e👨‍👩‍👧hṇ̃Ẃω\n️AاKy1à=؜%`#oAX3‏ IlאT:", kind: viewer.Sandbox.MadeKind.Markdown}, {name: "ma中ש中😀😀WWWmWש中שaa中mWשש😀a😀中😀ששW中😀😀m中שama中", kind: viewer.Sandbox.MadeKind.Folder}]);
	},
	steps: [
		tap({name: "M4A unnamed.m4a", role: "gridcell"}),
		resize(756, 1225),
		press("ArrowRight"),
		resize(253, 189)
	]
});
