package lanes;

import lanes.Tools.*;

class Css {
	public static final LANES:Array<Lane> = [
		{name: "css-differential", about: "helder.css's tokens and values against @csstools' on real stylesheets (fetched)", run: differential},
		{name: "css-reftests", about: "helder.ui.box against WPT's CSS 2.1 reftests, drawn natively (reftest-manifest.json; args: directories or names to run alone)", run: reftests},
		{name: "css-render", about: "a page drawn by helder.ui.box: css-render <page> <out.png> [width height] [--tree]", run: render},
		{name: "css", about: "helder.css's property table, grammars, values, syntax and selectors (parsed, matched on helder.dom) against WPT's fixtures and css-parsing-tests", run: css}
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
		exe("bin/css/CssSelectorsCheck", cps(["src", "tests/css"]).concat(["-main", "CssSelectorsCheck"]));
		run(exePath("bin/css/CssSelectorsCheck", HOST), []);
		// (BLESS=1: cascade-manifest.json's pending cases)
		exe("bin/css/CssCascadeCheck", cps(["src", "tests/css"]).concat(["-main", "CssCascadeCheck"]));
		run(exePath("bin/css/CssCascadeCheck", HOST), []);
		// (BLESS=1: counters-manifest.json's pending cases)
		exe("bin/css/CssCountersCheck", cps(["src", "tests/css"]).concat(["-main", "CssCountersCheck"]));
		run(exePath("bin/css/CssCountersCheck", HOST), []);
		themes();
	}

	// (a program styled by sheets compiled at build time alone, CssTheme:
	// its values, and its symbols without a CSS tokenizer or parser; the
	// same parsing a sheet when it runs has them, so the check checks)
	static function themes() {
		if (Sys.systemName() == "Windows") return;
		var parser = ["helder_css_Tokenizer", "helder_css_Parser", "helder_css__Parser_", "helder_css_SelectorParser", "helder_css__CssSheet_Builder"];
		var expected = "block 14px 28px 0px 1px rgb(0, 128, 0) rgb(0, 0, 200) 12px 6px";
		for (mode in ["theme", "parse"]) {
			var out = 'bin/css/ThemeProbe-$mode';
			exe(out, cps(["src", "tests/css"]).concat(["-main", "ThemeProbe", "-dce", "full", "-D", "hxmc.symbols"]).concat(mode == "parse" ? ["-D", "css.parse"] : []));
			var got = StringTools.trim(output(exePath(out, HOST), [])).split("\n").join(" ");
			if (got != expected) throw new Failed('$out: "$got", expected "$expected"');
			var symbols = output("nm", [exePath(out, HOST)]).split("\n");
			var linked = [for (p in parser) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
			if (mode == "theme" && linked.length > 0) throw new Failed('$out links a CSS parser: ${linked.join(", ")}');
			if (mode == "parse" && linked.length < 3) throw new Failed('$out: no parser in its symbols (${linked.join(", ")}): the check checks nothing');
			Sys.println('$out: ${Math.round(sys.FileSystem.stat(exePath(out, HOST)).size / 1024)} KB with symbols, ${linked.length == 0 ? "no CSS parser" : "parser: " + linked.join(", ")}');
		}
	}

	// (what follows css-reftests or css-render on the command line: theirs, Run.hx)
	public static var laneArgs:Array<String> = [];

	// (BLESS=1: reftest-manifest.json from the results; the WPT checkout made first when missing)
	static function reftests() {
		if (!sys.FileSystem.exists("bin/wpt/fonts/Ahem.ttf")) run(NODE, ["tests/css/import-wpt.mjs", "--checkout"]);
		exe("bin/css/CssReftestCheck", cps(["src", "tests/css"]).concat(["-main", "CssReftestCheck"]));
		run(exePath("bin/css/CssReftestCheck", HOST), laneArgs);
	}

	static function render() {
		exe("bin/css/CssRender", cps(["src", "tests/css"]).concat(["-main", "CssRender"]));
		run(exePath("bin/css/CssRender", HOST), laneArgs);
	}

	// (not headless: it fetches the sheets, tests/css/sheets.mjs)
	static function differential() {
		exe("bin/css/CssDump", cps(["src", "tests/css"]).concat(["-main", "CssDump"]));
		run(NODE, ["tests/css/differential.mjs", exePath("bin/css/CssDump", HOST)]);
	}
}
