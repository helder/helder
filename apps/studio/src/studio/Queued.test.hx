package studio;

import helder.test.Test;

// When the canvas waits (after the first prompt its places held by the
// queued blocks): nothing of the agent's on it (an empty folder's starter,
// until the agent changes it), not over a project's frames
function tests() {
	describe("Queued", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("the starter's canvas waits until a frame of the agent's draws; the starter's own never shown", async(() -> {
			// (outside any package: the starter's own tsconfig, as an Untitled folder's)
			var dir = Temp.dir("helder-queued-test");
			// (as Main does: the helder this studio was built from, for a project without one)
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var s = new Studio(dir, {starter: true});
			s.presence.arrive("a", "claude-code");
			assert(s.starter);
			assert(s.waiting());
			s.touched(true);
			helder.view.graph.Graph.flush();
			equals([s.project.screens.length, s.layout.screens().length], [1, 0]);
			assert(s.waiting());
			s.tools.call("project.patch", {path: "sketches/a.helder", text: '<Design>\n\t<Frame name="Home" width={200} height={300}><text>Hi</text></Frame>\n</Design>\n'}, "a");
			helder.view.graph.Graph.flush();
			assert(!s.waiting());
			equals([for (r in s.layout.screens()) r.name], ["sketches/a.helder#Home"]);
			// (the starter's files edited: its story the agent's, shown)
			s.tools.call("project.patch", {path: "app.tsx", edits: [{old: ">App<", "new": ">Pond<"}]}, "a");
			equals(s.starterOwn("App/Start"), false);
			s.stop();
			Temp.remove(dir);
		}));
		test("the starter's files go by themselves once the agent's story is there and nothing imports them", async(() -> {
			var dir = Temp.dir("helder-queued-tidy");
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var s = new Studio(dir, {starter: true});
			s.presence.arrive("a", "claude-code");
			function there()
				return [for (f in ["app.tsx", "app.story.tsx", "main.tsx"]) sys.FileSystem.exists('$dir/$f')];
			s.tools.call("project.patch", {path: "pond.tsx", text: 'export function Pond() {\n\treturn <view flexGrow={1}/>;\n}\n'}, "a");
			equals(there(), [true, true, true]);
			s.tools.call("project.patch", {path: "pond.story.tsx", text: 'import { story } from "helder/story";\nimport { Pond } from "./pond";\n\nexport const start = story({ name: "Pond/Start", width: 200, height: 200, render: () => <Pond/> });\n'}, "a");
			// (main.tsx, the starter's still, imports ./app: it stays)
			equals(there(), [true, false, true]);
			s.tools.call("project.patch", {path: "main.tsx", text: 'import { UiWindow, Surface } from "helder/ui";\nimport { Pond } from "./pond";\n\nUiWindow.run(<Surface title="Pond" width={200} height={200}><Pond/></Surface>);\n'}, "a");
			equals(there(), [false, false, true]);
			// (each removal an entry of the history: undone, back)
			s.undo();
			equals(there(), [true, false, true]);
			s.stop();
			Temp.remove(dir);
		}));
		test("a project's frames: nothing held", () -> {
			var dir = "bin/queued-test-design";
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', '<Design>\n\t<Frame name="Home" width={200} height={300}><text>Hi</text></Frame>\n</Design>\n');
			assert(!new Studio(dir, {}).waiting());
		});
		#end
	});
}
