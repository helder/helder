// A web build's files hold no machine's directories: no user's home
// (/Users/, /home/, C:\Users), nor the ones named (the project's, helder's)
// (helder.cli.Entry's -D hxmc.paths: a share shows no one where it was built).
//   node tests/cli/homeless.mjs <dir> [dir that must not appear...]
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

const [root, ...own] = process.argv.slice(2);
const needles = ['/Users/', '/home/', 'C:\\Users', 'C:/Users', ...own].map((s) => Buffer.from(s));
let files = 0;
const found = [];
function walk(d) {
	for (const n of readdirSync(d)) {
		const p = path.join(d, n);
		if (statSync(p).isDirectory()) walk(p);
		else {
			files++;
			const b = readFileSync(p);
			for (const x of needles) {
				const at = b.indexOf(x);
				if (at >= 0) found.push(`${p}: "${b.subarray(at, at + 100).toString('latin1').split('\0')[0]}"`);
			}
		}
	}
}
walk(root);
if (files === 0) {
	console.error(`homeless: ${root}: no files (no build there?)`);
	process.exit(1);
}
if (found.length) {
	console.error(`homeless: a machine's directory in a web build (${found.length}):\n  ${found.slice(0, 20).join('\n  ')}`);
	process.exit(1);
}
console.log(`homeless: ${root}: ${files} files, no machine's directory in them`);
