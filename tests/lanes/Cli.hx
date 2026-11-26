package lanes;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Cli {
	public static final LANES:Array<Lane> = [
		{name: "test", about: "every *.test.hx and *.test.ts, natively and as wasm32-wasi", run: helderTest},
		{name: "fuzz", about: "the robustness properties soaked (FUZZ_SECONDS each, FUZZ_SEED)", run: fuzz},
		{name: "cli", about: "helder build, run, dev and devices", run: cli},
		{name: "devtools", about: "the devtools protocol without a window", run: devtools},
		{name: "declarations", about: "the generated TypeScript declarations", run: declarations},
		{name: "typescript", about: "helder.typescript's programs against tsc and node", run: () -> run(NODE, ["tests/typescript/run.mjs"].concat(shardArgs()).concat(workerCount == null ? [] : ["--jobs", Std.string(workerCount)]))},
		{name: "typescript-native", about: "helder/native's definitions where their systems are", run: () -> run(NODE, ["tests/typescript/native.mjs"])},
		{name: "examples", about: "every example built, not run", run: examples},
		{name: "dev", about: "helder.dev.Hot and signals across a reload", run: dev},
		{name: "edit-loop", about: "the edit loop's times, from save to frame", run: editLoop},
		{name: "dev-host", about: "helder dev's host swapping shared libraries", run: devHost}
	];

	// (the properties with a limit, each run FUZZ_SECONDS (20) natively from
	// FUZZ_SEED (random: a failure says its seed); a case that hangs,
	// crashes or blows up is left in bin/fuzz/properties)
	static final FUZZ = ["tests/image/Fuzz.test.hx", "tests/pdf/Fuzz.test.hx", "tests/media/Fuzz.test.hx", "tests/text/Fuzz.test.hx",
		"src/helder/markdown/Markdown.test.hx", "src/helder/view/graph/AtomsModel.test.hx"];

	static function fuzz()
		// (its own bin/fuzz: beside the test lane under -j, the two wrote one bin/test/src)
		run(helderCli(), ["test"].concat(FUZZ).concat(["--target", "host", "--out", "bin/fuzz"]),
			["HELDER_PROPERTY_SOAK" => Sys.getEnv("FUZZ_SECONDS") ?? "20", "HELDER_PROPERTY_SEED" => Sys.getEnv("FUZZ_SEED") ?? "random"]);

	static function helderTest() {
		run(helderCli(), ["test", "--target", "all,interp"]);
		// (TypeScript's tests beside an example's sources: helder/test, natively and as wasm32-wasi)
		run(helderCli(), ["test", "examples/ts-todo", "--target", "all"]);
		// (the studio's own: its canvas' snapping, its ACP client, apps/studio/src/studio)
		var h = FileSystem.fullPath(helderCli()), here = Sys.getCwd();
		Sys.setCwd("apps/studio");
		try run(h, ["test", "src/studio", "--target", "all"]) catch (e:Failed) {
			Sys.setCwd(here);
			throw e;
		}
		Sys.setCwd(here);
	}

	// (the project: tests/cli/project copied, helder in its node_modules as a
	// package.json naming this checkout's src/: no link, which rmrf would follow)
	static function cli() {
		var h = helderCli();
		Sys.println('helder: ${Math.round(FileSystem.stat(h).size / 1024)} KB');
		// (the grammar, its parser's own tests src/helder/cli/Options.test.hx:
		// helder alone is help; the positional never a target; one error format)
		var none = new Map();
		expect(h, [], none, "helder <entry>                 shorthand for: helder dev <entry>");
		expect(h, ["build", "--help"], none, "  -o, --out <path>   build's output");
		expect(h, ["help", "dev"], none, "  --port <n>");
		expect(h, ["web"], none, "helder: `web` is a target: use helder dev --target web", 2);
		expect(h, ["build", "web", "examples/counter"], none, "helder build: one entry, not web and examples/counter", 2);
		expect(h, ["build", "web"], none, "helder build: `web` is a target: use --target web", 2);
		expect(h, ["run", "--bogus"], none, "helder run: unknown option --bogus (helder run --help)", 2);
		expect(h, ["dev", "--target"], none, "helder dev: --target takes a value", 2);
		expect(h, ["build", "-d", "emulator-5554"], none, "helder build: -d/--device picks a phone, emulator or simulator", 2);
		expect(h, ["run", "examples/counter", "--target", "ios-arm64"], none, "helder run: --target ios-arm64: an iPhone needs a signing identity (not yet)", 2);
		// (helder devices: no adb on the PATH, an empty directory; then a stand-in adb)
		rmrf("bin/cli/path");
		mkdirs("bin/cli/path/none");
		final noAdb = ["PATH" => FileSystem.fullPath("bin/cli/path/none"), "ADB" => "", "ANDROID_HOME" => "", "ANDROID_SDK_ROOT" => ""];
		expect(h, ["devices"], noAdb, "adb not found");
		expect(h, ["run", "examples/counter", "--target", "android"], noAdb, "adb not found (Android's platform-tools on the PATH, or ADB)", 1);
		expect(h, ["devices"], noAdb, 'host  this machine');
		if (!HOST.startsWith("windows-")) {
			mkdirs("bin/cli/path/adb");
			File.saveContent("bin/cli/path/adb/adb", "#!/bin/sh\necho 'List of devices attached'\necho 'emulator-5554  device product:sdk_gphone64 model:Pixel_7 device:emu64xa transport_id:1'\n");
			run("chmod", ["+x", "bin/cli/path/adb/adb"]);
			expect(h, ["devices"], ["PATH" => FileSystem.fullPath("bin/cli/path/adb"), "ADB" => ""], "emulator-5554  Pixel 7");
			// (helder's compiler that does not build: a stand-in node for
			// build.mjs, more errors than a pipe holds, exit code 1: the
			// errors and the build's exit code 1, not a wait for ever nor
			// hxmc's compiler in its place; on Linux timeout's 124 if it
			// waits, macOS having no timeout)
			mkdirs("bin/cli/path/node");
			File.saveContent("bin/cli/path/node/node", "#!/bin/sh\ni=0\nwhile [ $i -lt 1000 ]; do\n  echo \"src/helder/compiler/Compiler.hx:1: characters 1-2 : a stand-in error, line $i of a compiler that does not build\" >&2\n  i=$((i + 1))\ndone\nexit 1\n");
			run("chmod", ["+x", "bin/cli/path/node/node"]);
			final broken = ["HELDER_NODE" => FileSystem.fullPath("bin/cli/path/node/node"), "HELDER_BUILD_SERVER" => "0"];
			final linux = HOST.startsWith("linux-");
			final counter = (linux ? ["120", h] : []).concat(["build", "examples/counter/Counter.hx", "-o", "bin/cli/broken-compiler"]);
			// (~105 KB of errors, more than a pipe holds: the last of them, then the failure)
			expect(linux ? "timeout" : h, counter, broken, "line 999 of a compiler that does not build\n    error helder's compiler does not build", 1);
		}
		run(h, ["build", "examples/counter/Counter.hx"]);
		// (outside the checkout, no node_modules above it, a fresh cache, no
		// HXMC_RT_DIR from the launcher this runs under: helder's compiler,
		// alone in the cache, finds the platform package's runtime objects;
		// the compiler copied in, not built again)
		var tmp = (Sys.getEnv("RUNNER_TEMP") ?? Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp").split("\\").join("/");
		var fresh = '$tmp/helder-fresh-${Std.random(1 << 30)}', compiler = Path.directory(StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"])));
		copy(compiler, '$fresh/cache/compiler/${Path.withoutDirectory(compiler)}');
		if (!HOST.startsWith("windows-")) run("chmod", ["-R", "+x", '$fresh/cache/compiler']);
		File.copy("examples/counter/Counter.hx", '$fresh/Counter.hx');
		var here = Sys.getCwd(), cli = FileSystem.fullPath(h);
		Sys.setCwd(fresh);
		// (the directory made here, outside bin/: removed by removeTree, not rmrf)
		try run(cli, ["build", "Counter.hx"], ["HELDER_CACHE" => '$fresh/cache', "HXMC_RT_DIR" => ""]) catch (e:Failed) {
			Sys.setCwd(here);
			removeTree(fresh);
			throw e;
		}
		Sys.setCwd(here);
		removeTree(fresh);
		run(h, ["build", "--target", "web", "examples/counter"]);
		// (its imports the browser's and WASI's only: no other system's library reached, #83)
		run(NODE, ["tests/cli/imports.mjs", "bin/web/Counter.wasm"]);
		for (f in ["Counter.html", "Counter.wasm", "helder/os/browser.mjs", "helder/ui/imports.mjs"])
			if (!FileSystem.exists('bin/web/$f')) throw new Failed('helder build --target web: no bin/web/$f');
		// (helder.text's page ships helder's Inter, whatever machine built it)
		if (!File.getContent("bin/web/Counter.html").contains('"fonts/Inter.ttf"') || !FileSystem.exists("bin/web/fonts/Inter.ttf"))
			throw new Failed("helder build --target web: no fonts/Inter.ttf in the page");
		expect(h, ["run", "tests/cli/tally", "--", "3"], new Map(), "v1 count=3");
		rmrf("bin/cli/project");
		copy("tests/cli/project", "bin/cli/project");
		mkdirs("bin/cli/project/node_modules");
		mkdirs("bin/cli/project/node_modules/helder");
		var src = FileSystem.fullPath("src").split("\\").join("/");
		File.saveContent("bin/cli/project/node_modules/helder/package.json", haxe.Json.stringify({name: "helder", haxe: {name: "helder", classPath: src}}));
		expect(h, ["run", "bin/cli/project"], new Map(), "hello from the project");
		expect(h, ["run", "bin/cli/project/src/app/Hello.hx"], new Map(), "hello from app.Hello, hello from the project");
		run(h, ["build", "bin/cli/project", "--target", "wasm32-wasi"]);
		wasi("bin/cli/project/bin/wasm32-wasi/cli-fixture.wasm");
		run(NODE, ["tests/cli/page-args.mjs"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-native", "native"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-nohost", "native-nohost"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-web", "web"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-exit", "exit"]);
		// (assets: a change sent, nothing built, behind the same handle; the page told)
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset", "asset"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset-nohost", "asset-nohost"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset-web", "asset-web"]);
	}

	static function devtools() {
		var h = helderCli();
		exe("bin/devtools/FrameCost", cps(["src", "tests/devtools"]).concat(["-main", "FrameCost", "-D", "hxmc.dev"]));
		run(exePath("bin/devtools/FrameCost", HOST), []);
		// (helder dev's compilation server on an empty hxmc cache of its own: with
		// one kept from an earlier run (CI's actions/cache), a parse error in a
		// module the server had from that cache came back at times as "Module
		// Pulse does not define type Pulse" at no position, not the error: hxmc's
		// to fix; the check of the error's position stands)
		rmrf("bin/devtools/hxmc-cache");
		mkdirs("bin/devtools/hxmc-cache");
		run(NODE, ["tests/devtools/devtools.mjs", h, "bin/devtools/console", "console"], ["HXMC_CACHE" => FileSystem.fullPath("bin/devtools/hxmc-cache")]);
		run(NODE, ["tests/devtools/devtools.mjs", h, "bin/devtools/ui", "ui"]);
	}

	static function declarations() {
		var check = ["src/helder/typescript/api/declarations.mjs", "--check"];
		run(NODE, check);
		run(NODE, check.concat(["--cp", "tests/view", "--cp", "tests/ui",
			"TestTypeScript", "UiTypeScript"]));
		run(NODE, check.concat(["--cp", "tests/typescript/platform", "PlatformTypeScript"]));
		run(NODE, check.concat(sceneTsPaths()).concat(["frames.FramesTypeScript"]));
	}

	// (each run twice, into bin/headless-run/1 and 2: the same bytes)
	static function editLoop()
		run(NODE, ["tests/edit-loop/edit-loop.mjs", helderCli(), "bin/edit-loop"]);

	// (each program run twice, the second from the first's snapshot)
	static function dev() {
		var os = cps(["src", "tests/os"]).concat(["-D", "hxmc.dev"]);
		var views = cps(["src", "tests/view"]).concat(["-D", "hxmc.dev"]);
		var snapshot = (file:String) -> ["HXMC_DEV_SNAPSHOT" => file];
		exe("bin/dev/HotCheck", os.concat(["-main", "HotCheck"]));
		exe("bin/dev/HotTestChanged", os.concat(["-main", "HotCheck", "-D", "hot_changed"]));
		run(exePath("bin/dev/HotCheck", HOST), ["save", "bin/dev/hot.snapshot"]);
		run(exePath("bin/dev/HotCheck", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"));
		expect(exePath("bin/dev/HotTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"), "changed reset: its type changed");
		expect(exePath("bin/dev/HotTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"), "dial reset: its initial value changed");
		interp(os, "HotCheck", ["save", "bin/dev/hot-eval.snapshot"]);
		interp(os, "HotCheck", ["restore", "-"], snapshot("bin/dev/hot-eval.snapshot"));
		exe("bin/dev/RefreshCheck", views.concat(["-main", "RefreshCheck"]));
		// (an effect's thrown value uncaught in a dev build: printed, exit code 1, not a crash: tests/headless/DevThrow.hx)
		exe("bin/dev/DevThrow", cps(["src", "tests/headless"]).concat(["-D", "hxmc.dev", "-main", "DevThrow"]));
		expect(exePath("bin/dev/DevThrow", HOST), [], [], "Uncaught exception: helder.ui: <view> has no attribute flex-direction", 1);
		run(exePath("bin/dev/RefreshCheck", HOST), ["save", "bin/dev/refresh.snapshot"]);
		run(exePath("bin/dev/RefreshCheck", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"));
		exe("bin/dev/RefreshTestChanged", views.concat(["-main", "RefreshCheck", "-D", "refresh_changed"]));
		expect(exePath("bin/dev/RefreshTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"), "main.tuned reset: its initial value changed");
		interp(views, "RefreshCheck", ["save", "bin/dev/refresh-eval.snapshot"]);
		interp(views, "RefreshCheck", ["restore", "-"], snapshot("bin/dev/refresh-eval.snapshot"));
		// (the dev loop's server, @hxmc/cli's dev.mjs, run by node with the compiler)
		var compiler = "node_modules/.bin/haxe";
		run(NODE, ["tests/os/dev/dev-web.mjs", compiler, "bin/dev/web"]);
		if (HOST.startsWith("linux-")) shell('$XVFB -a -s "-screen 0 640x480x24" $NODE tests/os/dev/dev-native.mjs $compiler bin/dev/native');
		else run(NODE, ["tests/os/dev/dev-native.mjs", compiler, "bin/dev/native"]);
		run(NODE, ["tests/os/dev/server-verify.mjs", compiler]);
		run(NODE, ["tests/os/dev/dev-verify.mjs", compiler, "Counter", "web"]);
		// (helder dev's asset reload in the page: the same Image, no swap)
		run(NODE, ["tests/os/dev/dev-asset.mjs", helderCli(), "bin/dev/asset"]);
	}

	// (Linux: under Xvfb, a Windows build's Wine too)
	static function devHost() {
		run(NODE, ["tests/os/dev/dev-args.mjs", "node_modules/.bin/haxe", "bin/dev-args"]);
		var targets = [HOST].concat([for (t in (Sys.getEnv("DEV_HOST_TARGETS") ?? "").split(",")) if (t != "" && t != HOST) t]);
		for (t in targets) {
			var args = 'tests/os/dev/dev-host.mjs node_modules/.bin/haxe bin/dev-host/$t $t';
			if (HOST.startsWith("linux-")) shell('$XVFB -a -s "-screen 0 640x480x24" $NODE $args') else run(NODE, args.split(" "));
		}
	}

	static final HEADER = ~/^\/\/ *(title|summary|tags|demo|data):*(.*)$/;

	// each example directory's programs with a header naming them,
	//
	//   // title: Cube
	//   // summary: A textured cube casting a soft shadow, its shaders in Haxe
	//   // tags: gfx, shaders, 3d
	//   // demo: canvas 512x384
	//
	// (demo: canvas WxH, a program drawing on a canvas; sound, a program
	// started by a click; island, a JavaScript island of helder.web; module,
	// a wasm module JavaScript calls; none, a program of the command line
	// or of a native window, built by its own lane), each built for
	// wasm32-wasi but the islands, and those on a canvas or playing a sound for this machine
	// too, in parallel, into bin/examples (each one's log beside it), each by
	// the CLI with no flags but the target and the output: `helder build
	// <file> [--target web] -o <out>`. docs/examples' too (the docs' pages
	// play them: site/docs/Docs.hx), their ids prefixed by docs-.
	static function examples() {
		var h = helderCli();
		var builds:Array<{id:String, target:String, out:String, args:Array<String>}> = [];
		var dirs = [for (root in ["examples", "docs/examples"]) if (FileSystem.exists(root)) for (d in FileSystem.readDirectory(root)) '$root/$d'];
		dirs.sort(Reflect.compare);
		for (path in dirs) {
			if (!FileSystem.isDirectory(path)) continue;
			var dir = (path.startsWith("docs/") ? "docs-" : "") + Path.withoutDirectory(path);
			var files = [for (f in FileSystem.readDirectory(path)) if (f.endsWith(".hx") || (~/\.tsx?$/.match(f) && !f.endsWith(".d.ts"))) f];
			files.sort(Reflect.compare);
			for (f in files) {
				var head = new Map<String, String>();
				for (line in File.getContent('$path/$f').split("\n")) {
					if (!line.startsWith("//")) break;
					if (HEADER.match(line.trim())) head.set(HEADER.matched(1), HEADER.matched(2).trim());
				}
				if (!head.exists("title")) continue;
				var main = Path.withoutExtension(f);
				var demo = head.get("demo") ?? "";
				var id = dir + (files.length > 1 && main.toLowerCase() != dir.replace("-", "") ? "-" + main.toLowerCase() : "");
				// (EXAMPLES_WEB=site: not those the site's build makes too, CI's site
				// job: a canvas or a sound without fetched data, site/build.mjs)
				var bySite = Sys.getEnv("EXAMPLES_WEB") == "site" && (demo.startsWith("canvas") || demo == "sound") && !head.exists("data");
				if (demo != "" && demo != "island" && !bySite) {
					var out = 'bin/examples/wasm32-wasi/$id.wasm';
					builds.push({id: id, target: "wasm32-wasi", out: out, args: ["build", '$path/$f', "--target", "web", "-o", out]});
				}
				if (demo.startsWith("canvas") || demo == "sound") {
					var out = exePath('bin/examples/$HOST/$id', HOST);
					builds.push({id: id, target: HOST, out: out, args: ["build", '$path/$f', "-o", out]});
				}
			}
		}
		var t0 = Sys.time();
		var failed = [];
		parallel(builds, b -> {
			mkdirs(Path.directory(b.out));
			var r = build(b.args, b.out + ".log", h);
			var ok = r.code == 0 && FileSystem.exists(b.out);
			Sys.println(b.id.rpad(" ", 22) + " " + b.target.rpad(" ", 15) + " " + (ok ? "ok  " : "FAIL") + " " + Std.string(Math.round(r.seconds * 10) / 10).lpad(" ", 6) + "s");
			if (!ok) {
				failed.push(b.id + " (" + b.target + ")");
				Sys.println(r.log.length > 1500 ? r.log.substr(r.log.length - 1500) : r.log);
			}
		});
		Sys.println('examples: ${builds.length - failed.length}/${builds.length} built, ${Math.round(Sys.time() - t0)}s');
		if (failed.length > 0) throw new Failed(failed.join(", "));
	}
}
