package studio;

import helder.test.Test;

function tests() {
	describe("Launch", () -> {
		function read(lines:Array<String>):Launch {
			var l = new Launch("/p", "building App");
			for (s in lines)
				l.read(s);
			return l;
		}
		test("on its way: starting, its last line shown", () -> {
			var l = read(["helder dev v0.1.0  host · main"]);
			equals([l.state, l.note], ["starting", "helder dev v0.1.0  host · main"]);
		});
		test("a diagnostic's lines not shown on its way", () -> {
			var l = read(["   watching /p", "[WARNING] /h/Hot.hx:248: lines 248-252", "248 |  x", "- |  [...]", "     | a warning"]);
			equals(l.note, "watching /p");
		});
		test("built: running", () -> {
			equals(read(["\x1b[1;32m      built\x1b[0m in 3.2 s · 11 MB"]).state, "running");
		});
		test("a failed build: its first error and where, helder dev still on", () -> {
			var l = read([
				"[ERROR] /p/app.tsx:47: characters 8-14",
				"",
				"  47 |  const oops: number = \"x\";",
				"     |        ^^^^",
				"     | TS2322: Type 'string' is not assignable to type 'number'.",
				"[ERROR] /p/paper.tsx:3: characters 1-2",
				"     | TS1005: ';' expected.",
				"     failed in 2.3 s · waiting for a change"
			]);
			equals([l.state, l.at, l.note], ["failed", "app.tsx:47", "TS2322: Type 'string' is not assignable to type 'number'."]);
		});
		test("an early exit: failed, its code; a closed window: ended", () -> {
			var a = read(["helder dev v0.1.0"]);
			a.exited(1);
			equals([a.state, a.note], ["failed", "helder dev ended (exit code 1)"]);
			var b = read(["      built in 1 s", "     closed the program exited; stopping"]);
			b.exited(0);
			equals(b.state, "ended");
		});
		test("an error: failed, its message", () -> {
			var l = read(["      error the program did not start: no such file"]);
			equals([l.state, l.note], ["failed", "the program did not start: no such file"]);
		});
	});
}
