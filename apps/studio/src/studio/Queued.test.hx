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
		test("a project's frames: nothing held", () -> {
			var dir = "bin/queued-test-design";
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', '<Design>\n\t<Frame name="Home" width={200} height={300}><text>Hi</text></Frame>\n</Design>\n');
			assert(!new Studio(dir, {}).waiting());
		});
		#end
	});
}
