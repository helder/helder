// Markup's words of audit F (helder.view.Vocabulary): rewrites ui's markup
// to them, in Haxe, TSX and the Markdown samples, so that it runs again
// after a rebase. On ui's elements (view, text, image..., view:button...):
// tags HTML's names without a prefix (view:button: button, field:textarea:
// textarea, glass-group: a view's glassSpacing, Video: video, a text's
// span, b and i: text, strong, em); attributes camel, the style properties
// CSS's names (grow: flexGrow, radius: borderRadius, direction:
// flexDirection, dir: direction), the others HTML's (readonly: readOnly),
// assistive technology's ARIA's (label: aria-label, hidden: aria-hidden);
// onClick onPress; a button's role="button" and focusable dropped. Then
// the code's style objects (style={{...}}, style: {...}, .set({...})) and
// Style's fields (n.style.grow). What it cannot decide is listed:
// buttons that now take the focus, onClick handlers that read the event.
//
//   node tools/markup.mjs [--dry] [path...]   (default: src apps examples tests docs, the READMEs)
import fs from 'node:fs';
import path from 'node:path';

const STYLE = {
	direction: 'flexDirection', wrap: 'flexWrap', justify: 'justifyContent', grow: 'flexGrow', shrink: 'flexShrink', basis: 'flexBasis',
	radius: 'borderRadius', shadow: 'boxShadow', italic: 'fontStyle', dir: 'direction', maxLines: 'lineClamp'
};
const ATTR = {
	...STYLE, fit: 'objectFit', autofocus: 'autoFocus', readonly: 'readOnly', maxlength: 'maxLength', spellcheck: 'spellCheck',
	inputmode: 'inputMode', autocomplete: 'autoComplete', enterkey: 'enterKeyHint', autocapitalize: 'autoCapitalize', autocorrect: 'autoCorrect',
	tabindex: 'tabIndex', htmlFor: 'for', label: 'aria-label', description: 'aria-description', checked: 'aria-checked',
	pressed: 'aria-pressed', selected: 'aria-selected', expanded: 'aria-expanded', level: 'aria-level', live: 'aria-live',
	multiselectable: 'aria-multiselectable', current: 'aria-current', invalid: 'aria-invalid', modal: 'aria-modal',
	valueNow: 'aria-valuenow', valueMin: 'aria-valuemin', valueMax: 'aria-valuemax', valueText: 'aria-valuetext',
	posInSet: 'aria-posinset', setSize: 'aria-setsize', hidden: 'aria-hidden'
};
// (<Video>'s props, now <video>'s attributes)
const VIDEO = {autoplay: 'autoPlay', rate: 'playbackRate', fit: 'objectFit', grow: 'flexGrow'};
// (the attributes that are booleans: helder.view.Vocabulary.BOOLEANS, and ARIA's that are)
const BOOLEANS = new Set(['hidden', 'disabled', 'required', 'autoFocus', 'focusable', 'selectable', 'dragRegion', 'instant', 'mirrored', 'readOnly',
	'spellCheck', 'autoCorrect', 'inspectable', 'zoom', 'transparent', 'backGesture', 'interactive', 'autoPlay', 'loop', 'muted', 'layer', 'aria-hidden',
	'aria-disabled', 'aria-checked', 'aria-pressed', 'aria-selected', 'aria-expanded', 'aria-modal', 'aria-invalid', 'aria-required',
	'aria-multiselectable', 'aria-busy', 'aria-readonly']);
// (the table's HTML names: helder.view.Vocabulary.TAGS)
const HTML = new Set(['button', 'nav', 'main', 'section', 'header', 'footer', 'article', 'aside', 'form', 'ul', 'ol', 'li', 'fieldset', 'p', 'h1', 'h2',
	'h3', 'h4', 'h5', 'h6', 'label', 'legend', 'a', 'strong', 'em', 'code', 'textarea']);
// (components whose props are a box's style: Scene, Sprites)
const BOXES = new Set(['Scene', 'Sprites']);
// (the style properties' names, old and new: what makes an object a style)
const STYLES = new Set([...Object.keys(STYLE), ...Object.values(STYLE), 'padding', 'margin', 'background', 'color', 'width', 'height', 'alignItems',
	'fontSize', 'fontWeight', 'borderWidth', 'borderColor', 'opacity', 'cursor', 'columnGap', 'rowGap', 'gap', 'minWidth', 'minHeight', 'overflow',
	'textAlign', 'position', 'display', 'ringWidth', 'ringColor', 'outlineStyle', 'textWrap', 'textOverflow', 'letterSpacing', 'lineHeight']);
// (a design file's Frame is a box of ui's: its attributes a view's)
const UI = new Set(['view', 'text', 'scroll', 'image', 'icon', 'field', 'glass', 'webview', 'glass-group', 'Video', 'Frame']);
const TEXTS = new Set(['text', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'label', 'legend', 'a', 'strong', 'em', 'code', 'span', 'b', 'i']);
// (directories whose literals are a page's renderer's: their DOM vocabulary kept)
const SKIP = ['tests/web', 'tests/view', 'site', 'src/helder/web', 'node_modules', 'bin', 'tests/typescript/definitions/reject', 'tests/typescript/reject'];

const args = process.argv.slice(2);
const dry = args.includes('--dry');
const roots = args.filter(a => !a.startsWith('--'));
const notes = [];
let changed = 0;

function camel(n) {
	return n.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
}

// a ui element's new attribute name (null: dropped), for tag (its new tag)
function attrName(name, tag, oldTag) {
	if (name.startsWith('data-') || name.startsWith('aria-') || name === '...') return name;
	if (oldTag === 'glass-group' && name === 'spacing') return 'glassSpacing';
	if (oldTag === 'Video' && VIDEO[name]) return VIDEO[name];
	if (name === 'html-for') return 'for';
	const c = camel(name);
	if (name === 'onClick') return 'onPress';
	return ATTR[c] ?? c;
}

// ---- a scanner of code: comments, strings and markup literals

function scanFile(src, lang) {
	const edits = [];
	const s = src;
	let i = 0;
	const isId = c => /[A-Za-z0-9_$]/.test(c);
	function prevSignificant(k) {
		let j = k - 1;
		while (j >= 0 && /\s/.test(s[j])) j--;
		return j;
	}
	function markupStart(k) {
		if (s[k] !== '<') return false;
		const n = s[k + 1];
		if (!(n === '>' || /[A-Za-z]/.test(n))) return false;
		const j = prevSignificant(k);
		if (j < 0) return true;
		// (a ui element first on its line: a statement of its own, TypeScript's without a semicolon)
		let ls = k - 1;
		while (ls >= 0 && (s[ls] === ' ' || s[ls] === '\t')) ls--;
		if ((ls < 0 || s[ls] === '\n') && /^<(view|text|scroll|image|icon|field|glass|webview|Video|glass-group)\b/.test(s.slice(k, k + 14))) return true;
		const c = s[j];
		if ('([{,=:?;!&|'.includes(c)) return c !== '=' || s[j - 1] !== '=' && s[j - 1] !== '!' && s[j - 1] !== '<' && s[j - 1] !== '>';
		if (c === '>' && (s[j - 1] === '-' || s[j - 1] === '=')) return true;
		// (a for's, an if's, a while's body: [for (x in xs) <view/>])
		if (c === ')') {
			let depth = 0, w = j;
			for (; w >= 0; w--) {
				if (s[w] === ')') depth++;
				else if (s[w] === '(' && --depth === 0) break;
			}
			let e = w - 1;
			while (e >= 0 && /\s/.test(s[e])) e--;
			let b = e;
			while (b >= 0 && isId(s[b])) b--;
			return ['for', 'if', 'while'].includes(s.slice(b + 1, e + 1));
		}
		if (isId(c)) {
			let w = j;
			while (w >= 0 && isId(s[w])) w--;
			const word = s.slice(w + 1, j + 1);
			// (after metadata: @:privateAccess <view/>)
			if (s[w] === ':' && s[w - 1] === '@') return true;
			return ['return', 'else', 'case', 'default', 'in', 'yield', 'await', 'do'].includes(word);
		}
		return false;
	}
	// code until end (a char) at depth 0; returns the index of end
	function code(k, end) {
		let depth = 0;
		while (k < s.length) {
			const c = s[k];
			if (c === '/' && s[k + 1] === '/') { k = s.indexOf('\n', k); if (k < 0) return s.length; continue; }
			if (c === '/' && s[k + 1] === '*') { k = s.indexOf('*/', k + 2); if (k < 0) return s.length; k += 2; continue; }
			if (c === '"' || c === "'" || c === '`') { k = str(k); continue; }
			if (c === '<' && lang !== 'ts' && markupStart(k)) { const e = element(k, null); k = e.end; continue; }
			if (c === '{' || c === '(' || c === '[') depth++;
			if (c === '}' || c === ')' || c === ']') {
				if (depth === 0 && c === end) return k;
				depth--;
			}
			k++;
		}
		return k;
	}
	function str(k) {
		const q = s[k];
		k++;
		while (k < s.length && s[k] !== q) {
			if (s[k] === '\\') k++;
			// (a template's or an interpolation's code)
			else if (q === '`' && s[k] === '$' && s[k + 1] === '{') { k = code(k + 2, '}'); }
			else if (q === "'" && lang === 'hx' && s[k] === '$' && s[k + 1] === '{') { k = code(k + 2, '}'); }
			k++;
		}
		return k + 1;
	}
	function readName(k) {
		let e = k;
		while (e < s.length && /[A-Za-z0-9_:.\-$]/.test(s[e])) e++;
		return e;
	}
	function skipSpace(k) {
		while (k < s.length) {
			if (/\s/.test(s[k])) { k++; continue; }
			if (s[k] === '/' && s[k + 1] === '/') { k = s.indexOf('\n', k); continue; }
			if (s[k] === '{' && s.startsWith('{/*', k)) { k = s.indexOf('*/}', k) + 3; continue; }
			if (s[k] === '/' && s[k + 1] === '*') { k = s.indexOf('*/', k) + 2; continue; }
			break;
		}
		return k;
	}
	// an element at k ('<'): its attributes and children, edits made; parent: the enclosing element
	function element(k, parent) {
		const start = k;
		if (s[k + 1] === '>') {
			let j = children(k + 2, '', {tag: '', newTag: '', parent});
			return {end: j};
		}
		const ns = k + 1, ne = readName(ns);
		const tag = s.slice(ns, ne);
		const el = {tag, start, attrs: [], parent, ui: false, newTag: tag};
		el.ui = isUi(tag, parent);
		if (el.ui) el.newTag = newTag(tag, parent);
		el.box = BOXES.has(tag);
		let j = ne;
		while (true) {
			j = skipSpace(j);
			if (j >= s.length) return {end: j};
			// (a view or a text with an href: HTML's a, a link)
			if ((s[j] === '>' || s[j] === '/') && el.ui && (tag === 'view' || tag === 'text') && el.attrs.some(a => a.name === 'href')) el.newTag = 'a';
			if (s[j] === '/' && s[j + 1] === '>') { j += 2; break; }
			if (s[j] === '>') { j = children(j + 1, tag, el); break; }
			if (s[j] === '{') {
				const e = code(j + 1, '}');
				el.attrs.push({name: '...', start: j, end: e + 1});
				j = e + 1;
				continue;
			}
			const as = j, ae = readName(j);
			if (ae === as) { j++; continue; }
			const a = {name: s.slice(as, ae), start: as, nameEnd: ae, end: ae, value: null};
			j = skipSpace(ae);
			if (s[j] === '=') {
				j = skipSpace(j + 1);
				if (s[j] === '"' || s[j] === "'") {
					const q = s[j], e = s.indexOf(q, j + 1);
					a.value = {kind: 'static', start: j, end: e + 1, text: s.slice(j + 1, e)};
					j = e + 1;
				} else if (s[j] === '{') {
					const e = code(j + 1, '}');
					a.value = {kind: 'expr', start: j, end: e + 1, text: s.slice(j + 1, e)};
					j = e + 1;
				}
				a.end = j;
			}
			el.attrs.push(a);
		}
		if (el.ui) rewrite(el);
		// (HTML's names, ui's already or a page's: their booleans given as strings alone)
		else if (HTML.has(tag)) for (const a of el.attrs)
			if (BOOLEANS.has(a.name) && a.value && a.value.kind === 'static' && (a.value.text === 'true' || a.value.text === 'false'))
				edits.push([a.start, a.end, `${a.name}={${a.value.text}}`]);
		// (a component that is a box of ui's: its style props' names as an element's)
		if (el.box) for (const a of el.attrs) if (STYLE[a.name] && a.name !== 'dir') edits.push([a.start, a.nameEnd, STYLE[a.name]]);
		return {end: j};
	}
	function children(k, tag, el) {
		while (k < s.length) {
			const c = s[k];
			if (c === '<' && s[k + 1] === '/') {
				const ns = k + 2, ne = readName(ns);
				if (el && el.ui && el.newTag !== el.tag && s.slice(ns, ne) === el.tag) edits.push([ns, ne, el.newTag]);
				const e = s.indexOf('>', ne);
				return e + 1;
			}
			if (c === '<') { k = element(k, el).end; continue; }
			if (c === '{') { k = code(k + 1, '}') + 1; continue; }
			k++;
		}
		return k;
	}
	function isUi(tag, parent) {
		if (UI.has(tag) || /^(view|text|field):/.test(tag)) return true;
		// (a text's spans: span, b, i)
		if (['span', 'b', 'i'].includes(tag) && parent && parent.ui && TEXTS.has(parent.newTag)) return true;
		return false;
	}
	function newTag(tag, parent) {
		if (tag === 'glass-group') return 'view';
		if (tag === 'Video') return 'video';
		if (tag === 'span') return 'text';
		if (tag === 'b') return 'strong';
		if (tag === 'i') return 'em';
		const m = /^(view|text|field):(.*)$/.exec(tag);
		if (m) return m[2];
		return tag;
	}
	function line(k) {
		return s.slice(0, k).split('\n').length;
	}
	function rewrite(el) {
		const ts = el.start + 1;
		if (el.newTag !== el.tag) edits.push([ts, ts + el.tag.length, el.newTag]);
		const button = el.newTag === 'button';
		let focusable = false;
		for (const a of el.attrs) {
			if (a.name === '...') continue;
			if (button && a.name === 'role' && a.value && a.value.kind === 'static' && a.value.text === 'button') {
				drop(a);
				continue;
			}
			if (button && a.name === 'focusable') {
				focusable = true;
				if (!a.value || a.value.text === 'true') { drop(a); continue; }
			}
			if (a.name === 'onClick') {
				const t = a.value ? a.value.text : '';
				// (a handler that reads its event: a person decides)
				if (/^\s*\(?\s*\w+\s*(:[^)]*)?\)?\s*(->|=>)/.test(t) && !/^\s*\(\s*\)/.test(t)) {
					const v = /^\s*\(?\s*(\w+)/.exec(t)[1];
					if (v !== '_' && new RegExp('\\b' + v + '\\.(?!stop\\b|preventDefault\\b|defaultPrevented\\b)').test(t)) notes.push(`${file}:${line(a.start)}: onClick reads its event (${v}.): onPress or onPointerUp?`);
				}
			}
			let n = attrName(a.name, el.newTag, el.tag);
			// (direction the flex one where its value is a flex direction, or the element
			// is written in the old words; else the text's already, as a run before made it)
			if (a.name === 'direction' && !(a.value && /^(row|column|row-reverse|column-reverse)$/.test(a.value.text))
				&& !(a.value && /\b(Row|Column|RowReverse|ColumnReverse|Direction)\b/.test(a.value.text))
				&& !el.attrs.some(b => b !== a && b.name !== '...' && attrName(b.name, el.newTag, el.tag) !== b.name)) n = 'direction';
			// (italic, a flag: fontStyle's italic)
			if (a.name === 'italic') {
				if (!a.value || a.value.text === 'true') { edits.push([a.start, a.end, 'fontStyle="italic"']); continue; }
				if (a.value.kind === 'expr') {
					const italic = lang === 'hx' ? 'Italic' : '"italic"', normal = lang === 'hx' ? 'Normal' : '"normal"';
					edits.push([a.start, a.end, `fontStyle={(${a.value.text}) ? ${italic} : ${normal}}`]);
					continue;
				}
			}
			// (hidden assistive technology's in the old words, HTML's not rendered in the new: aria-hidden
			// only where the element is written in the old ones, else as it is)
			if (a.name === 'hidden' && !el.attrs.some(b => b !== a && b.name !== '...' && b.name !== 'hidden' && attrName(b.name, el.newTag, el.tag) !== b.name)
				&& el.newTag === el.tag) n = 'hidden';
			else if (a.name === 'hidden') notes.push(`${file}:${line(a.start)}: hidden is now aria-hidden; HTML's hidden is not rendered: which is meant?`);
			// (a boolean as a string: its value the boolean, spellCheck={false})
			if (BOOLEANS.has(n) && a.value && a.value.kind === 'static' && (a.value.text === 'true' || a.value.text === 'false')) {
				edits.push([a.start, a.end, `${n}={${a.value.text}}`]);
				continue;
			}
			if (n !== a.name) edits.push([a.start, a.nameEnd, n]);
			// (a style object: its keys)
			if (n === 'style' && a.value && a.value.kind === 'expr') styleKeys(a.value.start + 1, a.value.end - 1);
		}
		if (button && !focusable) notes.push(`${file}:${line(el.start)}: <button> takes the focus now (it did not): focusable={false} if it should not`);
	}
	function drop(a) {
		let st = a.start;
		while (st > 0 && (s[st - 1] === ' ' || s[st - 1] === '\t')) st--;
		edits.push([st, a.end, '']);
	}
	// the keys of the object literals in code from k to e that are style properties' old names
	function styleKeys(k, e) {
		const text = s.slice(k, e);
		const re = /([{,]\s*)(direction|wrap|justify|grow|shrink|basis|radius|shadow|italic|dir|maxLines)(\s*:)/g;
		let m;
		while ((m = re.exec(text))) {
			const at = k + m.index + m[1].length;
			// (italic: true, fontStyle's Italic)
			const flag = m[2] === 'italic' ? /^\s*:\s*(true|false)\b/.exec(s.slice(at + 6)) : null;
			if (flag) {
				const v = flag[1] === 'true' ? (lang === 'hx' ? 'Italic' : '"italic"') : (lang === 'hx' ? 'Normal' : '"normal"');
				edits.push([at, at + 6 + flag[0].length, 'fontStyle: ' + v]);
				continue;
			}
			// (direction the text's already: as it is)
			if (m[2] === 'direction' && !/^direction\s*:\s*(?:Row|Column|RowReverse|ColumnReverse|Direction\.\w+|'(?:row|column|row-reverse|column-reverse)'|\"(?:row|column|row-reverse|column-reverse)\")/.test(s.slice(at))) continue;
			edits.push([at, at + m[2].length, STYLE[m[2]]]);
		}
	}
	// (an object's keys at its top level, from its '{' at k to its '}' at e)
	function topKeys(k, e) {
		const keys = [];
		let depth = 0;
		for (let i = k; i < e; i++) {
			const c = s[i];
			if (c === '{' || c === '(' || c === '[') depth++;
			else if (c === '}' || c === ')' || c === ']') depth--;
			if (depth === 1 && (c === '{' || c === ',')) {
				const m = /^[{,]\s*(\w+)\s*:/.exec(s.slice(i, i + 40));
				if (m) keys.push(m[1]);
			}
		}
		return keys;
	}
	// (an object's keys at every depth)
	function allKeys(k, e) {
		const keys = [], re = /[{,]\s*(\w+)\s*:/g;
		re.lastIndex = k;
		let m;
		while ((m = re.exec(s)) && m.index < e) keys.push(m[1]);
		return keys;
	}
	let file = currentFile;
	// the file's code: its literals rewritten, then its style objects
	code(0, null);
	// (code outside markup: n.style.grow, style: {...}, .set({...}))
	const re = /\.style\.(direction|wrap|justify|grow|shrink|basis|radius|shadow|italic|dir|maxLines)\b/g;
	let m;
	while ((m = re.exec(s))) {
		const at = m.index + '.style.'.length;
		if (inEdits(edits, at)) continue;
		if (m[1] === 'italic') {
			const rest = /^italic\s*=\s*(true|false)\b/.exec(s.slice(at));
			if (rest) {
				edits.push([at, at + rest[0].length, 'fontStyle = ' + (rest[1] === 'true' ? (lang === 'hx' ? 'Italic' : '"italic"') : (lang === 'hx' ? 'Normal' : '"normal"'))]);
				continue;
			}
		}
		// (direction the text's already, Ltr or Rtl: as it is)
		if (m[1] === 'direction' && !/^direction\s*(?:=|==|!=)\s*(?:Row|Column|RowReverse|ColumnReverse|Direction\.\w+|'(?:row|column|row-reverse|column-reverse)'|\"(?:row|column|row-reverse|column-reverse)\")/.test(s.slice(at))) continue;
		edits.push([at, at + m[1].length, STYLE[m[1]]]);
	}
	// (and a look's parts: an object a function of the tokens gives, t -> {...})
	const objects = /(\bstyle\s*:\s*|\.set\(\s*|\bstyle\s*=\s*|(?:\b\w+|\))\s*(?:->|=>)\s*\(?)\{/g;
	while ((m = objects.exec(s))) {
		const open = m.index + m[0].length - 1;
		let depth = 0, k = open;
		for (; k < s.length; k++) {
			if (s[k] === '{') depth++;
			else if (s[k] === '}' && --depth === 0) break;
		}
		// (a function's object only where it is a style: a key of one at its top, not a block's)
		// (a function's object only where it is one, not a block, holding a style: a recipe's parts' too)
		if (/->|=>/.test(m[1]) && !(/^\{\s*(\w+|"[^"]*"|'[^']*')\s*:/.test(s.slice(open, open + 80)) && allKeys(open, k).some(key => STYLES.has(key) && key !== 'dir'))) continue;
		const before = edits.length;
		styleKeys(open, k + 1);
		// (only those no literal's attribute made already)
		const added = edits.splice(before);
		for (const ed of added) if (!inEdits(edits, ed[0])) edits.push(ed);
	}
	// (the samples in its comments: each line's markup, as code)
	if (lang !== 'ts') {
		const comment = /^([ \t]*\/\/ ?)(.*<(?:view|text|scroll|image|icon|field|glass|webview|Video|glass-group|Scene|Sprites)\b.*)$/gm;
		while ((m = comment.exec(s))) {
			const at = m.index + m[1].length;
			for (const [a, b, t] of scanFile(m[2], lang)) edits.push([at + a, at + b, t]);
		}
	}
	return edits;
}

function inEdits(edits, at) {
	return edits.some(e => e[0] <= at && at < e[1]);
}

function apply(src, edits) {
	const sorted = [...new Map(edits.map(e => [e[0] + ':' + e[1], e])).values()].sort((a, b) => b[0] - a[0]);
	let out = src, last = Infinity;
	for (const [a, b, t] of sorted) {
		if (b > last) continue;
		out = out.slice(0, a) + t + out.slice(b);
		last = a;
	}
	return out;
}

let currentFile = '';

function markdown(src) {
	// (a sample's code, ```haxe or ```ts...)
	// (and a bare one of markup: a design file's)
	return src.replace(/(```([^\n]*)\n)([\s\S]*?)(```)/g, (all, open, info, body, close) => {
		const kind = info.split(' ')[0];
		if (!['haxe', 'hx', 'ts', 'tsx', 'helder'].includes(kind) && !(kind === '' && /^\s*</.test(body))) return all;
		const lang = kind === 'haxe' || kind === 'hx' ? 'hx' : 'tsx';
		return open + apply(body, scanFile(body, lang)) + close;
	});
}

// (a transition names CSS's properties: Style's old shadow is box-shadow, else it silently no longer eases)
function transitions(src) {
	return src.replace(/(\btransition\s*[=:]\s*\{?\s*["'])([^"'\n]*)/g, (m, open, list) =>
		open + list.replace(/(^|[\s,])shadow\b/g, '$1box-shadow'));
}

function visit(p) {
	if (SKIP.some(d => p === d || p.startsWith(d + '/'))) return;
	if (path.basename(p) === 'node_modules') return;
	const st = fs.lstatSync(p);
	if (st.isSymbolicLink()) return;
	if (st.isDirectory()) {
		for (const f of fs.readdirSync(p).sort()) visit(path.join(p, f));
		return;
	}
	const ext = path.extname(p);
	if (!['.hx', '.tsx', '.ts', '.md', '.helder'].includes(ext) || p.endsWith('.d.ts')) return;
	if (p === 'tools/markup.mjs') return;
	currentFile = p;
	const src = fs.readFileSync(p, 'utf8');
	const out = transitions(ext === '.md' ? markdown(src) : apply(src, scanFile(src, ext === '.hx' ? 'hx' : ext === '.tsx' || ext === '.helder' ? 'tsx' : 'ts')));
	if (out !== src) {
		changed++;
		if (!dry) fs.writeFileSync(p, out);
	}
}

for (const r of roots.length > 0 ? roots : ['src', 'apps', 'examples', 'tests', 'docs', 'README.md', 'CONTRIBUTING.md']) visit(r);
for (const n of notes) console.log(n);
console.log(`${changed} files ${dry ? 'would change' : 'changed'}`);
