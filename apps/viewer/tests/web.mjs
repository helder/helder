// The viewer's web build (viewer.helder.run) in headless Chromium (bun run
// test ui-web): its page served as helder build --target web wrote it, the
// browser at Samples (the page's title, the count its accessibility mirror
// says: as many as the samples beside the page),
// then the PDF opened (type-ahead, Enter) and its first page shown, the
// Markdown sample opened and its text there; a sound and a video opened,
// at most one playing, the one shown, none once left (the next file,
// closed: no <audio> or <video> playing, no audio output given sound); files
// dropped on the page (a folder "Dropped" of them, a photo opened); Open
// folder on a tree of handles of the page's own (showDirectoryPicker's
// stand-in), its subfolder entered; no error on the page or in the console.
// Screenshots: <out>/web-samples.png, web-pdf.png, web-markdown.png, web-folder.png.
//   node tests/web.mjs <bin/web> <out dir>
import { createServer } from 'node:http';
import { readFile, readdir, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const [dir, out] = process.argv.slice(2);
const types = { '.html': 'text/html', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
	'.ttf': 'font/ttf', '.jpg': 'image/jpeg', '.pdf': 'application/pdf', '.mp4': 'video/mp4', '.m4a': 'audio/mp4', '.md': 'text/markdown' };
const server = createServer(async (req, res) => {
	let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	if (p === '/') p = '/viewer.html';
	try {
		const b = await readFile(path.join(dir, p));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const port = server.address().port;
const fail = (m) => { throw new Error('viewer (web): ' + m); };
const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--use-angle=swiftshader', '--enable-features=Vulkan', '--use-vulkan=swiftshader'] });
const errors = [];
try {
	await mkdir(out, { recursive: true });
	const page = await browser.newPage({ viewport: { width: 1180, height: 760 } });
	page.on('pageerror', (e) => errors.push('page: ' + e.message));
	page.on('console', (m) => { if (process.env.DEBUG) console.log(m.type(), m.text()); if (m.type() === 'error') errors.push('console: ' + m.text()); });
	// (what plays: <audio> and <video> elements playing a source, and the audio outputs
	// (AudioWorklet nodes) given sound in the last 300 ms in a running context)
	await page.addInitScript(() => {
		const nodes = [], elements = [];
		const Worklet = window.AudioWorkletNode;
		if (Worklet) window.AudioWorkletNode = class extends Worklet {
			constructor(...a) {
				super(...a);
				const n = { node: this, heard: -1e9 }, post = this.port.postMessage.bind(this.port);
				nodes.push(n);
				this.port.postMessage = (m, t) => {
					if (m instanceof Float32Array && m.some((x) => Math.abs(x) > 1e-4)) n.heard = performance.now();
					return post(m, t);
				};
			}
		};
		const create = document.createElement.bind(document);
		document.createElement = (t, ...a) => {
			const e = create(t, ...a);
			if (/^(audio|video)$/i.test(t)) elements.push(e);
			return e;
		};
		window.playing = () => ({
			elements: [...elements, ...document.querySelectorAll('audio, video')].filter((e, i, all) => all.indexOf(e) === i && !e.paused && e.src !== '').length,
			outputs: nodes.filter((n) => n.node.context.state === 'running' && performance.now() - n.heard < 300).length
		});
	});
	await page.goto(`http://localhost:${port}/`);
	await page.waitForFunction(() => document.title === 'Samples', null, { timeout: 60000 }).catch(() => fail(`not at Samples: "${'' + errors}"`));
	// (the canvas's mirror for assistive technology: the count, the files' names)
	const said = () => page.evaluate(() => document.querySelector('canvas')?.textContent ?? '');
	await page.waitForFunction(() => /\d+ items/.test(document.querySelector('canvas')?.textContent ?? ''), null, { timeout: 30000 })
		.catch(async () => fail('no count: ' + (await said()).slice(0, 400)));
	// (as many as the samples beside the page)
	const n = (await readdir(path.join(dir, 'assets/samples'))).length;
	if (!(await said()).includes(`${n} items`)) fail(`not ${n} items: ${(await said()).slice(0, 400)}`);
	// (the thumbnails: made on the workers, a few seconds on swiftshader)
	await page.waitForTimeout(4000);
	await page.screenshot({ path: path.join(out, 'web-samples.png') });
	await page.mouse.click(600, 400);
	await page.keyboard.type('About');
	await page.keyboard.press('Enter');
	await page.waitForFunction(() => /About Viewer\.pdf .*page 1 \/ 3/.test(document.title), null, { timeout: 60000 })
		.catch(async () => {
			await page.screenshot({ path: path.join(out, 'web-pdf.png') });
			fail('the PDF not shown: ' + (await page.title()));
		});
	await page.waitForTimeout(10000);
	await page.screenshot({ path: path.join(out, 'web-pdf.png') });
	const pdf = await page.title();
	await page.keyboard.press('Escape');
	// (the Markdown sample: its column, its text and its picture read from beside the page)
	await page.waitForFunction(() => document.title === 'Samples', null, { timeout: 30000 }).catch(async () => fail('not back at Samples: ' + (await page.title())));
	await page.mouse.click(600, 400);
	await page.keyboard.type('Welcome');
	await page.keyboard.press('Enter');
	await page.waitForFunction(() => /^Welcome\.md · /.test(document.title) && /This page is a Markdown file/.test(document.querySelector('canvas')?.textContent ?? ''), null,
		{ timeout: 30000 }).catch(async () => {
			await page.screenshot({ path: path.join(out, 'web-markdown.png') });
			fail('the Markdown document not shown: ' + (await page.title()) + ': ' + (await said()).slice(0, 300));
		});
	await page.waitForTimeout(3000);
	await page.screenshot({ path: path.join(out, 'web-markdown.png') });
	await page.keyboard.press('Escape');
	// (a sound and a video: at most one plays, the one shown; none once left: the next file, closed)
	const plays = async (what, most, least = 0) => {
		await page.waitForTimeout(1500);
		const p = await page.evaluate(() => window.playing());
		if (p.elements + p.outputs > most || p.elements + p.outputs < least) fail(`${what}: ${JSON.stringify(p)} playing (${await page.title()})`);
	};
	const open = async (name, title) => {
		await page.waitForFunction(() => document.title === 'Samples', null, { timeout: 30000 }).catch(async () => fail('not at Samples: ' + (await page.title())));
		await page.mouse.click(600, 400);
		await page.keyboard.type(name);
		await page.keyboard.press('Enter');
		await page.waitForFunction((t) => document.title.startsWith(t), title, { timeout: 30000 }).catch(async () => fail(`${name} not shown: ` + (await page.title())));
	};
	await open('Chimes', 'Chimes.m4a · ');
	await plays('Chimes.m4a shown', 1, 1);
	await page.keyboard.press('PageDown');
	await page.waitForFunction(() => !document.title.startsWith('Chimes.m4a'), null, { timeout: 30000 });
	await plays('the next file', 0);
	await page.keyboard.press('PageUp');
	await page.waitForFunction(() => document.title.startsWith('Chimes.m4a'), null, { timeout: 30000 });
	await plays('Chimes.m4a again', 1);
	await page.keyboard.press('Escape');
	await plays('closed', 0);
	await open('Starlings.mp4', 'Starlings.mp4 · ');
	await plays('Starlings.mp4 shown', 1);
	await page.keyboard.press('Escape');
	await plays('closed again', 0);
	// (files dropped on the page: a folder "Dropped" of them, a photo of it opened)
	await page.evaluate(async () => {
		const dt = new DataTransfer();
		dt.items.add(new File([await (await fetch('assets/samples/Planet.jpg')).blob()], 'Planet.jpg', { type: 'image/jpeg' }));
		dt.items.add(new File(['a note'], 'notes.txt', { type: 'text/plain' }));
		document.querySelector('canvas').dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true }));
	});
	await page.waitForFunction(() => document.title === 'Dropped' && /2 items/.test(document.querySelector('canvas')?.textContent ?? ''), null, { timeout: 30000 })
		.catch(async () => fail('the drop not shown: ' + (await page.title()) + ': ' + (await said()).slice(0, 300)));
	await page.mouse.click(600, 600);
	await page.keyboard.type('Planet');
	await page.keyboard.press('Enter');
	await page.waitForFunction(() => /^Planet\.jpg · 1 \/ 1 · 1440×900/.test(document.title), null, { timeout: 30000 })
		.catch(async () => fail('the dropped photo not shown: ' + (await page.title())));
	await page.keyboard.press('Escape');
	// (Open folder: the picker's folder, a tree of handles of the page's own)
	const button = '[...document.querySelectorAll("canvas [role=button]")].find((b) => b.getAttribute("aria-label") === "Open folder")';
	await page.waitForFunction(button, null, { timeout: 30000 }).catch(async () => fail('no Open folder: ' + (await page.title())));
	await page.evaluate(() => {
		const file = (name, url) => ({ kind: 'file', name, getFile: async () => new File([await (await fetch(url)).blob()], name, { lastModified: 1.7e12 }) });
		const dir = (name, kids) => ({ kind: 'directory', name, values: async function* () { yield* kids; } });
		window.showDirectoryPicker = async () =>
			dir('Trip', [file('Murmuration.jpg', 'assets/samples/Murmuration.jpg'), dir('Day 2', [file('Mandelbrot.jpg', 'assets/samples/Mandelbrot.jpg')])]);
		[...document.querySelectorAll('canvas [role=button]')].find((b) => b.getAttribute('aria-label') === 'Open folder').click();
	});
	await page.waitForFunction(() => document.title === 'Trip' && /2 items/.test(document.querySelector('canvas')?.textContent ?? ''), null, { timeout: 30000 })
		.catch(async () => fail('the folder opened not shown: ' + (await page.title()) + ': ' + (await said()).slice(0, 300)));
	await page.mouse.click(600, 600);
	await page.keyboard.type('Day');
	await page.keyboard.press('Enter');
	await page.waitForFunction(() => document.title === 'Day 2' && /1 item/.test(document.querySelector('canvas')?.textContent ?? ''), null, { timeout: 30000 })
		.catch(async () => fail('its subfolder not shown: ' + (await page.title())));
	await page.waitForTimeout(3000);
	await page.screenshot({ path: path.join(out, 'web-folder.png') });
	if (errors.length > 0) fail(errors.join('\n'));
	console.log(`viewer (web): at Samples, the PDF shown (${pdf}), the Markdown sample, a sound and a video left (none playing), a drop and a folder opened`);
} finally {
	await browser.close();
	server.close();
}
