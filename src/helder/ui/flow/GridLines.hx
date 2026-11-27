package helder.ui.flow;

import helder.css.CssTerm;
import helder.ui.box.BoxStyle;

// An axis's explicit grid lines and their names (the template's, and
// each named area's name-start and name-end), and an item's placement on
// it resolved (Grid 1 §8.3): a line by number, by name (the nth with it;
// past the explicit grid's lines, the implicit ones all have it), name
// alone its name-start or name-end line first; a span from the other
// side, of lines or of a name's; then the conflicts settled (§8.3.1).
// Lines from 0 at the explicit grid's start, negative before it.
class GridLines {
	public static inline var AUTO = -0x40000000;
	static inline var LINES = 32767;

	// (explicit tracks; lines 0 to count)
	public final count:Int;
	final names:Array<Array<String>>;

	public function new(count:Int, names:Array<Array<String>>) {
		this.count = count;
		this.names = names;
	}

	// An item's start line (AUTO: placed automatically) and span.
	public function resolve(st:BoxStyle, p:String):{start:Int, span:Int} {
		var k = p == "grid-row" ? 0 : 2;
		var s = GridLine.of(st.rare.gridLines[k]), e = GridLine.of(st.rare.gridLines[k + 1]);
		if (s.span && e.span) e = GridLine.NONE;
		if (s.definite && e.definite) {
			var a = line(s, false), b = line(e, true);
			if (b == a) b = a + 1;
			return b < a ? {start: b, span: a - b} : {start: a, span: b - a};
		}
		if (s.definite) {
			var a = line(s, false);
			return {start: a, span: e.span ? reach(e, a, true) - a : 1};
		}
		if (e.definite) {
			var b = line(e, true);
			var a = s.span ? reach(s, b, false) : b - 1;
			return {start: a, span: b - a};
		}
		var span = s.span ? s : e.span ? e : GridLine.NONE;
		return {start: AUTO, span: span.name != null ? 1 : span.n};
	}

	// An absolutely positioned item's lines (AUTO: its padding edge's): as resolve's, a span from a line
	// that's there, but no implicit ones made.
	public function lines(st:BoxStyle, p:String):{from:Int, to:Int} {
		var k = p == "grid-row" ? 0 : 2;
		var s = GridLine.of(st.rare.gridLines[k]), e = GridLine.of(st.rare.gridLines[k + 1]);
		var a = s.definite ? line(s, false) : AUTO, b = e.definite ? line(e, true) : AUTO;
		if (a != AUTO && b == AUTO && e.span) b = reach(e, a, true);
		if (b != AUTO && a == AUTO && s.span) a = reach(s, b, false);
		return {from: a, to: b};
	}

	// (a line's index: by number from either end, or the nth of a name's)
	function line(l:GridLine, end:Bool):Int {
		var n = l.n > LINES ? LINES : l.n < -LINES ? -LINES : l.n;
		if (l.name == null) return n > 0 ? n - 1 : count + 1 + n;
		var name = l.name;
		if (n == 0) {
			if (has(name + (end ? "-end" : "-start"))) name += end ? "-end" : "-start";
			n = 1;
		}
		var found = 0;
		if (n > 0) {
			for (i in 0...count + 1) if (named(i, name) && ++found == n) return i;
			return count + n - found;
		}
		var i = count;
		while (i >= 0) {
			if (named(i, name) && ++found == -n) return i;
			i--;
		}
		return -(-n - found);
	}

	// (the line a span reaches from a line, forward or back)
	function reach(l:GridLine, from:Int, forward:Bool):Int {
		var n = l.n > LINES ? LINES : l.n;
		if (l.name == null) return forward ? from + n : from - n;
		var found = 0;
		if (forward) {
			for (i in (from < 0 ? 0 : from + 1)...count + 1) if (named(i, l.name) && ++found == n) return i;
			return (from > count ? from : count) + n - found;
		}
		var i = (from > count ? count + 1 : from) - 1;
		while (i >= 0) {
			if (named(i, l.name) && ++found == n) return i;
			i--;
		}
		return (from < 0 ? from : 0) - (n - found);
	}

	inline function named(i:Int, name:String):Bool
		return i >= 0 && i < names.length && names[i].indexOf(name) >= 0;

	function has(name:String):Bool {
		for (l in names) if (l.indexOf(name) >= 0) return true;
		return false;
	}
}

// One side of a placement (grid-row-start and the rest): auto, a line (a
// number, a name, or the two), or a span (of lines, or of a name's).
class GridLine {
	public static final NONE = new GridLine(false, false, 1, null);

	public final definite:Bool;
	public final span:Bool;
	// (0: none given, with a name)
	public final n:Int;
	public final name:Null<String>;

	function new(definite:Bool, span:Bool, n:Int, name:Null<String>) {
		this.definite = definite;
		this.span = span;
		this.n = n;
		this.name = name;
	}

	public static function of(terms:Array<CssTerm>):GridLine {
		var span = false, n = 0, name:Null<String> = null;
		for (t in terms) switch t {
			case Keyword("span"): span = true;
			case Number(v, _): n = Std.int(v);
			case Ident(v): name = v;
			case _:
		}
		if (span) return new GridLine(false, true, n == 0 ? 1 : n, name);
		if (n == 0 && name == null) return NONE;
		return new GridLine(true, false, n, name);
	}
}
