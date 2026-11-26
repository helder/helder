// The JavaScript side of helder.ui in the browser, loaded by
// src/helder/os/browser.mjs (run's imports: 'ui/imports.mjs' beside os, gfx
// and text's): the imports of the module "hxmc_ui"
// (src/helder/ui/access/web/Access.hx), the accessibility tree's adapter.
//
// A UiWindow's accessibility tree (helder.ui.access.AccessTree) is mirrored
// as elements inside its canvas: a canvas's children are its fallback
// content, not drawn but in the page's accessibility tree, focusable, and
// their events reach the canvas's listeners by bubbling. Each node is a
// div with its ARIA role, name and states (a set's place, a table's rows
// and columns and a cell's, read-only), its children in order; the
// node with the keyboard focus gets the page's focus (keys still reach the
// program). An activation (a screen reader's click) or a focus moved by
// assistive technology comes back as an action (AccessAction). While a
// text field has it and the window takes text (helder.os's text input: its
// textarea focused, for input methods), the focus stays the textarea's,
// named as the field.
//
// A window's native text editors (src/helder/ui/platform/WebViews.hx): an input
// or a textarea of the page, in a layer over the canvas (its size, clipping
// them), absolutely placed where the
// field's content box is laid out, borderless and transparent (the drawn
// box is the theme's), in the field's font and colour. Edits, focus and the
// keys it leaves to the program (Tab, Escape; Enter, Up and Down on one
// line) are queued for the module.
// The program in a worker (src/helder/os/thread.mjs): the calls in PAGE
// are made by this module's page half (export page), its events posted
// to the worker's queues.
// (a keyboard's inputmode)
const MODES = { number: 'numeric', phone: 'tel' };
// (an editor's number as a system layer: helder.ui.platform.WebEditor's EDITOR)
const EDITOR = 1 << 24;

export default function ui(host) {
	const editors = new Map();
	const editorEvents = [];
	let nextEditor = 1;
	// a canvas's layer of editors: over it in the page, its size, clipping
	// them (one placed for an older layout never widens the page), kept on
	// the canvas as it changes size
	function layer(c) {
		if (c.hxmcEditors) return c.hxmcEditors;
		const l = document.createElement('div');
		l.style.cssText = 'position:absolute;overflow:hidden;pointer-events:none;z-index:2;';
		document.body.appendChild(l);
		const fit = () => {
			const r = c.getBoundingClientRect();
			l.style.left = r.left + window.scrollX + 'px';
			l.style.top = r.top + window.scrollY + 'px';
			l.style.width = r.width + 'px';
			l.style.height = r.height + 'px';
		};
		fit();
		new ResizeObserver(fit).observe(c);
		l.fit = fit;
		c.hxmcEditors = l;
		return l;
	}
	// a canvas's layer of scroll views (src/helder/ui/platform/web/Scroll.hx): as
	// the editors' but under them; the canvas's listeners take the pointer's
	// events over it (helder.os's c.hxmcForward), its cursor the canvas's
	function scrollLayer(c) {
		if (c.hxmcScrolls) return c.hxmcScrolls;
		if (!document.getElementById('hxmc-nobar')) {
			const style = document.createElement('style');
			style.id = 'hxmc-nobar';
			style.textContent = '.hxmc-nobar::-webkit-scrollbar{display:none}';
			document.head.appendChild(style);
		}
		const l = document.createElement('div');
		l.style.cssText = 'position:absolute;overflow:hidden;pointer-events:none;z-index:1;user-select:none;-webkit-user-select:none;-webkit-tap-highlight-color:transparent;';
		document.body.appendChild(l);
		const fit = () => {
			const r = c.getBoundingClientRect();
			l.style.left = r.left + window.scrollX + 'px';
			l.style.top = r.top + window.scrollY + 'px';
			l.style.width = r.width + 'px';
			l.style.height = r.height + 'px';
		};
		fit();
		new ResizeObserver(fit).observe(c);
		l.fit = fit;
		l.style.cursor = c.style.cursor;
		c.hxmcScrolls = l;
		c.hxmcForward?.(l);
		return l;
	}
	// a scroll view's popups over it left out of it (clip-path: neither
	// drawn, its scrollbar with it, nor hit there): the page draws it over the
	// canvas, and so over what the tree draws above it; one holding a layer
	// of the window's (layers_apply) is not cut, which would cut its content:
	// clear elements over it take the input there instead (hxmcBlock: the
	// canvas's, as over the canvas)
	function cover(s, l) {
		const c = s.covers ?? [], k = s.k;
		for (const b of s.blocks ?? []) b.remove();
		s.blocks = [];
		if (s.hosting) {
			s.clip = '';
			s.e.style.clipPath = '';
			const r = s.e.getBoundingClientRect(), o = l.getBoundingClientRect();
			for (let i = 0; i < c.length; i += 4) {
				const b = document.createElement('div');
				b.hxmcBlock = true;
				b.style.cssText = `position:absolute;left:${r.left - o.left + c[i] * k}px;top:${r.top - o.top + c[i + 1] * k}px;width:${c[i + 2] * k}px;height:${c[i + 3] * k}px;z-index:100000;pointer-events:auto;`;
				l.appendChild(b);
				s.blocks.push(b);
			}
			return;
		}
		// (its own outline far out: the holes are what count, whatever its size becomes)
		let d = '';
		for (let i = 0; i < c.length; i += 4)
			d += ` M${c[i] * k} ${c[i + 1] * k}h${c[i + 2] * k}v${c[i + 3] * k}h${-c[i + 2] * k}Z`;
		s.clip = d ? `path(evenodd, "M-100000 -100000H100000V100000H-100000Z${d}")` : '';
		s.e.style.clipPath = s.clip;
	}
	// (whether the browser's scrollbars overlay the content, taking no room: asked once)
	let overlay = null;
	const overlays = () => (overlay ??= (() => {
		const d = document.createElement('div');
		d.style.cssText = 'position:absolute;visibility:hidden;width:100px;height:100px;overflow:scroll;';
		document.body.appendChild(d);
		const w = d.offsetWidth - d.clientWidth;
		d.remove();
		return w === 0;
	})());
	// a view holding its scroller's content as a layer (stacked in paint
	// order, its bars no longer over everything), its bars wanted, where the
	// browser's overlay: the browser's own, moving and bouncing with its
	// scroll; the program told (-id, as a scroll), drawing none for it
	function showBars(s) {
		const on = !!(s.hosting && s.bars && overlays());
		s.e.style.scrollbarWidth = on ? 'auto' : 'none';
		s.e.classList.toggle('hxmc-nobar', !on);
		if (on === !!s.native) return;
		s.native = on;
		send('scrolled', [-s.id, on ? 1 : 0, 0]);
	}
	// per canvas: its views by id ({e: the scroller, s: its spacer}); the scrolls they made, queued
	const scrollers = new Map();
	const scrolled = [];
	// an event for the program (a string: a handle there), the page half's
	// posted to it in its worker; an editor's or a scroll's asks for a
	// frame, which polls it
	const lists = { editor: editorEvents, scrolled, actions: null };
	const send = (name, ev) => {
		if (host.program) host.program.post({ type: 'queue', mod: 'hxmc_ui', name, ev });
		else lists[name].push(ev.map((x) => (typeof x === 'string' ? host.handles.add(x) : x)));
		if (name !== 'actions') host.os?.redraw();
	};
	const queue = (ev) => send('editor', ev);
	const EDITOR_KEYS = { Tab: 0xff09, Escape: 0xff1b, Enter: 0xff0d, ArrowUp: 0xff52, ArrowDown: 0xff54 };
	// per canvas: the mirror's root, its elements by node id
	const mirrors = new Map();
	const actions = (lists.actions = []);
	// (focus() of ours: not an action)
	let focusing = false;

	function mirror(canvas) {
		let m = mirrors.get(canvas);
		if (!m) {
			const root = document.createElement('div');
			canvas.appendChild(root);
			m = { root, elements: new Map(), rootId: 0 };
			mirrors.set(canvas, m);
		}
		return m;
	}

	function element(m, id) {
		let e = m.elements.get(id);
		if (!e) {
			e = document.createElement('div');
			e.id = 'hxmc-access-' + id;
			e.addEventListener('click', (ev) => {
				send('actions', [id, 0]);
				ev.stopPropagation();
			});
			e.addEventListener('focus', () => {
				if (!focusing) send('actions', [id, 1]);
			});
			m.elements.set(id, e);
		}
		return e;
	}

	function apply(e, n) {
		const set = (k, v) => (v === undefined || v === null ? e.removeAttribute(k) : e.setAttribute(k, String(v)));
		set('role', n.role === 'text' ? null : n.role);
		if (n.role === 'text') e.textContent = n.name;
		else if (n.role === 'textbox' || ((n.role === 'combobox' || n.role === 'spinbutton') && n.value !== undefined)) {
			set('aria-label', n.name || null);
			set('aria-multiline', n.multiline ? 'true' : null);
		} else set('aria-label', n.name || null);
		set('aria-description', n.description);
		set('data-href', n.href);
		// (what UI tests find it by: Playwright's getByTestId)
		set('data-testid', n.identifier);
		set('aria-checked', n.role === 'button' ? null : n.checked);
		set('aria-pressed', n.role === 'button' ? n.checked : null);
		set('aria-selected', n.selected);
		set('aria-multiselectable', n.multiselectable ? 'true' : null);
		set('aria-current', n.current ? 'page' : null);
		set('aria-live', n.live);
		set('aria-expanded', n.expanded);
		set('aria-level', n.level);
		set('aria-disabled', n.disabled ? 'true' : null);
		set('aria-invalid', n.invalid ? 'true' : null);
		set('aria-required', n.required ? 'true' : null);
		set('aria-modal', n.modal ? 'true' : null);
		set('aria-valuenow', n.valueNow);
		set('aria-valuemin', n.valueMin);
		set('aria-valuemax', n.valueMax);
		set('aria-valuetext', n.valueText);
		set('aria-readonly', n.readOnly ? 'true' : null);
		// (a set's place, a table's size and a cell's place: ARIA's are from 1)
		set('aria-posinset', n.posInSet);
		set('aria-setsize', n.setSize);
		set('aria-rowcount', n.rowCount);
		set('aria-colcount', n.colCount);
		set('aria-rowindex', n.rowIndex === undefined ? null : n.rowIndex + 1);
		set('aria-colindex', n.colIndex === undefined ? null : n.colIndex + 1);
		set('tabindex', n.focusable ? '-1' : null);
		e.hxmcValue = n.value;
		e.hxmcChildren = n.children;
	}

	const hxmc_ui = {
		// an update of the tree of the window whose canvas is that handle (JSON:
		// full, root, focus, nodes, removed)
		access_update(canvas, json) {
			const c = host.handles.get(canvas);
			const u = JSON.parse(host.string(json));
			const m = mirror(c);
			// (whether the page's focus is the canvas's, before the elements
			// move: moving the focused one would blur it)
			const input = c.hxmcInput;
			const inside = document.activeElement === c || c.contains(document.activeElement) || (input && document.activeElement === input);
			if (u.full) {
				m.elements.clear();
				m.root.replaceChildren();
			}
			for (const id of u.removed) {
				m.elements.get(id)?.remove();
				m.elements.delete(id);
			}
			for (const n of u.nodes) apply(element(m, n.id), n);
			// the children in order (of each node updated: its list is its own)
			for (const n of u.nodes) {
				const e = m.elements.get(n.id);
				const kids = n.children.map((k) => element(m, k));
				// (a textbox's value is its text, before its children)
				const want = (n.role === 'textbox' || n.role === 'combobox' || n.role === 'spinbutton') && n.value ? [document.createTextNode(n.value), ...kids] : kids;
				if (n.role === 'text') continue;
				// (only what differs moves: the focused element stays put)
				const have = [...e.childNodes];
				const same = have.length === want.length && want.every((w, i) => w === have[i] || (w.nodeType === 3 && have[i].nodeType === 3 && w.data === have[i].data));
				if (!same) e.replaceChildren(...want);
			}
			m.rootId = u.root;
			const top = m.elements.get(u.root);
			if (top && top.parentNode !== m.root) m.root.replaceChildren(top);
			// the focus: the program's focused node, while the page's focus is the canvas's
			if (inside) {
				const f = u.focus ? m.elements.get(u.focus) : null;
				focusing = true;
				const role = f ? f.getAttribute('role') : null;
				const typed = f && (role === 'textbox' || ((role === 'combobox' || role === 'spinbutton') && f.hxmcValue !== undefined));
				if (f && input && document.activeElement === input && typed) {
					input.setAttribute('aria-label', f.getAttribute('aria-label') ?? '');
					// (a combobox or spin button typed in: the textarea is one, with its states)
					const copy = (k) => (f.hasAttribute(k) ? input.setAttribute(k, f.getAttribute(k)) : input.removeAttribute(k));
					if (role === 'textbox') input.removeAttribute('role');
					else input.setAttribute('role', role);
					for (const k of ['aria-expanded', 'aria-valuenow', 'aria-valuemin', 'aria-valuemax', 'aria-valuetext', 'aria-readonly']) copy(k);
					if (f.getAttribute('aria-multiline')) input.setAttribute('aria-multiline', 'true');
					else input.removeAttribute('aria-multiline');
				} else if (f && document.activeElement !== f) f.focus({ preventScroll: true });
				else if (!f && document.activeElement !== c) c.focus({ preventScroll: true });
				focusing = false;
			}
		},
		// a native text editor over the canvas: its handle
		// (given: its handle, the program's in a worker)
		editor_create(canvas, multiline, given) {
			const c = host.handles.get(canvas);
			const e = document.createElement(multiline ? 'textarea' : 'input');
			const h = given ?? nextEditor++;
			if (!multiline) e.type = 'text';
			e.id = 'hxmc-editor-' + h;
			e.setAttribute('data-hxmc-editor', '');
			e.style.cssText = 'position:absolute;display:none;margin:0;border:0;padding:0;background:transparent;outline:none;box-sizing:border-box;resize:none;overflow:hidden;pointer-events:auto;';
			const style = document.createElement('style');
			document.head.appendChild(style);
			layer(c).appendChild(e);
			const ed = { e, c, style, multiline, focusing: false };
			editors.set(h, ed);
			// (a layer of the window's where the page's are its: WebViews' EDITOR | h)
			slotted.set(EDITOR | h, e);
			const mods = (ev) => (ev.shiftKey ? 1 : 0) | (ev.ctrlKey ? 2 : 0) | (ev.altKey ? 4 : 0) | (ev.metaKey ? 8 : 0);
			e.addEventListener('input', () => queue([h, 1, e.selectionStart ?? 0, e.selectionEnd ?? 0, e.value]));
			e.addEventListener('focus', () => ed.focusing || queue([h, 2, 0, 0, 0]));
			e.addEventListener('blur', () => ed.focusing || queue([h, 3, 0, 0, 0]));
			e.addEventListener('keydown', (ev) => {
				const k = EDITOR_KEYS[ev.key];
				if (!k || ev.isComposing || (multiline && k !== 0xff09 && k !== 0xff1b)) return;
				ev.preventDefault();
				queue([h, 4, k, mods(ev), 0]);
			});
			return h;
		},
		editor_text(h, text, start, end) {
			const ed = editors.get(h);
			ed.e.value = host.string(text);
			if (document.activeElement === ed.e) ed.e.setSelectionRange(start, end);
		},
		editor_select(h, start, end) {
			const ed = editors.get(h);
			if (document.activeElement === ed.e && (ed.e.selectionStart !== start || ed.e.selectionEnd !== end)) ed.e.setSelectionRange(start, end);
		},
		// a phone's keyboard for it: inputmode (the input's type stays text:
		// an email's or a number's has no selection to set)
		editor_kind(h, keyboard, enter, capitalize, autocorrect) {
			const ed = editors.get(h), e = ed.e, k = host.string(keyboard), enterkey = host.string(enter);
			e.inputMode = MODES[k] ?? k;
			if (enterkey === 'default') e.removeAttribute('enterkeyhint');
			else e.setAttribute('enterkeyhint', enterkey);
			e.setAttribute('autocapitalize', host.string(capitalize));
			e.setAttribute('autocorrect', autocorrect ? 'on' : 'off');
			e.spellcheck = !!autocorrect;
		},
		// its place: the window's pixels (the canvas's buffer over its pixel
		// ratio: the device's, at most run's option maxPixelRatio, as os's),
		// scaled as the canvas is shown (a page may show it smaller), in the
		// canvas's layer
		editor_place(h, x, y, w, hh, shown) {
			const ed = editors.get(h), r = ed.c.getBoundingClientRect();
			const ratio = Math.min(devicePixelRatio, host.options.maxPixelRatio ?? Infinity);
			const k = r.width / Math.max(1, Math.round((ed.c.hxmcBuf ?? ed.c).width / ratio));
			const s = ed.e.style;
			layer(ed.c).fit();
			s.display = shown ? '' : 'none';
			s.left = x * k + 'px';
			s.top = y * k + 'px';
			s.width = w + 'px';
			s.height = hh + 'px';
			s.transformOrigin = '0 0';
			s.transform = Math.abs(k - 1) < 1e-3 ? '' : 'scale(' + k + ')';
		},
		editor_style(h, css, placeholder, placeholderColor, secret) {
			const ed = editors.get(h);
			ed.e.style.cssText = ed.e.style.cssText.replace(/(font|line-height|color|text-align):[^;]*;/g, '') + host.string(css);
			ed.e.placeholder = host.string(placeholder);
			ed.style.textContent = '#' + ed.e.id + '::placeholder{color:' + host.string(placeholderColor) + ';opacity:1}';
			if (!ed.multiline) ed.e.type = secret ? 'password' : 'text';
		},
		// the page's focus given, or taken back for the canvas
		editor_focus(h, on) {
			const ed = editors.get(h);
			ed.focusing = true;
			if (on) ed.e.focus({ preventScroll: true });
			else if (document.activeElement === ed.e) ed.c.focus({ preventScroll: true });
			ed.focusing = false;
		},
		editor_dispose(h) {
			const ed = editors.get(h);
			if (!ed) return;
			slotted.delete(EDITOR | h);
			if (document.activeElement === ed.e) ed.c.focus({ preventScroll: true });
			ed.e.remove();
			ed.style.remove();
			editors.delete(h);
		},
		// the next event into p (five Int32: the handle, the kind, its values); 0: none
		editor_event(p) {
			const ev = editorEvents.shift();
			if (!ev) return 0;
			new Int32Array(host.memory().buffer, p, 5).set(ev);
			return 1;
		},
		// the scrollers' changes (web.Scroll's JSON: the ui's width; views by
		// id, their geometry g (parent, box, content in ui points, axes,
		// bars, covered) and offsets o when they changed; r: the ids gone)
		scroll_update(canvas, json) {
			const c = host.handles.get(canvas);
			if (!c) return;
			const u = JSON.parse(host.string(json)), l = scrollLayer(c);
			let views = scrollers.get(canvas);
			if (!views) scrollers.set(canvas, (views = new Map()));
			l.fit();
			const k = l.getBoundingClientRect().width / Math.max(1, u.w);
			for (const id of u.r) {
				views.get(id)?.e.remove();
				views.delete(id);
			}
			for (const v of u.v) {
				let s = views.get(v.i);
				if (!s) {
					const e = document.createElement('div'), spacer = document.createElement('div');
					spacer.style.cssText = 'position:absolute;left:0;top:0;';
					e.appendChild(spacer);
					s = { e, spacer, id: v.i, k };
					e.hxmcScroller = true;
					e.addEventListener('scroll', () => {
						// (the program's own scroll told back, a frame late: not a scroll of the page's, which would
						// stop the program's glide where it was a frame ago)
						if (s.setX !== undefined && Math.abs(e.scrollLeft - s.setX) <= 1 && Math.abs(e.scrollTop - s.setY) <= 1) return;
						// (its own scroll: the offsets in ui points, 1/256ths)
						send('scrolled', [s.id, Math.round(e.scrollLeft / s.k * 256), Math.round(e.scrollTop / s.k * 256)]);
					}, { passive: true });
					views.set(v.i, s);
				}
				if (v.g) {
					const [parent, x, y, w, h, cw, ch, axes, bars, covered] = v.g, e = s.e;
					s.k = k;
					e.style.cssText = 'position:absolute;margin:0;padding:0;border:0;background:transparent;overscroll-behavior:auto;' +
						'left:' + x * k + 'px;top:' + y * k + 'px;width:' + w * k + 'px;height:' + h * k + 'px;' +
						'overflow-x:' + (axes & 1 ? 'auto' : 'hidden') + ';overflow-y:' + (axes & 2 ? 'auto' : 'hidden') + ';' +
						'touch-action:' + (axes === 3 ? 'pan-x pan-y' : axes & 1 ? 'pan-x' : 'pan-y') + ';' +
						// (its scrollbars helder's, drawn in order with the tree; Safari before 18.2 knows no scrollbar-width)
						'pointer-events:' + (covered ? 'none' : 'auto') + ';scrollbar-width:none;';
					e.classList.add('hxmc-nobar');
					s.bars = !!bars;
					showBars(s);
					e.style.clipPath = s.clip ?? '';
					s.spacer.style.width = cw * k + 'px';
					s.spacer.style.height = ch * k + 'px';
					// (appended once, in paint order: a later one over an earlier; moved, a scroller would lose its offsets)
					const into = parent ? views.get(parent)?.e ?? l : l;
					if (e.parentNode !== into) into.appendChild(e);
				}
				// the popups over it left out of it (clip-path: neither drawn, its scrollbar with it, nor hit there):
				// the page draws it over the canvas, and so over what the tree draws above it
				if (v.c) {
					s.covers = v.c;
					cover(s, l);
				}
				if (v.o) {
					s.e.scrollLeft = v.o[0] * k;
					s.e.scrollTop = v.o[1] * k;
					// (as the page rounded it: what its scroll event will say)
					s.setX = s.e.scrollLeft;
					s.setY = s.e.scrollTop;
				}
			}
		},
		// the next scroll into p (three Int32: the view's id, its offsets in 1/256 ui points); 0: none
		scroll_event(p) {
			const ev = scrolled.shift();
			if (!ev) return 0;
			new Int32Array(host.memory().buffer, p, 3).set(ev);
			return 1;
		},
		// the next action into p (two Int32: the node id, the AccessAction); 0: none
		access_action(p) {
			const a = actions.shift();
			if (!a) return 0;
			new Int32Array(host.memory().buffer, p, 2).set(a);
			return 1;
		},
	};
	// the window's layers (src/helder/ui/layers/web/Layers.hx): the bitmaps
	// read from the canvas since the last update, then each update once its
	// bitmaps are read, in order, to the page (layers_apply)
	let snaps = [], updates = Promise.resolve();
	hxmc_ui.layers_alpha = (canvas) => (host.handles.get(canvas).hxmcAlpha = true);
	hxmc_ui.layers_reading = () => (host.gfx?.reading?.() ? 1 : 0);
	// a node's system layer (WebSample's): a canvas of the page, by number;
	// a frame shown on it read into an ImageBitmap here (the browser's
	// VideoFrame, or a <video>'s), shown on the page
	let slotIds = 0;
	const page = (name) => (host.page ? host.page.forward('hxmc_ui', name, '') : hxmc_ui[name]);
	hxmc_ui.layers_slot = (canvas) => {
		const id = ++slotIds;
		page('layers_slot_make')(canvas, id);
		return id;
	};
	hxmc_ui.layers_slot_fit = (canvas, id, fit) => page('layers_slot_set')(canvas, id, fit, []);
	hxmc_ui.layers_slot_free = (canvas, id) => page('layers_slot_set')(canvas, id, -1, []);
	hxmc_ui.layers_slot_frame = (canvas, id, h) => {
		const o = h ? host.handles.get(h) : null;
		if (!o) return page('layers_slot_set')(canvas, id, -2, []);
		updates = updates.then(() => createImageBitmap(o.bitmap)).then((b) => page('layers_slot_set')(canvas, id, -3, [b]), () => {});
	};
	// (the page half's: each slot's canvas, by number)
	const slotted = new Map();
	hxmc_ui.layers_slot_make = (canvas, id) => {
		const e = document.createElement('canvas');
		e.style.cssText = 'position:absolute;pointer-events:none;object-fit:contain;display:none;';
		e.hxmcContext = e.getContext('bitmaprenderer');
		slotted.set(id, e);
	};
	// (fit: ImageFit (Fill, Contain, Cover, None); -1 gone, -2 nothing shown, -3 the bitmap shown)
	hxmc_ui.layers_slot_set = (canvas, id, fit, bitmaps) => {
		const e = slotted.get(id);
		if (!e) return;
		if (fit === -1) {
			e.remove();
			slotted.delete(id);
		} else if (fit === -2) {
			e.hxmcContext.transferFromImageBitmap(null);
		} else if (fit === -3) {
			e.width = bitmaps[0].width;
			e.height = bitmaps[0].height;
			e.hxmcContext.transferFromImageBitmap(bitmaps[0]);
		} else e.style.objectFit = ['fill', 'contain', 'cover', 'none'][fit] ?? 'contain';
	};
	// (WebGPU: the canvas's texture now copied on the GPU into a scratch
	// OffscreenCanvas of the same device, its bitmap taken at once: what a
	// canvas element gives createImageBitmap mid-task differs by version,
	// Chromium 141's not the texture drawn; WebGL2: the canvas as it is now)
	let scratch = null;
	const snap = (c, w, h) => {
		const device = host.gfx?.backend === 'webgpu' ? host.gfx.device : null;
		if (!device) return createImageBitmap(c, 0, 0, w, h);
		const t = c.getContext('webgpu').getCurrentTexture();
		if (!scratch || scratch.format !== t.format) {
			scratch = { canvas: new OffscreenCanvas(w, h), format: t.format };
			scratch.context = scratch.canvas.getContext('webgpu');
			scratch.context.configure({ device, format: t.format, alphaMode: 'premultiplied', usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT });
		}
		const s = scratch.canvas;
		if (s.width !== w) s.width = w;
		if (s.height !== h) s.height = h;
		const e = device.createCommandEncoder();
		e.copyTextureToTexture({ texture: t }, { texture: scratch.context.getCurrentTexture() }, [w, h]);
		device.queue.submit([e.finish()]);
		return Promise.resolve(s.transferToImageBitmap());
	};
	hxmc_ui.layers_snap = (canvas, w, h) => snaps.push(snap(host.handles.get(canvas), w, h)) - 1;
	hxmc_ui.layers_update = (canvas, json) => {
		// (when: its moving layers' animations start from this moment, the page's time)
		const list = snaps, u = host.string(json), at = performance.timeOrigin + performance.now();
		snaps = [];
		const apply = host.page ? host.page.forward('hxmc_ui', 'layers_apply', '') : hxmc_ui.layers_apply;
		updates = updates.then(() => Promise.all(list)).then((bitmaps) => apply(canvas, u, bitmaps, at), (e) => console.error('helder.ui: a layer not read:', e));
	};
	// the page half: each layer a box of canvases (its tiles, bitmaprenderer's),
	// a scroller's content in its scroll view's spacer (scrolled by the
	// browser), the others in the layer of scroll views, stacked by z
	const layered = new Map();
	hxmc_ui.layers_apply = (canvas, json, bitmaps, at) => {
		const c = host.handles.get(canvas);
		// (its bitmaps read after the canvas went, a preview closed: nothing to draw them on)
		if (!c) {
			for (const b of bitmaps) b?.close?.();
			return;
		}
		const u = JSON.parse(json), l = scrollLayer(c), views = scrollers.get(canvas);
		let all = layered.get(canvas);
		if (!all) layered.set(canvas, (all = new Map()));
		// (CSS pixels a point)
		const k = (c.getBoundingClientRect().width / Math.max(1, (c.hxmcBuf ?? c).width)) * u.s, px = k / u.s;
		for (const id of u.r) {
			if (!all.get(id)?.slot) all.get(id)?.e.remove();
			all.delete(id);
		}
		const seen = new Set();
		for (const v of u.l) {
			seen.add(v.i);
			// (a node's system layer: its canvas at its box, cut by its clip, in its scroll view's content where its scroller's is a layer)
			if (v.s) {
				const e = slotted.get(v.s), s = v.v ? views?.get(v.v) : null, into = s ? s.spacer : l;
				if (!e) continue;
				if (e.parentNode !== into) into.appendChild(e);
				// (an editor: its box in points scaled to the page's, as editor_place has it, its font in points)
				const st = e.style, [x0, y0, x1, y1] = v.c, q = e.tagName === 'CANVAS' ? k : 1;
				st.display = v.on ? '' : 'none';
				st.left = v.x * k + 'px';
				st.top = v.y * k + 'px';
				st.width = v.w * q + 'px';
				st.height = v.h * q + 'px';
				if (q === 1) {
					st.transformOrigin = '0 0';
					st.transform = Math.abs(k - 1) < 1e-3 ? '' : 'scale(' + k + ')';
				}
				st.zIndex = s ? 1 : v.z;
				st.clipPath = `inset(${(y0 - v.y) * q}px ${(v.x + v.w - x1) * q}px ${(v.y + v.h - y1) * q}px ${(x0 - v.x) * q}px)`;
				all.set(v.i, { e, tiles: [], view: null, slot: true });
				continue;
			}
			let a = all.get(v.i);
			if (!a) {
				const e = document.createElement('div');
				e.style.cssText = 'position:absolute;pointer-events:none;overflow:hidden;';
				all.set(v.i, (a = { e, tiles: [], view: null }));
			}
			const s = v.v ? views?.get(v.v) : null, into = s ? s.spacer : l;
			if (a.e.parentNode !== into) into.appendChild(a.e);
			if (a.view !== s) {
				const old = a.view;
				if (a.view) {
					a.view.hosting = false;
					a.view.e.style.zIndex = '';
					cover(a.view, l);
				}
				a.view = s;
				if (s) {
					s.hosting = true;
					cover(s, l);
				}
				for (const t of [old, s]) if (t) showBars(t);
			}
			if (s) s.e.style.zIndex = v.z;
			const st = a.e.style;
			st.display = '';
			st.left = v.x * k + 'px';
			st.top = v.y * k + 'px';
			st.width = v.w * k + 'px';
			st.height = v.h * k + 'px';
			st.zIndex = s ? '' : v.z;
			// (a moving layer: its transform about the frame's origin, its opacity, from the program's samples a frame apart)
			if (v.m) {
				const kf = [];
				for (let i = 0; i < v.m.length; i += 7) {
					const m = v.m;
					kf.push({ transform: `matrix(${m[i]},${m[i + 1]},${m[i + 2]},${m[i + 3]},${m[i + 4] * px},${m[i + 5] * px})`, opacity: m[i + 6] });
				}
				st.transformOrigin = `${-v.x * k}px ${-v.y * k}px`;
				a.anim?.cancel();
				a.anim = null;
				st.transform = kf[kf.length - 1].transform;
				st.opacity = kf[kf.length - 1].opacity;
				if (kf.length > 1) {
					a.anim = a.e.animate(kf, { duration: (kf.length - 1) * 1000 / 60, fill: 'both' });
					a.anim.currentTime = Math.max(0, performance.timeOrigin + performance.now() - at);
				}
			}
			for (const [n, w, h, b] of v.t) {
				let t = a.tiles[n];
				if (!t) {
					t = a.tiles[n] = document.createElement('canvas');
					t.style.cssText = 'position:absolute;';
					t.hxmcContext = t.getContext('bitmaprenderer');
					a.e.appendChild(t);
				}
				t.width = w;
				t.height = h;
				t.hxmcContext.transferFromImageBitmap(bitmaps[b]);
				t.style.left = (n % v.c) * v.tw * px + 'px';
				t.style.top = Math.floor(n / v.c) * v.th * px + 'px';
				t.style.width = w * px + 'px';
				t.style.height = h * px + 'px';
			}
			for (const t of a.tiles.splice(v.n)) t?.remove();
		}
		for (const [id, a] of all) if (!seen.has(id)) a.e.style.display = 'none';
		for (const [id, a] of all) if (a.slot && !seen.has(id)) all.delete(id);
	};
	// the program in a worker: the page's calls forwarded, the page half's events queued here
	if (host.page) {
		for (const [k, sig] of Object.entries(PAGE)) hxmc_ui[k] = host.page.forward('hxmc_ui', k, sig);
		const create = hxmc_ui.editor_create;
		hxmc_ui.editor_create = (canvas, multiline) => {
			const h = nextEditor++;
			create(canvas, multiline, h);
			return h;
		};
		host.page.on('queue', (m) => m.mod === 'hxmc_ui' && lists[m.name].push(m.ev.map((x) => (typeof x === 'string' ? host.handles.add(x) : x))));
	}
	return { hxmc_ui };
}

// the calls the page runs for a program in a worker (os/imports.mjs's PAGE)
const PAGE = { access_update: 'ns', editor_create: '', editor_text: 'ns', editor_select: '', editor_kind: 'nsss', editor_place: '', editor_style: 'nsss',
	editor_focus: '', editor_dispose: '', scroll_update: 'ns' };

export { ui as page };
