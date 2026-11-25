package studio;

import helder.test.Test;

// The agents here: their names and colours, where their tool calls put
// them, done, and the clock's timeouts
function tests() {
	describe("Presence", () -> {
		test("a client's name as the studio shows it", () -> {
			equals([for (c in ["claude-code", "claude-ai", "codex-mcp-client", "gemini-cli", "cursor-vscode", "opencode", "my-agent", null])
				Presence.name(c)], ["Claude", "Claude", "Codex", "Gemini", "Cursor", "OpenCode", "My Agent", "Agent"]);
		});
		test("two of a client numbered, colours in order and freed", () -> {
			var p = new Presence();
			p.arrive("a", "claude-code");
			p.arrive("b", "claude-code");
			p.arrive("c", "codex");
			equals([for (x in p.list()) x.name], ["Claude", "Claude 2", "Codex"]);
			equals([for (x in p.list()) x.colour], Theme.AGENTS.slice(0, 3));
			p.leave("a");
			equals(p.arrive("d", "cursor").colour, Theme.AGENTS[0]);
		});
		test("tool calls move it, done stops it", () -> {
			var p = new Presence();
			p.arrive("a", "claude-code");
			p.called("a", "project.read", {path: "app.tsx"});
			p.called("a", "run.tree", {screen: "Todo/Empty"});
			var a = p.peer("a");
			equals([a.file, a.screen], ["app.tsx", "Todo/Empty"]);
			equals(a.working, true);
			p.called("a", "project.patch", {path: "Todo.hx"});
			equals([p.peer("a").file, p.peer("a").status], ["Todo.hx", "Editing Todo.hx"]);
			p.called("a", "build.check", {});
			equals(p.peer("a").status, "Checking");
			p.working("a", "Making the title red");
			equals(p.peer("a").status, "Making the title red");
			p.done("a", "The title is red");
			equals(p.peer("a").working, false);
			equals(p.peer("a").status, "The title is red");
		});
		test("done: when, by its clock; found by its name", () -> {
			var now = 5.0;
			var p = new Presence(() -> now);
			p.arrive("a", "claude-code");
			p.done("a", "red");
			equals(p.peer("a").doneAt, 5.0);
			equals(p.named("Claude")?.id, "a");
			equals(p.named("Codex"), null);
		});
		test("quiet a minute it stops, ten it leaves", () -> {
			var now = 0.0;
			var p = new Presence(() -> now);
			p.arrive("a", "claude-code");
			p.called("a", "run.snap", {});
			now = 59;
			p.tick();
			equals(p.peer("a").working, true);
			now = 61;
			p.tick();
			equals(p.peer("a").working, false);
			p.seen("a");
			now = 61 + 599;
			p.tick();
			equals(p.list().length, 1);
			now = 61 + 601;
			p.tick();
			equals(p.list().length, 0);
		});
	});
}
