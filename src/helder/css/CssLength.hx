package helder.css;

import helder.css.CssCalc;
import helder.css.CssTerm;

enum abstract CssLengthKind(Int) {
	// value in px
	var Px;
	// value in %
	var Percent;
	// a number (line-height's, tab-size's)
	var Plain;
	// a keyword (auto, normal, none...)
	var Word;
	// a math function mixing lengths and percentages: only layout can finish it
	var Mixed;
	// a length in a unit not resolved without layout or fonts (ex, cqw...): value in unit
	var Relative;
	// not one term (in the group's others)
	var Other;
}

// A computed length, percentage, number or keyword, decoded from its one
// term. Interned per document: equal values are one object.
class CssLength {
	public static final OTHER = new CssLength(Other, 0, "", null, null, []);

	public final kind:CssLengthKind;
	public final value:Float;
	public final unit:String;
	public final keyword:Null<String>;
	public final calc:Null<CssCalcNode>;
	public final terms:Array<CssTerm>;
	@:allow(helder.css) var id = -1;

	function new(kind:CssLengthKind, value:Float, unit:String, keyword:Null<String>, calc:Null<CssCalcNode>, terms:Array<CssTerm>) {
		this.kind = kind;
		this.value = value;
		this.unit = unit;
		this.keyword = keyword;
		this.calc = calc;
		this.terms = terms;
	}

	// (null: not one length-like term)
	@:allow(helder.css)
	static function of(t:Array<CssTerm>):Null<CssLength>
		return t.length != 1 ? null : switch t[0] {
			case Dimension(v, "px"): new CssLength(Px, v, "px", null, null, t);
			case Dimension(v, u): new CssLength(Relative, v, u, null, null, t);
			case Percentage(v): new CssLength(Percent, v, "%", null, null, t);
			case Number(v, _): new CssLength(Plain, v, "", null, null, t);
			case Keyword(k): new CssLength(Word, 0, "", k, null, t);
			case Calc(n, _, _): new CssLength(Mixed, 0, "", null, n, t);
			case _: null;
		}

	// The length in px against what a percentage refers to; NaN for a
	// keyword, a number, a unit not known here.
	public function resolve(basis:Float):Float
		return switch kind {
			case Px: value;
			case Percent: value * basis / 100;
			case Mixed: switch CssCalc.simplify(calc, null, basis) {
					case Value(v, "px"): v;
					case _: Math.NaN;
				}
			case _: Math.NaN;
		}

	public inline function is(word:String):Bool
		return kind == Word && keyword == word;
}
