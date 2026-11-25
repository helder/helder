package studio;

import helder.test.Test;

// When the canvas waits (after the first prompt its places held by the
// queued blocks): nothing of the agent's on it (an empty folder's starter,
// until the agent changes it), not over a project's frames
function tests() {
	describe("Queued", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("the starter's canvas waits, until the agent's first change", () -> {
			// (outside any package: the starter's own tsconfig, as an Untitled folder's)
			var dir = Temp.dir("helder-queued-test");
			// (as Main does: the helder this studio was built from, for a project without one)
			if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", BuildInfo.helderSrc());
			var s = new Studio(dir, {starter: true});
			assert(s.starter);
			assert(s.waiting());
			s.touched(true);
			helder.view.graph.Graph.flush();
			equals(s.project.screens.length, 1);
			assert(!s.waiting());
			Temp.remove(dir);
		});
		test("a project's frames: nothing held", () -> {
			var dir = "bin/queued-test-design";
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', '<Design>\n\t<Frame name="Home" width={200} height={300}><text>Hi</text></Frame>\n</Design>\n');
			assert(!new Studio(dir, {}).waiting());
		});
		#end
	});
}
