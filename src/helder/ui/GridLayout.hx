package helder.ui;

// Layout's CSS grid, for a Display Grid container (Layout.size calls grid):
// CSS Grid Layout (level 1, a subset): the explicit grid's tracks, implicit
// ones added as items need (gridAutoRows, gridAutoColumns), the items
// placed by their lines or auto-placed (sparse, by rows or columns); the
// tracks sized columns first, then rows at the columns' widths, by CSS
// Grid's track sizing algorithm (11.3 to 11.8, as Chromium has it: the
// intrinsic tracks from the items' minimum, min- and max-content
// contributions, spanning items by span, those crossing flexible tracks
// last; the free space up to the growth limits; fr tracks at the size of
// an fr; auto tracks stretched when justify and alignContent are their
// defaults, CSS's normal); each item in its area by justifySelf (or the
// container's justifyItems) and alignSelf (or alignItems; Baseline: on
// its row's shared baseline). Named areas (gridTemplateAreas, items
// placed by their names), no other named lines, no subgrid.
@:allow(helder.ui.Layout)
@:access(helder.ui.Layout)
@:access(helder.ui.Node)
class GridLayout {
	// (the line numbers' limit, the tracks an axis has at most, an area of more cells than LARGE kept as a rectangle)
	static inline var LINES = 32767;
	static inline var MAX_TRACKS = 65535;
	static inline var LARGE = 64;
	// (a placement's line auto, its start not given)
	static inline var AUTO = -0x40000000;

	static function grid(l:Layout, n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool, least:Float, defH:Bool) {
		var s = n.style, rtl = n.rtl();
		var innerW = Layout.known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = Layout.known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = Layout.known(innerW) ? innerW : Layout.known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = Layout.known(innerH) ? innerH : Layout.known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var items:Array<GridItem> = [], absolute:Array<Node> = [];
		for (c in n.inOrder()) {
			var cs = c.style;
			if (cs.display == None) {
				if (perform) Layout.hide(c);
				continue;
			}
			if (cs.position == Absolute) {
				absolute.push(c);
				continue;
			}
			items.push(new GridItem(c));
		}
		var colsTemplate = s.gridTemplateColumns, rowsTemplate = s.gridTemplateRows;
		// (shift: the implicit tracks before the explicit grid's, of negative lines past its start)
		var shift = place(items, s);
		var nCols = gridColumnCount(s) + shift.cols, nRows = gridRowCount(s) + shift.rows;
		for (it in items) {
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
			if (it.row + it.rowSpan > nRows) nRows = it.row + it.rowSpan;
		}
		var colTracks = [for (i in 0...nCols) i >= shift.cols && i - shift.cols < colsTemplate.length ? colsTemplate[i - shift.cols] : s.gridAutoColumns];
		var rowTracks = [for (i in 0...nRows) i >= shift.rows && i - shift.rows < rowsTemplate.length ? rowsTemplate[i - shift.rows] : s.gridAutoRows];
		var colGap = s.columnGap, rowGap = s.rowGap;

		// the columns: at the content box's width, else at their max-content sizes (then the available width, when that is less)
		var stretchCols = s.justify == Normal, stretchRows = s.alignContent == Normal || s.alignContent == Stretch;
		// (an item with an aspect ratio and neither size its own: the columns sized again, its contribution its rows'
		// height through the ratio, then the rows again, as CSS's grid sizing has it; its height its first rows', as
		// Chromium's)
		var again = false;
		for (it in items) {
			var cs = it.node.style;
			if (cs.aspectRatio > 0 && !Layout.known(cs.width.resolve(Math.NaN)) && !Layout.known(cs.height.resolve(Math.NaN))) again = true;
		}
		var cols:Array<Float> = null, rows:Array<Float> = null, gridW = 0.0, width = 0.0, gridH = 0.0;
		for (pass in 0...2) {
			// (its percentages auto while its width is its content's, as Chromium sizes it)
			cols = tracks(l, colTracks, items, true, innerW, innerW, colGap, stretchCols, innerW, innerH, null);
			gridW = sum(cols, colGap);
			if (!Layout.known(innerW) && Layout.known(availInW) && gridW > availInW + 1e-6) {
				cols = tracks(l, colTracks, items, true, availInW, innerW, colGap, false, innerW, innerH, null);
				gridW = sum(cols, colGap);
			}
			width = Layout.known(innerW) ? innerW : Layout.clamp(gridW, Math.max(0, minW - padH), maxW - padH);
			if (!Layout.known(innerW) && width > gridW + 1e-6 && stretchCols) {
				cols = tracks(l, colTracks, items, true, width, innerW, colGap, true, width, innerH, null);
				gridW = sum(cols, colGap);
			}
			if (pass == 1 && !perform) break;
			// the rows: the items at their columns' widths
			for (it in items) {
				it.areaW = colGap * (it.colSpan - 1);
				for (i in it.col...it.col + it.colSpan)
					it.areaW += cols[i];
			}
			shims(l, items, s);
			// (a height laid out, not definite (an auto one within its min- or max-height): the rows sized in an
			// indefinite room, their percentages of it; stretched to it when it is more (a min-height's), not shrunk
			// to it when less (a max-height's: the grid overflowing it), as Chromium has it)
			rows = tracks(l, rowTracks, items, false, defH ? innerH : Math.NaN, innerH, rowGap, stretchRows && defH, width, innerH, cols);
			if (!defH && stretchRows && Layout.known(innerH) && innerH > sum(rows, rowGap) + 1e-6)
				rows = tracks(l, rowTracks, items, false, innerH, innerH, rowGap, true, width, innerH, cols);
			if (pass == 0) gridH = sum(rows, rowGap);
			if (!again || pass == 1) break;
			for (it in items) {
				it.areaH = rowGap * (it.rowSpan - 1);
				for (i in it.row...it.row + it.rowSpan)
					it.areaH += rows[i];
			}
		}
		var height = Layout.known(innerH) ? innerH : Layout.clamp(gridH, Math.max(0, (rows.length > 0 ? Math.max(minH, least) : minH) - padV), maxH - padV);
		var bw = width + padH, bh = height + padV;
		if (!perform) {
			l.rw = bw;
			l.rh = bh;
			return;
		}

		// the tracks' places (justify and alignContent: the tracks in the content box)
		var colPos = positions(cols, colGap, width, s.justify);
		var rowPos = positions(rows, rowGap, height, switch s.alignContent {
			case End: Justify.End;
			case Center: Justify.Center;
			case SpaceBetween: Justify.SpaceBetween;
			case SpaceAround: Justify.SpaceAround;
			case SpaceEvenly: Justify.SpaceEvenly;
			case _: Justify.Start;
		});
		var cw = 0.0, ch = 0.0, left = 0.0;
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			var ax = colPos[it.col], aw = colPos[it.col + it.colSpan - 1] + cols[it.col + it.colSpan - 1] - ax;
			var ay = rowPos[it.row], ah = rowPos[it.row + it.rowSpan - 1] + rows[it.row + it.rowSpan - 1] - ay;
			var jx = cs.justifySelf == Auto ? s.justifyItems : cs.justifySelf;
			if (jx == Auto) jx = Stretch;
			var jy = cs.alignSelf == Auto ? s.alignItems : cs.alignSelf;
			if (jy == Auto) jy = Stretch;
			// (auto margins: not stretched on that axis; placed by them once sized)
			var autoS = Math.isNaN(rtl ? m.right : m.left), autoE = Math.isNaN(rtl ? m.left : m.right), autoT = Math.isNaN(m.top), autoB = Math.isNaN(m.bottom);
			if ((autoS || autoE) && jx == Stretch) jx = Start;
			if ((autoT || autoB) && jy == Stretch) jy = Start;
			// (its percentages of its grid area, as CSS's)
			var roomW = Math.max(0, aw - Layout.mz(m.left) - Layout.mz(m.right)), roomH = Math.max(0, ah - Layout.mz(m.top) - Layout.mz(m.bottom));
			var minCW = Math.max(l.minWidthOf(c, cs.minWidth, aw, roomW), Layout.edgesH(cs)), maxCW = l.maxWidthOf(c, cs.maxWidth, aw, roomW);
			var minCH = Math.max(Layout.min(cs.minHeight, ah), Layout.edgesV(cs)), maxCH = Layout.max(cs.maxHeight, ah);
			var iw = Layout.clamp(cs.width.intrinsic() ? l.intrinsicWidth(c, cs.width, aw, roomW) : cs.width.resolve(aw), minCW, maxCW);
			var ih = Layout.clamp(cs.height.resolve(ah), minCH, maxCH);
			// (an aspect ratio and one size its own: the other its through the ratio, not stretched)
			var ar = cs.aspectRatio;
			if (ar > 0 && Layout.known(iw) && !Layout.known(ih) && jy == Stretch) jy = Start;
			if (ar > 0 && Layout.known(ih) && !Layout.known(iw) && jx == Stretch) jx = Start;
			// (an aspect ratio and neither size its own: not stretched but at its start, as wide as the
			// area within its widths and the heights it may have through the ratio, as Chromium has it)
			if (ar > 0 && !Layout.known(iw) && !Layout.known(ih) && jx == Stretch && jy == Stretch) {
				iw = Layout.clamp(Math.min(roomW, maxCH * ar), Math.max(minCW, minCH * ar), maxCW);
				ih = Layout.clamp(iw / ar, minCH, maxCH);
				jx = jy = Start;
			}
			if (!Layout.known(iw)) {
				if (jx == Stretch) iw = Layout.clamp(roomW, minCW, maxCW) else {
					// (fit-content: its max-content width, no more than the area)
					l.size(c, Math.NaN, ih, aw, ah, roomW, Layout.known(ih) ? ih : roomH, false);
					iw = Layout.clamp(Math.min(l.rw, Math.max(roomW, l.minContentWidth(c, aw, false))), minCW, maxCW);
					// (its height's through its aspect ratio however wide)
					if (l.rw <= roomW || ar > 0 && Layout.known(ih)) iw = Layout.clamp(l.rw, minCW, maxCW);
				}
			}
			if (!Layout.known(ih)) {
				if (jy == Stretch) ih = Layout.clamp(roomH, minCH, maxCH) else {
					l.size(c, iw, Math.NaN, aw, ah, iw, roomH, false);
					ih = Layout.clamp(l.rh, minCH, maxCH);
				}
			}
			// (the room left shared among its auto margins, none when it overflows)
			if (autoS || autoE) jx = roomW - iw <= 0 ? Start : autoS && autoE ? Center : autoS ? End : Start;
			if (autoT || autoB) jy = roomH - ih <= 0 ? Start : autoT && autoB ? Center : autoT ? End : Start;
			// (right to left: the columns from the right, each item's margins on its own sides)
			var x = ax + (rtl ? Layout.mz(m.right) : Layout.mz(m.left)) + switch jx {
				case End: roomW - iw;
				case Center: (roomW - iw) / 2;
				case _: 0;
			}
			if (rtl) x = width - x - iw;
			var y = ay + Layout.mz(m.top) + switch jy {
				case End: roomH - ih;
				case Center: (roomH - ih) / 2;
				case Baseline: it.shim;
				case _: 0;
			}
			var dx = Layout.relativeX(cs, aw, rtl), dy = cs.top.resolve(ah);
			if (!Layout.known(dy)) dy = -cs.bottom.resolve(ah);
			if (cs.position == Sticky) dx = dy = Math.NaN;
			c.lx = padL + x + (Layout.known(dx) ? dx : 0);
			c.ly = padT + y + (Layout.known(dy) ? dy : 0);
			// (its height definite for its children when stretched or its own, not its content's)
			l.looseH = !(jy == Stretch || Layout.known(cs.height.resolve(ah)));
			l.size(c, iw, ih, aw, ah, iw, ih, true);
			c.lw = iw;
			c.lh = ih;
			it.y = y;
			if (x + iw + Layout.mz(m.right) > cw) cw = x + iw + Layout.mz(m.right);
			if (y + ih + Layout.mz(m.bottom) > ch) ch = y + ih + Layout.mz(m.bottom);
			if (x - Layout.mz(m.left) < left) left = x - Layout.mz(m.left);
		}
		// (right to left: what overflows on the left, the columns' too)
		if (rtl) cw = width - Math.min(left, width - gridW);
		// (its first baseline: the first item's in its first row, one on its baseline there first; that item's
		// bottom edge when it has none; not moved by its relative offset)
		n.lb = Math.NaN;
		if (items.length > 0) {
			var firstRow = items[0].row;
			for (it in items)
				if (it.row < firstRow) firstRow = it.row;
			var pick:GridItem = null;
			for (it in items)
				if (it.row == firstRow && (pick == null || !onBaseline(pick, s) && onBaseline(it, s))) pick = it;
			var b = pick.node.firstBaseline();
			n.lb = padT + pick.y + (Math.isNaN(b) ? pick.node.lh : b);
		}
		// (its lines from the padding box's start, for its absolute children's areas)
		if (absolute != null) {
			// (no tracks: its first line still, at the content box's start)
			var colLines = [for (k in 0...cols.length + 1) (rtl ? s.padding.right : s.padding.left) + (k < cols.length ? colPos[k] : k > 0 ? colPos[k - 1] + cols[k - 1] : 0)];
			var rowLines = [for (k in 0...rows.length + 1) s.padding.top + (k < rows.length ? rowPos[k] : k > 0 ? rowPos[k - 1] + rows[k - 1] : 0)];
			l.absolutes(n, absolute, bw, bh, padL, padT, {cols: colLines, rows: rowLines, nCols: gridColumnCount(s), nRows: gridRowCount(s), colShift: shift.cols, rowShift: shift.rows});
		}
		n.lw = bw;
		n.lh = bh;
		@:privateAccess n.contentWidth = Math.max(cw, gridW);
		@:privateAccess n.contentHeight = Math.max(ch, gridH);
		n.dirty = false;
		n.relaid = true;
		l.rw = bw;
		l.rh = bh;
	}

	// a grid's min-content width: its columns sized under a min-content constraint
	static function minContent(l:Layout, n:Node):Float {
		var s = n.style;
		var items = [for (c in n.inOrder()) if (c.style.display != None && c.style.position != Absolute) new GridItem(c)];
		var shift = place(items, s);
		var nCols = gridColumnCount(s) + shift.cols;
		for (it in items)
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
		var defs = [for (i in 0...nCols) i >= shift.cols && i - shift.cols < s.gridTemplateColumns.length ? s.gridTemplateColumns[i - shift.cols] : s.gridAutoColumns];
		return sum(tracks(l, defs, items, true, Math.NaN, Math.NaN, s.columnGap, false, Math.NaN, Math.NaN, null, true), s.columnGap);
	}

	static function sum(sizes:Array<Float>, gap:Float):Float {
		var t = 0.0;
		for (v in sizes)
			t += v;
		return t + (sizes.length > 1 ? gap * (sizes.length - 1) : 0);
	}

	// each track's start: packed from the start, or placed as justify puts items
	static function positions(sizes:Array<Float>, gap:Float, room:Float, j:Justify):Array<Float> {
		var n = sizes.length, free = room - sum(sizes, gap), pos = 0.0, g = gap;
		// (too little room: overflowing at the start too when centred or at the end, as Chromium; distributed: at the start)
		if (n > 0 && free < 0) switch j {
			case End: pos = free;
			case Center: pos = free / 2;
			case _:
		} else if (n > 0 && free > 0) switch j {
			case End: pos = free;
			case Center: pos = free / 2;
			case SpaceBetween if (n > 1): g += free / (n - 1);
			case SpaceAround:
				g += free / n;
				pos = free / n / 2;
			case SpaceEvenly:
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

	// the explicit grid's size: its templates', its areas' if more
	static function gridColumnCount(s:Style):Int
		return s.gridTemplateAreas == null ? s.gridTemplateColumns.length : Std.int(Math.max(s.gridTemplateColumns.length, s.gridTemplateAreas.columns));

	static function gridRowCount(s:Style):Int
		return s.gridTemplateAreas == null ? s.gridTemplateRows.length : Std.int(Math.max(s.gridTemplateRows.length, s.gridTemplateAreas.rows));

	// the items' cells: those with both lines first, then those locked to a
	// row (a column, flowing by columns), then the rest by the cursor
	// (sparse; dense: the cursor back at the start for each)
	// (returns the tracks before the explicit grid's on each axis, its implicit ones of negative lines)
	static function place(items:Array<GridItem>, s:Style):{cols:Int, rows:Int} {
		var explicitCols = gridColumnCount(s), explicitRows = gridRowCount(s), flow = s.gridAutoFlow;
		var byColumn = flow == Column || flow == ColumnDense, dense = flow == RowDense || flow == ColumnDense;
		var areas = s.gridTemplateAreas;
		// (a line's index from 0; negative lines from the explicit grid's end;
		// a name's: its area's start or end line, else the first line past the explicit grid)
		// (lines clamped to ±LINES, an area to the tracks there are room for: MAX_TRACKS, as Taffy's i16 lines)
		function resolveLines(p:Grid.GridPlacement, count:Int, columns:Bool):{start:Int, span:Int} {
			inline function index(line:Int):Int {
				if (line > LINES) line = LINES else if (line < -LINES) line = -LINES;
				return line > 0 ? line - 1 : count + 1 + line;
			}
			function named(name:String, isEnd:Bool):Int {
				var atEnd = isEnd;
				var a = areas == null ? null : areas.areas.get(name);
				if (a == null && areas != null) {
					for (suffix in ["-start", "-end"])
						if (StringTools.endsWith(name, suffix)) {
							a = areas.areas.get(name.substr(0, name.length - suffix.length));
							atEnd = suffix == "-end";
						}
				}
				if (a == null) return count + (isEnd ? 1 : 0);
				return columns ? (atEnd ? a.colEnd : a.col) : (atEnd ? a.rowEnd : a.row);
			}
			if (p.startName != null || p.endName != null) {
				var a = p.startName != null ? named(p.startName, false) : p.start != 0 ? index(p.start) : AUTO;
				var b = p.endName != null ? named(p.endName, true) : p.end != 0 ? index(p.end) : AUTO;
				if (a != AUTO && b != AUTO) {
					// (the same line twice: the end dropped)
					if (b == a) return {start: a, span: 1};
					if (b < a) return {start: b, span: a - b};
					return {start: a, span: b - a};
				}
				if (a != AUTO) return {start: a, span: p.span};
				return {start: b - p.span, span: p.span};
			}
			if (p.start != 0 && p.end != 0) {
				var a = index(p.start), b = index(p.end);
				if (b < a) {
					var t = a;
					a = b;
					b = t;
				}
				return {start: a, span: Std.int(Math.max(1, b - a))};
			}
			if (p.start != 0) return {start: index(p.start), span: p.span};
			if (p.end != 0) return {start: index(p.end) - p.span, span: p.span};
			return {start: AUTO, span: p.span};
		}
		function resolve(p:Grid.GridPlacement, count:Int, columns:Bool):{start:Int, span:Int} {
			var r = resolveLines(p, count, columns);
			if (r.span > MAX_TRACKS) r.span = MAX_TRACKS;
			if (r.start != AUTO && r.start > MAX_TRACKS - r.span) r.start = MAX_TRACKS - r.span;
			return r;
		}
		var res = [for (it in items) {
			var c = resolve(it.node.style.gridColumn, explicitCols, true), r = resolve(it.node.style.gridRow, explicitRows, false);
			byColumn ? {major: c, minor: r} : {major: r, minor: c};
		}];
		// (lines before the explicit grid's start: implicit tracks there, every index shifted past them, as CSS's)
		var shiftMajor = 0, shiftMinor = 0;
		for (r in res) {
			if (r.major.start != AUTO && -r.major.start > shiftMajor) shiftMajor = -r.major.start;
			if (r.minor.start != AUTO && -r.minor.start > shiftMinor) shiftMinor = -r.minor.start;
		}
		for (r in res) {
			if (r.major.start != AUTO) r.major.start += shiftMajor;
			if (r.minor.start != AUTO) r.minor.start += shiftMinor;
		}
		// (the flow's axes: major across, minor along a row of the flow)
		var minorCount = (byColumn ? explicitRows : explicitCols) + shiftMinor;
		// (the cells taken: a small area's each in taken (by major, then minor), a large one's as its
		// rectangle (major, minor, majorSpan, minorSpan) in large, each small one's in small too)
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
				if (t != null)
					for (b in minor...minor + minorSpan)
						if (t.exists(b)) return false;
			}
			return true;
		}
		function take(it:GridItem, major:Int, minor:Int, majorSpan:Int, minorSpan:Int) {
			var r = majorSpan * minorSpan > LARGE ? large : small;
			r.push(major);
			r.push(minor);
			r.push(majorSpan);
			r.push(minorSpan);
			if (r == small)
				for (a in major...major + majorSpan) {
					var t = taken.get(a);
					if (t == null) taken.set(a, t = new Map());
					for (b in minor...minor + minorSpan)
						t.set(b, true);
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
		// both lines given
		for (k in 0...items.length) {
			var a = res[k].major, b = res[k].minor;
			if (a.start >= 0 && b.start >= 0) {
				take(items[k], a.start, b.start, a.span, b.span);
				done[k] = true;
			}
		}
		// locked to a major track: the first place along it, after what this step put there
		var cursors = new Map<Int, Int>();
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (a.start < 0) continue;
			var minor = !dense && cursors.exists(a.start) ? cursors.get(a.start) : 0;
			while (!free(a.start, minor, a.span, b.span))
				minor++;
			take(items[k], a.start, minor, a.span, b.span);
			cursors.set(a.start, minor + b.span);
			if (minor + b.span > minorCount) minorCount = minor + b.span;
			done[k] = true;
		}
		// the rest: from the cursor on
		var curMajor = 0, curMinor = 0;
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (dense) {
				curMajor = 0;
				curMinor = b.start >= 0 ? b.start : 0;
			}
			if (b.start >= 0) {
				// (its minor line given: the next major track where it fits)
				if (!dense && b.start < curMinor) curMajor++;
				curMinor = b.start;
				while (!free(curMajor, curMinor, a.span, b.span))
					curMajor++;
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

	// an item's width in its area (its areaW) while the rows are sized: its own, else stretched within its
	// widths (with an aspect ratio and no height its own, at its start, as placed), else NaN (its content's);
	// its percentages of its area
	static function widthIn(l:Layout, it:GridItem):Float {
		var c = it.node, cs = c.style, m = cs.margin;
		var room = Math.max(0, it.areaW - Layout.mz(m.left) - Layout.mz(m.right));
		var iw = cs.width.resolve(it.areaW);
		var jx = cs.justifySelf == Auto ? c.parent.style.justifyItems : cs.justifySelf;
		var jy = cs.alignSelf == Auto ? c.parent.style.alignItems : cs.alignSelf;
		var minCW = Math.max(l.minWidthOf(c, cs.minWidth, it.areaW, room), Layout.edgesH(cs)), maxCW = l.maxWidthOf(c, cs.maxWidth, it.areaW, room);
		if (!Layout.known(iw) && (jx == Stretch || jx == Auto)) iw = cs.aspectRatio > 0 && !Layout.known(cs.height.resolve(Math.NaN)) && (jy == Stretch || jy == Auto)
			? Layout.clamp(Math.min(room, Layout.max(cs.maxHeight, Math.NaN) * cs.aspectRatio), Math.max(minCW, Layout.min(cs.minHeight, Math.NaN) * cs.aspectRatio), maxCW)
			: Layout.clamp(room, minCW, maxCW);
		return iw;
	}

	// on its row's baseline (alignSelf, or the container's alignItems, Baseline; no auto margin above or below it)
	static function onBaseline(it:GridItem, s:Style):Bool {
		var cs = it.node.style;
		return (cs.alignSelf == Auto ? s.alignItems : cs.alignSelf) == Baseline && !Math.isNaN(cs.margin.top) && !Math.isNaN(cs.margin.bottom);
	}

	// CSS Grid 11.5's baseline shims: the items on their baselines that start in the same row (two or more), each
	// laid out at its area's width, the room above each that brings its first baseline (else its bottom edge) to
	// the deepest one's
	static function shims(l:Layout, items:Array<GridItem>, s:Style) {
		var any = false;
		for (it in items) {
			it.shim = 0;
			if (onBaseline(it, s)) any = true;
		}
		if (!any) return;
		var rows = new Map<Int, Array<GridItem>>();
		for (it in items)
			if (onBaseline(it, s)) {
				if (!rows.exists(it.row)) rows.set(it.row, []);
				rows.get(it.row).push(it);
			}
		for (group in rows) {
			if (group.length < 2) continue;
			var deepest = Math.NEGATIVE_INFINITY;
			for (it in group) {
				var c = it.node, m = c.style.margin;
				var iw = widthIn(l, it);
				l.looseH = true;
				l.size(c, iw, Math.NaN, it.areaW, Math.NaN, Layout.known(iw) ? iw : Math.max(0, it.areaW - Layout.mz(m.left) - Layout.mz(m.right)), Math.NaN, true);
				var b = c.firstBaseline();
				it.shim = Layout.mz(m.top) + (Math.isNaN(b) ? l.rh : b);
				if (it.shim > deepest) deepest = it.shim;
			}
			for (it in group)
				it.shim = deepest - it.shim;
		}
	}

	// a track sizing function's kind, once its percentage is resolved (one
	// of an indefinite size: auto)
	static inline var FIXED = 0;
	static inline var AUTO = 1;
	static inline var MIN_CONTENT = 2;
	static inline var MAX_CONTENT = 3;
	static inline var FLEX = 4;

	// CSS Grid's track sizing algorithm (level 1, 11.3 to 11.8) for one
	// axis's tracks: room the content box's size on it (NaN: indefinite,
	// sized under a max-content constraint; minContent: under a min-content
	// one), pct what percentage tracks are of (NaN: auto), stretch: auto
	// tracks take what is left; least and most the content box's min and max
	// sizes (an indefinite room's fr within them). The items' contributions
	// are measured with gridW and gridH as their percentages' base, rows at
	// the columns' sizes (their areaW), on their baseline shims
	static function tracks(l:Layout, defs:Array<Grid.Track>, items:Array<GridItem>, columns:Bool, room:Float, pct:Float, gap:Float, stretch:Bool, gridW:Float,
			gridH:Float, cols:Null<Array<Float>>, minContent = false, least = 0.0, most = Math.POSITIVE_INFINITY):Array<Float> {
		var n = defs.length, inf = Math.POSITIVE_INFINITY;
		var definite = Layout.known(room), maxContent = !definite && !minContent;
		var minK = new Array<Int>(), maxK = new Array<Int>(), fr = new Array<Float>();
		var base = new Array<Float>(), limit = new Array<Float>();
		minK.resize(n);
		maxK.resize(n);
		fr.resize(n);
		base.resize(n);
		limit.resize(n);
		// 11.4: the base sizes (a fixed minimum's, else 0) and growth limits (a fixed maximum's, else infinite)
		var settled = true;
		for (i in 0...n) {
			var d = defs[i];
			var mn = 0.0, mx = inf;
			minK[i] = switch d.min {
				case Px(v):
					mn = v;
					FIXED;
				case Percent(p) if (Layout.known(pct)):
					mn = pct * p / 100;
					FIXED;
				case MinContent: MIN_CONTENT;
				case MaxContent: MAX_CONTENT;
				case _: AUTO;
			}
			fr[i] = 0;
			maxK[i] = switch d.max {
				case Px(v):
					mx = v;
					FIXED;
				case Percent(p) if (Layout.known(pct)):
					mx = pct * p / 100;
					FIXED;
				case Fr(f):
					fr[i] = f;
					FLEX;
				case MinContent: MIN_CONTENT;
				case MaxContent: MAX_CONTENT;
				case _: AUTO;
			}
			base[i] = mn;
			limit[i] = mx < mn ? mn : mx;
			if (minK[i] != FIXED || maxK[i] != FIXED) settled = false;
		}
		// (every track fixed: no item measured; each at its size when its minimum and maximum agree)
		var exact = settled;
		for (i in 0...n)
			if (base[i] != limit[i]) exact = false;
		if (exact) return base;
		inline function gaps(a:Int, b:Int):Float
			return b - a > 1 ? gap * (b - a - 1) : 0;
		inline function startOf(it:GridItem):Int
			return columns ? it.col : it.row;
		inline function spanOf(it:GridItem):Int
			return columns ? it.colSpan : it.rowSpan;

		// the items' contributions on this axis (outer sizes, a baseline shim
		// within): min-content, max-content, and their minimum contributions;
		// only those spanning a track not fixed, the others never asked
		var count = items.length;
		var mins = new Array<Float>(), maxes = new Array<Float>(), minimums = new Array<Float>(), flexed = new Array<Bool>();
		mins.resize(count);
		maxes.resize(count);
		minimums.resize(count);
		flexed.resize(count);
		var order = [];
		for (k in 0...count) {
			var it = items[k], a = startOf(it), b = a + spanOf(it);
			var sized = false, crossesFlex = false, spansAutoMin = false, allFixedMax = true, fixedMax = gaps(a, b);
			for (i in a...b) {
				if (minK[i] != FIXED || maxK[i] != FIXED) sized = true;
				if (maxK[i] == FLEX) crossesFlex = true;
				if (minK[i] == AUTO) spansAutoMin = true;
				if (maxK[i] == FIXED) fixedMax += limit[i] else allFixedMax = false;
			}
			flexed[k] = crossesFlex;
			if (!sized || settled) {
				mins[k] = maxes[k] = minimums[k] = 0;
				continue;
			}
			order.push(k);
			var c = it.node, cs = c.style, m = cs.margin;
			var edges = columns ? Layout.mz(m.left) + Layout.mz(m.right) : Layout.mz(m.top) + Layout.mz(m.bottom) + it.shim;
			var pb = columns ? Layout.edgesH(cs) : Layout.edgesV(cs);
			if (columns && Layout.known(it.areaH) && cs.aspectRatio > 0 && !Layout.known(cs.width.resolve(Math.NaN)) && !Layout.known(cs.height.resolve(Math.NaN))) {
				// (sized again, its rows known: its width through the ratio from their height, within its heights)
				var ih = Layout.clamp(Math.max(0, it.areaH - Layout.mz(m.top) - Layout.mz(m.bottom)), Math.max(Layout.min(cs.minHeight, it.areaH), Layout.edgesV(cs)), Layout.max(cs.maxHeight, it.areaH));
				l.size(c, Math.NaN, ih, Math.NaN, it.areaH, Math.NaN, ih, false);
				mins[k] = maxes[k] = l.rw + edges;
			} else if (columns) {
				// (its percentages of its area, not known yet: auto meanwhile)
				mins[k] = l.minContentWidth(c, Math.NaN, true) + edges;
				l.size(c, Math.NaN, Math.NaN, Math.NaN, gridH, Math.NaN, Math.NaN, false);
				maxes[k] = l.rw + edges;
			} else {
				var iw = widthIn(l, it), room2 = Math.max(0, it.areaW - Layout.mz(m.left) - Layout.mz(m.right));
				l.size(c, iw, Math.NaN, it.areaW, Math.NaN, Layout.known(iw) ? iw : room2, Math.NaN, false);
				mins[k] = maxes[k] = l.rh + edges;
			}
			// its minimum contribution (CSS Grid 6.6): its min-content one when it has a size of its own (or
			// min-content, max-content, fit-content); else its
			// min size (a percentage of its area, 0 while that is not known); else none for a scroll container; else
			// its automatic minimum, its min-content size when it spans a track whose minimum is auto (and no
			// flexible one, spanning more than one), no more than the fixed maximums it spans only (within its
			// margins, no less than its padding and border), as Chromium has it
			var area = 0.0;
			for (i in a...b)
				if (minK[i] == FIXED && maxK[i] == FIXED && base[i] == limit[i]) area += base[i] else area = Math.NaN;
			if (Layout.known(area)) area += gaps(a, b);
			var preferred = columns ? cs.width : cs.height;
			var own = preferred.intrinsic() ? 0 : preferred.resolve(area);
			var given = (columns ? cs.minWidth : cs.minHeight).resolve(Layout.known(area) ? area : 0);
			minimums[k] = if (Layout.known(own)) mins[k] else if (Layout.known(given)) Math.max(given, pb) + edges else if (cs.overflow != Visible) pb + edges else
				if (spansAutoMin && (b - a == 1 || !crossesFlex)) {
					var v = mins[k] - edges;
					if (allFixedMax) v = Math.min(v, Math.max(fixedMax - edges, pb));
					v + edges;
				} else pb + edges;
		}

		// planned increases, item-incurred ones, tracks whose growth limit may still grow past it
		var planBase = new Array<Float>(), planLimit = new Array<Float>(), inc = new Array<Float>(), growable = new Array<Bool>();
		for (i in 0...n) {
			planBase.push(0);
			planLimit.push(0);
			inc.push(0);
			growable.push(false);
		}
		inline function size(i:Int, ofLimit:Bool):Float
			return ofLimit && limit[i] != inf ? limit[i] : base[i];
		// 11.5.1: space distributed equally (or by weight) among the affected tracks, each up to its limit, what is left returned
		function upTo(space:Float, a:Int, b:Int, affected:Int->Bool, weight:Int->Float, ofLimit:Bool, lim:Int->Float):Float {
			for (_ in 0...b - a + 1) {
				if (space <= 0.01) break;
				var sum = 0.0, first = inf;
				for (i in a...b)
					if (affected(i) && size(i, ofLimit) + inc[i] < lim(i)) {
						var w = weight(i);
						sum += w;
						var r = (lim(i) - size(i, ofLimit) - inc[i]) / w;
						if (r < first) first = r;
					}
				if (sum == 0) break;
				var step = Math.min(first, space / sum);
				for (i in a...b)
					if (affected(i)) {
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
		// an item's space to the base sizes of its affected tracks (crossing flexible ones: those, by their factors);
		// past their limits to those whose maximum is intrinsic (max-content, for max-content contributions), else all
		function toBase(space:Float, a:Int, b:Int, flex:Bool, affected:Int->Bool, lim:Int->Float, ofMax:Bool) {
			if (space == 0) return;
			var aff = flex ? i -> maxK[i] == FLEX && affected(i) : affected;
			var any = false, weights = 0.0;
			for (i in a...b)
				if (aff(i)) {
					any = true;
					weights += fr[i];
				}
			if (!any) return;
			var weight = flex && weights > 0 ? flexWeight : one;
			var have = gaps(a, b);
			for (i in a...b)
				have += base[i];
			var extra = upTo(Math.max(0, space - have), a, b, aff, weight, false, lim);
			if (extra > 0.000001) {
				var past = ofMax ? i -> maxK[i] == MAX_CONTENT : i -> maxK[i] == AUTO || maxK[i] == MIN_CONTENT || maxK[i] == MAX_CONTENT;
				var some = false;
				for (i in a...b)
					if (aff(i) && past(i)) some = true;
				upTo(extra, a, b, some ? i -> aff(i) && past(i) : aff, weight, false, unlimited);
			}
			for (i in a...b) {
				if (inc[i] > planBase[i]) planBase[i] = inc[i];
				inc[i] = 0;
			}
		}
		// an item's space to the growth limits of its affected tracks (an infinite one as its base size): those
		// that may grow past it first, then all
		function toLimit(space:Float, a:Int, b:Int, affected:Int->Bool) {
			if (space == 0) return;
			var any = false;
			for (i in a...b)
				if (affected(i)) any = true;
			if (!any) return;
			var have = gaps(a, b);
			for (i in a...b)
				have += size(i, true);
			var extra = upTo(Math.max(0, space - have), a, b, i -> affected(i) && (growable[i] || limit[i] == inf), one, true, unlimited);
			if (extra > 0) upTo(extra, a, b, affected, one, true, unlimited);
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
			for (i in a...a + spanOf(items[k]))
				if (f(i)) return true;
			return false;
		}
		// (sized under a min- or max-content constraint: an item's min-content contribution no more than the fixed
		// maximums it spans only, no less than its minimum contribution; crossing flexible tracks, what passes the
		// others' base sizes scaled by their factors when those add up to less than 1, as Chromium)
		function cap(k:Int, v:Float):Float {
			var it = items[k], a = startOf(it), b = a + spanOf(it), most = gaps(a, b);
			for (i in a...b)
				if (maxK[i] == FIXED) most += limit[i] else return v;
			return Math.min(v, most);
		}
		function scale(k:Int, v:Float):Float {
			var it = items[k], a = startOf(it), b = a + spanOf(it), inflexible = gaps(a, b), factors = 0.0;
			for (i in a...b)
				if (maxK[i] == FLEX) factors += fr[i] else inflexible += base[i];
			return inflexible + Math.max(v - inflexible, 0) * Math.min(factors, 1);
		}
		inline function scroller(k:Int):Bool
			return items[k].node.style.overflow != Visible;

		// 11.5: the items by span, those crossing a flexible track last, all at once
		var batches = [];
		order.sort((x, y) -> flexed[x] != flexed[y] ? (flexed[x] ? 1 : -1) : flexed[x] ? x - y : spanOf(items[x]) != spanOf(items[y]) ? spanOf(items[x]) - spanOf(items[y]) : x - y);
		var at = 0;
		while (at < order.length) {
			var first = order[at], end = at + 1;
			while (end < order.length && (flexed[first] || !flexed[order[end]] && spanOf(items[order[end]]) == spanOf(items[first])))
				end++;
			batches.push(order.slice(at, end));
			at = end;
		}
		for (batch in batches) {
			var flex = flexed[batch[0]];
			if (!flex && spanOf(items[batch[0]]) == 1) {
				// the items spanning one track: its base size their contributions', its growth limit too
				for (k in batch) {
					var i = startOf(items[k]);
					switch minK[i] {
						case MIN_CONTENT:
							base[i] = Math.max(base[i], mins[k]);
						case MAX_CONTENT:
							base[i] = Math.max(base[i], maxes[k]);
						case AUTO:
							base[i] = Math.max(base[i], !definite && !scroller(k) ? Math.max(minimums[k], cap(k, mins[k])) : minimums[k]);
						case _:
					}
					var want = switch maxK[i] {
						case AUTO | MAX_CONTENT: maxes[k];
						case MIN_CONTENT: mins[k];
						case _: -1.0;
					}
					if (want >= 0) {
						if (!growable[i] || want > planLimit[i]) planLimit[i] = want;
						growable[i] = true;
					}
				}
				// (a track with items its growth limit theirs, 0 too, as CSS's: not Taffy's, which keeps an infinite one)
				for (i in 0...n) {
					if (growable[i]) limit[i] = limit[i] == inf ? planLimit[i] : Math.max(limit[i], planLimit[i]);
					growable[i] = false;
					planLimit[i] = 0;
					if (limit[i] < base[i]) limit[i] = base[i];
				}
				continue;
			}
			// the intrinsic minimums: the items' minimum contributions (under a constraint: their limited min-content ones)
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
			// the content-based minimums: their min-content contributions
			var contentMin = i -> minK[i] == MIN_CONTENT || minK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, contentMin)) continue;
				var a = startOf(items[k]);
				if (mins[k] > 0) toBase(mins[k], a, a + spanOf(items[k]), flex, contentMin, growthLimit, false);
			}
			flushBase();
			// the max-content minimums: under a max-content constraint, their limited max-content contributions
			if (maxContent) {
				var autoMin = i -> minK[i] == AUTO && maxK[i] != MIN_CONTENT, maxMin = i -> minK[i] == MAX_CONTENT;
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
			// (in all cases: max-content minimums their max-content contributions)
			var maxMin = i -> minK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, maxMin)) continue;
				var a = startOf(items[k]);
				if (maxes[k] > 0) toBase(maxes[k], a, a + spanOf(items[k]), flex, maxMin, growthLimit, true);
			}
			flushBase();
			for (i in 0...n)
				if (limit[i] < base[i]) limit[i] = base[i];
			if (flex) continue;
			// the intrinsic maximums: their min-content contributions; then max-content maximums, their max-content ones
			var intrinsicMax = i -> maxK[i] != FIXED;
			for (k in batch) {
				if (!spans(k, intrinsicMax)) continue;
				var a = startOf(items[k]);
				if (mins[k] > 0) toLimit(mins[k], a, a + spanOf(items[k]), intrinsicMax);
			}
			flushLimit(true);
			var maxMax = i -> maxK[i] == AUTO || maxK[i] == MAX_CONTENT;
			for (k in batch) {
				if (!spans(k, maxMax)) continue;
				var a = startOf(items[k]);
				if (maxes[k] > 0) toLimit(maxes[k], a, a + spanOf(items[k]), maxMax);
			}
			flushLimit(false);
		}
		for (i in 0...n)
			if (limit[i] == inf) limit[i] = base[i];

		// 11.6: the free space to the base sizes, up to the growth limits (a max-content constraint's: all of it)
		if (maxContent) {
			for (i in 0...n)
				base[i] = limit[i];
		} else if (definite) {
			var free = room - gaps(0, n);
			for (i in 0...n)
				free -= base[i];
			if (free > 0) {
				upTo(free, 0, n, i -> true, one, false, growthLimit);
				for (i in 0...n) {
					base[i] += inc[i];
					inc[i] = 0;
				}
			}
		}

		// 11.7: the flexible tracks, at the size of an fr
		function frSize(a:Int, b:Int, space:Float):Float {
			if (space == 0) return 0;
			var hyp = inf, was = inf;
			for (_ in 0...b - a + 1) {
				var used = gaps(a, b), factors = 0.0;
				for (i in a...b)
					if (maxK[i] == FLEX && fr[i] * hyp >= base[i]) factors += fr[i] else used += base[i];
				was = hyp;
				hyp = (space - used) / Math.max(factors, 1);
				var valid = true;
				for (i in a...b)
					if (maxK[i] == FLEX && !(fr[i] * hyp >= base[i] || fr[i] * was < base[i])) valid = false;
				if (valid) break;
			}
			return hyp;
		}
		var anyFlex = false;
		for (i in 0...n)
			if (maxK[i] == FLEX) anyFlex = true;
		if (anyFlex) {
			var fraction = 0.0;
			if (definite) {
				var used = gaps(0, n);
				for (i in 0...n)
					used += base[i];
				fraction = room - used <= 0 ? 0 : frSize(0, n, room);
			} else if (!(minContent && columns)) {
				// (indefinite: the largest fr a flexible track or an item crossing one needs, within the min and max sizes)
				for (i in 0...n)
					if (maxK[i] == FLEX) fraction = Math.max(fraction, fr[i] > 1 ? base[i] / fr[i] : base[i]);
				for (k in order)
					if (flexed[k]) {
						var a = startOf(items[k]);
						fraction = Math.max(fraction, frSize(a, a + spanOf(items[k]), maxes[k]));
					}
				var total = gaps(0, n);
				for (i in 0...n)
					total += maxK[i] == FLEX ? Math.max(base[i], fr[i] * fraction) : base[i];
				if (total < least) fraction = frSize(0, n, least) else if (total > most) fraction = frSize(0, n, most);
			}
			for (i in 0...n)
				if (maxK[i] == FLEX) base[i] = Math.max(base[i], fr[i] * fraction);
		}

		// 11.8: auto tracks stretched over what is left
		if (stretch && definite) {
			var free = room - gaps(0, n), autos = 0;
			for (i in 0...n) {
				free -= base[i];
				if (defs[i].max == Grid.TrackSize.Auto) autos++;
			}
			if (free > 0 && autos > 0)
				for (i in 0...n)
					if (defs[i].max == Grid.TrackSize.Auto) base[i] += free / autos;
		}
		return base;
	}
}

private class GridItem {
	public final node:Node;
	// its cells: the first column and row (from 0), how many
	public var col = 0;
	public var row = 0;
	public var colSpan = 1;
	public var rowSpan = 1;
	// its area's width (the columns' sizes, the gaps between)
	public var areaW = 0.0;
	// its area's height, once the rows are sized (NaN before)
	public var areaH = Math.NaN;
	// on its row's baseline: the room above it that puts it there (CSS Grid 11.5's shim)
	public var shim = 0.0;
	// its border box's top in the content box, once placed (no relative offset)
	public var y = 0.0;

	public function new(node:Node)
		this.node = node;
}
