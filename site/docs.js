// The docs' pages in the browser (static/docs.js; site/docs/Docs.hx writes
// them): an example's source tabs (Haxe, its TypeScript twin), the sidebar
// on a phone (the top bar's menu: the pages and the site's links), and the search: docs/search.json (every page's title, headings and
// text) fetched on the first focus, matched word by word as you type.
(() => {
	for (const tabs of document.querySelectorAll('.example .tabs')) {
		const box = tabs.parentElement;
		tabs.addEventListener('click', (e) => {
			const b = e.target.closest('button[role=tab]');
			if (!b) return;
			for (const t of tabs.querySelectorAll('button')) t.setAttribute('aria-selected', String(t === b));
			for (const p of box.querySelectorAll('.code')) p.hidden = p.dataset.file !== b.dataset.file;
		});
	}

	const menu = document.querySelector('.menu'), sidebar = document.getElementById('sidebar');
	const show = (open) => {
		// (under the top bar wherever it is: a host's notice above it scrolls)
		if (open) sidebar.style.top = menu.closest('.top').getBoundingClientRect().bottom + 'px';
		sidebar.classList.toggle('open', open);
		menu.setAttribute('aria-expanded', String(open));
		document.documentElement.classList.toggle('menu-open', open);
	};
	menu?.addEventListener('click', () => show(!sidebar.classList.contains('open')));
	// (a page or heading chosen, or Escape: the menu closed)
	sidebar?.addEventListener('click', (e) => e.target.closest('a') && show(false));
	document.addEventListener('keydown', (e) => e.key === 'Escape' && sidebar?.classList.contains('open') && show(false));

	const input = document.querySelector('.search'), list = document.querySelector('.results');
	if (!input || !list) return;
	let index = null;
	const load = () => (index ||= fetch('docs/search.json').then((r) => r.json()).catch(() => []));
	input.addEventListener('focus', load);
	const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
	// (a page's score: each word in its title counts most, then its headings, then its text; every word must be somewhere)
	function search(pages, q) {
		const words = q.toLowerCase().split(/\s+/).filter((w) => w);
		const hits = [];
		for (const p of pages) {
			let score = 0, heading = null;
			for (const w of words) {
				const t = p.title.toLowerCase().includes(w) ? 10 : 0;
				const h = p.headings.find((x) => x.text.toLowerCase().includes(w));
				const x = p.text.toLowerCase().includes(w) ? 1 : 0;
				if (!t && !h && !x) {
					score = 0;
					break;
				}
				score += t + (h ? 4 : 0) + x;
				if (h && !heading) heading = h;
			}
			if (score > 0) hits.push({ p, heading, score });
		}
		return hits.sort((a, b) => b.score - a.score).slice(0, 12);
	}
	input.addEventListener('input', async () => {
		const q = input.value.trim();
		if (!q) {
			list.hidden = true;
			return;
		}
		const hits = search(await load(), q);
		list.innerHTML = hits.length ? hits.map(({ p, heading }) => `<li><a href="${p.url}${heading ? '#' + heading.id : ''}">${esc(p.title)}${heading
			? ' › ' + esc(heading.text) : ''}<small>${esc(p.section)}</small></a></li>`).join('') : '<li class="none">Nothing found</li>';
		list.hidden = false;
	});
	input.addEventListener('keydown', (e) => {
		if (e.key === 'Escape') {
			input.value = '';
			list.hidden = true;
		}
		if (e.key === 'Enter') list.querySelector('a')?.click();
	});
	document.addEventListener('click', (e) => {
		if (!e.target.closest('.top')) list.hidden = true;
	});
	// (/ focuses the search)
	document.addEventListener('keydown', (e) => {
		if (e.key === '/' && document.activeElement !== input && !e.target.closest('input, textarea, canvas')) {
			e.preventDefault();
			input.focus();
		}
	});
})();
