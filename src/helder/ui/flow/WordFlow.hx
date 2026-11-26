package helder.ui.flow;

import helder.canvas.ShapedRun;
import helder.text.FontFile;
import helder.ui.box.Box;
import helder.ui.box.BoxInline;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.Len;

using StringTools;

// The line builder's stand-in until the inline lane's lands (its
// InlineContent does the rest: white space, transforms, bidi levels, break
// opportunities, shaped words): lines filled greedily at the content's
// opportunities, collapsible spaces at their ends taking no room, line
// boxes as CSS 2.1 §10.8 makes them (each inline box's line height around
// its font's rounded ascent and descent, the strut, vertical-align),
// text-align and justify, text-indent, inline boxes' edges, outside
// markers; in logical order (no visual reordering). Its output is what
// the real builder's will be: line, span and text fragments with glyph
// runs. It builds the box tree's InlineContent (`collect`): the items in
// order, atomic inlines laid out first.
class WordFlow {
	static inline var WORD = 0;
	static inline var SPACE = 1;
	static inline var OPEN = 2;
	static inline var CLOSE = 3;
	static inline var ATOMIC = 4;
	static inline var NEWLINE = 5;
	// (out of flow: placed by the block, at the line they are met in)
	static inline var FLOAT = 6;
	static inline var ABSOLUTE = 7;

	final flow:BlockFlow;
	// (the content's atoms, kept between calls)
	final kinds:Array<Int> = [];
	final boxes:Array<Box> = [];
	final starts:Array<Int> = [];
	final ends:Array<Int> = [];
	final widths:Array<Float> = [];
	// (a space of a style that wraps: a break after it; a kept space: not removed at a line's ends)
	final breaks:Array<Bool> = [];
	final kept:Array<Bool> = [];
	final atomicFragments:Array<Int> = [];
	var count = 0;
	var markers:Array<Box> = [];

	public function new(flow:BlockFlow)
		this.flow = flow;

	// ---- the atoms: InlineContent's pieces

	var content:Null<InlineContent> = null;
	// (the width the content's styles resolve percentages against: theirs, made once)
	var cbWidth = 0.0;
	// (each atom's piece of the content: its shaped word read when its fragment is made, the
	// shaper's cache being emptied past its size, and the content shaped again, in between)
	final pieces:Array<Int> = [];

	// (atomic inlines are laid out while walking, their own lines with this:
	// the atoms are filled after)
	function collect(block:Box, space:Space, width:Float, pct:Float, measureOnly:Bool) {
		var found = [];
		var frags = space.fragments;
		var c = new InlineContent(BoxInline.of(block, width));
		var laid = new Map<Box, Int>();
		// (a text item's box by its DOM text; generated text's is its style's)
		var textBoxes = new haxe.ds.ObjectMap<helder.dom.Node, Box>();
		// (inline boxes and atomic inlines in order: their items come in that order, one piece each;
		// a style is shared by boxes alike, so it doesn't say which)
		var opened:Array<Box> = [], atomics:Array<Box> = [], outOfFlow:Array<Box> = [];
		function walk(b:Box) {
			var k = b.first;
			while (k != null) {
				switch k.kind {
					case Text:
						if (k.node != null) textBoxes.set(k.node, k);
						c.addText(k.text, BoxInline.of(k, width), k.node, k.offset);
					case Inline if (k.flags & Box.OUTSIDE != 0):
						found.push(k);
					case Inline:
						opened.push(k);
						c.openBox(BoxInline.of(k, width), k.node);
						walk(k);
						c.closeBox(k.node);
					case Break:
						c.addBreak(k.node, BoxInline.of(k, width));
					case _ if (k.floating || k.absolute):
						outOfFlow.push(k);
						if (measureOnly && k.floating) {
							if (k.context != null) k.context.intrinsic(k, space) else flow.intrinsic(k, space);
						}
						if (k.floating) c.addFloat(k.node) else c.addAbspos(k.node);
					case _:
						var w = 0.0, h = 0.0, base = Math.NaN;
						if (measureOnly) {
							if (k.context != null) k.context.intrinsic(k, space) else flow.intrinsic(k, space);
							w = k.maxContent;
						} else {
							var f = flow.child(k, space.child(width, pct));
							laid.set(k, f);
							w = frags.width(f);
							h = frags.height(f);
							base = frags.baseline(f);
						}
						atomics.push(k);
						c.addAtomic(w, h, base, BoxInline.of(k, width), k.node);
				}
				k = k.next;
			}
		}
		walk(block);
		c.finish();
		content = c;
		markers = found;
		cbWidth = width;
		count = 0;
		var openOf = new Map<Int, Box>(), nextOpen = 0, nextAtomic = 0, nextOut = 0;
		for (p in 0...c.pieces) {
			var item = c.pieceItem(p);
			var kind = switch c.pieceKind(p) {
				case InlineContent.WORD: WORD;
				case InlineContent.SPACE | InlineContent.TAB: SPACE;
				case _: switch c.kind(item) {
						case Open: OPEN;
						case Close: CLOSE;
						case Atomic: ATOMIC;
						case Break: NEWLINE;
						case Float: FLOAT;
						case Abspos: ABSOLUTE;
						case _: -1;
					}
			}
			if (kind < 0) continue;
			var style:BoxInline = kind == FLOAT || kind == ABSOLUTE ? null : cast c.style(kind == CLOSE ? c.match(item) : item);
			var keep = kind == SPACE && switch style.whiteSpaceCollapse() {
				case Collapse | PreserveBreaks | Discard: false;
				case _: true;
			}
			var start = c.pieceStart(p), end = c.pieceEnd(p);
			kinds[count] = kind;
			var source = c.source(item);
			var box = switch kind {
				case OPEN:
					var b = opened[nextOpen++];
					openOf.set(item, b);
					b;
				case CLOSE: openOf.get(c.match(item)) ?? style.box;
				case ATOMIC: atomics[nextAtomic++];
				case FLOAT | ABSOLUTE: outOfFlow[nextOut++];
				case WORD | SPACE if (source != null): textBoxes.get(source) ?? style.box;
				case _: style.box;
			}
			boxes[count] = box;
			starts[count] = start;
			ends[count] = end;
			widths[count] = c.pieceWidth(p);
			breaks[count] = c.pieceBreak(p) & LineBreaks.STATUS == LineBreaks.ALLOWED;
			kept[count] = keep;
			pieces[count] = p;
			atomicFragments[count] = kind == ATOMIC ? (laid.get(box) ?? -1) : -1;
			count++;
		}
	}

	static function codePoint(s:String, i:Int):Int {
		var c = s.fastCodeAt(i);
		if (c < 0xD800 || c >= 0xDC00 || i + 1 >= s.length) return c;
		var d = s.fastCodeAt(i + 1);
		return d >= 0xDC00 && d < 0xE000 ? ((c - 0xD800) << 10) + (d - 0xDC00) + 0x10000 : c;
	}

	// ---- intrinsic sizes (CSS Sizing 3: min-content breaks at every opportunity, max-content at forced ones)

	public function intrinsic(block:Box, space:Space):{min:Float, max:Float} {
		collect(block, space, 0, Math.NaN, true);
		var min = 0.0, max = 0.0, run = 0.0, line = 0.0, trailing = 0.0;
		var indent = Lens.resolve(block.style.len("text-indent"), 0, 0);
		line = indent;
		run = indent;
		for (i in 0...count) {
			var w = widths[i];
			if (breaks[i]) {
				min = Math.max(min, run - trailing);
				run = 0;
			}
			switch kinds[i] {
				case ATOMIC:
					var b = boxes[i];
					var m = fixed(b.style.model().margin[1]) + fixed(b.style.margin[3]);
					run += b.minContent + m;
					line += b.maxContent + m;
					trailing = 0;
				case SPACE:
					run += w;
					line += w;
					trailing = kept[i] ? 0 : trailing + w;
				case FLOAT:
					var b = boxes[i];
					var m = fixed(b.style.model().margin[1]) + fixed(b.style.margin[3]);
					min = Math.max(min, b.minContent + m);
					line += b.maxContent + m;
				case ABSOLUTE:
				case NEWLINE:
					min = Math.max(min, run - trailing);
					max = Math.max(max, line - trailing);
					run = line = trailing = 0;
				case _:
					run += w;
					line += w;
					if (kinds[i] == WORD) trailing = 0;
			}
		}
		min = Math.max(min, run - trailing);
		max = Math.max(max, line - trailing);
		return {min: min, max: Math.max(min, max)};
	}

	// ---- lines

	public function layout(block:Box, width:Float, space:Space, frag:Int, ox:Float, oy:Float, pct:Float):{height:Float, lines:Int, baseline:Float} {
		collect(block, space, width, pct, false);
		var bs = block.style;
		var indent = Lens.resolve(bs.len("text-indent"), width, 0);
		var align = bs.keyword("text-align-all");
		var last = bs.keyword("text-align-last");
		var strut = metrics(block, space.fonts);
		var y = 0.0, lines = 0, baseline = Math.NaN;
		var i = 0, first = true;
		// (the inline boxes open where a line starts)
		var open:Array<Box> = [];
		// (floats and absolutely positioned boxes placed once, where their line is first tried)
		var done = [for (_ in 0...count) false];
		var avail = width, left = 0.0, next = Math.POSITIVE_INFINITY;
		function room() {
			var lw = space.lineWidth == null ? null : space.lineWidth(oy + y, strut.height);
			avail = lw == null ? width : lw.width;
			left = lw == null ? 0 : lw.offset - ox;
			next = lw == null ? Math.POSITIVE_INFINITY : lw.next - oy;
		}
		while (i < count || first) {
			room();
			var x = first ? indent : 0.0;
			var start = i, lastBreak = -1, forced = false, filled = false;
			while (i < count) {
				var k = kinds[i];
				if (k == NEWLINE) {
					forced = true;
					i++;
					break;
				}
				if (k == FLOAT || k == ABSOLUTE) {
					if (!done[i]) {
						done[i] = true;
						if (k == FLOAT) {
							if (space.placeFloat != null) {
								// (the float's own lines are laid out by this: these atoms kept around it)
								var saved = save();
								space.placeFloat(saved.boxes[i], oy + y);
								load(saved);
							}
							room();
						} else if (space.placeAbsolute != null) space.placeAbsolute(boxes[i], ox + left + x, oy + y);
					}
					i++;
					continue;
				}
				if (breaks[i] && i > start) lastBreak = i;
				var w = widths[i];
				if ((k == WORD || k == ATOMIC) && x + w > avail + 0.001) {
					if (lastBreak > start) {
						i = lastBreak;
						break;
					}
					// (nothing fits beside the floats here: the line goes down to where they end, §9.5)
					if (!filled && next < Math.POSITIVE_INFINITY && next > y) {
						y = next;
						i = start;
						room();
						x = first ? indent : 0.0;
						lastBreak = -1;
						continue;
					}
				}
				if (k == WORD || k == ATOMIC) filled = true;
				x += w;
				i++;
			}
			var end = i;
			var lastLine = i >= count || forced;
			var h = line(block, space, frag, start, end, open, ox + left, oy + y, avail, first ? indent : 0, lastLine ? (last == "auto" || last == "" ? align : last) : align, strut, first && markers.length > 0);
			if (h.height > 0 || h.content) {
				baseline = y + h.baseline;
				lines++;
			}
			y += h.height;
			for (k in start...end) switch kinds[k] {
				case OPEN: open.push(boxes[k]);
				case CLOSE: open.remove(boxes[k]);
				case _:
			}
			first = false;
			if (start == end && i >= count) break;
		}
		return {height: y, lines: lines, baseline: baseline};
	}

	// (an inline box's metrics: its font's rounded ascent and descent, its line height's leading around them, §10.8.1)
	function metrics(b:Box, fonts:FontMatch):Metrics {
		var style = BoxInline.of(b, cbWidth);
		var f = content.fonts, id = f.idOf(style);
		var a = f.ascent(id), d = f.descent(id);
		var lh = style.lineHeight();
		if (Math.isNaN(lh)) lh = f.normalLineHeight(id);
		var above = a + Math.floor((lh - (a + d)) / 2);
		return {
			ascent: a,
			descent: d,
			above: above,
			below: lh - above,
			height: lh,
			size: style.fontSize(),
			face: f.set(id).primary,
			xHeight: f.xHeight(id)
		};
	}

	// One line box of atoms start...end: its inline boxes' and atomics'
	// places, its height and baseline; its fragments added under frag.
	function line(block:Box, space:Space, frag:Int, start:Int, end:Int, open:Array<Box>, ox:Float, oy:Float, avail:Float, indent:Float,
			align:String, strut:Metrics, marker:Bool):{height:Float, baseline:Float, content:Bool} {
		var frags = space.fragments;
		// (collapsible spaces at the line's start and end take no room)
		var hidden = [for (k in start...end) false];
		var k = start;
		while (k < end && (kinds[k] == SPACE && !kept[k] || kinds[k] == OPEN || kinds[k] == CLOSE || kinds[k] >= FLOAT)) {
			if (kinds[k] == SPACE) hidden[k - start] = true;
			k++;
		}
		k = end - 1;
		while (k >= start && (kinds[k] == SPACE && !kept[k] || kinds[k] == OPEN || kinds[k] == CLOSE || kinds[k] == NEWLINE || kinds[k] >= FLOAT)) {
			if (kinds[k] == SPACE) hidden[k - start] = true;
			k--;
		}
		// (spans: the line's root inline box first, then each inline box on it)
		var spans:Array<Span> = [{
			box: block,
			parent: -1,
			m: strut,
			offset: 0,
			x0: 0,
			x1: 0,
			start: false,
			end: false,
			align: "baseline",
			frag: -1
		}];
		var stack = [0];
		function openSpan(b:Box, x:Float, startEdge:Bool) {
			var parent = stack[stack.length - 1];
			var m = metrics(b, space.fonts);
			var va = valign(b);
			var po = spans[parent].offset, pm = spans[parent].m;
			var off = switch va.kind {
				case "sub": po + pm.size / 5 + 1;
				case "super": po - pm.size / 3 - 1;
				case "text-top": po - pm.ascent + m.above;
				case "text-bottom": po + pm.descent - m.below;
				case "middle": po - pm.xHeight / 2 - (m.below - m.above) / 2;
				case "shift": po - va.shift;
				case "percent": po - va.shift * m.height / 100;
				case _: po;
			}
			spans.push({
				box: b,
				parent: parent,
				m: m,
				offset: off,
				x0: x,
				x1: x,
				start: startEdge,
				end: false,
				align: va.kind,
				frag: -1
			});
			stack.push(spans.length - 1);
		}
		for (b in open) openSpan(b, 0, false);
		// (horizontal places)
		var x = indent;
		var xs = [for (_ in start...end) 0.0];
		var spanOf = [for (_ in start...end) 0];
		var content = false;
		for (k in start...end) {
			var w = hidden[k - start] ? 0 : widths[k];
			xs[k - start] = x;
			switch kinds[k] {
				case OPEN:
					openSpan(boxes[k], x, boxes[k].flags & Box.NO_START == 0);
					if (w != 0) content = true;
				case CLOSE:
					var top = stack.pop();
					spans[top].x1 = x + w;
					spans[top].end = boxes[k].flags & Box.NO_END == 0;
					if (w != 0) content = true;
				case WORD:
					content = true;
				case SPACE:
					if (kept[k]) content = true;
				case ATOMIC:
					content = true;
				case _:
			}
			spanOf[k - start] = stack[stack.length - 1];
			x += w;
		}
		while (stack.length > 1) spans[stack.pop()].x1 = x;
		var used = x;
		if (!content) {
			for (s in spans) if (s.box != block && edges(s, avail) != 0) content = true;
		}
		// (a line with nothing in it is of no height, its inline boxes still placed and painted: CSS 2.1 §9.4.2)
		if (!content && !marker && spans.length == 1 && start == end) return {height: 0, baseline: 0, content: false};
		// (vertical: each box's bounds around its baseline; top- and bottom-aligned subtrees apart)
		var top = -strut.above, bottom = strut.below;
		inline function inAligned(si:Int):Bool {
			var a = false;
			while (si > 0) {
				if (spans[si].align == "top" || spans[si].align == "bottom") a = true;
				si = spans[si].parent;
			}
			return a;
		}
		for (si in 1...spans.length) {
			var s = spans[si];
			if (inAligned(si)) continue;
			top = Math.min(top, s.offset - s.m.above);
			bottom = Math.max(bottom, s.offset + s.m.below);
		}
		var atomTop = [for (_ in start...end) 0.0];
		for (k in start...end) if (kinds[k] == ATOMIC) {
			var b = boxes[k], f = atomicFragments[k];
			var bs = b.style.model();
			var mt = res(bs.margin[0], avail), mb = res(bs.margin[2], avail);
			var h = frags.height(f) + mt + mb;
			var bl = frags.baseline(f);
			var base = b.kind == InlineReplaced || Math.isNaN(bl) ? h : mt + bl;
			var si = spanOf[k - start];
			var po = spans[si].offset, pm = spans[si].m;
			var va = valign(b);
			var t = switch va.kind {
				case "middle": po - pm.xHeight / 2 - h / 2;
				case "text-top": po - pm.ascent;
				case "text-bottom": po + pm.descent - h;
				case "sub": po + pm.size / 5 + 1 - base;
				case "super": po - pm.size / 3 - 1 - base;
				case "shift": po - va.shift - base;
				case "percent": po - va.shift * metrics(b, space.fonts).height / 100 - base;
				case _: po - base;
			}
			atomTop[k - start] = t;
			if (va.kind == "top" || va.kind == "bottom" || inAligned(si)) continue;
			top = Math.min(top, t);
			bottom = Math.max(bottom, t + h);
		}
		// (top and bottom: against the line box, which they may make taller)
		for (si in 1...spans.length) {
			var s = spans[si];
			if (s.align != "top" && s.align != "bottom") continue;
			var h = s.m.above + s.m.below;
			if (h > bottom - top) {
				if (s.align == "top") bottom = top + h else top = bottom - h;
			}
			var want = s.align == "top" ? top + s.m.above : bottom - s.m.below;
			var shift = want - s.offset;
			for (sj in si...spans.length) if (sj == si || descends(spans, sj, si)) spans[sj].offset += shift;
		}
		for (k in start...end) if (kinds[k] == ATOMIC) {
			var b = boxes[k];
			var va = valign(b);
			if (va.kind != "top" && va.kind != "bottom") continue;
			var f = atomicFragments[k];
			var bs = b.style.model();
			var h = frags.height(f) + res(bs.margin[0], avail) + res(bs.margin[2], avail);
			if (h > bottom - top) {
				if (va.kind == "top") bottom = top + h else top = bottom - h;
			}
			atomTop[k - start] = va.kind == "top" ? top : bottom - h;
		}
		var height = content || marker ? bottom - top : 0.0, baseline = -top;
		// (alignment)
		var slack = avail - used;
		var rtl = block.style.rtl;
		var shift = switch align {
			case "right" | "-webkit-right": slack;
			case "center" | "-webkit-center": slack / 2;
			case "end": rtl ? 0 : slack;
			case "start" | "": rtl ? slack : 0;
			case "left" | "-webkit-left": 0;
			case _: rtl ? slack : 0;
		}
		if (shift < 0) shift = 0;
		var spaceShare = 0.0;
		if (align == "justify" && slack > 0) {
			var gaps = 0;
			for (k in start...end) if (kinds[k] == SPACE && !hidden[k - start]) gaps++;
			var lastLine = end >= count || kinds[end - 1] == NEWLINE;
			if (gaps > 0 && !lastLine) spaceShare = slack / gaps;
		}
		// (fragments: the line, its spans, its text and atomics)
		var lineFrag = frags.add(Fragments.LINE, block, avail, height);
		frags.adopt(frag, lineFrag, ox, oy);
		frags.setBaseline(lineFrag, baseline);
		var extra = 0.0;
		var absX = [for (k in start...end) 0.0];
		for (k in start...end) {
			absX[k - start] = xs[k - start] + shift + extra;
			if (kinds[k] == SPACE && !hidden[k - start]) extra += spaceShare;
		}
		inline function px(k:Int):Float
			return absX[k - start];
		// (span boxes' x from their atoms: the open's x, the close's end)
		for (si in 1...spans.length) {
			var s = spans[si];
			s.x0 += shift;
			s.x1 += shift;
		}
		for (k in start...end) switch kinds[k] {
			case OPEN:
				for (si in 1...spans.length) if (spans[si].box == boxes[k] && spans[si].start) spans[si].x0 = px(k);
			case CLOSE:
				for (si in 1...spans.length) if (spans[si].box == boxes[k] && spans[si].end) spans[si].x1 = px(k) + widths[k];
			case _:
		}
		var spanX = [0.0], spanY = [0.0];
		var spanFrag = [lineFrag];
		for (si in 1...spans.length) {
			var s = spans[si];
			var bs = s.box.style.model();
			var ml = s.start ? res(bs.margin[3], avail) : 0, mr = s.end ? res(bs.margin[1], avail) : 0;
			var pt = res(bs.padding[0], avail), pb = res(bs.padding[2], avail);
			var bx = s.x0 + ml, bw = s.x1 - mr - bx;
			var by = baseline + s.offset - s.m.ascent - pt - bs.border[0];
			var bh = s.m.ascent + s.m.descent + pt + pb + bs.border[0] + bs.border[2];
			var f = frags.add(Fragments.SPAN, s.box, Math.max(0, bw), bh);
			frags.setRange(f, s.start ? 0 : Box.NO_START, s.end ? 0 : Box.NO_END);
			frags.setBaseline(f, s.offset + baseline - by);
			var off = BlockFlow.offset(s.box, avail, Math.NaN);
			var p = s.parent;
			frags.adopt(spanFrag[p], f, bx - spanX[p] + off.x, by - spanY[p] + off.y);
			spanX.push(bx);
			spanY.push(by);
			spanFrag.push(f);
			s.frag = f;
		}
		// (text: consecutive words and spaces of one run in one fragment)
		var k = start;
		while (k < end) {
			var kind = kinds[k];
			if (kind == ATOMIC) {
				var b = boxes[k], f = atomicFragments[k], si = spanOf[k - start];
				var bs = b.style.model();
				var off = BlockFlow.offset(b, avail, Math.NaN);
				frags.adopt(spanFrag[si], f, px(k) + b.marginLeft - spanX[si] + off.x, baseline + atomTop[k - start] + res(bs.margin[0], avail) - spanY[si] + off.y);
				k++;
				continue;
			}
			if (kind != WORD && kind != SPACE || hidden[k - start]) {
				k++;
				continue;
			}
			var b = boxes[k], si = spanOf[k - start];
			var e = k;
			while (e < end && boxes[e] == b && (kinds[e] == WORD || kinds[e] == SPACE) && !hidden[e - start]) e++;
			textFragment(space, b, k, e, px(k), spaceShare, baseline, spans, si, spanFrag[si], spanX[si], spanY[si]);
			k = e;
		}
		if (marker) markersOn(space, block, lineFrag, baseline, spans[0], rtl ? avail : 0, rtl);
		return {height: height, baseline: baseline, content: content || marker};
	}

	static function descends(spans:Array<Span>, sj:Int, si:Int):Bool {
		var p = spans[sj].parent;
		while (p > 0) {
			if (p == si) return true;
			p = spans[p].parent;
		}
		return false;
	}

	// (an inline box's horizontal margins, borders and padding on this line)
	function edges(s:Span, avail:Float):Float {
		var st = BoxInline.of(s.box, cbWidth);
		return (s.start ? st.marginStart() + st.borderStart() + st.paddingStart() : 0) + (s.end ? st.marginEnd() + st.borderEnd() + st.paddingEnd() : 0);
	}

	// (text fragments of atoms k...e of one run: their content area, a glyph run of each face)
	function textFragment(space:Space, b:Box, k:Int, e:Int, x:Float, spaceShare:Float, baseline:Float, spans:Array<Span>, si:Int, parent:Int, px:Float,
			py:Float) {
		var frags = space.fragments, c = content, shaper = c.shaper;
		c.ensureShaped();
		var m = spans[si].box == b.parent ? spans[si].m : metrics(b, space.fonts);
		var top = baseline + spans[si].offset - m.ascent;
		var run:Null<ShapedRun> = null, runX = 0.0, pen = 0.0, from = starts[k], to = from;
		var all = c.text.substring(starts[k], ends[e - 1]);
		var glyphs = 0;
		for (a in k...e) {
			var en = c.pieceEntry(pieces[a]);
			if (en >= 0) glyphs += shaper.glyphCount(en);
		}
		function flush() {
			if (run == null || run.count == 0) return;
			run.text = all;
			var f = frags.add(Fragments.TEXT, b, pen - runX, m.ascent + m.descent);
			frags.setRange(f, c.domOffset(from), to > from ? c.domOffset(to - 1) + 1 : c.domOffset(from));
			frags.setBaseline(f, m.ascent);
			frags.setRun(f, frags.runs.length);
			frags.runs.push(run);
			frags.adopt(parent, f, x + runX - px, top - py);
			run = null;
		}
		for (a in k...e) {
			var en = c.pieceEntry(pieces[a]);
			if (en >= 0) {
				var g0 = shaper.glyphStart(en);
				for (g in g0...g0 + shaper.glyphCount(en)) {
					var face = shaper.face(g);
					if (run == null || run.face != face) {
						flush();
						run = new ShapedRun(face, m.size);
						sized(run, glyphs);
						runX = pen;
						from = starts[a] + shaper.cluster(g);
					}
					var unit = starts[a] - starts[k] + shaper.cluster(g);
					run.push(shaper.id(g), pen - runX + shaper.dx(g), shaper.dy(g), unit, unit + 1);
					pen += shaper.advance(g);
					to = starts[a] + shaper.cluster(g) + 1;
				}
				to = ends[a];
			} else
				pen += widths[a];
			if (kinds[a] == SPACE) pen += spaceShare;
		}
		flush();
	}

	// (the atoms of the content being laid out, copied while another is: a float in a line)
	function save():Saved
		return {
			kinds: kinds.slice(0, count),
			boxes: boxes.slice(0, count),
			starts: starts.slice(0, count),
			ends: ends.slice(0, count),
			widths: widths.slice(0, count),
			breaks: breaks.slice(0, count),
			kept: kept.slice(0, count),
			atomicFragments: atomicFragments.slice(0, count),
			pieces: pieces.slice(0, count),
			count: count,
			markers: markers,
			content: content,
			cbWidth: cbWidth
		};

	function load(s:Saved) {
		for (k in 0...s.count) {
			kinds[k] = s.kinds[k];
			boxes[k] = s.boxes[k];
			starts[k] = s.starts[k];
			ends[k] = s.ends[k];
			widths[k] = s.widths[k];
			breaks[k] = s.breaks[k];
			kept[k] = s.kept[k];
			atomicFragments[k] = s.atomicFragments[k];
			pieces[k] = s.pieces[k];
		}
		count = s.count;
		markers = s.markers;
		content = s.content;
		cbWidth = s.cbWidth;
	}

	// (a run's columns made their size at once: grown one glyph at a time, each push copies)
	static function sized(run:ShapedRun, n:Int) {
		run.ids.resize(n);
		run.xs.resize(n);
		run.ys.resize(n);
		run.starts.resize(n);
		run.ends.resize(n);
	}

	// (outside markers: before the first line's start, on its baseline)
	function markersOn(space:Space, block:Box, lineFrag:Int, baseline:Float, root:Span, edge:Float, rtl:Bool) {
		var frags = space.fragments;
		for (mk in markers) {
			var t = mk.first;
			if (t == null || t.kind != Text) continue;
			var s = mk.style;
			var m = metrics(mk, space.fonts);
			var face = space.fonts.face(s), size = FontMatch.size(s);
			var run = new ShapedRun(face, size);
			var pen = 0.0;
			var i = 0;
			while (i < t.text.length) {
				var cp = codePoint(t.text, i);
				var n = cp > 0xFFFF ? 2 : 1;
				var g = face.glyph(cp);
				run.push(g, pen, 0, i, i + n);
				pen += face.advanceAt(g, size);
				i += n;
			}
			run.text = t.text;
			var x = rtl ? edge : edge - pen;
			var span = frags.add(Fragments.SPAN, mk, pen, m.ascent + m.descent);
			frags.adopt(lineFrag, span, x, baseline - m.ascent);
			frags.setBaseline(span, m.ascent);
			var f = frags.add(Fragments.TEXT, t, pen, m.ascent + m.descent);
			frags.setRange(f, 0, t.text.length);
			frags.setBaseline(f, m.ascent);
			frags.setRun(f, frags.runs.length);
			frags.runs.push(run);
			frags.adopt(span, f, 0, 0);
		}
	}

	static function valign(b:Box):{kind:String, shift:Float} {
		var v = b.style.verticalAlign();
		return v.kind == "length" ? {kind: "shift", shift: v.shift} : v;
	}

	static inline function res(l:Len, base:Float):Float {
		var v = Lens.resolve(l, base, 0);
		return Math.isNaN(v) ? 0 : v;
	}

	static function fixed(l:Len):Float
		return switch l {
			case Px(v): v;
			case _: 0;
		}
}

private typedef Saved = {
	kinds:Array<Int>,
	boxes:Array<Box>,
	starts:Array<Int>,
	ends:Array<Int>,
	widths:Array<Float>,
	breaks:Array<Bool>,
	kept:Array<Bool>,
	atomicFragments:Array<Int>,
	pieces:Array<Int>,
	count:Int,
	markers:Array<Box>,
	content:Null<InlineContent>,
	cbWidth:Float
}

private typedef Metrics = {ascent:Float, descent:Float, above:Float, below:Float, height:Float, size:Float, face:FontFile, xHeight:Float}

private typedef Span = {
	box:Box,
	parent:Int,
	m:Metrics,
	offset:Float,
	x0:Float,
	x1:Float,
	start:Bool,
	end:Bool,
	align:String,
	frag:Int
}
