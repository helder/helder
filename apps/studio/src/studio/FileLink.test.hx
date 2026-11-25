package studio;

import helder.test.Test;

// A link of an agent's reply to the project's file and line, else nothing
function tests() {
	describe("FileLink", () -> {
		test("a file and its line", () -> {
			equals(FileLink.parse("app.helder#L2", "/p"), {path: "/p/app.helder", line: 2});
			equals(FileLink.parse("src/a.ts:12:4", "/p"), {path: "/p/src/a.ts", line: 12});
			equals(FileLink.parse("file:///p/a%20b.ts#L3-L9", "/p"), {path: "/p/a b.ts", line: 3});
			equals(FileLink.parse("/p/app.tsx", "/p"), {path: "/p/app.tsx", line: null});
		});
		test("not the project's", () -> {
			equals(FileLink.parse("https://helder.build", "/p"), null);
			equals(FileLink.parse("mailto:a@b.c", "/p"), null);
			equals(FileLink.parse("../other/x.ts", "/p"), null);
			equals(FileLink.parse("/etc/hosts", "/p"), null);
		});
	});
}
