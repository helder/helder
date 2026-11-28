package helder.ui.flow;

import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.box.Fragments;
import helder.ui.box.Len;

using StringTools;

// Flex layout (CSS Flexible Box Layout 1 §9), as helder.ui's Layout has it
// for its own nodes (the same steps, Taffy's fixtures their test) over the
// box tree: each in-flow child an item (BoxTree wraps runs of text), laid
// out by its own context (block, inline, table, flex) at the sizes flexing
// and stretching give it. Items in order (`order`), into lines (nowrap
// one, wrap as they fit); each its flex base size (flex-basis, else its
// width or height, else its content's), its hypothetical main size within
// its min and max (min auto: its content's, no more than its own size; 0
// when it clips); the flexible lengths resolved per line (§9.7: frozen
// items, violations, shares rounded to 64ths as Chromium's); cross sizes
// from layout at the main size, lines as tall as their items (baselines
// shared), a single line the container's; align-content between lines;
// stretched items laid out again at their line's size; auto margins, then
// justify-content and align-self. Reverse directions and right to left
// mirror the axes. Absolutely positioned children: the content box's
// start as their static place.
class FlexFlow implements FormattingContext {
	final flow:BlockFlow;

	public function new(flow:BlockFlow)
		this.flow = flow;

	public function layout(box:Box, space:Space):Int {
		var key = Math.isNaN(space.fixedWidth) ? space.width : -1 - space.fixedWidth;
		var reusable = box.flags & Box.ESCAPES == 0 && space.fragmentation == null;
		var cached = reusable ? BlockFlow.hit(box, key, space) : -1;
		if (cached >= 0) return cached;
		var cuts = space.lazy != null ? space.lazy.count : 0;
		var f = container(box, space);
		// (cut short by a lazy layout: not kept, laid out again as the cut moves on)
		if (space.lazy != null && space.lazy.count != cuts) {
			box.uncache();
			return f;
		}
		BlockFlow.keep(box, key, space, reusable ? f : -1);
		return f;
	}

	static inline function same(a:Float, b:Float):Bool
		return a == b || Math.isNaN(a) && Math.isNaN(b);

	// (an item laid out by its own context)
	inline function child(b:Box, space:Space):Int
		return flow.child(b, space);

	// ---- the container

	function container(box:Box, space:Space):Int {
		var s = box.style.model();
		var cb = space.width;
		var pl = BlockFlow.res(s.padding[3], cb), pr = BlockFlow.res(s.padding[1], cb), pt = BlockFlow.res(s.padding[0], cb), pb = BlockFlow.res(s.padding[2], cb);
		var bl = s.border[3], br = s.border[1], bt = s.border[0], bb = s.border[2];
		// (in a fragmentainer, resumed: its start's border and padding were in the one before)
		var fr = space.fragmentation;
		var resume = fr != null ? fr.resume(box) : null;
		if (resume != null) bt = pt = 0;
		var bpx = pl + pr + bl + br, bpy = pt + pb + bt + bb;
		// (measured for its content's height (ignoreHeight): its own height only where a wrapping column breaks)
		var ownHeight = BlockFlow.size(s.height, space.height, s.borderBox, bpy);
		var measuring = space.ignoreHeight && Math.isNaN(space.fixedHeight);
		var heightSpec = !Math.isNaN(space.fixedHeight) ? Math.max(0, space.fixedHeight - bpy) : measuring ? Math.NaN : ownHeight;
		if (!Math.isNaN(heightSpec)) heightSpec = BlockFlow.clampHeight(s, space.height, bpy, heightSpec);
		if (resume != null && !Math.isNaN(heightSpec)) heightSpec = Math.max(0, heightSpec - resume.consumed);
		var w = width(box, s, space, bpx, heightSpec);
		BlockFlow.alignRootFloat(box, cb, w + bpx);
		// (an aspect-ratio's auto height: its width's through it; not when measured for its content, the content size
		// suggestion a flex item's automatic minimum takes, §4.5)
		if (Math.isNaN(heightSpec) && !measuring) {
			var rh = Ratio.height(box, w, bpx, bpy);
			// (no less than its content's, its min-height auto, Sizing 4 §5.1: its content measured at its width, no
			// more than its max-width gives through the ratio; a wrapping one's lines are broken at the ratio's)
			var flexWrap = box.style.flexWrap;
			if (!Math.isNaN(rh) && Lens.isAuto(s.minHeight) && Lens.isAuto(s.height) && (flexWrap == "nowrap" || flexWrap == "")) {
				var probe = space.child(space.width, space.height);
				probe.fragmentation = null;
				probe.ignoreHeight = true;
				probe.fixedWidth = w + bpx;
				var content = space.fragments.height(container(box, probe)) - bpy;
				var cap = Ratio.height(box, nanTo(BlockFlow.size(s.maxWidth, space.width, s.borderBox, bpx), Math.NaN), bpx, bpy);
				rh = Math.max(rh, Math.isNaN(cap) ? content : Math.min(content, cap));
			}
			if (!Math.isNaN(rh)) heightSpec = BlockFlow.clampHeight(s, space.height, bpy, rh);
		}
		// (measured for its content: its own min and max height aside, as GridFlow's)
		var minH = measuring ? Math.NaN : BlockFlow.size(s.minHeight, space.height, s.borderBox, bpy);
		// (a wrapping column's lines still broken at it)
		var ownMax = BlockFlow.size(s.maxHeight, space.height, s.borderBox, bpy), maxH = measuring ? Math.NaN : ownMax;
		var frags = space.fragments;
		var frag = frags.add(Fragments.BOX, box, w + bpx, 0);
		var dir = box.style.flexDirection;
		var row = dir != "column" && dir != "column-reverse", reverse = dir == "row-reverse" || dir == "column-reverse";
		var wrap = box.style.flexWrap;
		var wraps = wrap == "wrap" || wrap == "wrap-reverse", wrapReverse = wrap == "wrap-reverse";
		var rtl = box.style.rtl;
		var rowGap = gap(box.style.rowGap, heightSpec), colGap = gap(box.style.columnGap, w);
		var mainGap = row ? colGap : rowGap, crossGap = row ? rowGap : colGap;
		// (the main size: definite or not; a column without a height breaks its lines at its max-height)
		var mainSize = row ? w : heightSpec;
		var ratioH = measuring && Math.isNaN(ownHeight) ? Ratio.height(box, w, bpx, bpy) : Math.NaN;
		var mainLimit = row ? w : !Math.isNaN(heightSpec) ? heightSpec : measuring
			&& !Math.isNaN(ownHeight) ? BlockFlow.clampHeight(s, space.height, bpy, ownHeight) : !Math.isNaN(ratioH) ? ratioH : !Math.isNaN(ownMax) ? ownMax : Math.POSITIVE_INFINITY;
		var crossSize = row ? heightSpec : w;
		// (its height as its items' percentages see it: none where its own isn't definite)
		var pctH = space.looseHeight ? Math.NaN : heightSpec;
		// (absolutely positioned children: for the nearest positioned box; the others are items, in order)
		var owner = box.parent == null || box.style.positioned || box.style.containment.containingBlock;
		var positioned = owner ? new Positioned() : space.positioned ?? new Positioned();
		var fixed = box.parent == null ? new Positioned() : box.style.containment.containingBlock ? positioned : space.fixed ?? positioned;
		var items:Array<Item> = [];
		var c = box.first, index = 0;
		var abs:Array<Box> = [];
		while (c != null) {
			if (c.absolute) abs.push(c) else
				items.push(item(c, row, w, pctH, crossSize, !wraps, space, index++));
			c = c.next;
		}
		// (a column's items of no definite height, but those whose flex base size is a length: a basis in pixels, or
		// none and a height in pixels, as Chromium has them)
		if (!row && Math.isNaN(pctH))
			for (it in items) {
				var st = it.box.style, basis = BlockFlow.size(st.flexBasis, Math.NaN, false, 0);
				it.looseMain = Math.isNaN(basis) && !(st.flexBasisKeyword == "auto" && !Math.isNaN(BlockFlow.size(st.model().height, Math.NaN, false, 0)))
					&& Math.isNaN(Ratio.of(it.box));
			}
		// (a long document's cut into the items of a single row, each at the content's top: their tops the
		// document's, as a block's children's; a sidebar and the document beside it, as ecmarkup's body)
		if (space.lazy != null && row && !wraps && fr == null)
			for (it in items)
				if (it.autoCross == 0 && (it.align == "stretch" || it.align == "flex-start" || it.align == "start" || it.align == "self-start"
					|| it.align == "normal")) it.top = space.top + bt + pt + it.crossStart;
		items.sort((a, b) -> a.order != b.order ? a.order - b.order : a.index - b.index);
		// (lines: one when not wrapping, else as many items as fit, each at least one)
		var lines:Array<Array<Item>> = [];
		var line:Array<Item> = [], used = 0.0;
		for (it in items) {
			var outer = it.hypo + it.mainStart + it.mainEnd;
			if (wraps && line.length > 0 && used + mainGap + outer > mainLimit + 1e-6) {
				lines.push(line);
				line = [];
				used = 0;
			}
			used += (line.length > 0 ? mainGap : 0) + outer;
			line.push(it);
		}
		if (line.length > 0 || lines.length == 0) lines.push(line);
		// (an indefinite main size: the largest line's, within min and max)
		if (Math.isNaN(mainSize)) {
			var most = 0.0;
			for (l in lines) {
				var sum = 0.0;
				for (k in 0...l.length) sum += l[k].hypo + l[k].mainStart + l[k].mainEnd + (k > 0 ? mainGap : 0);
				most = Math.max(most, sum);
			}
			mainSize = clamp(most, row ? 0 : nanTo(minH, 0), row ? Math.POSITIVE_INFINITY : nanTo(maxH, Math.POSITIVE_INFINITY));
		}
		for (l in lines) flexible(l, mainSize, mainGap);
		// (cross sizes: each item laid out at its main size)
		var lineCross = [], lineBase = [];
		for (l in lines) {
			var most = 0.0, above = 0.0, below = 0.0;
			for (it in l) {
				measureCross(it, row, mainSize, crossSize, space);
				var outer = it.cross + it.crossStart + it.crossEnd;
				// (a column's: its start edge across, as Chromium synthesizes it)
				if (it.align == "baseline" && it.autoCross == 0) {
					var b = row ? it.baseline : 0;
					above = Math.max(above, b + it.crossStart);
					below = Math.max(below, outer - b - it.crossStart);
				} else
					most = Math.max(most, outer);
			}
			lineCross.push(Math.max(most, above + below));
			lineBase.push(above);
		}
		var crossUsed = 0.0;
		for (k in 0...lineCross.length) crossUsed += lineCross[k] + (k > 0 ? crossGap : 0);
		if (Math.isNaN(crossSize)) crossSize = row ? clamp(crossUsed, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY)) : crossUsed;
		// (a single line: the container's cross size, its min and max in)
		if (!wraps && lines.length == 1) {
			lineCross[0] = crossSize;
			crossUsed = crossSize;
		}
		// (align-content: the lines in the cross size; normal and stretch share the free space)
		var content = logical(keyword(box.style.alignContent), wrapReverse);
		var free = crossSize - crossUsed;
		var lineStart = [];
		var at = 0.0, between = crossGap;
		if (wraps) {
			if ((content == "normal" || content == "stretch" || content == "") && free > 0) {
				for (k in 0...lineCross.length) lineCross[k] += free / lineCross.length;
				free = 0;
			}
			var d = distribute(content, free, lines.length, wrapReverse);
			at = d.start;
			between += d.between;
		}
		for (k in 0...lines.length) {
			lineStart.push(at);
			at += lineCross[k] + between;
		}
		// (each item placed: stretched, then main axis alignment, then cross axis)
		var baseline = Math.NaN, placed:Array<Item> = [];
		var justify = logical(keyword(box.style.justifyContent), reverse);
		var innerW = w, innerH = row ? crossSize : mainSize;
		for (k in 0...lines.length) {
			var l = lines[k];
			var lc = lineCross[k];
			// (stretched: an auto cross size, no auto cross margin: the line's, within min and max)
			for (it in l)
				if (it.align == "stretch" && it.crossAuto && it.autoCross == 0) {
					var size = clamp(lc - it.crossStart - it.crossEnd, it.minCross, it.maxCross);
					if (Math.abs(size - it.cross) > 1e-6 || !row) {
						it.cross = size;
						it.frag = laid(it, row, size, space, mainSize, crossSize, true);
					}
				}
			// (main axis: auto margins take the free space, else justify-content)
			var sum = 0.0, autos = 0;
			for (i in 0...l.length) {
				var it = l[i];
				sum += it.main + it.mainStart + it.mainEnd + (i > 0 ? mainGap : 0);
				if (it.autoMain & 1 != 0) autos++;
				if (it.autoMain & 2 != 0) autos++;
			}
			var room = mainSize - sum;
			var pos = 0.0, extra = mainGap;
			if (autos > 0 && room > 0) {
				var each = room / autos;
				for (it in l) {
					if (it.autoMain & 1 != 0) it.mainStart += each;
					if (it.autoMain & 2 != 0) it.mainEnd += each;
				}
			} else {
				var d = distribute(justify == "normal" ? "flex-start" : justify, room, l.length, reverse);
				pos = d.start;
				extra += d.between;
			}
			for (i in 0...l.length) {
				var it = l[i];
				var m = pos + it.mainStart;
				pos = m + it.main + it.mainEnd + extra;
				// (cross axis: auto margins, else align-self)
				var crossRoom = lc - it.cross - it.crossStart - it.crossEnd;
				var cpos = it.crossStart;
				if (it.autoCross != 0 && crossRoom > 0) {
					cpos += it.autoCross == 3 ? crossRoom / 2 : it.autoCross == 1 ? crossRoom : 0;
				} else switch it.align {
					case "flex-end": cpos += crossRoom;
					case "center": cpos += crossRoom / 2;
					case "baseline" if (it.autoCross == 0): cpos = lineBase[k] - (row ? it.baseline : 0);
					case _:
				}
				// (reversed: from the main end; wrap-reverse: lines from the cross end)
				var mainAt = reverse ? mainSize - m - it.main : m;
				var crossAt = lineStart[k] + cpos;
				if (wrapReverse) crossAt = crossSize - (lineStart[k] + lc) + (lc - cpos - it.cross);
				var x:Float, y:Float;
				if (row) {
					x = rtl ? innerW - mainAt - it.main : mainAt;
					y = crossAt;
				} else {
					x = rtl ? innerW - crossAt - it.cross : crossAt;
					y = mainAt;
				}
				var off = BlockFlow.offset(it.box, innerW, innerH);
				it.x = x + off.x;
				it.y = y + off.y;
				it.line = k;
				placed.push(it);
				if (fr == null) frags.adopt(frag, it.frag, bl + pl + it.x, bt + pt + it.y);
				if (Math.isNaN(baseline) && k == 0) {
					var b = frags.baseline(it.frag);
					baseline = bt + pt + y + (Math.isNaN(b) ? frags.height(it.frag) : b);
				}
			}
		}
		var h = row ? crossSize : mainSize;
		// (size containment: an auto height as if empty, contain-intrinsic-height's)
		if (Math.isNaN(heightSpec) && box.style.containment.has(Size)) h = box.style.intrinsicSize(false);
		if (Math.isNaN(heightSpec)) h = clamp(h, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY));
		// (in a fragmentainer: its rows here, from where it resumes to a break; broken, its end's border and padding
		// in a later one, its height to the fragmentainer's end)
		var broken = false;
		if (fr != null) {
			// (Rows: a row's line one row, a column's items one each, all one when it has several lines)
			var rows = fr.rows(), splits = row || lines.length == 1;
			for (k in 0...placed.length) {
				var it = placed[k], ih = frags.height(it.frag);
				rows.add(row ? it.line : splits ? k : 0, it.box, it.frag, it.x, it.y, it.y - (row ? it.crossStart : it.mainStart), it.y + ih + (row ? it.crossEnd : it.mainEnd));
			}
			var r = rows.place(box, frag, space, flow, bl + pl, bt + pt, h);
			broken = r.broken;
			if (broken) {
				bb = pb = 0;
				bpy = pt + bt;
				h = Math.max(r.height, fr.size - space.pageTop - bt - pt);
			} else if (resume != null)
				h = r.height;
			if (resume != null || broken) {
				frags.setRange(frag, resume != null ? Box.NO_START : 0, broken ? Box.NO_END : 0);
				baseline = Math.NaN;
			}
		}
		// (absolutely positioned children: static places as if each were the only item, Flexbox §4.1:
		// justify-content along the main axis, align-self across, in the content box; in its first fragment)
		if (resume == null) for (a in abs) {
			var j = fraction(justify, reverse), self = logical(selfOf(a, row), wrapReverse);
			var k = fraction(self == "stretch" || self == "baseline" ? "flex-start" : self, wrapReverse);
			var fx = row ? (rtl ? 1 - j : j) : (rtl ? 1 - k : k), fy = row ? k : j;
			(a.style.position == "fixed" ? fixed : positioned).add(a, frag, bl + pl, bt + pt, [bl + pl, bt + pt, w, h, fx, fy]);
		}
		frags.resize(frag, w + bpx, h + bpy);
		if (!Math.isNaN(baseline)) frags.setBaseline(frag, baseline);
		if (space.lazy != null) for (it in items) if (it.cuts != null) space.lazy.put(it.cuts);
		// (its margins for its parent: a flex container's don't collapse with its items')
		var mt = resume != null ? 0 : BlockFlow.res(s.margin[0], cb), mb = broken ? 0 : BlockFlow.res(s.margin[2], cb);
		box.topPositive = mt > 0 ? mt : 0;
		box.topNegative = mt < 0 ? mt : 0;
		box.bottomPositive = mb > 0 ? mb : 0;
		box.bottomNegative = mb < 0 ? mb : 0;
		box.through = false;
		if (box.parent == null) {
			BlockFlow.repeat(fixed, frag, space, bl + pl, bt + pt, -box.marginLeft, 0);
			var r = space.repeated;
			flow.place(fixed, frag, space, -box.marginLeft, 0, r != null ? r.width : space.width, r != null ? r.height : space.height);
			flow.place(positioned, frag, space, -box.marginLeft, 0, space.width, space.height);
		} else if (owner)
			flow.place(positioned, frag, space, bl, bt, w + pl + pr, h + pt + pb, resume != null || broken);
		return frag;
	}

	// (the container's content width: given, set, or filling its containing block; shrink-to-fit when it
	// floats, is absolutely positioned or inline-level)
	function width(box:Box, s:BoxStyle, space:Space, bpx:Float, height:Float):Float {
		var cb = space.width;
		var ml = BlockFlow.auto(s.margin[3], cb), mr = BlockFlow.auto(s.margin[1], cb);
		var minW = nanTo(BlockFlow.size(s.minWidth, cb, s.borderBox, bpx), 0), maxW = BlockFlow.size(s.maxWidth, cb, s.borderBox, bpx);
		if (!Math.isNaN(space.fixedWidth)) {
			box.marginLeft = nanTo(ml, 0);
			box.marginRight = nanTo(mr, 0);
			return Math.max(0, space.fixedWidth - bpx);
		}
		var spec = BlockFlow.size(s.width, cb, s.borderBox, bpx);
		if (Math.isNaN(spec)) spec = BlockFlow.sizing(box, space, cb, ml, mr, bpx, () -> intrinsic(box, space));
		if (Math.isNaN(spec)) spec = Ratio.width(box, height, bpx, s.border[0] + s.border[2] + BlockFlow.res(s.padding[0], cb) + BlockFlow.res(s.padding[2], cb));
		if (box.blockLevel && box.kind != InlineBlock && !box.floating && !box.absolute) {
			var rtl = box.parent != null && box.parent.style.rtl;
			var w = BlockFlow.solve(box, spec, ml, mr, cb, bpx, rtl);
			if (!Math.isNaN(maxW) && w > maxW) w = BlockFlow.solve(box, maxW, ml, mr, cb, bpx, rtl);
			if (w < minW) w = BlockFlow.solve(box, minW, ml, mr, cb, bpx, rtl);
			return Math.max(0, w);
		}
		box.marginLeft = nanTo(ml, 0);
		box.marginRight = nanTo(mr, 0);
		if (Math.isNaN(spec)) {
			intrinsic(box, space);
			spec = Math.min(Math.max(box.minContent, cb - box.marginLeft - box.marginRight), box.maxContent) - bpx;
		}
		return Math.max(0, clamp(spec, minW, nanTo(maxW, Math.POSITIVE_INFINITY)));
	}

	// ---- items

	function item(b:Box, row:Bool, w:Float, h:Float, crossSize:Float, single:Bool, space:Space, index:Int):Item {
		var it = new Item(b, index);
		var s = b.style.model(), st = b.style;
		var cb = w;
		it.order = st.order;
		it.grow = st.flexGrow;
		it.shrink = st.flexShrink;
		var ml = BlockFlow.auto(s.margin[3], cb), mr = BlockFlow.auto(s.margin[1], cb);
		var mt = BlockFlow.auto(s.margin[0], cb), mb = BlockFlow.auto(s.margin[2], cb);
		var rtl = b.parent != null && b.parent.style.rtl;
		var pd = b.parent == null ? "" : b.parent.style.flexDirection, reverse = pd == "row-reverse" || pd == "column-reverse";
		// (main start and end: left and right in a row, mirrored right to left; top and bottom in a column; a
		// reversed axis's from its other side, its items placed from there)
		var ms = row ? (rtl != reverse ? mr : ml) : (reverse ? mb : mt), me = row ? (rtl != reverse ? ml : mr) : (reverse ? mt : mb);
		var cs = row ? mt : (rtl ? mr : ml), ce = row ? mb : (rtl ? ml : mr);
		it.autoMain = (Math.isNaN(ms) ? 1 : 0) | (Math.isNaN(me) ? 2 : 0);
		it.autoCross = (Math.isNaN(cs) ? 1 : 0) | (Math.isNaN(ce) ? 2 : 0);
		it.mainStart = nanTo(ms, 0);
		it.mainEnd = nanTo(me, 0);
		it.crossStart = nanTo(cs, 0);
		it.crossEnd = nanTo(ce, 0);
		var pl = BlockFlow.res(s.padding[3], cb), pr = BlockFlow.res(s.padding[1], cb), pt = BlockFlow.res(s.padding[0], cb), pb = BlockFlow.res(s.padding[2], cb);
		var bpx = pl + pr + s.border[1] + s.border[3], bpy = pt + pb + s.border[0] + s.border[2];
		it.edgesMain = row ? bpx : bpy;
		it.edgesCross = row ? bpy : bpx;
		var mainBase = row ? w : h, crossBase = row ? h : w;
		var mainLen = row ? s.width : s.height, crossLen = row ? s.height : s.width;
		var mainSet = BlockFlow.size(mainLen, mainBase, s.borderBox, it.edgesMain);
		var crossSet = BlockFlow.size(crossLen, crossBase, s.borderBox, it.edgesCross);
		// (auto as written: a percentage of an indefinite size is not stretched, Flexbox §9.4 step 11)
		it.crossAuto = Lens.isAuto(crossLen);
		it.minCross = nanTo(BlockFlow.size(row ? s.minHeight : s.minWidth, crossBase, s.borderBox, it.edgesCross), 0) + it.edgesCross;
		it.maxCross = nanTo(BlockFlow.size(row ? s.maxHeight : s.maxWidth, crossBase, s.borderBox, it.edgesCross), Math.POSITIVE_INFINITY) + it.edgesCross;
		// (width, min-width, max-width as min-content, max-content or fit-content: its content's, border box, the
		// room within them for fit-content)
		var r = st.rare, kw = r.widthKeyword, kmin = r.minWidthKeyword, kmax = r.maxWidthKeyword;
		var keyMin = Math.NaN, keyMax = Math.NaN;
		if (kw != "" || kmin != "" || kmax != "") {
			var room = (row ? w : Math.isNaN(crossSize) ? Math.POSITIVE_INFINITY : crossSize) - (row ? it.mainStart + it.mainEnd : it.crossStart + it.crossEnd);
			// (its content's, its own width aside)
			var c = if (b.context == null || b.context == flow) flow.contentSizes(b, space) else if (b.context == this) contentSizes(b, space) else {
				b.context.intrinsic(b, space);
				{min: b.minContent, max: b.maxContent};
			}
			function sized(k:String):Float
				return switch k {
					case "min-content": c.min;
					case "max-content": c.max;
					case "fit-content": Math.min(Math.max(c.min, room), c.max);
					case _: Math.NaN;
				}
			keyMin = sized(kmin);
			keyMax = sized(kmax);
			if (!row) {
				if (!Math.isNaN(keyMin)) it.minCross = keyMin;
				if (!Math.isNaN(keyMax)) it.maxCross = keyMax;
			}
			var k = sized(kw);
			if (!Math.isNaN(k)) {
				if (row) mainSet = k - it.edgesMain else {
					crossSet = k - it.edgesCross;
					it.crossAuto = false;
				}
			}
		}
		// (a cross size set: within its min and max, as any size is)
		it.crossSet = Math.isNaN(crossSet) ? Math.NaN : clamp(crossSet + it.edgesCross, it.minCross, it.maxCross);
		var self = logical(selfOf(b, row), b.parent.style.flexWrap == "wrap-reverse");
		it.align = self;
		// (its cross size for laying it out to measure its main size: set, or stretched in a column)
		if (!row) it.cross = !it.crossAuto ? it.crossSet : self == "stretch" && it.autoCross == 0 && single && !Math.isNaN(crossSize) ? clamp(crossSize
			- it.crossStart - it.crossEnd, it.minCross, it.maxCross) : Math.NaN;
		// (the flex base size: flex-basis, else its main size, else its content's)
		var basis = st.flexBasisKeyword;
		var basisLen = st.flexBasis;
		var base = Math.NaN;
		var keywordBasis = basis == "content" || basis == "max-content" || basis == "min-content" || basis == "fit-content" || basis == "stretch";
		if (basis != "auto" && !keywordBasis) {
			base = BlockFlow.size(basisLen, mainBase, s.borderBox, it.edgesMain);
			if (!Math.isNaN(base)) base += it.edgesMain;
		}
		if (Math.isNaN(base) && !keywordBasis && !Math.isNaN(mainSet)) base = mainSet + it.edgesMain;
		// (an aspect-ratio's, its cross size definite: that through the ratio, §9.2.3 B; a stretched one's
		// definite in a single line of a definite cross size, §9.8)
		if (Math.isNaN(base) && !keywordBasis && !Math.isNaN(Ratio.of(b))) {
			var cross = !it.crossAuto ? it.crossSet : self == "stretch" && it.autoCross == 0 && single && !Math.isNaN(crossSize) ? clamp(crossSize
				- it.crossStart - it.crossEnd, it.minCross, it.maxCross) : Math.NaN;
			var through = row ? Ratio.width(b, cross - it.edgesCross, bpx, bpy) : Ratio.height(b, cross - it.edgesCross, bpx, bpy);
			if (!Math.isNaN(through)) base = through + it.edgesMain;
		}
		// (its height in a row where it is known: set, or stretched in a single line of a known height)
		var definiteCross = !it.crossAuto ? it.crossSet : self == "stretch" && it.autoCross == 0 && single && !Math.isNaN(crossSize)
			&& !(columnItem(b.parent) && looseColumns(b)) ? clamp(crossSize - it.crossStart - it.crossEnd, it.minCross, it.maxCross) : Math.NaN;
		// (its content measured where its basis or its auto min is its content's: a whole document in an item, its
		// basis set and clipping, not laid out for it)
		var content:Null<{min:Float, max:Float}> = null;
		function sizes()
			return content != null ? content : content = contentMain(it, row, space, crossSize, row ? definiteCross : Math.NaN, single);
		// (content and max-content its max-content size, min-content its min, fit-content the room within them,
		// stretch the room)
		var room = nanTo(mainBase, Math.POSITIVE_INFINITY) - it.mainStart - it.mainEnd;
		if (Math.isNaN(base)) base = switch basis {
			case "min-content": sizes().min;
			case "fit-content": Math.min(Math.max(sizes().min, room), sizes().max);
			case "stretch" if (room < Math.POSITIVE_INFINITY): room;
			case _: sizes().max;
		}
		base = Math.max(base, it.edgesMain);
		it.basis = base;
		// (min and max: an auto min its content's, no more than its own size; none when it clips)
		var minLen = row ? s.minWidth : s.minHeight, maxLen = row ? s.maxWidth : s.maxHeight;
		var minMain = row && !Math.isNaN(keyMin) ? keyMin - it.edgesMain : BlockFlow.size(minLen, mainBase, s.borderBox, it.edgesMain);
		if (Math.isNaN(minMain)) {
			minMain = st.clips ? 0 : sizes().min - it.edgesMain;
			if (!Math.isNaN(mainSet)) minMain = Math.min(minMain, mainSet);
			// (an aspect-ratio item's content size suggestion within its min and max cross sizes through the
			// ratio, §4.5)
			if (!Math.isNaN(Ratio.of(b))) {
				function through(cross:Float):Float
					return row ? Ratio.width(b, cross - it.edgesCross, bpx, bpy) : Ratio.height(b, cross - it.edgesCross, bpx, bpy);
				var lo = through(it.minCross), hi = it.maxCross == Math.POSITIVE_INFINITY ? Math.NaN : through(it.maxCross);
				// (its definite cross size's through the ratio, the transferred size, no more than its content's)
				var dc = row ? definiteCross : Math.NaN;
				if (!Math.isNaN(dc) && !st.clips && Math.isNaN(mainSet)) minMain = Math.max(minMain, through(dc));
				if (!Math.isNaN(hi)) minMain = Math.min(minMain, hi);
				if (!Math.isNaN(lo)) minMain = Math.max(minMain, lo);
			}
		}
		var maxMain = row && !Math.isNaN(keyMax) ? keyMax - it.edgesMain : BlockFlow.size(maxLen, mainBase, s.borderBox, it.edgesMain);
		it.maxMain = Math.isNaN(maxMain) ? Math.POSITIVE_INFINITY : maxMain + it.edgesMain;
		it.minMain = Math.max(0, Math.min(minMain + it.edgesMain, it.maxMain));
		if (!Math.isNaN(maxMain) && it.minMain > it.maxMain) it.minMain = it.maxMain;
		it.hypo = clamp(base, it.minMain, it.maxMain);
		return it;
	}

	// (its content's main size, min and max, border box: in a row its min- and max-content widths; in a
	// column its height laid out at its cross size)
	function contentMain(it:Item, row:Bool, space:Space, crossSize:Float, cross:Float, single:Bool):{min:Float, max:Float} {
		var b = it.box;
		if (row) {
			// (its content's, its own width aside: the content size suggestion; an aspect-ratio's within
			// its min and max height through it)
			var c = if (b.context == null || b.context == flow) flow.contentSizes(b, space) else if (b.context == this) contentSizes(b, space, cross) else {
				b.context.intrinsic(b, space);
				{min: b.minContent, max: b.maxContent};
			}
			if (Math.isNaN(Ratio.of(b))) return c;
			var s = b.style.model(), e = it.edgesMain;
			return {min: BlockFlow.transferred(b, s, c.min - e, Math.NaN, e, it.edgesCross) + e, max: BlockFlow.transferred(b, s, c.max - e, Math.NaN, e, it.edgesCross) + e};
		}
		var cs = space.child(Math.isNaN(crossSize) ? space.width : crossSize, Math.NaN);
		cs.fragmentation = null;
		cs.ignoreHeight = true;
		cs.fixedWidth = !Math.isNaN(it.cross) ? it.cross : fit(it, crossSize, space);
		var f = child(b, cs);
		var h = space.fragments.height(f);
		it.measured = f;
		it.measuredWidth = cs.fixedWidth;
		// (an aspect-ratio's: its basis its width's through the ratio, §9.2.3 E; its minimum no less than that where
		// its width is definite (set or stretched) and its height auto, its content's, §4.5 and Sizing 4 §5.1)
		var rh = Ratio.height(b, cs.fixedWidth - it.edgesCross, it.edgesCross, it.edgesMain);
		if (!Math.isNaN(rh))
			return {min: Math.isNaN(it.cross) ? h : Lens.isAuto(b.style.model().height) ? Math.max(h, rh + it.edgesMain) : rh + it.edgesMain, max: rh + it.edgesMain};
		return {min: h, max: h};
	}

	// (its cross size at its main size: laid out, or its own; its baseline)
	function measureCross(it:Item, row:Bool, mainSize:Float, crossSize:Float, space:Space) {
		it.frag = laid(it, row, Math.NaN, space, mainSize, crossSize, false);
		var frags = space.fragments;
		it.cross = row ? frags.height(it.frag) : frags.width(it.frag);
		var b = frags.baseline(it.frag);
		it.baseline = Math.isNaN(b) ? frags.height(it.frag) : b;
	}

	// (an item laid out at its main size, its cross size given (stretched) or its own)
	function laid(it:Item, row:Bool, cross:Float, space:Space, mainSize:Float, crossSize:Float, stretched:Bool):Int {
		var b = it.box;
		var fw = row ? it.main : !Math.isNaN(cross) ? cross : !Math.isNaN(it.cross) ? it.cross : Math.NaN;
		// (a column's aspect-ratio item, not stretched, its width its flexed height's through the ratio)
		if (Math.isNaN(fw) && Lens.isAuto(b.style.model().width) && !Math.isNaN(it.main)) {
			var rw = Ratio.width(b, it.main - it.edgesMain, it.edgesCross, it.edgesMain);
			if (!Math.isNaN(rw)) fw = clamp(rw + it.edgesCross, it.minCross, it.maxCross);
		}
		if (Math.isNaN(fw)) fw = fit(it, crossSize, space);
		// (a column's item at the height it was measured at, as wide: that layout is this one, unless what it
		// holds takes a percentage of its height, indefinite when measured)
		if (!row && it.measured >= 0 && fw == it.measuredWidth && Math.abs(space.fragments.height(it.measured) - it.main) < 1e-9
			&& !percentHeights(b)) return it.measured;
		var cs = space.child(row ? mainSize : (Math.isNaN(crossSize) ? space.width : crossSize), row ? crossSize : mainSize);
		cs.fragmentation = null;
		cs.fixedWidth = fw;
		var lazy = Math.isNaN(it.top) ? null : space.lazy, cuts = lazy != null ? lazy.count : 0;
		if (lazy != null) {
			cs.lazy = lazy;
			cs.top = it.top;
		}
		if (row) {
			if (!Math.isNaN(cross)) cs.fixedHeight = cross;
		} else {
			cs.fixedHeight = it.main;
			cs.looseHeight = it.looseMain;
		}
		var f = child(b, cs);
		// (its cuts its last layout's: put back once every item is laid out, in their order)
		if (lazy != null) it.cuts = lazy.take(cuts);
		return f;
	}

	// (whether something takes a percentage of the box's height, indefinite
	// when it was measured: its row gap or grid rows, a child's height, min,
	// max or flex basis, through anonymous boxes)
	static function percentHeights(b:Box):Bool {
		if (Lens.relative(b.style.rowGap) || b.style.inner == BoxStyle.GRID && percent(b.style.rare.gridTemplateRows)) return true;
		var c = b.first;
		while (c != null) {
			if (c.kind != Text && c.kind != Break && !c.absolute) {
				var m = c.style.model();
				if (Lens.relative(m.height) || Lens.relative(m.minHeight) || Lens.relative(m.maxHeight) || Lens.relative(c.style.flexBasis)) return true;
				if (c.anonymous && percentHeights(c)) return true;
			}
			c = c.next;
		}
		return false;
	}

	static function percent(terms:Array<helder.css.CssTerm>):Bool {
		for (t in terms) switch t {
			case Percentage(_): return true;
			case Calc(_, _, _): return true;
			case Func(_, a) | Brackets(_, a) | Part(_, a): if (percent(a)) return true;
			case _:
		}
		return false;
	}

	// (a column's item's width, its own: fit-content in the room, within its min and max)
	function fit(it:Item, crossSize:Float, space:Space):Float {
		var b = it.box;
		if (b.context != null) b.context.intrinsic(b, space) else flow.intrinsic(b, space);
		var room = (Math.isNaN(crossSize) ? Math.POSITIVE_INFINITY : crossSize) - it.crossStart - it.crossEnd;
		return clamp(Math.min(Math.max(b.minContent, room), b.maxContent), it.minCross, it.maxCross);
	}

	// (§9.7: each line's items' main sizes from their bases, grown or shrunk by their factors, frozen at
	// their min or max, until none is left open)
	static function flexible(l:Array<Item>, mainSize:Float, gap:Float) {
		var gaps = gap * (l.length - 1);
		var hypo = gaps;
		for (it in l) hypo += it.hypo + it.mainStart + it.mainEnd;
		var growing = hypo < mainSize;
		var open = false;
		for (it in l) {
			var factor = growing ? it.grow : it.shrink;
			it.frozen = factor == 0 || (growing && it.basis > it.hypo) || (!growing && it.basis < it.hypo);
			it.main = it.frozen ? it.hypo : it.basis;
			if (!it.frozen) open = true;
		}
		var initial = mainSize - gaps;
		for (it in l) initial -= (it.frozen ? it.main : it.basis) + it.mainStart + it.mainEnd;
		var guard = l.length + 1;
		while (open && guard-- > 0) {
			var remaining = mainSize - gaps;
			var factors = 0.0, scaled = 0.0;
			for (it in l) {
				remaining -= (it.frozen ? it.main : it.basis) + it.mainStart + it.mainEnd;
				if (!it.frozen) {
					factors += growing ? it.grow : it.shrink;
					scaled += it.shrink * (it.basis - it.edgesMain);
				}
			}
			if (factors < 1 && Math.abs(initial * factors) < Math.abs(remaining)) remaining = initial * factors;
			var violation = 0.0;
			for (it in l) if (!it.frozen) {
				// (its share as Chromium adds it: rounded to a 64th of a pixel, its LayoutUnit)
				var target = it.basis;
				if (growing) target += Math.fround(remaining * it.grow / factors * 64) / 64;
				else if (scaled > 0) target += Math.fround(remaining * (it.shrink * (it.basis - it.edgesMain)) / scaled * 64) / 64;
				var c = clamp(target, it.minMain, it.maxMain);
				if (c < it.edgesMain) c = it.edgesMain;
				it.violation = c - target;
				violation += it.violation;
				it.main = c;
			}
			open = false;
			for (it in l) {
				if (!it.frozen && (violation == 0 || (violation > 0 && it.violation > 0) || (violation < 0 && it.violation < 0))) it.frozen = true;
				if (!it.frozen) open = true;
			}
		}
	}

	// (justify-content's or align-content's: where the first starts, what goes between, in free space)
	static function distribute(how:String, free:Float, count:Int, reverse:Bool):{start:Float, between:Float} {
		if (how.startsWith("safe ") || how.startsWith("unsafe ")) how = how.substr(how.indexOf(" ") + 1);
		return switch how {
			case "flex-end" | "end": {start: free, between: 0};
			case "center": {start: free / 2, between: 0};
			case "space-between": free > 0 && count > 1 ? {start: 0, between: free / (count - 1)} : {start: 0, between: 0};
			// (with no free space, their fallback: safe center, the start when overflowing: the writing mode's, the
			// other end of a reversed axis)
			case "space-around": free > 0 ? {start: free / count / 2, between: free / count} : {start: reverse ? free : 0, between: 0};
			case "space-evenly": free > 0 ? {start: free / (count + 1), between: free / (count + 1)} : {start: reverse ? free : 0, between: 0};
			case _: {start: 0, between: 0};
		}
	}

	// (an alignment property's value: flow-start and flow-end (flex-start and flex-end, their legacy
	// aliases, Align 3) are the main or cross start and end in a flex container)
	static function keyword(v:String):String
		return switch v.indexOf(" ") >= 0 ? "" : v {
			case "flow-start": "flex-start";
			case "flow-end": "flex-end";
			case k: k;
		}

	// (how far into the free space an alignment puts a box: 0 at the start, 1 at the end; reversed axes flip it)
	static function fraction(how:String, reverse:Bool):Float {
		if (how.startsWith("safe ") || how.startsWith("unsafe ")) how = how.substr(how.indexOf(" ") + 1);
		var f = switch how {
			case "flex-end": 1.0;
			case "center" | "space-around" | "space-evenly": 0.5;
			case _: 0.0;
		}
		return reverse ? 1 - f : f;
	}

	// (align-self, its auto its container's align-items, normal stretch; self-start and self-end by its
	// own direction across a column, where the cross axis is the inline one)
	static function selfOf(b:Box, row:Bool):String {
		var self = keyword(b.style.alignSelf);
		if (self == "auto" || self == "normal" || self == "") self = keyword(b.parent.style.alignItems);
		if (self.startsWith("safe ") || self.startsWith("unsafe ")) self = self.substr(self.indexOf(" ") + 1);
		if (self == "normal" || self == "") self = "stretch";
		if (self == "first baseline") self = "baseline";
		var flipped = !row && b.style.rtl != b.parent.style.rtl;
		return switch self {
			case "self-start": flipped ? "end" : "start";
			case "self-end": flipped ? "start" : "end";
			case k: k;
		}
	}

	// (an alignment in the flex terms the layout places by: start and end, the writing mode's, are the
	// flex ones but on a reversed axis, where they are the other way round)
	static function logical(how:String, reverse:Bool):String {
		if (how.startsWith("safe ") || how.startsWith("unsafe ")) how = how.substr(how.indexOf(" ") + 1);
		return switch how {
			case "start" | "left" | "top": reverse ? "flex-end" : "flex-start";
			case "end" | "right" | "bottom": reverse ? "flex-start" : "flex-end";
			case k: k;
		}
	}

	// (a gap's length against base: normal (Auto) none)
	static function gap(l:Len, base:Float):Float
		return Lens.isAuto(l) ? 0 : nanTo(Lens.resolve(l, base, 0), 0);

	// ---- intrinsic sizes (a row: its items' side by side, or the largest when wrapping; a column: the largest)

	public function intrinsic(box:Box, space:Space) {
		if (!Math.isNaN(box.minContent)) return;
		var s = box.style.model();
		var bpx = BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]) + s.border[1] + s.border[3];
		var min = 0.0, max = 0.0;
		var w = BlockFlow.size(s.width, Math.NaN, s.borderBox, bpx);
		// (an aspect-ratio's: its fixed height's through it, else its content's within its min and max height's)
		var bpy = BlockFlow.fixed(s.padding[0]) + BlockFlow.fixed(s.padding[2]) + s.border[0] + s.border[2];
		if (Math.isNaN(w)) {
			w = Ratio.width(box, BlockFlow.size(s.height, Math.NaN, s.borderBox, bpy), bpx, bpy);
			// (through its aspect ratio: no narrower than its content, its min-width auto, Sizing 4 §5.1)
			if (!Math.isNaN(w) && Lens.isAuto(s.minWidth) && !box.style.clips) w = Math.max(w, contentSizes(box, space).min - bpx);
		}
		if (!Math.isNaN(w)) min = max = w else {
			var c = contentSizes(box, space);
			min = BlockFlow.transferred(box, s, c.min - bpx, Math.NaN, bpx, bpy);
			max = BlockFlow.transferred(box, s, c.max - bpx, Math.NaN, bpx, bpy);
		}
		var maxW = BlockFlow.size(s.maxWidth, Math.NaN, s.borderBox, bpx), minW = BlockFlow.size(s.minWidth, Math.NaN, s.borderBox, bpx);
		if (!Math.isNaN(maxW)) {
			min = Math.min(min, maxW);
			max = Math.min(max, maxW);
		}
		if (!Math.isNaN(minW)) {
			min = Math.max(min, minW);
			max = Math.max(max, minW);
		}
		box.minContent = min + bpx;
		box.maxContent = Math.max(min, max) + bpx;
	}

	// Its items' min- and max-content contributions, side by side in a row (the largest when wrapping), the
	// largest in a column; its own width aside, border box; not cached.
	public function contentSizes(box:Box, space:Space, height = Math.NaN):{min:Float, max:Float} {
		var s = box.style.model();
		var bpx = BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]) + s.border[1] + s.border[3];
		// (size or inline-size containment: as if empty, contain-intrinsic-width's, Contain 2 §3.1)
		var c = box.style.containment;
		if (c.has(Size) || c.has(InlineSize)) {
			var w = box.style.intrinsicSize(true) + bpx;
			return {min: w, max: w};
		}
		var dir = box.style.flexDirection;
		var row = dir != "column" && dir != "column-reverse";
		var wraps = box.style.flexWrap != "nowrap" && box.style.flexWrap != "";
		var colGap = gap(box.style.columnGap, Math.NaN);
		// (a single row of a fixed height: an aspect-ratio's stretched item's width that height's through it, §9.8)
		var bpy = BlockFlow.fixed(s.padding[0]) + BlockFlow.fixed(s.padding[2]) + s.border[0] + s.border[2];
		var fixedCross = row && !wraps ? BlockFlow.size(s.height, Math.NaN, s.borderBox, bpy) : Math.NaN;
		// (a wrapping column of a known height, its own or its stretched one: its columns side by side, its items
		// broken into them at that height, as Chromium sizes it; else as one column)
		var columnH = row || !wraps ? Math.NaN : !Math.isNaN(height) ? height - bpy : BlockFlow.size(s.height, Math.NaN, s.borderBox, bpy);
		if (!row && wraps && Math.isNaN(columnH)) columnH = BlockFlow.size(s.maxHeight, Math.NaN, s.borderBox, bpy);
		var min = 0.0, max = 0.0, n = 0;
		var colW = 0.0, colH = 0.0, columns = 0.0, rowGap = gap(box.style.rowGap, Math.NaN), inColumn = 0;
		var c = box.first;
		while (c != null) {
			if (!c.absolute && !Math.isNaN(columnH)) {
				if (c.context != null) c.context.intrinsic(c, space) else flow.intrinsic(c, space);
				var m = c.style.model();
				var edges = BlockFlow.fixed(m.margin[1]) + BlockFlow.fixed(m.margin[3]);
				var cs = space.child(c.maxContent, columnH);
				cs.fragmentation = null;
				cs.fixedWidth = c.maxContent;
				var ch = space.fragments.height(child(c, cs)) + BlockFlow.fixed(m.margin[0]) + BlockFlow.fixed(m.margin[2]);
				var basis = BlockFlow.size(c.style.flexBasis, Math.NaN, m.borderBox, 0);
				if (!Math.isNaN(basis)) ch = basis + BlockFlow.fixed(m.margin[0]) + BlockFlow.fixed(m.margin[2]);
				if (inColumn > 0 && colH + rowGap + ch > columnH) {
					columns += colW + colGap;
					colW = colH = 0;
					inColumn = 0;
				}
				colH += (inColumn > 0 ? rowGap : 0) + ch;
				colW = Math.max(colW, c.maxContent + edges);
				inColumn++;
			}
			if (!c.absolute) {
				if (c.context != null) c.context.intrinsic(c, space) else flow.intrinsic(c, space);
				var m = c.style.model();
				var edges = BlockFlow.fixed(m.margin[1]) + BlockFlow.fixed(m.margin[3]);
				var cmin = c.minContent + edges, cmax = c.maxContent + edges;
				// (a wrapping column stretched to the row's height: its columns at that height)
				if (!Math.isNaN(fixedCross) && c.context == this && Lens.isAuto(m.height) && selfOf(c, true) == "stretch" && columnWraps(c)
					&& !(columnItem(box) && looseColumns(c))) {
					var r = contentSizes(c, space, fixedCross - BlockFlow.fixed(m.margin[0]) - BlockFlow.fixed(m.margin[2]));
					cmin = r.min + edges;
					cmax = r.max + edges;
				}
				if (!Math.isNaN(fixedCross) && !Math.isNaN(Ratio.of(c)) && Lens.isAuto(m.height) && selfOf(c, true) == "stretch"
					&& !Lens.isAuto(m.margin[0]) && !Lens.isAuto(m.margin[2])) {
					var cbpx = m.border[1] + m.border[3] + BlockFlow.fixed(m.padding[1]) + BlockFlow.fixed(m.padding[3]);
					var cbpy = m.border[0] + m.border[2] + BlockFlow.fixed(m.padding[0]) + BlockFlow.fixed(m.padding[2]);
					var ch = fixedCross - BlockFlow.fixed(m.margin[0]) - BlockFlow.fixed(m.margin[2]) - cbpy;
					var minH = BlockFlow.size(m.minHeight, Math.NaN, m.borderBox, cbpy), maxH = BlockFlow.size(m.maxHeight, Math.NaN, m.borderBox, cbpy);
					ch = clamp(ch, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY));
					cmin = cmax = Ratio.width(c, Math.max(0, ch), cbpx, cbpy) + cbpx + edges;
				}
				// (an item's set width, its basis in a row, within its min and max)
				var set = BlockFlow.size(m.width, Math.NaN, m.borderBox, 0);
				var basis = row ? BlockFlow.size(c.style.flexBasis, Math.NaN, m.borderBox, 0) : Math.NaN;
				if (!Math.isNaN(set)) {
					var bp = m.border[1] + m.border[3] + BlockFlow.fixed(m.padding[1]) + BlockFlow.fixed(m.padding[3]);
					// (a border box no narrower than its padding and border, within its min and max width, the min first)
					var lo = nanTo(BlockFlow.size(m.minWidth, Math.NaN, m.borderBox, bp), 0) + bp;
					var hi = nanTo(BlockFlow.size(m.maxWidth, Math.NaN, m.borderBox, bp), Math.POSITIVE_INFINITY) + bp;
					cmax = clamp(m.borderBox ? Math.max(set, bp) : set + bp, lo, hi) + edges;
					if (row && !c.style.clips) cmin = Math.min(cmin, cmax);
				}
				// (a row's item with a basis that is a length: its base size where its factor that way is 0, else its
				// contribution, no less than its automatic minimum, as Chromium sums a row)
				if (row && !Math.isNaN(basis)) {
					var bp = m.border[1] + m.border[3] + BlockFlow.fixed(m.padding[1]) + BlockFlow.fixed(m.padding[3]);
					var b = (m.borderBox ? Math.max(basis, bp) : basis + bp) + edges;
					var grow = c.style.flexGrow, shrink = c.style.flexShrink;
					var lo = nanTo(BlockFlow.size(m.minWidth, Math.NaN, m.borderBox, bp), Math.NaN);
					if (Math.isNaN(lo)) {
						// (its content's min-content, its own width aside: the content size suggestion)
						var content = c.context == null || c.context == flow ? flow.contentSizes(c, space).min : c.context == this ? contentSizes(c, space).min : c.minContent;
						lo = c.style.clips ? 0 : Math.min(content, Math.isNaN(set) ? Math.POSITIVE_INFINITY : (m.borderBox ? set : set + bp)) - bp;
					}
					lo += bp + edges;
					var hi = nanTo(BlockFlow.size(m.maxWidth, Math.NaN, m.borderBox, bp), Math.POSITIVE_INFINITY) + bp + edges;
					inline function factored(v:Float):Float
						return clamp(v > b && grow == 0 || v < b && shrink == 0 ? b : v, lo, hi);
					cmin = factored(cmin);
					cmax = factored(cmax);
				}
				if (row && !wraps) {
					min += cmin + (n > 0 ? colGap : 0);
					max += cmax + (n > 0 ? colGap : 0);
				} else if (row) {
					min = Math.max(min, cmin);
					max += cmax + (n > 0 ? colGap : 0);
				} else {
					min = Math.max(min, cmin);
					max = Math.max(max, cmax);
				}
				n++;
			}
			c = c.next;
		}
		if (!Math.isNaN(columnH)) max = columns + colW;
		return {min: min + bpx, max: Math.max(min, max) + bpx};
	}

	// (whether a box is a flex column's item: its height that column's to share, its own layout measured first with
	// its height left indefinite, as Chromium does, what it holds sized by that)
	static function columnItem(b:Box):Bool {
		var p = b.parent;
		if (p == null || b.absolute || p.style.inner != BoxStyle.FLEX) return false;
		var d = p.style.flexDirection;
		return d == "column" || d == "column-reverse";
	}

	// (a wrapping column a column's row measures unbroken, as Chromium: no height in pixels, nothing in it a
	// percentage of its height)
	static function looseColumns(b:Box):Bool {
		if (!columnWraps(b)) return true;
		var m = b.style.model();
		if (m.height.match(Px(_)) || Lens.relative(m.height) || Lens.relative(m.minHeight) || Lens.relative(m.maxHeight)) return false;
		var c = b.first;
		while (c != null) {
			if (!c.absolute) {
				var cm = c.style.model();
				if (Lens.relative(cm.height) || Lens.relative(cm.minHeight) || Lens.relative(cm.maxHeight) || Lens.relative(c.style.flexBasis)) return false;
			}
			c = c.next;
		}
		return true;
	}

	static function columnWraps(b:Box):Bool {
		var d = b.style.flexDirection, w = b.style.flexWrap;
		return (d == "column" || d == "column-reverse") && w != "nowrap" && w != "";
	}

	static inline function clamp(v:Float, lo:Float, hi:Float):Float
		return v > hi ? (hi < lo ? lo : hi) : v < lo ? lo : v;

	static inline function nanTo(v:Float, d:Float):Float
		return Math.isNaN(v) ? d : v;
}

private class Item {
	public final box:Box;
	public final index:Int;
	public var order = 0;
	public var grow = 0.0;
	public var shrink = 1.0;
	public var mainStart = 0.0;
	public var mainEnd = 0.0;
	// (a column's item flexed in a column of no definite height: its height not definite)
	public var looseMain = false;
	public var crossStart = 0.0;
	public var crossEnd = 0.0;
	// (its auto margins: 1 at the start, 2 at the end)
	public var autoMain = 0;
	public var autoCross = 0;
	public var edgesMain = 0.0;
	public var edgesCross = 0.0;
	public var basis = 0.0;
	public var hypo = 0.0;
	public var main = 0.0;
	public var minMain = 0.0;
	public var maxMain = Math.POSITIVE_INFINITY;
	public var cross = Math.NaN;
	public var crossSet = Math.NaN;
	// (a column's item laid out to measure its height, at measuredWidth; -1: not)
	public var measured = -1;
	public var measuredWidth = Math.NaN;
	public var crossAuto = true;
	public var minCross = 0.0;
	public var maxCross = Math.POSITIVE_INFINITY;
	public var align = "stretch";
	public var baseline = 0.0;
	public var frozen = false;
	public var violation = 0.0;
	public var frag = -1;
	// (where a long document's cut goes into it: its top in the document, NaN: not; the cuts its layout made)
	public var top = Math.NaN;
	public var cuts:Null<Array<Box>> = null;
	// (its place in the content box, and its line)
	public var x = 0.0;
	public var y = 0.0;
	public var line = 0;

	public function new(box:Box, index:Int) {
		this.box = box;
		this.index = index;
	}
}
