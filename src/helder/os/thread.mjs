// The page's side of a program in a Web Worker (browser.mjs's run with the
// option worker: true, or 'auto' where it fits; the worker's side is
// worker.mjs). The first window's canvas (run's option canvas, else one
// made to fill the page) gives its control to the worker
// (transferControlToOffscreen), where the program draws on it; the page
// keeps the canvas's element and the imports' page halves (os, ui and
// text's `page` export: the same imports given a host of the page's), which
// listen to it and post its input to the worker, make the calls the
// program forwards (the DOM's, in order), and tell it what it reads at once
// as that changes. A callback the page half calls (host.call) is the
// program's, answered by a promise.
//
// run's result is {host, exitCode} once main returned in the worker, its
// host a stand-in: host.worker, host.exitCode; host.os.redraw(),
// host.os.stop(); host.gfx.backend, host.gfx.readPixels() (a promise of
// {width, height, data}, as on the page), host.gfx.release();
// host.dispose() ends the worker. run's options stdout, stderr, onExit and
// onError are called on the page; the others go to the worker, so they are
// what a structured clone keeps (functions are left out).
//
// What fits (fits, for 'auto'): a browser with module workers and
// OffscreenCanvas, WebGL2 in one; imports given as URLs; a module that imports nothing
// only the page has (PAGE_ONLY: audio's AudioContext, helder.web's DOM,
// helder.media's <video> element, helder.canvas's Canvas 2D: Chromium's
// OffscreenCanvas clips without antialiasing); no option that is the
// page's own (audioContext, track, gpu). One window: a second one gets no
// canvas.
const PAGE_ONLY = new Set(['hxmc_os.audio_open', 'hxmc_web', 'helder_media.element', 'hxmc_canvas', 'helder_preview']);

// the module compiled (a URL fetched, a Response streamed, bytes; a
// promise of one awaited), so that its imports can be read and it posted
export async function module(wasm) {
	wasm = await wasm;
	if (wasm instanceof WebAssembly.Module) return wasm;
	if (typeof wasm === 'string') return WebAssembly.compileStreaming(fetch(new URL(wasm, document.baseURI)));
	if (wasm instanceof Response) return WebAssembly.compileStreaming(wasm);
	return WebAssembly.compile(wasm);
}

// (Safari before 17: no WebGL in an OffscreenCanvas; asked once)
let gl = null;
function offscreenGL() {
	if (gl !== null) return gl;
	const g = new OffscreenCanvas(1, 1).getContext('webgl2');
	g?.getExtension('WEBGL_lose_context')?.loseContext();
	return (gl = !!g);
}

export function fits(m, options) {
	if (typeof Worker !== 'function' || typeof OffscreenCanvas !== 'function' || !HTMLCanvasElement.prototype.transferControlToOffscreen || !offscreenGL()) return false;
	if ((options.imports ?? []).some((i) => typeof i !== 'string')) return false;
	if (options.audioContext || options.track || options.gpu) return false;
	return !WebAssembly.Module.imports(m).some((i) => PAGE_ONLY.has(i.module) || PAGE_ONLY.has(i.module + '.' + i.name));
}

export async function run(m, options) {
	const url = (u) => new URL(u, document.baseURI).href;
	const imports = (options.imports ?? []).map(url);
	const worker = new Worker(new URL('worker.mjs', import.meta.url), { type: 'module' });
	const asked = new Map();
	let ids = 0;
	const ask = (msg) => new Promise((ok) => {
		const id = ++ids;
		asked.set(id, ok);
		worker.postMessage({ ...msg, id });
	});
	// the page halves' host: strings and bytes as they came, callbacks the worker's
	const objects = new Map();
	let next = 1 << 24;
	const host = {
		options: { ...options }, disposed: false, exitCode: null,
		program: { post: (msg) => worker.postMessage(msg) },
		string: (s) => s,
		bytes: (b) => b,
		call: (f, ...args) => ask({ type: 'call', f, args }),
		onDispose() {},
		keep() {},
		handles: {
			add(o) {
				objects.set(next, o);
				return next++;
			},
			set: (h, o) => objects.set(h, o),
			get: (h) => objects.get(h),
			remove: (h) => objects.delete(h),
		},
	};
	const halves = {};
	for (const u of imports) {
		const pkg = await import(u);
		if (pkg.page) Object.assign(halves, await pkg.page(host));
	}
	if (!host.os?.transfer) throw new Error('helder.os: no page half (os/imports.mjs) for the program in a worker');
	const { canvas, state } = host.os.transfer();
	// (what a structured clone keeps of the options, the files' URLs the page's)
	const sent = { base: document.baseURI };
	for (const [k, v] of Object.entries(options))
		if (typeof v !== 'function' && !['imports', 'canvas', 'worker', 'stdout', 'stderr'].includes(k)) sent[k] = v;
	if (sent.assets) sent.assets = url(sent.assets);
	if (sent.files) sent.files = Object.fromEntries(Object.entries(sent.files).map(([k, v]) => [k, url(v)]));
	if (sent.fonts) sent.fonts = sent.fonts.map((f) => (typeof f === 'string' ? url(f) : f));
	const proxy = {
		worker, exitCode: null, disposed: false, options,
		os: {
			canvases: [],
			redraw: () => worker.postMessage({ type: 'redraw' }),
			stop() {
				host.os.stop();
				worker.postMessage({ type: 'stop' });
			},
		},
		gfx: {
			backend: null,
			readPixels: () => ask({ type: 'readPixels' }).then((px) => (px.error ? Promise.reject(new Error(px.error)) : px)),
			release: () => worker.postMessage({ type: 'release' }),
		},
		// (run's option timing: the frames' times so far)
		timing: () => ask({ type: 'timing' }),
		dispose() {
			if (proxy.disposed) return;
			proxy.disposed = host.disposed = true;
			host.os.stop();
			worker.terminate();
		},
	};
	const out = { 1: options.stdout ?? ((s) => console.log(s)), 2: options.stderr ?? ((s) => console.error(s)) };
	return new Promise((resolve, reject) => {
		worker.onerror = (e) => {
			e.preventDefault?.();
			const err = new Error(e.message || 'helder.os: the worker failed');
			if (options.onError) options.onError(err);
			else reject(err);
		};
		worker.onmessage = (e) => {
			const msg = e.data;
			if (msg.type === 'page') {
				for (const [mod, name, args] of msg.calls) halves[mod][name](...args);
			} else if (msg.type === 'answer') {
				asked.get(msg.id)?.(msg.value);
				asked.delete(msg.id);
			} else if (msg.type === 'out') out[msg.fd](msg.line);
			else if (msg.type === 'exit') {
				proxy.exitCode = msg.code;
				options.onExit?.(msg.code, msg.stack, msg.message);
			} else if (msg.type === 'error') {
				if (options.onError) options.onError(new Error(msg.message));
				else console.error('helder.os:', msg.message);
			} else if (msg.type === 'started') {
				proxy.gfx.backend = msg.backend;
				proxy.exitCode ??= msg.exitCode || null;
				resolve({ host: proxy, instance: null, exitCode: msg.exitCode });
			} else if (msg.type === 'failed') {
				const err = new Error(msg.message);
				err.outOfMemory = msg.outOfMemory;
				reject(err);
			}
		};
		worker.postMessage({ type: 'start', wasm: m, imports, options: sent, canvas, state }, [canvas]);
	});
}
