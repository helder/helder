// MediaWebTest's page side: the frame's pixels read back (helder.gfx's
// readPixels: a headless target's as it is, resolved later), by handle;
// each decoded frame's planes read before helder.media gives it out (its
// hook host.mediaFrame), for the checksums. The test's alone: apps never
// read a frame's planes.
export default function (host) {
	// (a frame's planes, rows packed, as NV12 or P010; null: RGB)
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
	host.mediaFrame = (o) => planes(o.bitmap).then((p) => { o.pixels = p; });
	return {
		helder_media_check: {
			read() {
				const r = { state: 0, data: null };
				host.gfx.readPixels().then((p) => { r.data = p.data; r.state = 1; host.wake?.(0); }, () => { r.state = -1; host.wake?.(0); });
				return host.handles.add(r);
			},
			// a frame's planes (its handle): their length, then them
			pixels_length: (h) => host.handles.get(h).pixels?.length ?? 0,
			pixels(h, p, n) {
				const b = host.handles.get(h).pixels;
				if (b) host.bytes(p, Math.min(n, b.length)).set(b.subarray(0, n));
			},
			take(h, p, n) {
				const r = host.handles.get(h);
				if (r.data) host.bytes(p, Math.min(n, r.data.length)).set(r.data.subarray(0, n));
				host.handles.remove(h);
			},
		},
	};
}
