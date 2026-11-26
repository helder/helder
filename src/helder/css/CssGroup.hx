package helder.css;

import helder.css.CssProperty;
import helder.css.CssTerm;

// A computed style's group of properties (CssGroups' classes): typed
// values, interned per document so equal groups are one object, and
// never changed once interned. others: the values a field's type can't
// hold (a function where keywords go, a math function left unresolved),
// as terms.
class CssGroup {
	var others:Null<Map<Int, Array<CssTerm>>> = null;
	// (its number in the document's intern table; -1 until interned)
	@:allow(helder.css) var id = -1;

	// The property's computed value as terms.
	public function terms(p:CssProperty):Array<CssTerm>
		throw "abstract";

	function copy():CssGroup
		throw "abstract";

	function set(p:CssProperty, t:Array<CssTerm>, intern:CssIntern) {}

	function same(o:CssGroup):Bool
		return false;

	function hash(intern:CssIntern):Int
		return 0;

	function keyword(p:CssProperty, t:Array<CssTerm>):Int {
		switch t {
			case [Keyword(k)]:
				var i = CssProperties.keywords(p).indexOf(k);
				if (i >= 0) return i;
			case _:
		}
		keep(p, t);
		return -2;
	}

	function number(p:CssProperty, t:Array<CssTerm>, integer:Bool):Float {
		switch t {
			case [Number(v, i)] if (i == integer): return v;
			case [Keyword(k)] if (CssProperties.keywords(p).indexOf(k) >= 0): return Math.NaN;
			case _:
		}
		keep(p, t);
		return Math.NaN;
	}

	// (after number(): -1 a number, a keyword's index, -2 in others)
	function numberKeyword(p:CssProperty, t:Array<CssTerm>):Int {
		if (others != null && others.exists(p)) return -2;
		return switch t {
			case [Keyword(k)]: CssProperties.keywords(p).indexOf(k);
			case _: -1;
		}
	}

	function other<T>(p:CssProperty, t:Array<CssTerm>, sentinel:T):T {
		keep(p, t);
		return sentinel;
	}

	// (others is shared with the copy it came from: changed as a new map)
	function keep(p:CssProperty, t:Array<CssTerm>) {
		var m = others == null ? new Map() : others.copy();
		m.set(p, t);
		others = m;
	}

	function forget(p:CssProperty) {
		if (others == null || !others.exists(p)) return;
		var m = others.copy();
		m.remove(p);
		others = Lambda.count(m) == 0 ? null : m;
	}

	function sameOthers(g:CssGroup):Bool {
		if (others == null || g.others == null) return others == g.others;
		if (Lambda.count(others) != Lambda.count(g.others)) return false;
		for (k => v in others) {
			var w = g.others.get(k);
			if (w == null || CssIntern.key(v) != CssIntern.key(w)) return false;
		}
		return true;
	}

	static inline function floatHash(v:Float):Int
		return v != v ? 7 : Std.int(v * 64) ^ Std.int(v * 7919);
}
