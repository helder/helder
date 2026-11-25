package studio;

import helder.test.Test;
import studio.Agent;
import studio.Turn;

// The prompt bar's turn folded from the agent's events: text streamed, a
// tool's updates merged into its row, the question gone once it ends
function tests() {
	describe("Turn", () -> {
		test("a message after a tool call: its own paragraph", () -> {
			var t = Turns.start("hi");
			for (e in [Text("Checking it builds."), Text(" Then"), Tool("t1", "Build", "other", "completed"), Text("Court looks good.")])
				t = Turns.add(t, e);
			equals(t.text, "Checking it builds. Then\n\nCourt looks good.");
		});
		test("a reply split where notes were sent", () -> {
			equals(Turns.split("abcdef", []), ["abcdef"]);
			equals(Turns.split("abcdef", [2, 4]), ["ab", "cd", "ef"]);
			equals(Turns.split("abc", [5]), ["abc", ""]);
		});
		test("events folded", () -> {
			var t = Turns.start("hi");
			for (e in [
				Text("Hello "), Tool("t1", "Edit app.helder", "edit", "pending"), Text("world"), Tool("t1", "", "", "completed"),
				Steps([{text: "edit", done: true}]), Ask("Allow?", ["Yes", "No"], _ -> {})
			])
				t = Turns.add(t, e);
			equals(t.text, "Hello \n\nworld");
			equals(t.tools, [{id: "t1", title: "Edit app.helder", kind: "edit", status: "completed"}]);
			equals(t.ask.options, ["Yes", "No"]);
			assert(Turns.running(t));
			t = Turns.add(t, Done("end_turn"));
			equals(t.end, "end_turn");
			equals(t.ask, null);
			assert(!Turns.running(t));
			equals(Turns.add(Turns.start("x"), Failed("gone")).error, "gone");
			equals(Turns.broken(t, "app.tsx:3: oops").build, "app.tsx:3: oops");
		});
	});
}
