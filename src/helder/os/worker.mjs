// A program in a Web Worker (browser.mjs's option worker; the page's side
// is thread.mjs): the module run here with the imports, its first window's
// canvas the page's, transferred (OffscreenCanvas). The packages' imports
// see host.page: the calls only the page can make (its DOM: listeners,
// text fields, the accessibility mirror, history, the clipboard) are
// forwarded to the imports' page halves there, in order, once a task
// (page.forward); what the program reads at once (the pixel ratio, the
// soft keyboard, media queries, localStorage) is the page's state as it
// last told it (page.state); its events come as messages (page.on).
import { run } from './browser.mjs';

const handlers = new Map();
let calls = [], transfer = [];
const flush = () => {
	if (calls.length) postMessage({ type: 'page', calls }, transfer);
	calls = [];
	transfer = [];
};
const page = {
	state: null,
	canvas: null,
	host: null,
	on(type, f) {
		if (!handlers.has(type)) handlers.set(type, []);
		handlers.get(type).push(f);
	},
	// a call of the page half (mod's name), its arguments read from the module's memory by sig
	forward: (mod, name, sig) => (...a) => {
		const h = page.host;
		const args = a.map((x, i) => (sig[i] === 's' ? (x ? h.string(x) : null) : sig[i] === 'b' ? h.bytes(x, a[i + 1]).slice() : x));
		for (const x of args) if (x instanceof Uint8Array) transfer.push(x.buffer);
		if (!calls.length) queueMicrotask(flush);
		calls.push([mod, name, args]);
	},
};

const answer = (id, value, t) => postMessage({ type: 'answer', id, value }, t);

self.onmessage = async (e) => {
	const m = e.data, host = page.host;
	if (m.type === 'start') return start(m);
	if (m.type === 'call') {
		const v = host?.call(m.f, ...m.args);
		flush();
		return answer(m.id, v);
	}
	if (m.type === 'readPixels') return host.gfx.readPixels().then((px) => answer(m.id, px, [px.data.buffer]), (err) => answer(m.id, { error: String(err) }));
	if (m.type === 'redraw') return host?.os.redraw();
	if (m.type === 'timing') return answer(m.id, host?.options.timing ?? []);
	if (m.type === 'stop') return host?.os.stop();
	if (m.type === 'release') return host?.gfx?.release();
	for (const f of handlers.get(m.type) ?? []) f(m);
};

async function start(m) {
	page.state = m.state;
	page.canvas = m.canvas;
	const o = m.options;
	try {
		const r = await run(m.wasm, {
			...o, imports: m.imports, page,
			stdout: (line) => postMessage({ type: 'out', fd: 1, line }),
			stderr: (line) => postMessage({ type: 'out', fd: 2, line }),
			onExit: (code, stack, message) => postMessage({ type: 'exit', code, stack, message }),
			onError: (err) => postMessage({ type: 'error', message: String(err?.message ?? err) }),
		});
		flush();
		postMessage({ type: 'started', exitCode: r.exitCode, backend: r.host.gfx?.backend ?? null });
	} catch (err) {
		postMessage({ type: 'failed', message: String(err?.message ?? err), outOfMemory: !!err?.outOfMemory, stack: String(err?.stack ?? '') });
	}
}
