package helder.ui.flow;

import haxe.ds.Vector;
import helder.ui.flow.InlineContent;
import helder.ui.flow.InlineLayout;
import helder.ui.flow.InlineValues;

// Lines of an InlineContent, LayoutNG's line breaker and inline layout
// algorithm in one: each line's pieces taken greedily up to the last
// opportunity where they fit (spaces that hang at its end left out:
// collapsible ones removed, pre-wrap's hanging; a soft hyphen's break with
// its hyphen in), a run that fits nowhere cut where overflow-wrap lets it
// (between clusters) or left overflowing; then its line box (CSS 2.1
// §10.8): the root's strut and every inline box and atomic on it, each at
// its baseline shifted by vertical-align from its parent's, top and bottom
// aligned subtrees placed last; its fragments placed and its text runs'
// glyphs copied into the layout's InlineGlyphs. Floats narrow a line
// through the constraints' lineWidth: asked at the strut's height, asked
// again at the line's own when it is taller and the line built again
// where that is narrower.
@:allow(helder.ui.flow.InlineLayout)
class LineBuilder {
	// a line's flags
	public static inline var FORCED = 1;
	public static inline var HYPHENATED = 2;
	static inline var EPSILON = 1e-4;
	// (a piece on the line being built: removed, hanging)
	static inline var REMOVED = 1;
	static inline var HANG = 2;

	var c:InlineContent;
	var out:InlineLayout;
	var dir = 0;
	// (the break found: the piece and unit the next line starts at, its flags, the width used)
	var endP = 0;
	var endU = 0;
	var endFlags = 0;
	var endUsed = 0.0;
	// (min-content: overflow-wrap: break-word's cuts not taken)
	var minimum = false;

	function new() {}

	inline function startOf(p:Int):Int
		return p < c.pieces ? c.pieceStart(p) : c.text.length;

	// --- the lines ---

	function layout(out:InlineLayout, content:InlineContent, cons:InlineConstraints) {
		this.out = out;
		c = content;
		minimum = false;
		out.lines = 0;
		out.fragments = 0;
		out.glyphs.clear();
		out.height = 0;
		out.width = 0;
		var root = c.root;
		dir = cons.direction < 0 ? c.direction : cons.direction;
		var indent = root.textIndent(), eachLine = root.textIndentEachLine(), hanging = root.textIndentHanging();
		var strut = strutHeight();
		var p = 0, u = startOf(0), y = 0.0, first = true, afterForced = false;
		while (p < c.pieces) {
			var indented = first || eachLine && afterForced;
			var x0 = indented != hanging ? indent : 0.0;
			var off = 0.0, avail = cons.width;
			if (cons.lineWidth != null) {
				var r = cons.lineWidth(y, strut);
				off = r.offset;
				avail = r.width;
			}
			breakLine(p, u, x0, avail);
			var h = build(p, u, y, x0, avail, off);
			if (cons.lineWidth != null && h > strut + EPSILON) {
				// (taller than the strut: the floats beside its whole height)
				var r = cons.lineWidth(y, h);
				if (r.width < avail - EPSILON || r.offset != off) {
					undo();
					breakLine(p, u, x0, r.width);
					h = build(p, u, y, x0, r.width, r.offset);
				}
			}
			y += h;
			first = false;
			afterForced = endFlags & FORCED != 0;
			p = endP;
			u = endU;
		}
		out.height = y;
	}

	// (the last line taken back)
	function undo() {
		var k = --out.lines;
		out.fragments = out.lFirst[k];
	}

	// the widest line at a width (0: min-content, infinity: max-content)
	function intrinsic(content:InlineContent, width:Float):Float {
		c = content;
		minimum = width == 0;
		var root = c.root, indent = root.textIndent(), eachLine = root.textIndentEachLine(), hanging = root.textIndentHanging();
		var p = 0, u = startOf(0), widest = 0.0, first = true, afterForced = false;
		while (p < c.pieces) {
			var indented = first || eachLine && afterForced;
			breakLine(p, u, indented != hanging ? indent : 0.0, width);
			if (endUsed > widest) widest = endUsed;
			first = false;
			afterForced = endFlags & FORCED != 0;
			p = endP;
			u = endU;
		}
		minimum = false;
		return widest;
	}

	// --- breaking ---

	// the advance of piece p's units from...to, at x on its line (a tab's to its stop)
	function advance(p:Int, from:Int, to:Int, x:Float):Float {
		var k = c.pieceKind(p);
		if (k == InlineContent.TAB) {
			var t = c.pieceWidth(p);
			if (t <= 0) return 0;
			var next = (Math.floor(x / t + EPSILON) + 1) * t;
			// (closer than half a space: the stop after it)
			if (next - x < c.tabSpace / 2) next += t;
			return next - x;
		}
		if (k == InlineContent.ITEM) return c.pieceWidth(p);
		var s = c.pieceStart(p);
		if (from == s && to == c.pieceEnd(p)) return c.pieceWidth(p);
		return c.shaper.advanceOf(c.pieceEntry(p), from - s, to - s);
	}

	// (a piece that is content: what ends a run of hanging spaces)
	inline function solid(p:Int):Bool {
		var k = c.pieceKind(p);
		if (k == InlineContent.WORD) return true;
		if (k == InlineContent.SPACE || k == InlineContent.TAB) return c.flags(c.pieceItem(p)) & InlineContent.HANGS == 0;
		return c.kind(c.pieceItem(p)) == Atomic;
	}

	// the line from piece p (its unit u) at x0 in avail: endP, endU, endFlags, endUsed
	function breakLine(p:Int, u:Int, x0:Float, avail:Float) {
		var n = c.pieces;
		var x = x0, trailing = 0.0;
		var fitP = -1, fitUsed = 0.0, fitFlags = 0;
		// (a soft hyphen's break that fits but for its hyphen: the break where all else overflows)
		var overP = -1, overUsed = 0.0;
		// (nothing on the line yet but boxes' edges and spaces removed at its start: no soft break)
		var content = false;
		var i = p;
		while (i < n) {
			if (i > p) {
				var br = c.pieceBreak(i), s = br & LineBreaks.STATUS;
				if (s == LineBreaks.ALLOWED && !content) s = LineBreaks.NONE;
				if (s == LineBreaks.FORCED) {
					// (what is before it fits, else the last fit, else a cut)
					if (x - trailing <= avail + EPSILON) end(i, startOf(i), FORCED, x - trailing);
					else if (fitP >= 0) end(fitP, startOf(fitP), fitFlags, fitUsed);
					else if (overP >= 0) end(overP, startOf(overP), HYPHENATED, overUsed);
					else cut(p, u, x0, avail, i);
					return;
				}
				if (s == LineBreaks.ALLOWED) {
					var hy = br & InlineContent.HYPHEN != 0 ? hyphenWidth(c.pieceItem(i - 1)) : 0.0;
					var used = x - trailing + hy;
					if (used <= avail + EPSILON) {
						fitP = i;
						fitUsed = used;
						fitFlags = hy > 0 ? HYPHENATED : 0;
					} else if (x - trailing <= avail + EPSILON) {
						overP = i;
						overUsed = used;
					} else if (fitP >= 0) {
						end(fitP, startOf(fitP), fitFlags, fitUsed);
						return;
					} else if (overP >= 0) {
						end(overP, startOf(overP), HYPHENATED, overUsed);
						return;
					} else {
						cut(p, u, x0, avail, i);
						return;
					}
				}
			}
			var w = leading(i, content) ? 0 : advance(i, i == p ? u : c.pieceStart(i), c.pieceEnd(i), x);
			if (!content && (solid(i) || c.pieceKind(i) == InlineContent.SPACE && !leading(i, false))) content = true;
			trailing = trail(i, w, trailing);
			x += w;
			i++;
		}
		var used = x - trailing;
		if (used <= avail + EPSILON) end(n, c.text.length, 0, used);
		else if (fitP >= 0) end(fitP, startOf(fitP), fitFlags, fitUsed);
		else if (overP >= 0) end(overP, startOf(overP), HYPHENATED, overUsed);
		else cut(p, u, x0, avail, n);
	}

	// (what is left out of a line's fit after piece i: the spaces that hang
	// at its end, and the boxes' end edges after them, as Blink leaves them out)
	inline function trail(i:Int, w:Float, trailing:Float):Float {
		var k = c.pieceKind(i);
		if ((k == InlineContent.SPACE || k == InlineContent.TAB) && c.flags(c.pieceItem(i)) & InlineContent.HANGS != 0) return trailing + w;
		if (solid(i)) return 0;
		if (trailing > 0 && k == InlineContent.ITEM && c.kind(c.pieceItem(i)) == Close) return trailing + w;
		return trailing;
	}

	// (a collapsible space at a line's start, before anything but edges: removed, CSS Text 3 §4.1.2)
	inline function leading(i:Int, content:Bool):Bool
		return !content && c.pieceKind(i) == InlineContent.SPACE && c.flags(c.pieceItem(i)) & InlineContent.COLLAPSIBLE != 0;

	inline function end(p:Int, u:Int, flags:Int, used:Float) {
		endP = p;
		endU = u;
		endFlags = flags;
		endUsed = used;
	}

	// a run with no opportunity where it fits (pieces p, from u, to limit):
	// cut where overflow-wrap lets it, between clusters (one at least on the
	// line), else it overflows to limit
	function cut(p:Int, u:Int, x0:Float, avail:Float, limit:Int) {
		var x = x0, trailing = 0.0, any = false, content = false;
		for (i in p...limit) {
			var from = i == p ? u : c.pieceStart(i), to = c.pieceEnd(i);
			var w = leading(i, content) ? 0 : advance(i, from, to, x);
			if (!content && (solid(i) || c.pieceKind(i) == InlineContent.SPACE && !leading(i, false))) content = true;
			var f = c.flags(c.pieceItem(i));
			var cuts = f & InlineContent.WRAPS != 0 && f & (minimum ? InlineContent.ANYWHERE : InlineContent.BREAK_WORD) != 0;
			// (a tab or a space that does not hang, overflowing: before it)
			var k = c.pieceKind(i);
			if (cuts && any && (k == InlineContent.TAB || k == InlineContent.SPACE) && f & InlineContent.HANGS == 0 && x + w > avail + EPSILON) {
				end(i, from, 0, x - trailing);
				return;
			}
			if (cuts && c.pieceKind(i) == InlineContent.WORD && x + w > avail + EPSILON) {
				var s = c.pieceStart(i), e = c.pieceEntry(i), best = -1, bestW = 0.0, firstCut = -1, firstW = 0.0;
				for (b in from + 1...to)
					if (c.breakAt(b) & LineBreaks.CLUSTER != 0) {
						var pw = c.shaper.advanceOf(e, from - s, b - s);
						if (firstCut < 0) {
							firstCut = b;
							firstW = pw;
						}
						if (x + pw <= avail + EPSILON) {
							best = b;
							bestW = pw;
						} else break;
					}
				if (best > 0) {
					end(i, best, 0, x + bestW);
					return;
				}
				// (nothing of it fits: its first cluster, as Blink keeps it; one cluster: before it, if the line has something)
				if (firstCut > 0) {
					end(i, firstCut, 0, x + firstW);
					return;
				}
				if (any) {
					end(i, from, 0, x - trailing);
					return;
				}
			}
			trailing = trail(i, w, trailing);
			if (w > 0) any = true;
			x += w;
		}
		var forced = limit < c.pieces && c.pieceBreak(limit) & LineBreaks.STATUS == LineBreaks.FORCED;
		end(limit, startOf(limit), forced ? FORCED : 0, x - trailing);
	}

	// the hyphen a break after an item's soft hyphen shows (hyphenate-character
	// auto: U+2010 where its font has it, else "-")
	function hyphenWidth(item:Int):Float
		return c.shaper.width(hyphenEntry(item));

	function hyphenEntry(item:Int):Int {
		var f = c.font(item), set = c.fonts.set(f);
		var h = set.primary.glyph(0x2010) != 0 ? "‐" : "-";
		return c.shaper.shape(set, f, h, 0, 1, 0, c.letterSpacing(item), c.wordSpacing(item));
	}

	// --- the line box ---

	// (per line: each piece's state, REMOVED or HANG)
	var state = new Vector<Int>(64);
	// (the boxes on the line, slots: slot 0 the root; each its Open (-1 the
	// root), parent slot, whether it starts and ends here, its left and right,
	// its BoxSpan fragment, style, its baseline's shift up from its subtree's
	// root (sRoot: the slot whose top or bottom aligns it, 0 the line's), its
	// layout bounds above and below that baseline, its font's ascent and descent)
	var slots = 0;
	var sOpen = new Vector<Int>(16);
	var sParent = new Vector<Int>(16);
	var sEdges = new Vector<Int>(16);
	var sLeft = new Vector<Float>(16);
	var sRight = new Vector<Float>(16);
	var sSpan = new Vector<Int>(16);
	var sStyle = new Vector<Int>(16);
	var sRoot = new Vector<Int>(16);
	var sShift = new Vector<Float>(16);
	var sAbove = new Vector<Float>(16);
	var sBelow = new Vector<Float>(16);
	var sAscent = new Vector<Float>(16);
	var sDescent = new Vector<Float>(16);
	// (each subtree root's extent: the highest top and lowest bottom above its baseline)
	var sTop = new Vector<Float>(16);
	var sBottom = new Vector<Float>(16);
	var sBaseline = new Vector<Float>(16);
	// (each fragment of the line: its slot, and how far its top is above that slot's baseline)
	var fSlot = new Vector<Int>(64);
	var fRise = new Vector<Float>(64);
	static inline var STARTS = 1;
	static inline var ENDS = 2;
	static inline var ATOMIC = 4;

	// the root's strut: its line height
	function strutHeight():Float {
		var lh = c.root.lineHeight();
		return Math.isNaN(lh) ? c.fonts.normalLineHeight(fontOfStyle(0)) : lh;
	}

	inline function fontOfStyle(s:Int):Int
		return c.fonts.idOf(c.styles[s]);

	// a slot for a box (open: its Open item; -1 the root) or an atomic in parent
	function slot(open:Int, parent:Int, style:Int, edges:Int):Int {
		var s = slots++;
		if (s == sOpen.length) growSlots();
		sOpen[s] = open;
		sParent[s] = parent;
		sEdges[s] = edges;
		sLeft[s] = Math.POSITIVE_INFINITY;
		sRight[s] = Math.NEGATIVE_INFINITY;
		sSpan[s] = -1;
		sStyle[s] = style;
		return s;
	}

	// (a box's or an atomic's own metrics: its layout bounds above and below
	// its baseline, its font's ascent and descent; its subtree's extent, sTop
	// and sBottom, from them)
	function metrics(s:Int) {
		var st = c.styles[sStyle[s]], f = fontOfStyle(sStyle[s]);
		var a = c.fonts.ascent(f), d = c.fonts.descent(f);
		sAscent[s] = a;
		sDescent[s] = d;
		if (sEdges[s] & ATOMIC != 0) {
			// (an atomic: its margin box around its baseline; none: its bottom margin edge)
			var i = sOpen[s], h = c.atomicHeight(i), b = c.atomicBaseline(i);
			var mt = st.marginTop(), mb = st.marginBottom();
			if (Math.isNaN(b)) b = h + mb;
			sAbove[s] = mt + b;
			sBelow[s] = h + mb - b;
			sAscent[s] = b;
			sDescent[s] = h - b;
		} else {
			var lh = st.lineHeight();
			if (Math.isNaN(lh)) lh = c.fonts.normalLineHeight(f);
			var leading = lu(lh) - (a + d), half = leadingAbove(leading);
			sAbove[s] = a + half;
			sBelow[s] = d + leading - half;
		}
		sTop[s] = sAbove[s];
		sBottom[s] = -sBelow[s];
	}

	// (a box's baseline's shift up from its parent's by vertical-align: by its
	// subtree's extent, its children's in it, as Blink aligns a box when it
	// ends; top and bottom: 0, placed with the line box)
	function shiftOf(s:Int):Float {
		var st = c.styles[sStyle[s]], p = sParent[s];
		var ps = c.styles[sStyle[p]], pf = fontOfStyle(sStyle[p]);
		var size = ps.fontSize();
		return switch st.verticalAlign() {
			case Sub: -lu(size / 5 + 1);
			case Super: lu(size / 3 + 1);
			case TextTop: c.fonts.ascent(pf) - sTop[s];
			case TextBottom: -sBottom[s] - c.fonts.descent(pf);
			case Middle: Math.round(c.fonts.xHeight(pf) / 2 * 64) / 64 - half(sTop[s] + sBottom[s]);
			case Length: lu(st.verticalShift());
			case Percent:
				var lh = st.lineHeight();
				if (Math.isNaN(lh)) lh = c.fonts.normalLineHeight(fontOfStyle(sStyle[s]));
				lu(st.verticalShift() * lh);
			case _: 0.0;
		}
	}

	// (top or bottom aligned: a subtree of its own)
	inline function pending(s:Int):Bool {
		var va = c.styles[sStyle[s]].verticalAlign();
		return s > 0 && (va == Top || va == Bottom);
	}

	// (Blink's LayoutUnit: a float to 1/64 of a pixel, toward zero; halved, its raw value halved toward zero)
	static inline function lu(v:Float):Float
		return (v >= 0 ? Math.floor(v * 64) : Math.ceil(v * 64)) / 64;

	static inline function half(v:Float):Float {
		var raw = Std.int(lu(v) * 64);
		return Std.int(raw / 2) / 64;
	}

	// (the leading's part above: half of it, floored to a pixel, as Blink's CalculateLeadingSpace)
	static inline function leadingAbove(leading:Float):Float
		return Math.floor(half(leading));

	// (bounds above and below a slot's baseline into its subtree's extent)
	inline function contribute(s:Int, above:Float, below:Float) {
		if (above > sTop[s]) sTop[s] = above;
		if (-below < sBottom[s]) sBottom[s] = -below;
	}

	function growSlots() {
		var n = sOpen.length * 2;
		sOpen = ints(sOpen, n);
		sParent = ints(sParent, n);
		sEdges = ints(sEdges, n);
		sSpan = ints(sSpan, n);
		sStyle = ints(sStyle, n);
		sRoot = ints(sRoot, n);
		sLeft = floats(sLeft, n);
		sRight = floats(sRight, n);
		sShift = floats(sShift, n);
		sAbove = floats(sAbove, n);
		sBelow = floats(sBelow, n);
		sAscent = floats(sAscent, n);
		sDescent = floats(sDescent, n);
		sTop = floats(sTop, n);
		sBottom = floats(sBottom, n);
		sBaseline = floats(sBaseline, n);
	}

	// (a fragment of the line, its slot and rise; its kind, item, x, width)
	function fragment(kind:InlineFragment, item:Int, x:Float, w:Float, slot:Int):Int {
		var o = out, f = o.fragments++;
		if (f == o.fKind.length) growFragments();
		if (f >= fSlot.length) {
			fSlot = ints(fSlot, f * 2 + 2);
			fRise = floats(fRise, f * 2 + 2);
		}
		o.fKind[f] = kind;
		o.fItem[f] = item;
		o.fX[f] = x;
		o.fWidth[f] = w;
		o.fY[f] = 0;
		o.fHeight[f] = 0;
		o.fAscent[f] = 0;
		o.fDescent[f] = 0;
		o.fLevel[f] = item >= 0 ? c.level(item) : dir;
		o.fStart[f] = o.fEnd[f] = item >= 0 ? c.start(item) : 0;
		o.fRun[f] = -1;
		fSlot[f] = slot;
		fRise[f] = 0;
		return f;
	}

	// the line endP and endU end, from p (unit u) at top: its fragments, its
	// box; its height
	function build(p:Int, u:Int, top:Float, x0:Float, avail:Float, offset:Float):Float {
		var o = out, k = o.lines++;
		if (k == o.lTop.length) growLines();
		o.lFirst[k] = o.fragments;
		var last = endU > startOf(endP) ? endP : endP - 1;
		var count = last - p + 1;
		if (count > state.length) state = new Vector<Int>(count * 2);
		for (j in 0...(count > 0 ? count : 0))
			state[j] = 0;
		// (the spaces at its end: collapsible ones removed, others hanging)
		var j = last;
		while (j >= p) {
			var kind = c.pieceKind(j);
			if (kind == InlineContent.ITEM) {
				var ik = c.kind(c.pieceItem(j));
				if (ik == Close || ik == Open || ik == Float || ik == Abspos || ik == Break) {
					j--;
					continue;
				}
				break;
			}
			if (kind == InlineContent.WORD) break;
			var f = c.flags(c.pieceItem(j));
			if (f & InlineContent.COLLAPSIBLE != 0) state[j - p] = REMOVED else if (f & InlineContent.HANGS != 0) state[j - p] = HANG else break;
			j--;
		}
		// (and those at its start)
		var j = p;
		while (j <= last) {
			if (leading(j, false)) state[j - p] = REMOVED;
			else if (solid(j) || c.pieceKind(j) == InlineContent.SPACE) break;
			j++;
		}
		var lastText = -1;
		if (endFlags & HYPHENATED != 0)
			for (i in p...last + 1)
				if (c.pieceKind(i) == InlineContent.WORD) lastText = i;
		// (the boxes it continues from the line before: outermost first)
		slots = 0;
		var rootSlot = slot(-1, -1, 0, 0);
		var chain:Array<Int> = [];
		if (p < c.pieces) {
			var fi = c.pieceItem(p);
			var b = c.kind(fi) == Open ? c.parent(fi) : c.box(fi);
			while (b >= 0) {
				chain.unshift(b);
				b = c.parent(b);
			}
		}
		var cur = rootSlot;
		for (b in chain) {
			var s = slot(b, cur, c.styleOf(b), 0);
			sSpan[s] = fragment(BoxSpan, b, x0, 0, s);
			sLeft[s] = x0;
			cur = s;
		}
		// (what makes the line not empty: CSS 2.1 §9.4.2)
		var filled = endFlags & FORCED != 0;
		var x = x0, trailing = 0.0, textFragment = -1, textItem = -1;
		for (i in p...last + 1) {
			var st = state[i - p];
			if (st == REMOVED) continue;
			var item = c.pieceItem(i), kind = c.pieceKind(i);
			var from = i == p ? u : c.pieceStart(i), to = i == endP ? endU : c.pieceEnd(i);
			var w = advance(i, from, to, x);
			if (kind != InlineContent.ITEM) {
				// (a tab: a fragment of its own, as Blink's control items)
				if (textItem != item || kind == InlineContent.TAB || c.pieceKind(i - 1) == InlineContent.TAB) {
					textFragment = fragment(TextRun, item, x, 0, cur);
					textItem = item;
					o.fStart[textFragment] = from;
					var f = c.font(item);
					o.fAscent[textFragment] = c.fonts.ascent(f);
					o.fDescent[textFragment] = c.fonts.descent(f);
					fRise[textFragment] = o.fAscent[textFragment];
					o.fRun[textFragment] = o.glyphs.begin(c.fonts.set(f));
				}
				// (preserved white space too: only removed spaces leave a line empty)
				filled = true;
				glyphsOf(i, from, to, x - o.fX[textFragment]);
				o.fWidth[textFragment] = x + w - o.fX[textFragment];
				o.fEnd[textFragment] = to;
				if (i == lastText) {
					x += w;
					hyphen(i, x, cur);
					w = 0;
					x = o.fX[o.fragments - 1] + o.fWidth[o.fragments - 1];
				}
			} else {
				textItem = -1;
				var s = c.styles[c.styleOf(item)];
				switch c.kind(item) {
					case Open:
						var b = slot(item, cur, c.styleOf(item), STARTS);
						sSpan[b] = fragment(BoxSpan, item, x, 0, b);
						fragment(BoxStart, item, x, w, b);
						sLeft[b] = x + s.marginStart();
						cur = b;
						if (w > 0) filled = true;
					case Close:
						var b = cur;
						while (b > 0 && sOpen[b] != c.box(item))
							b = sParent[b];
						if (b > 0) {
							fragment(BoxEnd, c.box(item), x, w, b);
							sEdges[b] |= ENDS;
							sRight[b] = x + w - c.styles[c.styleOf(c.box(item))].marginEnd();
							cur = sParent[b];
						}
						if (w > 0) filled = true;
					case Atomic:
						var a = slot(item, cur, c.styleOf(item), ATOMIC);
						var f = fragment(Atomic, item, x + s.marginStart(), c.atomicWidth(item), a);
						o.fEnd[f] = c.end(item);
						filled = true;
					case Float:
						fragment(Float, item, x, 0, -1);
					case Abspos:
						fragment(Abspos, item, x, 0, -1);
					case Break:
						// (a line a forced break ends is not empty: its strut)
						filled = true;
					case _:
				}
			}
			if ((kind == InlineContent.SPACE || kind == InlineContent.TAB) && st == HANG) trailing += w;
			else if (solid(i)) trailing = 0;
			x += w;
		}
		// (the boxes still open: to the line's end, its hanging spaces in)
		var b = cur;
		while (b > 0) {
			sRight[b] = x;
			b = sParent[b];
		}
		var used = x - trailing;
		// (before a forced break or at the end, preserved spaces hang only
		// where they overflow: conditionally, CSS Text 3 §4.1.3)
		if (trailing > 0 && (endFlags & FORCED != 0 || endP >= c.pieces)) used = Math.min(x, Math.max(used, avail));
		// --- vertical: every box's metrics, its children's in it, then the line box ---
		var height = 0.0, baseline = 0.0;
		for (s in 0...slots)
			metrics(s);
		// (text in its own style where it differs from its box's)
		for (f in o.lFirst[k]...o.fragments)
			if (o.fKind[f] == TextRun) {
				var item = o.fItem[f], s = fSlot[f];
				if (c.styleOf(item) != sStyle[s]) {
					var st = c.styles[c.styleOf(item)], fi = c.font(item);
					var a = c.fonts.ascent(fi), d = c.fonts.descent(fi), lh = st.lineHeight();
					if (Math.isNaN(lh)) lh = c.fonts.normalLineHeight(fi);
					var leading = lu(lh) - (a + d), above = leadingAbove(leading);
					contribute(s, a + above, d + leading - above);
				}
			}
		// (innermost first: each one's shift from its subtree, its subtree into its parent's)
		var s = slots - 1;
		while (s > 0) {
			if (pending(s)) sShift[s] = 0 else {
				var r = shiftOf(s), p = sParent[s];
				sShift[s] = r;
				if (sTop[s] + r > sTop[p]) sTop[p] = sTop[s] + r;
				if (sBottom[s] + r < sBottom[p]) sBottom[p] = sBottom[s] + r;
			}
			s--;
		}
		// (outermost first: each one's shift from its subtree root's baseline)
		sRoot[0] = 0;
		sShift[0] = 0;
		for (s in 1...slots)
			if (pending(s)) {
				sRoot[s] = s;
				sShift[s] = 0;
			} else {
				var p = sParent[s];
				sRoot[s] = sRoot[p];
				sShift[s] += sShift[p];
			}
		if (filled) {
			height = sTop[0] - sBottom[0];
			baseline = sTop[0];
			// (top and bottom aligned subtrees: the line grows to hold them)
			for (s in 1...slots)
				if (sRoot[s] == s) {
					var h = sTop[s] - sBottom[s];
					if (h > height) {
						if (c.styles[sStyle[s]].verticalAlign() == Bottom) baseline += h - height;
						height = h;
					}
				}
			for (s in 1...slots)
				if (sRoot[s] == s) sBaseline[s] = c.styles[sStyle[s]].verticalAlign() == Top ? sTop[s] : height + sBottom[s];
			sBaseline[0] = baseline;
		} else
			for (s in 0...slots)
				sBaseline[s] = 0;
		// --- alignment ---
		var root = c.root;
		var align = endFlags & FORCED != 0 || endP >= c.pieces ? root.textAlignLast() : root.textAlign();
		if (align == Auto) align = root.textAlign() == Justify ? Start : root.textAlign();
		var free = avail - used;
		if (free < 0) free = 0;
		var rtl = dir == 1;
		var shift = switch align {
			case Center: free / 2;
			case Right: free;
			case End: rtl ? 0 : free;
			case Start | Justify | MatchParent: rtl ? free : 0;
			case _: 0;
		}
		// --- the fragments placed ---
		for (f in o.lFirst[k]...o.fragments) {
			o.fX[f] += offset + shift;
			var s = fSlot[f];
			if (s < 0) {
				o.fY[f] = top;
				continue;
			}
			var base = top + sBaseline[sRoot[s]] - sShift[s];
			// (an empty line: zero high, its boxes too)
			if (!filled && o.fKind[f] != Atomic) {
				o.fY[f] = top;
				if (o.fKind[f] == BoxSpan) {
					o.fX[f] = sLeft[s] + offset + shift;
					o.fWidth[f] = sRight[s] - sLeft[s];
				}
				continue;
			}
			switch o.fKind[f] {
				case BoxSpan | BoxStart | BoxEnd:
					var st = c.styles[sStyle[s]];
					var up = sAscent[s] + st.paddingTop() + st.borderTop();
					o.fY[f] = base - up;
					o.fHeight[f] = up + sDescent[s] + st.paddingBottom() + st.borderBottom();
					o.fAscent[f] = sAscent[s];
					o.fDescent[f] = sDescent[s];
					if (o.fKind[f] == BoxSpan) {
						o.fX[f] = sLeft[s] + offset + shift;
						o.fWidth[f] = Math.max(0, sRight[s] - sLeft[s]);
					}
				case Atomic:
					o.fY[f] = base - sAscent[s];
					o.fHeight[f] = c.atomicHeight(o.fItem[f]);
					o.fAscent[f] = sAbove[s];
					o.fDescent[f] = sBelow[s];
				case _:
					o.fY[f] = base - fRise[f];
					o.fHeight[f] = o.fAscent[f] + o.fDescent[f];
			}
		}
		o.lTop[k] = top;
		o.lHeight[k] = height;
		o.lBaseline[k] = baseline;
		o.lWidth[k] = used;
		o.lLeft[k] = offset + shift;
		o.lAvail[k] = avail;
		o.lStart[k] = u;
		o.lEnd[k] = endU;
		o.lLast[k] = o.fragments;
		o.lFlags[k] = endFlags;
		if (offset + shift + used > o.width) o.width = offset + shift + used;
		return height;
	}

	// (piece p's glyphs from...to into the current run, from x in it)
	function glyphsOf(p:Int, from:Int, to:Int, x:Float) {
		var e = c.pieceEntry(p);
		if (e < 0) return;
		var sh = c.shaper, g0 = sh.glyphStart(e), s = c.pieceStart(p), whole = from == s && to == c.pieceEnd(p);
		var glyphs = out.glyphs;
		for (g in g0...g0 + sh.glyphCount(e)) {
			var cl = s + sh.cluster(g);
			if (!whole && (cl < from || cl >= to)) continue;
			if (sh.id(g) >= 0) glyphs.add(sh.face(g), sh.id(g), x + sh.dx(g), sh.dy(g), sh.advance(g), cl);
			x += sh.advance(g);
		}
	}

	// (the hyphen a break after piece p's soft hyphen shows, at x)
	function hyphen(p:Int, x:Float, slot:Int) {
		var item = c.pieceItem(p), e = hyphenEntry(item), f = c.font(item), sh = c.shaper;
		var h = fragment(Hyphen, item, x, sh.width(e), slot);
		out.fStart[h] = out.fEnd[h] = c.pieceEnd(p);
		out.fAscent[h] = c.fonts.ascent(f);
		out.fDescent[h] = c.fonts.descent(f);
		fRise[h] = out.fAscent[h];
		out.fRun[h] = out.glyphs.begin(c.fonts.set(f));
		var gx = 0.0;
		for (g in sh.glyphStart(e)...sh.glyphStart(e) + sh.glyphCount(e)) {
			out.glyphs.add(sh.face(g), sh.id(g), gx + sh.dx(g), sh.dy(g), sh.advance(g), c.pieceEnd(p));
			gx += sh.advance(g);
		}
	}

	function growLines() {
		var o = out, n = o.lTop.length * 2;
		o.lTop = floats(o.lTop, n);
		o.lHeight = floats(o.lHeight, n);
		o.lBaseline = floats(o.lBaseline, n);
		o.lWidth = floats(o.lWidth, n);
		o.lLeft = floats(o.lLeft, n);
		o.lAvail = floats(o.lAvail, n);
		o.lStart = ints(o.lStart, n);
		o.lEnd = ints(o.lEnd, n);
		o.lFirst = ints(o.lFirst, n);
		o.lLast = ints(o.lLast, n);
		o.lFlags = ints(o.lFlags, n);
	}

	function growFragments() {
		var o = out, n = o.fKind.length * 2;
		o.fKind = ints(o.fKind, n);
		o.fX = floats(o.fX, n);
		o.fY = floats(o.fY, n);
		o.fWidth = floats(o.fWidth, n);
		o.fHeight = floats(o.fHeight, n);
		o.fAscent = floats(o.fAscent, n);
		o.fDescent = floats(o.fDescent, n);
		o.fLevel = ints(o.fLevel, n);
		o.fItem = ints(o.fItem, n);
		o.fStart = ints(o.fStart, n);
		o.fEnd = ints(o.fEnd, n);
		o.fRun = ints(o.fRun, n);
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
}
