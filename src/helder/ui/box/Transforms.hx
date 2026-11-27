package helder.ui.box;

import helder.ui.box.Len.Lens;

import helder.canvas.Matrix;
import helder.css.CssTerm;

// 2D transforms (Transforms 1): a computed transform list as a matrix
// about its transform-origin, in the coordinates of a box at (x, y).
// The 3D functions keep their 2D part.
class Transforms {
	public static function matrix(s:BoxStyle, x:Float, y:Float, w:Float, h:Float):Null<Matrix> {
		var list = s.rare.transform;
		if (list.length == 0 || list[0].match(Keyword("none"))) return null;
		var origin = s.rare.transformOrigin;
		var ox = x + at(origin, 0, w), oy = y + at(origin, 1, h);
		var m = new Matrix().translate(ox, oy);
		for (t in list) switch t {
			case Func(name, args):
				var v = [for (a in args) if (!a.match(Delim(_))) a];
				inline function len(k:Int, base:Float):Float
					return k < v.length ? length(v[k], base) : 0;
				inline function num(k:Int, fallback:Float):Float
					return k < v.length ? number(v[k]) : fallback;
				switch name {
					case "translate": m.translate(len(0, w), len(1, h));
					case "translatex": m.translate(len(0, w), 0);
					case "translatey": m.translate(0, len(0, h));
					case "translate3d": m.translate(len(0, w), len(1, h));
					case "scale" | "scale3d":
						var sx = num(0, 1);
						m.scale(sx, num(1, sx));
					case "scalex": m.scale(num(0, 1), 1);
					case "scaley": m.scale(1, num(0, 1));
					case "rotate" | "rotatez": m.rotate(angle(v[0]));
					case "skew": m.transform(1, v.length > 1 ? Math.tan(angle(v[1])) : 0, Math.tan(angle(v[0])), 1, 0, 0);
					case "skewx": m.transform(1, 0, Math.tan(angle(v[0])), 1, 0, 0);
					case "skewy": m.transform(1, Math.tan(angle(v[0])), 0, 1, 0, 0);
					case "matrix" if (v.length == 6): m.transform(num(0, 1), num(1, 0), num(2, 0), num(3, 1), num(4, 0), num(5, 0));
					case "matrix3d" if (v.length == 16): m.transform(num(0, 1), num(1, 0), num(4, 0), num(5, 1), num(12, 0), num(13, 0));
					case _:
				}
			case _:
		}
		return m.translate(-ox, -oy);
	}

	static function at(origin:Array<CssTerm>, axis:Int, size:Float):Float {
		var t = origin.length > axis ? origin[axis] : Percentage(50);
		return switch t {
			case Keyword("left" | "top"): 0;
			case Keyword("right" | "bottom"): size;
			case Keyword("center"): size / 2;
			case _: length(t, size);
		}
	}

	public static function length(t:CssTerm, base:Float):Float
		return Lens.resolve(BoxStyle.toLen([t]), base, 0);

	static function number(t:CssTerm):Float
		return switch t {
			case Number(v, _): v;
			case Percentage(p): p / 100;
			case _: 0;
		}

	public static function angle(t:CssTerm):Float
		return switch t {
			case Dimension(v, "deg"): v * Math.PI / 180;
			case Dimension(v, "rad"): v;
			case Dimension(v, "grad"): v * Math.PI / 200;
			case Dimension(v, "turn"): v * Math.PI * 2;
			case Dimension(v, _) | Number(v, _): v * Math.PI / 180;
			case _: 0;
		}
}
