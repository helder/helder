package viewer;

import helder.scenario.Scenario.scenario;
import helder.scenario.Steps.tap;
import helder.scenario.Steps.press;
import helder.scenario.Steps.resize;
import helder.scenario.Steps.scroll;
import helder.scenario.Steps.wait;

// What the UI monkey found in the viewer (tests/viewer/Monkey.test.hx), as
// it wrote them: each replayed by the monkey's invariants
// (Monkey.test.hx's "found" test), a bug fixed kept as its regression test,
// one still open skipped there with its reason. Open in the studio as any
// scenario: each names only the app's own code (not a test's scenario: the
// studio builds none of the tests).

// an audio file playing on a phone, the window resized past the phone's width and back: two players
final twoPlayers = scenario({
	name: "Found/Two players",
	size: [390, 844],
	dark: true,
	time: "2045-09-12T00:00:01Z",
	locale: "ar-EG",
	settings: {textScale: 1.3},
	boot: () -> {
		viewer.Shell.act(Go(viewer.Sandbox.MADE));
		viewer.Sandbox.made([{name: "", kind: viewer.Sandbox.MadeKind.Audio}, {name: "ma\ttpé!عaéa`اﬁna8^\"\r\"&i‮🇧🇪ωi&éhyY‮ea\t文 b`ṇ̃ﬁ", kind: viewer.Sandbox.MadeKind.Folder}, {name: "", kind: viewer.Sandbox.MadeKind.Folder}, {name: "Name", kind: viewer.Sandbox.MadeKind.Folder}, {name: "Name", kind: viewer.Sandbox.MadeKind.Folder}, {name: "\r\nωm-𝔸]\raא‮$e👨‍👩‍👧hṇ̃Ẃω\n️AاKy1à=؜%`#oAX3‏ IlאT:", kind: viewer.Sandbox.MadeKind.Markdown}, {name: "ma中ש中😀😀WWWmWש中שaa中mWשש😀a😀中😀ששW中😀😀m中שama中", kind: viewer.Sandbox.MadeKind.Folder}]);
	},
	steps: [
		tap({name: "M4A unnamed.m4a", role: "gridcell"}),
		resize(756, 1225),
		press("ArrowRight"),
		resize(253, 189)
	]
});

// a phone's grid scrolled, a document opened from it, its wheel: the grid's behind it, latched
final markdownWheel = scenario({
	name: "Found/A document's wheel after a tap",
	size: [390, 844],
	boot: () -> viewer.Viewer_scenario.phone.boot(),
	steps: [
		resize(240, 335),
		scroll({x: 120, y: 168}, "end"),
		tap("Files"),
		scroll({x: 120, y: 168}, "end")
	]
});

// the made folder's grid wheeled to its end at 975 x 620: 6.6 points short of it, for good
final gridEnd = scenario({
	name: "Found/A grid wheeled to its end twice",
	size: [2560, 1440],
	dark: true,
	time: "1970-01-09T00:00:05Z",
	boot: () -> {
		viewer.Shell.act(Go(viewer.Sandbox.MADE));
		viewer.Sandbox.made([{name: "", kind: viewer.Sandbox.MadeKind.Photo}, {name: "", kind: viewer.Sandbox.MadeKind.Webp}, {name: "Name", kind: viewer.Sandbox.MadeKind.Small}, {name: "", kind: viewer.Sandbox.MadeKind.Markdown}, {name: "a", kind: viewer.Sandbox.MadeKind.Folder}, {name: "a", kind: viewer.Sandbox.MadeKind.Markdown}, {name: "h\t8🇧🇪\r\né7�️﻿　بL{srk;qRm~fa\n❤️j`�\\️　,a)\\0`ω ", kind: viewer.Sandbox.MadeKind.Folder}, {name: "Name", kind: viewer.Sandbox.MadeKind.Small}, {name: "", kind: viewer.Sandbox.MadeKind.Audio}, {name: "Name", kind: viewer.Sandbox.MadeKind.Folder}, {name: "a", kind: viewer.Sandbox.MadeKind.Audio}, {name: "a", kind: viewer.Sandbox.MadeKind.Text}, {name: "a", kind: viewer.Sandbox.MadeKind.Pdf}, {name: "b\r\nfef[fr", kind: viewer.Sandbox.MadeKind.Photo}, {name: "WWaWשm😀mWW中שWmשmaWש中am中W😀m中WamWWa中m中maa中中", kind: viewer.Sandbox.MadeKind.Text}, {name: "a", kind: viewer.Sandbox.MadeKind.Webp}, {name: "中中😀aWWmaW😀aששm中שmWשש😀😀a😀aWשש😀ששa😀ש😀😀ששaW", kind: viewer.Sandbox.MadeKind.Pdf}, {name: "Name", kind: viewer.Sandbox.MadeKind.Text}, {name: "é@`kpá éb_3ب}ö g�DعSﬁhب\\`؜j ‍éa❤️k　　\n👍🏽_M", kind: viewer.Sandbox.MadeKind.Pdf}, {name: "", kind: viewer.Sandbox.MadeKind.Photo}, {name: "", kind: viewer.Sandbox.MadeKind.Folder}, {name: "%?à`gbOY‏ת~2bVاb﻿eﬁṇ̃𝔸❤️y　؜zb$שc dnt \n! ß  s", kind: viewer.Sandbox.MadeKind.Empty}, {name: "", kind: viewer.Sandbox.MadeKind.Gif}, {name: " d️eà ÁuN`|\"` é W%ﬁP\rع` n文`A👨‍👩‍👧_🏳️‍🌈ab﻿中文`hF", kind: viewer.Sandbox.MadeKind.Text}, {name: "Name", kind: viewer.Sandbox.MadeKind.Empty}]);
	},
	steps: [
		wait(0.5),
		resize(975, 620),
		scroll("Files", "end"),
		scroll("Files", "end")
	]
});
