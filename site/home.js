// The landing's flock (site/docs/Home.hx): started where WebGPU is, on a
// real GPU, and motion is welcome; elsewhere its picture stays (WebGL2
// would steer it on the CPU, fewer and slower) until Play. A demo the
// reader started is marked data-pressed: only then does site.css show
// "Loading…" over its picture. And the install line's Copy.
(() => {
	for (const ev of ['pointerdown', 'keydown'])
		document.addEventListener(ev, (e) => {
			const island = e.isTrusted && e.target.closest?.('hxmc-island');
			if (island) island.setAttribute('data-pressed', '');
		}, true);
	const flock = document.getElementById('play-murmuration');
	if (flock && navigator.gpu && !matchMedia('(prefers-reduced-motion: reduce)').matches)
		navigator.gpu.requestAdapter().then((a) => a && !a.isFallbackAdapter && !a.info?.isFallbackAdapter && flock.click(), () => {});
	for (const b of document.querySelectorAll('[data-copy]')) {
		if (!navigator.clipboard?.writeText) continue;
		b.hidden = false;
		b.addEventListener('click', async () => {
			await navigator.clipboard.writeText(document.getElementById(b.dataset.copy).textContent);
			b.textContent = 'Copied';
			setTimeout(() => (b.textContent = 'Copy'), 2000);
		});
	}
})();
