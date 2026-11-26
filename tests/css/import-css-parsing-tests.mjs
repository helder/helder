// css-parsing-tests (https://github.com/SimonSapin/css-parsing-tests, CC0)
// at its pinned revision as fixtures/css-parsing-tests: its JSON files
// and license copied as they are. The manifest keeps its cases'
// statuses; a case it has not seen comes in pending until the check says
// (BLESS=1).
//
//   node tests/css/import-css-parsing-tests.mjs [checkout]
//
// (no checkout: cloned into bin/css/css-parsing-tests at REVISION)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REVISION = '203ce36bffd617db7f118c551e32794561fb273d';
const REPOSITORY = 'https://github.com/SimonSapin/css-parsing-tests.git';

const here = path.dirname(fileURLToPath(import.meta.url));
let checkout = process.argv[2];
if (!checkout) {
	checkout = path.join(here, '../../bin/css/css-parsing-tests');
	if (!fs.existsSync(checkout)) execFileSync('git', ['clone', '-q', REPOSITORY, checkout], { stdio: 'inherit' });
	execFileSync('git', ['-C', checkout, 'checkout', '-q', REVISION], { stdio: 'inherit' });
}
const revision = execFileSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (revision !== REVISION) throw new Error(`${checkout} is at ${revision}, not ${REVISION}`);

const manifestPath = path.join(here, 'manifest.json');
const old = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : { files: {}, cases: [] };
const kept = new Map(old.cases.map((c) => [`${c.file}#${c.index}`, c]));

// (a file the manifest skips is not copied)
const out = path.join(here, 'fixtures/css-parsing-tests');
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const files = fs.readdirSync(checkout).filter((f) => f.endsWith('.json') && !old.files?.[f]?.skip).sort();
for (const f of [...files, 'LICENSE']) fs.copyFileSync(path.join(checkout, f), path.join(out, f));

const cases = [];
for (const f of files) {
	const pairs = JSON.parse(fs.readFileSync(path.join(out, f), 'utf8'));
	for (let i = 0; i < pairs.length; i += 2) {
		const input = typeof pairs[i] === 'string' ? pairs[i] : pairs[i].css_bytes;
		const id = `${f}#${i / 2}`;
		const c = kept.get(id);
		cases.push(c && c.input === input ? c : { file: f, index: i / 2, input, pending: 'new' });
	}
}
const manifest = { schema: 1, repository: REPOSITORY, revision, license: 'CC0-1.0', files: old.files ?? {}, cases: [] };
// (a case a line)
const head = JSON.stringify(manifest, null, '\t').replace(/\[\]\n\}$/, '[\n');
fs.writeFileSync(manifestPath, head + cases.map((c) => '\t\t' + JSON.stringify(c)).join(',\n') + '\n\t]\n}\n');
console.log(`${cases.length} cases from css-parsing-tests ${revision}`);
