// The JavaScript side of helder.story.web.Preview (the module
// "helder_preview"), in the preview's worker (worker.mjs): its
// OffscreenCanvas, each frame transferred to the page as an ImageBitmap
// (run's option onFrame), the protocol's lines both ways (onLine; the
// worker's queue, options.preview.queue), the loop on the worker's
// animation frames (requestAnimationFrame where the worker has it, else a
// timer at 60 Hz), turned at once by a line for the program
// (host.preview.wake).
const enc = new TextEncoder();

export default function (host) {
	const queue = host.options.preview?.queue ?? [];
	const raf = typeof requestAnimationFrame === 'function';
	// (the loop's next turn: an animation frame's, or a timer's; one of them at a time)
	let stopped = false, tick = null, frame = 0, timer = 0;
	const schedule = (f) => {
		if (raf) frame = requestAnimationFrame(f);
		else timer = setTimeout(f, 16);
	};
	// (a line for the program: its loop turned now, not at the next animation
	// frame: a worker's come with the page's, and a page drawing nothing, the
	// studio's while it waits on the program, gave none for tens of seconds)
	const wake = () => {
		if (!tick || stopped || host.disposed || (timer && !frame)) return;
		if (frame) cancelAnimationFrame(frame);
		if (timer) clearTimeout(timer);
		frame = 0;
		timer = setTimeout(tick, 0);
	};
	host.preview = { stop: () => (stopped = true), wake };
	return {
		helder_preview: {
			canvas: () => host.handles.add(new OffscreenCanvas(1, 1)),
			resize(h, w, hh) {
				const c = host.handles.get(h);
				if (c.width !== w) c.width = w;
				if (c.height !== hh) c.height = hh;
			},
			present(h, screen, version, width, height) {
				const bitmap = host.handles.get(h).transferToImageBitmap();
				host.options.onFrame?.({ screen, version, width, height, bitmap });
			},
			send: (p) => host.options.onLine?.(host.string(p)),
			next: () => (queue.length ? host.handles.add(queue.shift()) : 0),
			text_length: (h) => enc.encode(host.handles.get(h)).length,
			text_take(h, p) {
				const b = enc.encode(host.handles.get(h));
				host.bytes(p, b.length + 1).set(b);
				host.bytes(p + b.length, 1)[0] = 0;
				host.handles.remove(h);
			},
			start(f) {
				tick = () => {
					frame = timer = 0;
					if (stopped || host.disposed) return;
					if (host.call(f) !== 0) schedule(tick);
				};
				schedule(tick);
			},
		},
	};
}
