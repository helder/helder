package helder.css;

import helder.css.CssSelector;

// A selector's specificity (a, b, c): IDs; classes, attributes and
// pseudo-classes; types and pseudo-elements. One Int, 10 bits each
// (saturating at 1023), so comparing two is comparing Ints.
abstract CssSpecificity(Int) {
	public static var ZERO(get, never):CssSpecificity;

	static inline function get_ZERO():CssSpecificity
		return new CssSpecificity(0);

	public var a(get, never):Int;
	public var b(get, never):Int;
	public var c(get, never):Int;

	inline function new(v:Int)
		this = v;

	public static function make(a:Int, b:Int, c:Int):CssSpecificity
		return new CssSpecificity((sat(a) << 20) | (sat(b) << 10) | sat(c));

	static inline function sat(v:Int):Int
		return v > 1023 ? 1023 : v;

	inline function get_a():Int
		return this >> 20;

	inline function get_b():Int
		return (this >> 10) & 1023;

	inline function get_c():Int
		return this & 1023;

	public function add(o:CssSpecificity):CssSpecificity
		return make(a + o.a, b + o.b, c + o.c);

	public inline function compare(o:CssSpecificity):Int
		return this - o.toInt();

	public inline function toInt():Int
		return this;

	public function toString():String
		return '($a, $b, $c)';

	// the most specific of a list's
	public static function most(list:Array<CssSelector>):CssSpecificity {
		var m = ZERO;
		for (s in list)
			if (s.specificity.toInt() > m.toInt()) m = s.specificity;
		return m;
	}

	// a simple selector's (§17: :is(), :not() and :has() their most
	// specific argument's, :where() none, :nth-child(An+B of S) a
	// pseudo-class's and S's most specific)
	public static function of(s:CssSimple):CssSpecificity
		return switch s {
			case Id(_): make(1, 0, 0);
			case Class(_) | Attribute(_, _, _, _, _): make(0, 1, 0);
			case Type(_, _): make(0, 0, 1);
			case Universal(_): ZERO;
			case Pseudo(Is(l) | Not(l) | Has(l)): most(l);
			case Pseudo(Where(_)): ZERO;
			case Pseudo(NthChild(_, of) | NthLastChild(_, of)): make(0, 1, 0).add(of == null ? ZERO : most(of));
			case Pseudo(_): make(0, 1, 0);
		}
}
