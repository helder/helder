// Audit H (the apps onto helder.ui.controls, widgets gone): shared helpers for the scripts
// beside this file. Each script is idempotent: run it again after a rebase
// (`node tools/audit-h/<n>-<step>.mjs` from the checkout's root) and it
// renames what the rebase brought in, leaving what it already renamed.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "../..");
const DIRS = ["src", "apps", "examples", "tests", "docs", "site", "README.md", "CONTRIBUTING.md", ".github"];
const TEXT = /\.(hx|ts|tsx|mts|mjs|js|json|md|hxml|yml|yaml|css|snap|txt|html)$/;

// the repository's tracked text files under DIRS (paths relative to root)
export function files(filter = () => true) {
	const out = execFileSync("git", ["ls-files", "-z", "--", ...DIRS], { cwd: root, maxBuffer: 1 << 28 }).toString().split("\0");
	return out.filter((f) => f && TEXT.test(f) && !f.includes("/fixtures/") && !f.startsWith("tools/audit-h/") && fs.existsSync(path.join(root, f)) && filter(f));
}

export function read(f) {
	return fs.readFileSync(path.join(root, f), "utf8");
}

let changed = 0;
export function write(f, s) {
	if (read(f) === s) return;
	fs.writeFileSync(path.join(root, f), s);
	changed++;
}

// every file: s => s', counted
export function edit(filter, fn) {
	for (const f of files(filter)) {
		const s = read(f), t = fn(s, f);
		if (t !== s) write(f, t);
	}
}

// a git mv, unless done
export function move(from, to) {
	if (!fs.existsSync(path.join(root, from))) return;
	fs.mkdirSync(path.dirname(path.join(root, to)), { recursive: true });
	execFileSync("git", ["mv", from, to], { cwd: root });
	changed++;
}

// an import line added (Haxe), unless there: before the first import (the
// file's own imports, later, keep precedence), else after the package line
export function addImport(s, line) {
	if (s.split(/\r?\n/).includes(line)) return s;
	// (a reject fixture's expected positions: a line further down)
	s = s.replace(/^\/\/ expect: [\w.]+\.hx:\d+:.*$/gm, (l) =>
		l.replace(/(\.hx:)(\d+)(?=:)/, (_, a, n) => a + (Number(n) + 1)).replace(/\blines (\d+)-(\d+)/, (_, a, b) => `lines ${Number(a) + 1}-${Number(b) + 1}`));
	const i = /^import /m.exec(s);
	if (i) return s.slice(0, i.index) + line + "\n" + s.slice(i.index);
	const m = /^package[^;]*;\r?\n/m.exec(s);
	if (m) return s.slice(0, m.index + m[0].length) + "\n" + line + "\n" + s.slice(m.index + m[0].length);
	return line + "\n" + s;
}

export const hx = (f) => f.endsWith(".hx");
export const ts = (f) => /\.(ts|tsx|mts)$/.test(f);

export function done(name) {
	console.log(`${name}: ${changed} file(s) changed`);
}
