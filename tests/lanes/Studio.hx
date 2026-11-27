package lanes;

import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import lanes.Tools.*;

using StringTools;

class Studio {
	public static final LANES:Array<Lane> = [
		{name: "story-shared", about: "helder.story's native preview host end to end", run: storyShared},
		{name: "compiler-web", about: "helder's toolchain as wasm in a worker", run: compilerWeb},
		{name: "studio", about: "helder studio run headless by scripts", run: studioLane},
		{name: "demos", about: "the showcase demos' stills against goldens", run: demosLane},
		{name: "studio-web", about: "helder studio in headless Chromium", run: studioWeb},
		{name: "studio-orphans", about: "helder studio killed (SIGKILL): its studio, host, play window and agent gone with it", run: () -> run(NODE, ["tests/studio/orphans.mjs", helderCli()])},
		{name: "story-host", about: "helder.story.Host's 50 stories, timed", run: storyHost},
		{name: "scenarios", about: "pong's scenarios against its stories in the studio, timed", run: scenarios},
		{name: "viewer-scenarios", about: "the viewer's scenarios in the studio: each still drawn, beside its story's, timed", run: viewerScenarios},
		{name: "headless-run", about: "helder run --headless on scripted examples", run: headlessRun}
	];

	static function storyShared() {
		var b = 'bin/story-shared/$GFX_TARGET', cp = cps(["src", "tests/story/host"]);
		native('$b/SmokeHost', cp.concat(["-main", "SmokeHost", "-D", "hxmc.dev", "-D", "helder.headless"]), GFX_TARGET);
		native('$b/SmokeStudio', cp.concat(["-main", "SmokeStudio"]), GFX_TARGET);
		var require = GFX_TARGET == HOST && (HOST.startsWith("macos-") || HOST.startsWith("windows-"));
		var args = [exePath('$b/SmokeHost', GFX_TARGET)].concat(require ? ["--require"] : []);
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) run("wine", [exePath('$b/SmokeStudio', GFX_TARGET)].concat(args)) else
			run(exePath('$b/SmokeStudio', GFX_TARGET), args);
	}

	// (drawn on the CPU, --soft: the same pixels on every machine; ui-draw is the GPU's)
	static function headlessRun() {
		var h = helderCli(), b = "bin/headless-run";
		rmrf(b);
		// (a TSX file of 2,000 lines for the code editor: examples/ts-todo's app as it was when the script was written, repeated)
		mkdirs(b);
		File.saveContent('$b/code.tsx', repeatedLines("tests/headless/code-editor.tsx.txt", 2000));
		for (pass in ["1", "2"]) {
			var o = '$b/$pass';
			// (helder.ui.code: examples/code-editor on it, scripted)
			run(h, [
				"run", "--headless", "--soft", "examples/code-editor", "--script", "tests/headless/code-editor.json", "--size", "900x640", "--tree", '$o/code-multi.json',
				"--at", "mark:multi", "--tree", '$o/code-undone.json', "--at", "mark:undone", "--tree", '$o/code-find.json', "--at", "mark:find", "--snap",
				'$o/code-end.png', "--tree", '$o/code-end.json', "--", '$b/code.tsx'
			]);
			for (app in ["todo", "ts-todo"])
				run(h, [
					"run", "--headless", "--soft", 'examples/$app', "--script", "tests/headless/todo.json", "--snap", '$o/$app-toggled.png', "--tree", '$o/$app-toggled.json',
					"--at", "mark:toggled", "--tree", '$o/$app-end.json', "--trace", '$o/$app.jsonl'
				]);
			run(h, [
				"run", "--headless", "--soft", "examples/todo", "--script", "tests/headless/todo.json", "--frames", "6", "--every", "2", "--start", "0.3", "-o", '$o/frames', "--keys",
				"--pointer"
			]);
			// (live literals: a dev build's title colour and text patched by the script, the next frame showing them)
			for (app in ["todo", "ts-todo"])
				run(h, [
					"run", "--headless", "--soft", "--dev", 'examples/$app', "--script", "tests/headless/literals.json", "--snap", '$o/$app-literal-before.png', "--at", "mark:before",
					"--snap", '$o/$app-literal-after.png', "--tree", '$o/$app-literal.json', "--at", "mark:patched"
				]);
			run(h, ["run", "--headless", "--soft", "examples/glow", "--size", "320x240", "--snap", '$o/glow.png', "--at", "0.5"]);
			// (a million rows: tests/headless/million.json's marks)
			for (app in ["million", "ts-million"]) {
				var args = ["run", "--headless", "--soft", 'examples/$app', "--script", "tests/headless/million.json", "--size", "480x640"];
				for (m in ["start", "down", "up", "end", "keys", "kept", "before", "inserted"])
					args = args.concat(["--tree", '$o/$app-$m.json', "--at", 'mark:$m']);
				run(h, args.concat(["--snap", '$o/$app-last.png', "--at", "mark:last"]));
			}
			// (helder.ui.motion: examples/motion scripted, its trace and frame strips; again under --reduced-motion)
			var shots = [];
			for (strip in [
				{name: "rows", at: [0.32, 0.37, 0.42, 0.47, 0.52, 0.6]},
				{name: "zoom", at: [1.62, 1.68, 1.74, 1.8, 1.88, 2.0]},
				{name: "theme", at: [3.02, 3.08, 3.14, 3.2, 3.3, 3.5]}
			])
				for (k => t in strip.at)
					shots = shots.concat(["--snap", '$o/motion-${strip.name}-$k.png', "--at", '$t']);
			run(h, ["run", "--headless", "--soft", "examples/motion/Motion.hx", "--script", "tests/headless/motion.json", "--trace", '$o/motion.jsonl'].concat(shots)
				.concat(["--tree", '$o/motion-end.json', "--at", "end"]));
			run(h, ["run", "--headless", "--soft", "examples/motion/Motion.hx", "--script", "tests/headless/motion.json", "--reduced-motion", "--trace", '$o/motion-reduced.jsonl']);
			run(h, ["run", "--headless", "--soft", "examples/motion/main.tsx", "--script", "tests/headless/motion.json", "--trace", '$o/motion-ts.jsonl']);
			// (helder.ui's Stack: a push mid-transition and after, the edge swipe's drags)
			run(h, [
				"run", "--headless", "--soft", "tests/headless/StackSlide.hx", "--script", "tests/headless/navigation.json", "--snap", '$o/nav-mid.png', "--tree",
				'$o/nav-mid.json', "--at", "mark:mid", "--tree", '$o/nav-detail.json', "--at", "mark:detail", "--tree", '$o/nav-dragging.json', "--at",
				"mark:dragging", "--tree", '$o/nav-kept.json', "--at", "mark:kept", "--snap", '$o/nav-end.png', "--tree", '$o/nav-end.json', "--at", "end"
			]);
			run(h, [
				"run", "--headless", "--soft", "apps/viewer", "--script", "tests/headless/viewer.json", "--size", "480x360", "--tree", '$o/viewer-menu.json', "--at", "mark:menu",
				"--tree", '$o/viewer-end.json'
			]);
		}
		exe('$b/Check', cps(["src", "tests/headless"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
		// (a video: where ffmpeg is installed)
		if (Sys.command("sh", ["-c", "command -v ffmpeg >/dev/null"]) == 0) {
			run(h, ["run", "--headless", "--soft", "examples/todo", "--script", "tests/headless/todo.json", "--video", '$b/todo.mp4', "--keys", "--pointer"]);
			if (!FileSystem.exists('$b/todo.mp4') || FileSystem.exists('$b/todo.frames')) throw new Failed('$b/todo.mp4: not written, or its frames left');
		} else Sys.println("headless-run: no ffmpeg: --video not checked");
	}

	// (HELDER_STUDIO_STEPS: some of its steps, the others' outputs kept in
	// bin/studio-check: todo, ts-todo, design, free, phone, files, acp (watch.json),
	// stories, start, check; a run of all of them past a command's time
	// limit, run in parts, check last)
	static function studioLane() {
		var h = helderCli(), b = "bin/studio-check";
		var only = (Sys.getEnv("HELDER_STUDIO_STEPS") ?? "").split(",").filter(x -> x != "");
		function step(name:String):Bool {
			if (only.length > 0 && !only.contains(name)) return false;
			// (the studio's files of it, then its copy (their links into it): a run of it as fresh as the whole lane's)
			rmrf('bin/studio/$name');
			rmrf('$b/$name');
			return true;
		}
		if (only.length == 0) {
			// (the studio's files first: their links into the copies)
			rmrf("bin/studio");
			rmrf(b);
			run(h, ["studio", "--help"]);
		}
		mkdirs(b);
		mkdirs("bin/studio");
		for (app in ["todo", "ts-todo"]) {
			if (!step(app)) continue;
			// (a copy, a repository of its own: its branch in the sidebar the same everywhere)
			copy('examples/$app', '$b/$app');
			run("git", ["init", "-q", "-b", "studio", '$b/$app']);
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/edit.json", "--size", "1180x740", "--snap", '$b/$app-overview.png', "--at",
				"mark:overview", "--snap", '$b/$app-zoomed.png', "--at", "mark:zoomed", "--snap", '$b/$app-selected.png', "--at", "mark:selected", "--snap", '$b/$app-end.png', "--at", "mark:end", "--",
				'$b/$app', "--classic", "--events", '$b/$app.jsonl'
			]);
		}
		// (a project of design files alone: its frames interpreted, nothing built)
		if (step("design")) {
			copy('examples/design', '$b/design');
			run("git", ["init", "-q", "-b", "studio", '$b/design']);
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/design.json", "--size", "1180x740", "--snap", '$b/design-selected.png', "--at",
				"mark:selected", "--snap", '$b/design-end.png', "--at", "mark:end", "--", '$b/design', "--classic", "--events", '$b/design.jsonl'
			]);
		}
		// (the free canvas: a frame selected, a story moved (its place made in canvas.helder), a frame entered, left, every frame fitted)
		if (step("free")) {
			copy('examples/todo', '$b/free');
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/free.json", "--size", "1180x740", "--snap", '$b/free-entered.png', "--at",
				"mark:entered", "--snap", '$b/free-playing.png', "--at", "mark:playing", "--snap", '$b/free-end.png', "--at", "mark:end", "--", '$b/free', "--classic", "--events", '$b/free.jsonl'
			]);
		}
		// (a phone's: the sheets over the canvas, switched by the bar, dragged by the handle)
		if (step("phone")) {
			copy('examples/design', '$b/phone');
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/phone.json", "--size", "390x844", "--snap", '$b/phone-picked.png', "--at",
				"mark:picked", "--snap", '$b/phone-end.png', "--at", "mark:end", "--", '$b/phone', "--classic", "--events", '$b/phone.jsonl'
			]);
		}
		// (the sidebar's file browser: design files, an image, a font, code in folders)
		if (step("files")) {
			copy('examples/design', '$b/files');
			mkdirs('$b/files/assets');
			mkdirs('$b/files/fonts');
			mkdirs('$b/files/src');
			File.copy("tests/ui/svg/shapes.png", '$b/files/assets/shapes.png');
			File.copy("apps/studio/fonts/HankenGrotesk-Medium.ttf", '$b/files/fonts/HankenGrotesk-Medium.ttf');
			File.saveContent('$b/files/src/Main.hx', 'class Main {\n\tstatic function main() trace("hi");\n}\n');
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/files.json", "--size", "1180x740", "--snap", '$b/files-image.png', "--at",
				"mark:image", "--snap", '$b/files-end.png', "--at", "mark:end", "--", '$b/files', "--classic", "--events", '$b/files.jsonl'
			]);
		}
		// (the studio's own shell, watched, with an agent over ACP: the scripted one, tests/studio/acp-agent.mjs on node)
		if (step("acp")) {
			copy('examples/design', '$b/acp');
			run("git", ["init", "-q", "-b", "studio", '$b/acp']);
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/watch.json", "--size", "1180x740", "--snap", '$b/acp-working.png', "--at",
				"mark:working", "--snap", '$b/acp-question.png', "--at", "mark:question", "--snap", '$b/acp-end.png', "--at", "mark:end", "--", '$b/acp', "--agent",
				'$NODE ${FileSystem.fullPath("tests/studio/acp-agent.mjs")}', "--events", '$b/acp.jsonl'
			]);
		}
		if (step("stories")) studioStories(h, b);
		if (step("start")) studioStart(h, b);
		if (only.length > 0 && !only.contains("check")) return;
		exe('$b/Check', cps(["src", "tests/studio"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
	}

	// (a story file changed under the studio, as an agent changes it: a copy
	// of examples/ts-todo held open (--hold-while) and driven over its MCP
	// server: app.story.tsx's exports renamed and a story added
	// (project.patch), a story file written on disk, a type error in app.tsx
	// and its fix; Check reads the events)
	static function studioStories(h:String, b:String) {
		var dir = '$b/stories';
		copy('examples/ts-todo', dir);
		run("git", ["init", "-q", "-b", "studio", dir]);
		held(h, b, "stories", dir, ["--classic"], (call, events, until) -> {
			until("first build", () -> events("all-shown").length > 0);
			var story = File.getContent('$dir/app.story.tsx'), app = File.getContent('$dir/app.tsx');
			// (the exports renamed, a story renamed, one added)
			call("project.patch", {
				path: "app.story.tsx",
				text: story.replace("export const empty", "export const serve").replace("export const items", "export const play")
					.replace('export const done = story({ name: "Todo/Done"', 'export const over = story({ name: "Todo/All done"')
					+ '\nexport const more = story({ name: "Todo/One item", width: 480, height: 560, render: () => <App store={store([three[0]])}/> });\n'
			});
			// (a story file written on disk: the watcher's)
			File.saveContent('$dir/extra.story.tsx', 'import { story } from "helder/story";\nimport { App, store } from "./app";\n\nexport const blank = story({ name: "Extra/Blank", width: 480, height: 560, render: () => <App store={store()}/> });\n');
			until("extra.story.tsx read", () -> Lambda.exists(events("stories"), e -> (e.file : String).endsWith("extra.story.tsx")));
			until("Extra/Blank shown", () -> Lambda.exists(events("screen-shown"), e -> e.screen == "Extra/Blank"));
			// (a type error, then its fix)
			call("project.patch", {path: "app.tsx", text: app + 'export const broken: number = "not a number";\n'});
			call("project.patch", {path: "app.tsx", text: app});
		});
	}

	// (an empty folder opened in the studio's own shell: the starter written,
	// its screen built and shown after the first prompt (the script's /tree);
	// studio.guide's topics answered; Check reads the events)
	static function studioStart(h:String, b:String) {
		var dir = '$b/start';
		mkdirs(dir);
		held(h, b, "start", dir, [], (call, events, until) -> {
			until("the starter's first build", () -> events("all-shown").length > 0);
			var start = call("studio.guide", {}), game = call("studio.guide", {topic: "game"});
			if (!start.startsWith("# Start") || start.indexOf("Topics (studio.guide {topic}): start:") < 0) throw new Failed('studio: start: studio.guide {}: ${start.substr(0, 80)}');
			if (!game.startsWith("# Game") || game.indexOf("Clock.add") < 0) throw new Failed('studio: start: studio.guide {topic: "game"}: ${game.substr(0, 80)}');
		});
	}

	// (the studio held open (--hold-while) on dir, its script tests/studio/<name>.json, the
	// end snapped to <b>/<name>-end.png, its events in <b>/<name>.jsonl, driven over its MCP
	// server by body; then let go to finish its script)
	static function held(h:String, b:String, name:String, dir:String, flags:Array<String>,
			body:(call:(String, Dynamic) -> String, events:String->Array<Dynamic>, until:(String, Void->Bool) -> Void) -> Void) {
		var hold = '$b/$name.hold';
		File.saveContent(hold, "");
		var p = new Process(h, [
			"run", "--headless", "apps/studio", "--script", 'tests/studio/$name.json', "--size", "1180x740", "--snap", '$b/$name-end.png', "--at",
			"mark:end", "--", dir
		].concat(flags).concat(["--events", '$b/$name.jsonl', "--hold-while", hold]));
		var url:Null<String> = null;
		function drain(i:haxe.io.Input)
			sys.thread.Thread.create(() -> try while (true) {
				var l = i.readLine();
				Sys.println(l);
				var at = l.indexOf("studio: MCP at ");
				if (at >= 0) url = l.substr(at + 15).split(" ")[0];
			} catch (_:Dynamic) {});
		drain(p.stdout);
		drain(p.stderr);
		function events(e:String):Array<Dynamic>
			return try [for (l in File.getContent('$b/$name.jsonl').split("\n")) if (l.indexOf('"event":"$e"') >= 0) haxe.Json.parse(l)] catch (_:Dynamic) [];
		function until(what:String, done:Void->Bool) {
			var t0 = Sys.time();
			while (url == null || !done()) {
				if (Sys.time() - t0 > 300) throw new Failed('studio: $name: no $what in 300 s');
				Sys.sleep(0.2);
			}
		}
		function call(tool:String, args:Dynamic):String {
			var http = new sys.Http(url);
			http.cnxTimeout = 300;
			http.setHeader("content-type", "application/json");
			http.setPostData(haxe.Json.stringify({jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: tool, arguments: args}}));
			var out = "";
			http.onData = d -> out = d;
			http.onError = e -> throw new Failed('studio: $name: $tool: $e');
			http.request(true);
			var r:Dynamic = haxe.Json.parse(out);
			var text:String = r.result.content[0].text;
			Sys.println('studio: $name: $tool: ' + text.split("\n").join(" ").substr(0, 200));
			return text;
		}
		try body(call, events, until) catch (e:Dynamic) {
			try sys.FileSystem.deleteFile(hold) catch (_:Dynamic) {}
			p.kill();
			throw e;
		}
		sys.FileSystem.deleteFile(hold);
		var code = p.exitCode();
		p.close();
		if (code != 0) throw new Failed('studio: $name: the studio ended with $code');
	}

	// the demos' stills: [name, entry, script or "", the program's arguments, times (seconds or mark:<name>)]
	// (scale: half by default; a quarter for the stills that are mostly noise,
	// a large golden at half that shows no more)
	static final DEMO_SHOTS:Array<{name:String, entry:String, script:String, flags:Array<String>, args:Array<String>, at:Array<String>, ?scale:Float}> = [
		{name: "showreel-title", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "title"], at: ["3.4"]},
		{name: "showreel-launch", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "launch"], at: ["1.0", "7.0"]},
		{name: "showreel-zoom", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "zoom"], at: ["2.4"]},
		{name: "showreel-odometer", entry: "examples/showreel", script: "", flags: ["--reduced-motion"], args: ["--scene", "odometer"], at: ["0.5"]},
		{name: "showreel-million", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "million"], at: ["2.2"]},
		{name: "showreel-type", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "type"], at: ["3.0"]},
		{name: "showreel-material", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "material"], at: ["4.0"], scale: 0.25},
		{name: "showreel-canvas", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "canvas"], at: ["3.0"], scale: 0.25},
		{name: "showreel-theme", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "theme"], at: ["3.6"]},
		{name: "fx", entry: "examples/fx", script: "", flags: [], args: [], at: ["1.0"]},
		{name: "fx-tour", entry: "examples/fx", script: "", flags: [], args: ["--tour"], at: ["9.6"]},
		{name: "fx-reduced", entry: "examples/fx", script: "", flags: ["--reduced-motion"], args: [], at: ["0.5"]},
		{name: "literal", entry: "examples/literal", script: "examples/literal/demo.json", flags: ["--pointer"], args: [], at: ["mark:frozen", "mark:fallen"]},
		{name: "notes", entry: "examples/notes", script: "examples/notes/demo.json", flags: ["--pointer", "--keys"], args: [], at: ["mark:launcher", "mark:end"]}
	];

	// each demo run headless (it runs: its exit status), its stills against the goldens
	static function demosLane() {
		var h = helderCli(), b = "bin/demos";
		rmrf(b);
		mkdirs(b);
		for (d in DEMO_SHOTS) {
			// (on the CPU but fx's: its effects hash noise with sin, which every
			// implementation computes apart, so its goldens are the GPU's)
			var args = ["run", "--headless"].concat(d.name.startsWith("fx") ? [] : ["--soft"]).concat([d.entry, "--scale", Std.string(d.scale ?? 0.5)])
				.concat(d.flags);
			if (d.script != "") args = args.concat(["--script", d.script]);
			for (t in d.at)
				args = args.concat(["--snap", '$b/${d.name}-${t.replace("mark:", "")}.png', "--at", t]);
			run(h, d.args.length > 0 ? args.concat(["--"]).concat(d.args) : args);
		}
		exe('$b/Check', cps(["src", "tests/demos"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
	}

	// (the site apps/studio/web/build.mjs writes: the studio for the web, todo, design and 50 screens bundled)
	static function studioWeb() {
		// helder.build's site (its sites/build/assemble.mjs) bundles these by
		// path and quotes design's app.helder: moving one broke its deploy
		for (e in ["todo", "design", "signup", "mail"])
			if (!FileSystem.isDirectory('examples/$e')) throw new Failed('examples/$e: helder.build\'s site bundles it');
		// (Playwright first: the builds take minutes)
		run(NODE, ["tests/playwright.mjs"]);
		var b = "bin/studio-web";
		rmrf(b);
		// (the site's programs started natively, a frame drawn, as its covers
		// start them: signup's look once crashed at its start on macOS)
		for (e in ["todo", "signup", "mail"]) {
			run(helderCli(), ["run", "--headless", 'examples/$e', "--snap", '$b/$e.png']);
			if (!FileSystem.exists('$b/$e.png')) throw new Failed('examples/$e: no frame drawn');
		}
		run(NODE, ["tests/story/host/host.mjs", "project", '$b/screens50']);
		// (helder.compiler.web's toolchain, as the compiler-web lane builds it: structural edits built in the browser)
		run(NODE, ["src/helder/compiler/web/build.mjs", "bin/compiler-web"]);
		run(NODE, ["apps/studio/web/build.mjs", '$b/site', "--compiler", "bin/compiler-web", "examples/todo=Todo", "examples/design=Design", '$b/screens50=50 screens']);
		run(NODE, ["tests/studio-web/check.mjs", '$b/site', b].concat(BLESS ? ["--bless"] : []));
	}

	// (the studio headless on copies of tests/scenario/fixtures/pong: stills over MCP, bin/scenario/results.md)
	static function scenarios()
		run(NODE, ["tests/scenario/check.mjs", helderCli(), "bin/scenario"]);

	// (the studio headless on copies of apps/viewer: bin/scenario-viewer/results.md)
	static function viewerScenarios()
		run(NODE, ["tests/scenario/viewer.mjs", helderCli(), "bin/scenario-viewer"]);

	static function storyHost() {
		var b = "bin/story-host";
		rmrf(b);
		run(NODE, ["tests/story/host/host.mjs", "gen", b]);
		var cp = cps(["src", "examples/todo", '$b/gen']).concat(["-D", "hxmc.dev", "-D", "helder.headless"]);
		native('$b/BenchHost', cp.concat(["-main", "BenchHost"]), HOST);
		// (the desktop studio on the same stories: helder run's)
		Sys.putEnv("HELDER", helderCli());
		run(NODE, ["tests/story/host/host.mjs", "measure", b]);
	}

	static function compilerWeb() {
		run(NODE, ["src/helder/compiler/web/build.mjs", "bin/compiler-web"]);
		run(NODE, ["tests/compiler-web/node.mjs", "bin/compiler-web"]);
		run(NODE, ["tests/compiler-web/browser.mjs", "bin/compiler-web"]);
	}
}
