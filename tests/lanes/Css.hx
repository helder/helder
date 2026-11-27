package lanes;

import lanes.Tools.*;

class Css {
	public static final LANES:Array<Lane> = [
		{name: "css-differential", about: "helder.css's tokens and values against @csstools' on real stylesheets (fetched)", run: differential},
		{name: "css-reftests", about: "helder.ui.box against WPT's CSS 2.1 reftests, drawn natively, and its noref tests against goldens Chromium draws (Playwright; reftest-manifest.json; args: directories or names to run alone)", run: reftests},
		{name: "css-geometry", about: "helder.ui.box's layout against Chromium's, box by box: the reftests' pages against snapshots geometry.mjs takes (Playwright), the likely cause of each difference (bin/css/geometry/report.md; args: directories or names to run alone), and a property of generated blocks", run: geometry},
		{name: "css-paged", about: "real documents on pages (tests/paged: an invoice, a report) against their goldens of our own output, drawn by PagedView (BLESS=1 takes them); a screen-only program without the paged host's fragmentation in its symbols", run: pagedLane},
		{name: "pdf-docs", about: "real-world documents (tests/pdf-docs) through helder pdf, each page rasterised by helder.pdf against its golden of our own output (BLESS=1 takes them); against WeasyPrint's PDFs where bin/pdf-docs has them (CI: similarity.md, diff/)", run: pdfDocs},
		{name: "css-app", about: "src/helder/css/ua/app.css against helder.ui today: example screens (todo, mail) mirrored as helder.dom trees, their computed values compared (a report: bin/css/app-ua.md)", run: app},
		{name: "box-conformance", about: "Taffy's flexbox and grid fixtures (Chrome's boxes) through helder's CSS engine, DocumentView (box-manifest.json; BLESS=1 takes it; args: fixture ids' parts)", run: boxConformance},
		{name: "css-render", about: "a page drawn by helder.ui.box: css-render <page> <out.png> [width height] [--tree]", run: render},
		{name: "css", about: "helder.css's property table, grammars, values, syntax and selectors (parsed, matched on helder.dom) against WPT's fixtures and css-parsing-tests", run: css}
	];

	// (the app user agent sheet's draft against helder.ui's defaults: a report, not a gate)
	static function app() {
		exe("bin/css/AppUaCheck", uiCp().concat(cps(["tests/css"])).concat(["-main", "AppUaCheck"]));
		run(exePath("bin/css/AppUaCheck", HOST), []);
	}

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
		// (BLESS=1: interpolation-manifest.json's pending cases)
		exe("bin/css/CssInterpolationCheck", cps(["src", "tests/css"]).concat(["-main", "CssInterpolationCheck"]));
		run(exePath("bin/css/CssInterpolationCheck", HOST), []);
		// (BLESS=1: gcpm-manifest.json's pending cases)
		exe("bin/css/CssGcpmCheck", cps(["src", "tests/css"]).concat(["-main", "CssGcpmCheck"]));
		run(exePath("bin/css/CssGcpmCheck", HOST), []);
		themes();
		modules();
	}

	// (a program styled by sheets compiled at build time alone, CssTheme:
	// its values, and its symbols without a CSS tokenizer or parser; the
	// same parsing a sheet when it runs has them, so the check checks)
	static function themes() {
		// (a width under border-style: none computes as given, Borders 4; the used width is 0)
		var expected = "block 14px 28px 3px 1px rgb(0, 128, 0) rgb(0, 0, 200) 12px 6px";
		probe("ThemeProbe", expected, []);
		probe("ThemeProbe", expected, ["-D", "css.parse"]);
		// (the user agent's sheet compiled too: a document styled by it alone links no parser)
		var ua = "32px 700 16px block inline list-item underline linktext 1";
		probe("UaProbe", ua, []);
		probe("UaProbe", ua, ["-D", "css.parse"]);
		// (the engine as an app has it, DocumentApp: a tree built in code, compiled sheets: no CSS, HTML or XML parser, nor grid or table layout, nor counters)
		var engine = "laid out 28px rgb(59, 130, 246) flex row scroll";
		probe("EngineProbe", engine, [], true);
		probe("EngineProbe", engine, ["-D", "css.parse"], true);
	}

	// (CSS modules: a program styled through one, its values and no parser
	// in its symbols; a misspelt name and a module's error fail the build,
	// the latter at the CSS file's line; the TypeScript declarations
	// CssScope makes type a program exactly, tsc's)
	static function modules() {
		probe("ModuleProbe", "4px rgb(0, 0, 200) 0px 2px 20px 700", []);
		for (f in [
			{main: "Misspelt", says: "has no field cardd"},
			{main: "Broken", says: "broken.module.css:2: characters 20-27"}
		]) {
			var out = 'bin/css/${f.main}';
			var r = build(cps(["src", "tests/css/modules"]).concat(["-main", f.main, "--custom-target", 'hxmc=$out']).concat(os([])), '$out.log');
			if (r.code == 0) throw new Failed('${f.main}: built, expected to fail');
			if (r.log.indexOf(f.says) < 0) throw new Failed('${f.main}: failed without "${f.says}":\n${r.log}');
			Sys.println('${f.main}: fails as it should (${f.says})');
		}
		exe("bin/css/ModuleProbe-ts", cps(["src", "tests/css"]).concat(["-main", "ModuleProbe", "-D", "css.typescript"]));
		var dir = "bin/css/modules-ts";
		mkdirs(dir);
		run(exePath("bin/css/ModuleProbe-ts", HOST), ["--typescript", dir]);
		for (f in ["good", "bad"])
			sys.io.File.copy('tests/css/modules/ts/$f.ts', '$dir/$f.ts');
		var good = tsc('$dir/good.ts'), bad = tsc('$dir/bad.ts');
		if (good.code != 0) throw new Failed('tsc: $dir/good.ts does not check:\n${good.out}');
		if (bad.code == 0) throw new Failed('tsc: $dir/bad.ts checks: a misspelt name and a write went through');
		for (e in ["Property 'cardd' does not exist", "Cannot assign to 'card' because it is a read-only property"])
			if (bad.out.indexOf(e) < 0) throw new Failed('tsc: bad.ts without "$e":\n${bad.out}');
		Sys.println("tsc: good.ts checks; bad.ts fails (a misspelt name, a write)");
	}

	// (tsc on a file, strict: its exit code and what it printed)
	static function tsc(file:String):{code:Int, out:String} {
		var args = ["--noEmit", "--strict", "--allowArbitraryExtensions", "--module", "esnext", "--moduleResolution", "bundler", "--target", "es2022", "--types", "", file];
		var p = new sys.io.Process("node_modules/.bin/tsc", args);
		var out = drain(p);
		var code = p.exitCode();
		p.close();
		return {code: code, out: out.out + out.err};
	}

	// (a probe built with -dce full and symbols: what it prints, and a CSS
	// parser in its symbols only when it parses, -D css.parse; not on Windows)
	// (app: an app's probe, its tree built in code and laid out: helder.dom's
	// HTML and XML parsers counted too, the formatting contexts its sheets
	// can't make, grid and table, and the counters they don't need: DocumentApp)
	static function probe(main:String, expected:String, defines:Array<String>, app = false) {
		if (Sys.systemName() == "Windows") return;
		var parser = ["helder_css_Tokenizer", "helder_css_Parser", "helder_css__Parser_", "helder_css_SelectorParser", "helder_css__CssSheet_Builder"];
		if (app) parser = parser.concat(["helder_dom_Tokenizer", "helder_dom_TreeBuilder", "helder_dom_XmlParser", "helder_ui_flow_GridFlow", "helder_ui_flow_TableFlow", "helder_css_CssCounters", "helder_css_CssCounterStyles"]);
		var parses = defines.contains("css.parse");
		var out = 'bin/css/$main-${parses ? "parse" : "sym"}';
		exe(out, cps(["src", "tests/css"]).concat(["-main", main, "-dce", "full", "-D", "hxmc.symbols"]).concat(defines));
		var got = StringTools.trim(output(exePath(out, HOST), [])).split("\n").join(" ");
		if (got != expected) throw new Failed('$out: "$got", expected "$expected"');
		var symbols = output("nm", [exePath(out, HOST)]).split("\n");
		var linked = [for (p in parser) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
		if (!parses && linked.length > 0) throw new Failed('$out links a parser: ${linked.join(", ")}');
		if (parses && linked.length < 3) throw new Failed('$out: no parser in its symbols (${linked.join(", ")}): the check checks nothing');
		Sys.println('$out: ${Math.round(sys.FileSystem.stat(exePath(out, HOST)).size / 1024)} KB with symbols, ${linked.length == 0 ? "no parser" : "parser: " + linked.join(", ")}');
	}

	// (what follows css-reftests or css-render on the command line: theirs, Run.hx)
	public static var laneArgs:Array<String> = [];

	// (BLESS=1: reftest-manifest.json from the results; the WPT checkout made first when missing)
	static function reftests() {
		// (the checkout, and DejaVu for the generic families: WptPage)
		if (!sys.FileSystem.exists("bin/wpt/fonts/Ahem.ttf") || !sys.FileSystem.exists("bin/fonts/dejavu-2.37/DejaVuSansMono.ttf"))
			run(NODE, ["tests/css/import-wpt.mjs", "--checkout"]);
		exe("bin/css/CssReftestCheck", cps(["src", "tests/css"]).concat(["-main", "CssReftestCheck"]));
		if (laneArgs[0] == "--fonts") return run(exePath("bin/css/CssReftestCheck", HOST), laneArgs);
		// (noref tests against Chromium's goldens: drawn where missing, kept in bin/css/goldens, the directory in its `current`)
		run(NODE, ["tests/css/goldens.mjs"].concat(laneArgs));
		run(exePath("bin/css/CssReftestCheck", HOST), laneArgs, ["GOLDENS" => StringTools.trim(sys.io.File.getContent("bin/css/goldens/current"))]);
		// (the whole gate: the real documents on pages too, and Taffy's flex and grid fixtures through the engine)
		if (laneArgs.length == 0) {
			paged();
			boxConformance();
		}
	}

	// (Chromium's snapshots taken where missing, kept in bin/css/geometry, the directory in its `current`)
	static function geometry() {
		if (!sys.FileSystem.exists("bin/wpt/fonts/Ahem.ttf") || !sys.FileSystem.exists("bin/fonts/dejavu-2.37/DejaVuSansMono.ttf"))
			run(NODE, ["tests/css/import-wpt.mjs", "--checkout"]);
		exe("bin/css/CssGeometryCheck", cps(["src", "tests/css"]).concat(["-main", "CssGeometryCheck"]));
		run(NODE, ["tests/css/geometry.mjs"].concat(laneArgs));
		run(exePath("bin/css/CssGeometryCheck", HOST), laneArgs, ["GEOMETRY" => StringTools.trim(sys.io.File.getContent("bin/css/geometry/current"))]);
		if (laneArgs.length == 0) {
			exe("bin/css/GeometryProperty", cps(["src", "tests/css"]).concat(["-main", "GeometryProperty"]));
			run(exePath("bin/css/GeometryProperty", HOST), []);
		}
	}

	static function pagedLane() {
		paged();
		screenOnly();
	}

	// (a program drawing on a screen alone links no fragmentation: Breaks,
	// BreakToken, PagedView are objects only a paged host creates; one on
	// pages links them, so the check checks)
	static function screenOnly() {
		if (Sys.systemName() == "Windows") return;
		var paged = ["helder_ui_flow_Breaks", "helder_ui_flow_BreakToken", "helder_ui_box_PagedView", "helder_ui_box_PageMargins"];
		for (main in ["ScreenProbe", "PagedProbe"]) {
			var out = 'bin/paged/$main';
			exe(out, cps(["src", "tests/paged"]).concat(["-main", main, "-dce", "full", "-D", "hxmc.symbols"]));
			var got = StringTools.trim(output(exePath(out, HOST), []));
			if (got != "drawn") throw new Failed('$out: "$got", expected "drawn"');
			var symbols = output("nm", [exePath(out, HOST)]).split("\n");
			var linked = [for (p in paged) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
			if (main == "ScreenProbe" && linked.length > 0) throw new Failed('$out links the paged host: ${linked.join(", ")}');
			if (main == "PagedProbe" && linked.length < paged.length) throw new Failed('$out: not all of the paged host in its symbols (${linked.join(", ")}): the check checks nothing');
			Sys.println('$out: ${Math.round(sys.FileSystem.stat(exePath(out, HOST)).size / 1024)} KB with symbols, ${linked.length == 0 ? "no fragmentation" : linked.join(", ")}');
		}
	}

	static function paged() {
		if (!sys.FileSystem.exists("bin/fonts/dejavu-2.37/DejaVuSansMono.ttf")) run(NODE, ["tests/css/import-wpt.mjs", "--checkout"]);
		exe("bin/paged/PagedCheck", cps(["src", "tests/css", "tests/paged"]).concat(["-main", "PagedCheck"]));
		run(exePath("bin/paged/PagedCheck", HOST), []);
	}

	static function pdfDocs() {
		if (!sys.FileSystem.exists("bin/fonts/dejavu-2.37/DejaVuSansMono.ttf")) run(NODE, ["tests/css/import-wpt.mjs", "--checkout"]);
		var cli = helderCli();
		mkdirs("bin/pdf-docs");
		var names = [for (f in sys.FileSystem.readDirectory("tests/pdf-docs")) if (StringTools.endsWith(f, ".html")) f];
		names.sort(Reflect.compare);
		for (f in names) run(cli, ["pdf", 'tests/pdf-docs/$f', "-o", 'bin/pdf-docs/${f.substr(0, f.length - 5)}.pdf']);
		exe("bin/pdf-docs/DocsCheck", cps(["src", "tests/pdf-docs"]).concat(["-main", "DocsCheck"]));
		run(exePath("bin/pdf-docs/DocsCheck", HOST), []);
	}

	static function boxConformance() {
		exe("bin/css/BoxConformanceCheck", cps(["src", "tests/layout-conformance"]).concat(["-main", "BoxConformanceCheck"]));
		run(exePath("bin/css/BoxConformanceCheck", HOST), laneArgs);
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
