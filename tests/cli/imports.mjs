// A browser build's wasm imports only WASI and helder's browser modules
// (the hxmc_* objects src/helder/**/imports.mjs define): a native system's
// library there (libEGL, libobjc, ...) is another platform's code reached
// (#83). The cli lane: node tests/cli/imports.mjs bin/web/Counter.wasm
import fs from 'node:fs';
import path from 'node:path';

const own = new Set(['wasi_snapshot_preview1']);
for (const f of fs.readdirSync('src/helder', {recursive: true}))
	if (path.basename(f) === 'imports.mjs')
		for (const m of fs.readFileSync(path.join('src/helder', f), 'utf8').matchAll(/\b(hxmc_\w+) =/g)) own.add(m[1]);
let bad = 0;
for (const file of process.argv.slice(2)) {
	const modules = new Set(WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync(file))).map(i => i.module));
	for (const m of modules) if (!own.has(m)) {
		console.error(`${file}: imports ${m}`);
		bad++;
	}
}
process.exit(bad ? 1 : 0);
