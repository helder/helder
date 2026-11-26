// helder.media's decoding in browsers: MediaWebCheck.wasm run by
// src/helder/os/browser.mjs on a page served from the repository by a
// server that honours Range, in Chromium (on WebGPU where it has it, and
// on WebGL2), Firefox and WebKit, each where Playwright has it installed
// (else a note). A clip by URL: every request of a video a Range one, and
// of its bytes less than the whole file sent before its first frame showed
// (the source not downloaded whole).
//   node tests/media/web/browser.mjs <module.wasm> [chromium firefox webkit]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
// (the checkout's playwright, else node's global one: npm i -g playwright)
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const wasm = path.resolve(process.argv[2]);
const browsers = process.argv.length > 3 ? process.argv.slice(3) : ['chromium', 'firefox', 'webkit'];
const page = (gfx, name, mode = '', copied = false) => `<!doctype html><body><script type="module">
import { run } from '/src/helder/os/browser.mjs';
const { host } = await run('/module.wasm', { imports: ['/src/helder/os/imports.mjs', '/src/helder/gfx/imports.mjs', '/src/helder/async/imports.mjs', '/src/helder/media/imports.mjs',
	'/tests/media/web/check.mjs'], env: { BROWSER: '${name}', MODE: '${mode}' }, ${gfx ? `gfx: '${gfx}', ` : ''}${copied ? 'videoCopied: true, ' : ''}stdout: (l) => console.log(l), stderr: (l) => console.log(l) });
const wait = () => host.exitCode === null ? setTimeout(wait, 10) : console.log('exit ' + host.exitCode);
wait();
</script>`;
// (WebGPU as the gfx lanes have it, on SwiftShader's Vulkan where the machine has no GPU: CI's)
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
let counting = false, sent = new Map(), whole = 0, current = '';
const server = createServer(async (req, res) => {
	const url = new URL(req.url, 'http://x').pathname;
	try {
		if (url === '/' || url === '/webgl2' || url === '/autoplay' || url === '/copied')
			return res.writeHead(200, { 'content-type': 'text/html' }).end(page(url === '/webgl2' ? 'webgl2' : null, current, url === '/autoplay' ? 'autoplay' : '', url === '/copied'));
		if (url.endsWith('.mark')) {
			counting = url === '/begin.mark';
			return res.writeHead(200).end();
		}
		const body = await readFile(url === '/module.wasm' ? wasm : path.join(root, url));
		const head = { 'content-type': types[path.extname(url)] ?? 'application/octet-stream', 'cache-control': 'no-store', 'accept-ranges': 'bytes' };
		const range = /^bytes=(\d+)-(\d+)?$/.exec(req.headers.range ?? '');
		if (url.startsWith('/tests/media/') && /\.(mp4|webm|mov|mkv)$/.test(url) && !range) whole++;
		if (!range) return res.writeHead(200, head).end(body);
		const start = Number(range[1]), end = Math.min(range[2] ? Number(range[2]) : body.length - 1, body.length - 1);
		if (start >= body.length) return res.writeHead(416, { 'content-range': `bytes */${body.length}` }).end();
		// (the bytes of it sent, each counted once)
		if (counting) {
			const s = sent.get(url) ?? { bytes: new Uint8Array(body.length), size: body.length };
			s.bytes.fill(1, start, end + 1);
			sent.set(url, s);
		}
		res.writeHead(206, { ...head, 'content-range': `bytes ${start}-${end}/${body.length}` }).end(body.subarray(start, end + 1));
	} catch {
		res.writeHead(404).end();
	}
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
let failed = 0;
// (Chromium also on WebGL2, once with its autoplay policy: no gesture yet,
// and once with every video frame copied by the CPU, as WebGPU's are where
// it cannot import them (helder.gfx's videoCopied): their RGB as ffmpeg's)
for (const [name, route] of browsers.flatMap((b) => (b === 'chromium' ? [[b, '/'], [b, '/webgl2'], [b, '/autoplay'], [b, '/copied']] : [[b, '/']]))) {
	const what = `${name}${route === '/' ? '' : route === '/webgl2' ? ' (WebGL2)' : route === '/copied' ? ' (video frames copied by the CPU)' : ' (autoplay, no gesture)'}`, autoplay = route === '/autoplay';
	let browser;
	try {
		browser = await pw[name].launch({ args: name === 'chromium' ? [...(autoplay ? [] : ['--autoplay-policy=no-user-gesture-required']), ...CHROMIUM_ARGS] : [],
			firefoxUserPrefs: name === 'firefox' ? { 'media.autoplay.default': 0, 'media.autoplay.block-webaudio': false } : undefined });
	} catch (e) {
		console.log(`${what}: skipped: not installed (npx playwright install ${name})`);
		continue;
	}
	sent = new Map();
	whole = 0;
	current = name;
	const p = await browser.newPage();
	const out = [];
	const done = new Promise((resolve) => p.on('console', (m) => {
		out.push(m.text());
		if (m.text().startsWith('exit ')) resolve(Number(m.text().slice(5)));
	}));
	p.on('pageerror', (e) => out.push('page error: ' + e.message));
	const t0 = Date.now();
	await p.goto(`http://127.0.0.1:${server.address().port}${route}`);
	// (a gesture: sound allowed, as a user's click would; WebKit has no flag for it)
	if (!autoplay) await p.mouse.click(1, 1);
	const code = await Promise.race([done, new Promise((r) => setTimeout(() => r(-1), 60000))]);
	console.log(`${what} ${browser.version()}, ${((Date.now() - t0) / 1000).toFixed(1)} s:\n  ` + out.join('\n  '));
	// (none counted: the test skipped it)
	const [url, s] = [...sent][0] ?? ['', { bytes: [], size: 1 }], n = s.bytes.reduce((a, b) => a + b, 0), ranged = whole === 0 && n < s.size;
	if (!autoplay) console.log(`  ${url || 'no clip'} by URL: ${n} of its ${s.size} bytes sent until its first frame showed; ${whole === 0 ? 'every request of a video by Range' : whole + ' requests without Range'}`);
	if (code !== 0 || !ranged) failed++;
	await browser.close();
}
server.close();
process.exit(failed ? 1 : 0);
