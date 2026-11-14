// The compute tier in headless Chromium (ComputeTest.hx as wasm32-wasi):
// on WebGPU its stages run and the harness checks what the program says it
// expects, as WebGPU reads back asynchronously only: each buffer
// (host.gfx.readBuffer: its bytes' FNV-1a) and the frame's pixels
// (host.gfx.readPixels, within 2 of each channel); on WebGL2 (forced:
// browser.mjs's option gfx: 'webgl2') the device has no compute,
// createComputePipeline and a storage buffer throw. Chromium renders with
// WebGPU on SwiftShader and WebGL2 on ANGLE's SwiftShader (no GPU needed).
//   node tests/gfx/compute-web.mjs <ComputeTest.wasm>
// (Playwright from npm, with Chromium: npx playwright install chromium)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm] = process.argv.slice(2);
if (!wasm) {
	console.error('usage: node compute-web.mjs <ComputeTest.wasm>');
	process.exit(2);
}
// (as web.mjs: WebGPU on SwiftShader's Vulkan)
const CHROMIUM_ARGS = process.env.CHROMIUM_ARGS ? process.env.CHROMIUM_ARGS.split(' ') : ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const files = {
	'/test.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../src/helder/gfx/imports.mjs'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const page = `<!doctype html><title>ComputeTest</title>
<script type="module">
import { run } from './os/browser.mjs';
const log = [];
window.log = log;
const fnv = (data) => {
	let h = 0x811c9dc5;
	for (const b of data) h = Math.imul(h ^ b, 0x01000193);
	return (h >>> 0).toString(16).toUpperCase().padStart(8, '0');
};
window.start = async (gfx) => {
	const r = await run('test.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs'], gfx, args: [], stdout: (s) => log.push(s), stderr: (s) => log.push('stderr: ' + s) });
	log.push('exit ' + r.exitCode);
	if (r.host.gfx.backend !== gfx) return { ok: false, text: gfx + ': on ' + r.host.gfx.backend };
	const wrong = [];
	let checked = 0;
	if (gfx === 'webgpu') {
		for (const l of log) {
			const m = /^ComputeTest: read ([a-z]+) ([0-9]+) ([0-9]+) ([0-9A-F]+)$/.exec(l);
			if (!m) continue;
			const data = await r.host.gfx.readBuffer(+m[2], 0, +m[3]);
			checked++;
			if (fnv(data) !== m[4]) {
				const ints = Array.from(new Int32Array(data.buffer, 0, Math.min(8, data.length >> 2)));
				wrong.push(m[1] + ': FNV ' + fnv(data) + ', not ' + m[4] + ' (' + ints.join(', ') + ', ...)');
			}
		}
		const px = await r.host.gfx.readPixels();
		for (const l of log) {
			const m = /^ComputeTest: pixel ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)$/.exec(l);
			if (!m) continue;
			checked++;
			const o = 4 * (+m[2] * px.width + +m[1]), got = [px.data[o], px.data[o + 1], px.data[o + 2]];
			if ([3, 4, 5].some((k, i) => Math.abs(got[i] - +m[k]) > 2)) wrong.push('pixel (' + m[1] + ', ' + m[2] + '): ' + got.join(' ') + ', not ' + m.slice(3).join(' '));
		}
	}
	return { ok: wrong.length === 0, text: gfx + ': ' + checked + ' checks' + (wrong.length ? ', ' + wrong.slice(0, 6).join('; ') : ''), checked };
};
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' ? 'text/html' : types[path.extname(p)] });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;
const browser = await pw.chromium.launch({ args: CHROMIUM_ARGS, executablePath: process.env.CHROMIUM_PATH || undefined });
console.log(`compute-web.mjs: chromium ${browser.version()}`);
let failed = 0;
for (const gfx of ['webgpu', 'webgl2']) {
	const p = await browser.newPage();
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
	await p.goto(url);
	const r = await p.evaluate((g) => window.start(g), gfx).catch((e) => ({ ok: false, text: e.message.split('\n')[0] }));
	const log = await p.evaluate(() => window.log);
	const expect = gfx === 'webgpu' ? ['ComputeTest: compute on WebGPU', 'ComputeTest: ok'] : ['ComputeTest: no compute (WebGL2)'];
	const missing = expect.filter((e) => !log.includes(e));
	// (WebGPU: the buffers and the pixels, 2 + 133)
	if (gfx === 'webgpu' && !(r.checked > 100)) missing.push('the checks (' + r.checked + ')');
	const ok = r.ok && missing.length === 0 && errors.length === 0 && log.includes('exit 0') && !log.some((l) => l.includes('FAIL'));
	if (!ok) failed++;
	console.log(`compute-web.mjs: ${r.text}${ok ? '' : ' FAILED'}`);
	for (const l of log) if (!/^ComputeTest: (pixel|read) /.test(l)) console.log('  ' + l);
	for (const m of missing) console.log('  missing: ' + m);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
