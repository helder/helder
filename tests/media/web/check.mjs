// MediaWebTest's page side: the frame's pixels read back (helder.gfx's
// readPixels: a headless target's as it is, resolved later), by handle.
export default function (host) {
	return {
		helder_media_check: {
			read() {
				const r = { state: 0, data: null };
				host.gfx.readPixels().then((p) => { r.data = p.data; r.state = 1; host.wake?.(0); }, () => { r.state = -1; host.wake?.(0); });
				return host.handles.add(r);
			},
			take(h, p, n) {
				const r = host.handles.get(h);
				if (r.data) host.bytes(p, Math.min(n, r.data.length)).set(r.data.subarray(0, n));
				host.handles.remove(h);
			},
		},
	};
}
