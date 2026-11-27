package helder.ui.flow;

import haxe.ds.Vector;
import haxe.io.Bytes;
import helder.ui.box.Box;
import helder.text.Bidi;
import helder.ui.flow.InlineValues;

// One inline formatting context's content, what does not depend on the
// width it is laid out at: built from the box tree's items in order
// (addText, openBox, closeBox, addAtomic, addBreak, addFloat, addAbspos),
// then finish(): CSS Text 3's white-space processing (phase I: spaces
// collapsed across the items, segment breaks made spaces or removed, a
// line's leading spaces dropped at the start and after a forced break),
// text-transform, the bidi levels (UAX #9 over each paragraph, inline
// boxes as embeddings or isolates per unicode-bidi, a forced break a
// paragraph's end), the break opportunities (LineBreaks; white-space's
// wrapping by the item before each, as Blink's line breaker has it; soft
// hyphens per hyphens) and the pieces the line builder places: each word, run of
// spaces and tab shaped once (InlineShaper), each item that is not text a
// piece of its own. Laid out again at another width nothing is shaped again.
//
// The processed text is `text`; items index it (start to end), each from
// one source (a text box for text: sourceOffset maps each unit of the
// text back to its offset in that box's text).
class InlineContent {
	public final root:InlineStyle;
	public final fonts:InlineFonts;
	public final shaper:InlineShaper;
	// the processed text
	public var text(default, null) = "";
	// the root's direction: 0 left to right, 1 right to left (plaintext: paragraphDirection)
	public var direction(default, null) = 0;
	// whether bidi levels were resolved (something right to left, an embedding, an rtl root): else all 0
	public var bidi(default, null) = false;
	// (something right to left in it: text, the root, a box's direction)
	var rtl = false;
	public var items(default, null) = 0;
	public var pieces(default, null) = 0;
	public var finished(default, null) = false;
	// the block's space advance, tabs' least width's double (Blink's)
	public var tabSpace(default, null) = 0.0;
	// the styles of the items (styles[0]: the root's)
	public final styles:Array<InlineStyle> = [];

	// --- items ---
	var iKind = new Vector<Int>(16);
	var iStart = new Vector<Int>(16);
	var iEnd = new Vector<Int>(16);
	var iStyle = new Vector<Int>(16);
	var iBox = new Vector<Int>(16);
	var iMatch = new Vector<Int>(16);
	var iLevel = new Vector<Int>(16);
	var iFont = new Vector<Int>(16);
	// (an atomic's sizes, the items' spacing: let go where every item's is 0, compact())
	var iWidth:Null<Vector<Float>> = new Vector<Float>(16);
	var iHeight:Null<Vector<Float>> = new Vector<Float>(16);
	var iBaseline:Null<Vector<Float>> = new Vector<Float>(16);
	var iSource = new Vector<Box>(16);
	// (an Open's: the box around it and its depth; every item's: its style's flags, spacing)
	var iParent = new Vector<Int>(16);
	var iDepth = new Vector<Int>(16);
	var iFlags = new Vector<Int>(16);
	var iLetter:Null<Vector<Float>> = new Vector<Float>(16);
	var iWord:Null<Vector<Float>> = new Vector<Float>(16);
	// (the bidi paragraphs: each one's first unit and base level)
	final paragraphs:Array<Int> = [];
	// (each item's isolate initiator's or PDI's level: an Open's or Close's of an isolating box; -1 else)
	final isolates:Array<Int> = [];

	// --- units: each UTF-16 unit of the text ---
	// (each unit's offset in its item's source, as it is built; then, compact(), only where they don't go one
	// unit to the next (a space collapsed, an item's start, a transform's two units of one): unit, offset pairs)
	var offsets:Null<Vector<Int>> = new Vector<Int>(64);
	var jumps:Null<Vector<Int>> = null;
	var levels = Bytes.alloc(64);
	var breaks = Bytes.alloc(65);

	// --- pieces ---
	// (a byte each: a kind, an opportunity)
	var pKind = Bytes.alloc(16);
	var pStart = new Vector<Int>(16);
	var pEnd = new Vector<Int>(16);
	var pItem = new Vector<Int>(16);
	var pBreak = Bytes.alloc(16);
	var pEntry = new Vector<Int>(16);
	var pWidth = new Vector<Float>(16);
	var shapedIn = -1;

	// (what the builder was given, before finish processes it)
	var raw:Array<RawItem> = [];

	public function new(root:InlineStyle, ?fonts:InlineFonts, ?shaper:InlineShaper) {
		this.root = root;
		this.fonts = fonts == null ? InlineFonts.shared : fonts;
		// (the fonts' own: the shaped-word cache is keyed by their sets' numbers)
		this.shaper = shaper == null ? this.fonts.shaper : shaper;
		styles.push(root);
	}

	// --- building ---

	// a text box's text (from sourceOffset in it): finish processes it
	public function addText(text:String, style:InlineStyle, ?source:Box, sourceOffset = 0)
		push(Text, text, style, source, sourceOffset);

	// an inline box's start (its margin, border and padding at its start: style's)
	public function openBox(style:InlineStyle, ?source:Box)
		push(Open, "", style, source, 0);

	// its end
	public function closeBox(?source:Box)
		push(Close, "", null, source, 0);

	// an inline-block, replaced element or inline flex or grid, laid out:
	// its border box's width and height, its baseline from its top (NaN: none,
	// its bottom margin edge then); style's margins around it
	public function addAtomic(width:Float, height:Float, baseline:Float, style:InlineStyle, ?source:Box) {
		var r = push(Atomic, "￼", style, source, 0);
		r.width = width;
		r.height = height;
		r.baseline = baseline;
	}

	// a forced break (<br>; style: its own, else its box's)
	public function addBreak(?source:Box, ?style:InlineStyle)
		push(Break, "\n", style, source, 0);

	// a float's or absolutely positioned box's place (its static position)
	public function addFloat(?source:Box)
		push(Float, "", null, source, 0);

	public function addAbspos(?source:Box)
		push(Abspos, "", null, source, 0);

	function push(kind:InlineItem, text:String, style:Null<InlineStyle>, source:Null<Box>, offset:Int):RawItem {
		if (finished) throw new haxe.Exception("InlineContent: finished");
		var r = new RawItem(kind, text, style == null ? -1 : styleIndex(style), source, offset);
		raw.push(r);
		return r;
	}

	function styleIndex(s:InlineStyle):Int {
		var n = styles.length;
		if (styles[n - 1] == s) return n - 1;
		for (i in 0...n)
			if (styles[i] == s) return i;
		styles.push(s);
		return n;
	}

	// --- items ---

	public inline function kind(i:Int):InlineItem
		return cast iKind[i];

	public inline function start(i:Int):Int
		return iStart[i];

	public inline function end(i:Int):Int
		return iEnd[i];

	public inline function style(i:Int):InlineStyle
		return styles[iStyle[i]];

	public inline function styleOf(i:Int):Int
		return iStyle[i];

	public inline function source(i:Int):Null<Box>
		return iSource[i];

	// the Open item of the inline box an item is in (-1: the root; an Open's
	// and a Close's: their box's own Open); an Open's and a Close's each other
	public inline function box(i:Int):Int
		return iBox[i];

	public inline function match(i:Int):Int
		return iMatch[i];

	// An inline edge with any margin, border or padding keeps the line from being empty.
	@:allow(helder.ui.flow.LineBuilder, helder.ui.flow.BlockLines)
	inline function edged(item:Int):Bool {
		var open = kind(item) == Open, b = open ? item : box(item);
		if (b < 0) return false;
		var st = styles[styleOf(b)];
		return open ? st.marginStart() != 0 || st.borderStart() != 0 || st.paddingStart() != 0 : st.marginEnd() != 0 || st.borderEnd() != 0
			|| st.paddingEnd() != 0;
	}

	// an Open's: the box around it (-1: the root), its depth (1: in the root)
	public inline function parent(open:Int):Int
		return iParent[open];

	public inline function depth(open:Int):Int
		return iDepth[open];

	// its bidi level (a text item's units all have it)
	public inline function level(i:Int):Int
		return iLevel[i];

	// an isolating box's Open or Close: its initiator's or PDI's level, at
	// which it parts the runs around it (UAX #9 keeps isolates where X9
	// removes embeddings); -1: none
	public inline function isolateLevel(i:Int):Int
		return i < isolates.length ? isolates[i] : -1;

	// its font (InlineFonts' id: its style's)
	public inline function font(i:Int):Int
		return iFont[i];

	public inline function letterSpacing(i:Int):Float
		return iLetter == null ? 0 : iLetter[i];

	public inline function wordSpacing(i:Int):Float
		return iWord == null ? 0 : iWord[i];

	public inline function atomicWidth(i:Int):Float
		return iWidth == null ? 0 : iWidth[i];

	public inline function atomicHeight(i:Int):Float
		return iHeight == null ? 0 : iHeight[i];

	public inline function atomicBaseline(i:Int):Float
		return iBaseline == null ? 0 : iBaseline[i];

	// the item a unit of the text is in (not a zero-length one)
	public function itemAt(u:Int):Int {
		var lo = 0, hi = items - 1;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (iEnd[mid] <= u) lo = mid + 1 else hi = mid;
		}
		return lo;
	}

	// --- units ---

	// a position in the text (a unit, a caret's place before it) as one of
	// its sources': the box of the item it is in and the offset there (in a
	// text box's text, an atomic's or a break's 0 or 1: before or after
	// it); after the text, the end of its last text or atomic (not the
	// boxes closed after it: a caret's place is in the text)
	public function position(u:Int):{box:Null<Box>, offset:Int} {
		if (items == 0) return {box: null, offset: 0};
		if (u >= text.length) {
			var i = items - 1;
			while (i > 0 && (iSource[i] == null || kind(i) == Open || kind(i) == Close))
				i--;
			return kind(i) == Text ? {box: iSource[i], offset: iEnd[i] > iStart[i] ? sourceOffset(iEnd[i] - 1) + 1 : 0} : {box: iSource[i], offset: 1};
		}
		var i = itemAt(u);
		return kind(i) == Text ? {box: iSource[i], offset: sourceOffset(u)} : {box: iSource[i], offset: 0};
	}

	// the unit of a position (a source box of the content and an offset in
	// it): in a text box, the first unit from that offset on (a collapsed
	// space's the next one kept); an atomic's place before it; -1: not in
	// the content
	public function unitOf(box:Box, offset:Int):Int {
		var found = -1;
		for (i in 0...items) {
			if (iSource[i] != box) continue;
			if (kind(i) != Text) return offset > 0 ? iEnd[i] : iStart[i];
			for (u in iStart[i]...iEnd[i])
				if (sourceOffset(u) >= offset) return u;
			found = iEnd[i];
		}
		return found;
	}

	// a unit's offset in its item's source (a text box's text)
	public function sourceOffset(u:Int):Int {
		if (offsets != null) return offsets[u];
		var j = jumps, lo = 0, hi = (j.length >> 1) - 1;
		while (lo < hi) {
			var m = (lo + hi + 1) >> 1;
			if (j[2 * m] <= u) lo = m else hi = m - 1;
		}
		return j[2 * lo + 1] + (u - j[2 * lo]);
	}

	public inline function unitLevel(u:Int):Int
		return bidi ? levels.get(u) : 0;

	// the opportunity before a unit (LineBreaks' status and CLUSTER; HYPHEN)
	public inline function breakAt(u:Int):Int
		return breaks.get(u);

	// a hyphen shown where a line breaks there (after a soft hyphen)
	public static inline var HYPHEN = 8;

	// a paragraph's base level at a unit (0, 1): the root's direction, or
	// with unicode-bidi: plaintext the paragraph's own
	public function paragraphDirection(u:Int):Int {
		var d = direction, k = 0;
		while (k < paragraphs.length && paragraphs[k] <= u) {
			d = paragraphs[k + 1];
			k += 2;
		}
		return d;
	}

	// --- pieces: what the line builder places, in logical order ---
	public static inline var WORD = 0;
	public static inline var SPACE = 1;
	public static inline var TAB = 2;
	// (an item that is not text: what it is, its item's kind)
	public static inline var ITEM = 3;

	public inline function pieceKind(p:Int):Int
		return pKind.get(p);

	public inline function pieceStart(p:Int):Int
		return pStart[p];

	public inline function pieceEnd(p:Int):Int
		return pEnd[p];

	public inline function pieceItem(p:Int):Int
		return pItem[p];

	// the opportunity before it (LineBreaks' NONE, ALLOWED, FORCED; HYPHEN)
	public inline function pieceBreak(p:Int):Int
		return pBreak.get(p);

	// its shaped word (InlineShaper's entry; -1: none)
	public inline function pieceEntry(p:Int):Int
		return pEntry[p];

	// its advance: a word's or spaces', an Open's start edges, a Close's end
	// ones, an atomic's margin box; a tab's, its stops' interval
	public inline function pieceWidth(p:Int):Float
		return pWidth[p];

	// shaped again where the cache was emptied since (InlineShaper.generation)
	public function ensureShaped() {
		if (shapedIn != shaper.generation) shape();
	}

	// --- finish ---

	public function finish() {
		if (finished) return;
		finished = true;
		// (its items and units about as many as what it was given: their columns that long at once)
		var units = 0;
		for (r in raw) units += r.text.length;
		itemRoom(raw.length + 4, true);
		room(units + 4, true);
		process();
		bidiLevels();
		opportunities();
		segment();
		shape();
		// (not kept: a long document's contents each held its source runs)
		raw = [];
	}

	// an item's style's flags (flags): wraps (text-wrap-mode), break-spaces,
	// hyphens: none, collapsible spaces (removed at a line's end), spaces
	// that hang there (collapsible or pre-wrap's), overflow-wrap's
	// emergency breaks (break-word, anywhere: also in the min-content size)
	public static inline var WRAPS = 1;
	public static inline var BREAK_SPACES = 2;
	public static inline var NO_HYPHENS = 4;
	public static inline var COLLAPSIBLE = 8;
	public static inline var HANGS = 16;
	public static inline var BREAK_WORD = 32;
	public static inline var ANYWHERE = 64;
	// (a box's: its unicode-bidi opens and closes controls, in the text as Blink has them)
	public static inline var CONTROLS = 128;

	public inline function flags(i:Int):Int
		return iFlags[i];

	// (the items in order with their processed text: white space, transforms)
	function process() {
		var n = 0, cps:Array<Int> = [];
		var stack:Array<Int> = [], styleStack:Array<Int> = [0];
		// (the collapsible white space in progress: its space's item, the
		// character before it, whether it has a segment break; a line's start)
		var pending = false, pendingItem = -1, before = -1, segment = false;
		var lineStart = true, letterBefore = false;
		inline function emit(c:Int, offset:Int) {
			var len = c >= 0x10000 ? 2 : 1;
			room(n + len);
			for (k in 0...len)
				offsets[n + k] = offset;
			cps.push(c);
			n += len;
		}
		inline function newItem(kind:InlineItem, style:Int, source:Null<Box>):Int {
			var i = items++;
			itemRoom(items);
			iKind[i] = kind;
			iStart[i] = n;
			iEnd[i] = n;
			iStyle[i] = style;
			iBox[i] = stack.length == 0 ? -1 : stack[stack.length - 1];
			iMatch[i] = -1;
			iLevel[i] = 0;
			iSource[i] = source;
			iParent[i] = -1;
			iDepth[i] = 0;
			iWidth[i] = iHeight[i] = iBaseline[i] = 0;
			return i;
		}
		// (the run's space taken out: it is the last unit, the items after it empty)
		function dropPending() {
			cps.pop();
			n--;
			for (j in pendingItem...items) {
				if (iStart[j] > n) iStart[j] = n;
				if (iEnd[j] > n) iEnd[j] = n;
			}
			pending = false;
		}
		for (r in raw) {
			switch r.kind {
				case Open:
					var i = newItem(Open, r.style, r.source);
					iParent[i] = iBox[i];
					iDepth[i] = stack.length + 1;
					iBox[i] = i;
					stack.push(i);
					styleStack.push(r.style);
				case Close:
					var open = stack.length == 0 ? -1 : stack.pop();
					if (open >= 0) styleStack.pop();
					var i = newItem(Close, open < 0 ? 0 : iStyle[open], r.source);
					iBox[i] = open;
					iMatch[i] = open;
					if (open >= 0) iMatch[open] = i;
				case Float | Abspos:
					newItem(r.kind, styleStack[styleStack.length - 1], r.source);
				case Atomic:
					pending = false;
					segment = false;
					lineStart = false;
					letterBefore = false;
					before = 0xFFFC;
					var i = newItem(Atomic, r.style, r.source);
					emit(0xFFFC, 0);
					iEnd[i] = n;
					iWidth[i] = r.width;
					iHeight[i] = r.height;
					iBaseline[i] = r.baseline;
				case Break:
					var i = newItem(Break, r.style < 0 ? styleStack[styleStack.length - 1] : r.style, r.source);
					emit(10, 0);
					iEnd[i] = n;
					pending = false;
					segment = false;
					lineStart = true;
					letterBefore = false;
				case Text:
					var st = styles[r.style], mode = st.whiteSpaceCollapse(), transform:Int = st.textTransform();
					var s = r.text, item = -1, k = 0;
					var collapse = mode == Collapse || mode == PreserveBreaks || mode == Discard;
					while (k < s.length) {
						var c = StringTools.fastCodeAt(s, k), len = 1;
						if (c >= 0xD800 && c < 0xDC00 && k + 1 < s.length) {
							var d = StringTools.fastCodeAt(s, k + 1);
							if (d >= 0xDC00 && d < 0xE000) {
								c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
								len = 2;
							}
						}
						var offset = r.offset + k;
						k += len;
						// (carriage returns are spaces; segment breaks too where they are not preserved)
						var space = c == 32 || c == 9 || c == 13;
						if (c == 10 && (mode == Collapse || mode == Discard || mode == PreserveSpaces)) space = true;
						if (space && collapse) {
							if (mode == Discard) continue;
							if (pending) {
								if (c == 10) segment = true;
								// (a nowrap item's space before a wrapping one's: Blink keeps the second, its break the wrapping one's)
								if (pendingItem == item || pendingItem >= 0 && item < 0 && iSource[pendingItem] == r.source && iStyle[pendingItem] == r.style
									|| styles[iStyle[pendingItem]].textWrapMode() != NoWrap || st.textWrapMode() == NoWrap)
									continue;
								var seg = segment;
								dropPending();
								segment = seg;
							}
							if (lineStart) continue;
							if (item < 0) item = newItem(Text, r.style, r.source);
							if (!segment) segment = c == 10;
							pending = true;
							pendingItem = item;
							emit(32, offset);
							iEnd[item] = n;
							letterBefore = false;
							continue;
						}
						if (c == 10) {
							// (a preserved segment break: a forced break; preserve-breaks drops the spaces before it)
							if (pending && mode == PreserveBreaks) dropPending();
							pending = false;
							segment = false;
							var b = newItem(Break, r.style, r.source);
							emit(10, offset);
							iEnd[b] = n;
							item = -1;
							lineStart = true;
							letterBefore = false;
							continue;
						}
						if (pending && segment && removesBreak(before, c)) dropPending();
						pending = false;
						segment = false;
						lineStart = false;
						if (item < 0) item = newItem(Text, r.style, r.source);
						if (space) {
							// (preserved: a tab stays a tab, the others are spaces)
							emit(c == 9 ? 9 : 32, offset);
							letterBefore = false;
						} else if (transform == 0) {
							emit(c, offset);
							letterBefore = isLetter(c);
						} else {
							var t = transformed(c, transform, letterBefore), j = 0;
							while (j < t.length) {
								var d = StringTools.fastCodeAt(t, j);
								if (d >= 0xD800 && d < 0xDC00 && j + 1 < t.length) {
									d = 0x10000 + ((d - 0xD800) << 10) + (StringTools.fastCodeAt(t, j + 1) - 0xDC00);
									j++;
								}
								emit(d, offset);
								j++;
							}
							letterBefore = isLetter(c);
						}
						before = c;
						iEnd[item] = n;
					}
			}
		}
		// (boxes left open: closed at the end)
		while (stack.length > 0) {
			var open = stack.pop();
			var i = newItem(Close, iStyle[open], null);
			iBox[i] = open;
			iMatch[i] = open;
			iMatch[open] = i;
		}
		var buf = new StringBuf();
		for (c in cps)
			buf.addChar(c);
		text = buf.toString();
		// (what each item's style asks, read once a style)
		var last = -1, flags = 0, font = 0, letter = 0.0, word = 0.0;
		for (i in 0...items) {
			if (iStyle[i] != last) {
				last = iStyle[i];
				var st = styles[last];
				var ws = st.whiteSpaceCollapse(), wrap = st.textWrapMode() == Wrap;
				var collapsible = ws == Collapse || ws == PreserveBreaks || ws == Discard;
				flags = (wrap ? WRAPS : 0) | (ws == BreakSpaces ? BREAK_SPACES : 0) | (st.hyphens() == None ? NO_HYPHENS : 0)
					| (collapsible ? COLLAPSIBLE | HANGS : 0) | (wrap && (ws == Preserve || ws == PreserveSpaces) ? HANGS : 0)
					| (st.overflowWrap() == BreakWord ? BREAK_WORD : 0)
					| (st.overflowWrap() == Anywhere || st.wordBreak() == BreakWord ? BREAK_WORD | ANYWHERE : 0)
					| (last > 0 && st.unicodeBidi() != Normal ? CONTROLS : 0);
				font = fonts.idOf(st);
				letter = st.letterSpacing();
				word = st.wordSpacing();
			}
			iFlags[i] = flags;
			iFont[i] = font;
			iLetter[i] = letter;
			iWord[i] = word;
		}
	}

	function room(n:Int, exact = false) {
		if (n <= offsets.length) return;
		offsets = ints(offsets, exact ? n : n * 2);
	}

	function itemRoom(n:Int, exact = false) {
		if (n <= iKind.length) return;
		var m = exact ? n : n * 2;
		iKind = ints(iKind, m);
		iStart = ints(iStart, m);
		iEnd = ints(iEnd, m);
		iStyle = ints(iStyle, m);
		iBox = ints(iBox, m);
		iMatch = ints(iMatch, m);
		iLevel = ints(iLevel, m);
		iFont = ints(iFont, m);
		iParent = ints(iParent, m);
		iDepth = ints(iDepth, m);
		iFlags = ints(iFlags, m);
		iWidth = floats(iWidth, m);
		iHeight = floats(iHeight, m);
		iBaseline = floats(iBaseline, m);
		iLetter = floats(iLetter, m);
		iWord = floats(iWord, m);
		var s = new Vector<Box>(m);
		Vector.blit(iSource, 0, s, 0, iSource.length);
		iSource = s;
	}

	static final NO_LEVELS = Bytes.alloc(0);

	static function bytes(b:Bytes, n:Int):Bytes {
		var c = Bytes.alloc(n);
		c.blit(0, b, 0, b.length);
		return c;
	}

	function pieceRoom(n:Int) {
		if (n <= pKind.length) return;
		var m = n * 2;
		pKind = bytes(pKind, m);
		pStart = ints(pStart, m);
		pEnd = ints(pEnd, m);
		pItem = ints(pItem, m);
		pBreak = bytes(pBreak, m);
		pEntry = ints(pEntry, m);
		pWidth = floats(pWidth, m);
	}

	var compacted = false;

	// Its columns cut to what they hold (they grow by doubling, from 16 items
	// and 64 units): a long document keeps one a block, for its lines' hit
	// tests and its later layouts.
	public function compact() {
		// (once: a kept content is laid out again at each width)
		if (compacted) return;
		compacted = true;
		inline function slack(length:Int, used:Int):Bool
			return length > used + (used >> 2) + 8;
		if (slack(iKind.length, items)) {
			var m = items;
			iKind = fit(iKind, m);
			iStart = fit(iStart, m);
			iEnd = fit(iEnd, m);
			iStyle = fit(iStyle, m);
			iBox = fit(iBox, m);
			iMatch = fit(iMatch, m);
			iLevel = fit(iLevel, m);
			iFont = fit(iFont, m);
			iParent = fit(iParent, m);
			iDepth = fit(iDepth, m);
			iFlags = fit(iFlags, m);
			iWidth = fit(iWidth, m);
			iHeight = fit(iHeight, m);
			iBaseline = fit(iBaseline, m);
			iLetter = fit(iLetter, m);
			iWord = fit(iWord, m);
			iSource = fit(iSource, m);
		}
		if (slack(pKind.length, pieces)) {
			var m = pieces;
			pKind = pKind.sub(0, m);
			pStart = fit(pStart, m);
			pEnd = fit(pEnd, m);
			pItem = fit(pItem, m);
			pBreak = pBreak.sub(0, m);
			pEntry = fit(pEntry, m);
			pWidth = fit(pWidth, m);
		}
		// (columns of zeros alone: none)
		inline function zeros(v:Null<Vector<Float>>):Bool {
			var z = v != null;
			if (z) for (i in 0...items) if (v[i] != 0) {
				z = false;
				break;
			}
			return z;
		}
		if (zeros(iWidth)) iWidth = null;
		if (zeros(iHeight)) iHeight = null;
		if (zeros(iBaseline)) iBaseline = null;
		if (zeros(iLetter)) iLetter = null;
		if (zeros(iWord)) iWord = null;
		var n = text.length;
		var o = offsets, count = 0;
		for (u in 0...n + 1) if (u == 0 || u >= o.length || o[u] != o[u - 1] + 1) count++;
		var j = new Vector<Int>(2 * count), k = 0;
		for (u in 0...n + 1) if (u == 0 || u >= o.length || o[u] != o[u - 1] + 1) {
			j[k++] = u;
			j[k++] = u < o.length ? o[u] : 0;
		}
		jumps = j;
		offsets = null;
		// (all 0 without bidi: none kept)
		if (!bidi) levels = NO_LEVELS else if (slack(levels.length, n + 1)) levels = levels.sub(0, n + 1);
		if (slack(breaks.length, n + 1)) breaks = breaks.sub(0, n + 1);
	}

	static function fit<T>(v:Vector<T>, n:Int):Vector<T> {
		var w = new Vector<T>(n);
		Vector.blit(v, 0, w, 0, n);
		return w;
	}

	static function ints(v:Vector<Int>, n:Int):Vector<Int> {
		var w = new Vector<Int>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	static function floats(v:Vector<Float>, n:Int):Vector<Float> {
		var w = new Vector<Float>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	// a segment break between two characters removed (CSS Text 3 §4.1.2):
	// next to a zero width space, or between two East Asian wide ones, not
	// Hangul and not emoji (as Firefox: emoji are wide, yet words of their own)
	static function removesBreak(before:Int, after:Int):Bool {
		if (before == 0x200B || after == 0x200B) return true;
		return before >= 0 && joins(before) && joins(after);
	}

	static inline function joins(c:Int):Bool
		return LineBreaks.wide(c) && !hangul(c) && !helder.text.Emoji.presentation(c);

	static inline function hangul(c:Int):Bool
		return c >= 0x1100 && c <= 0x11FF || c >= 0x3130 && c <= 0x318F || c >= 0xAC00 && c <= 0xD7FF || c >= 0xA960 && c <= 0xA97F;

	// (a letter or digit, what capitalize's words are made of)
	static function isLetter(c:Int):Bool {
		if (c < 0x80) return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code;
		var k = LineBreaks.classOf(c);
		return k == LineBreaks.AL || k == LineBreaks.HL || k == LineBreaks.NU || k == LineBreaks.ID || k == LineBreaks.SA || k == LineBreaks.CM
			|| k == LineBreaks.H2 || k == LineBreaks.H3 || k == LineBreaks.JL || k == LineBreaks.JV || k == LineBreaks.JT || k == LineBreaks.AK
			|| k == LineBreaks.AS || k == LineBreaks.CJ;
	}

	// text-transform's form of a character (its case's, full-width, full-size kana)
	static function transformed(c:Int, t:Int, letterBefore:Bool):String {
		var s = String.fromCharCode(c);
		switch t & InlineTransform.CASE {
			case 1:
				if (!letterBefore) s = s.toUpperCase();
			case 2:
				s = s.toUpperCase();
			case 3:
				s = s.toLowerCase();
			case _:
		}
		if (t & (InlineTransform.FullWidth : Int) != 0) {
			var buf = new StringBuf();
			for (i in 0...s.length) {
				var d = StringTools.fastCodeAt(s, i);
				buf.addChar(d == 32 ? 0x3000 : d >= 0x21 && d <= 0x7E ? d - 0x21 + 0xFF01 : d);
			}
			s = buf.toString();
		}
		if (t & (InlineTransform.FullSizeKana : Int) != 0 && s.length == 1) s = String.fromCharCode(fullSizeKana(StringTools.fastCodeAt(s, 0)));
		return s;
	}

	// (the small kana and their full sizes: CSS Text 3's table)
	static function fullSizeKana(c:Int):Int {
		var small = "ぁぃぅぇぉゕゖっゃゅょゎァィゥェォヵㇰヶㇱㇲッㇳㇴㇵㇶㇷㇸㇹㇺャュョㇻㇼㇽㇾㇿヮｧｨｩｪｫｯｬｭｮ";
		var full = "あいうえおかけつやゆよわアイウエオカクケシスツトヌハヒフヘホムヤユヨラリルレロワｱｲｳｴｵﾂﾔﾕﾖ";
		var k = small.indexOf(String.fromCharCode(c));
		return k < 0 ? c : StringTools.fastCodeAt(full, k);
	}

	// --- bidi ---

	// every unit's level: UAX #9 on each paragraph (between forced breaks),
	// the inline boxes' embeddings and isolates as their controls (opened
	// again after a break inside them), atomics as U+FFFC; then each text
	// item cut where its level changes
	function bidiLevels() {
		var n = text.length;
		if (levels.length < n + 1) levels = Bytes.alloc(n + 1);
		levels.fill(0, n + 1, 0);
		var base = root.direction() == Rtl ? 1 : 0;
		direction = base;
		var plaintext = root.unicodeBidi() == Plaintext;
		rtl = base == 1;
		paragraphs.resize(0);
		isolates.resize(0);
		var explicit = false;
		if (!rtl) {
			var i = 0;
			while (i < n) {
				var c = StringTools.fastCodeAt(text, i++);
				if (c < 0x590) continue;
				if (c >= 0xD800 && c < 0xDC00 && i < n) c = 0x10000 + ((c - 0xD800) << 10) + (StringTools.fastCodeAt(text, i++) - 0xDC00);
				var k = Bidi.classOf(c);
				if (k == Bidi.R || k == Bidi.AL || k == Bidi.RLE || k == Bidi.RLO || k == Bidi.RLI || k == Bidi.FSI) {
					rtl = true;
					break;
				}
				if (k >= Bidi.LRE && k <= Bidi.PDI) explicit = true;
			}
		}
		// (a block container's bidi-override: its inline content's, each paragraph in an override, CSS Writing Modes 3 §2.2)
		var rootBidi = root.unicodeBidi();
		var forced = rootBidi == BidiOverride || rootBidi == IsolateOverride ? (base == 1 ? 0x202E : 0x202D) : -1;
		var any = rtl || explicit || plaintext || forced >= 0;
		for (k in 1...styles.length)
			if (styles[k].direction() == Rtl) rtl = true;
		// (an override or embedding asked for: the algorithm, even on left-to-right text)
		if (!any)
			for (k in 1...styles.length)
				if (styles[k].unicodeBidi() != Normal) any = true;
		bidi = any;
		if (!any) {
			for (i in 0...items)
				iLevel[i] = 0;
			return;
		}
		// (the code points of a paragraph, the controls among them, the unit each is: -1 a control's)
		var cps:Array<Int> = [], at:Array<Int> = [], open:Array<Int> = [];
		// (the isolates' levels in item order, and where each one's control is in the paragraph)
		var marks:Array<Int> = [], pending:Array<Int> = [];
		var first = 0;
		function paragraph() {
			if (cps.length == 0) return;
			var r = Bidi.levels(cps, plaintext ? -1 : base);
			paragraphs.push(first);
			paragraphs.push(r.base);
			var k = 0;
			while (k < pending.length) {
				marks[pending[k]] = r.levels[pending[k + 1]];
				k += 2;
			}
			pending.resize(0);
			for (k in 0...cps.length) {
				var u = at[k];
				if (u < 0) continue;
				levels.set(u, r.levels[k]);
				if (cps[k] >= 0x10000) levels.set(u + 1, r.levels[k]);
			}
			cps.resize(0);
			at.resize(0);
		}
		inline function control(c:Int) {
			cps.push(c);
			at.push(-1);
		}
		if (forced >= 0) control(forced);
		for (i in 0...items) {
			switch kind(i) {
				case Open:
					open.push(i);
					var cs = opening(styles[iStyle[i]]);
					if (cs.length > 0 && cs[0] >= 0x2066 && cs[0] <= 0x2068) {
						pending.push(marks.length);
						pending.push(cps.length);
						marks.push(-1);
					}
					for (c in cs)
						control(c);
				case Close:
					if (open.length > 0) {
						var o = open.pop();
						var cs = closing(styles[iStyle[o]]);
						if (cs.length > 0 && cs[cs.length - 1] == 0x2069) {
							pending.push(marks.length);
							pending.push(cps.length + cs.length - 1);
							marks.push(-1);
						}
						for (c in cs)
							control(c);
					}
				case Break:
					// (its paragraph ends here; the boxes still open, opened again after it)
					cps.push(10);
					at.push(iStart[i]);
					paragraph();
					first = iEnd[i];
					if (forced >= 0) control(forced);
					for (o in open)
						for (c in opening(styles[iStyle[o]]))
							control(c);
				case _:
					var u = iStart[i];
					while (u < iEnd[i]) {
						var c = StringTools.fastCodeAt(text, u), len = 1;
						if (c >= 0xD800 && c < 0xDC00 && u + 1 < iEnd[i]) {
							c = 0x10000 + ((c - 0xD800) << 10) + (StringTools.fastCodeAt(text, u + 1) - 0xDC00);
							len = 2;
						}
						cps.push(c);
						at.push(u);
						u += len;
					}
			}
		}
		paragraph();
		splitLevels();
		// (zero-length items: the level of what is before them)
		for (j in 0...items)
			if (iEnd[j] == iStart[j]) iLevel[j] = j > 0 ? iLevel[j - 1] : base;
		if (marks.length == 0) return;
		// (the isolating boxes' Opens and Closes, met in the same order)
		var m = 0, opened:Array<Int> = [];
		isolates.resize(items);
		for (j in 0...items) {
			isolates[j] = -1;
			switch kind(j) {
				case Open:
					var cs = opening(styles[iStyle[j]]);
					var iso = cs.length > 0 && cs[0] >= 0x2066 && cs[0] <= 0x2068;
					opened.push(iso ? 1 : 0);
					if (iso) isolates[j] = marks[m++];
				case Close:
					if (opened.length > 0 && opened.pop() == 1) isolates[j] = marks[m++];
				case _:
			}
		}
	}

	// (the controls an inline box's unicode-bidi opens and closes)
	static function opening(s:InlineStyle):Array<Int> {
		var rtl = s.direction() == Rtl;
		return switch s.unicodeBidi() {
			case Embed: [rtl ? 0x202B : 0x202A];
			case Isolate: [rtl ? 0x2067 : 0x2066];
			case BidiOverride: [rtl ? 0x202E : 0x202D];
			case IsolateOverride: [rtl ? 0x2067 : 0x2066, rtl ? 0x202E : 0x202D];
			case Plaintext: [0x2068];
			case _: [];
		}
	}

	static function closing(s:InlineStyle):Array<Int>
		return switch s.unicodeBidi() {
			case Embed | BidiOverride: [0x202C];
			case Isolate | Plaintext: [0x2069];
			case IsolateOverride: [0x202C, 0x2069];
			case _: [];
		}

	// (each text item of one level: cut where it changes, the items made again in one pass)
	function splitLevels() {
		var cuts = 0;
		for (i in 0...items) {
			if (iEnd[i] > iStart[i]) iLevel[i] = levels.get(iStart[i]);
			if (kind(i) == Text)
				for (u in iStart[i] + 1...iEnd[i])
					if (levels.get(u) != levels.get(u - 1)) cuts++;
		}
		if (cuts == 0) return;
		var old = items, moved = new Vector<Int>(old);
		var from = new InlineContent(root, fonts, shaper);
		from.itemRoom(old);
		for (i in 0...old)
			from.copyFrom(this, i, i);
		items = 0;
		itemRoom(old + cuts);
		for (i in 0...old) {
			moved[i] = items;
			copyFrom(from, i, items);
			items++;
			if (from.kind(i) == Text)
				for (u in from.iStart[i] + 1...from.iEnd[i])
					if (levels.get(u) != levels.get(u - 1)) {
						iEnd[items - 1] = u;
						copyFrom(from, i, items);
						iStart[items] = u;
						iLevel[items] = levels.get(u);
						items++;
					}
		}
		for (i in 0...items) {
			if (iBox[i] >= 0) iBox[i] = moved[iBox[i]];
			if (iMatch[i] >= 0) iMatch[i] = moved[iMatch[i]];
			if (iParent[i] >= 0) iParent[i] = moved[iParent[i]];
		}
	}

	function copyFrom(o:InlineContent, from:Int, to:Int) {
		iKind[to] = o.iKind[from];
		iStart[to] = o.iStart[from];
		iEnd[to] = o.iEnd[from];
		iStyle[to] = o.iStyle[from];
		iBox[to] = o.iBox[from];
		iMatch[to] = o.iMatch[from];
		iLevel[to] = o.iLevel[from];
		iFont[to] = o.iFont[from];
		iWidth[to] = o.atomicWidth(from);
		iHeight[to] = o.atomicHeight(from);
		iBaseline[to] = o.atomicBaseline(from);
		iSource[to] = o.iSource[from];
		iParent[to] = o.iParent[from];
		iDepth[to] = o.iDepth[from];
		iFlags[to] = o.iFlags[from];
		iLetter[to] = o.letterSpacing(from);
		iWord[to] = o.wordSpacing(from);
	}

	// --- break opportunities ---

	static final analyzer = new LineBreaks();

	function opportunities() {
		var n = text.length;
		if (breaks.length < n + 1) breaks = Bytes.alloc(n + 1);
		var opts = Bytes.alloc(n + 1);
		for (i in 0...items) {
			if (iEnd[i] == iStart[i]) continue;
			var s = styles[iStyle[i]], o = 0;
			switch s.lineBreak() {
				case Strict: o |= LineBreaks.STRICT;
				case Loose: o |= LineBreaks.LOOSE;
				case Anywhere: o |= LineBreaks.ANYWHERE;
				case _:
			}
			switch s.wordBreak() {
				case BreakAll: o |= LineBreaks.BREAK_ALL;
				case KeepAll: o |= LineBreaks.KEEP_ALL;
				case _:
			}
			if (kind(i) == Atomic) o |= LineBreaks.ATOMIC;
			if (o != 0) opts.fill(iStart[i], iEnd[i] - iStart[i], o);
		}
		analyzer.analyze(text, 0, n, breaks, opts);
		// (white-space's wrapping, hyphens, break-spaces' spaces: each boundary by the items on its sides)
		var a = 0;
		for (u in 1...n) {
			while (a < items - 1 && iEnd[a] <= u - 1)
				a++;
			var s = breaks.get(u), status = s & LineBreaks.STATUS;
			var before = StringTools.fastCodeAt(text, u - 1), fa = iFlags[a];
			// (break-spaces: after every preserved space)
			if (status == LineBreaks.NONE && fa & BREAK_SPACES != 0 && (before == 32 || before == 9) && StringTools.fastCodeAt(text, u) != 10)
				status = LineBreaks.ALLOWED;
			// (a wrapping item that ends in a space: a break at its end, whatever starts the next, as Blink's line breaker)
			if (status == LineBreaks.NONE && fa & WRAPS != 0 && iEnd[a] == u && (before == 32 || before == 9) && StringTools.fastCodeAt(text, u) != 10)
				status = LineBreaks.ALLOWED;
			if (status != LineBreaks.ALLOWED) {
				if (status != s & LineBreaks.STATUS) breaks.set(u, s & ~LineBreaks.STATUS | status);
				continue;
			}
			if (fa & WRAPS == 0) status = LineBreaks.NONE;
			// Blink keeps a pipe inside printable ASCII text together at normal breaks.
			else if (before == "|".code && (opts.get(u - 1) | opts.get(u)) == 0) {
				var after = StringTools.fastCodeAt(text, u);
				if (after > 0x20 && after < 0x7F) status = LineBreaks.NONE;
			} else if (before == 0xAD) {
				if (fa & NO_HYPHENS != 0) status = LineBreaks.NONE else s |= HYPHEN;
			}
			breaks.set(u, s & ~LineBreaks.STATUS | status);
		}
		hyphenate();
	}

	// hyphens: auto: each word's hyphenation points (helder.text's
	// Hyphenation, its language's by the item's lang) as opportunities that
	// show a hyphen. As TextLayout and browsers leave them: words shorter than
	// HYPHEN_WORD letters, with a soft hyphen, in capitals, and the words of a
	// token (between spaces) with a digit, an @, /, \ or _, or a . or : inside
	// it; at least HYPHEN_SIDE letters on each side of a point
	public static inline var HYPHEN_WORD = 5;
	public static inline var HYPHEN_SIDE = 2;

	function hyphenate() {
		for (i in 0...items) {
			if (kind(i) != Text || iFlags[i] & WRAPS == 0) continue;
			var st = styles[iStyle[i]];
			if (st.hyphens() != Auto) continue;
			var h = helder.text.Hyphenation.get(st.lang());
			if (h == null) continue;
			var u = iStart[i], e = iEnd[i];
			inline function at(k:Int):Int
				return StringTools.fastCodeAt(text, k);
			while (u < e) {
				if (at(u) == 32 || at(u) == 9 || at(u) == 10) {
					u++;
					continue;
				}
				// (a token: up to a space)
				var t = u, skip = false;
				while (u < e && at(u) != 32 && at(u) != 9 && at(u) != 10) {
					var c = at(u);
					if (c >= "0".code && c <= "9".code || c == "@".code || c == "/".code || c == "\\".code || c == "_".code
						|| (c == ".".code || c == ":".code) && u + 1 < e && isLetter(at(u + 1)))
						skip = true;
					u++;
				}
				if (skip) continue;
				var j = t;
				while (j < u) {
					while (j < u && !isLetter(at(j)))
						j++;
					var w = j, shy = false, lower = false;
					while (j < u && (isLetter(at(j)) || at(j) == 0xAD)) {
						var c = at(j);
						if (c == 0xAD) shy = true;
						else if (String.fromCharCode(c).toUpperCase() != String.fromCharCode(c)) lower = true;
						j++;
					}
					if (j - w < HYPHEN_WORD || shy || !lower) continue;
					for (p in h.points(text.substring(w, j))) {
						if (p < HYPHEN_SIDE || p > j - w - HYPHEN_SIDE) continue;
						var b = breaks.get(w + p);
						// (not inside a cluster: a mark, a joiner)
						if (b & LineBreaks.STATUS == LineBreaks.NONE && b & LineBreaks.CLUSTER != 0) breaks.set(w + p, b | LineBreaks.ALLOWED | HYPHEN);
					}
				}
			}
		}
	}

	// --- pieces ---

	function segment() {
		pieces = 0;
		for (i in 0...items) {
			var k = kind(i);
			if (k != Text) {
				var p = addPiece(ITEM, iStart[i], iEnd[i], i);
				// (a Close ends what is before it: no break before it; but a box's closing control is text: after a forced break, on the next line)
				pBreak.set(p, k == Close && !takesBreak(i) ? LineBreaks.NONE : breakBefore(i));
				continue;
			}
			var u = iStart[i], e = iEnd[i];
			while (u < e) {
				var c = StringTools.fastCodeAt(text, u);
				var kindOf = c == 9 ? TAB : c == 32 ? SPACE : WORD;
				var v = u + 1;
				if (kindOf != TAB)
					while (v < e) {
						var d = StringTools.fastCodeAt(text, v);
						if ((d == 9 ? TAB : d == 32 ? SPACE : WORD) != kindOf || breaks.get(v) & LineBreaks.STATUS != LineBreaks.NONE) break;
						v++;
					}
				var p = addPiece(kindOf, u, v, i);
				pBreak.set(p, u == iStart[i] ? breakBefore(i) : breaks.get(u) & (LineBreaks.STATUS | HYPHEN));
				u = v;
			}
		}
	}

	// (the opportunity before item i: the boundary at its start, taken by
	// the first item there after any Close (they end what is before them))
	function breakBefore(i:Int):Int {
		var at = iStart[i];
		if (at == 0) return LineBreaks.NONE;
		var s = breaks.get(at) & (LineBreaks.STATUS | HYPHEN);
		if (s == LineBreaks.NONE) return s;
		var j = i - 1;
		while (j >= 0 && iStart[j] == at && iEnd[j] == at && kind(j) != Close)
			j--;
		if (j >= 0 && kind(j) == Close && iStart[j] == at && takesBreak(j)) return LineBreaks.NONE;
		return j == i - 1 ? s : LineBreaks.NONE;
	}

	// (a Close whose box's unicode-bidi closes a control after a forced break:
	// the control is text, Blink's, so the box ends on the next line; the
	// forced break is before it. Only in content with something right to
	// left: HTML's isolate on div, p and the like would otherwise move a
	// left-to-right box's end, which neither Chromium, whose sheet doesn't
	// have it, nor Firefox does)
	function takesBreak(close:Int):Bool {
		var b = iBox[close], at = iStart[close];
		if (!rtl || b < 0 || iFlags[b] & CONTROLS == 0 || at == 0 || breaks.get(at) & LineBreaks.STATUS != LineBreaks.FORCED) return false;
		// (the first such Close there takes it)
		var j = close - 1;
		while (j >= 0 && iStart[j] == at && iEnd[j] == at) {
			if (kind(j) == Close && iBox[j] >= 0 && iFlags[iBox[j]] & CONTROLS != 0) return false;
			j--;
		}
		return true;
	}

	function addPiece(kind:Int, start:Int, end:Int, item:Int):Int {
		var p = pieces++;
		pieceRoom(pieces);
		pKind.set(p, kind);
		pStart[p] = start;
		pEnd[p] = end;
		pItem[p] = item;
		pBreak.set(p, LineBreaks.NONE);
		pEntry[p] = -1;
		pWidth[p] = 0;
		return p;
	}

	// each piece's advance: words and spaces shaped, boxes' edges, atomics' margin boxes
	function shape() {
		shapedIn = shaper.generation;
		for (p in 0...pieces) {
			var i = pItem[p];
			switch pKind.get(p) {
				case WORD | SPACE:
					var f = iFont[i];
					var rtl = iLevel[i] & 1 == 1 && pKind.get(p) == WORD ? InlineShaper.RTL : 0;
					var e = shaper.shape(fonts.set(f), f, text, pStart[p], pEnd[p], rtl, letterSpacing(i), wordSpacing(i));
					pEntry[p] = e;
					pWidth[p] = shaper.width(e);
				case TAB:
					// (tab-size: spaces of the block container's font, each with its spacing, as Blink measures it; or a length)
					var t = root.tabSize(), f = fonts.idOf(root);
					tabSpace = shaper.width(shaper.shape(fonts.set(f), f, " ", 0, 1, 0, 0, 0));
					if (t > 0) {
						var e = shaper.shape(fonts.set(f), f, " ", 0, 1, 0, root.letterSpacing(), root.wordSpacing());
						pWidth[p] = t * shaper.width(e);
					} else pWidth[p] = -t;
				case _:
					var s = styles[iStyle[i]];
					pWidth[p] = switch kind(i) {
						case Open: s.marginStart() + s.borderStart() + s.paddingStart();
						case Close: s.marginEnd() + s.borderEnd() + s.paddingEnd();
						case Atomic: s.marginStart() + atomicWidth(i) + s.marginEnd();
						case _: 0;
					}
			}
		}
	}
}

// What an item of InlineContent is (what the box tree gives the IFC)
enum abstract InlineItem(Int) to Int {
	// text in one style, from one text box
	var Text;
	// an inline box's start and end
	var Open;
	var Close;
	// an inline-block, replaced element, inline flex or grid
	var Atomic;
	// a forced break (<br>, a preserved segment break)
	var Break;
	// a float's and an absolutely positioned box's place
	var Float;
	var Abspos;
}

// (what the builder was given, finish's to process)
private class RawItem {
	public final kind:InlineItem;
	public final text:String;
	public final style:Int;
	public final source:Null<Box>;
	public final offset:Int;
	public var width = 0.0;
	public var height = 0.0;
	public var baseline = 0.0;

	public function new(kind:InlineItem, text:String, style:Int, source:Null<Box>, offset:Int) {
		this.kind = kind;
		this.text = text;
		this.style = style;
		this.source = source;
		this.offset = offset;
	}
}
