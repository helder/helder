package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.box.Fragments;
import helder.ui.box.Len;
import helder.ui.box.TableGrid;

using StringTools;

// Table layout (CSS 2.1 §17 with CSS Tables 3 where they agree): the
// wrapper box's captions above and below the table box; the grid of
// rows and cells (HTML's colspan and rowspan, row groups in their order:
// a header first, a footer last); column widths by the fixed algorithm
// (table-layout: fixed with a width: the columns' and the first row's
// widths) or the auto one (each column's min-content and max-content from
// its cells, spanning cells spread over theirs, percentages; Tables 3's
// guesses for a width between them); border-spacing, or the collapsing
// border model (§17.6.2: each grid line's segment's border, what wins of
// the cells', rows', groups', columns' and the table's); row heights from
// their cells, baselines and rowspans; cells laid out as blocks (flow)
// and aligned in their rows (vertical-align: baseline, top, middle,
// bottom); empty-cells; rows of visibility: collapse take no room.
class TableFlow implements FormattingContext {
	final flow:BlockFlow;

	public function new(flow:BlockFlow)
		this.flow = flow;

	public function layout(wrapper:Box, space:Space):Int {
		var key = Math.isNaN(space.fixedWidth) ? space.width : -1 - space.fixedWidth;
		// (in a fragmentainer: laid out afresh, its rows sliced where it breaks)
		var paged = space.fragmentation != null;
		if (!paged && wrapper.cacheFragment >= 0 && wrapper.cacheWidth == key && (wrapper.cacheHeight == space.height || Math.isNaN(wrapper.cacheHeight)
			&& Math.isNaN(space.height)))
			return wrapper.cacheFragment;
		var abs = space.positioned?.boxes.length ?? 0, fixed = space.fixed?.boxes.length ?? 0;
		var f = place(wrapper, space);
		var escaped = (space.positioned?.boxes.length ?? 0) > abs || (space.fixed?.boxes.length ?? 0) > fixed;
		wrapper.cacheWidth = key;
		wrapper.cacheHeight = space.height;
		wrapper.cacheFragment = paged || escaped ? -1 : f;
		return f;
	}

	public function intrinsic(wrapper:Box, space:Space) {
		if (!Math.isNaN(wrapper.minContent)) return;
		var t = tableOf(wrapper);
		if (t == null) {
			wrapper.minContent = wrapper.maxContent = 0;
			return;
		}
		var g = grid(t, space);
		var s = t.style.model();
		var edges = outerEdges(t, g, 0);
		var spacing = g.spacingH * Math.max(2, g.columns + 1);
		var min = edges + spacing, max = edges + spacing;
		for (c in g.cols) {
			min += c.min;
			max += c.pct > 0 ? c.min : c.max;
		}
		switch s.width {
			case Px(v):
				min = Math.max(min, v);
				max = Math.max(min, v);
			case _:
		}
		min = Math.max(min, captionMin(wrapper, t, space));
		wrapper.minContent = min;
		wrapper.maxContent = Math.max(min, max);
	}

	// (auto-width captions need room for their contents in the table's used width)
	function captionMin(wrapper:Box, table:Box, space:Space, autoOnly = false):Float {
		var min = 0.0, c = wrapper.first;
		while (c != null) {
			if (c != table && (!autoOnly || Lens.isAuto(c.style.model().width))) {
				flow.intrinsic(c, space);
				var m = c.style.model().margin;
				min = Math.max(min, c.minContent + BlockFlow.fixed(m[1]) + BlockFlow.fixed(m[3]));
			}
			c = c.next;
		}
		return min;
	}

	static function tableOf(wrapper:Box):Null<Box> {
		var c = wrapper.first;
		while (c != null) {
			if (c.kind == Container && c.style.inner == BoxStyle.TABLE) return c;
			c = c.next;
		}
		return null;
	}

	// ---- the grid

	function grid(t:Box, space:Space):Grid {
		var g = new Grid();
		var s = t.style;
		g.collapse = s.rare.borderCollapse;
		g.exact = space.exact;
		if (!g.collapse) switch s.rare.borderSpacing {
			case [h, v]:
				g.spacingH = h;
				g.spacingV = v;
			case [h]:
				g.spacingH = g.spacingV = h;
			case _:
		}
		// (row groups in order: the first header, the bodies and lone rows, the first footer, §17.2)
		var header:Null<Box> = null, footer:Null<Box> = null;
		var middle:Array<Box> = [];
		var c = t.first;
		while (c != null) {
			switch c.style.part {
				case BoxStyle.HEADER_GROUP if (header == null): header = c;
				case BoxStyle.FOOTER_GROUP if (footer == null): footer = c;
				case BoxStyle.ROW_GROUP | BoxStyle.HEADER_GROUP | BoxStyle.FOOTER_GROUP | BoxStyle.ROW: middle.push(c);
				case BoxStyle.COLUMN_GROUP:
					var cols = c.children();
					if (cols.length == 0) for (_ in 0...span(c)) {
						g.colBoxes.push(null);
						g.colGroups.push(c);
					} else for (col in cols) for (_ in 0...span(col)) {
						g.colBoxes.push(col);
						g.colGroups.push(c);
					}
				case BoxStyle.COLUMN:
					for (_ in 0...span(c)) {
						g.colBoxes.push(c);
						g.colGroups.push(null);
					}
				case _:
			}
			c = c.next;
		}
		var groups = (header != null ? [header] : []).concat(middle).concat(footer != null ? [footer] : []);
		g.header = header;
		g.footer = footer;
		var groupIndex = 0;
		while (groupIndex < groups.length) {
			var group:Null<Box> = groups[groupIndex++];
			var rows:Array<Box>;
			if (group.style.part == BoxStyle.ROW) {
				// (consecutive direct rows have the same implicit row group, including in XHTML)
				rows = [group];
				while (groupIndex < groups.length && groups[groupIndex].style.part == BoxStyle.ROW)
					rows.push(groups[groupIndex++]);
				group = null;
			} else
				rows = group.children();
			var first = g.rows.length;
			for (r in rows) {
				g.rows.push(r);
				g.rowGroups.push(group);
			}
			// (cells into slots, past those a rowspan above holds; rowspan 0: to the group's end)
			for (k in 0...rows.length) {
				var ri = first + k;
				var col = 0;
				var cell = rows[k].first;
				while (cell != null) {
					while (g.taken(ri, col)) col++;
					var cs = attr(cell, "colspan", 1, 1, 1000);
					var rs = attr(cell, "rowspan", 1, 0, 65534);
					if (rs == 0 || rs > rows.length - k) rs = rows.length - k;
					g.cells.push({box: cell, row: ri, col: col, rows: rs, cols: cs, fragment: -1, height: 0, contentHeight: 0, baseline: Math.NaN, bottomEdge: 0});
					for (dr in 0...rs) for (dc in 0...cs) g.take(ri + dr, col + dc);
					col += cs;
					cell = cell.next;
				}
			}
		}
		g.columns = g.colBoxes.length;
		for (r in g.slots) if (r.length > g.columns) g.columns = r.length;
		for (cell in g.cells) if (cell.col + cell.cols > g.columns) g.columns = cell.col + cell.cols;
		while (g.colBoxes.length < g.columns) {
			g.colBoxes.push(null);
			g.colGroups.push(null);
		}
		// (resolve spans in reading order, then give layout physical column indices)
		if (s.rtl) {
			g.colBoxes.reverse();
			g.colGroups.reverse();
			for (cell in g.cells) cell.col = g.columns - cell.col - cell.cols;
		}
		for (_ in 0...g.columns) g.cols.push({min: 0, max: 0, pct: 0, fixed: false});
		if (g.collapse) collapseBorders(t, g);
		measure(g, space);
		return g;
	}

	// (an HTML cell's colspan or rowspan, a column's or column group's span)
	// (as BoxTree read it of an HTML element: -1 none)
	static function attr(b:Box, name:String, fallback:Int, min:Int, max:Int):Int {
		var n = name == "rowspan" ? b.rowSpan : name == "colspan" ? b.colSpan : b.span;
		if (n == -1) return fallback;
		return n < min ? (name == "rowspan" && n == 0 ? 0 : fallback) : n > max ? max : n;
	}

	static function span(b:Box):Int
		return attr(b, "span", 1, 1, 1000);

	// (each column's min-content, max-content, percentage, and whether a width is set, from its cells:
	// those of one column first, then the spanning ones spread over theirs, Tables 3 §3.8)
	function measure(g:Grid, space:Space) {
		for (c in 0...g.columns) {
			var col = g.colBoxes[c];
			var group = g.colGroups[c];
			var track = g.cols[c];
			if (group != null) widthInto(track, group);
			if (col != null) widthInto(track, col);
		}
		var spanning = [];
		for (cell in g.cells) {
			var b = cell.box;
			flow.intrinsic(b, space);
			if (cell.cols > 1) {
				spanning.push(cell);
				continue;
			}
			var col = g.cols[cell.col];
			var s = b.style.model();
			var d = delta(g, cell);
			var min = b.minContent + d, max = b.maxContent + d;
			col.min = Math.max(col.min, min);
			switch s.width {
				// (a cell's width: its column's max-content, at least its min-content)
				case Px(v):
					col.fixed = true;
					switch s.maxWidth {
						case Px(m) if (m < v): v = m;
						case _:
					}
					col.max = Math.max(col.max, Math.max(min, s.borderBox ? v : v + bpx(b) + d));
				case Percent(p):
					col.pct = Math.max(col.pct, p);
					col.max = Math.max(col.max, max);
				case _:
					col.max = Math.max(col.max, max);
			}
		}
		spanning.sort((a, b) -> a.cols - b.cols);
		for (cell in spanning) {
			var b = cell.box;
			var inner = g.spacingH * (cell.cols - 1);
			var min = 0.0, max = 0.0;
			for (c in cell.col...cell.col + cell.cols) {
				min += g.cols[c].min;
				max += g.cols[c].max;
			}
			var d = delta(g, cell);
			spread(g, cell, b.minContent + d - inner - min, true, max);
			// (raising the minimum can also raise a column's maximum)
			max = 0;
			for (c in cell.col...cell.col + cell.cols)
				max += g.cols[c].max;
			spread(g, cell, b.maxContent + d - inner - max, false, max);
		}
		for (c in g.cols) if (c.max < c.min) c.max = c.min;
	}

	// (in the collapsing model a cell's left and right borders are half its lines', not its own)
	static function delta(g:Grid, cell:Cell):Float {
		if (!g.collapse) return 0;
		var s = cell.box.style.model(), half = cellBorders(g, cell);
		return half[1] + half[3] - s.border[1] - s.border[3];
	}

	static function widthInto(col:TableColumn, box:Box) {
		var s = box.style.model();
		var min = Lens.resolve(s.minWidth, Math.NaN, 0);
		col.min = Math.max(col.min, min);
		switch s.width {
			case Px(v):
				col.fixed = true;
				col.max = Math.max(col.max, Math.min(v, Lens.resolve(s.maxWidth, Math.NaN, v)));
			case Percent(p):
				switch s.maxWidth {
					case Percent(max): p = Math.min(p, max);
					case _:
				}
				col.pct = Math.max(col.pct, p);
			case _:
		}
	}

	// (more min-content or max-content for a spanning cell: over its columns, by their max-content, else evenly)
	static function spread(g:Grid, cell:Cell, extra:Float, min:Bool, total:Float) {
		if (extra <= 0) return;
		for (c in cell.col...cell.col + cell.cols) {
			var col = g.cols[c];
			var share = total > 0 ? extra * col.max / total : extra / cell.cols;
			if (min) {
				col.min += share;
				if (col.max < col.min) col.max = col.min;
			} else
				col.max += share;
		}
	}

	static function bpx(b:Box):Float {
		var s = b.style.model();
		return s.border[1] + s.border[3] + BlockFlow.fixed(s.padding[1]) + BlockFlow.fixed(s.padding[3]);
	}

	// ---- the collapsing border model (§17.6.2)

	function collapseBorders(t:Box, g:Grid) {
		var tg = new TableGrid(g.columns, g.rows.length);
		tg.collapsing();
		tg.exact = g.exact;
		g.borders = tg;
		var rows = g.rows.length, cols = g.columns;
		inline function side(b:Box, k:Int):{w:Float, s:String, c:Int} {
			var st = b.style.model();
			var name = SIDES[k];
			return {w: st.border[k], s: b.style.borderStyle(k), c: b.style.borderColor(k)};
		}
		function h(line:Int, from:Int, to:Int, b:Box, k:Int) {
			var e = side(b, k);
			for (c in from...to) tg.offerH(line, c, e.w, e.s, e.c);
		}
		function v(line:Int, from:Int, to:Int, b:Box, k:Int) {
			var e = side(b, k);
			for (r in from...to) tg.offerV(r, line, e.w, e.s, e.c);
		}
		// (cells first: the strongest origin; then rows, row groups, columns, column groups, the table)
		for (cell in g.cells) {
			h(cell.row, cell.col, cell.col + cell.cols, cell.box, 0);
			h(cell.row + cell.rows, cell.col, cell.col + cell.cols, cell.box, 2);
			v(cell.col, cell.row, cell.row + cell.rows, cell.box, 3);
			v(cell.col + cell.cols, cell.row, cell.row + cell.rows, cell.box, 1);
		}
		for (r in 0...rows) {
			var row = g.rows[r];
			h(r, 0, cols, row, 0);
			h(r + 1, 0, cols, row, 2);
			v(0, r, r + 1, row, 3);
			v(cols, r, r + 1, row, 1);
		}
		var r = 0;
		while (r < rows) {
			var group = g.rowGroups[r];
			var end = r + 1;
			while (end < rows && g.rowGroups[end] == group) end++;
			if (group != null) {
				h(r, 0, cols, group, 0);
				h(end, 0, cols, group, 2);
				v(0, r, end, group, 3);
				v(cols, r, end, group, 1);
			}
			r = end;
		}
		// (equal borders from the same origin favour inline-start)
		var rtl = t.style.rtl;
		inline function column(i:Int):Int
			return rtl ? cols - 1 - i : i;
		for (i in 0...cols) {
			var c = column(i), col = g.colBoxes[c];
			if (col == null) continue;
			v(c, 0, rows, col, 3);
			v(c + 1, 0, rows, col, 1);
			h(0, c, c + 1, col, 0);
			h(rows, c, c + 1, col, 2);
		}
		var i = 0;
		while (i < cols) {
			var group = g.colGroups[column(i)];
			var end = i + 1;
			while (end < cols && g.colGroups[column(end)] == group) end++;
			if (group != null) {
				var left = rtl ? cols - end : i, right = rtl ? cols - i : end;
				v(left, 0, rows, group, 3);
				v(right, 0, rows, group, 1);
				h(0, left, right, group, 0);
				h(rows, left, right, group, 2);
			}
			i = end;
		}
		h(0, 0, cols, t, 0);
		h(rows, 0, cols, t, 2);
		v(0, 0, rows, t, 3);
		v(cols, 0, rows, t, 1);
	}

	static final SIDES = ["top", "right", "bottom", "left"];

	// (the table's own border and padding on the left and right: in the collapsing model half of its
	// outer lines' widest, no padding)
	static function outerEdges(t:Box, g:Grid, base:Float):Float {
		var s = t.style.model();
		if (g.collapse) {
			var e = collapsedEdges(g);
			return e[1] + e[3];
		}
		return s.border[1] + s.border[3] + BlockFlow.res(s.padding[1], base) + BlockFlow.res(s.padding[3], base);
	}

	// (the table's border widths in the collapsing model, CSS 2.1 §17.6.2: what of its outer lines'
	// widest lies outside the grid, split by TableGrid.half; a cell's are the other parts, cellBorders)
	static function collapsedEdges(g:Grid):Array<Float> {
		var tg = g.borders, out = [0.0, 0.0, 0.0, 0.0];
		if (tg == null) return out;
		var rows = g.rows.length, cols = g.columns;
		for (c in 0...cols) {
			out[0] = Math.max(out[0], tg.half(tg.hPainted(tg.h(0, c)), false));
			out[2] = Math.max(out[2], tg.half(tg.hPainted(tg.h(rows, c)), true));
		}
		for (r in 0...rows) {
			out[3] = Math.max(out[3], tg.half(tg.vPainted(tg.v(r, 0)), false));
			out[1] = Math.max(out[1], tg.half(tg.vPainted(tg.v(r, cols)), true));
		}
		return out;
	}

	// ---- column widths

	// (the columns' widths for the space between the outer spacing: Tables 3 §3.9's guesses, the
	// width between two of them shared linearly, past the last one given to auto columns first)
	public static function distribute(cols:Array<TableColumn>, w:Float):Array<Float> {
		var n = cols.length;
		if (n == 0) return [];
		var guesses = [
			[for (c in cols) c.min],
			[for (c in cols) c.pct > 0 ? Math.max(c.min, c.pct * w / 100) : c.min],
			[for (c in cols) c.pct > 0 ? Math.max(c.min, c.pct * w / 100) : c.fixed ? c.max : c.min],
			[for (c in cols) c.pct > 0 ? Math.max(c.min, c.pct * w / 100) : c.max]
		];
		var sums = [for (g in guesses) Lambda.fold(g, (x, a) -> x + a, 0.0)];
		if (w <= sums[0]) return guesses[0];
		for (k in 0...3)
			if (w <= sums[k + 1]) {
				var r = sums[k + 1] > sums[k] ? (w - sums[k]) / (sums[k + 1] - sums[k]) : 0;
				return [for (i in 0...n) guesses[k][i] + (guesses[k + 1][i] - guesses[k][i]) * r];
			}
		var out = guesses[3].copy(), extra = w - sums[3];
		inline function give(pick:TableColumn->Bool, weight:TableColumn->Float):Bool {
			var total = 0.0, count = 0;
			for (c in cols) if (pick(c)) {
				total += weight(c);
				count++;
			}
			if (count == 0) return false;
			for (i in 0...n) if (pick(cols[i])) out[i] += total > 0 ? extra * weight(cols[i]) / total : extra / count;
			return true;
		}
		if (!give(c -> c.pct == 0 && !c.fixed && c.max > 0, c -> c.max)
			&& !give(c -> c.pct == 0 && !c.fixed, c -> 1)
			&& !give(c -> c.pct == 0, c -> c.max)
			&& !give(c -> c.pct > 0, c -> c.pct))
			give(c -> true, c -> 1);
		return out;
	}

	// (table-layout: fixed, §17.5.2.1: the columns' widths, else the first row's cells', the rest shared)
	static function fixedLayout(g:Grid, w:Float):Array<Float> {
		var out = [for (_ in 0...g.columns) Math.NaN];
		for (c in 0...g.columns) {
			var col = g.colBoxes[c] ?? g.colGroups[c];
			if (col != null) {
				var v = Lens.resolve(col.style.model().width, w, Math.NaN);
				if (!Math.isNaN(v)) out[c] = v;
			}
		}
		for (cell in g.cells) {
			if (cell.row != 0) continue;
			var s = cell.box.style.model();
			var v = Lens.resolve(s.width, w, Math.NaN);
			if (Math.isNaN(v)) continue;
			if (!s.borderBox) v += bpx(cell.box) + delta(g, cell);
			var per = (v - g.spacingH * (cell.cols - 1)) / cell.cols;
			for (c in cell.col...cell.col + cell.cols) if (Math.isNaN(out[c])) out[c] = per;
		}
		var used = 0.0, auto = 0;
		for (v in out) if (Math.isNaN(v)) auto++ else used += v;
		if (auto > 0) {
			var share = Math.max(0, (w - used) / auto);
			return [for (v in out) Math.isNaN(v) ? share : v];
		}
		if (out.length == 0 || used >= w) return out;
		if (used == 0) return [for (_ in out) w / out.length];
		return [for (v in out) v * w / used];
	}

	// ---- layout

	function place(wrapper:Box, space:Space):Int {
		var frags = space.fragments;
		var t = tableOf(wrapper);
		var ts = (t ?? wrapper).style.model();
		var cb = space.width;
		var mt = BlockFlow.res(ts.margin[0], cb), mb = BlockFlow.res(ts.margin[2], cb);
		wrapper.topPositive = mt > 0 ? mt : 0;
		wrapper.topNegative = mt < 0 ? mt : 0;
		wrapper.bottomPositive = mb > 0 ? mb : 0;
		wrapper.bottomNegative = mb < 0 ? mb : 0;
		wrapper.through = false;
		if (t == null) {
			wrapper.marginLeft = wrapper.marginRight = 0;
			return frags.add(Fragments.BOX, wrapper, 0, 0);
		}
		var g = grid(t, space);
		var collapse = g.collapse;
		var edges = collapse ? collapsedEdges(g) : [
			ts.border[0] + BlockFlow.res(ts.padding[0], cb),
			ts.border[1] + BlockFlow.res(ts.padding[1], cb),
			ts.border[2] + BlockFlow.res(ts.padding[2], cb),
			ts.border[3] + BlockFlow.res(ts.padding[3], cb)
		];
		var cols = g.columns;
		var outerH = edges[1] + edges[3] + g.spacingH * Math.max(2, cols + 1);
		var minW = outerH, maxW = outerH;
		for (c in g.cols) {
			minW += c.min;
			maxW += c.pct > 0 ? c.min : c.max;
		}
		// (a table's width is its border box's, at least its min-content: §17.5.2)
		var ml = BlockFlow.auto(ts.margin[3], cb), mr = BlockFlow.auto(ts.margin[1], cb);
		// (a table's width and height are its border box's under box-sizing: border-box, as HTML's
		// sheet has <table>; else its content box's, its edges added)
		var spec = Lens.resolve(ts.width, cb, Math.NaN);
		if (!ts.borderBox && !Math.isNaN(spec)) spec += edges[1] + edges[3];
		// (table-layout: fixed with a width: the columns' widths, not their content, §17.5.2.1)
		var fixed = t.style.rare.tableLayout == "fixed" && !Math.isNaN(spec);
		if (fixed) minW = outerH;
		var minCaption = captionMin(wrapper, t, space, true);
		minW = Math.max(minW, minCaption);
		var w:Float;
		if (!Math.isNaN(space.fixedWidth)) w = Math.max(space.fixedWidth, minCaption) else if (!Math.isNaN(spec)) w = Math.max(spec, minW) else {
			var available = cb - (Math.isNaN(ml) ? 0 : ml) - (Math.isNaN(mr) ? 0 : mr);
			w = Math.max(minW, Math.min(maxW, available));
		}
		var maxSpec = Lens.resolve(ts.maxWidth, cb, Math.NaN), minSpec = Lens.resolve(ts.minWidth, cb, Math.NaN);
		if (!Math.isNaN(maxSpec) && w > maxSpec) w = Math.max(maxSpec, minW);
		if (!Math.isNaN(minSpec) && w < minSpec) w = minSpec;
		if (wrapper.blockLevel && !wrapper.floating) BlockFlow.solve(wrapper, w, ml, mr, cb, 0, wrapper.parent != null && wrapper.parent.style.rtl) else {
			wrapper.marginLeft = Math.isNaN(ml) ? 0 : ml;
			wrapper.marginRight = Math.isNaN(mr) ? 0 : mr;
		}
		var inner = w - outerH;
		var widths = fixed ? fixedLayout(g, inner) : distribute(g.cols, inner);
		var sum = Lambda.fold(widths, (x, a) -> x + a, 0.0);
		if (sum > inner) w += sum - inner;
		BlockFlow.alignRootFloat(wrapper, cb, w);
		// (column edges from the table's border box)
		var colX = [], x = edges[3] + g.spacingH;
		for (c in 0...cols) {
			colX.push(x);
			x += widths[c] + g.spacingH;
		}
		colX.push(x);
		// (insets use the wrapper's final size, after its rows and captions are laid out)
		var pending = new Positioned();
		var parts = space.child(cb, space.height);
		parts.positioned = parts.fixed = pending;
		// (the cells laid out at their columns' width, a block each)
		var rows = g.rows.length;
		for (cell in g.cells) {
			var cw = colX[cell.col + cell.cols] - colX[cell.col] - g.spacingH;
			var cs = parts.child(cw, Math.NaN);
			cs.fixedWidth = cw;
			if (collapse) cs.borders = cellBorders(g, cell);
			cell.box.uncache();
			var f = flow.child(cell.box, cs);
			cell.fragment = f;
			cell.contentHeight = Math.isNaN(cs.cellContentHeight) ? frags.height(f) : cs.cellContentHeight;
			cell.height = Math.max(frags.height(f), cell.contentHeight);
			cell.bottomEdge = bottomEdge(cell.box, cs);
			if (valign(cell.box) == "baseline") cell.baseline = cellBaseline(frags, f, cell.bottomEdge);
		}
		// (row heights: their own, their cells', the baseline's; a rowspan's last row taking what it needs)
		var rowH = [for (r in 0...rows) Math.max(0, Lens.resolve(g.rows[r].style.model().height, Math.NaN, 0))];
		var baselines = [for (_ in 0...rows) Math.NEGATIVE_INFINITY];
		var fallback = [for (_ in 0...rows) Math.POSITIVE_INFINITY];
		for (cell in g.cells) {
			if (!Math.isNaN(cell.baseline)) baselines[cell.row] = Math.max(baselines[cell.row], cell.baseline);
			fallback[cell.row] = Math.min(fallback[cell.row], cell.bottomEdge);
		}
		for (cell in g.cells) {
			var need = cell.rows == 1 ? cell.height : 0.0;
			if (!Math.isNaN(cell.baseline)) need = cell.rows == 1 ? need + baselines[cell.row] - cell.baseline : baselines[cell.row];
			rowH[cell.row] = Math.max(rowH[cell.row], need);
		}
		for (cell in g.cells) {
			if (cell.rows == 1) continue;
			var have = g.spacingV * (cell.rows - 1);
			for (r in cell.row...cell.row + cell.rows) have += rowH[r];
			var need = cell.height;
			if (!Math.isNaN(cell.baseline)) need += baselines[cell.row] - cell.baseline;
			if (need > have) rowH[cell.row + cell.rows - 1] += need - have;
		}
		for (r in 0...rows) if (g.rows[r].style.rare.visibility == "collapse") rowH[r] = 0;
		// (a grid without rows has no block-axis row spacing)
		var beforeRows = rows == 0 ? 0.0 : g.spacingV;
		var edgesV = edges[0] + edges[2] + beforeRows + g.spacingV * rows;
		var gridH = edgesV;
		for (h in rowH) gridH += h;
		var specH = Lens.resolve(ts.height, space.height, Math.NaN);
		if (!ts.borderBox && !Math.isNaN(specH)) specH += edges[0] + edges[2];
		if (!Math.isNaN(specH) && specH > gridH) {
			var extra = specH - gridH, total = gridH - edgesV;
			for (r in 0...rows) rowH[r] += total > 0 ? extra * rowH[r] / total : extra / rows;
			gridH = specH;
		}
		// (in a fragmentainer: its header rows, the body rows from where it resumes to where it breaks, its
		// footer rows; captions above only where it starts, below only where it ends)
		var shown = [for (_ in 0...rows) true];
		// (in a fragmentainer: where the table box starts in it; box-decoration-break: clone, each fragment its border,
		// padding and spacing whole, the bottom ones' room kept as it is)
		var tableTop = 0.0, clone = t.style.rare.boxDecorationBreak == "clone";
		// (rows broken inside here, their cells at their top)
		var split = [for (_ in 0...rows) false];
		var resumed = false, broken = false;
		var fr = space.fragmentation;
		if (fr != null) {
			var hEnd = 0, fStart = rows;
			while (hEnd < rows && g.header != null && g.rowGroups[hEnd] == g.header) hEnd++;
			while (fStart > hEnd && g.footer != null && g.rowGroups[fStart - 1] == g.footer) fStart--;
			// (a header or footer repeated only when it takes no more than a quarter of the fragmentainer, as
			// LayoutNG's; else its rows are the body's, broken as they are)
			inline function rowsH(a:Int, b:Int):Float {
				var h = 0.0;
				for (r in a...b) h += rowH[r] + g.spacingV;
				return h;
			}
			// (one not repeated still the table's head or foot: no break between it and the body's first or last row)
			var head = hEnd, foot = fStart;
			if (rowsH(0, hEnd) > fr.size / 4) hEnd = 0;
			if (rowsH(fStart, rows) > fr.size / 4) fStart = rows;
			var r0 = hEnd;
			if (fr.resume(wrapper) != null) {
				resumed = true;
				for (r in hEnd...fStart) {
					var at = fr.resume(g.rowGroups[r] ?? t);
					if (at != null && at.child == g.rows[r]) r0 = r;
				}
			}
			// (resumed: its top border, padding and spacing were in the fragmentainer before, sliced)
			var y = space.pageTop;
			if (!resumed) for (k in wrapper.children()) if (k != t && k.style.rare.captionSide != "bottom") {
				var probe = space.child(w, Math.NaN);
				probe.positioned = probe.fixed = new Positioned();
				var f = flow.child(k, probe);
				y += k.topPositive + k.topNegative + frags.height(f) + k.bottomPositive + k.bottomNegative;
			} else if (k == t) break;
			tableTop = y;
			// (cloned: its border and padding again, its spacing not)
			if (!resumed) y += edges[0] + beforeRows else if (clone) y += edges[0];
			for (r in 0...hEnd) y += rowH[r] + g.spacingV;
			var footerH = edges[2] + space.reserve;
			for (r in fStart...rows) footerH += rowH[r] + g.spacingV;
			var end = fStart, prev = y;
			for (r in r0...fStart) {
				// (between rows: not where a cell spans them)
				if (r > r0 && !(hEnd == 0 && r == head) && !(fStart == rows && r == foot) && !Lambda.exists(g.cells, c -> c.row < r && c.row + c.rows > r)
					&& (fr.between(g.rowGroups[r] ?? t, g.rows[r - 1], g.rows[r], prev + footerH) || fr.stopped)) {
					end = r;
					broken = true;
					break;
				}
				// (a row past the fragmentainer's end, or resumed inside: its cells broken in parallel, each at its own
				// break, the row to the fragmentainer's end; not one a cell spans into or out of)
				var row = g.rows[r], at = fr.resume(row);
				var inside = r == r0 && at != null && at.parallel != null;
				if ((inside || y + rowH[r] + footerH > fr.size + 0.01) && !Lambda.exists(g.cells, c -> c.rows > 1 && c.row <= r && c.row + c.rows > r)) {
					var whole = rowH[r];
					// (its cells keep room for the footer rows, and for its bottom edges only when cloned: sliced at the break)
					var s = splitRow(g, r, parts, fr, y, clone ? footerH : footerH - edges[2], colX);
					var going = s.tokens.iterator().hasNext() && s.progress;
					// (under a repeated header or above a repeated footer, a monolithic overflow not carried on: the row
					// whole here, past the end, the next after the header there, as LayoutNG's)
					if (going && (hEnd > 0 || fStart < rows) && overflowOnly(s.tokens)) going = false;
					split[r] = inside;
					// (resumed: as tall as its cells' rest; else its height as laid out, the break not taken here: as it
					// would go on, for the opportunities after it)
					if (inside) rowH[r] = s.height else rowH[r] = Math.max(rowH[r], s.height);
					// (its cells' breaks kept the footer's room: broken, they reach the fragmentainer's end, so it fits there)
					if (going && (fr.split(row, s.tokens, Math.min(y + s.height + footerH, fr.size), whole > fr.size) || fr.stopped)) {
						split[r] = true;
						rowH[r] = Math.max(s.height, fr.size - footerH - y);
						end = r + 1;
						broken = true;
						fr.placed(y + rowH[r] + footerH);
						break;
					}
					// (not taken here: its cells go on past the fragmentainer's end, the opportunities after it there too, as
					// content past the end before them (floated's floor))
					if (going) fr.floated(fr.size + y + s.height);
				}
				prev = y + rowH[r];
				fr.placed(prev + footerH);
				y = prev + g.spacingV;
			}
			for (r in hEnd...fStart) shown[r] = r >= r0 && r < end;
		}
		var rowY = [], y = !resumed ? edges[0] + beforeRows : clone ? edges[0] : 0;
		for (r in 0...rows) {
			rowY.push(y);
			if (shown[r]) y += rowH[r] + g.spacingV;
		}
		rowY.push(y);
		// (broken: its bottom spacing, padding and border in a later fragmentainer, sliced; to the fragmentainer's end, as
		// a block's)
		if (fr != null) gridH = !broken ? y + edges[2] : clone ? y - g.spacingV + edges[2] : Math.max(y - g.spacingV, fr.size - tableTop);
		// (fragments: the table box; its column groups and columns, row groups, rows and cells, in
		// the order their backgrounds paint, §17.5.1)
		var tf = frags.add(Fragments.BOX, t, w, gridH);
		if ((resumed || broken) && !clone) frags.setRange(tf, resumed ? Box.NO_START : 0, broken ? Box.NO_END : 0);
		var tg = g.borders ?? new TableGrid(cols, rows);
		for (c in 0...cols) {
			tg.x.push(colX[c]);
			tg.widths.push(widths[c]);
		}
		for (r in 0...rows) {
			tg.y.push(rowY[r]);
			tg.heights.push(rowH[r]);
		}
		if (fr != null) {
			tg.shown = shown;
			tg.previous = t.table;
		}
		t.table = tg;
		tg.fragment = tf;
		tg.spacing = g.spacingH + g.spacingV;
		var mark = collapse ? Box.COLLAPSED : 0;
		t.flags = (t.flags & ~Box.COLLAPSED) | mark;
		var top = rows > 0 ? rowY[0] : edges[0], bottom = rows > 0 ? rowY[rows] - g.spacingV : edges[0];
		var c = 0;
		while (c < cols) {
			var group = g.colGroups[c];
			var end = c + 1;
			while (end < cols && g.colGroups[end] == group) end++;
			if (group != null) {
				var gf = frags.add(Fragments.BOX, group, colX[end] - g.spacingH - colX[c], bottom - top);
				frags.adopt(tf, gf, colX[c], top);
				group.flags |= mark;
			}
			c = end;
		}
		for (c in 0...cols) {
			var col = g.colBoxes[c];
			if (col == null) continue;
			var cf = frags.add(Fragments.BOX, col, widths[c], bottom - top);
			frags.adopt(tf, cf, colX[c], top);
			col.flags |= mark;
		}
		var groupFrag = -1, groupBox:Null<Box> = null, groupTop = 0.0;
		var rowFrags = [];
		for (r in 0...rows) {
			var group = g.rowGroups[r];
			if (group != groupBox) {
				groupBox = group;
				groupFrag = -1;
				if (group != null) {
					var end = r, any = false;
					while (end < rows && g.rowGroups[end] == group) {
						if (shown[end]) any = true;
						end++;
					}
					groupTop = rowY[r];
					if (any) {
						groupFrag = frags.add(Fragments.BOX, group, colX[cols] - g.spacingH - colX[0], rowY[end] - g.spacingV - rowY[r]);
						frags.adopt(tf, groupFrag, colX[0], rowY[r]);
					}
					group.flags |= mark;
				}
			}
			if (!shown[r]) {
				rowFrags.push(-1);
				continue;
			}
			var row = g.rows[r];
			row.flags |= mark;
			var rf = frags.add(Fragments.BOX, row, colX[cols] - g.spacingH - colX[0], rowH[r]);
			if (groupFrag >= 0) frags.adopt(groupFrag, rf, 0, rowY[r] - groupTop) else frags.adopt(tf, rf, colX[0], rowY[r]);
			rowFrags.push(rf);
		}
		for (cell in g.cells) {
			if (!shown[cell.row]) continue;
			var f = cell.fragment;
			var h = rowY[cell.row + cell.rows] - g.spacingV - rowY[cell.row];
			var shift = split[cell.row] ? 0.0 : switch valign(cell.box) {
				case "top": 0.0;
				case "bottom": h - cell.contentHeight;
				case "middle": (h - cell.contentHeight) / 2;
				case _: Math.isNaN(cell.baseline) ? 0.0 : baselines[cell.row] - cell.baseline;
			}
			if (shift != 0) {
				var k = frags.first(f);
				while (k >= 0) {
					frags.moveTo(k, frags.x(k), frags.y(k) + shift);
					k = frags.next(k);
				}
			}
			// (its column's width even where its padding and borders are wider: they overflow, as browsers lay it out)
			frags.resize(f, colX[cell.col + cell.cols] - g.spacingH - colX[cell.col], h);
			cell.box.flags = (cell.box.flags & ~(Box.COLLAPSED | Box.EMPTY)) | mark | (empty(cell.box) ? Box.EMPTY : 0);
			frags.adopt(rowFrags[cell.row], f, colX[cell.col] - colX[0], 0);
		}
		// (the wrapper: captions above and below the table, at its width)
		var wf = frags.add(Fragments.BOX, wrapper, w, 0);
		var wy = 0.0, baseline = Math.NaN;
		var k = wrapper.first;
		while (k != null) {
			if (k == t) {
				frags.adopt(wf, tf, 0, wy);
				for (r in 0...rows) if (shown[r]) {
					// (a row without a baseline-aligned cell's content uses its lowest content edge after sizing)
					var b = baselines[r] == Math.NEGATIVE_INFINITY ? Math.max(0, rowH[r] - fallback[r]) : baselines[r];
					baseline = wy + rowY[r] + b;
					break;
				}
				wy += gridH;
			} else if (resumed && k.style.rare.captionSide != "bottom" || broken && k.style.rare.captionSide == "bottom") {
				// (a caption above where it doesn't start, below where it doesn't end: none)
			} else {
				// (a caption: a block in the table's width)
				var f = flow.child(k, parts.child(w, Math.NaN));
				var top = k.topPositive + k.topNegative;
				frags.adopt(wf, f, k.marginLeft, wy + top);
				wy += top + frags.height(f) + k.bottomPositive + k.bottomNegative;
			}
			k = k.next;
		}
		frags.resize(wf, w, wy);
		if (!Math.isNaN(baseline)) frags.setBaseline(wf, baseline);
		if (pending.boxes.length > 0) placePositioned(wrapper, wf, space, pending, resumed, broken);
		return wf;
	}

	function placePositioned(wrapper:Box, wf:Int, space:Space, pending:Positioned, resumed:Bool, broken:Bool) {
		var frags = space.fragments;
		var root = wrapper.parent == null;
		var contained = wrapper.style.containment.containingBlock;
		var owner = wrapper.style.positioned || contained;
		var abs = new Positioned(), fixed = new Positioned();
		var absTarget = owner || root ? abs : space.positioned;
		var fixedTarget = contained ? abs : space.fixed ?? (root ? fixed : null);
		for (k in 0...pending.boxes.length) {
			var from = pending.fragments[k], at = from;
			// (only the cell or caption fragments that made it into this wrapper)
			while (at >= 0 && at != wf) at = frags.parent(at);
			if (at < 0) continue;
			var b = pending.boxes[k];
			var list = b.style.position == "fixed" ? fixedTarget : absTarget;
			if (list != null) list.add(b, from, pending.xs[k], pending.ys[k], pending.aligns[k]);
		}
		if (owner) flow.place(abs, wf, space, 0, 0, frags.width(wf), frags.height(wf), resumed || broken);
		if (root && (!owner || fixed.boxes.length > 0)) {
			var off = space.fragmentation == null ? BlockFlow.offset(wrapper, space.width, space.height) : {x: 0.0, y: 0.0};
			var x = -wrapper.marginLeft - off.x, y = -wrapper.topPositive - wrapper.topNegative - off.y;
			if (!owner) flow.place(abs, wf, space, x, y, space.width, space.height, resumed);
			flow.place(fixed, wf, space, x, y, space.width, space.height);
		}
	}

	// (a row's cells laid out from its top in the fragmentainer, each a parallel flow with its own breaks (one
	// that ended before: an empty continuation); their tallest's height, the tokens of those that go on, whether
	// any made progress (none: a break inside would take nothing of it, the row goes whole))
	function splitRow(g:Grid, r:Int, space:Space, fr:Fragmentation, top:Float, reserve:Float, colX:Array<Float>):{height:Float, tokens:ObjectMap<Box, BreakToken>,
			progress:Bool} {
		var frags = space.fragments, tokens = new ObjectMap<Box, BreakToken>(), height = 0.0, progress = false;
		for (cell in g.cells) if (cell.row == r) {
			var cw = colX[cell.col + cell.cols] - colX[cell.col] - g.spacingH;
			var sub = fr.parallel(g.rows[r], cell.box);
			var f:Int;
			if (sub == null) {
				f = frags.add(Fragments.BOX, cell.box, cw, 0);
				frags.setRange(f, Box.NO_START, 0);
			} else {
				function lay():Int {
					var cs = space.child(cw, Math.NaN);
					cs.fixedWidth = cw;
					if (g.collapse) cs.borders = cellBorders(g, cell);
					cs.fragmentation = sub;
					cs.pageTop = top;
					cs.reserve = reserve;
					cell.box.uncache();
					return flow.child(cell.box, cs);
				}
				f = lay();
				if (sub.decide()) f = lay();
				var t = sub.token();
				// (progress: a cell ended here, or took more of its content than before)
				var was = fr.resume(g.rows[r]), before = was != null && was.parallel != null ? was.parallel.get(cell.box) : null;
				var had = before == null ? 0.0 : before.resumes.get(cell.box).consumed;
				if (t == null || t.resumes.get(cell.box).consumed > had + 0.01) progress = true;
				if (t != null) tokens.set(cell.box, t);
				for (d in sub.deferred) fr.defer(d);
			}
			cell.fragment = f;
			cell.height = frags.height(f);
			height = Math.max(height, cell.height);
		}
		return {height: height, tokens: tokens, progress: progress};
	}

	// (cells' tokens that only go on with a monolithic box's overflow: no line, no float, nothing past their content)
	static function overflowOnly(tokens:haxe.ds.ObjectMap<Box, BreakToken>):Bool {
		var mono = false;
		for (t in tokens) {
			if (t.floats.iterator().hasNext()) return false;
			for (r in t.resumes) {
				if (r.line == BreakToken.MONO) mono = true;
				else if (r.line != -1) return false;
			}
		}
		return mono;
	}

	// (a cell's border widths in the collapsing model: its lines' parts inside it, the widest on each side)
	static function cellBorders(g:Grid, cell:Cell):Array<Float> {
		var tg = g.borders, out = [0.0, 0.0, 0.0, 0.0];
		for (c in cell.col...cell.col + cell.cols) {
			out[0] = Math.max(out[0], tg.half(tg.hPainted(tg.h(cell.row, c)), true));
			out[2] = Math.max(out[2], tg.half(tg.hPainted(tg.h(cell.row + cell.rows, c)), false));
		}
		for (r in cell.row...cell.row + cell.rows) {
			out[3] = Math.max(out[3], tg.half(tg.vPainted(tg.v(r, cell.col)), true));
			out[1] = Math.max(out[1], tg.half(tg.vPainted(tg.v(r, cell.col + cell.cols)), false));
		}
		return out;
	}

	// (a cell's bottom border and padding: a cell without a line aligns its content box's bottom)
	static function bottomEdge(b:Box, space:Space):Float {
		var s = b.style.model();
		return (space.borders != null ? space.borders[2] : s.border[2]) + BlockFlow.res(s.padding[2], space.width);
	}

	static function cellBaseline(frags:Fragments, f:Int, bottomEdge:Float):Float {
		var baseline = BlockFlow.firstBaseline(frags, f);
		if (!Math.isNaN(baseline)) return baseline;
		// (a cell with in-flow content but no line or table row aligns its content box's bottom)
		var child = frags.first(f);
		while (child >= 0) {
			var box = frags.box(child);
			if (!box.floating && !box.absolute) return frags.height(f) - bottomEdge;
			child = frags.next(child);
		}
		return Math.NaN;
	}

	static function valign(b:Box):String
		return switch b.style.verticalAlign().kind {
			case "top" | "text-top": "top";
			case "bottom" | "text-bottom": "bottom";
			case "middle": "middle";
			case _: "baseline";
		}

	// (no in-flow content: empty-cells hides its background and borders, §17.6.1.1)
	static function empty(b:Box):Bool {
		var c = b.first;
		while (c != null) {
			if (c.kind != Text || !~/^[ \t\n\r\x0C]*$/.match(c.text)) return false;
			c = c.next;
		}
		return true;
	}
}

// a column for distribute: its min-content and max-content widths, a percentage (0: none), whether a width is set
typedef TableColumn = {min:Float, max:Float, pct:Float, fixed:Bool};
private typedef Cell = {box:Box, row:Int, col:Int, rows:Int, cols:Int, fragment:Int, height:Float, contentHeight:Float, baseline:Float, bottomEdge:Float};

private class Grid {
	public final rows:Array<Box> = [];
	public final rowGroups:Array<Null<Box>> = [];
	public final colBoxes:Array<Null<Box>> = [];
	public final colGroups:Array<Null<Box>> = [];
	public final cells:Array<Cell> = [];
	public final cols:Array<TableColumn> = [];
	public final slots:Array<Array<Bool>> = [];
	public var columns = 0;
	public var spacingH = 0.0;
	public var spacingV = 0.0;
	public var collapse = false;
	public var exact = false;
	public var borders:Null<TableGrid> = null;
	// (its header and footer groups: repeated on every page it is on)
	public var header:Null<Box> = null;
	public var footer:Null<Box> = null;

	public function new() {}

	public function taken(r:Int, c:Int):Bool
		return r < slots.length && c < slots[r].length && slots[r][c];

	public function take(r:Int, c:Int) {
		while (slots.length <= r) slots.push([]);
		var row = slots[r];
		while (row.length <= c) row.push(false);
		row[c] = true;
	}
}
