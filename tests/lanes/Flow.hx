package lanes;

import lanes.Tools.*;

class Flow {
	public static final LANES:Array<Lane> = [
		{name: "flow-differential", about: "helder.ui.flow's inline layout against headless Chromium's in Ahem (generated and kept cases)", run: differential}
	];

	// (a browser: not headless)
	static function differential() {
		exe("bin/flow/InlineDiffCheck", cps(["src", "tests/flow"]).concat(["-main", "InlineDiffCheck"]));
		run(NODE, ["tests/flow/differential.mjs", exePath("bin/flow/InlineDiffCheck", HOST)]);
	}
}
