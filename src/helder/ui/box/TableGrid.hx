package helder.ui.box;

// A table box's grid as layout leaves it for paint (CSS 2.1 §17.5, §17.6):
// its columns' and rows' places in the table's border box, and in the
// collapsing border model each grid line's segment's border (§17.6.2),
// what wins of the cells', rows', row groups', columns' and the table's.
class TableGrid {
	public final columns:Int;
	public final rows:Int;
	// column c from x[c] to x[c] + widths[c]; row r from y[r] to y[r] + heights[r]
	public final x:Array<Float> = [];
	public final widths:Array<Float> = [];
	public final y:Array<Float> = [];
	public final heights:Array<Float> = [];
	public var collapse(default, null) = false;
	// no pixel grid (print): its lines split in exact halves
	public var exact = false;
	// the table box's fragment, and its spacing between cells
	public var fragment = -1;
	// (in fragmentainers: the rows on this fragment, and the grid of the table's fragment before (a page's
	// layout each; paint finds its fragment's by it))
	public var shown:Null<Array<Bool>> = null;
	public var previous:Null<TableGrid> = null;

	// the grid of a table's fragment (its latest layout's when none is that fragment's)
	public static function of(latest:Null<TableGrid>, fragment:Int):Null<TableGrid> {
		var g = latest;
		while (g != null && g.fragment != fragment) g = g.previous;
		return g ?? latest;
	}

	// (a line's part on one side of it: whole pixels, floor(w/2) above it and to its left, the rest below and to
	// its right, as Chromium's; exactly half without a pixel grid, as WeasyPrint's)
	public function half(w:Float, after:Bool):Float
		return exact ? w / 2 : after ? Math.ceil(w / 2) : Math.floor(w / 2);

	public inline function hides(row:Int):Bool
		return shown != null && !shown[row];
	public var spacing = 0.0;
	// (the horizontal lines' segments: (rows + 1) * columns, line r above row r; the vertical
	// ones': rows * (columns + 1), line c left of column c)
	public final hWidth:Array<Float> = [];
	public final hStyle:Array<String> = [];
	public final hColor:Array<Int> = [];
	public final vWidth:Array<Float> = [];
	public final vStyle:Array<String> = [];
	public final vColor:Array<Int> = [];

	public function new(columns:Int, rows:Int) {
		this.columns = columns;
		this.rows = rows;
	}

	public function collapsing() {
		collapse = true;
		for (_ in 0...(rows + 1) * columns) {
			hWidth.push(0);
			hStyle.push("none");
			hColor.push(0);
		}
		for (_ in 0...rows * (columns + 1)) {
			vWidth.push(0);
			vStyle.push("none");
			vColor.push(0);
		}
	}

	public inline function h(line:Int, column:Int):Int
		return line * columns + column;

	public inline function v(row:Int, line:Int):Int
		return row * (columns + 1) + line;

	// (§17.6.2.1: hidden wins, none loses, then the wider, the stronger style, the earlier
	// origin (a cell's over a row's over a row group's over a column's over a column group's
	// over the table's): those already there came from an origin as strong or stronger)
	public static function wins(width:Float, style:String, oldWidth:Float, oldStyle:String):Bool {
		if (oldStyle == "hidden") return false;
		if (style == "hidden") return true;
		if (style == "none" || width <= 0) return false;
		if (oldStyle == "none" || oldWidth <= 0) return true;
		if (width != oldWidth) return width > oldWidth;
		return STRENGTH.indexOf(style) < STRENGTH.indexOf(oldStyle);
	}

	static final STRENGTH = ["double", "solid", "dashed", "dotted", "ridge", "outset", "groove", "inset"];

	public function offerH(line:Int, column:Int, width:Float, style:String, color:Int) {
		var k = h(line, column);
		if (wins(width, style, hWidth[k], hStyle[k])) {
			hWidth[k] = width;
			hStyle[k] = style;
			hColor[k] = color;
		}
	}

	public function offerV(row:Int, line:Int, width:Float, style:String, color:Int) {
		var k = v(row, line);
		if (wins(width, style, vWidth[k], vStyle[k])) {
			vWidth[k] = width;
			vStyle[k] = style;
			vColor[k] = color;
		}
	}

	// a segment's width as painted (hidden and none: nothing)
	public inline function hPainted(k:Int):Float
		return hStyle[k] == "none" || hStyle[k] == "hidden" ? 0 : hWidth[k];

	public inline function vPainted(k:Int):Float
		return vStyle[k] == "none" || vStyle[k] == "hidden" ? 0 : vWidth[k];
}
