// A TypeScript build writes helder's declaration files again when its stamp is
// stale (helder.typescript.Generator): on a copy of src (HELDER_SRC) and a cache
// of its own (HELDER_CACHE), a program built after an edit of a Haxe comment
// the declarations print sees it in helder/view's index.d.ts; a build with
// nothing changed writes nothing; a copy under node_modules is never written;
// one linked into node_modules (apps/tables') is.
//
//   node tests/typescript/stamp.mjs
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const built = spawnSync(process.execPath, ['src/helder/compiler/build.mjs', '--quiet'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']});
if (built.status !== 0) process.exit(1);
const compiler = built.stdout.trim();
const work = path.resolve(`bin/typescript/stamp-${process.pid}`);
fs.rmSync(work, {recursive: true, force: true});
fs.mkdirSync(work, {recursive: true});
const cache = `${work}/cache`, main = `${work}/main.ts`;
fs.writeFileSync(main, 'console.log("hello")\n');
fs.cpSync('src', `${work}/repo/src`, {recursive: true});

const doc = 'src/helder/view/TypeScript.hx', dts = 'src/helder/view/index.d.ts';
function edit(src, from, to) {
	const f = `${src}/${doc.slice(4)}`;
	fs.writeFileSync(f, fs.readFileSync(f, 'utf8').replace(from, to));
}
function build(src) {
	const r = spawnSync(compiler, [main, '-o', `${work}/main`], {encoding: 'utf8', env: {...process.env, HELDER_SRC: src, HELDER_CACHE: cache}});
	assert.equal(r.status, 0, `build with ${src}\n${r.stdout}\n${r.stderr}`);
}
const stamps = () => fs.existsSync(`${cache}/declarations`) ? fs.readdirSync(`${cache}/declarations`) : [];
const text = src => fs.readFileSync(`${src}/${dts.slice(4)}`, 'utf8');
const mtime = src => fs.statSync(`${src}/${dts.slice(4)}`).mtimeMs;

try {
	const src = `${work}/repo/src`;
	// (no stamp: written, the same files)
	build(src);
	assert.equal(stamps().length, 1, 'a stamp written');
	assert.equal(text(src), fs.readFileSync(dts, 'utf8'), 'the same declarations as the repo\'s');
	// (stale: a comment the declarations print, edited)
	edit(src, 'signals,\n// computations', 'signals (edited),\n// computations');
	build(src);
	assert.match(text(src), /signals \(edited\),/, 'written again after the edit');
	// (fresh: nothing written)
	const before = mtime(src), stamp = fs.readFileSync(`${cache}/declarations/${stamps()[0]}`, 'utf8');
	build(src);
	assert.equal(mtime(src), before, 'not written when fresh');
	assert.equal(fs.readFileSync(`${cache}/declarations/${stamps()[0]}`, 'utf8'), stamp, 'the stamp unchanged');
	// (linked into a package's node_modules, its real path the copy's: written)
	fs.mkdirSync(`${work}/app/node_modules`, {recursive: true});
	fs.symlinkSync(`${work}/repo`, `${work}/app/node_modules/helder`, 'dir');
	edit(src, 'signals (edited),', 'signals (linked),');
	build(`${work}/app/node_modules/helder/src`);
	assert.match(text(src), /signals \(linked\),/, 'written through a link');
	fs.rmSync(`${work}/app/node_modules/helder`);
	// (installed: under node_modules, never written)
	fs.mkdirSync(`${work}/pkg/node_modules`, {recursive: true});
	fs.renameSync(`${work}/repo`, `${work}/pkg/node_modules/helder`);
	const installed = `${work}/pkg/node_modules/helder/src`;
	edit(installed, 'signals (linked),', 'signals (installed),');
	const count = stamps().length, at = mtime(installed);
	build(installed);
	assert.equal(mtime(installed), at, 'not written under node_modules');
	assert.doesNotMatch(text(installed), /installed/, 'not written under node_modules');
	assert.equal(stamps().length, count, 'no stamp for a package installed');
	console.log('PASS declarations (stale: written again; fresh: untouched; installed: skipped; linked: written)');
} finally {
	fs.rmSync(work, {recursive: true, force: true});
}
