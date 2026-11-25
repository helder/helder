package studio;

import helder.test.Test;
import helder.syntax.Transaction;

// An agent's edit marked on the canvas (Marks): its toast, its frame; the
// user's own edit none; a new frame rising (natively: a copy of tests/studio/design)
function tests() {
	describe("Marks", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		function studio(dir:String):Studio {
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', sys.io.File.getContent("../../tests/studio/design/app.helder"));
			return new Studio(dir, {});
		}
		test("an agent's patch: its toast, its frame", async(() -> {
			var s = studio("bin/marks-test");
			s.presence.arrive("a", "claude-code");
			s.tools.call("project.patch", {path: "app.helder", edits: [{old: 'color="#3b82f6">todos', "new": 'color="#e8875b">todos'}]}, "a");
			helder.view.graph.Graph.flush();
			var t = s.marks.toast.peek();
			equals([t.by, t.file], ["Claude", "app.helder"]);
			equals(t.entry == s.docs.nextUndo(), true);
			equals(s.presence.peer("a").screen, "app.helder#Home");
		}));
		test("the user's own edit: nothing marked", () -> {
			var s = studio("bin/marks-test-2");
			var f = s.project.dir + "/app.helder", text = s.docs.get(f).text, at = text.indexOf("#3b82f6");
			s.edit(f, new Transaction([new helder.syntax.Transaction.Change(at, at + 7, "#ef4444")], null, text), "colour", "inspector");
			helder.view.graph.Graph.flush();
			equals(s.marks.toast.peek(), null);
			equals(s.presence.list().length, 0);
		});
		test("a frame new since the last: it arrives", () -> {
			var s = studio("bin/marks-test-3");
			s.marks.saw(["app.helder#Home", "app.helder#Empty", "app.helder#Done"]);
			helder.view.graph.Graph.flush();
			equals([for (a in s.marks.arrivals.peek()) a.screen], ["app.helder#Done"]);
		});
		#end
	});
}
