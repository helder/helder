// The landing's flock (site/docs/Home.hx): started where WebGPU is and motion
// is welcome; elsewhere its picture stays (a phone's WebGL2 would steer it
// on the CPU, fewer and slower). And the install line's Copy.
(() => {
	const flock = document.getElementById('play-murmuration');
	if (flock && navigator.gpu && !matchMedia('(prefers-reduced-motion: reduce)').matches)
		navigator.gpu.requestAdapter().then((a) => a && flock.click(), () => {});
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
