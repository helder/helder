package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class View {
	public static final LANES:Array<Lane> = [
		{name: "view", about: "helder.view on Eval, natively and as JavaScript", run: view},
		{name: "view-stores", about: "helder.view's graph tests through stores (atoms)", run: viewStores},
		{name: "ui", about: "helder.ui on Eval: layout, events, focus, markup", run: ui},
		{name: "fast-probe", about: "fast nodes as an app has them (tests/ui/FastProbe.hx, -dce full with symbols): laid out, no helder.dom, cascade, matcher or CSS parser in its symbols; with a DocumentNode beside it (-D fast.island) they are: the check's control; the todo and the mail client on fast nodes (examples/todo-fast, mail-fast) the same, and driven headless (TodoFastCheck, MailFastCheck: focus, Tab, keys, typing, selection, the keymap, dark mode, their accessibility trees against helder.ui's)", run: fastProbe},
		{name: "layout-conformance", about: "flexbox and grid against Taffy's fixtures", run: layoutConformance},
		{name: "web", about: "helder.web's static and DOM renderers", run: web},
		{name: "ui-soft", about: "helder.ui drawn on the CPU, writing the goldens", run: uiSoft},
		{name: "ui-draw", about: "helder.ui's GPU renderer against golden images", run: uiDraw},
		{name: "ui-web", about: "helder.ui as wasm32-wasi in headless Chromium", run: uiWeb},
		{name: "document-window", about: "long documents in a real window (DocumentNode: the HTML Standard, the ECMAScript spec, Wikipedia's longest page and Japanese pitch accent, War and Peace, WebKit's chapter-reflow): the wheel, jumps, anchors, the thumb and text dragged, each step's frame in a budget, the live heap flat (fetched into bin/bench/html)", run: documentWindow}
	];

	static function view() {
		var cp = cps(["src", "tests/view"]);
		interp(cp, "ViewCheck", [TOOL]);
		exe("bin/view/ViewCheck", cp.concat(["-main", "ViewCheck"]));
		run(exePath("bin/view/ViewCheck", HOST), []);
		js("bin/view/ViewCheck.js", cp.concat(["-main", "ViewCheck"]));
		run(NODE, ["bin/view/ViewCheck.js"]);
	}

	// (tests/view/graph run in a store each test (home), and through a store's
	// nodes of the default's (foreign): tests/view/graph/Stores.hx)
	static function viewStores() {
		for (mode in ["home", "foreign"])
			run(helderCli(), ["test", "tests/view/graph"], ["HELDER_GRAPH_STORES" => mode]);
		// (reactive-framework-test-suite's cases, plain and through stores: tests/view/conformance)
		js("bin/conformance/framework.js", cps(["src", "tests/view/conformance"]).concat(["-main", "Framework"]));
		run(NODE, ["tests/view/conformance/conformance.mjs", "bin/conformance/framework.js"]);
	}

	static function ui() {
		var cp = cps(["src", "tests/ui"]);
		interp(cp, "UiCheck");
		interp(cp, "MarkupCheck");
		interp(cp.concat(cps([guideTestSource()])), "GuideCheck");
	}

	// (what a fast app must not link, and what it must: its layout and paint)
	static final FAST_NONE = ["helder_dom_", "helder_css_CssStyles", "helder_css_CssResolver", "helder_css_CssMatcher", "helder_css_CssRuleIndex", "helder_css_CssBloom",
		"helder_css_Tokenizer", "helder_css_Parser", "helder_css_SelectorParser", "helder_css_CssData", "helder_css_CssShorthands", "helder_css_CssComputed",
		"helder_ui_flow_GridFlow", "helder_ui_flow_TableFlow"];
	static final FAST_MUST = ["helder_ui_flow_BlockFlow", "helder_ui_flow_FlexFlow", "helder_ui_flow_InlineLayout", "helder_ui_box_BoxPainter", "helder_ui_fast_Tree"];

	static function fastProbe() {
		if (Sys.systemName() == "Windows") return;
		for (island in [false, true]) {
			var out = 'bin/ui/FastProbe${island ? "-island" : ""}';
			exe(out, cps(["src", "tests/ui"]).concat(["-main", "FastProbe", "-dce", "full", "-D", "helder.release", "-D", "hxmc.symbols"])
				.concat(island ? ["-D", "fast.island"] : []).concat(targetArgs(HOST)));
			var got = StringTools.trim(output(exePath(out, HOST), ["layout"]));
			var expected = "laid out 480x";
			if (!got.startsWith(expected) || got.indexOf("3 rows 3 items left") < 0) throw new Failed('$out: "$got", expected "$expected... 3 rows 3 items left"');
			var symbols = output("nm", [exePath(out, HOST)]).split("\n");
			function linked(names:Array<String>)
				return [for (p in names) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
			var none = linked(FAST_NONE), must = linked(FAST_MUST);
			if (must.length < FAST_MUST.length) throw new Failed('$out: without ${[for (m in FAST_MUST) if (!must.contains(m)) m].join(", ")}');
			if (!island && none.length > 0) throw new Failed('$out links ${none.join(", ")}');
			if (island && none.length < 8) throw new Failed('$out: the island links only ${none.join(", ")}: the check checks nothing');
			Sys.println('$out: $got; ${Math.round(FileSystem.stat(exePath(out, HOST)).size / 1024)} KB with symbols; ${none.length == 0 ? "no DOM or cascade" : "links " + none.join(", ")}');
		}
		// (a style's literal and a CSS module checked when the program is built: a misspelt name, a selector no
		// fast style has, an error of the build at its place)
		for (f in [
			{main: "MisspeltField", says: "a style has no field paddin; did you mean padding?"},
			{main: "MisspeltClass", says: "has no field cardd"},
			{main: "Descendant", says: "descendant.module.css:2: characters 7-8"}
		]) {
			var out = 'bin/ui/fast-errors/${f.main}';
			var r = build(cps(["src", "tests/ui/fast/errors"]).concat(["-main", f.main, "--custom-target", 'hxmc=$out']).concat(os([])), '$out.log');
			if (r.code == 0) throw new Failed('${f.main}: built, expected to fail');
			if (r.log.indexOf(f.says) < 0) throw new Failed('${f.main}: failed without "${f.says}":\n${r.log}');
			Sys.println('${f.main}: fails as it should (${f.says})');
		}
		// (the todo and the mail client on fast nodes, through their markup: as an app builds them, the same check;
		// driven headless, TodoFastCheck and MailFastCheck)
		for (app in [{main: "TodoFast", dir: "todo"}, {main: "MailFast", dir: "mail"}]) {
			var out = 'bin/ui/${app.main}';
			exe(out, cps(["src", 'examples/${app.dir}-fast']).concat(["-main", app.main, "-dce", "full", "-D", "helder.release", "-D", "hxmc.symbols"])
				.concat(targetArgs(HOST)));
			var symbols = output("nm", [exePath(out, HOST)]).split("\n");
			var none = [for (p in FAST_NONE) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
			var must = [for (p in FAST_MUST) if (Lambda.exists(symbols, s -> s.indexOf(p) >= 0)) p];
			if (none.length > 0) throw new Failed('$out links ${none.join(", ")}');
			if (must.length < FAST_MUST.length) throw new Failed('$out: without ${[for (m in FAST_MUST) if (!must.contains(m)) m].join(", ")}');
			Sys.println('$out: ${Math.round(FileSystem.stat(exePath(out, HOST)).size / 1024)} KB with symbols; no DOM or cascade');
			var check = 'bin/ui/${app.main}Check';
			exe(check, cps(["src", "tests/ui", "tests/gfx", 'examples/${app.dir}-fast', 'examples/${app.dir}']).concat(["-main", '${app.main}Check'])
				.concat(targetArgs(HOST)));
			run(exePath(check, HOST), []);
		}
	}

	static function guideTestSource():String {
		var dir = "bin/ui/guide";
		var sample = "docs/apps/interactions.md";
		var source = File.getContent("tests/ui/GuideCheck.hx").replace("\r\n", "\n");
		var blocks = File.getContent(sample).replace("\r\n", "\n").split("\n```haxe\n").slice(1).map(b -> b.split("\n```")[0]);
		for (name in ["Confirm", "Editor"]) {
			var declaration = 'static function $name(';
			var code = Lambda.find(blocks, b -> b.startsWith(declaration));
			if (code == null) throw new Failed('$sample: missing Haxe sample for $name');
			var start = source.indexOf('\t' + declaration);
			var end = source.indexOf("\n\n", start);
			if (start < 0 || end < 0) throw new Failed('GuideCheck: missing $name');
			source = source.substr(0, start) + code + source.substr(end);
		}
		mkdirs(dir);
		File.saveContent('$dir/GuideCheck.hx', source);
		return dir;
	}

	static function layoutConformance()
		interp(cps(["src", "tests/ui", "tests/layout-conformance"]), "LayoutConformanceCheck");

	static function web() {
		var cp = cps(["src", "tests/web", "examples/web-demo"]);
		interp(cp, "StaticCheck");
		exe("bin/web/StaticCheck", cp.concat(["-main", "StaticCheck"]));
		run(exePath("bin/web/StaticCheck", HOST), []);
		rmrf("bin/web/demo");
		interp(cp, "DemoPage", ["bin/web/demo"]);
		js("bin/web/domtest.js", cp.concat(["-main", "DomCheck", "-debug"]));
		js("bin/web/demo/islands.js", cp.concat(["-main", "DemoBundle", "-dce", "full", "-debug"]));
		js("bin/web/demo/counter.js", cp.concat(["-main", "Counter", "-dce", "full", "-D", "js-es=6", "-D", "analyzer-optimize"]));
		wasm("bin/web/demo/locale.wasm", cps(["src", "tests/os"]).concat(["-main", "LocaleCheck", "-D", "helder.asset.out=bin/web/demo/locale.wasm"]));
		wasm("bin/web/demo/lab.wasm", cps(["src", "examples/web-demo"]).concat(["-main", "Lab"]));
		wasm("bin/web/demo/cube.wasm", gfxCp().concat(["-main", "Cube"]));
		// (ui's counter, its root a <Surface>: the page's <Surface>)
		wasm("bin/web/demo/counter-ui.wasm", cps(["src", "examples/counter"]).concat(["-main", "Counter"]));
		for (f in FileSystem.readDirectory("bin/web/demo"))
			if (f.endsWith(".log")) FileSystem.deleteFile('bin/web/demo/$f');
		// (a plain UI program links no helder.async but Errors: tests/web/links.mjs; the code
		// editor's embeds its font, Embed.bytes)
		wasm("bin/ui/WebTodo.wasm", uiCp().concat(["-main", "WebTodo"]));
		wasm("bin/web/editor.wasm", cps(["src", "examples/code-editor"]).concat(["-main", "Editor"]));
		run(NODE, ["tests/web/links.mjs", "bin/web/domtest.js", "bin/web/demo/counter-ui.wasm", "bin/ui/WebTodo.wasm", "bin/web/editor.wasm"]);
		run(NODE, ["tests/web/web.mjs", "bin/web"]);
	}

	static function uiPrograms() {
		var t = GFX_TARGET;
		var programs = ["UiDrawCheck", "TodoCheck", "StressCheck", "LayerCheck", "DamageCheck", "ClipboardCheck", "EmojiCheck", "BoxCheck", "SnapCheck", "WindowCheck", "ControlsGallery", "ControlsCostCheck", "RenderThreadCheck", "AsyncScrollCheck", "AsyncScrollWindowCheck", "GlassCheck"];
		if (t.startsWith("macos-")) programs = programs.concat(["SystemLayersWindowCheck", "GlassWindowCheck"]);
		if (t.startsWith("linux-")) programs = programs.concat(["KeyInputCheck", "LinuxAccessCheck", "AtspiCheck", "AccessApp"]);
		if (t.startsWith("windows-")) programs.push("WinAccessCheck");
		for (m in programs)
			native('bin/ui/$t/$m', uiCp().concat(["-main", m]), t);
	}

	// (the image tests drawn on the CPU: their goldens; on Linux static, so nothing of a GPU's can be loaded)
	static function uiSoft() {
		var b = 'bin/ui-soft/$HOST', bless = BLESS ? " --bless" : "";
		// (the goldens' faces on every machine, none of the system's: DejaVu 2.37, as CI's fonts-dejavu-core; a Mac's
		// Helvetica and its own Inter drew them otherwise)
		run(NODE, ["tests/dejavu.mjs"]);
		Sys.putEnv("HELDER_FONT_DIRS", sys.FileSystem.fullPath("bin/fonts/dejavu-2.37"));
		var programs = ["UiDrawCheck", "TodoCheck", "BoxCheck", "EmojiCheck", "ControlsGallery", "SnapCheck", "GlassCheck"];
		// (-D helder.headless: no window code, static on Linux)
		var soft = ["-D", "helder.soft", "-D", "helder.headless", "-D", 'hxmc.target=$HOST'];
		prebuild([for (m in programs) {out: exePath('$b/$m', HOST), args: uiCp().concat(["-main", m]).concat(soft)}]);
		for (m in programs)
			hxmc(exePath('$b/$m', HOST), uiCp().concat(["-main", m]).concat(soft));
		shell('$b/UiDrawCheck tests/ui/draw.png $b/draw.png$bless');
		shell('$b/TodoCheck tests/ui/todo.png $b/todo.png$bless');
		shell('$b/BoxCheck tests/ui/boxes.png $b/boxes.png');
		shell('$b/EmojiCheck tests/ui/emoji.png $b/emoji.png');
		shell('$b/SnapCheck');
		shell('$b/GlassCheck tests/ui/glass.png $b/glass.png$bless');
		mkdirs('$b/controls');
		shell('$b/ControlsGallery tests/ui/controls $b/controls$bless');
		Sys.putEnv("HELDER_FONT_DIRS", "");
	}

	static function uiDraw() {
		uiPrograms();
		var b = 'bin/ui/$GFX_TARGET';
		// (the goldens are the CPU's: ui-soft blesses them)
		var bless = "";
		var gpu = "LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY";
		// (Linux: a window in Xvfb; elsewhere the desktop's own)
		var linux = Sys.systemName() == "Linux";
		var xvfb = linux ? '$XVFB -a -s "-screen 0 640x480x24"' : "";
		// (the goldens' faces and raster elsewhere too: DejaVu 2.37 alone, drawn by helder's engine as FreeType draws
		// them on Linux; a Mac's Core Text drew lighter text on dark)
		if (!linux) {
			run(NODE, ["tests/dejavu.mjs"]);
			Sys.putEnv("HELDER_FONT_DIRS", sys.FileSystem.fullPath("bin/fonts/dejavu-2.37"));
			Sys.putEnv("HELDER_TEXT_ENGINE", "helder");
		}
		shell('$gpu $b/UiDrawCheck tests/ui/draw.png $b/draw.png$bless');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/UiDrawCheck tests/ui/draw.png $b/window.png --window');
		shell('$gpu $b/TodoCheck tests/ui/todo.png $b/todo.png$bless');
		shell('$gpu $b/StressCheck');
		shell('$gpu $b/LayerCheck');
		shell('$gpu $b/DamageCheck');
		shell('$gpu $b/EmojiCheck tests/ui/emoji.png $b/emoji.png');
		shell('$gpu $b/BoxCheck tests/ui/boxes.png $b/boxes.png');
		shell('$gpu $b/SnapCheck');
		// (Liquid Glass drawn: its backdrop, blur and lens against the CPU's)
		shell('$gpu $b/GlassCheck tests/ui/glass.png $b/glass.png');
		// (the controls: their gallery against tests/ui/controls' images, their cost)
		mkdirs('$b/controls');
		shell('$gpu $b/ControlsGallery tests/ui/controls $b/controls$bless');
		shell('$gpu $b/ControlsCostCheck');
		shell('$xvfb $b/WindowCheck');
		// (damage in a window whose frame is multisampled, the frame kept single-sampled: the same pixels)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/DamageCheck --window');
		// (the render thread's frames against the synchronous path's, in a window; resources hammered while frames are on their way)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/RenderThreadCheck');
		// (the compositor's scrolling: its physics and frames against the program's, then in a window the program blocked while scroll input comes)
		shell('$gpu $b/AsyncScrollCheck');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/AsyncScrollWindowCheck');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/AsyncScrollWindowCheck --anim');
		if (!linux) shell('$b/AsyncScrollWindowCheck --native');
		// (Core Animation's layers: the same scene composited by it and by the textured compositor, window captures compared)
		if (GFX_TARGET.startsWith("macos-") && !linux) shell('$b/SystemLayersWindowCheck');
		// (the system's Liquid Glass, macOS 26: its views in the layer tree, kept in the background)
		if (GFX_TARGET.startsWith("macos-") && !linux) shell('HELDER_BACKGROUND=1 $b/GlassWindowCheck');
		if (!linux) {
			Sys.putEnv("HELDER_FONT_DIRS", "");
			Sys.putEnv("HELDER_TEXT_ENGINE", "");
			return;
		}
		// (the clipboard: Xvfb's own, not a desktop's in use; X11's text input
		// and AT-SPI: Linux's; Windows' are the window lane's)
		shell('$xvfb $b/ClipboardCheck');
		shell('$xvfb $b/KeyInputCheck');
		// (AT-SPI: the window's tree read by another process through libatspi,
		// in a D-Bus session: the fixture's, acted on, then the examples' and
		// the guide's, read whole)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/LinuxAccessCheck & p=$$!; $b/AtspiCheck fixture; s=$$?; wait $$p && exit $$s\'');
		for (screen in ACCESS_SCREENS)
			shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/AccessApp ${screen[0]} & p=$$!; $b/AtspiCheck ${screen.join(" ")}; s=$$?; kill $$p; exit $$s\'');
	}

	// (a window in the background; HELDER_TEST_INPUT=1 adds --real: the drags posted to its own queue at a mouse's pace)
	static function documentWindow() {
		run(NODE, ["tests/bench/pages.mjs"]);
		var b = 'bin/ui/$GFX_TARGET/DocumentWindowCheck';
		native(b, cps(["src", "tests/ui"]).concat(["-main", "DocumentWindowCheck"]), GFX_TARGET);
		var linux = Sys.systemName() == "Linux";
		var pre = linux ? 'LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a -s "-screen 0 1280x1024x24" ' : "HELDER_BACKGROUND=1 ";
		var pages = ["html-spec", "telemann", "ecma262", "war-and-peace", "chapter-reflow", "pitch-accent"];
		for (p in pages)
			shell('$pre${exePath(b, GFX_TARGET)} bin/bench/html/$p.html bin/bench/html/$p-sheets.json');
		// (--front: shown over the other windows, not made key, as a window in use presents; HELDER_TEST_FRONT=1)
		if (Sys.getEnv("HELDER_TEST_INPUT") == "1") for (p in pages)
			shell('${pre}THUMB_HZ=250 THUMB_S=20 ${exePath(b, GFX_TARGET)} bin/bench/html/$p.html bin/bench/html/$p-sheets.json --real${Sys.getEnv("HELDER_TEST_FRONT") == "1" ? " --front" : ""}');
	}

	static function uiWeb() {
		var b = "bin/ui";
		wasm('$b/WebTodo.wasm', uiCp().concat(["-main", "WebTodo"]));
		run(NODE, ["tests/ui/web.mjs", '$b/WebTodo.wasm', b]);
		// (resized in steps with the page: each frame shown at the size it lays out)
		run(NODE, ["tests/ui/web-resize.mjs", '$b/WebTodo.wasm']);
		// (the pointer's shape: a hand over what is pressed, as web pages have it)
		wasm('$b/WebCursorPage.wasm', uiCp().concat(["-main", "WebCursorPage"]));
		run(NODE, ["tests/ui/web-cursor.mjs", '$b/WebCursorPage.wasm']);
		run(NODE, ["tests/ui/web-cursor.mjs", '$b/WebCursorPage.wasm', "worker"]);
		wasm('$b/WebField.wasm', uiCp().concat(["-main", "WebField"]));
		run(NODE, ["tests/ui/web-field.mjs", '$b/WebField.wasm']);
		run(NODE, ["tests/ui/web-field.mjs", '$b/WebField.wasm', "worker"]);
		// (the ARIA mirror of the fixture: Playwright's snapshot, Chromium's tree, a screen reader's clicks)
		wasm('$b/WebAccessPage.wasm', uiCp().concat(["-main", "WebAccessPage"]));
		run(NODE, ["tests/ui/web-access.mjs", '$b/WebAccessPage.wasm']);
		run(NODE, ["tests/ui/web-access.mjs", '$b/WebAccessPage.wasm', "worker"]);
		// (the browser's scroll views driving the scrollers: wheels, clicks, keys and swipes)
		wasm('$b/WebScrollPage.wasm', uiCp().concat(["-main", "WebScrollPage"]));
		run(NODE, ["tests/ui/web-scroll.mjs", '$b/WebScrollPage.wasm']);
		// (the viewer's web build, viewer.helder.run's: at its sample folder, the PDF, the Markdown sample, a drop, Open folder)
		run(helderCli(), ["build", "--target", "web", "apps/viewer"]);
		run(NODE, ["apps/viewer/tests/web.mjs", "apps/viewer/bin/web", '$b/viewer']);
		// (Liquid Glass drawn on WebGPU and WebGL2 against the CPU's golden)
		wasm('$b/WebGlass.wasm', uiCp().concat(["-main", "WebGlass"]));
		run(NODE, ["tests/ui/web-glass.mjs", '$b/WebGlass.wasm']);
		// (the browser as the compositor: the window's layers canvases of the page, against the flat window; scrolled while the program is busy)
		wasm('$b/WebLayersPage.wasm', uiCp().concat(["-main", "WebLayersPage"]));
		run(NODE, ["tests/ui/web-layers.mjs", '$b/WebLayersPage.wasm']);
		// (a video's frames on its system layer, a canvas of the page, between the window's and the layer over it)
		wasm('$b/WebVideoLayers.wasm', uiCp().concat(["-main", "WebVideoLayers"]));
		run(NODE, ["tests/ui/web-video-layers.mjs", '$b/WebVideoLayers.wasm']);
	}
}
