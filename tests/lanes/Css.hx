package lanes;

import lanes.Tools.*;

class Css {
	public static final LANES:Array<Lane> = [
		{name: "css-differential", about: "helder.css's tokens and values against @csstools' on real stylesheets (fetched)", run: differential},
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

	// (not headless: it fetches the sheets, tests/css/sheets.mjs)
	static function differential() {
		exe("bin/css/CssDump", cps(["src", "tests/css"]).concat(["-main", "CssDump"]));
		run(NODE, ["tests/css/differential.mjs", exePath("bin/css/CssDump", HOST)]);
	}
}
