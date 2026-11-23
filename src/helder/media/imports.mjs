// The page's side of helder.media's WebSource (src/helder/media/WebSource.hx):
// the imports of the module "helder_media", for browser.mjs's option
// imports. A URL is read by fetch with Range requests (its size from the
// first's Content-Range); a server answering 200 sends it whole, kept as a
// Blob. Blobs by name: browser.mjs's option blobs ({name: Blob}) and
// host.blob(name, blob), for the page and other modules (a file picked or
// dropped). OPFS: a path in navigator.storage.getDirectory(). Reads are
// a Blob's slices or Range requests; each ends in a turn of the loop
// (host.wake, helder.async's).
export default function (host) {
	const blobs = new Map(Object.entries(host.options.blobs ?? {}));
	host.blob = (name, blob) => blobs.set(name, blob);
	const base = () => (typeof document !== 'undefined' ? document.baseURI : host.options.base);
	const settle = (o, ok) => { o.state = ok ? 1 : -1; host.wake?.(0); };
	const get = (h) => host.handles.get(h);
	const source = (blob) => ({ state: blob ? 1 : 0, size: blob ? blob.size : -1, blob, url: null });
	return {
		helder_media: {
			url(p) {
				const s = source(null);
				s.url = new URL(host.string(p), base()).href;
				fetch(s.url, { headers: { Range: 'bytes=0-0' } }).then(async (r) => {
					if (r.status === 206) {
						const total = /\/(\d+)$/.exec(r.headers.get('content-range') ?? '');
						s.size = total ? Number(total[1]) : -1;
						await r.arrayBuffer();
					} else if (r.ok) {
						s.blob = await r.blob();
						s.size = s.blob.size;
					} else throw r.status;
				}).then(() => settle(s, true), () => settle(s, false));
				return host.handles.add(s);
			},
			blob(p) {
				const b = blobs.get(host.string(p));
				const s = source(b ?? null);
				if (!b) s.state = -1;
				return host.handles.add(s);
			},
			opfs(p) {
				const s = source(null);
				(async () => {
					const parts = host.string(p).split('/').filter((x) => x);
					let dir = await navigator.storage.getDirectory();
					for (const d of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(d);
					s.blob = await (await dir.getFileHandle(parts[parts.length - 1])).getFile();
					s.size = s.blob.size;
				})().then(() => settle(s, true), () => settle(s, false));
				return host.handles.add(s);
			},
			state: (h) => get(h).state,
			size: (h) => get(h).size,
			read(h, offset, n) {
				const s = get(h), r = { state: 0, body: null, abort: new AbortController() };
				const got = s.blob
					? s.blob.slice(offset, offset + n).arrayBuffer()
					: fetch(s.url, { headers: { Range: `bytes=${offset}-${offset + n - 1}` }, signal: r.abort.signal }).then((x) => {
						// (416: past the end)
						if (x.status === 416) return new ArrayBuffer(0);
						if (!x.ok) throw x.status;
						return x.arrayBuffer().then((b) => (x.status === 206 ? b : b.slice(offset, offset + n)));
					});
				got.then((b) => { r.body = new Uint8Array(b); settle(r, true); }, () => settle(r, false));
				return host.handles.add(r);
			},
			length: (h) => get(h).body?.length ?? 0,
			take(h, p, n) {
				const r = get(h);
				if (r.body) new Uint8Array(host.memory().buffer, p, Math.min(n, r.body.length)).set(r.body.subarray(0, n));
				host.handles.remove(h);
			},
			free(h) {
				get(h)?.abort?.abort();
				host.handles.remove(h);
			},
		},
	};
}
