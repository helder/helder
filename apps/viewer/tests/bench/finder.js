// Finder's side of finder.mjs (osascript -l JavaScript finder.js '<json>'):
// in one process, so that a poll is a few Apple events, not an osascript
// launch. Each measure: a new Finder window on a folder, then one window's
// target changed, in list view, until its accessibility tree (System
// Events: Finder's window's outline) has the folder's first rows (first:
// rows, not the last folder's count: each folder's is its own) and all of
// them (all); times from Finder's command, in ms. The
// polling's own cost: a count on a window already populated (count), and
// the outline found again and counted (find). Every window it opens is
// closed. Prints JSON.
//   cfg: {folders: {key: {path, entries}}, runs}
ObjC.import('Foundation');

function run(argv) {
	const cfg = JSON.parse(argv[0]);
	const finder = Application('Finder');
	const se = Application('System Events');
	const proc = se.processes.byName('Finder');
	const t = () => $.NSProcessInfo.processInfo.systemUptime * 1000;
	const opened = [];

	// (the window's list: the outline of list view, found by walking its elements)
	function outline(el, depth) {
		if (depth > 8) return null;
		let kids;
		try {
			kids = el.uiElements();
		} catch (e) {
			return null;
		}
		for (const k of kids) if (k.role() === 'AXOutline') return k;
		for (const k of kids) {
			const f = outline(k, depth + 1);
			if (f) return f;
		}
		return null;
	}
	const rows = (o) => {
		try {
			return o.rows.length;
		} catch (e) {
			return -1;
		}
	};
	// (from t0: its first rows (the last folder's count, before, gone), all of
	// them; o: the outline, when the window is the same)
	function populated(t0, entries, before, o) {
		let firstAt = null;
		while (t() - t0 < 20000) {
			if (!o) o = outline(proc.windows[0], 0);
			const n = o ? rows(o) : -1;
			if (n < 0) o = null;
			if (firstAt === null && n > 0 && (n !== before || n === entries)) firstAt = t() - t0;
			if (n === entries) return { first: firstAt, all: t() - t0, outline: o };
			delay(0.005);
		}
		return { first: firstAt, all: null, outline: o };
	}
	function open(path) {
		const w = finder.make({ new: 'Finder window', to: Path(path) });
		opened.push(w);
		w.currentView = 'list view';
		return w;
	}
	function close() {
		for (const w of opened) {
			try {
				w.close();
			} catch (e) {}
		}
		opened.length = 0;
	}

	const out = { overhead: { count: [], find: [] }, window: {}, nav: {} };
	try {
		const keys = Object.keys(cfg.folders);
		// the polling's cost, on a window already populated
		open(cfg.folders[keys[0]].path);
		delay(1);
		const o = outline(proc.windows[0], 0);
		for (let k = 0; k < cfg.runs; k++) {
			let t0 = t();
			rows(o);
			out.overhead.count.push(t() - t0);
			t0 = t();
			rows(outline(proc.windows[0], 0));
			out.overhead.find.push(t() - t0);
		}
		close();
		// a new window on each folder
		for (const key of keys) {
			out.window[key] = [];
			for (let k = 0; k < cfg.runs; k++) {
				const t0 = t();
				open(cfg.folders[key].path);
				const r = populated(t0, cfg.folders[key].entries, -1, null);
				out.window[key].push({ first: r.first, all: r.all });
				close();
			}
		}
		// one window, its target changed: each folder after another
		const w = open(cfg.folders[keys[0]].path);
		delay(0.5);
		let found = null, before = cfg.folders[keys[0]].entries;
		for (const key of keys) out.nav[key] = [];
		for (let k = 0; k < cfg.runs; k++) for (const key of keys) {
			const t0 = t();
			w.target = Path(cfg.folders[key].path);
			const r = populated(t0, cfg.folders[key].entries, before, found);
			found = r.outline;
			before = cfg.folders[key].entries;
			out.nav[key].push({ first: r.first, all: r.all });
		}
	} finally {
		close();
	}
	return JSON.stringify(out);
}
