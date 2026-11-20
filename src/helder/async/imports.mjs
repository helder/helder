// The JavaScript side of helder.async in the browser: the imports of the
// module "helder_async" (src/helder/async/Web.hx), for browser.mjs's option
// imports. The page's event loop turns the module's Loop: one timer at a
// time, at the earliest time the module asked for (wake, or what a turn
// returned); a turn wanted at once comes as a task of its own
// (MessageChannel, setImmediate under node), not a microtask, so that the
// page renders and handles its events between turns. Fetches end in a turn.
export default function (host) {
	let turn = 0, timer = null, due = Infinity;
	const soon = typeof setImmediate === 'function' ? setImmediate : (() => {
		const ch = new MessageChannel(), fs = [];
		ch.port1.onmessage = () => fs.shift()?.();
		return (f) => { fs.push(f); ch.port2.postMessage(0); };
	})();
	const clear = () => {
		if (timer !== null && timer !== true) clearTimeout(timer);
		timer = null;
		due = Infinity;
	};
	const run = () => {
		clear();
		if (!turn) return;
		const next = host.call(turn);
		if (next !== undefined && next >= 0) wake(next);
	};
	const wake = (seconds) => {
		const at = performance.now() + seconds * 1000;
		if (at >= due) return;
		clear();
		due = at;
		if (seconds <= 0) {
			timer = true;
			soon(() => timer === true && run());
		} else timer = setTimeout(run, seconds * 1000);
	};
	// (other modules' events that need a turn: helder_image's decodes)
	host.wake = wake;
	return {
		helder_async: {
			start(f) {
				turn = f;
				wake(0);
			},
			wake,
			fetch_start(p) {
				// (its body read as it arrives: loaded, and total where the
				// response says (its Content-Length, unless it is encoded:
				// that counts the encoded bytes); a turn at most every 50 ms
				// while it does, for progress)
				const f = { state: 0, body: null, loaded: 0, total: 0, abort: new AbortController() };
				const base = typeof document !== 'undefined' ? document.baseURI : host.options.base;
				let told = 0;
				fetch(new URL(host.string(p), base), { signal: f.abort.signal }).then(async (r) => {
					if (!r.ok) throw r.status;
					const length = Number(r.headers.get('content-length'));
					if (length > 0 && !r.headers.get('content-encoding')) f.total = length;
					if (!r.body || !r.body.getReader) return new Uint8Array(await r.arrayBuffer());
					const reader = r.body.getReader(), chunks = [];
					for (;;) {
						const { done, value } = await reader.read();
						if (done) break;
						chunks.push(value);
						f.loaded += value.length;
						const now = performance.now();
						if (now - told > 50) { told = now; wake(0); }
					}
					if (chunks.length == 1) return chunks[0];
					const out = new Uint8Array(f.loaded);
					let at = 0;
					for (const c of chunks) { out.set(c, at); at += c.length; }
					return out;
				}).then(
					(b) => { f.body = b; f.loaded = b.length; f.state = 1; wake(0); }, () => { f.state = -1; wake(0); });
				return host.handles.add(f);
			},
			fetch_state: (h) => host.handles.get(h).state,
			fetch_length: (h) => host.handles.get(h).body?.length ?? 0,
			fetch_loaded: (h) => host.handles.get(h).loaded,
			fetch_total: (h) => host.handles.get(h).total,
			// (into a span: its address and length; no more than the length)
			fetch_take(h, p, n) {
				const f = host.handles.get(h);
				if (f.body) new Uint8Array(host.memory().buffer, p, Math.min(n, f.body.length)).set(f.body.subarray(0, n));
				host.handles.remove(h);
			},
			fetch_free(h) {
				host.handles.get(h).abort.abort();
				host.handles.remove(h);
			},
			// a request (Client.request): a fetch's handle, its status and headers kept;
			// a status of an error a reply (the program reads it), only the network's errors a failure
			http_start(url, method, headers, p, n) {
				const f = { state: 0, body: null, loaded: 0, total: 0, abort: new AbortController(), status: 0, headers: '' };
				const base = typeof document !== 'undefined' ? document.baseURI : host.options.base;
				const h = new Headers();
				for (const line of host.string(headers).split('\n')) {
					const i = line.indexOf(':');
					if (i > 0) h.append(line.slice(0, i).trim(), line.slice(i + 1).trim());
				}
				const m = host.string(method);
				const body = n > 0 ? new Uint8Array(host.memory().buffer, p, n).slice() : undefined;
				fetch(new URL(host.string(url), base), { method: m, headers: h, body: m === 'GET' || m === 'HEAD' ? undefined : body, signal: f.abort.signal })
					.then(async (r) => {
						f.status = r.status;
						const lines = [];
						r.headers.forEach((v, k) => lines.push(k + ': ' + v));
						f.headers = new TextEncoder().encode(lines.join('\n'));
						return new Uint8Array(await r.arrayBuffer());
					}).then((b) => { f.body = b; f.loaded = b.length; f.state = 1; wake(0); }, () => { f.state = -1; wake(0); });
				return host.handles.add(f);
			},
			http_status: (h) => host.handles.get(h).status,
			http_headers_length: (h) => host.handles.get(h).headers.length,
			http_headers(h, p, n) {
				const f = host.handles.get(h);
				new Uint8Array(host.memory().buffer, p, Math.min(n, f.headers.length)).set(f.headers.subarray(0, n));
			},
			// the page's WebSocket (WebSocket.open): its messages queued as UTF-8, a turn at each event
			ws_open(url) {
				const w = { state: 0, queue: [], ws: null };
				const base = typeof document !== 'undefined' ? document.baseURI : host.options.base;
				const u = new URL(host.string(url), base);
				// (relative to the page: its http as ws, https as wss)
				if (u.protocol === 'http:') u.protocol = 'ws:';
				else if (u.protocol === 'https:') u.protocol = 'wss:';
				try {
					w.ws = new WebSocket(u);
				} catch {
					w.state = -1;
					return host.handles.add(w);
				}
				w.ws.binaryType = 'arraybuffer';
				w.ws.onopen = () => { w.state = 1; wake(0); };
				w.ws.onmessage = (e) => {
					w.queue.push(typeof e.data === 'string' ? new TextEncoder().encode(e.data) : new Uint8Array(e.data));
					wake(0);
				};
				w.ws.onclose = () => { w.state = w.state === 0 ? -1 : 2; wake(0); };
				w.ws.onerror = () => { if (w.state === 0) w.state = -1; wake(0); };
				return host.handles.add(w);
			},
			ws_state: (h) => host.handles.get(h).state,
			ws_next: (h) => { const q = host.handles.get(h).queue; return q.length ? q[0].length : -1; },
			ws_take(h, p, n) {
				const m = host.handles.get(h).queue.shift();
				if (m) new Uint8Array(host.memory().buffer, p, Math.min(n, m.length)).set(m.subarray(0, n));
			},
			ws_send(h, text) {
				const w = host.handles.get(h);
				if (w.state === 1) w.ws.send(host.string(text));
			},
			ws_close(h, code) {
				const w = host.handles.get(h);
				if (!w) return;
				try { w.ws?.close(code); } catch {}
				host.handles.remove(h);
			},
		},
	};
}
