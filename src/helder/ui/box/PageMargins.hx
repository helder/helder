package helder.ui.box;

import helder.ui.flow.BlockFlow;
import helder.ui.flow.FormattingContext;
import helder.ui.flow.Space;

// A page's margin boxes (CSS Paged Media 3 §6): the four corners, and
// three boxes along each side between them, those with content
// (generated: content not none or normal) laid out in the page's
// margins. Along a side (§6.3.2), a box with an auto size takes it from
// its content: without a centre box the two at the ends share the side by
// their max-content sizes (their min-content ones when those don't fit);
// with one the centre box is centred, sized against twice the larger of
// the two others, and they take what is left on each side. Across, a box
// fills its margin. Its content is placed by vertical-align (top, middle,
// bottom) in its height; text-align is its lines'.
class PageMargins {
	public static final NAMES = [
		"top-left-corner", "top-left", "top-center", "top-right", "top-right-corner", "right-top", "right-middle", "right-bottom",
		"bottom-right-corner", "bottom-right", "bottom-center", "bottom-left", "bottom-left-corner", "left-bottom", "left-middle", "left-top"
	];

	// The boxes (each a generated box's root, content() its children: null
	// not generated) laid out on a page of width by height with margins
	// (top, right, bottom, left): their fragments, placed in the page box.
	public static function layout(boxes:Map<String, Box>, width:Float, height:Float, margins:Array<Float>, space:Space, flow:FormattingContext):Array<Int> {
		var out = [];
		var mt = margins[0], mr = margins[1], mb = margins[2], ml = margins[3];
		// (the corners)
		corner(boxes.get("top-left-corner"), 0, 0, ml, mt, space, flow, out);
		corner(boxes.get("top-right-corner"), width - mr, 0, mr, mt, space, flow, out);
		corner(boxes.get("bottom-right-corner"), width - mr, height - mb, mr, mb, space, flow, out);
		corner(boxes.get("bottom-left-corner"), 0, height - mb, ml, mb, space, flow, out);
		// (along the top and bottom: widths from content, the margin's height)
		for (side in [{names: ["top-left", "top-center", "top-right"], y: 0.0, h: mt}, {names: ["bottom-left", "bottom-center", "bottom-right"], y: height - mb, h: mb}]) {
			var bs = [for (n in side.names) boxes.get(n)];
			var sizes = [for (b in bs) b == null ? null : across(b, width - ml - mr, space, flow)];
			var at = along(sizes, width - ml - mr);
			for (k in 0...3) if (bs[k] != null) place(bs[k], ml + at[k].start, side.y, at[k].size, side.h, space, flow, out);
		}
		// (along the sides: heights from content, the margin's width)
		for (side in [{names: ["left-top", "left-middle", "left-bottom"], x: 0.0, w: ml}, {names: ["right-top", "right-middle", "right-bottom"], x: width - mr, w: mr}]) {
			var bs = [for (n in side.names) boxes.get(n)];
			var sizes = [for (b in bs) b == null ? null : down(b, side.w, height - mt - mb, space, flow)];
			var at = along(sizes, height - mt - mb);
			for (k in 0...3) if (bs[k] != null) place(bs[k], side.x, mt + at[k].start, side.w, at[k].size, space, flow, out);
		}
		return out;
	}

	// (a box's outer size along its side: set (NaN: auto), its min- and max-content)
	static function across(b:Box, avail:Float, space:Space, flow:FormattingContext):Size {
		var m = b.style.model();
		var edges = BlockFlow.res(m.margin[1], avail) + BlockFlow.res(m.margin[3], avail);
		var bpx = m.border[1] + m.border[3] + BlockFlow.res(m.padding[1], avail) + BlockFlow.res(m.padding[3], avail);
		var set = BlockFlow.size(m.width, avail, m.borderBox, bpx);
		flow.intrinsic(b, space.child(avail, Math.NaN));
		return {set: Math.isNaN(set) ? Math.NaN : set + bpx + edges, min: b.minContent + edges, max: b.maxContent + edges};
	}

	static function down(b:Box, w:Float, avail:Float, space:Space, flow:FormattingContext):Size {
		var m = b.style.model();
		var edges = BlockFlow.res(m.margin[0], avail) + BlockFlow.res(m.margin[2], avail);
		var bpy = m.border[0] + m.border[2] + BlockFlow.res(m.padding[0], avail) + BlockFlow.res(m.padding[2], avail);
		var set = BlockFlow.size(m.height, avail, m.borderBox, bpy);
		// (its content's height at its width: min and max alike)
		var f = laid(b, w, Math.NaN, space, flow);
		var h = space.fragments.height(f) + edges;
		return {set: Math.isNaN(set) ? Math.NaN : set + bpy + edges, min: h, max: h};
	}

	// (the three boxes' starts and sizes along a side of avail, §6.3.2: the middle one centred)
	static function along(s:Array<Null<Size>>, avail:Float):Array<{start:Float, size:Float}> {
		inline function used(x:Null<Size>, auto:Float):Float
			return x == null ? 0 : Math.isNaN(x.set) ? auto : x.set;
		var a = s[0], b = s[1], c = s[2];
		var wa = 0.0, wb = 0.0, wc = 0.0;
		if (b == null) {
			var shared = share(a, c, avail);
			wa = used(a, shared[0]);
			wc = used(c, shared[1]);
			if (a != null && c != null && !Math.isNaN(a.set) != !Math.isNaN(c.set)) {
				if (Math.isNaN(a.set)) wa = avail - wc else wc = avail - wa;
			}
		} else {
			// (the outer two as one, twice the larger: the middle one centred between them)
			inline function twice(x:Null<Size>, f:Size->Float):Float
				return x == null ? 0 : Math.isNaN(x.set) ? f(x) : x.set;
			var ac:Size = {
				set: Math.NaN,
				min: 2 * Math.max(twice(a, x -> x.min), twice(c, x -> x.min)),
				max: 2 * Math.max(twice(a, x -> x.max), twice(c, x -> x.max))
			};
			wb = Math.isNaN(b.set) ? share(b, ac, avail)[0] : b.set;
			wa = used(a, (avail - wb) / 2);
			wc = used(c, (avail - wb) / 2);
		}
		return [{start: 0, size: wa}, {start: (avail - wb) / 2, size: wb}, {start: avail - wc, size: wc}];
	}

	// (two auto sizes sharing avail: by their max-content ones when those fit, else growing from their
	// min-content ones by what each lacks, else by their min-content ones)
	static function share(a:Null<Size>, c:Null<Size>, avail:Float):Array<Float> {
		var amin = a == null ? 0 : a.min, amax = a == null ? 0 : a.max;
		var cmin = c == null ? 0 : c.min, cmax = c == null ? 0 : c.max;
		var max = amax + cmax, min = amin + cmin;
		if (max <= 0) return [a == null ? 0 : avail / (c == null ? 1 : 2), c == null ? 0 : avail / (a == null ? 1 : 2)];
		if (max <= avail) return [avail * amax / max, avail * cmax / max];
		if (min <= avail && max > min) {
			var spare = avail - min;
			return [amin + spare * (amax - amin) / (max - min), cmin + spare * (cmax - cmin) / (max - min)];
		}
		return min <= 0 ? [avail / 2, avail / 2] : [avail * amin / min, avail * cmin / min];
	}

	static function corner(b:Null<Box>, x:Float, y:Float, w:Float, h:Float, space:Space, flow:FormattingContext, out:Array<Int>)
		if (b != null) place(b, x, y, w, h, space, flow, out);

	// (a box in its margin rectangle: its set size, else the rectangle's less its margins; its content
	// placed by vertical-align in its height)
	static function place(b:Box, x:Float, y:Float, w:Float, h:Float, space:Space, flow:FormattingContext, out:Array<Int>) {
		var m = b.style.model();
		var mt = BlockFlow.res(m.margin[0], h), mb = BlockFlow.res(m.margin[2], h);
		var ml = BlockFlow.res(m.margin[3], w), mr = BlockFlow.res(m.margin[1], w);
		var bpx = m.border[1] + m.border[3] + BlockFlow.res(m.padding[1], w) + BlockFlow.res(m.padding[3], w);
		var bpy = m.border[0] + m.border[2] + BlockFlow.res(m.padding[0], h) + BlockFlow.res(m.padding[2], h);
		var sw = BlockFlow.size(m.width, w, m.borderBox, bpx), sh = BlockFlow.size(m.height, h, m.borderBox, bpy);
		var bw = Math.isNaN(sw) ? w - ml - mr : sw + bpx, bh = Math.isNaN(sh) ? h - mt - mb : sh + bpy;
		var f = laid(b, Math.max(0, bw), Math.max(0, bh), space, flow);
		var frags = space.fragments;
		var content = frags.height(f);
		frags.resize(f, Math.max(0, bw), Math.max(0, bh));
		// (vertical-align's longhands, Inline 3: top and bottom by baseline-shift, middle the default §6.2 gives)
		var dy = switch b.style.verticalAlign().kind {
			case "top" | "text-top": 0.0;
			case "bottom" | "text-bottom": bh - content;
			case _: (bh - content) / 2;
		}
		if (dy != 0) {
			var k = frags.first(f);
			while (k >= 0) {
				frags.moveTo(k, frags.x(k), frags.y(k) + dy);
				k = frags.next(k);
			}
		}
		frags.moveTo(f, x + ml, y + mt);
		out.push(f);
	}

	// (laid out at a border-box width, afresh: a running element's boxes are laid out on every page)
	static function laid(b:Box, w:Float, h:Float, space:Space, flow:FormattingContext):Int {
		afresh(b);
		var s = space.child(w, h);
		s.fixedWidth = w;
		return flow.layout(b, s);
	}

	static function afresh(b:Box) {
		b.cacheFragment = -1;
		b.minContent = b.maxContent = Math.NaN;
		var c = b.first;
		while (c != null) {
			afresh(c);
			c = c.next;
		}
	}
}

private typedef Size = {set:Float, min:Float, max:Float};
