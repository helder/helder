package studio;

import helder.test.Test;

// The chat's questions and lines (natively: a studio on a design file): an
// ACP permission ask is a question of the same card, its pick its reply
// (not the inbox's), closed when its turn ends; several picks toggled, then
// sent; the turn's line before the agent's first words
function tests() {
	describe("Conversation", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		function studio(dir:String):Studio {
			helder.cli.TestCommand.mkdirs(dir);
			sys.io.File.saveContent('$dir/app.helder', '<Design>\n\t<Frame name="Home" width={200} height={300}><text>Hi</text></Frame>\n</Design>\n');
			return new Studio(dir, {});
		}
		test("a permission ask: the card's pick its reply, closed after", () -> {
			var s = studio("bin/conversation-test-0");
			var got = [];
			var q = s.questions.permission({name: "Claude", colour: "#e8875b"}, "Edit app.helder", ["Allow", "Reject"], (picked, text) -> got.push(picked));
			equals(s.questions.open().length, 1);
			s.questions.pick(q.id, "1");
			equals(got, [["1"]]);
			equals(s.inbox.pending().length, 0);
			var q2 = s.questions.permission({name: "Claude", colour: "#e8875b"}, "Run it", ["Allow"], (_, _) -> got.push([]));
			s.questions.close(q2.id);
			equals(s.questions.get(q2.id).answered, true);
			equals(got.length, 1);
		});
		test("several picks: toggled, then sent", () -> {
			var s = studio("bin/conversation-test-1");
			var q = s.questions.ask(null, "Which rows?", [{id: "a", label: "A"}, {id: "b", label: "B"}, {id: "c", label: "C"}], true);
			s.questions.pick(q.id, "a");
			s.questions.pick(q.id, "c");
			s.questions.pick(q.id, "a");
			equals(s.questions.get(q.id).answered, false);
			s.questions.send(q.id);
			equals(s.questions.get(q.id).picked, ["c"]);
			equals(s.inbox.pending().length, 1);
		});
		test("the turn's line before its first words: what the agent says it does, else thinking", () -> {
			var s = studio("bin/conversation-test-2");
			var t = Turn.Turns.add(Turn.Turns.start("a pong game"), Thought("A court."));
			equals(Chat.status(s, t), "Thinking…");
			var p = s.presence.arrive("a", "claude-code");
			s.presence.working(p.id, "Sketching the court");
			helder.view.graph.Graph.flush();
			equals(Chat.status(s, t), "Sketching the court");
			s.presence.done(p.id);
			helder.view.graph.Graph.flush();
			equals(Chat.status(s, t), "Thinking…");
		});
		test("a question's place: where the turn's reply was when it was asked", () -> {
			var s = studio("bin/conversation-test-3");
			s.talk.set(Turn.Turns.add(Turn.Turns.start("a game"), Text("Three ideas.")), true);
			var q = s.questions.ask(null, "Which game?", [{id: "a", label: "A"}, {id: "b", label: "B"}], false);
			equals([q.turn, q.at], [0, 12]);
			equals(Turn.Turns.split("Three ideas. Building A.", [q.at]), ["Three ideas.", " Building A."]);
		});
		#end
	});
}
