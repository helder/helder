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
		#end
	});
}
