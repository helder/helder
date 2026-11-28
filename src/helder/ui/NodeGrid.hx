package helder.ui;

import helder.css.CssTerm;
import helder.ui.Grid;
import helder.ui.box.BoxRare;

// A helder.ui style's grid as the terms the engine's GridFlow reads (the
// cascade's computed values): its tracks, areas, auto-flow and an item's
// lines (NodeBoxes).
@:access(helder.ui.box.BoxRare)
class NodeGrid {
	// (whether a style has any of it: those made each time, not shared)
	public static function has(s:Style):Bool
		return s.display == Grid || s.gridRow != GridPlacement.AUTO || s.gridColumn != GridPlacement.AUTO;

	public static function fill(s:Style, rare:BoxRare) {
		if (s.display == Grid) {
			rare.gridTemplateColumns = s.gridTemplateColumns.length == 0 ? [Keyword("none")] : [for (t in s.gridTemplateColumns) track(t)];
			rare.gridTemplateRows = s.gridTemplateRows.length == 0 ? [Keyword("none")] : [for (t in s.gridTemplateRows) track(t)];
			rare.gridAutoColumns = [track(s.gridAutoColumns)];
			rare.gridAutoRows = [track(s.gridAutoRows)];
			rare.gridAutoFlow = switch s.gridAutoFlow {
				case Column: [Keyword("column")];
				case RowDense: [Keyword("dense")];
				case ColumnDense: [Keyword("column"), Keyword("dense")];
				case _: [Keyword("row")];
			}
			var a = s.gridTemplateAreas;
			if (a != null) rare.gridTemplateAreas = areas(a);
		}
		var r = lines(s.gridRow), c = lines(s.gridColumn);
		rare.gridLines = [r[0], r[1], c[0], c[1]];
	}

	static function size(t:TrackSize):CssTerm
		return switch t {
			case Px(v): Dimension(v, "px");
			case Percent(p): Percentage(p);
			case Fr(f): Dimension(f, "fr");
			case Auto: Keyword("auto");
			case MinContent: Keyword("min-content");
			case MaxContent: Keyword("max-content");
		}

	static function track(t:Track):CssTerm
		return t.min == t.max || t.min == Auto && t.max.match(Fr(_)) ? size(t.max) : Func("minmax", [size(t.min), Delim(","), size(t.max)]);

	// (the rows' strings again, "." where no area is)
	static function areas(a:GridAreas):Array<CssTerm> {
		var cells = [for (_ in 0...a.rows) [for (_ in 0...a.columns) "."]];
		for (name => r in a.areas)
			for (y in r.row...r.rowEnd)
				for (x in r.col...r.colEnd)
					cells[y][x] = name;
		return a.rows == 0 ? [Keyword("none")] : [for (row in cells) Str(row.join(" "))];
	}

	// (start and end: a line's number or name, a span on the side without a line, else auto)
	static function lines(p:GridPlacement):Array<Array<CssTerm>> {
		var auto = [Keyword("auto")], span:Array<CssTerm> = [Keyword("span"), Number(p.span, true)];
		var start:Array<CssTerm> = p.startName != null ? [Ident(p.startName)] : p.start != 0 ? [Number(p.start, true)] : null;
		var end:Array<CssTerm> = p.endName != null ? [Ident(p.endName)] : p.end != 0 ? [Number(p.end, true)] : null;
		if (start == null && end == null) return [p.span > 1 ? span : auto, auto];
		if (start == null) return [p.span > 1 ? span : auto, end];
		if (end == null) return [start, p.span > 1 ? span : auto];
		return [start, end];
	}
}
