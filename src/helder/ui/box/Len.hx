package helder.ui.box;

import helder.css.CssCalc;

// A length as layout reads it: auto, px, a percentage of a base, or a
// math function of both (resolved once the base is known).
enum Len {
	Auto;
	Px(value:Float);
	Percent(value:Float);
	Calc(node:CssCalcNode);
}

class Lens {
	// The length against base (NaN: indefinite); auto, or a percentage of an
	// indefinite base, is `auto`.
	public static function resolve(l:Len, base:Float, auto:Float):Float
		return switch l {
			case Auto: auto;
			case Px(v): v;
			case Percent(p): Math.isNaN(base) ? auto : p * base / 100;
			case Calc(n):
				if (Math.isNaN(base) && CssCalc.hasPercent(n)) auto else switch CssCalc.simplify(n, null, Math.isNaN(base) ? 0 : base) {
					case Value(v, _): v;
					case _: auto;
				}
		}

	public static inline function isAuto(l:Len):Bool
		return l.match(Auto);

	// (a percentage, alone or in calc(): what an indefinite base makes auto)
	public static function relative(l:Len):Bool
		return switch l {
			case Percent(_): true;
			case Calc(n): CssCalc.hasPercent(n);
			case _: false;
		}
}
