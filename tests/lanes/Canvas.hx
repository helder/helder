package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Canvas {
	public static final LANES:Array<Lane> = [
		{name: "canvas", about: "helder.canvas against Chromium's scenes and WPT", run: canvasLane},
		{name: "canvas-gpu", about: "helder.canvas's GPU back end against the CPU's", run: canvasGpu},
		{name: "canvas-web", about: "helder.canvas's web back end in headless Chromium", run: canvasWeb},
		{name: "canvas-doc", about: "helder.canvas's PDF and SVG documents", run: canvasDoc}
	];

	static function canvasDoc() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		mkdirs("bin/canvas/ours");
		mkdirs("bin/canvas/doc");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(targetArgs(HOST)));
		run(exePath("bin/canvas/render", HOST), []);
		run(compiler, ["tests/canvas/render-doc.ts", "-o", exePath("bin/canvas/render-doc", HOST)].concat(targetArgs(HOST)));
		File.saveContent("bin/canvas/doc.txt", output(exePath("bin/canvas/render-doc", HOST), []));
		run(NODE, ["tests/canvas/doc.mjs", "bin/canvas/doc.txt"]);
		// (raster fallbacks drawn at twice the size, then scaled by the viewer: images and patterns softer)
		var own = "composite=skip,caps=skip,images=0.1,patterns=0.15,shadows=skip,filters=skip";
		if (FileSystem.exists("bin/canvas/pdf/fill-nonzero.png")) run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/pdf", "bin/canvas/ours", "bin/canvas/pdf-report", "white", own]);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/svg", "bin/canvas/ours", "bin/canvas/svg-report", "-", own]);
	}

	static function canvasWeb() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		run(compiler, ["tests/canvas/render-web.ts", "-o", "bin/canvas/render-web.wasm"].concat(targetArgs("wasm32-wasi")));
		run(NODE, ["tests/canvas/web.mjs", "bin/canvas/render-web.wasm"]);
		// (the references are Chromium 153's; CI's Playwright has 141, whose zero-length subpaths' caps differ: caps looser)
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/web", "tests/canvas/ref", "bin/canvas/web-report", "-", "caps=0.03"]);
		// (the browser's decoding: BrowserImages against helder's decoders)
		wasm("bin/canvas/WebDecode.wasm", cps(["src", "tests/canvas"]).concat(["-main", "WebDecode"]));
		run(NODE, ["tests/canvas/webdecode.mjs", "bin/canvas/WebDecode.wasm"]);
	}

	static function canvasGpu() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var args = targetArgs(GFX_TARGET);
		mkdirs("bin/canvas/ours");
		mkdirs("bin/canvas/gpu");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(targetArgs(HOST)));
		run(exePath("bin/canvas/render", HOST), []);
		run(compiler, ["tests/canvas/render-gpu.ts", "-o", exePath("bin/canvas/render-gpu", GFX_TARGET)].concat(args));
		Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
		run(exePath("bin/canvas/render-gpu", GFX_TARGET), []);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/gpu", "bin/canvas/ours", "bin/canvas/gpu-report"]);
		// (in a window: examples/canvas-window's 30th frame, the canvas read back: something drawn)
		native("bin/canvas/canvas-window", cps(["src", "examples/canvas-window"]).concat(["-main", "CanvasWindow"]), GFX_TARGET);
		var cmd = exePath("bin/canvas/canvas-window", GFX_TARGET) + " --shot bin/canvas/window.png";
		if (Sys.systemName() == "Linux") shell('$XVFB -a $cmd') else shell(cmd);
		run(NODE, ["tests/canvas/window.mjs", "bin/canvas/window.png"]);

	}

	static function canvasLane() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var args = targetArgs(HOST);
		mkdirs("bin/canvas/ours");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(args));
		run(exePath("bin/canvas/render", HOST), []);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/ours", "tests/canvas/ref", "bin/canvas/report"]);
		run(compiler, ["tests/canvas/wpt.ts", "-o", exePath("bin/canvas/wpt", HOST)].concat(args));
		File.saveContent("bin/canvas/wpt.txt", output(exePath("bin/canvas/wpt", HOST), []));
		run(NODE, ["tests/canvas/wpt/check.mjs", "bin/canvas/wpt.txt"]);
		if (Sys.systemName() == "Linux") {
			var cp = cps(["src", "tests/canvas"]).concat(targetArgs(HOST));
			for (m in ["Tiny", "Full"]) {
				exe('bin/canvas/$m', cp.concat(["-main", m, "-dce", "full"]));
				exe('bin/canvas/$m-sym', cp.concat(["-main", m, "-dce", "full", "-D", "hxmc.symbols"]));
				run(exePath('bin/canvas/$m', HOST), []);
			}
			run(NODE, ["tests/canvas/dce.mjs", "bin/canvas/Tiny", "bin/canvas/Tiny-sym", "bin/canvas/Full", "bin/canvas/Full-sym"]);
		}
	}
}
