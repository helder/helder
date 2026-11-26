// html5lib-tests (https://github.com/html5lib/html5lib-tests, MIT) and the
// tree construction tests that moved from it to web-platform-tests
// (https://github.com/web-platform-tests/wpt, html/syntax/parsing/resources,
// BSD-3-Clause), at the revisions pinned below, as this suite's fixtures:
// fixtures/tokenizer/*.test and fixtures/tree-construction/*.dat. Left out:
// xmlViolation.test (html5lib's coercion to an XML infoset) and the
// serializer tests (html5lib's serializer of token streams: unclosed
// elements, single quotes, unquoted values; not the HTML standard's
// algorithm). The manifest keeps its cases' statuses; new cases come in
// pending until the check says (BLESS=1), a #script-on case skipped (the
// parser's scripting is off).
//
//   node tests/dom/import-html5lib.mjs [html5lib-tests checkout] [wpt checkout]
//
// Without checkouts both are fetched at their revisions into bin/dom/upstream.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HTML5LIB = { url: 'https://github.com/html5lib/html5lib-tests', revision: 'c5495c539ca8a79c3c5107f5f14010bcff9a35d5' };
const WPT = { url: 'https://github.com/web-platform-tests/wpt', revision: 'bc5ea7a9006b77c12118534bf7d2953e530d811f', sparse: 'html/syntax/parsing/resources' };

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const git = (dir, ...args) => execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8' }).trim();

function checkout(given, repo, name) {
	let dir = given;
	if (!dir) {
		dir = path.join(root, 'bin/dom/upstream', name);
		if (!fs.existsSync(path.join(dir, '.git'))) {
			fs.mkdirSync(dir, { recursive: true });
			git(dir, 'init', '-q');
			git(dir, 'remote', 'add', 'origin', repo.url);
			if (repo.sparse) {
				git(dir, 'config', 'core.sparseCheckout', 'true');
				fs.writeFileSync(path.join(dir, '.git/info/sparse-checkout'), repo.sparse + '/\nLICENSE.md\n');
			}
		}
		git(dir, 'fetch', '-q', '--depth', '1', '--filter=blob:none', 'origin', repo.revision);
		git(dir, 'checkout', '-q', repo.revision);
	}
	const head = git(dir, 'rev-parse', 'HEAD');
	if (head !== repo.revision) throw new Error(`${dir}: at ${head}, not the pinned ${repo.revision}`);
	return dir;
}

const h5 = checkout(process.argv[2], HTML5LIB, 'html5lib-tests');
const wpt = checkout(process.argv[3], WPT, 'wpt');
const fixtures = path.join(here, 'fixtures');
fs.rmSync(fixtures, { recursive: true, force: true });
for (const d of ['tokenizer', 'tree-construction']) fs.mkdirSync(path.join(fixtures, d), { recursive: true });

const ids = [];
const scriptOn = new Set();
for (const f of fs.readdirSync(path.join(h5, 'tokenizer')).filter((f) => f.endsWith('.test') && f !== 'xmlViolation.test').sort()) {
	fs.copyFileSync(path.join(h5, 'tokenizer', f), path.join(fixtures, 'tokenizer', f));
	const json = JSON.parse(fs.readFileSync(path.join(h5, 'tokenizer', f), 'utf8'));
	json.tests.forEach((t, i) => {
		for (const s of t.initialStates ?? ['Data state']) ids.push(`tokenizer/${f}#${i}:${s.replace(/ state$/, '')}`);
	});
}
for (const f of fs.readdirSync(path.join(wpt, WPT.sparse)).filter((f) => f.endsWith('.dat')).sort()) {
	const text = fs.readFileSync(path.join(wpt, WPT.sparse, f), 'utf8');
	fs.writeFileSync(path.join(fixtures, 'tree-construction', f), text);
	// (a test starts at #data, or at the #description some put before it)
	let count = 0, open = false;
	for (const l of text.split('\n')) {
		if (l === '#description' || (l === '#data' && !open)) count++;
		if (l === '#description' || l === '#data') open = true;
		if (l === '#document') open = false;
		if (l === '#script-on') scriptOn.add(`tree-construction/${f}#${count - 1}`);
	}
	for (let i = 0; i < count; i++) ids.push(`tree-construction/${f}#${i}`);
}
fs.copyFileSync(path.join(h5, 'LICENSE'), path.join(here, 'HTML5LIB-LICENSE'));
fs.copyFileSync(path.join(wpt, 'LICENSE.md'), path.join(here, 'WPT-LICENSE'));

// (the manifest's statuses kept; new cases pending)
const manifestPath = path.join(here, 'manifest.json');
const old = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : { cases: [] };
const status = new Map(old.cases.map((c) => [c.id, c]));
const cases = ids.map((id) => status.get(id) ?? (scriptOn.has(id) ? { id, skip: '#script-on: the parser runs with scripting off' } : { id, pending: 'new' }));
const head = { schema: 1, html5lib_tests: HTML5LIB.revision, wpt: WPT.revision };
fs.writeFileSync(
	manifestPath,
	JSON.stringify(head, null, '\t').replace(/\n}$/, ',\n\t"cases": [\n') + cases.map((c) => '\t\t' + JSON.stringify(c)).join(',\n') + '\n\t]\n}\n'
);
console.log(`tests/dom: ${ids.length} cases (${cases.filter((c) => c.pending === 'new').length} new)`);
