package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class View {
	public static final LANES:Array<Lane> = [
		{name: "view", about: "helder.view on Eval, natively and as JavaScript", run: view},
		{name: "ui", about: "helder.ui on Eval: layout, events, focus, markup", run: ui},
		{name: "layout-conformance", about: "flexbox and grid against Taffy's fixtures", run: layoutConformance},
		{name: "web", about: "helder.web's static and DOM renderers", run: web},
		{name: "ui-soft", about: "helder.ui drawn on the CPU, writing the goldens", run: uiSoft},
		{name: "ui-draw", about: "helder.ui's GPU renderer against golden images", run: uiDraw},
		{name: "thread-web", about: "not in CI: the page's thread against a worker", run: threadWeb},
		{name: "ui-web", about: "helder.ui as wasm32-wasi in headless Chromium", run: uiWeb}
	];

	static function view() {
		var cp = cps(["src", "tests/view"]);
		interp(cp, "ViewTest", [TOOL]);
		exe("bin/view/ViewTest", cp.concat(["-main", "ViewTest"]));
		run(exePath("bin/view/ViewTest", HOST), []);
		js("bin/view/ViewTest.js", cp.concat(["-main", "ViewTest"]));
		run(NODE, ["bin/view/ViewTest.js"]);
	}

	static function ui() {
		var cp = cps(["src", "tests/ui"]);
		interp(cp, "UiTest");
		interp(cp, "MarkupTest");
		interp(cp.concat(cps([guideTestSource()])), "GuideTest");
	}

	static function guideTestSource():String {
		var dir = "bin/ui/guide";
		var sample = "docs/apps/interactions.md";
		var source = File.getContent("tests/ui/GuideTest.hx").replace("\r\n", "\n");
		var blocks = File.getContent(sample).replace("\r\n", "\n").split("\n```haxe\n").slice(1).map(b -> b.split("\n```")[0]);
		for (name in ["Confirm", "Editor"]) {
			var declaration = 'static function $name(';
			var code = Lambda.find(blocks, b -> b.startsWith(declaration));
			if (code == null) throw new Failed('$sample: missing Haxe sample for $name');
			var start = source.indexOf('\t' + declaration);
			var end = source.indexOf("\n\n", start);
			if (start < 0 || end < 0) throw new Failed('GuideTest: missing $name');
			source = source.substr(0, start) + code + source.substr(end);
		}
		mkdirs(dir);
		File.saveContent('$dir/GuideTest.hx', source);
		return dir;
	}

	static function layoutConformance()
		interp(cps(["src", "tests/ui", "tests/layout-conformance"]), "LayoutConformance");

	static function web() {
		var cp = cps(["src", "tests/web", "examples/web-demo"]);
		interp(cp, "StaticTest");
		exe("bin/web/StaticTest", cp.concat(["-main", "StaticTest"]));
		run(exePath("bin/web/StaticTest", HOST), []);
		rmrf("bin/web/demo");
		interp(cp, "DemoPage", ["bin/web/demo"]);
		js("bin/web/domtest.js", cp.concat(["-main", "DomTest", "-debug"]));
		js("bin/web/demo/islands.js", cp.concat(["-main", "DemoBundle", "-dce", "full", "-debug"]));
		js("bin/web/demo/counter.js", cp.concat(["-main", "Counter", "-dce", "full", "-D", "js-es=6", "-D", "analyzer-optimize"]));
		wasm("bin/web/demo/locale.wasm", cps(["src", "tests/os"]).concat(["-main", "LocaleCheck", "-D", "helder.asset.out=bin/web/demo/locale.wasm"]));
		wasm("bin/web/demo/lab.wasm", cps(["src", "examples/web-demo"]).concat(["-main", "Lab"]));
		wasm("bin/web/demo/cube.wasm", gfxCp().concat(["-main", "Cube"]));
		// (ui's counter, its root a <Surface>: the page's <Surface>)
		wasm("bin/web/demo/counter-ui.wasm", cps(["src", "examples/counter"]).concat(["-main", "Counter"]));
		for (f in FileSystem.readDirectory("bin/web/demo"))
			if (f.endsWith(".log")) FileSystem.deleteFile('bin/web/demo/$f');
		run(NODE, ["tests/web/web.mjs", "bin/web"]);
	}

	static function uiPrograms() {
		var t = GFX_TARGET;
		var programs = ["UiDrawTest", "TodoTest", "StressTest", "LayerTest", "DamageTest", "ClipboardTest", "EmojiTest", "BoxTest", "SnapTest", "WindowTest", "ControlsGallery", "ControlsBench", "RenderThreadTest", "AsyncScrollTest", "AsyncScrollWindow", "GlassTest"];
		if (t.startsWith("macos-")) programs = programs.concat(["SystemLayersWindow", "GlassWindow"]);
		if (t.startsWith("linux-")) programs = programs.concat(["TextInputTest", "LinuxAccessTest", "AtspiProbe", "AccessApp"]);
		if (t.startsWith("windows-")) programs.push("WinAccessTest");
		for (m in programs)
			native('bin/ui/$t/$m', uiCp().concat(["-main", m]), t);
	}

	// (the image tests drawn on the CPU: their goldens; on Linux static, so nothing of a GPU's can be loaded)
	static function uiSoft() {
		var b = 'bin/ui-soft/$HOST', bless = BLESS ? " --bless" : "";
		var programs = ["UiDrawTest", "TodoTest", "BoxTest", "EmojiTest", "ControlsGallery", "SnapTest", "GlassTest"];
		// (-D helder.headless: no window code, static on Linux)
		var soft = ["-D", "helder.soft", "-D", "helder.headless", "-D", 'hxmc.target=$HOST'];
		prebuild([for (m in programs) {out: exePath('$b/$m', HOST), args: uiCp().concat(["-main", m]).concat(soft)}]);
		for (m in programs)
			hxmc(exePath('$b/$m', HOST), uiCp().concat(["-main", m]).concat(soft));
		shell('$b/UiDrawTest tests/ui/draw.png $b/draw.png$bless');
		shell('$b/TodoTest tests/ui/todo.png $b/todo.png$bless');
		shell('$b/BoxTest tests/ui/boxes.png $b/boxes.png');
		shell('$b/EmojiTest tests/ui/emoji.png $b/emoji.png');
		shell('$b/SnapTest');
		shell('$b/GlassTest tests/ui/glass.png $b/glass.png$bless');
		mkdirs('$b/controls');
		shell('$b/ControlsGallery tests/ui/controls $b/controls$bless');
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
		shell('$gpu $b/UiDrawTest tests/ui/draw.png $b/draw.png$bless');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/UiDrawTest tests/ui/draw.png $b/window.png --window');
		shell('$gpu $b/TodoTest tests/ui/todo.png $b/todo.png$bless');
		shell('$gpu $b/StressTest');
		shell('$gpu $b/LayerTest');
		shell('$gpu $b/DamageTest');
		shell('$gpu $b/EmojiTest tests/ui/emoji.png $b/emoji.png');
		shell('$gpu $b/BoxTest tests/ui/boxes.png $b/boxes.png');
		shell('$gpu $b/SnapTest');
		// (Liquid Glass drawn: its backdrop, blur and lens against the CPU's)
		shell('$gpu $b/GlassTest tests/ui/glass.png $b/glass.png');
		// (the controls: their gallery against tests/ui/controls' images, their cost)
		mkdirs('$b/controls');
		shell('$gpu $b/ControlsGallery tests/ui/controls $b/controls$bless');
		shell('$gpu $b/ControlsBench');
		shell('$xvfb $b/WindowTest');
		// (damage in a window whose frame is multisampled, the frame kept single-sampled: the same pixels)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/DamageTest --window');
		// (the render thread's frames against the synchronous path's, in a window; resources hammered while frames are on their way)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/RenderThreadTest');
		// (the compositor's scrolling: its physics and frames against the program's, then in a window the program blocked while scroll input comes)
		shell('$gpu $b/AsyncScrollTest');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/AsyncScrollWindow');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/AsyncScrollWindow --anim');
		if (!linux) shell('$b/AsyncScrollWindow --native');
		// (Core Animation's layers: the same scene composited by it and by the textured compositor, window captures compared)
		if (GFX_TARGET.startsWith("macos-") && !linux) shell('$b/SystemLayersWindow');
		// (the system's Liquid Glass, macOS 26: its views in the layer tree, kept in the background)
		if (GFX_TARGET.startsWith("macos-") && !linux) shell('HELDER_BACKGROUND=1 $b/GlassWindow');
		// (the clipboard: Xvfb's own, not a desktop's in use; X11's text input
		// and AT-SPI: Linux's; Windows' are the window lane's)
		if (!linux) return;
		shell('$xvfb $b/ClipboardTest');
		shell('$xvfb $b/TextInputTest');
		// (AT-SPI: the window's tree read by another process through libatspi,
		// in a D-Bus session: the fixture's, acted on, then the examples' and
		// the guide's, read whole)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/LinuxAccessTest & p=$$!; $b/AtspiProbe fixture; s=$$?; wait $$p && exit $$s\'');
		for (screen in ACCESS_SCREENS)
			shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/AccessApp ${screen[0]} & p=$$!; $b/AtspiProbe ${screen.join(" ")}; s=$$?; kill $$p; exit $$s\'');
	}

	static function threadWeb() {
		wasm("bin/ui/ThreadBench.wasm", uiCp().concat(["-main", "ThreadBench"]));
		run(NODE, ["tests/ui/thread-bench.mjs", "bin/ui/ThreadBench.wasm", "--json", "bin/ui/thread-bench.json"]);
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
