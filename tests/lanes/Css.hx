package lanes;

import lanes.Tools.*;

class Css {
	public static final LANES:Array<Lane> = [
		{name: "css", about: "helder.css's property table, grammars, values and syntax against WPT's fixtures and css-parsing-tests", run: css}
	];

	static function css() {
		exe("bin/css/CssCheck", cps(["src", "tests/css"]).concat(["-main", "CssCheck"]));
		run(exePath("bin/css/CssCheck", HOST), []);
		// (BLESS=1: the syntax manifest's pending cases from the results)
		exe("bin/css/CssConformanceCheck", cps(["src", "tests/css"]).concat(["-main", "CssConformanceCheck"]));
		run(exePath("bin/css/CssConformanceCheck", HOST), []);
		// (BLESS=1: values-manifest.json's skipped and pending cases from the results)
		exe("bin/css/CssValuesCheck", cps(["src", "tests/css"]).concat(["-main", "CssValuesCheck"]));
		run(exePath("bin/css/CssValuesCheck", HOST), []);
	}
}
