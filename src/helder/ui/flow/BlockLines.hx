package helder.ui.flow;

import helder.canvas.ShapedRun;
import helder.dom.Node;
import helder.ui.box.Box;
import helder.ui.box.BoxInline;
import helder.ui.box.BoxKind;
import helder.ui.box.Fragments;
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
	final markerLayout = new InlineLayout();

	public function new(flow:BlockFlow)
		this.flow = flow;

	public function layout(block:Box, width:Float, space:Space, frag:Int, ox:Float, oy:Float, pct:Float):{height:Float, lines:Int, baseline:Float} {
		var built = build(block, space, width, pct, false);
		var c = built.content;
		var frags = space.fragments;
		if (layouts.length <= depth) layouts.push(new InlineLayout());
		var l = layouts[depth++];
		// (the function, not the space's field: the lines are laid out again for hit testing, the space gone on)
		var lineWidth = space.lineWidth;
		var constraints = new InlineConstraints(width, lineWidth == null ? null : (y, h) -> {
			var lw = lineWidth(oy + y, h);
			return lw == null ? {offset: 0.0, width: width} : {offset: lw.offset - ox, width: lw.width};
		});
		try {
			// (floats placed where their lines put them, the lines then laid out around them: until they stay)
			var floats = built.floats;
			var tops:Array<Float> = [];
			for (round in 0...(floats.length > 0 && space.placeFloat != null ? 4 : 1)) {
				l.layout(c, constraints);
				if (floats.length == 0 || space.placeFloat == null) break;
				var at = statics(l, InlineFragment.Float);
				var same = round > 0 && at.length == tops.length;
				if (same) for (k in 0...at.length) if (at[k].y != tops[k]) same = false;
				if (same) break;
				if (round > 0 && space.unplace != null) space.unplace(floats.length);
				tops = [for (a in at) a.y];
				for (k in 0...floats.length) space.placeFloat(floats[k], oy + (k < tops.length ? tops[k] : 0));
			}
			if (space.placeAbsolute != null) {
				var at = statics(l, InlineFragment.Abspos);
				for (k in 0...built.absolutes.length) if (k < at.length) space.placeAbsolute(built.absolutes[k], ox + at[k].x, oy + at[k].y);
			}
			var r = fragments(l, built, space, frag, ox, oy, constraints);
			block.lines = new BlockText(c, constraints, frag, ox, oy);
			depth--;
			return r;
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

	// (the places of the fragments of a kind, in order)
	static function statics(l:InlineLayout, kind:InlineFragment):Array<{x:Float, y:Float}> {
		var out = [];
		for (f in 0...l.fragments) if (l.kind(f) == kind) out.push({x: l.x(f), y: l.y(f)});
		return out;
	}

	// ---- the content

	// (the box tree's inline content: atomics laid out first (measure: their min- or max-content as their
	// width), the boxes behind its items in the order they come)
	function build(block:Box, space:Space, width:Float, pct:Float, measure:Bool, min = false):Built {
		var frags = space.fragments;
		var c = new InlineContent(BoxInline.of(block, width));
		var out:Built = {
			content: c,
			opened: [],
			atomics: [],
			laid: [],
			floats: [],
			absolutes: [],
			markers: [],
			texts: new haxe.ds.ObjectMap<Node, Array<Box>>()
		};
		function walk(b:Box) {
			var k = b.first;
			while (k != null) {
				switch k.kind {
					case Text:
						if (k.node != null) {
							var list = out.texts.get(k.node);
							if (list == null) out.texts.set(k.node, list = []);
							list.push(k);
						}
						c.addText(k.text, BoxInline.of(k, width), k.node, k.offset);
					case Inline if (k.flags & Box.OUTSIDE != 0):
						out.markers.push(k);
					case Inline:
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
		return out;
	}

	// ---- fragments

	function fragments(l:InlineLayout, built:Built, space:Space, frag:Int, ox:Float, oy:Float, constraints:InlineConstraints):{height:Float, lines:Int, baseline:Float} {
		// (where a line at y starts, the floats beside it: an outside marker goes before it)
		inline function edge(y:Float, h:Float):Float
			return constraints.lineWidth == null ? 0 : constraints.lineWidth(y, h).offset;
		var frags = space.fragments, c = built.content, glyphs = l.glyphs;
		// (an item's box: an inline box's by its Open item, an atomic's by order, text's by its DOM text)
		var openBox = new Map<Int, Box>(), atomicFrag = new Map<Int, Int>(), atomicBox = new Map<Int, Box>();
		var nextOpen = 0, nextAtomic = 0;
		for (i in 0...c.items) switch c.kind(i) {
			case Open: openBox.set(i, built.opened[nextOpen++]);
			case Atomic:
				atomicFrag.set(i, built.laid[nextAtomic]);
				atomicBox.set(i, built.atomics[nextAtomic++]);
			case _:
		}
		function textBox(i:Int):Box {
			var source = c.source(i);
			var list = source != null ? built.texts.get(source) : null;
			if (list != null) {
				if (list.length == 1) return list[0];
				// (the run whose part of the DOM text the item's first unit is from)
				var at = c.end(i) > c.start(i) ? c.domOffset(c.start(i)) : -1;
				for (b in list) if (at >= b.offset && at < b.offset + b.text.length) return b;
				return list[0];
			}
			return (cast c.style(i) : BoxInline).box;
		}
		var lines = 0, baseline = Math.NaN;
		for (k in 0...l.lines) {
			var top = l.lineTop(k), h = l.lineHeight(k);
			var line = frags.add(Fragments.LINE, (cast c.root : BoxInline).box, l.lineAvailable(k), h);
			frags.adopt(frag, line, ox, oy + top);
			frags.setBaseline(line, l.lineBaseline(k));
			if (h > 0) {
				lines++;
				baseline = top + l.lineBaseline(k);
			}
			// (spans first, outer ones before inner: the boxes' parts on this line, by their Open item)
			var spanOf = new Map<Int, Int>(), spanX = new Map<Int, Float>(), spanY = new Map<Int, Float>();
			var start = l.lineFragmentStart(k), end = l.lineFragmentEnd(k);
			var order = [for (f in start...end) if (l.kind(f) == BoxSpan) f];
			order.sort((a, b) -> c.depth(l.item(a)) - c.depth(l.item(b)));
			inline function parentOf(item:Int):{frag:Int, x:Float, y:Float} {
				var open = c.box(item);
				while (open >= 0 && !spanOf.exists(open)) open = c.parent(open);
				return open >= 0 ? {frag: spanOf.get(open), x: spanX.get(open), y: spanY.get(open)} : {frag: line, x: 0.0, y: top};
			}
			for (f in order) {
				var open = l.item(f);
				var box = openBox.get(open);
				if (box == null) continue;
				var p = c.parent(open);
				while (p >= 0 && !spanOf.exists(p)) p = c.parent(p);
				var px = p >= 0 ? spanX.get(p) : 0.0, py = p >= 0 ? spanY.get(p) : top, pf = p >= 0 ? spanOf.get(p) : line;
				var sf = frags.add(Fragments.SPAN, box, l.fragmentWidth(f), l.fragmentHeight(f));
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
				frags.adopt(pf, sf, l.x(f) - px + off.x, l.y(f) - py + off.y);
				spanOf.set(open, sf);
				spanX.set(open, l.x(f));
				spanY.set(open, l.y(f));
			}
			for (f in start...end) switch l.kind(f) {
				case TextRun | Hyphen | Ellipsis:
					var item = l.item(f);
					var p = parentOf(item);
					var box = textBox(item);
					text(space, l, f, box, c, p.frag, l.x(f) - p.x, l.y(f) - p.y);
				case Atomic:
					var item = l.item(f);
					var af = atomicFrag.get(item);
					if (af == null || af < 0) continue;
					var p = parentOf(item);
					var b = atomicBox.get(item);
					var off = BlockFlow.offset(b, l.lineAvailable(k), Math.NaN);
					frags.adopt(p.frag, af, l.x(f) - p.x + off.x, l.y(f) - p.y + off.y);
				case _:
			}
			if (k == 0 && built.markers.length > 0) markers(space, built.markers, line, l.lineBaseline(k), edge(top, h), (cast c.root : BoxInline).box.style.rtl, l.lineAvailable(k));
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
		return {height: l.height, lines: lines, baseline: baseline};
	}

	// (a text fragment: its content area, its glyph runs, one a face)
	function text(space:Space, l:InlineLayout, f:Int, box:Box, c:InlineContent, parent:Int, x:Float, y:Float) {
		var frags = space.fragments, glyphs = l.glyphs;
		var r = l.glyphRun(f);
		var ascent = l.ascent(f), descent = l.descent(f);
		var t0 = l.textStart(f), t1 = l.textEnd(f);
		var all = c.text.substring(t0, t1);
		var from = t0 < t1 ? c.domOffset(t0) : 0, to = t0 < t1 ? c.domOffset(t1 - 1) + 1 : from;
		if (r < 0) return;
		var fonts = glyphs.runFonts(r);
		var g0 = glyphs.runStart(r), n = glyphs.runCount(r);
		var run:Null<ShapedRun> = null, runX = 0.0;
		function flush(endX:Float) {
			if (run == null || run.count == 0) return;
			run.text = all;
			var tf = frags.add(Fragments.TEXT, box, endX - runX, ascent + descent);
			frags.setRange(tf, from, to);
			frags.setBaseline(tf, ascent);
			frags.setRun(tf, frags.runs.length);
			frags.runs.push(run);
			frags.adopt(parent, tf, x + runX, y);
			run = null;
		}
		for (g in g0...g0 + n) {
			var face = glyphs.face(g);
			if (run == null || run.face != face) {
				flush(glyphs.x(g));
				run = new ShapedRun(face, fonts.size);
				// (its columns their size at once: grown a glyph at a time, each push copies)
				var left = g0 + n - g;
				run.ids.resize(left);
				run.xs.resize(left);
				run.ys.resize(left);
				run.starts.resize(left);
				run.ends.resize(left);
				run.skew = fonts.oblique ? 0.25 : 0;
				runX = glyphs.x(g);
			}
			var unit = glyphs.cluster(g) - t0;
			if (unit < 0) unit = 0;
			run.push(glyphs.id(g), glyphs.x(g) - runX, glyphs.y(g), unit, unit + 1);
		}
		flush(n > 0 ? Math.max(l.fragmentWidth(f), glyphs.x(g0 + n - 1) + glyphs.advance(g0 + n - 1)) : l.fragmentWidth(f));
	}

	// (outside markers: before the first line's start, on its baseline; laid out by the engine alone)
	// (baseline -1: the line is the marker's own; its height and baseline given back)
	function markers(space:Space, list:Array<Box>, line:Int, baseline:Float, left:Float, rtl:Bool, avail:Float):{height:Float, baseline:Float} {
		var frags = space.fragments;
		var own = baseline < 0, height = 0.0;
		for (mk in list) {
			var mc = new InlineContent(BoxInline.of(mk, avail));
			var t = mk.first;
			while (t != null) {
				if (t.kind == Text) mc.addText(t.text, BoxInline.of(t, avail), t.node, t.offset);
				t = t.next;
			}
			mc.finish();
			mc.ensureShaped();
			// (its width with its trailing space, which a line's end would hang: "1. ", "\u2022 "; laid out
			// in just that, its item's text-align then moving nothing)
			var w = 0.0;
			for (p in 0...mc.pieces) w += mc.pieceWidth(p);
			var ml = markerLayout.layout(mc, new InlineConstraints(w));
			if (ml.lines == 0) continue;
			var mb = ml.lineBaseline(0);
			if (own) {
				baseline = Math.max(baseline, mb);
				height = Math.max(height, ml.lineHeight(0));
			}
			var span = frags.add(Fragments.SPAN, mk, w, ml.lineHeight(0));
			frags.adopt(line, span, rtl ? left + avail : left - w, own ? 0 : baseline - mb);
			frags.setBaseline(span, mb);
			for (f in ml.lineFragmentStart(0)...ml.lineFragmentEnd(0)) if (ml.kind(f) == TextRun)
				text(space, ml, f, mk.first ?? mk, mc, span, ml.x(f), ml.y(f));
		}
		return {height: height, baseline: baseline};
	}
}

private typedef Built = {
	content:InlineContent,
	opened:Array<Box>,
	atomics:Array<Box>,
	laid:Array<Int>,
	floats:Array<Box>,
	absolutes:Array<Box>,
	markers:Array<Box>,
	// (a DOM text's runs: one, or its ::first-letter's and the rest)
	texts:haxe.ds.ObjectMap<Node, Array<Box>>
}
