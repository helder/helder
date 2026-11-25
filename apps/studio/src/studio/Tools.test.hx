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
		test("an empty folder: a main and a story made, its screen there and built", async(() -> {
			// (outside any package: its own project, helder's modules mapped by the
			// tsconfig.json the studio writes; helder's src/ the studio's, as Main sets it)
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var s = empty(haxe.io.Path.normalize((Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp") + "/helder-studio-revive"));
			equals(s.project.typescript, false);
			equals(s.previews == null, true);
			// (the screens in view, as the canvas tells them each frame: drawn)
			var done = false;
			helder.async.Async.launch(_ -> while (!done) {
				if (s.previews != null) s.previews.show([for (x in s.previews.screens) x.info.name], null);
				helder.async.Async.delay(0.1);
			});
			s.tools.call("project.patch", {path: "app.tsx", text: 'export function App() {\n\treturn <view grow={1} background="#0e1424"><text color="#9fd3ff">Pond</text></view>;\n}\n'}, "a");
			s.tools.call("project.patch", {path: "main.tsx", text: 'import { UiWindow, Surface } from "helder/ui";\nimport { App } from "./app";\n\nUiWindow.run(<Surface title="Pond" width={320} height={480}><App/></Surface>);\n'}, "a");
			s.tools.call("project.patch", {path: "app.story.tsx", text: 'import { story } from "helder/story";\nimport { App } from "./app";\n\nexport const pond = story({ name: "Pond/Start", width: 320, height: 480, render: () => <App/> });\n'}, "a");
			equals(s.project.typescript, true);
			equals(s.previews != null, true);
			equals([for (x in s.project.live()) x.name], ["Pond/Start"]);
			var t0 = haxe.Timer.stamp();
			while (s.previews.busy() && haxe.Timer.stamp() - t0 < 120)
				helder.async.Async.delay(0.1);
			equals(s.previews.screen("Pond/Start").version > 0, true);
			var c:Dynamic = haxe.Json.parse(s.tools.call("build.check", {}, "a").content[0].text);
			equals(c.ok, true);
			done = true;
			s.stop();
		})).timeout(180);
		#end
	});
}
