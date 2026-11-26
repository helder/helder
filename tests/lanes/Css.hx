package lanes;

import lanes.Tools.*;

class Css {
	public static final LANES:Array<Lane> = [
		{name: "css", about: "helder.css's property table and grammars against the WPT fixtures", run: css}
	];

	static function css() {
		exe("bin/css/CssCheck", cps(["src", "tests/css"]).concat(["-main", "CssCheck"]));
		run(exePath("bin/css/CssCheck", HOST), []);
	}
}
