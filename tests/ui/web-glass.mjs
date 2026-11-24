// Liquid Glass in a browser (bun run test ui-web): WebGlass.wasm in headless
// Chromium on WebGPU, then on WebGL2 (forced), its frame against the
// stripes quarter of glass.png (GlassTest's golden, the CPU's), within
// GlassTest's tolerance: the backdrop captured, blurred and lensed by the
// glass's shaders as WGSL and GLSL ES.
//   node tests/ui/web-glass.mjs <WebGlass.wasm>
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
const fonts = process.env.DEJAVU_DIR ?? '/usr/share/fonts/truetype/dejavu';
const CHROMIUM_ARGS = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const files = {
	'/glass.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../src/helder/gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../src/helder/text/imports.mjs'),
	'/ui/imports.mjs': path.join(here, '../../src/helder/ui/imports.mjs'),
	'/compare.mjs': path.join(here, '../gfx/compare.mjs'),
	'/glass.png': path.join(here, 'glass.png'),
	'/DejaVuSans.ttf': path.join(fonts, 'DejaVuSans.ttf'),
	'/DejaVuSans-Bold.ttf': path.join(fonts, 'DejaVuSans-Bold.ttf'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf' };
// (GlassTest's: TOLERANCE, MAX_FAR, MEAN)
const page = `<!doctype html><title>Glass</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 300px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
import { decode } from './compare.mjs';
window.log = [];
window.start = async (gfx) => {
	window.r = run('glass.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx,
		fonts: ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	window.result = await window.r;
	return window.result.host.gfx.backend;
};
window.check = async () => {
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const px = await pixels, g = await decode('glass.png');
	let far = 0, sum = 0, max = 0;
	for (let y = 0; y < 300; y++)
		for (let x = 0; x < 400; x++) {
			const a = 4 * (y * 400 + x), b = 4 * (y * g.width + x);
			let d = 0;
			for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(px.data[a + k] - g.data[b + k]));
			sum += d;
			if (d > 6) far++;
			max = Math.max(max, d);
		}
	const mean = sum / 120000, ok = px.width === 400 && far <= 0.02 * 120000 && mean < 1;
	return { ok, text: (ok ? 'ok' : 'FAIL') + ' (' + far + ' pixels more than 6 apart, at most ' + max + ', mean ' + mean.toFixed(2) + ')' };
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
const browser = await pw.chromium.launch({ args: CHROMIUM_ARGS });
let failed = 0;
for (const gfx of ['webgpu', 'webgl2']) {
	const p = await browser.newPage({ viewport: { width: 400, height: 300 }, deviceScaleFactor: 1 });
	await p.goto(url);
	const backend = await p.evaluate((g) => window.start(g), gfx);
	// (its first frames: the glass drawn once the fonts are in)
	await p.waitForTimeout(1500);
	const r = await p.evaluate(() => window.check());
	console.log(`web-glass.mjs: ${backend}: ${r.text}`);
	if (!r.ok) {
		failed++;
		console.log((await p.evaluate(() => window.log)).join('\n'));
	}
	await p.close();
}
await browser.close();
server.close();
process.exit(failed === 0 ? 0 : 1);
