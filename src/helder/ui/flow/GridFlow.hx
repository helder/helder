package helder.ui.flow;

import helder.css.CssText;
import helder.ui.Grid.GridAreas;
import helder.ui.Grid.Track;
import helder.ui.Grid.TrackSize;
import helder.ui.flow.GridTemplate.FitTrack;
import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.box.Fragments;
import helder.ui.box.Len;

using StringTools;

// Grid layout (CSS Grid Layout 1, a subset), as helder.ui's GridLayout has it
// for its own nodes (the same placement and track sizing, Taffy's fixtures
// their test) over the box tree: the explicit grid's tracks and named lines
// (grid-template-columns, -rows, GridTemplate's: auto-fill and auto-fit
// repeats, fit-content(); -areas, helder.ui's Grid parses), implicit ones
// as items need (grid-auto-columns, -rows in turn); items placed by their
// lines (GridLines) or auto-placed (grid-auto-flow: rows or columns, sparse
// or dense), auto-fit's empty tracks collapsed; the
// tracks sized columns first, then rows at the columns' widths (§11.3 to
// §11.8: intrinsic tracks from the items' minimum, min- and max-content
// contributions, spanning items by span, those crossing flexible tracks
// last; the free space up to the growth limits; fr tracks at the size of an
// fr; auto tracks stretched); each item in its area by justify-self and
// align-self (baselines shared in a row), laid out by its own context.
// Absolutely positioned children: the content box's start as their static
// place.
class GridFlow implements FormattingContext {
	final flow:BlockFlow;

	public function new(flow:BlockFlow)
		this.flow = flow;

	public function layout(box:Box, space:Space):Int {
		var key = Math.isNaN(space.fixedWidth) ? space.width : -1 - space.fixedWidth;
		var reusable = box.flags & Box.ESCAPES == 0 && Math.isNaN(space.fixedHeight) && space.fragmentation == null && !space.ignoreHeight;
		if (reusable && box.cacheFragment >= 0 && box.cacheWidth == key && (box.cacheHeight == space.height || Math.isNaN(box.cacheHeight)
			&& Math.isNaN(space.height))) return box.cacheFragment;
		var f = container(box, space);
		box.cacheWidth = key;
		box.cacheHeight = space.height;
		box.cacheFragment = reusable ? f : -1;
		return f;
	}

	// ---- the container

	function container(box:Box, space:Space):Int {
		var s = box.style.model(), st = box.style;
		var cb = space.width;
		var pl = BlockFlow.res(s.padding[3], cb), pr = BlockFlow.res(s.padding[1], cb), pt = BlockFlow.res(s.padding[0], cb), pb = BlockFlow.res(s.padding[2], cb);
		var bl = s.border[3], br = s.border[1], bt = s.border[0], bb = s.border[2];
		// (in a fragmentainer, resumed: its start's border and padding were in the one before)
		var fr = space.fragmentation;
		var resume = fr != null ? fr.resume(box) : null;
		if (resume != null) bt = pt = 0;
		var bpx = pl + pr + bl + br, bpy = pt + pb + bt + bb;
		var heightSpec = !Math.isNaN(space.fixedHeight) ? Math.max(0, space.fixedHeight - bpy) : space.ignoreHeight ? Math.NaN : BlockFlow.size(s.height,
			space.height, s.borderBox, bpy);
		if (!Math.isNaN(heightSpec) && !space.ignoreHeight) heightSpec = BlockFlow.clampHeight(s, space.height, bpy, heightSpec);
		var w = width(box, s, space, bpx, heightSpec);
		// (an aspect-ratio's auto height: its width's through it)
		if (Math.isNaN(heightSpec) && Math.isNaN(space.fixedHeight)) {
			var rh = Ratio.height(box, w, bpx, bpy);
			if (!Math.isNaN(rh)) heightSpec = BlockFlow.clampHeight(s, space.height, bpy, rh);
		}
		var minH = space.ignoreHeight ? Math.NaN : BlockFlow.size(s.minHeight, space.height, s.borderBox, bpy);
		var maxH = space.ignoreHeight ? Math.NaN : BlockFlow.size(s.maxHeight, space.height, s.borderBox, bpy);
		var frags = space.fragments;
		var frag = frags.add(Fragments.BOX, box, w + bpx, 0);
		var rtl = st.rtl;
		var g = grid(box, space, w, heightSpec);
		var items = g.items;
		var colGap = gap(st, "column-gap", w), rowGap = gap(st, "row-gap", heightSpec);
		// (the columns at the content box's width; then the rows, the items at their columns' widths)
		var stretchCols = keyword(st, "justify-content") == "normal";
		var align = keyword(st, "align-content");
		var stretchRows = align == "normal" || align == "stretch";
		var cols = tracks(g.cols, items, true, w, w, colGap, stretchCols, space, null);
		for (it in items) {
			it.areaW = colGap * (it.colSpan - 1);
			for (i in it.col...it.col + it.colSpan) it.areaW += cols[i];
		}
		shims(items, st, space);
		var rows = tracks(g.rows, items, false, heightSpec, heightSpec, rowGap, stretchRows, space, cols, false, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY));
		var gridH = sum(rows, rowGap);
		var h = !Math.isNaN(heightSpec) ? heightSpec : clamp(gridH, nanTo(minH, 0), nanTo(maxH, Math.POSITIVE_INFINITY));
		// (an auto height its min-height made more: the rows stretched to it; fr rows sized again at it)
		if (Math.isNaN(heightSpec) && (stretchRows && h > gridH + 1e-6 || Lambda.exists(g.rows, t -> t.max.match(Fr(_)))))
			rows = tracks(g.rows, items, false, h, h, rowGap, stretchRows, space, cols);
		// (the tracks' places: justify-content and align-content in the content box)
		var colPos = positions(cols, colGap, w, keyword(st, "justify-content"));
		var rowPos = positions(rows, rowGap, h, align);
		var baseline = Math.NaN, firstRow = 0x7fffffff;
		for (it in items) if (it.row < firstRow) firstRow = it.row;
		var pick:Null<GridItem> = null;
		for (it in items) {
			var c = it.box, m = c.style.model();
			var ax = colPos[it.col], aw = colPos[it.col + it.colSpan - 1] + cols[it.col + it.colSpan - 1] - ax;
			var ay = rowPos[it.row], ah = rowPos[it.row + it.rowSpan - 1] + rows[it.row + it.rowSpan - 1] - ay;
			var jx = selfOf(c, "justify-self", "justify-items"), jy = selfOf(c, "align-self", "align-items");
			var ml = BlockFlow.auto(m.margin[3], aw), mr = BlockFlow.auto(m.margin[1], aw);
			var mt = BlockFlow.auto(m.margin[0], aw), mb = BlockFlow.auto(m.margin[2], aw);
			var autoS = Math.isNaN(rtl ? mr : ml), autoE = Math.isNaN(rtl ? ml : mr), autoT = Math.isNaN(mt), autoB = Math.isNaN(mb);
			if ((autoS || autoE) && jx == "stretch") jx = "start";
			if ((autoT || autoB) && jy == "stretch") jy = "start";
			ml = nanTo(ml, 0);
			mr = nanTo(mr, 0);
			mt = nanTo(mt, 0);
			mb = nanTo(mb, 0);
			var roomW = Math.max(0, aw - ml - mr), roomH = Math.max(0, ah - mt - mb);
			var cbpx = m.border[1] + m.border[3] + BlockFlow.res(m.padding[1], aw) + BlockFlow.res(m.padding[3], aw);
			var cbpy = m.border[0] + m.border[2] + BlockFlow.res(m.padding[0], aw) + BlockFlow.res(m.padding[2], aw);
			var minCW = nanTo(BlockFlow.size(m.minWidth, aw, m.borderBox, cbpx), 0) + cbpx, maxCW = nanTo(BlockFlow.size(m.maxWidth, aw, m.borderBox, cbpx), Math.POSITIVE_INFINITY) + cbpx;
			var minCH = nanTo(BlockFlow.size(m.minHeight, ah, m.borderBox, cbpy), 0) + cbpy, maxCH = nanTo(BlockFlow.size(m.maxHeight, ah, m.borderBox, cbpy), Math.POSITIVE_INFINITY) + cbpy;
			var sw = BlockFlow.size(m.width, aw, m.borderBox, cbpx), sh = BlockFlow.size(m.height, ah, m.borderBox, cbpy);
			var iw = Math.isNaN(sw) ? Math.NaN : clamp(sw + cbpx, minCW, maxCW), ih = Math.isNaN(sh) ? Math.NaN : clamp(sh + cbpy, minCH, maxCH);
			// (an aspect-ratio's, normal: stretched across, its height through the ratio, and so its width within
			// its min and max height's through it when that is stretched too, as Chromium has it)
			var ratio = !Math.isNaN(Ratio.of(c)), normal = jy == "stretch" && normal(c);
			if (Math.isNaN(iw) && jx == "stretch" && ratio && Math.isNaN(ih) && jy == "stretch") {
				var lo = Ratio.width(c, minCH - cbpy, cbpx, cbpy) + cbpx, hi = Ratio.width(c, maxCH - cbpy, cbpx, cbpy) + cbpx;
				iw = clamp(Math.min(roomW, hi), Math.max(minCW, lo), maxCW);
			}
			if (ratio && normal) jy = "start";
			if (Math.isNaN(iw)) {
				if (jx == "stretch") iw = clamp(roomW, minCW, maxCW) else {
					// (fit-content: its max-content width, no more than the area, no less than its min-content)
					intrinsicOf(c, space);
					iw = clamp(Math.min(c.maxContent, Math.max(roomW, c.minContent)), minCW, maxCW);
				}
			}
			var cs = space.child(aw, ah);
			cs.fragmentation = null;
			cs.fixedWidth = iw;
			if (Math.isNaN(ih) && jy == "stretch") ih = clamp(roomH, minCH, maxCH);
			if (!Math.isNaN(ih)) cs.fixedHeight = ih;
			c.cacheFragment = -1;
			var f = flow.child(c, cs);
			if (Math.isNaN(ih)) ih = frags.height(f);
			if (autoS || autoE) jx = roomW - iw <= 0 ? "start" : autoS && autoE ? "center" : autoS ? "end" : "start";
			if (autoT || autoB) jy = roomH - ih <= 0 ? "start" : autoT && autoB ? "center" : autoT ? "end" : "start";
			var x = ax + (rtl ? mr : ml) + switch jx {
				case "end": roomW - iw;
				case "center": (roomW - iw) / 2;
				case _: 0;
			}
			if (rtl) x = w - x - iw;
			var y = ay + mt + switch jy {
				case "end": roomH - ih;
				case "center": (roomH - ih) / 2;
				case "baseline": it.shim;
				case _: 0;
			}
			var off = BlockFlow.offset(c, aw, ah);
			if (fr == null) frags.adopt(frag, f, bl + pl + x + off.x, bt + pt + y + off.y);
			it.x = x + off.x;
			it.top = y + off.y;
			it.y = y;
			it.frag = f;
			if (it.row == firstRow && (pick == null || !onBaseline(pick) && onBaseline(it))) pick = it;
		}
		// (its baseline: the first row's item on its baseline, else its first; that item's bottom without one)
		if (pick != null) {
			var b = frags.baseline(pick.frag);
			baseline = bt + pt + pick.y + (Math.isNaN(b) ? frags.height(pick.frag) : b);
		}
		// (in a fragmentainer: its rows here, rows that spanning items join one, from where it resumes to a break;
		// broken, its end's border and padding in a later one, its height to the fragmentainer's end)
		var broken = false;
		if (fr != null) {
			var group = [], reach = -1, n = -1;
			for (r in 0...rows.length) {
				if (r > reach) n++;
				for (it in items) if (it.row == r && it.row + it.rowSpan - 1 > reach) reach = it.row + it.rowSpan - 1;
				if (reach < r) reach = r;
				group.push(n);
			}
			var parts = new Rows();
			for (it in items) {
				var m = it.box.style.model(), ih = frags.height(it.frag);
				parts.add(group[it.row], it.box, it.frag, it.x, it.top, it.top - BlockFlow.res(m.margin[0], w), it.top + ih + BlockFlow.res(m.margin[2], w));
			}
			var r = parts.place(box, frag, space, flow, bl + pl, bt + pt, h);
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
		frags.resize(frag, w + bpx, h + bpy);
		if (!Math.isNaN(baseline)) frags.setBaseline(frag, baseline);
		var mt = resume != null ? 0 : BlockFlow.res(s.margin[0], cb), mb = broken ? 0 : BlockFlow.res(s.margin[2], cb);
		box.topPositive = mt > 0 ? mt : 0;
		box.topNegative = mt < 0 ? mt : 0;
		box.bottomPositive = mb > 0 ? mb : 0;
		box.bottomNegative = mb < 0 ? mb : 0;
		box.through = false;
		// (absolutely positioned children: at the content box's start, for their containing block; when it is
		// this grid, the area their lines give (an auto one, or one the grid hasn't, its padding edge), §9.1)
		var owner = box.parent == null || st.positioned;
		var positioned = owner ? new Positioned() : space.positioned ?? new Positioned();
		var fixed = box.parent == null ? new Positioned() : space.fixed ?? positioned;
		var fullW = w + pl + pr, fullH = h + pt + pb;
		// (each line where an area starts at it, its next track's start, and where one ends at it, its track's end: gaps between)
		var colLines = lines(colPos, cols, rtl ? pr : pl, true), rowLines = lines(rowPos, rows, pt, true);
		var colEnds = lines(colPos, cols, rtl ? pr : pl, false), rowEnds = lines(rowPos, rows, pt, false);
		if (resume == null) for (a in g.absolute) {
			if (owner && a.style.position != "fixed" && box.parent != null) {
				var c = area(g.colLines, a.style, "grid-column", colLines, colEnds, g.shiftCols, g.colMap, fullW);
				var r = area(g.rowLines, a.style, "grid-row", rowLines, rowEnds, g.shiftRows, g.rowMap, fullH);
				var x0 = rtl ? fullW - c.to : c.from;
				var one = new Positioned();
				one.add(a, frag, bl + x0 + (rtl ? c.to - c.from : 0), bt + r.from);
				flow.place(one, frag, space, bl + x0, bt + r.from, c.to - c.from, r.to - r.from, broken);
				continue;
			}
			(a.style.position == "fixed" ? fixed : positioned).add(a, frag, bl + pl + (rtl ? w : 0), bt + pt);
		}
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

	// ---- the grid: tracks and placed items

	function grid(box:Box, space:Space, w:Float, h:Float):Grid {
		var st = box.style, s = st.model();
		var items:Array<GridItem> = [], absolute:Array<Box> = [];
		var c = box.first;
		while (c != null) {
			if (c.absolute) absolute.push(c) else items.push(new GridItem(c));
			c = c.next;
		}
		var areas = try {
			var t = text(st, "grid-template-areas");
			t == "none" || t == "" ? null : GridAreas.parse(t);
		} catch (_:Dynamic) null;
		// (an auto repeat's room: the content box's size, else its max; its min the size to reach)
		var bpx = s.border[1] + s.border[3] + BlockFlow.res(s.padding[1], space.width) + BlockFlow.res(s.padding[3], space.width);
		var bpy = s.border[0] + s.border[2] + BlockFlow.res(s.padding[0], space.width) + BlockFlow.res(s.padding[2], space.width);
		var colsTemplate = GridTemplate.parse(st, "grid-template-columns", !Math.isNaN(w) ? w : BlockFlow.size(s.maxWidth, space.width, s.borderBox, bpx),
			BlockFlow.size(s.minWidth, space.width, s.borderBox, bpx), gap(st, "column-gap", w));
		var rowsTemplate = GridTemplate.parse(st, "grid-template-rows", !Math.isNaN(h) ? h : BlockFlow.size(s.maxHeight, space.height, s.borderBox, bpy),
			BlockFlow.size(s.minHeight, space.height, s.borderBox, bpy), gap(st, "row-gap", h));
		var autoCols = GridTemplate.parse(st, "grid-auto-columns", w, Math.NaN, 0).tracks, autoRows = GridTemplate.parse(st, "grid-auto-rows", h, Math.NaN, 0).tracks;
		var explicitCols = areas == null ? colsTemplate.tracks.length : Std.int(Math.max(colsTemplate.tracks.length, areas.columns));
		var explicitRows = areas == null ? rowsTemplate.tracks.length : Std.int(Math.max(rowsTemplate.tracks.length, areas.rows));
		var colLines = new GridLines(explicitCols, names(colsTemplate, areas, explicitCols, true));
		var rowLines = new GridLines(explicitRows, names(rowsTemplate, areas, explicitRows, false));
		var shift = place(items, st, colLines, rowLines);
		var nCols = explicitCols + shift.cols, nRows = explicitRows + shift.rows;
		for (it in items) {
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
			if (it.row + it.rowSpan > nRows) nRows = it.row + it.rowSpan;
		}
		var ct = colsTemplate.tracks, rt = rowsTemplate.tracks;
		var cols = [for (i in 0...nCols) track(ct, autoCols, i - shift.cols)], rows = [for (i in 0...nRows) track(rt, autoRows, i - shift.rows)];
		return {
			cols: cols,
			rows: rows,
			items: items,
			absolute: absolute,
			colLines: colLines,
			rowLines: rowLines,
			shiftCols: shift.cols,
			shiftRows: shift.rows,
			colMap: collapse(colsTemplate, cols, items, shift.cols, true),
			rowMap: collapse(rowsTemplate, rows, items, shift.rows, false)
		};
	}

	// (a track from the explicit grid's start: the template's, else grid-auto-*'s in turn, after it and
	// back from its start before it)
	static function track(template:Array<Track>, autos:Array<Track>, i:Int):Track {
		if (i >= 0 && i < template.length) return template[i];
		if (autos.length == 0) return Track.AUTO;
		var n = autos.length;
		return i >= 0 ? autos[(i - template.length) % n] : autos[n - 1 - (-i - 1) % n];
	}

	// (each explicit line's names: the template's, and a named area's name-start and name-end, §7.3.2)
	static function names(t:GridTemplate, areas:Null<GridAreas>, count:Int, columns:Bool):Array<Array<String>> {
		var out = [for (i in 0...count + 1) i < t.names.length ? t.names[i].copy() : []];
		if (areas != null) for (name => a in areas.areas) {
			out[columns ? a.col : a.row].push(name + "-start");
			out[columns ? a.colEnd : a.rowEnd].push(name + "-end");
		}
		return out;
	}

	// (auto-fit's empty tracks collapsed, §7.2.3.2: out of the tracks, the items' indices past them less; each
	// line's index among the tracks left, for absolutely positioned children; null: none collapsed)
	static function collapse(t:GridTemplate, tracks:Array<Track>, items:Array<GridItem>, shift:Int, columns:Bool):Null<Array<Int>> {
		if (t.fitFrom < 0) return null;
		var used = [for (_ in 0...tracks.length) false];
		for (it in items) {
			var a = columns ? it.col : it.row;
			for (i in a...a + (columns ? it.colSpan : it.rowSpan)) used[i] = true;
		}
		var from = t.fitFrom + shift, any = false;
		var gone = [for (i in 0...tracks.length) i >= from && i < from + t.fitCount && !used[i]];
		for (g in gone) if (g) any = true;
		if (!any) return null;
		var map = [], k = 0;
		for (i in 0...tracks.length + 1) {
			map.push(k);
			if (i < tracks.length && !gone[i]) k++;
		}
		for (it in items) if (columns) it.col = map[it.col] else it.row = map[it.row];
		var i = tracks.length;
		while (i-- > 0) if (gone[i]) tracks.splice(i, 1);
		return map;
	}

	static function text(st:BoxStyle, p:String):String
		return CssText.join(st.terms(p), CssText.term);

	// (§8.5: the items' cells: those with both lines first, then those locked to a row (a column, flowing by
	// columns), then the rest by the cursor (sparse; dense: back at the start for each); the tracks before
	// the explicit grid's of negative lines)
	static inline var AUTO = -0x40000000;
	static inline var MAX_TRACKS = 65535;
	static inline var LARGE = 64;

	static function place(items:Array<GridItem>, st:BoxStyle, colLines:GridLines, rowLines:GridLines):{cols:Int, rows:Int} {
		var flow = text(st, "grid-auto-flow");
		var byColumn = flow.startsWith("column"), dense = flow.indexOf("dense") >= 0;
		function resolve(lines:GridLines, b:Box, p:String):{start:Int, span:Int} {
			var r = lines.resolve(b.style, p);
			if (r.span > MAX_TRACKS) r.span = MAX_TRACKS;
			if (r.start != AUTO && r.start > MAX_TRACKS - r.span) r.start = MAX_TRACKS - r.span;
			if (r.start != AUTO && r.start < -MAX_TRACKS) r.start = -MAX_TRACKS;
			return r;
		}
		var res = [for (it in items) {
			var c = resolve(colLines, it.box, "grid-column"), r = resolve(rowLines, it.box, "grid-row");
			byColumn ? {major: c, minor: r} : {major: r, minor: c};
		}];
		var shiftMajor = 0, shiftMinor = 0;
		for (r in res) {
			if (r.major.start != AUTO && -r.major.start > shiftMajor) shiftMajor = -r.major.start;
			if (r.minor.start != AUTO && -r.minor.start > shiftMinor) shiftMinor = -r.minor.start;
		}
		for (r in res) {
			if (r.major.start != AUTO) r.major.start += shiftMajor;
			if (r.minor.start != AUTO) r.minor.start += shiftMinor;
		}
		var minorCount = (byColumn ? rowLines.count : colLines.count) + shiftMinor;
		var taken = new Map<Int, Map<Int, Bool>>(), small:Array<Int> = [], large:Array<Int> = [];
		inline function overlaps(r:Array<Int>, major:Int, minor:Int, majorSpan:Int, minorSpan:Int):Bool {
			var i = 0, hit = false;
			while (i < r.length && !hit) {
				hit = major < r[i] + r[i + 2] && r[i] < major + majorSpan && minor < r[i + 1] + r[i + 3] && r[i + 1] < minor + minorSpan;
				i += 4;
			}
			return hit;
		}
		function free(major:Int, minor:Int, majorSpan:Int, minorSpan:Int):Bool {
			if (overlaps(large, major, minor, majorSpan, minorSpan)) return false;
			if (majorSpan * minorSpan > LARGE) return !overlaps(small, major, minor, majorSpan, minorSpan);
			for (a in major...major + majorSpan) {
				var t = taken.get(a);
				if (t != null) for (b in minor...minor + minorSpan) if (t.exists(b)) return false;
			}
			return true;
		}
		function take(it:GridItem, major:Int, minor:Int, majorSpan:Int, minorSpan:Int) {
			var r = majorSpan * minorSpan > LARGE ? large : small;
			r.push(major);
			r.push(minor);
			r.push(majorSpan);
			r.push(minorSpan);
			if (r == small) for (a in major...major + majorSpan) {
				var t = taken.get(a);
				if (t == null) taken.set(a, t = new Map());
				for (b in minor...minor + minorSpan) t.set(b, true);
			}
			if (byColumn) {
				it.col = major;
				it.row = minor;
				it.colSpan = majorSpan;
				it.rowSpan = minorSpan;
			} else {
				it.row = major;
				it.col = minor;
				it.rowSpan = majorSpan;
				it.colSpan = minorSpan;
			}
		}
		for (k in 0...items.length) {
			var minorEnd = res[k].minor.start + res[k].minor.span;
			if (res[k].minor.start >= 0 && minorEnd > minorCount) minorCount = minorEnd;
			if (res[k].minor.start < 0 && res[k].minor.span > minorCount) minorCount = res[k].minor.span;
		}
		var done = [for (_ in items) false];
		for (k in 0...items.length) {
			var a = res[k].major, b = res[k].minor;
			if (a.start >= 0 && b.start >= 0) {
				take(items[k], a.start, b.start, a.span, b.span);
				done[k] = true;
			}
		}
		var cursors = new Map<Int, Int>();
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (a.start < 0) continue;
			var minor = !dense && cursors.exists(a.start) ? cursors.get(a.start) : 0;
			while (!free(a.start, minor, a.span, b.span)) minor++;
			take(items[k], a.start, minor, a.span, b.span);
			cursors.set(a.start, minor + b.span);
			if (minor + b.span > minorCount) minorCount = minor + b.span;
			done[k] = true;
		}
		var curMajor = 0, curMinor = 0;
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (dense) {
				curMajor = 0;
				curMinor = b.start >= 0 ? b.start : 0;
			}
			if (b.start >= 0) {
				if (!dense && b.start < curMinor) curMajor++;
				curMinor = b.start;
				while (!free(curMajor, curMinor, a.span, b.span)) curMajor++;
			} else {
				while (true) {
					if (curMinor + b.span > minorCount) {
						curMajor++;
						curMinor = 0;
					}
					if (free(curMajor, curMinor, a.span, b.span)) break;
					curMinor++;
				}
			}
			take(items[k], curMajor, curMinor, a.span, b.span);
			curMinor += b.span;
		}
		return byColumn ? {cols: shiftMajor, rows: shiftMinor} : {cols: shiftMinor, rows: shiftMajor};
	}

	// (an absolutely positioned child's area on an axis between the grid's lines, from the padding box's
	// start: a line it hasn't, or auto, the padding edge, §9.1)
	static function area(lines:GridLines, st:BoxStyle, p:String, starts:Array<Float>, ends:Array<Float>, shift:Int, map:Null<Array<Int>>,
			full:Float):{from:Float, to:Float} {
		var l = lines.lines(st, p), last = map == null ? starts.length - 1 : map.length - 1;
		// (swapped when backwards first, then one the grid hasn't auto)
		var a = l.from, b = l.to;
		if (a != GridLines.AUTO && b != GridLines.AUTO && b < a) {
			var t = a;
			a = b;
			b = t;
		}
		if (b == a) b = GridLines.AUTO;
		inline function index(k:Int):Int
			return k == GridLines.AUTO || k + shift < 0 || k + shift > last ? -1 : k + shift;
		a = index(a);
		b = index(b);
		if (map != null) {
			if (a >= 0) a = map[a];
			if (b >= 0) b = map[b];
		}
		var from = a >= 0 ? starts[a] : 0.0, to = b >= 0 ? ends[b] : full;
		return {from: from, to: Math.max(from, to)};
	}

	static function lines(pos:Array<Float>, sizes:Array<Float>, edge:Float, starts:Bool):Array<Float> {
		var n = sizes.length;
		return [for (k in 0...n + 1) edge + (starts && k < n || k == 0 ? (n > 0 ? pos[k] : 0) : pos[k - 1] + sizes[k - 1])];
	}

	// ---- track sizing (§11.3 to §11.8), helder.ui's GridLayout.tracks over boxes

	static inline var FIXED = 0;
	static inline var AUTO_TRACK = 1;
	static inline var MIN_CONTENT = 2;
	static inline var MAX_CONTENT = 3;
	static inline var FLEX = 4;

	// one axis's tracks: room the content box's size on it (NaN: indefinite, a max-content constraint;
	// minContent: a min-content one), pct what percentages are of, stretch: auto tracks take what is left;
	// least and most the content box's min and max (an indefinite room's fr within them); rows measured at the
	// columns' sizes (their areaW), on their baseline shims
	function tracks(defs:Array<Track>, items:Array<GridItem>, columns:Bool, room:Float, pct:Float, gap:Float, stretch:Bool, space:Space,
			cols:Null<Array<Float>>, minContent = false, least = 0.0, most = Math.POSITIVE_INFINITY):Array<Float> {
		var n = defs.length, inf = Math.POSITIVE_INFINITY;
		var definite = !Math.isNaN(room), maxContent = !definite && !minContent;
		var minK = [for (_ in 0...n) 0], maxK = [for (_ in 0...n) 0], fr = [for (_ in 0...n) 0.0];
		var base = [for (_ in 0...n) 0.0], limit = [for (_ in 0...n) 0.0];
		// (fit-content()'s argument: the most its growth limit goes to)
		var fit = [for (_ in 0...n) inf];
		var settled = true;
		for (i in 0...n) {
			var d = defs[i];
			var f = Std.downcast(d, FitTrack);
			if (f != null) fit[i] = switch f.limit {
				case Px(v): v;
				case Percent(p) if (!Math.isNaN(pct)): pct * p / 100;
				case _: inf;
			}
			var mn = 0.0, mx = inf;
			minK[i] = switch d.min {
				case Px(v):
					mn = v;
					FIXED;
				case Percent(p) if (!Math.isNaN(pct)):
					mn = pct * p / 100;
					FIXED;
				case MinContent: MIN_CONTENT;
				case MaxContent: MAX_CONTENT;
				case _: AUTO_TRACK;
			}
			maxK[i] = switch d.max {
				case Px(v):
					mx = v;
					FIXED;
				case Percent(p) if (!Math.isNaN(pct)):
					mx = pct * p / 100;
					FIXED;
				case Fr(f):
					fr[i] = f;
					FLEX;
				case MinContent: MIN_CONTENT;
				case MaxContent: MAX_CONTENT;
				case _: AUTO_TRACK;
			}
			base[i] = mn;
			limit[i] = mx < mn ? mn : mx;
			if (minK[i] != FIXED || maxK[i] != FIXED) settled = false;
		}
		var exact = settled;
		for (i in 0...n) if (base[i] != limit[i]) exact = false;
		if (exact) return base;
		inline function gaps(a:Int, b:Int):Float
			return b - a > 1 ? gap * (b - a - 1) : 0;
		inline function startOf(it:GridItem):Int
			return columns ? it.col : it.row;
		inline function spanOf(it:GridItem):Int
			return columns ? it.colSpan : it.rowSpan;
		// (the items' contributions: min-content, max-content, minimum)
		var count = items.length;
		var mins = [for (_ in 0...count) 0.0], maxes = [for (_ in 0...count) 0.0], minimums = [for (_ in 0...count) 0.0], flexed = [for (_ in 0...count) false];
		var order = [];
		for (k in 0...count) {
			var it = items[k], a = startOf(it), b = a + spanOf(it);
			var sized = false, crossesFlex = false, spansAutoMin = false, allFixedMax = true, fixedMax = gaps(a, b);
			for (i in a...b) {
				if (minK[i] != FIXED || maxK[i] != FIXED) sized = true;
				if (maxK[i] == FLEX) crossesFlex = true;
				if (minK[i] == AUTO_TRACK) spansAutoMin = true;
				if (maxK[i] == FIXED) fixedMax += limit[i] else allFixedMax = false;
			}
			flexed[k] = crossesFlex;
			if (!sized || settled) continue;
			order.push(k);
			var c = it.box, m = c.style.model();
			var edges = columns ? BlockFlow.fixed(m.margin[1]) + BlockFlow.fixed(m.margin[3]) : BlockFlow.fixed(m.margin[0]) + BlockFlow.fixed(m.margin[2]) + it.shim;
			var pb = columns ? m.border[1] + m.border[3] + BlockFlow.fixed(m.padding[1]) + BlockFlow.fixed(m.padding[3]) : m.border[0] + m.border[2]
				+ BlockFlow.fixed(m.padding[0]) + BlockFlow.fixed(m.padding[2]);
			if (columns) {
				intrinsicOf(c, space);
				mins[k] = c.minContent + edges;
				maxes[k] = c.maxContent + edges;
			} else {
				mins[k] = maxes[k] = space.fragments.height(laidAt(it, space)) + edges;
			}
			// (its minimum contribution, §6.6: its min-content one with a size of its own; its min size; none for
			// a scroll container; its automatic minimum, its min-content size when it spans an auto-minimum track,
			// no more than the fixed maximums it spans only)
			var area = 0.0;
			for (i in a...b) if (minK[i] == FIXED && maxK[i] == FIXED && base[i] == limit[i]) area += base[i] else area = Math.NaN;
			if (!Math.isNaN(area)) area += gaps(a, b);
			var preferred = columns ? m.width : m.height;
			var own = Lens.resolve(preferred, area, Math.NaN);
			var given = Lens.resolve(columns ? m.minWidth : m.minHeight, Math.isNaN(area) ? 0 : area, Math.NaN);
			minimums[k] = if (!Math.isNaN(own)) mins[k] else if (!Math.isNaN(given)) Math.max(given + (m.borderBox ? 0 : pb), pb) + edges else if (c.style.clips) pb
				+ edges else if (spansAutoMin && (b - a == 1 || !crossesFlex)) {
				var v = mins[k] - edges;
				if (allFixedMax) v = Math.min(v, Math.max(fixedMax - edges, pb));
				v + edges;
			} else pb + edges;
		}
		var planBase = [for (_ in 0...n) 0.0], planLimit = [for (_ in 0...n) 0.0], inc = [for (_ in 0...n) 0.0], growable = [for (_ in 0...n) false];
		inline function size(i:Int, ofLimit:Bool):Float
			return ofLimit && limit[i] != inf ? limit[i] : base[i];
		function upTo(space:Float, a:Int, b:Int, affected:Int->Bool, weight:Int->Float, ofLimit:Bool, lim:Int->Float):Float {
			for (_ in 0...b - a + 1) {
				if (space <= 0.01) break;
				var sum = 0.0, first = inf;
				for (i in a...b) if (affected(i) && size(i, ofLimit) + inc[i] < lim(i)) {
					var w = weight(i);
					sum += w;
					var r = (lim(i) - size(i, ofLimit) - inc[i]) / w;
					if (r < first) first = r;
				}
				if (sum == 0) break;
				var step = Math.min(first, space / sum);
				for (i in a...b) if (affected(i)) {
					var d = step * weight(i);
					if (d > 0 && size(i, ofLimit) + inc[i] + d <= lim(i) + 0.01) {
						inc[i] += d;
						space -= d;
					}
				}
			}
			return space;
		}
		function one(_:Int):Float
			return 1;
		function flexWeight(i:Int):Float
			return fr[i];
		function unlimited(_:Int):Float
			return inf;
		function growthLimit(i:Int):Float
			return limit[i];
		function fitted(i:Int):Float
			return fit[i];
		function toBase(space:Float, a:Int, b:Int, flex:Bool, affected:Int->Bool, lim:Int->Float, ofMax:Bool) {
			if (space == 0) return;
			var aff = flex ? i -> maxK[i] == FLEX && affected(i) : affected;
			var any = false, weights = 0.0;
			for (i in a...b) if (aff(i)) {
				any = true;
				weights += fr[i];
			}
			if (!any) return;
			var weight = flex && weights > 0 ? flexWeight : one;
			var have = gaps(a, b);
			for (i in a...b) have += base[i];
			var extra = upTo(Math.max(0, space - have), a, b, aff, weight, false, lim);
			if (extra > 0.000001) {
				var past = ofMax ? i -> maxK[i] == MAX_CONTENT : i -> maxK[i] == AUTO_TRACK || maxK[i] == MIN_CONTENT || maxK[i] == MAX_CONTENT;
				var some = false;
				for (i in a...b) if (aff(i) && past(i)) some = true;
				upTo(extra, a, b, some ? i -> aff(i) && past(i) : aff, weight, false, unlimited);
			}
			for (i in a...b) {
				if (inc[i] > planBase[i]) planBase[i] = inc[i];
				inc[i] = 0;
			}
		}
		function toLimit(space:Float, a:Int, b:Int, affected:Int->Bool) {
			if (space == 0) return;
			var any = false;
			for (i in a...b) if (affected(i)) any = true;
			if (!any) return;
			var have = gaps(a, b);
			for (i in a...b) have += size(i, true);
			var extra = upTo(Math.max(0, space - have), a, b, i -> affected(i) && (growable[i] || limit[i] == inf), one, true, fitted);
			if (extra > 0) upTo(extra, a, b, affected, one, true, fitted);
			for (i in a...b) {
				if (inc[i] > planLimit[i]) planLimit[i] = inc[i];
				inc[i] = 0;
			}
		}
		function flushBase() {
			for (i in 0...n) {
				base[i] += planBase[i];
				planBase[i] = 0;
			}
		}
		function flushLimit(mark:Bool) {
			for (i in 0...n) {
				if (planLimit[i] > 0) {
					limit[i] = limit[i] == inf ? base[i] + planLimit[i] : limit[i] + planLimit[i];
					growable[i] = mark;
				} else growable[i] = false;
				planLimit[i] = 0;
			}
		}
		function spans(k:Int, f:Int->Bool):Bool {
			var a = startOf(items[k]);
			for (i in a...a + spanOf(items[k])) if (f(i)) return true;
			return false;
		}
		function cap(k:Int, v:Float):Float {
			var it = items[k], a = startOf(it), b = a + spanOf(it), most = gaps(a, b);
			for (i in a...b) if (maxK[i] == FIXED) most += limit[i] else if (fit[i] < inf) most += fit[i] else if (maxK[i] == MIN_CONTENT && limit[i] < inf) most += limit[i] else return v;
			return Math.min(v, most);
		}
		function scale(k:Int, v:Float):Float {
			var it = items[k], a = startOf(it), b = a + spanOf(it), inflexible = gaps(a, b), factors = 0.0;
			for (i in a...b) if (maxK[i] == FLEX) factors += fr[i] else inflexible += base[i];
			return inflexible + Math.max(v - inflexible, 0) * Math.min(factors, 1);
		}
		inline function scroller(k:Int):Bool
			return items[k].box.style.clips;
		// (§11.5: the items by span, those crossing a flexible track last, all at once)
		var batches = [];
		order.sort((x, y) -> flexed[x] != flexed[y] ? (flexed[x] ? 1 : -1) : flexed[x] ? x - y : spanOf(items[x]) != spanOf(items[y]) ? spanOf(items[x])
			- spanOf(items[y]) : x - y);
		var at = 0;
		while (at < order.length) {
			var first = order[at], end = at + 1;
			while (end < order.length && (flexed[first] || !flexed[order[end]] && spanOf(items[order[end]]) == spanOf(items[first]))) end++;
			batches.push(order.slice(at, end));
			at = end;
		}
		for (batch in batches) {
			var flex = flexed[batch[0]];
			if (!flex && spanOf(items[batch[0]]) == 1) {
				for (k in batch) {
					var i = startOf(items[k]);
					switch minK[i] {
						case MIN_CONTENT: base[i] = Math.max(base[i], mins[k]);
						case MAX_CONTENT: base[i] = Math.max(base[i], maxes[k]);
						case AUTO_TRACK: base[i] = Math.max(base[i], !definite && !scroller(k) ? Math.max(minimums[k], cap(k, mins[k])) : minimums[k]);
						case _:
					}
					var want = switch maxK[i] {
						case AUTO_TRACK | MAX_CONTENT: Math.min(maxes[k], fit[i]);
						case MIN_CONTENT: mins[k];
						case _: -1.0;
					}
					if (want >= 0) {
						if (!growable[i] || want > planLimit[i]) planLimit[i] = want;
						growable[i] = true;
					}
				}
				for (i in 0...n) {
					if (growable[i]) limit[i] = limit[i] == inf ? planLimit[i] : Math.max(limit[i], planLimit[i]);
					growable[i] = false;
					planLimit[i] = 0;
					if (limit[i] < base[i]) limit[i] = base[i];
				}
				continue;
			}
			for (k in batch) {
				var it = items[k], a = startOf(it), b = a + spanOf(it);
				var space = minimums[k];
				if (!definite && !scroller(k)) {
					var floor = Math.max(minimums[k], cap(k, mins[k]));
					space = flex ? Math.max(minimums[k], scale(k, floor)) : floor;
				}
				if (space > 0) toBase(space, a, b, flex, i -> minK[i] != FIXED, growthLimit, false);
			}
			flushBase();
			var contentMin = i -> minK[i] == MIN_CONTENT || minK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, contentMin)) continue;
				var a = startOf(items[k]);
				if (mins[k] > 0) toBase(mins[k], a, a + spanOf(items[k]), flex, contentMin, growthLimit, false);
			}
			flushBase();
			if (maxContent) {
				var autoMin = i -> minK[i] == AUTO_TRACK && maxK[i] != MIN_CONTENT, maxMin = i -> minK[i] == MAX_CONTENT;
				for (k in batch) {
					if (!spans(k, i -> autoMin(i) || maxMin(i))) continue;
					var a = startOf(items[k]), b = a + spanOf(items[k]);
					var space = flex ? scale(k, cap(k, maxes[k])) : cap(k, maxes[k]);
					if (space > 0) {
						if (spans(k, maxMin)) toBase(space, a, b, flex, maxMin, unlimited, true) else toBase(space, a, b, flex, autoMin, growthLimit, true);
					}
				}
				flushBase();
			}
			var maxMin = i -> minK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, maxMin)) continue;
				var a = startOf(items[k]);
				if (maxes[k] > 0) toBase(maxes[k], a, a + spanOf(items[k]), flex, maxMin, growthLimit, true);
			}
			flushBase();
			for (i in 0...n) if (limit[i] < base[i]) limit[i] = base[i];
			if (flex) continue;
			var intrinsicMax = i -> maxK[i] != FIXED;
			for (k in batch) {
				if (!spans(k, intrinsicMax)) continue;
				var a = startOf(items[k]);
				if (mins[k] > 0) toLimit(mins[k], a, a + spanOf(items[k]), intrinsicMax);
			}
			flushLimit(true);
			var maxMax = i -> maxK[i] == AUTO_TRACK || maxK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, maxMax)) continue;
				var a = startOf(items[k]);
				if (maxes[k] > 0) toLimit(maxes[k], a, a + spanOf(items[k]), maxMax);
			}
			flushLimit(false);
		}
		for (i in 0...n) if (limit[i] == inf) limit[i] = base[i];
		// (§11.6: the free space to the base sizes, up to the growth limits)
		if (maxContent) {
			for (i in 0...n) base[i] = limit[i];
		} else if (definite) {
			var free = room - gaps(0, n);
			for (i in 0...n) free -= base[i];
			if (free > 0) {
				upTo(free, 0, n, i -> true, one, false, growthLimit);
				for (i in 0...n) {
					base[i] += inc[i];
					inc[i] = 0;
				}
			}
		}
		// (§11.7: the flexible tracks at the size of an fr)
		function frSize(a:Int, b:Int, space:Float):Float {
			if (space == 0) return 0;
			var hyp = inf, was = inf;
			for (_ in 0...b - a + 1) {
				var used = gaps(a, b), factors = 0.0;
				for (i in a...b) if (maxK[i] == FLEX && fr[i] * hyp >= base[i]) factors += fr[i] else used += base[i];
				was = hyp;
				hyp = (space - used) / Math.max(factors, 1);
				var valid = true;
				for (i in a...b) if (maxK[i] == FLEX && !(fr[i] * hyp >= base[i] || fr[i] * was < base[i])) valid = false;
				if (valid) break;
			}
			return hyp;
		}
		var anyFlex = false;
		for (i in 0...n) if (maxK[i] == FLEX) anyFlex = true;
		if (anyFlex) {
			var fraction = 0.0;
			if (definite) {
				var used = gaps(0, n);
				for (i in 0...n) used += base[i];
				fraction = room - used <= 0 ? 0 : frSize(0, n, room);
			} else if (!(minContent && columns)) {
				for (i in 0...n) if (maxK[i] == FLEX) fraction = Math.max(fraction, fr[i] > 1 ? base[i] / fr[i] : base[i]);
				for (k in order) if (flexed[k]) {
					var a = startOf(items[k]);
					fraction = Math.max(fraction, frSize(a, a + spanOf(items[k]), maxes[k]));
				}
				var total = gaps(0, n);
				for (i in 0...n) total += maxK[i] == FLEX ? Math.max(base[i], fr[i] * fraction) : base[i];
				if (total < least) fraction = frSize(0, n, least) else if (total > most) fraction = frSize(0, n, most);
			}
			for (i in 0...n) if (maxK[i] == FLEX) base[i] = Math.max(base[i], fr[i] * fraction);
		}
		// (§11.8: auto tracks stretched over what is left)
		if (stretch && definite) {
			var free = room - gaps(0, n), autos = 0;
			for (i in 0...n) {
				free -= base[i];
				if (defs[i].max.match(Auto)) autos++;
			}
			if (free > 0 && autos > 0) for (i in 0...n) if (defs[i].max.match(Auto)) base[i] += free / autos;
		}
		return base;
	}

	// (an item laid out at its width in its area: its own, else stretched, else its fit-content width)
	function laidAt(it:GridItem, space:Space):Int {
		var c = it.box, m = c.style.model();
		var room = Math.max(0, it.areaW - BlockFlow.fixed(m.margin[1]) - BlockFlow.fixed(m.margin[3]));
		var cs = space.child(it.areaW, Math.NaN);
		cs.fragmentation = null;
		var bpx = m.border[1] + m.border[3] + BlockFlow.res(m.padding[1], it.areaW) + BlockFlow.res(m.padding[3], it.areaW);
		var sw = BlockFlow.size(m.width, it.areaW, m.borderBox, bpx);
		var jx = selfOf(c, "justify-self", "justify-items");
		if (!Math.isNaN(sw)) cs.fixedWidth = sw + bpx else if (jx == "stretch") cs.fixedWidth = room else {
			intrinsicOf(c, space);
			cs.fixedWidth = Math.min(c.maxContent, Math.max(room, c.minContent));
		}
		c.cacheFragment = -1;
		return flow.child(c, cs);
	}

	inline function intrinsicOf(c:Box, space:Space)
		if (c.context != null) c.context.intrinsic(c, space) else flow.intrinsic(c, space);

	// (on its row's baseline: align-self baseline, no auto margin above or below)
	static function onBaseline(it:GridItem):Bool {
		var m = it.box.style.model();
		return selfOf(it.box, "align-self", "align-items") == "baseline" && !Lens.isAuto(m.margin[0]) && !Lens.isAuto(m.margin[2]);
	}

	// (§11.5's baseline shims: the items on their baselines starting in the same row, the room above each
	// that brings its first baseline to the deepest one's)
	function shims(items:Array<GridItem>, st:BoxStyle, space:Space) {
		var rows = new Map<Int, Array<GridItem>>();
		for (it in items) {
			it.shim = 0;
			if (onBaseline(it)) {
				if (!rows.exists(it.row)) rows.set(it.row, []);
				rows.get(it.row).push(it);
			}
		}
		for (group in rows) {
			if (group.length < 2) continue;
			var deepest = Math.NEGATIVE_INFINITY;
			for (it in group) {
				var f = laidAt(it, space);
				var h = space.fragments.height(f), b = space.fragments.baseline(f);
				it.shim = BlockFlow.fixed(it.box.style.model().margin[0]) + (Math.isNaN(b) ? h : b);
				if (it.shim > deepest) deepest = it.shim;
			}
			for (it in group) it.shim = deepest - it.shim;
		}
	}

	// (each track's start: packed, or placed as justify-content or align-content puts them; too little
	// room: overflowing at the start too when centred or at the end)
	static function positions(sizes:Array<Float>, gap:Float, room:Float, how:String):Array<Float> {
		var n = sizes.length, free = room - sum(sizes, gap), pos = 0.0, g = gap;
		if (how.startsWith("safe ") || how.startsWith("unsafe ")) how = how.substr(how.indexOf(" ") + 1);
		if (n > 0 && free < 0) switch how {
			case "end" | "flex-end": pos = free;
			case "center": pos = free / 2;
			case _:
		} else if (n > 0 && free > 0) switch how {
			case "end" | "flex-end": pos = free;
			case "center": pos = free / 2;
			case "space-between" if (n > 1): g += free / (n - 1);
			case "space-around":
				g += free / n;
				pos = free / n / 2;
			case "space-evenly":
				g += free / (n + 1);
				pos = free / (n + 1);
			case _:
		}
		var out = [];
		for (v in sizes) {
			out.push(pos);
			pos += v + g;
		}
		return out;
	}

	static function sum(sizes:Array<Float>, gap:Float):Float {
		var t = 0.0;
		for (v in sizes) t += v;
		return t + (sizes.length > 1 ? gap * (sizes.length - 1) : 0);
	}

	// (justify-self or align-self, auto its container's -items; normal stretch; flow-start and -end, self-start and
	// -end are start and end in a grid)
	static function selfOf(b:Box, self:String, items:String):String {
		var v = keyword(b.style, self);
		if (v == "auto" || v == "normal" || v == "" || v == "legacy") v = keyword(b.parent.style, items);
		if (v.startsWith("safe ") || v.startsWith("unsafe ")) v = v.substr(v.indexOf(" ") + 1);
		if (v.startsWith("legacy ")) v = v.substr(7);
		return switch v {
			case "normal" | "" | "legacy": "stretch";
			case "flow-start" | "self-start" | "left" | "start": "start";
			case "flow-end" | "self-end" | "right" | "end": "end";
			case "first baseline": "baseline";
			case k: k;
		}
	}

	// (align-self normal, its own or its container's align-items')
	static function normal(b:Box):Bool {
		var v = keyword(b.style, "align-self");
		if (v == "auto" || v == "normal" || v == "") v = keyword(b.parent.style, "align-items");
		return v == "normal" || v == "" || v == "legacy";
	}

	static function keyword(s:BoxStyle, p:String):String {
		var k = s.keyword(p);
		return k == "" ? CssText.join(s.terms(p), CssText.term) : k;
	}

	static function gap(s:BoxStyle, p:String, base:Float):Float {
		if (s.keyword(p) == "normal") return 0;
		return nanTo(Lens.resolve(s.len(p), base, 0), 0);
	}

	// ---- intrinsic sizes: the columns sized under a min-content and a max-content constraint

	public function intrinsic(box:Box, space:Space) {
		if (!Math.isNaN(box.minContent)) return;
		var s = box.style.model();
		var bpx = BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]) + s.border[1] + s.border[3];
		var min = 0.0, max = 0.0;
		var w = BlockFlow.size(s.width, Math.NaN, s.borderBox, bpx);
		var bpy = BlockFlow.fixed(s.padding[0]) + BlockFlow.fixed(s.padding[2]) + s.border[0] + s.border[2];
		if (Math.isNaN(w)) w = Ratio.width(box, BlockFlow.size(s.height, Math.NaN, s.borderBox, bpy), bpx, bpy);
		if (!Math.isNaN(w)) min = max = w else {
			var g = grid(box, space, Math.NaN, Math.NaN);
			var colGap = gap(box.style, "column-gap", Math.NaN);
			min = sum(tracks(g.cols, g.items, true, Math.NaN, Math.NaN, colGap, false, space, null, true), colGap);
			max = sum(tracks(g.cols, g.items, true, Math.NaN, Math.NaN, colGap, false, space, null), colGap);
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

	static inline function clamp(v:Float, lo:Float, hi:Float):Float
		return v > hi ? (hi < lo ? lo : hi) : v < lo ? lo : v;

	static inline function nanTo(v:Float, d:Float):Float
		return Math.isNaN(v) ? d : v;
}

private class GridItem {
	public final box:Box;
	public var col = 0;
	public var row = 0;
	public var colSpan = 1;
	public var rowSpan = 1;
	// (its area's width, the columns' sizes and gaps between)
	public var areaW = 0.0;
	// (on its row's baseline: the room above it that puts it there)
	public var shim = 0.0;
	// (its border box's top in the content box, once placed, and its place there, relative offsets in)
	public var y = 0.0;
	public var x = 0.0;
	public var top = 0.0;
	public var frag = -1;

	public function new(box:Box)
		this.box = box;
}

private typedef Grid = {
	cols:Array<Track>,
	rows:Array<Track>,
	items:Array<GridItem>,
	absolute:Array<Box>,
	colLines:GridLines,
	rowLines:GridLines,
	shiftCols:Int,
	shiftRows:Int,
	colMap:Null<Array<Int>>,
	rowMap:Null<Array<Int>>
}
