package helder.ui.flow;

import helder.canvas.ShapedRun;
import helder.dom.Node;
import helder.ui.box.Box;
import helder.ui.box.BoxInline;
import helder.ui.box.BoxKind;
import helder.ui.box.Fragments;
import helder.ui.box.Len.Lens;
import helder.ui.flow.InlineLayout;

// A block container's lines: its inline formatting context built from the
// box tree (InlineContent: text runs with their DOM text, inline boxes
// opened and closed, atomic inlines laid out first, forced breaks, floats'
// and absolutely positioned boxes' places), laid out by the inline lane's
// engine (InlineLayout, LineBuilder), and its output made fragments: a
// line each, its inline boxes' spans nested as the boxes are, text runs
// with their glyph runs, atomics, hyphens and ellipses. Floats met in the
// lines are placed at the top of the line they are in, and the lines laid
// out again around them until they stay; absolutely positioned boxes get
// their static place. Outside list markers sit before the first line.
class BlockLines {
	final flow:BlockFlow;
	// (one engine layout a nesting depth: an atomic inline's lines are laid out inside another's)
	final layouts:Array<InlineLayout> = [];
	var depth = 0;
	// (a block's leaders filled: built as they are)
	var filling = false;
	final markerLayout = new InlineLayout();
	static final NO_BOXES:Array<Box> = [];
	static final NO_FRAGMENTS:Array<Int> = [];
	// (text's: each glyph's characters' end)
	final ends:Array<Int> = [];
	// (a line's spans and adoptions, fragments(): stamped per line, kept to grow)
	var lineStamp = 0;
	final spanStamp:Array<Int> = [];
	final spanOf:Array<Int> = [];
	final spanX:Array<Float> = [];
	final spanY:Array<Float> = [];
	final firstStamp:Array<Int> = [];
	final firstOf:Array<Int> = [];
	final aParent:Array<Int> = [];
	final aChild:Array<Int> = [];
	final aX:Array<Float> = [];
	final aY:Array<Float> = [];

	public function new(flow:BlockFlow)
		this.flow = flow;

	public function layout(block:Box, width:Float, space:Space, frag:Int, ox:Float, oy:Float, pct:Float):{height:Float, lines:Int, baseline:Float} {
		var built = build(block, space, width, pct, false);
		var c = built.content;
		var frags = space.fragments;
		if (layouts.length <= depth) layouts.push(new InlineLayout());
		var l = layouts[depth++];
		// (in a fragmentainer, resumed at a line: laid out from its break, the lines before it and their floats
		// were in the fragmentainers before)
		var fr = space.fragmentation;
		var resume = fr != null ? fr.resume(block) : null;
		var from = resume != null ? resume.from : null;
		// (resumed inside a line past the fragmentainer's end: the lines from it up by what the ones before showed of it,
		// clipped to the page)
		var shift = resume != null && resume.line == BreakToken.LINE ? resume.shift ?? 0.0 : 0.0;
		if (shift > 0) block.flags |= Box.SLICED;
		oy -= shift;
		// (the function, not the space's field: the lines are laid out again for hit testing, the space gone on)
		var lineWidth = space.lineWidth, narrowed = false;
		var constraints = new InlineConstraints(width, lineWidth == null ? null : (y, h) -> {
			var lw = lineWidth(oy + y, h);
			if (lw != null) narrowed = true;
			return lw == null ? {offset: 0.0, width: width} : {offset: lw.offset - ox, width: lw.width};
		});
		constraints.exactMetrics = space.exact;
		constraints.lazyText = true;
		try {
			// (floats placed where their lines put them, the lines then laid out around them: until they stay)
			var floats:Array<Box> = [];
			var tops:Array<Float> = [], bottoms:Array<Float> = [];
			var placed = 0;
			function lay() {
				var skipped = 0;
				if (from != null) {
					var end = from.piece < c.pieces ? c.pieceItem(from.piece) : c.items;
					for (i in 0...end) if (c.kind(i) == Float) skipped++;
				}
				floats = built.floats.slice(skipped);
				for (round in 0...(floats.length > 0 && space.placeFloat != null ? 4 : 1)) {
					l.layout(c, constraints, from);
					if (floats.length == 0 || space.placeFloat == null) break;
					var at = statics(l, InlineFragment.Float);
					var same = round > 0 && at.length == tops.length;
					if (same) for (k in 0...at.length) if (at[k].y != tops[k]) same = false;
					if (same) break;
					if (round > 0 && space.unplace != null) space.unplace(placed);
					tops = [for (a in at) a.y];
					bottoms = [];
					placed = 0;
					for (k in 0...floats.length) {
						bottoms.push(space.placeFloat(floats[k], oy + (k < tops.length ? tops[k] : 0)) - oy);
						placed++;
					}
				}
			}
			lay();
			// (leaders: their fill repeated to their lines' room, the lines laid out again)
			if (built.leaders.length > 0 && fill(l, built)) {
				if (placed > 0 && space.unplace != null) space.unplace(placed);
				placed = 0;
				tops = [];
				filling = true;
				built = build(block, space, width, pct, false);
				filling = false;
				c = built.content;
				lay();
			}
			// (class B: between lines, from the second here, the floats of the lines before it before it too; a
			// break taken ends this fragment's lines)
			var last = l.lines, overflows = false;
			if (fr != null) {
				var top = space.reserve + space.pageTop - shift, next = 0;
				for (k in 0...l.lines) {
					while (next < bottoms.length && next < tops.length && tops[next] < l.lineTop(k)) fr.floated(top + bottoms[next++]);
					var bottom = top + (k == 0 ? 0 : l.lineTop(k - 1) + l.lineHeight(k - 1));
					if (fr.inLines(block, 0, k, l.lines, bottom, l.breakAt(k)) || fr.stopped) {
						last = k;
						break;
					}
					// (a line past the end at the fragmentainer's top, nothing before it here to break at, monolithic: a break
					// inside it, its overflow on the pages after; elsewhere it goes to the next whole)
					var lineTop = space.pageTop - shift + l.lineTop(k);
					if (lineTop <= 0.01 && lineTop + l.lineHeight(k) + space.reserve > fr.size + 0.01 && fr.overflowing(block, l.breakAt(k), lineTop)) {
						block.flags |= Box.SLICED;
						last = k + 1;
						overflows = true;
						break;
					}
				}
				if (last == l.lines) while (next < bottoms.length) fr.floated(top + bottoms[next++]);
			}
			var end = last < l.lines ? l.lineTop(last) : Math.POSITIVE_INFINITY;
			// (the floats of the lines from last on: the next fragmentainer's)
			if (last < l.lines && space.unplace != null) {
				var later = 0;
				for (k in 0...floats.length) if (k < tops.length && tops[k] >= end) later++;
				if (later > 0) space.unplace(later);
			}
			if (space.placeAbsolute != null) {
				var at = absoluteStatics(l, built.absolutes, width, block.style.rtl);
				for (k in 0...built.absolutes.length)
					if (k < at.length && at[k].y < end) space.placeAbsolute(built.absolutes[k], ox + at[k].x, oy + at[k].y);
			}
			var r = fragments(l, built, space, frag, ox, oy, constraints, 0, last);
			if (fr == null) {
				c.compact();
				// (a hit test's lines have their glyphs; no floats beside them: no callback kept, nor the layout's
				// space it reaches, which a long document's blocks would each hold till their next layout)
				constraints.lazyText = false;
				if (!narrowed) constraints.lineWidth = null;
				block.lines = new BlockText(c, constraints, frag, ox, oy);
			}
			depth--;
			// (broken inside a line: its content to the fragmentainer's end, the rest of the line's overflow)
			var h = r.height - shift;
			if (overflows) h = Math.min(h, fr.size - space.reserve - space.pageTop);
			return h != r.height ? {height: Math.max(0, h), lines: r.lines, baseline: r.baseline - shift} : r;
		} catch (e:haxe.Exception) {
			depth--;
			throw e;
		}
	}

	public function intrinsic(block:Box, space:Space):{min:Float, max:Float} {
		var built = build(block, space, 0, Math.NaN, true, true);
		var min = built.content;
		// (atomics are as wide as their min-content in one, their max-content in the other: else one does)
		var max = built.atomics.length > 0 ? build(block, space, 0, Math.NaN, true, false).content : min;
		var lo = InlineLayout.minContent(min), hi = InlineLayout.maxContent(max);
		// (floats: as wide as their own, beside the lines at most)
		var c = block.first;
		var floats = 0.0;
		while (c != null) {
			if (c.floating) {
				var m = c.style.model();
				var edges = BlockFlow.fixed(m.margin[1]) + BlockFlow.fixed(m.margin[3]);
				lo = Math.max(lo, c.minContent + edges);
				floats += c.maxContent + edges;
			}
			c = c.next;
		}
		return {min: lo, max: Math.max(lo, hi + floats)};
	}

	// (each leader's text its fill as often as its line's room takes, from
	// one fill's width there: whether one changed)
	static function fill(l:InlineLayout, built:Built):Bool {
		var c = built.content, changed = false;
		for (box in built.leaders) {
			for (k in 0...l.lines) {
				var w = 0.0;
				for (f in l.lineFragmentStart(k)...l.lineFragmentEnd(k))
					if (l.kind(f) == TextRun && (cast c.style(l.item(f)) : BoxInline).box == box) w += l.fragmentWidth(f);
				if (w <= 0) continue;
				var copies = Std.int(box.text.length / box.fill.length);
				var one = w / Math.max(1, copies);
				var n = copies + Std.int(Math.max(0, l.lineAvailable(k) - l.lineWidth(k)) / one);
				var text = [for (_ in 0...n) box.fill].join("");
				if (text != box.text) {
					box.text = text;
					changed = true;
				}
				break;
			}
		}
		return changed;
	}

	// (the places of the fragments of a kind, in order)
	static function statics(l:InlineLayout, kind:InlineFragment):Array<{x:Float, y:Float}> {
		var out = [];
		for (f in 0...l.fragments) if (l.kind(f) == kind) out.push({x: l.x(f), y: l.y(f)});
		return out;
	}

	// (absolutely positioned boxes' static places: an inline-level one's
	// where the line has it; one block-level before blockification
	// (originalDisplay) as a block would be: at the content edge where its
	// line starts, or where the next one does when in-flow content comes
	// before it on its line, as LayoutNG has it)
	static function absoluteStatics(l:InlineLayout, boxes:Array<Box>, width:Float, rtl:Bool):Array<{x:Float, y:Float}> {
		var out = [], k = 0;
		for (line in 0...l.lines)
			for (f in l.lineFragmentStart(line)...l.lineFragmentEnd(line)) {
				if (l.kind(f) != InlineFragment.Abspos) continue;
				var box = k < boxes.length ? boxes[k] : null;
				k++;
				if (box == null || box.style.css.originalDisplay.outer != Block) {
					out.push({x: l.x(f), y: l.y(f)});
					continue;
				}
				var before = false;
				for (g in l.lineFragmentStart(line)...l.lineFragmentEnd(line))
					switch l.kind(g) {
						case TextRun | Atomic if (l.item(g) < l.item(f)): before = true;
						case _:
					}
				out.push({x: rtl ? width : 0, y: before ? l.lineTop(line) + l.lineHeight(line) : l.lineTop(line)});
			}
		return out;
	}

	// ---- the content

	// (the box tree's inline content: atomics laid out first (measure: their min- or max-content as their
	// width), the boxes behind its items in the order they come)
	function build(block:Box, space:Space, width:Float, pct:Float, measure:Bool, min = false):Built {
		// (kept from a build before: text, inline boxes and breaks alone, none of them a percentage of the width;
		// on pages none: a cross-reference's text changes between their passes)
		var kept:Null<Built> = space.exact ? null : cast block.inlineCache;
		if (kept != null) return kept;
		var frags = space.fragments;
		var relative = widthRelative(block, true);
		var c = new InlineContent(BoxInline.of(block, width), space.fonts.inlines);
		var out = new Built(c);
		var runs:Array<Box> = [];
		function walk(b:Box) {
			var k = b.first;
			while (k != null) {
				switch k.kind {
					case Text:
						if (k.node != null) runs.push(k);
						// (a leader: one fill, unless the lines just filled it)
						if (k.flags & Box.LEADER != 0) {
							if (!filling) k.text = k.fill;
							out.leaders.push(k);
						}
						c.addText(k.text, BoxInline.of(k, width), k.node, k.offset);
					case Inline if (k.flags & Box.OUTSIDE != 0):
						out.markers.push(k);
					case Inline:
						if (widthRelative(k, false)) relative = true;
						out.opened.push(k);
						c.openBox(BoxInline.of(k, width), k.node);
						walk(k);
						c.closeBox(k.node);
					case Break:
						c.addBreak(k.node, BoxInline.of(k, width));
					case _ if (k.floating):
						if (measure) {
							if (k.context != null) k.context.intrinsic(k, space) else flow.intrinsic(k, space);
						}
						out.floats.push(k);
						c.addFloat(k.node);
					case _ if (k.absolute):
						out.absolutes.push(k);
						c.addAbspos(k.node);
					case _:
						var w = 0.0, h = 0.0, base = Math.NaN, f = -1;
						if (measure) {
							if (k.context != null) k.context.intrinsic(k, space) else flow.intrinsic(k, space);
							w = min ? k.minContent : k.maxContent;
						} else {
							f = flow.child(k, space.child(width, pct));
							w = frags.width(f);
							h = frags.height(f);
							base = frags.baseline(f);
						}
						out.atomics.push(k);
						out.laid.push(f);
						// (its border box, its baseline from its top: NaN its bottom margin edge; its margins its style's)
						c.addAtomic(w, h, k.kind == InlineReplaced ? Math.NaN : base, BoxInline.of(k, width), k.node);
				}
				k = k.next;
			}
		}
		walk(block);
		c.finish();
		// (each text item's run: the runs come in the items' order, a DOM text's ::first-letter's and the
		// rest told apart by the offset of the item's first unit)
		var t = 0;
		out.texts = new haxe.ds.Vector(c.items);
		for (i in 0...c.items) {
			var source = c.kind(i) == Text ? c.source(i) : null;
			if (source == null) continue;
			var at = c.end(i) > c.start(i) ? c.domOffset(c.start(i)) : -1, k = t;
			while (k < runs.length && (runs[k].node != source || at >= 0 && at >= runs[k].offset + runs[k].text.length && k + 1 < runs.length && runs[k + 1].node == source))
				k++;
			if (k < runs.length) t = k;
			out.texts[i] = k < runs.length ? runs[k] : null;
		}
		// (what a later layout and the sizes' questions take again: the same at any width; a live
		// document's changes let it go, DocumentView.stale)
		// (absolutely positioned boxes too: their static places are worked out from the lines each layout)
		if (!space.exact && !relative && out.atomics.length == 0 && out.floats.length == 0 && out.leaders.length == 0) {
			// (a block each keeps one: the empty lists shared, the content cut to size)
			out.atomics = out.floats = out.leaders = NO_BOXES;
			if (out.absolutes.length == 0) out.absolutes = NO_BOXES;
			out.laid = NO_FRAGMENTS;
			if (out.opened.length == 0) out.opened = NO_BOXES;
			if (out.markers.length == 0) out.markers = NO_BOXES;
			c.compact();
			block.inlineCache = out;
		}
		return out;
	}

	// (whether its inline edges or text-indent take a percentage of the width)
	static function widthRelative(b:Box, block:Bool):Bool {
		var m = b.style.model();
		if (block) return Lens.relative(b.style.len("text-indent"));
		for (k in 0...4) if (Lens.relative(m.margin[k]) || Lens.relative(m.padding[k])) return true;
		return false;
	}

	// ---- fragments

	// (lines from...to: a fragmentainer's part of them)
	function fragments(l:InlineLayout, built:Built, space:Space, frag:Int, ox:Float, oy:Float, constraints:InlineConstraints, from:Int,
			to:Int):{height:Float, lines:Int, baseline:Float} {
		// (where a line at y starts, the floats beside it: an outside marker goes before it)
		inline function edge(y:Float, h:Float):Float
			return constraints.lineWidth == null ? 0 : constraints.lineWidth(y, h).offset;
		var frags = space.fragments, c = built.content, glyphs = l.glyphs;
		// (an item's box: an inline box's by its Open item, an atomic's by order, text's by its DOM text)
		// (its place among the opened boxes or the atomics, by item; -1: neither)
		var slot = built.slots();
		inline function openBox(i:Int):Null<Box>
			return slot[i] >= 0 && slot[i] < built.opened.length ? built.opened[slot[i]] : null;
		inline function atomicFrag(i:Int):Int
			return slot[i] >= 0 && slot[i] < built.laid.length ? built.laid[slot[i]] : -1;
		function textBox(i:Int):Box {
			var b = i < built.texts.length ? built.texts[i] : null;
			return b != null ? b : (cast c.style(i) : BoxInline).box;
		}
		var root = (cast c.root : BoxInline).box, rtl = root.style.rtl, align = root.style.keyword("text-align");
		var startAligned = align == "" || align == "start" || align == "justify" || align == (rtl ? "right" : "left");
		var lines = 0, baseline = Math.NaN;
		for (k in from...to) {
			var top = l.lineTop(k), h = l.lineHeight(k);
			// (a leader's line: the leader takes what the line leaves, its copies whole from the end, so
			// what follows it is at the line's end, GCPM 3 §1.1, as WeasyPrint's: the room before them)
			var gap = 0.0, lx = 0.0, lr = 0.0;
			if (built.leaders.length > 0 && startAligned)
				for (f in l.lineFragmentStart(k)...l.lineFragmentEnd(k))
					if (l.kind(f) == TextRun && textBox(l.item(f)).flags & Box.LEADER != 0) {
						gap = Math.max(0, l.lineAvailable(k) - l.lineWidth(k));
						lx = l.x(f);
						lr = lx + l.fragmentWidth(f);
						break;
					}
			// (a span around the leader, from before it: as much wider)
			inline function around(f:Int):Bool {
				var x = l.x(f), w = l.fragmentWidth(f);
				return gap > 0 && l.kind(f) == BoxSpan && (rtl ? x + w > lr + 1e-6 && x <= lx + 1e-6 : x < lx - 1e-6 && x + w >= lr - 1e-6);
			}
			inline function fx(f:Int):Float {
				var x = l.x(f), w = l.fragmentWidth(f);
				return gap == 0 ? x : rtl ? (x + w <= lr + 1e-6 || around(f) ? x - gap : x) : (x >= lx - 1e-6 ? x + gap : x);
			}
			var line = frags.add(Fragments.LINE, (cast c.root : BoxInline).box, l.lineAvailable(k), h);
			frags.adopt(frag, line, ox, oy + top);
			frags.setBaseline(line, l.lineBaseline(k));
			if (h > 0) {
				lines++;
				baseline = top + l.lineBaseline(k);
			}
			// (its marker first, the item's first child)
			if (k == 0 && l.from == null && built.markers.length > 0) markers(space, built.markers, line, l.lineBaseline(k), edge(top, h), rtl, l.lineAvailable(k));
			// (spans made first, outer ones before inner: the boxes' parts on this line, by their Open item;
			// then everything adopted in the line's order, a span where its first part on the line is, before
			// what it holds: the tree's order in a line of one direction, as paint and a PDF's text follow it;
			// a run of the other direction kept as shown, PdfWriter's ActualText giving its logical order)
			var start = l.lineFragmentStart(k), end = l.lineFragmentEnd(k);
			// (a line of text and atomics alone, no inline box's span on it: each in the line's order, into it)
			var spans = false;
			for (f in start...end) if (l.kind(f) == BoxSpan) spans = true;
			if (!spans) {
				for (f in start...end) switch l.kind(f) {
					case TextRun | Hyphen | Ellipsis:
						var item = l.item(f);
						text(space, l, f, textBox(item), c, line, fx(f), l.y(f) - top);
					case Atomic:
						var item = l.item(f), af = atomicFrag(item);
						if (af < 0) continue;
						var off = BlockFlow.offset(built.atomics[slot[item]], l.lineAvailable(k), Math.NaN);
						frags.adopt(line, af, fx(f) + off.x, l.y(f) - top + off.y);
					case _:
				}
				continue;
			}
			// (per item, stamped by the line: an Open's span and its place; a box's first fragment on the line)
			var stamp = ++lineStamp;
			if (spanStamp.length < c.items) {
				spanStamp.resize(c.items);
				spanOf.resize(c.items);
				spanX.resize(c.items);
				spanY.resize(c.items);
				firstStamp.resize(c.items);
				firstOf.resize(c.items);
				for (i in 0...c.items) spanStamp[i] = firstStamp[i] = 0;
			}
			inline function hasSpan(open:Int):Bool
				return spanStamp[open] == stamp;
			// (each fragment's adoption: its parent, the child (-1: a text run's, made then), its place)
			var n = end - start;
			if (aParent.length < n) {
				aParent.resize(n);
				aChild.resize(n);
				aX.resize(n);
				aY.resize(n);
			}
			for (k in 0...n) aParent[k] = -2;
			var order = [for (f in start...end) if (l.kind(f) == BoxSpan) f];
			order.sort((a, b) -> c.depth(l.item(a)) - c.depth(l.item(b)));
			for (f in order) {
				var open = l.item(f);
				var box = openBox(open);
				if (box == null) continue;
				var p = c.parent(open);
				while (p >= 0 && !hasSpan(p)) p = c.parent(p);
				var px = p >= 0 ? spanX[p] : 0.0, py = p >= 0 ? spanY[p] : top, pf = p >= 0 ? spanOf[p] : line;
				var sf = frags.add(Fragments.SPAN, box, l.fragmentWidth(f) + (around(f) ? gap : 0), l.fragmentHeight(f));
				var starts = false, ends = false;
				for (g in start...end) if (l.item(g) == open) switch l.kind(g) {
					case BoxStart: starts = true;
					case BoxEnd: ends = true;
					case _:
				}
				// (its edges on this line: where it starts and ends, and not where the box tree split it around a block)
				starts = starts && box.flags & Box.NO_START == 0;
				ends = ends && box.flags & Box.NO_END == 0;
				frags.setRange(sf, starts ? 0 : Box.NO_START, ends ? 0 : Box.NO_END);
				frags.setBaseline(sf, l.ascent(f));
				var off = BlockFlow.offset(box, l.lineAvailable(k), Math.NaN);
				var a = f - start;
				aParent[a] = pf;
				aChild[a] = sf;
				aX[a] = fx(f) - px + off.x;
				aY[a] = l.y(f) - py + off.y;
				spanStamp[open] = stamp;
				spanOf[open] = sf;
				spanX[open] = fx(f);
				spanY[open] = l.y(f);
			}
			// (an item's nearest box with a span on the line: its fragment and place, or the line's)
			inline function parentOf(item:Int):Int {
				var open = c.box(item);
				while (open >= 0 && !hasSpan(open)) open = c.parent(open);
				return open;
			}
			for (f in start...end) switch l.kind(f) {
				case TextRun | Hyphen | Ellipsis:
					var o = parentOf(l.item(f)), a = f - start;
					aParent[a] = o >= 0 ? spanOf[o] : line;
					aChild[a] = -1;
					aX[a] = fx(f) - (o >= 0 ? spanX[o] : 0.0);
					aY[a] = l.y(f) - (o >= 0 ? spanY[o] : top);
				case Atomic:
					var item = l.item(f);
					var af = atomicFrag(item);
					if (af < 0) continue;
					var o = parentOf(item), a = f - start;
					var off = BlockFlow.offset(built.atomics[slot[item]], l.lineAvailable(k), Math.NaN);
					aParent[a] = o >= 0 ? spanOf[o] : line;
					aChild[a] = af;
					aX[a] = fx(f) - (o >= 0 ? spanX[o] : 0.0) + off.x;
					aY[a] = l.y(f) - (o >= 0 ? spanY[o] : top) + off.y;
				case _:
			}
			for (f in start...end) if (l.kind(f) != BoxSpan) {
				var open = c.box(l.item(f));
				while (open >= 0) {
					if (firstStamp[open] != stamp || firstOf[open] > f) {
						firstStamp[open] = stamp;
						firstOf[open] = f;
					}
					open = c.parent(open);
				}
			}
			inline function key(f:Int):Int {
				var i = l.item(f);
				return l.kind(f) == BoxSpan && firstStamp[i] == stamp ? firstOf[i] : f;
			}
			inline function rank(f:Int):Int
				return l.kind(f) == BoxSpan ? c.depth(l.item(f)) : 1 << 20;
			var all = [for (f in start...end) if (aParent[f - start] != -2) f];
			all.sort((a, b) -> key(a) != key(b) ? key(a) - key(b) : rank(a) != rank(b) ? rank(a) - rank(b) : a - b);
			for (f in all) {
				var a = f - start;
				if (aChild[a] >= 0) frags.adopt(aParent[a], aChild[a], aX[a], aY[a]);
				else text(space, l, f, textBox(l.item(f)), c, aParent[a], aX[a], aY[a]);
			}
		}
		// (a list item with nothing else: a line for its marker, as tall as the marker's)
		if (l.lines == 0 && built.markers.length > 0) {
			var line = frags.add(Fragments.LINE, (cast c.root : BoxInline).box, 0, 0);
			frags.adopt(frag, line, ox, oy);
			var h = markers(space, built.markers, line, -1, edge(0, 1), (cast c.root : BoxInline).box.style.rtl, 0);
			frags.resize(line, 0, h.height);
			frags.setBaseline(line, h.baseline);
			return {height: h.height, lines: 1, baseline: h.baseline};
		}
		return {height: to < l.lines ? l.lineTop(to) : l.height, lines: lines, baseline: baseline};
	}

	// (a text fragment: its content area, its glyph runs, one a face)
	function text(space:Space, l:InlineLayout, f:Int, box:Box, c:InlineContent, parent:Int, x:Float, y:Float) {
		var frags = space.fragments, glyphs = l.glyphs;
		var r = l.glyphRun(f);
		var ascent = l.ascent(f), descent = l.descent(f);
		var t0 = l.textStart(f), t1 = l.textEnd(f);
		var from = t0 < t1 ? c.domOffset(t0) : 0, to = t0 < t1 ? c.domOffset(t1 - 1) + 1 : from;
		if (r < 0) return;
		var fonts = glyphs.runFonts(r);
		// (plain text: its run made when first asked for, from the content, nothing placed now)
		var lazy = l.kind(f) == TextRun && l.plain(f);
		if (lazy && !check) {
			var tf = frags.add(Fragments.TEXT, box, l.fragmentWidth(f), ascent + descent);
			frags.setRange(tf, from, to);
			frags.setBaseline(tf, ascent);
			frags.later(tf, c, l.item(f), t0, t1, fonts, space.fonts);
			frags.adopt(parent, tf, x, y);
			return;
		}
		var made = lazy ? LazyText.make(c, l.item(f), t0, t1, fonts, box, space.fonts) : null, madeAt = 0;
		var g0 = glyphs.runStart(r), n = glyphs.runCount(r);
		var run:Null<ShapedRun> = null, runX = 0.0;
		function flush(endX:Float) {
			if (run == null || run.count == 0) return;
			// (the content's whole text, each glyph's characters in it: a line's runs
			// one text to a painter that keeps text, a PDF's ActualText then giving a
			// run of the other direction in logical order)
			run.text = c.text;
			if (made != null) {
				checked++;
				for (i in 0...run.count) {
					var k = madeAt + i;
					if (k >= made.count || made.id(k) != run.id(i) || Math.abs(made.x(k) - (runX + run.x(i))) > 1e-6 || made.y(k) != run.y(i) || made.start(k) != run.start(i) || made.end(k) != run.end(i)) {
						if (differed++ < 20) Sys.println('BlockLines: a lazy run differs at glyph $i: ${k < made.count ? made.id(k) + " " + made.x(k) + " " + made.start(k) + "-" + made.end(k) : "none"} against ${run.id(i)} ${runX + run.x(i)} ${run.start(i)}-${run.end(i)} in "${c.text.substring(t0, t1)}"');
						break;
					}
				}
				madeAt += run.count;
			}
			var tf = frags.add(Fragments.TEXT, box, endX - runX, ascent + descent);
			frags.setRange(tf, from, to);
			frags.setBaseline(tf, ascent);
			frags.setRun(tf, frags.runs.length);
			frags.runs.push(run);
			frags.adopt(parent, tf, x + runX, y);
			run = null;
		}
		// (each glyph's characters: its cluster up to the next one above it, the
		// fragment's end after the last; a ligature's several, a pair's both units;
		// clusters in order, as left to right text has them, at a pass from the end)
		var ordered = true;
		for (g in g0 + 1...g0 + n) if (glyphs.cluster(g) < glyphs.cluster(g - 1)) ordered = false;
		var next:Null<Map<Int, Int>> = null, ends = this.ends;
		if (ordered) {
			if (ends.length < n) ends.resize(n);
			var e = t1, k = n;
			while (--k >= 0) {
				var cl = glyphs.cluster(g0 + k);
				ends[k] = e;
				// (the next one above: past the glyphs of the same cluster)
				if (k == 0 || glyphs.cluster(g0 + k - 1) != cl) e = cl;
			}
		} else {
			var bounds = [for (g in g0...g0 + n) glyphs.cluster(g)];
			bounds.sort((a, b) -> a - b);
			next = new Map<Int, Int>();
			var e = t1, k = bounds.length;
			while (--k >= 0) {
				if (!next.exists(bounds[k])) next.set(bounds[k], e);
				e = bounds[k];
			}
		}
		for (g in g0...g0 + n) {
			var face = glyphs.face(g);
			if (run == null || run.face != face) {
				flush(glyphs.x(g));
				run = new ShapedRun(face, fonts.size);
				// (its columns their size at once: grown a glyph at a time, each push copies)
				var left = g0 + n - g;
				run.reserve(left);
				// (per face: a fallback found at the weight or style asked for is not synthesized again)
				run.skew = fonts.oblique && (face == fonts.primary || !face.italic) ? 0.25 : 0;
				run.bold = fonts.bold && (face == fonts.primary || face.weight < 600) ? embolden(fonts.size) : 0;
				if (face.hasColor) run.palette = space.fonts.palette(face, box.style);
				runX = glyphs.x(g);
			}
			var cl = glyphs.cluster(g), unit = cl < t0 ? t0 : cl, end:Int = next == null ? ends[g - g0] : next.get(cl);
			run.push(glyphs.id(g), glyphs.x(g) - runX, glyphs.y(g), unit, end > unit ? end : unit + 1);
		}
		flush(n > 0 ? Math.max(l.fragmentWidth(f), glyphs.x(g0 + n - 1) + glyphs.advance(g0 + n - 1)) : l.fragmentWidth(f));
		if (made != null && madeAt != made.count && differed++ < 20) Sys.println('BlockLines: a lazy run has ${made.count} glyphs against $madeAt in "${c.text.substring(t0, t1)}"');
	}

	// (a test's, HELDER_CHECK_TEXT: each lazy run made at once and compared with the line's glyphs, glyph for
	// glyph; those compared and those that differed)
	@:noCompletion public static var check = Sys.getEnv("HELDER_CHECK_TEXT") != null;
	@:noCompletion public static var checked = 0;
	@:noCompletion public static var differed = 0;

	// (outside markers: before the first line's start, on its baseline; laid out by the engine alone)
	// (baseline -1: the line is the marker's own; its height and baseline given back)
	function markers(space:Space, list:Array<Box>, line:Int, baseline:Float, left:Float, rtl:Bool, avail:Float):{height:Float, baseline:Float} {
		var frags = space.fragments;
		var own = baseline < 0, height = 0.0;
		for (mk in list) {
			// (text alone: its content kept for the layouts after, as a block's inline content is)
			var kept:Null<InlineContent> = space.exact ? null : cast mk.inlineCache;
			var mc = kept ?? new InlineContent(BoxInline.of(mk, avail), space.fonts.inlines);
			var t = kept != null ? null : mk.first, laid = [];
			while (t != null) {
				if (t.kind == Text) mc.addText(t.text, BoxInline.of(t, avail), t.node, t.offset);
				// (list-style-image's image: laid out as a line's atomic is)
				else if (t.kind == InlineReplaced) {
					var f = flow.child(t, space.child(avail, avail));
					laid.push(f);
					mc.addAtomic(frags.width(f), frags.height(f), Math.NaN, BoxInline.of(t, avail), t.node);
				}
				t = t.next;
			}
			if (kept == null) {
				mc.finish();
				if (laid.length == 0 && !space.exact) {
					mc.compact();
					mk.inlineCache = mc;
				}
			}
			mc.ensureShaped();
			// (its width with its trailing space, which a line's end would hang: "1. ", "\u2022 "; laid out
			// in just that, its item's text-align then moving nothing)
			var w = 0.0;
			for (p in 0...mc.pieces) w += mc.pieceWidth(p);
			var mcons = new InlineConstraints(w);
			mcons.exactMetrics = space.exact;
			mcons.lazyText = true;
			var ml = markerLayout.layout(mc, mcons);
			if (ml.lines == 0) continue;
			var mb = ml.lineBaseline(0);
			if (own) {
				baseline = Math.max(baseline, mb);
				height = Math.max(height, ml.lineHeight(0));
			}
			var span = frags.add(Fragments.SPAN, mk, w, ml.lineHeight(0));
			// (an image's: 7 before the line, as Chromium's marker padding; a text's own space does that)
			var gap = laid.length > 0 ? 7 : 0;
			frags.adopt(line, span, rtl ? left + avail + gap : left - w - gap, own ? 0 : baseline - mb);
			frags.setBaseline(span, mb);
			var atomic = 0;
			for (f in ml.lineFragmentStart(0)...ml.lineFragmentEnd(0)) switch ml.kind(f) {
				case TextRun: text(space, ml, f, mk.first ?? mk, mc, span, ml.x(f), ml.y(f));
				case Atomic if (atomic < laid.length): frags.adopt(span, laid[atomic++], ml.x(f), ml.y(f));
				case _:
			}
		}
		return {height: height, baseline: baseline};
	}

	// (synthesized bold's stroke, as Skia's: 1/24 of the size at 9px to 1/32 at 36px)
	@:allow(helder.ui.flow) static function embolden(size:Float):Float {
		var t = size <= 9 ? 0 : size >= 36 ? 1 : (size - 9) / 27;
		return size * (1 / 24 + (1 / 32 - 1 / 24) * t);
	}
}

private class Built {
	public final content:InlineContent;
	public var opened:Array<Box> = [];
	public var atomics:Array<Box> = [];
	public var laid:Array<Int> = [];
	public var floats:Array<Box> = [];
	public var absolutes:Array<Box> = [];
	public var markers:Array<Box> = [];
	public var leaders:Array<Box> = [];
	// (each item's text run: null for the items not text, and generated text's)
	public var texts = new haxe.ds.Vector<Null<Box>>(0);
	var slotted:Null<haxe.ds.Vector<Int>> = null;

	public function new(content:InlineContent)
		this.content = content;

	// (each item's place among the opened boxes or the atomics; -1: neither): made once
	public function slots():haxe.ds.Vector<Int> {
		if (slotted != null) return slotted;
		var c = content, out = new haxe.ds.Vector<Int>(c.items), open = 0, atomic = 0;
		for (i in 0...c.items) out[i] = switch c.kind(i) {
			case Open: open++;
			case Atomic: atomic++;
			case _: -1;
		}
		return slotted = out;
	}
}
