// bench inline: InlineBench natively on the HTML Standard (fetched into
// bin/bench/html, as html.mjs fetches it): bin/bench/inline.md.
//   node tests/bench/inline.mjs <InlineBench executable>
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';

const [exe] = process.argv.slice(2);
const RUNS = process.env.RUNS ?? '5';
const page = 'bin/bench/html/html-spec.html';
if (!fs.existsSync(page)) {
	fs.mkdirSync('bin/bench/html', {recursive: true});
	const res = await fetch('https://html.spec.whatwg.org/', {headers: {'user-agent': 'helder-bench'}});
	if (!res.ok) throw Error(`html-spec: ${res.status}`);
	fs.writeFileSync(page, Buffer.from(await res.arrayBuffer()));
}
const r = spawnSync(exe, [page, RUNS], {encoding: 'utf8'});
if (r.status !== 0) throw Error(r.stderr || r.stdout);
const o = JSON.parse(r.stdout.trim().split('\n').pop());
const table = `# helder.ui.flow's inline layout, the HTML Standard's paragraphs

${o.paragraphs} paragraphs, ${o.mb} MB of text (UTF-16 units), Inter 16px; ms per MB, the least of ${RUNS} runs

| | ms/MB |
| --- | ---: |
| InlineContent + InlineLayout at 700px, word cache empty | ${o.inlineCold} |
| the same, word cache full | ${o.inlineWarm} |
| InlineLayout again at 500px (no shaping) | ${o.inlineRelayout500} |
| TextLayout at 700px | ${o.textLayout700} |
| TextLayout.wrap at 500px | ${o.textLayoutWrap500} |

Lines at 700px: ${o.lines700}; TextLayout's at 500px: ${o.textLayoutLines500}.
`;
fs.mkdirSync('bin/bench', {recursive: true});
fs.writeFileSync('bin/bench/inline.md', table);
console.log(table);
