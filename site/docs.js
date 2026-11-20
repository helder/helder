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
	const input = document.querySelector('.search'), list = document.querySelector('.results'), status = document.getElementById('search-status');
	const show = (open) => {
		// (under the top bar wherever it is: a host's notice above it scrolls)
		if (open) sidebar.style.top = menu.closest('.top').getBoundingClientRect().bottom + 'px';
		sidebar.classList.toggle('open', open);
		menu.setAttribute('aria-expanded', String(open));
		document.documentElement.classList.toggle('menu-open', open);
	};
	menu?.addEventListener('click', () => {
		const open = !sidebar.classList.contains('open');
		show(open);
		if (open) sidebar.querySelector('ul a[aria-current]')?.focus();
	});
	matchMedia('(max-width: 900px)').addEventListener('change', (e) => {
		if (!e.matches) show(false);
	});
	// (a page or heading chosen, or Escape: the menu closed)
	sidebar?.addEventListener('click', (e) => e.target.closest('a') && show(false));
	document.addEventListener('keydown', (e) => {
		if (e.key !== 'Escape' || !sidebar?.classList.contains('open') || !list?.hidden) return;
		show(false);
		menu.focus();
	});

	for (const button of document.querySelectorAll('.copy-code')) {
		if (!navigator.clipboard?.writeText) continue;
		const code = button.closest('.code').querySelector('pre code');
		button.hidden = false;
		let reset;
		button.addEventListener('click', async () => {
			try {
				await navigator.clipboard.writeText(code.textContent);
				button.textContent = 'Copied';
				button.setAttribute('aria-label', 'Code copied');
			} catch {
				const range = document.createRange();
				range.selectNodeContents(code);
				const selection = window.getSelection();
				selection.removeAllRanges();
				selection.addRange(range);
				button.textContent = 'Selected';
				button.setAttribute('aria-label', 'Code selected for manual copy');
			}
			clearTimeout(reset);
			reset = setTimeout(() => {
				button.textContent = 'Copy';
				button.setAttribute('aria-label', 'Copy code');
			}, 2000);
		});
	}

	if (!input || !list) return;
	let index = null;
	const load = () => (index ??= fetch('docs/search.json').then((r) => {
		if (!r.ok) throw new Error('Search index unavailable');
		return r.json();
	}).catch(() => {
		index = null;
		return null;
	}));
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
	let request = 0;
	const hide = () => {
		request++;
		list.hidden = true;
		status.textContent = '';
	};
	async function update() {
		const q = input.value.trim();
		if (!q) {
			hide();
			return;
		}
		const id = ++request;
		const pages = await load();
		if (id !== request) return;
		const hits = pages ? search(pages, q) : [];
		const count = hits.length;
		const message = pages ? (count ? `${count} ${count === 1 ? 'result' : 'results'}` : 'No results') : 'Search is unavailable. Try again.';
		list.innerHTML = hits.length ? hits.map(({ p, heading }) => `<li><a href="${p.url}${heading ? '#' + heading.id : ''}">${esc(p.title)}${heading
			? ' › ' + esc(heading.text) : ''}<small>${esc(p.section)}</small></a></li>`).join('') : `<li class="none">${message}</li>`;
		list.hidden = false;
		status.textContent = message;
	}
	input.addEventListener('input', update);
	input.addEventListener('keydown', async (e) => {
		if (e.key !== 'ArrowDown' || !input.value.trim()) return;
		e.preventDefault();
		if (list.hidden) await update();
		list.querySelector('a')?.focus();
	});
	input.addEventListener('keydown', (e) => {
		if (e.key === 'Enter' && !list.hidden) list.querySelector('a')?.click();
	});
	list.addEventListener('keydown', (e) => {
		if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
		const link = e.target.closest('li');
		if (!link) return;
		e.preventDefault();
		if (e.key === 'ArrowDown') link.nextElementSibling?.querySelector('a')?.focus();
		else (link.previousElementSibling?.querySelector('a') ?? input).focus();
	});
	list.addEventListener('click', (e) => {
		if (e.target.closest('a')) {
			hide();
			if (sidebar.classList.contains('open')) show(false);
		}
	});
	document.querySelector('.top').addEventListener('keydown', (e) => {
		if (e.key !== 'Escape' || (e.target !== input && !list.contains(e.target))) return;
		e.stopPropagation();
		if (!list.hidden) {
			hide();
			input.focus();
		} else if (sidebar.classList.contains('open')) {
			show(false);
			menu.focus();
		}
	});
	document.addEventListener('click', (e) => {
		if (e.target !== input && !list.contains(e.target)) hide();
	});
	document.addEventListener('focusin', (e) => {
		if (e.target !== input && !list.contains(e.target)) hide();
	});
	// (/ focuses the search)
	document.addEventListener('keydown', (e) => {
		if (e.key === '/' && !e.altKey && !e.ctrlKey && !e.metaKey && !e.target.closest('input, textarea, canvas, [contenteditable]')) {
			e.preventDefault();
			input.focus();
		}
	});
})();
