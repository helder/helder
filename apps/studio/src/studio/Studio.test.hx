package studio;

import helder.test.Test;

function tests() {
	describe("Studio", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("a source edited on disk, not a story's or a design's: an edit of the history", async(() -> Temp.within("helder-disk", dir -> {
			Files.save('$dir/app.helder', sys.io.File.getContent("../../tests/studio/design/app.helder"));
			Files.save('$dir/paper.ts', "export const fold = 1;\n");
			var s = new Studio(dir, {});
			s.scanDisk();
			// (within the same second: its size tells it apart)
			Files.save('$dir/paper.ts', "export const fold = 22;\n");
			s.scanDisk();
			var e = s.docs.nextUndo();
			equals([e?.file, e?.label], [s.project.dir + "/paper.ts", "the file changed on disk"]);
			equals(s.docs.get(s.project.dir + "/paper.ts").text, "export const fold = 22;\n");
		})));
		test("a frame's bar: its label, Play from here (the scenarios' main: the root held, then played at it), Ask's chip, Code at its line",
			async(() -> Temp.within("helder-bar", dir -> {
				Files.save('$dir/main.tsx', 'import { UiWindow } from "helder/ui";\nimport { App } from "./app";\n\nUiWindow.run(<App/>);\n');
				Files.save('$dir/app.tsx', 'import { signal } from "helder/view";\n\nexport const sky = signal("day");\nexport function App() {\n\treturn <view/>;\n}\n');
				Files.save('$dir/app.scenario.tsx', 'import { scenario } from "helder/scenario";\nimport { sky } from "./app";\n\n// the beam at dusk\n'
					+ 'export const dusk = scenario({ name: "Harbour at night/Dusk sweep", loop: 7, boot() { sky("dusk"); } });\n');
				if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
				Starter.config(dir);
				var s = new Studio(dir, {}), name = "Harbour at night/Dusk sweep";
				equals(SelectionBar.parts(s.project, name), {label: "Harbour at night · Dusk sweep", play: true, loop: 7.0});
				s.focus(name, false);
				helder.view.graph.Graph.flush();
				equals(SelectionBar.selected(s), [name]);
				var entry = s.playEntry(s.project.screen(name));
				var main = Files.read(entry);
				equals([for (l in main.split("\n")) if (StringTools.startsWith(l, "import") || StringTools.startsWith(l, "play")) l], [
					'import "./.helder-play-boot";', 'import { dusk as s0 } from "./app.scenario";', 'import "./main";', 'import { play } from "helder/scenario";',
					'play([s0], "Harbour at night/Dusk sweep");'
				]);
				equals(Files.read('${s.project.dir}/${Studio.BOOT}').indexOf('import { hold } from "helder/scenario";\n\nhold();\n') > 0, true);
				s.clearAbout();
				helder.view.graph.Graph.flush();
				equals([s.about(), s.focused.peek()], [null, name]);
				s.askAbout(name);
				helder.view.graph.Graph.flush();
				equals(s.about(), name);
				s.codeOf(name);
				helder.view.graph.Graph.flush();
				equals(s.talk.reading.peek(), {file: s.project.dir + "/app.scenario.tsx", line: 5});
			})));
		test("Play from here with a window open: switched (a scenario it has), queued (an edit not built), its main written again (one it has not), else a window of its own", () -> {
			equals(Studio.playPlan(true, ["A/One", "A/Two"], "A/Two", true, false), "switch");
			equals(Studio.playPlan(true, ["A/One", "A/Two"], "A/Two", true, true), "queue");
			equals(Studio.playPlan(true, ["A/One"], "A/Three", true, false), "rewrite");
			equals(Studio.playPlan(true, null, "A/Two", true, false), "open");
			equals(Studio.playPlan(true, ["A/One"], "Court/In motion", false, false), "open");
			equals(Studio.playPlan(false, ["A/One"], "A/One", true, false), "open");
		});
		// (the window's half: the scenarios' main built headless, run as helder dev runs it, this test its devtools)
		test("Play from here's window: two scenarios played in it, its tree after each", async(() -> {
			var dir = Temp.dir("helder-play");
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			Files.save('$dir/main.tsx', 'import { UiWindow, Surface } from "helder/ui";\nimport { App } from "./app";\n\n'
				+ 'UiWindow.run(<Surface title="Labels" width={240} height={120}><App/></Surface>);\n');
			Files.save('$dir/app.tsx', 'import { signal } from "helder/view";\n\nexport const label = signal("main");\n'
				+ 'export function App() {\n\treturn <view flexGrow={1}><text>{label()}</text></view>;\n}\n');
			Files.save('$dir/app.scenario.tsx', 'import { scenario } from "helder/scenario";\nimport { label } from "./app";\n\n'
				+ 'export const one = scenario({ name: "Labels/One", boot() { label("one"); } });\n'
				+ 'export const two = scenario({ name: "Labels/Two", boot() { label("two"); } });\n');
			Starter.config(dir);
			var s = new Studio(dir, {}), entry = s.playEntry(s.project.screen("Labels/One"));
			var cli = sys.FileSystem.fullPath("../../src/helder/cli/run.mjs");
			var b = new sys.io.Process("node", [cli, "run", "--headless", "--dev", entry, "--snap", '$dir/first.png', "--at", "0.2"]);
			var out = b.stdout.readAll().toString() + b.stderr.readAll().toString(), code = b.exitCode();
			b.close();
			if (code != 0) Sys.println(out);
			equals(code, 0);
			var exe = sys.FileSystem.fullPath("bin/headless/" + haxe.io.Path.withoutExtension(Studio.PLAY));
			var server = helder.async.Server.listen("127.0.0.1", 0);
			var env = helder.async.Process.environment();
			env.set("HXMC_DEV", '127.0.0.1:${server.port}');
			env.set("HXMC_DEV_PROTOCOL", "1");
			env.set("HELDER_HEADLESS", haxe.Json.stringify({serve: {frames: '$dir/frames.rgba'}}));
			var p = new helder.async.Process(exe, [], {env: env, cwd: dir});
			try {
				var d = new Dev(server.accept());
				equals(d.shows("one"), true);
				equals(d.call("Scenario.play", {name: "Labels/Two"}).result.playing, "Labels/Two");
				equals([d.shows("two"), d.texts().contains("one")], [true, false]);
				equals(d.call("Scenario.play", {name: "Labels/One"}).result.playing, "Labels/One");
				equals([d.shows("one"), d.texts().contains("two")], [true, false]);
				equals(d.call("Scenario.play", {name: "Labels/Nope"}).error != null, true);
			} catch (e:haxe.Exception) {
				p.kill();
				server.close();
				Temp.remove(dir);
				throw e;
			}
			p.kill();
			server.close();
			Temp.remove(dir);
		})).timeout(300);
		#end
	});
}

#if !(hxmc.target == "wasm32-wasi")
// (a program's devtools connection, as helder dev's end of it: its hello answered, requests by id, its tree's texts)
private class Dev {
	final socket:helder.async.Socket;
	final reader:helder.async.Reader;
	var id = 0;

	public function new(socket:Null<helder.async.Socket>) {
		if (socket == null) throw "no connection";
		this.socket = socket;
		reader = new helder.async.Reader(socket);
	}

	@:coroutine public function call(method:String, params:Dynamic):Dynamic {
		var mine = ++id;
		socket.writeString(haxe.Json.stringify({jsonrpc: "2.0", id: mine, method: method, params: params}) + "\n");
		while (true) {
			var line = reader.readLine();
			if (line == null) return null;
			var m:Dynamic = try haxe.Json.parse(line) catch (_:Dynamic) null;
			if (m == null) continue;
			if (m.method == "Runtime.hello" && m.id != null) socket.writeString(haxe.Json.stringify({jsonrpc: "2.0", id: m.id, result: {protocol: 1}}) + "\n");
			if (m.method == null && m.id == mine) return m;
		}
	}

	@:coroutine public function texts():Array<String> {
		var out = [];
		function walk(n:Dynamic) {
			if (n == null) return;
			if (n.text != null) out.push(Std.string(n.text));
			for (c in (n.children ?? [] : Array<Dynamic>))
				walk(c);
		}
		walk(Studio.rootOf(call("Ui.getTree", {})));
		return out;
	}

	// (text in its tree within 10 s)
	@:coroutine public function shows(text:String):Bool {
		var t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 10) {
			if (texts().contains(text)) return true;
			helder.async.Async.delay(0.05);
		}
		return false;
	}
}
#end
