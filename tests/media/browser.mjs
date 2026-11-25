// helder.media's WebSource in headless Chromium: WebSourceCheck.wasm run by
// src/helder/os/browser.mjs with helder.async's and helder.media's
// imports, on a page served from the repository by a server that honours
// Range (206, Content-Range) and, under /whole/, one that ignores it; the
// page gives a Blob (option blobs) and writes a file into OPFS first. The
// bytes sent for the MP4 until the program asks for opened.mark, once it
// opened and sought it:
// of its mdat's payload no more than a box header's read (no full
// download), every request a Range one.
//   node tests/media/browser.mjs <module.wasm>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const pw = require('playwright');
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..');
const wasm = path.resolve(process.argv[2]);
const expected = JSON.parse(await readFile(path.join(root, 'tests/media/expected.json'), 'utf8'));
const crcs = expected['h264-aac.mp4'].packets.map((p) => p[7]).sort().join(',');
const page = `<!doctype html><script type="module">
import { run } from '/src/helder/os/browser.mjs';
const clip = await (await fetch('/tests/media/vp9-opus.webm')).blob();
const dir = await (await navigator.storage.getDirectory()).getDirectoryHandle('media', { create: true });
const w = await (await dir.getFileHandle('clip.webm', { create: true })).createWritable();
await w.write(clip);
await w.close();
const { host } = await run('/module.wasm', { imports: ['/src/helder/async/imports.mjs', '/src/helder/media/imports.mjs'], blobs: { clip },
	env: { CRCS: ${JSON.stringify(crcs)} }, stdout: (l) => console.log(l), stderr: (l) => console.log(l) });
const wait = () => host.exitCode === null ? setTimeout(wait, 10) : console.log('exit ' + host.exitCode);
wait();
</script>`;
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm' };
let sent = 0, ranged = true, opened = -1, inMedia = 0, media = [0, 0];
const mp4 = '/tests/media/h264-aac.mp4';
const server = createServer(async (req, res) => {
	let url = new URL(req.url, 'http://x').pathname;
	const whole = url.startsWith('/whole/');
	if (whole) url = url.slice(6);
	try {
		if (url === '/') return res.writeHead(200, { 'content-type': 'text/html' }).end(page);
		if (url === '/opened.mark') {
			opened = sent;
			return res.writeHead(200).end();
		}
		const body = await readFile(url === '/module.wasm' ? wasm : path.join(root, url));
		const type = types[path.extname(url)] ?? 'application/octet-stream';
		const range = /^bytes=(\d+)-(\d+)?$/.exec(req.headers.range ?? '');
		if (url === mp4 && opened < 0) {
			if (!range) ranged = false;
		}
		if (!range || whole) return res.writeHead(200, { 'content-type': type }).end(body);
		const start = Number(range[1]), end = Math.min(range[2] ? Number(range[2]) : body.length - 1, body.length - 1);
		if (start >= body.length) return res.writeHead(416, { 'content-range': `bytes */${body.length}` }).end();
		if (url === mp4 && opened < 0) {
			sent += end - start + 1;
			inMedia += Math.max(0, Math.min(end + 1, media[1]) - Math.max(start, media[0]));
		}
		res.writeHead(206, { 'content-type': type, 'content-range': `bytes ${start}-${end}/${body.length}` }).end(body.subarray(start, end + 1));
	} catch {
		res.writeHead(404).end();
	}
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const file = await readFile(path.join(root, mp4)), size = file.length;
for (let at = 0; at + 8 <= size; ) {
	const n = file.readUInt32BE(at);
	if (file.toString('latin1', at + 4, at + 8) === 'mdat') media = [at + 8, at + n];
	if (n < 8) break;
	at += n;
}
const browser = await pw.chromium.launch();
const p = await browser.newPage();
const out = [];
const done = new Promise((resolve) => p.on('console', (m) => {
	out.push(m.text());
	if (m.text().startsWith('exit ')) resolve(Number(m.text().slice(5)));
}));
p.on('pageerror', (e) => out.push('page error: ' + e.message));
await p.goto(`http://127.0.0.1:${server.address().port}/`);
let code = await Promise.race([done, new Promise((r) => setTimeout(() => r(-1), 20000))]);
console.log(out.join('\n'));
console.log(`the MP4 opened and sought: ${opened} of its ${size} bytes sent, ${inMedia} of its mdat's ${media[1] - media[0]}, ${ranged ? 'all' : 'not all'} by Range`);
if (!(opened > 0 && inMedia <= 8 && ranged)) code = 1;
await browser.close();
server.close();
process.exit(code === 0 ? 0 : 1);
