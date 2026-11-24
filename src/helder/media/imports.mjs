// The page's side of helder.media's WebSource (src/helder/media/WebSource.hx):
// the imports of the module "helder_media", for browser.mjs's option
// imports. A URL is read by fetch with Range requests (its size from the
// first's Content-Range); a server answering 200 sends it whole, kept as a
// Blob. Blobs by name: browser.mjs's option blobs ({name: Blob}) and
// host.blob(name, blob), for the page and other modules (a file picked or
// dropped). OPFS: a path in navigator.storage.getDirectory(). Reads are
// a Blob's slices or Range requests; each ends in a turn of the loop
// (host.wake, helder.async's).
//
// WebCodecs (helder.media.web): decoders by handle, our packets in as
// EncodedVideoChunk and EncodedAudioChunk (their bytes copied: the
// module's memory may grow), what comes out kept here: a VideoFrame never
// enters the module's memory, a handle of {bitmap, width, height} that
// helder.gfx's texture_image copies on the GPU (copyExternalImageToTexture,
// texImage2D); AudioData copied as interleaved floats. Nothing needs a
// document: decoders run in a worker too. The `<video>` element (main
// thread only) is the fallback for what WebCodecs does not decode.
export default function (host) {
	const blobs = new Map(Object.entries(host.options.blobs ?? {}));
	host.blob = (name, blob) => blobs.set(name, blob);
	const base = () => (typeof document !== 'undefined' ? document.baseURI : host.options.base);
	const settle = (o, ok) => { o.state = ok ? 1 : -1; host.wake?.(0); };
	const get = (h) => host.handles.get(h);
	const source = (blob) => ({ state: blob ? 1 : 0, size: blob ? blob.size : -1, blob, url: null });
	const wake = () => host.wake?.(0);
	const config = (kind, codec, d, n, a, b) => {
		const c = { codec: host.string(codec) };
		if (n > 0) c.description = host.bytes(d, n).slice();
		if (kind) Object.assign(c, { sampleRate: a, numberOfChannels: b });
		else Object.assign(c, { codedWidth: a, codedHeight: b });
		return c;
	};
	const MATRIX = { bt709: 709, 'bt2020-ncl': 2020 };
	// (a frame's planes, rows packed, as NV12 or P010: a test's, for its checksums)
	async function planes(f) {
		const rect = f.visibleRect, w = rect.width, h = rect.height, cw = (w + 1) >> 1, ch = (h + 1) >> 1;
		// (RGB already: Firefox's software decoders' BGRX)
		if (!/^(I4|NV)/.test(f.format ?? '')) return null;
		const buf = new Uint8Array(f.allocationSize({ rect })), lay = await f.copyTo(buf, { rect });
		const deep = f.format.includes('P10'), px = deep ? 2 : 1, out = new Uint8Array((w * h + cw * ch * 2) * px);
		const nv = f.format.startsWith('NV12');
		let at = 0;
		const put = (v) => {
			if (deep) { v <<= 6; out[at++] = v & 255; out[at++] = v >> 8; } else out[at++] = v;
		};
		const get = (p, x, y) => {
			const o = lay[p].offset + y * lay[p].stride + x * px;
			return deep ? buf[o] | (buf[o + 1] << 8) : buf[o];
		};
		for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) put(get(0, x, y));
		for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
			put(nv ? get(1, x * 2, y) : get(1, x, y));
			put(nv ? get(1, x * 2 + 1, y) : get(2, x, y));
		}
		return out;
	}
	function frame(f, w, h) {
		const s = f.colorSpace ?? {};
		return { bitmap: f, premultiply: false, state: 1, width: w, height: h, time: f.timestamp ?? 0, matrix: MATRIX[s.matrix] ?? 601, full: s.fullRange ? 1 : 0,
			bits: f.format?.includes('P10') ? 10 : 8, pixels: null };
	}
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
			// WebCodecs: whether a config decodes here (a handle's state)
			supported(kind, codec, a, b, d, n) {
				const s = { state: 0 }, C = globalThis[kind ? 'AudioDecoder' : 'VideoDecoder'];
				if (!C) s.state = -1;
				else C.isConfigSupported(config(kind, codec, d, n, a, b)).then((r) => settle(s, r.supported), () => settle(s, false));
				return host.handles.add(s);
			},
			// a decoder: frames (or AudioData) kept in out as they come; copy:
			// each frame's planes read first (a test's); gen: a reset's, what
			// was in flight before it dropped
			decoder(kind, codec, a, b, copy, space, d, n) {
				const v = { kind, config: config(kind, codec, d, n, a, b), out: [], hidden: new Set(), pending: 0, failed: false, gen: 0, dec: null };
				const C = globalThis[kind ? 'AudioDecoder' : 'VideoDecoder'];
				// (colours the stream does not name: BT.601's matrix, as ffmpeg and
				// Apple read them; sRGB's primaries and transfer, so that nothing
				// else is converted, as helder shows a video)
				if (space) v.config.colorSpace = { primaries: 'bt709', transfer: 'iec61966-2-1', matrix: 'smpte170m', fullRange: space === 2 };
				const out = kind ? (x) => { v.out.push(x); wake(); } : (f) => {
					// (before a seek's target: never shown, its picture given back at once)
					if (v.hidden.delete(f.timestamp)) return f.close();
					const o = frame(f, f.displayWidth, f.displayHeight), g = v.gen;
					const done = () => { if (g !== v.gen) return f.close(); v.pending--; v.out.push(o); wake(); };
					if (copy) planes(f).then((p) => { o.pixels = p; done(); }, done);
					else done();
				};
				try {
					v.dec = new C({ output: out, error: (e) => { console.warn('helder.media: ' + e.message); v.failed = true; wake(); } });
					v.dec.configure(v.config);
				} catch { v.failed = true; }
				return host.handles.add(v);
			},
			// a packet (time and duration in microseconds); show 0: decoded, not output; 0: it failed
			decode(h, key, time, duration, show, p, n) {
				const v = get(h), Chunk = v.kind ? EncodedAudioChunk : EncodedVideoChunk;
				if (v.failed) return 0;
				if (!show) v.hidden.add(time);
				else if (!v.kind) v.pending++;
				try { v.dec.decode(new Chunk({ type: key ? 'key' : 'delta', timestamp: time, duration, data: host.bytes(p, n) })); }
				catch { v.failed = true; }
				return v.failed ? 0 : 1;
			},
			failed: (h) => (get(h).failed ? 1 : 0),
			pending: (h) => get(h).pending,
			flush(h) {
				const v = get(h);
				if (!v.failed) v.dec.flush().catch(() => {});
			},
			reset(h) {
				const v = get(h);
				v.gen++;
				for (const o of v.out) (o.bitmap ?? o).close();
				v.out = [];
				v.hidden.clear();
				v.pending = 0;
				if (v.failed) return;
				// (reset leaves it unconfigured)
				try { v.dec.reset(); v.dec.configure(v.config); } catch { v.failed = true; }
			},
			close(h) {
				const v = get(h);
				for (const o of v.out) (o.bitmap ?? o).close();
				if (v.dec?.state !== 'closed') try { v.dec?.close(); } catch {}
				host.handles.remove(h);
			},
			// the next frame out (a handle; 0: none)
			frame: (h) => { const o = get(h).out.shift(); return o ? host.handles.add(o) : 0; },
			// its time (microseconds), size, matrix (601, 709, 2020), range (1: full), bits
			info: (h, what) => { const o = get(h); return [o.time, o.width, o.height, o.matrix, o.full, o.bits][what]; },
			pixels_length: (h) => get(h).pixels?.length ?? 0,
			pixels(h, p, n) { const b = get(h).pixels; if (b) host.bytes(p, Math.min(n, b.length)).set(b.subarray(0, n)); },
			release(h) {
				get(h).bitmap.close?.();
				host.handles.remove(h);
			},
			// the next AudioData's frames (-1: none)
			audio_frames: (h) => get(h).out[0]?.numberOfFrames ?? -1,
			// it into p: interleaved stereo floats (mono doubled, more: the first two), given back
			audio_take(h, p) {
				const a = get(h).out.shift(), k = a.numberOfFrames, l = new Float32Array(k), r = a.numberOfChannels > 1 ? new Float32Array(k) : l;
				a.copyTo(l, { planeIndex: 0, format: 'f32-planar' });
				if (r !== l) a.copyTo(r, { planeIndex: 1, format: 'f32-planar' });
				a.close();
				const m = new Float32Array(host.memory().buffer, p, k * 2);
				for (let i = 0; i < k; i++) { m[i * 2] = l[i]; m[i * 2 + 1] = r[i]; }
			},
			// the <video> element (no document: 0): a source's URL or Blob, playing by itself, muted until asked
			element(src) {
				if (typeof document === 'undefined') return 0;
				const s = get(src), e = document.createElement('video'), o = { bitmap: e, premultiply: false, state: 0, width: 0, height: 0, time: 0, matrix: 601, full: 0, bits: 8, shown: 0, ended: 0, failed: 0 };
				e.muted = true;
				e.playsInline = true;
				e.preload = 'auto';
				e.crossOrigin = 'anonymous';
				// (in the page, unseen: some browsers decode a detached one's frames only once)
				e.style.cssText = 'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none';
				document.body.append(e);
				e.src = s.blob ? (o.url = URL.createObjectURL(s.blob)) : s.url;
				e.onloadeddata = () => { o.width = e.videoWidth; o.height = e.videoHeight; settle(o, true); };
				e.onerror = () => { o.failed = 1; settle(o, false); };
				e.onended = () => { o.ended = 1; wake(); };
				// (each frame presented: its own time, a turn of the loop)
				const each = (_, m) => { o.time = m.mediaTime; o.shown++; wake(); e.requestVideoFrameCallback(each); };
				if (e.requestVideoFrameCallback) e.requestVideoFrameCallback(each);
				return host.handles.add(o);
			},
			// what of it: its time (the frame shown's), frames presented, ended, failed, duration, playing
			element_get(h, what) {
				const o = get(h), e = o.bitmap;
				return [e.requestVideoFrameCallback ? o.time : e.currentTime, e.requestVideoFrameCallback ? o.shown : e.currentTime, o.ended, o.failed, e.duration || 0, e.paused ? 0 : 1][what];
			},
			// set it: play (1, 0: pause), currentTime, volume, muted, playbackRate, loop
			element_set(h, what, v) {
				const o = get(h), e = o.bitmap;
				if (what === 0) {
					o.ended = 0;
					// (no gesture yet: a video with sound is refused, then played muted)
					if (v) e.play().catch(() => { if (!e.muted) { e.muted = true; e.play().catch(() => {}); } });
					else e.pause();
				} else if (what === 3 && !v && navigator.userActivation?.hasBeenActive === false) {
					// (sound before a gesture would pause it: muted until one)
				} else e[['', 'currentTime', 'volume', 'muted', 'playbackRate', 'loop'][what]] = what === 3 || what === 5 ? !!v : v;
			},
			element_close(h) {
				const o = get(h), e = o.bitmap;
				e.pause();
				e.removeAttribute('src');
				e.load();
				e.remove();
				if (o.url) URL.revokeObjectURL(o.url);
				host.handles.remove(h);
			},
		},
	};
}
