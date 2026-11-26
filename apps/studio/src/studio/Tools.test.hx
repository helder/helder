package studio;

import helder.test.Test;

// An agent's patch through the studio's tools: its history entry its name,
// the agent there, the lines it made (natively: a copy of tests/studio/design)
function tests() {
	describe("Tools", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("an agent's patch: the history's entry its", async(() -> {
			var dir = "bin/tools-test";
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', sys.io.File.getContent("../../tests/studio/design/app.helder"));
			var s = new Studio(dir, {});
			s.presence.arrive("a", "claude-code");
			var r = s.tools.call("project.patch", {path: "app.helder", edits: [{old: 'color="#3b82f6">todos', "new": 'color="#ef4444">todos'}]}, "a");
			equals(r.isError, false);
			var e = s.docs.nextUndo();
			equals([e.by, e.label, Studio.entryLabel(e)], ["Claude", "app.helder", "Claude: app.helder"]);
			var a = s.presence.peer("a");
			equals([a.file, a.status], ["app.helder", "Editing app.helder"]);
			equals(a.working, true);
			equals(a.spans.length, 1);
			s.tools.call("studio.done", {note: "red"}, "a");
			equals(s.presence.peer("a").working, false);
			s.undo();
			equals(s.docs.nextUndo(), null);
			var both = s.tools.call("project.patch", {path: "app.helder", text: "x", edits: []}, "a");
			equals(both.isError, true);
			equals(sys.io.File.getContent('$dir/app.helder').indexOf("todos") >= 0, true);
		}));
		// (an empty folder, as an agent finds a new project)
		function empty(dir:String):Studio {
			if (sys.FileSystem.exists(dir)) helder.cli.TestCommand.rmrf(dir);
			helder.cli.TestCommand.mkdirs(dir);
			var s = new Studio(dir, {});
			s.presence.arrive("a", "claude-code");
			return s;
		}
		test("a patch's text makes a file (its folder too); undone it is gone", async(() -> {
			var s = empty("bin/tools-create"), f = s.project.dir + "/sketches/a.helder";
			var r = s.tools.call("project.patch", {path: "sketches/a.helder", text: '<Design>\n\t<Frame name="Home"><text>Hi</text></Frame>\n</Design>\n'}, "a");
			equals(r.isError, false);
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [true, true]);
			equals(s.docs.nextUndo().by, "Claude");
			s.undo();
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [false, false]);
			s.redo();
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [true, true]);
			var missing = s.tools.call("project.patch", {path: "app.tsx", edits: [{old: "a", "new": "b"}]}, "a");
			equals(missing.isError, true);
			equals(missing.content[0].text, "app.tsx: no such file; send text to create it");
		}));
		test("a patch deletes a file; undone it is back, redone gone", async(() -> {
			var s = empty("bin/tools-delete"), f = s.project.dir + "/sketches/a.helder";
			s.tools.call("project.patch", {path: "sketches/a.helder", text: '<Design>\n\t<Frame name="Home"><text>Hi</text></Frame>\n</Design>\n'}, "a");
			equals(s.tools.call("project.patch", {path: "sketches/a.helder", delete: true}, "a").isError, false);
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [false, false]);
			equals(s.docs.nextUndo().by, "Claude");
			s.undo();
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [true, true]);
			s.redo();
			equals([sys.FileSystem.exists(f), s.project.screen("sketches/a.helder#Home") != null], [false, false]);
			var again = s.tools.call("project.patch", {path: "sketches/a.helder", delete: true}, "a");
			equals(again.isError, false);
			equals(haxe.Json.parse(again.content[0].text).result, "gone");
		}));
		test("an empty folder: a main and a story made, its screen there and built", async(() -> {
			// (outside any package: its own project, helder's modules mapped by the
			// tsconfig.json the studio writes; helder's src/ the studio's, as Main sets it)
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var dir = Temp.dir("helder-studio-revive"), s = empty(dir), done = false;
			try {
				equals(s.project.typescript, false);
				equals(s.previews == null, true);
				// (one screen in view, as the canvas tells it each frame: the other drawn all the same, not waited on)
				helder.async.Async.launch(_ -> while (!done) {
					if (s.previews != null) s.previews.show(["Pond/Start"], null);
					helder.async.Async.delay(0.1);
				});
				s.tools.call("project.patch", {path: "app.tsx", text: 'export function App() {\n\treturn <view grow={1} background="#0e1424"><text color="#9fd3ff">Pond</text></view>;\n}\n'}, "a");
				s.tools.call("project.patch", {path: "main.tsx", text: 'import { UiWindow, Surface } from "helder/ui";\nimport { App } from "./app";\n\nUiWindow.run(<Surface title="Pond" width={320} height={480}><App/></Surface>);\n'}, "a");
				s.tools.call("project.patch", {path: "app.story.tsx", text: 'import { story } from "helder/story";\nimport { App } from "./app";\n\nexport const pond = story({ name: "Pond/Start", width: 320, height: 480, render: () => <App/> });\nexport const ripple = story({ name: "Pond/Ripple", width: 320, height: 480, loop: 1.5, render: () => <App/> });\n'}, "a");
				equals(s.project.typescript, true);
				equals(s.previews != null, true);
				equals([for (x in s.project.live()) x.name], ["Pond/Start", "Pond/Ripple"]);
				equals([for (x in s.project.live()) x.loop], [null, 1.5]);
				var t0 = haxe.Timer.stamp();
				while (s.previews.busy() && haxe.Timer.stamp() - t0 < 120)
					helder.async.Async.delay(0.1);
				equals(s.previews.screen("Pond/Start").version > 0, true);
				var snap = s.tools.call("run.snap", {screen: "Pond/Ripple"}, "a");
				equals([snap.isError, s.previews.screen("Pond/Ripple").version > 0], [false, true]);
				var c:Dynamic = haxe.Json.parse(s.tools.call("build.check", {}, "a").content[0].text);
				equals(c.ok, true);
				// (Play: the story in a window of its own, a main of it beside the project's files)
				var entry = s.playEntry(s.project.screen("Pond/Start"));
				equals(haxe.io.Path.withoutDirectory(entry), Studio.PLAY);
				equals(sys.io.File.getContent(entry).indexOf('import { pond } from "./app.story";\n\nplay(pond);') > 0, true);
				done = true;
				s.stop();
			} catch (e:haxe.Exception) {
				done = true;
				s.stop();
				Temp.remove(dir);
				throw e;
			}
			Temp.remove(dir);
		})).timeout(180);
		test("a screen that throws when run: why, where, in the answers; the others drawn", async(() -> {
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var dir = Temp.dir("helder-studio-crash"), s = empty(dir), done = false;
			try {
				helder.async.Async.launch(_ -> while (!done) {
					if (s.previews != null) s.previews.show(["App/Good", "App/Bad"], null);
					helder.async.Async.delay(0.1);
				});
				s.tools.call("project.patch", {path: "app.tsx", text: 'const end: any = ["e", "nd"].join("");\n\nexport function Good() {\n\treturn <view grow={1}/>;\n}\n\nexport function Bad() {\n\treturn <view grow={1}>\n\t\t<text text-align={end}>Bad</text>\n\t</view>;\n}\n'}, "a");
				s.tools.call("project.patch", {path: "main.tsx", text: 'import { UiWindow, Surface } from "helder/ui";\nimport { Good } from "./app";\n\nUiWindow.run(<Surface title="Two" width={200} height={200}><Good/></Surface>);\n'}, "a");
				var r = s.tools.call("project.patch", {path: "app.story.tsx", text: 'import { story } from "helder/story";\nimport { Good, Bad } from "./app";\n\nexport const good = story({ name: "App/Good", width: 200, height: 200, render: () => <Good/> });\nexport const bad = story({ name: "App/Bad", width: 200, height: 200, render: () => <Bad/> });\n'}, "a");
				var a:Dynamic = haxe.Json.parse(r.content[0].text);
				// (a value known only when it runs: a literal one is an error when compiling)
				var why = "app.tsx:9: text-align: end is not a TextAlign";
				equals(a.result, "crashed");
				equals(a.crashed, ['App/Bad: $why']);
				equals([s.previews.screen("App/Good").version > 0, s.previews.screen("App/Bad").crashed], [true, true]);
				var snap = s.tools.call("run.snap", {screen: "App/Bad"}, "a");
				equals(snap.isError, true);
				equals(snap.content[0].text, 'App/Bad crashed: $why');
				var c:Dynamic = haxe.Json.parse(s.tools.call("build.check", {}, "a").content[0].text);
				equals(c.ok, true);
				equals(c.crashed, ['App/Bad: $why']);
				equals(s.crashes(), ['App/Bad: $why']);
				done = true;
				s.stop();
			} catch (e:haxe.Exception) {
				done = true;
				s.stop();
				Temp.remove(dir);
				throw e;
			}
			Temp.remove(dir);
		})).timeout(180);
		test("a file made again: the checker finds it (no TS2307 kept)", async(() -> {
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var dir = Temp.dir("helder-studio-again"), s = empty(dir), done = false;
			try {
				helder.async.Async.launch(_ -> while (!done) {
					if (s.previews != null) s.previews.show(["App/Start"], null);
					helder.async.Async.delay(0.1);
				});
				var app = 'export function App() {\n\treturn <view grow={1}/>;\n}\n';
				s.tools.call("project.patch", {path: "app.tsx", text: app}, "a");
				s.tools.call("project.patch", {path: "main.tsx", text: 'import { UiWindow, Surface } from "helder/ui";\n\nUiWindow.run(<Surface title="A" width={200} height={200}><view/></Surface>);\n'}, "a");
				s.tools.call("project.patch", {path: "app.story.tsx", text: 'import { story } from "helder/story";\nimport { App } from "./app";\n\nexport const start = story({ name: "App/Start", width: 200, height: 200, render: () => <App/> });\n'}, "a");
				function result(r:{content:Array<Dynamic>, isError:Bool}):String
					return haxe.Json.parse(r.content[0].text).result;
				equals(result(s.tools.call("project.patch", {path: "app.tsx", delete: true}, "a")), "failed");
				equals(s.problems()[0].indexOf("TS2307") > 0, true);
				equals(result(s.tools.call("project.patch", {path: "app.tsx", text: app}, "a")), "built");
				done = true;
				s.stop();
			} catch (e:haxe.Exception) {
				done = true;
				s.stop();
				Temp.remove(dir);
				throw e;
			}
			Temp.remove(dir);
		})).timeout(180);
		#end
	});
}
