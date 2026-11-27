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
		var reusable = box.flags & Box.ESCAPES == 0 && Math.isNaN(space.fixedHeight) && space.fragmentation == null;
		if (reusable && box.cacheFragment >= 0 && box.cacheWidth == key && same(box.cacheHeight, space.height)) return box.cacheFragment;
		var f = container(box, space);
		box.cacheWidth = key;
		box.cacheHeight = space.height;
		box.cacheFragment = reusable ? f : -1;
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
		var bpx = pl + pr + bl + br, bpy = pt + pb + bt + bb;
		var w = width(box, s, space, bpx);
		var heightSpec = !Math.isNaN(space.fixedHeight) ? Math.max(0, space.fixedHeight - bpy) : BlockFlow.size(s.height, space.height, s.borderBox, bpy);
		if (!Math.isNaN(heightSpec)) heightSpec = BlockFlow.clampHeight(s, space.height, bpy, heightSpec);
		var minH = BlockFlow.size(s.minHeight, space.height, s.borderBox, bpy), maxH = BlockFlow.size(s.maxHeight, space.height, s.borderBox, bpy);
		var frags = space.fragments;
		var frag = frags.add(Fragments.BOX, box, w + bpx, 0);
		var dir = box.style.keyword("flex-direction");
		var row = dir != "column" && dir != "column-reverse", reverse = dir == "row-reverse" || dir == "column-reverse";
		var wrap = box.style.keyword("flex-wrap");
		var wraps = wrap == "wrap" || wrap == "wrap-reverse", wrapReverse = wrap == "wrap-reverse";
		var rtl = box.style.rtl;
		var rowGap = gap(box.style, "row-gap", heightSpec), colGap = gap(box.style, "column-gap", w);
		var mainGap = row ? colGap : rowGap, crossGap = row ? rowGap : colGap;
		// (the main size: definite or not; a column without a height breaks its lines at its max-height)
		var mainSize = row ? w : heightSpec;
		var mainLimit = row ? w : !Math.isNaN(heightSpec) ? heightSpec : !Math.isNaN(maxH) ? maxH : Math.POSITIVE_INFINITY;
		var crossSize = row ? heightSpec : w;
		// (absolutely positioned children: for the nearest positioned box; the others are items, in order)
		var owner = box.parent == null || box.style.positioned;
		var positioned = owner ? new Positioned() : space.positioned ?? new Positioned();
		var fixed = box.parent == null ? new Positioned() : space.fixed ?? positioned;
		var items:Array<Item> = [];
		var c = box.first, index = 0;
		var abs:Array<Box> = [];
		while (c != null) {
			if (c.absolute) abs.push(c) else
				items.push(item(c, row, w, heightSpec, crossSize, space, index++));
			c = c.next;
		}
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
				if (it.align == "baseline" && row && it.autoCross == 0) {
					above = Math.max(above, it.baseline + it.crossStart);
					below = Math.max(below, outer - it.baseline - it.crossStart);
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
		var content = logical(keyword(box.style, "align-content"), wrapReverse);
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
		var baseline = Math.NaN;
		var justify = logical(keyword(box.style, "justify-content"), reverse);
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
					case "baseline" if (row && it.autoCross == 0): cpos = lineBase[k] - it.baseline;
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
				frags.adopt(frag, it.frag, bl + pl + x + off.x, bt + pt + y + off.y);
				if (Math.isNaN(baseline) && k == 0) {
					var b = frags.baseline(it.frag);
					baseline = bt + pt + y + (Math.isNaN(b) ? frags.height(it.frag) : b);
				}
			}
		}
		var h = row ? crossSize : mainSize;
		if (Math.isNaN(heightSpec)) h = clamp(h, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY));
		// (absolutely positioned children: static places as if each were the only item, Flexbox §4.1:
		// justify-content along the main axis, align-self across, in the content box)
		for (a in abs) {
			var j = fraction(justify, reverse), self = logical(selfOf(a, row), wrapReverse);
			var k = fraction(self == "stretch" || self == "baseline" ? "flex-start" : self, wrapReverse);
			var fx = row ? (rtl ? 1 - j : j) : (rtl ? 1 - k : k), fy = row ? k : j;
			(a.style.position == "fixed" ? fixed : positioned).add(a, frag, bl + pl, bt + pt, [bl + pl, bt + pt, w, h, fx, fy]);
		}
		frags.resize(frag, w + bpx, h + bpy);
		if (!Math.isNaN(baseline)) frags.setBaseline(frag, baseline);
		// (its margins for its parent: a flex container's don't collapse with its items')
		var mt = BlockFlow.res(s.margin[0], cb), mb = BlockFlow.res(s.margin[2], cb);
		box.topPositive = mt > 0 ? mt : 0;
		box.topNegative = mt < 0 ? mt : 0;
		box.bottomPositive = mb > 0 ? mb : 0;
		box.bottomNegative = mb < 0 ? mb : 0;
		box.through = false;
		if (box.parent == null) {
			flow.place(fixed, frag, space, -box.marginLeft, 0, space.width, space.height);
			flow.place(positioned, frag, space, -box.marginLeft, 0, space.width, space.height);
		} else if (owner)
			flow.place(positioned, frag, space, bl, bt, w + pl + pr, h + pt + pb);
		return frag;
	}

	// (the container's content width: given, set, or filling its containing block; shrink-to-fit when it
	// floats, is absolutely positioned or inline-level)
	function width(box:Box, s:BoxStyle, space:Space, bpx:Float):Float {
		var cb = space.width;
		var ml = BlockFlow.auto(s.margin[3], cb), mr = BlockFlow.auto(s.margin[1], cb);
		var minW = nanTo(BlockFlow.size(s.minWidth, cb, s.borderBox, bpx), 0), maxW = BlockFlow.size(s.maxWidth, cb, s.borderBox, bpx);
		if (!Math.isNaN(space.fixedWidth)) {
			box.marginLeft = nanTo(ml, 0);
			box.marginRight = nanTo(mr, 0);
			return Math.max(0, space.fixedWidth - bpx);
		}
		var spec = BlockFlow.size(s.width, cb, s.borderBox, bpx);
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

	function item(b:Box, row:Bool, w:Float, h:Float, crossSize:Float, space:Space, index:Int):Item {
		var it = new Item(b, index);
		var s = b.style.model(), st = b.style;
		var cb = w;
		it.order = Std.int(st.number("order", 0));
		it.grow = st.number("flex-grow", 0);
		it.shrink = st.number("flex-shrink", 1);
		var ml = BlockFlow.auto(s.margin[3], cb), mr = BlockFlow.auto(s.margin[1], cb);
		var mt = BlockFlow.auto(s.margin[0], cb), mb = BlockFlow.auto(s.margin[2], cb);
		var rtl = b.parent != null && b.parent.style.rtl;
		// (main start and end: left and right in a row, mirrored right to left; top and bottom in a column)
		var ms = row ? (rtl ? mr : ml) : mt, me = row ? (rtl ? ml : mr) : mb;
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
		it.crossAuto = Math.isNaN(crossSet);
		it.crossSet = Math.isNaN(crossSet) ? Math.NaN : crossSet + it.edgesCross;
		it.minCross = nanTo(BlockFlow.size(row ? s.minHeight : s.minWidth, crossBase, s.borderBox, it.edgesCross), 0) + it.edgesCross;
		it.maxCross = nanTo(BlockFlow.size(row ? s.maxHeight : s.maxWidth, crossBase, s.borderBox, it.edgesCross), Math.POSITIVE_INFINITY) + it.edgesCross;
		var self = logical(selfOf(b, row), b.parent.style.keyword("flex-wrap") == "wrap-reverse");
		it.align = self;
		// (its cross size for laying it out to measure its main size: set, or stretched in a column)
		if (!row) it.cross = !it.crossAuto ? it.crossSet : self == "stretch" && it.autoCross == 0 && !Math.isNaN(crossSize) ? clamp(crossSize
			- it.crossStart - it.crossEnd, it.minCross, it.maxCross) : Math.NaN;
		// (the flex base size: flex-basis, else its main size, else its content's)
		var basis = st.keyword("flex-basis");
		var basisLen = st.len("flex-basis");
		var base = Math.NaN;
		var keywordBasis = basis == "content" || basis == "max-content" || basis == "min-content" || basis == "fit-content" || basis == "stretch";
		if (basis != "auto" && !keywordBasis) {
			base = BlockFlow.size(basisLen, mainBase, s.borderBox, it.edgesMain);
			if (!Math.isNaN(base)) base += it.edgesMain;
		}
		if (Math.isNaN(base) && !keywordBasis && !Math.isNaN(mainSet)) base = mainSet + it.edgesMain;
		var content = contentMain(it, row, space, crossSize);
		// (content and max-content its max-content size, min-content its min, fit-content the room within them,
		// stretch the room)
		var room = nanTo(mainBase, Math.POSITIVE_INFINITY) - it.mainStart - it.mainEnd;
		if (Math.isNaN(base)) base = switch basis {
			case "min-content": content.min;
			case "fit-content": Math.min(Math.max(content.min, room), content.max);
			case "stretch" if (room < Math.POSITIVE_INFINITY): room;
			case _: content.max;
		}
		base = Math.max(base, it.edgesMain);
		it.basis = base;
		// (min and max: an auto min its content's, no more than its own size; none when it clips)
		var minLen = row ? s.minWidth : s.minHeight, maxLen = row ? s.maxWidth : s.maxHeight;
		var minMain = BlockFlow.size(minLen, mainBase, s.borderBox, it.edgesMain);
		if (Math.isNaN(minMain)) {
			minMain = st.clips ? 0 : content.min - it.edgesMain;
			if (!Math.isNaN(mainSet)) minMain = Math.min(minMain, mainSet);
		}
		var maxMain = BlockFlow.size(maxLen, mainBase, s.borderBox, it.edgesMain);
		it.maxMain = Math.isNaN(maxMain) ? Math.POSITIVE_INFINITY : maxMain + it.edgesMain;
		it.minMain = Math.max(0, Math.min(minMain + it.edgesMain, it.maxMain));
		if (!Math.isNaN(maxMain) && it.minMain > it.maxMain) it.minMain = it.maxMain;
		it.hypo = clamp(base, it.minMain, it.maxMain);
		return it;
	}

	// (its content's main size, min and max, border box: in a row its min- and max-content widths; in a
	// column its height laid out at its cross size)
	function contentMain(it:Item, row:Bool, space:Space, crossSize:Float):{min:Float, max:Float} {
		var b = it.box;
		if (row) {
			// (its content's, its own width aside: the content size suggestion)
			if (b.context == null || b.context == flow) return flow.contentSizes(b, space);
			if (b.context == this) return contentSizes(b, space);
			b.context.intrinsic(b, space);
			return {min: b.minContent, max: b.maxContent};
		}
		var cs = space.child(Math.isNaN(crossSize) ? space.width : crossSize, Math.NaN);
		cs.fragmentation = null;
		cs.ignoreHeight = true;
		if (!Math.isNaN(it.cross)) cs.fixedWidth = it.cross else {
			if (b.context != null) b.context.intrinsic(b, space) else flow.intrinsic(b, space);
			var room = (Math.isNaN(crossSize) ? Math.POSITIVE_INFINITY : crossSize) - it.crossStart - it.crossEnd;
			cs.fixedWidth = clamp(Math.min(Math.max(b.minContent, room), b.maxContent), it.minCross, it.maxCross);
		}
		var f = child(b, cs);
		var h = space.fragments.height(f);
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
		var cs = space.child(row ? mainSize : (Math.isNaN(crossSize) ? space.width : crossSize), row ? crossSize : mainSize);
		cs.fragmentation = null;
		if (row) {
			cs.fixedWidth = it.main;
			if (!Math.isNaN(cross)) cs.fixedHeight = cross;
		} else {
			cs.fixedHeight = it.main;
			if (!Math.isNaN(cross)) cs.fixedWidth = cross else if (!Math.isNaN(it.cross)) cs.fixedWidth = it.cross else {
				if (b.context != null) b.context.intrinsic(b, space) else flow.intrinsic(b, space);
				var room = (Math.isNaN(crossSize) ? Math.POSITIVE_INFINITY : crossSize) - it.crossStart - it.crossEnd;
				cs.fixedWidth = clamp(Math.min(Math.max(b.minContent, room), b.maxContent), it.minCross, it.maxCross);
			}
		}
		b.cacheFragment = -1;
		return child(b, cs);
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
			// (with no free space, their fallback: safe center, the start when overflowing)
			case "space-around": free > 0 ? {start: free / count / 2, between: free / count} : {start: 0, between: 0};
			case "space-evenly": free > 0 ? {start: free / (count + 1), between: free / (count + 1)} : {start: 0, between: 0};
			case _: {start: 0, between: 0};
		}
	}

	// (an alignment property's value: flow-start and flow-end (flex-start and flex-end, their legacy
	// aliases, Align 3) are the main or cross start and end in a flex container)
	static function keyword(s:BoxStyle, p:String):String
		return switch s.keyword(p) {
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
		var self = keyword(b.style, "align-self");
		if (self == "auto" || self == "normal" || self == "") self = keyword(b.parent.style, "align-items");
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

	static function gap(s:BoxStyle, p:String, base:Float):Float {
		if (s.keyword(p) == "normal") return 0;
		return nanTo(Lens.resolve(s.len(p), base, 0), 0);
	}

	// ---- intrinsic sizes (a row: its items' side by side, or the largest when wrapping; a column: the largest)

	public function intrinsic(box:Box, space:Space) {
		if (!Math.isNaN(box.minContent)) return;
		var s = box.style.model();
		var bpx = BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]) + s.border[1] + s.border[3];
		var min = 0.0, max = 0.0;
		var w = BlockFlow.size(s.width, Math.NaN, s.borderBox, bpx);
		if (!Math.isNaN(w)) min = max = w else {
			var c = contentSizes(box, space);
			min = c.min - bpx;
			max = c.max - bpx;
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
	public function contentSizes(box:Box, space:Space):{min:Float, max:Float} {
		var s = box.style.model();
		var bpx = BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]) + s.border[1] + s.border[3];
		var dir = box.style.keyword("flex-direction");
		var row = dir != "column" && dir != "column-reverse";
		var wraps = box.style.keyword("flex-wrap") != "nowrap" && box.style.keyword("flex-wrap") != "";
		var colGap = gap(box.style, "column-gap", Math.NaN);
		var min = 0.0, max = 0.0, n = 0;
		var c = box.first;
		while (c != null) {
			if (!c.absolute) {
				if (c.context != null) c.context.intrinsic(c, space) else flow.intrinsic(c, space);
				var m = c.style.model();
				var edges = BlockFlow.fixed(m.margin[1]) + BlockFlow.fixed(m.margin[3]);
				var cmin = c.minContent + edges, cmax = c.maxContent + edges;
				// (an item's set width, its basis in a row, within its min and max)
				var set = BlockFlow.size(m.width, Math.NaN, m.borderBox, 0);
				if (!Math.isNaN(set)) {
					var bp = m.border[1] + m.border[3] + BlockFlow.fixed(m.padding[1]) + BlockFlow.fixed(m.padding[3]);
					cmax = (m.borderBox ? set : set + bp) + edges;
					if (row && !c.style.clips) cmin = Math.min(cmin, cmax);
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
		return {min: min + bpx, max: Math.max(min, max) + bpx};
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
	public var crossAuto = true;
	public var minCross = 0.0;
	public var maxCross = Math.POSITIVE_INFINITY;
	public var align = "stretch";
	public var baseline = 0.0;
	public var frozen = false;
	public var violation = 0.0;
	public var frag = -1;

	public function new(box:Box, index:Int) {
		this.box = box;
		this.index = index;
	}
}
