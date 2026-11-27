package helder.css;

import helder.css.CssColors;
import helder.css.CssTerm;

// A computed colour as sRGB floats (0 to 1, alpha too), or a keyword
// (currentcolor, kept as such: it's the element's color when used;
// auto). Interned per document.
@:allow(helder.css.CssColorSpace)
class CssRgba {
	public static final OTHER = new CssRgba(null, 0, 0, 0, 0, []);

	public final keyword:Null<String>;
	public final r:Float;
	public final g:Float;
	public final b:Float;
	public final a:Float;
	public final terms:Array<CssTerm>;
	@:allow(helder.css) var id = -1;
	var pending:Null<CssColorValue> = null;

	function new(keyword:Null<String>, r:Float, g:Float, b:Float, a:Float, terms:Array<CssTerm>) {
		this.keyword = keyword;
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
		this.terms = terms;
	}

	@:allow(helder.css)
	static function of(t:Array<CssTerm>):Null<CssRgba>
		return t.length != 1 ? null : switch t[0] {
			// (a relative colour: resolved, else of currentcolor, resolved with it)
			case Color(c) if (c.from != null):
				var a = CssColors.absolute(c);
				// (its terms the relative colour's: what's written)
				if (a != null) {
					var rgb = srgb(a);
					new CssRgba(null, rgb[0], rgb[1], rgb[2], Math.isNaN(a.alpha) ? 0 : a.alpha, t);
				} else {
					var r = new CssRgba("currentcolor", 0, 0, 0, 0, t);
					r.pending = c;
					r;
				}
			case Color(c) if (c.keyword == "currentcolor"): new CssRgba("currentcolor", 0, 0, 0, 0, t);
			case Color(c) if (c.c.length == 3):
				var rgb = srgb(c);
				new CssRgba(null, rgb[0], rgb[1], rgb[2], c.alpha, t);
			// (a system colour, as computed: kept by name)
			case Color(c): new CssRgba(c.keyword, 0, 0, 0, c.alpha, t);
			case Keyword(k): new CssRgba(k, 0, 0, 0, 0, t);
			case _: null;
		}

	// A computed colour's terms as 0xAARRGGBB, sRGB clipped; null: a keyword's
	// (currentcolor, a system colour) or not a colour
	public static function argb(t:Array<CssTerm>):Null<Int> {
		var c = of(t);
		if (c == null || c.keyword != null) return null;
		inline function byte(x:Float):Int {
			var v = Math.round((Math.isNaN(x) ? 0 : x) * 255);
			return v < 0 ? 0 : v > 255 ? 255 : v;
		}
		return byte(c.a) << 24 | byte(c.r) << 16 | byte(c.g) << 8 | byte(c.b);
	}

	// (any of Color 4's spaces as sRGB, 0 to 1, not clipped; none as 0)
	static function srgb(c:CssColorValue):Array<Float> {
		var v = [for (x in c.c) Math.isNaN(x) ? 0.0 : x];
		return switch c.space {
			case "rgb" | "hsl" | "hwb": [for (x in CssColors.srgb({space: c.space, c: v, alpha: c.alpha})) x / 255];
			case "srgb": v;
			case "srgb-linear": [for (x in v) gamma(x)];
			case "display-p3": fromXyz(times(P3, [for (x in v) linear(x)]));
			case "display-p3-linear": fromXyz(times(P3, v));
			case "a98-rgb": fromXyz(times(A98, [for (x in v) signed(x, 563 / 256)]));
			case "prophoto-rgb": fromXyz(times(D50_D65, times(PROPHOTO, [for (x in v) Math.abs(x) <= 16 / 512 ? x / 16 : signed(x, 1.8)])));
			case "rec2020": fromXyz(times(REC2020, [for (x in v) rec2020(x)]));
			case "xyz" | "xyz-d65": fromXyz(v);
			case "xyz-d50": fromXyz(times(D50_D65, v));
			case "lab": fromXyz(times(D50_D65, lab(v[0], v[1], v[2])));
			case "lch": fromXyz(times(D50_D65, lab(v[0], v[1] * Math.cos(v[2] * Math.PI / 180), v[1] * Math.sin(v[2] * Math.PI / 180))));
			case "oklab": fromXyz(oklab(v[0], v[1], v[2]));
			case "oklch": fromXyz(oklab(v[0], v[1] * Math.cos(v[2] * Math.PI / 180), v[1] * Math.sin(v[2] * Math.PI / 180)));
			case _: v;
		}
	}

	static function fromXyz(xyz:Array<Float>):Array<Float>
		return [for (x in times(XYZ_SRGB, xyz)) gamma(x)];

	static function linear(c:Float):Float {
		var a = Math.abs(c);
		return a <= 0.04045 ? c / 12.92 : (c < 0 ? -1 : 1) * Math.pow((a + 0.055) / 1.055, 2.4);
	}

	static function gamma(c:Float):Float {
		var a = Math.abs(c);
		return a > 0.0031308 ? (c < 0 ? -1 : 1) * (1.055 * Math.pow(a, 1 / 2.4) - 0.055) : 12.92 * c;
	}

	static function signed(c:Float, e:Float):Float
		return (c < 0 ? -1 : 1) * Math.pow(Math.abs(c), e);

	// (Color 4's rec2020: a gamma of 2.4, BT.1886's, no longer BT.2020's curve)
	static function rec2020(c:Float):Float
		return signed(c, 2.4);

	// (Lab to XYZ, D50)
	static function lab(l:Float, a:Float, b:Float):Array<Float> {
		var k = 24389 / 27, e = 216 / 24389;
		var f1 = (l + 16) / 116, f0 = a / 500 + f1, f2 = f1 - b / 200;
		var x = Math.pow(f0, 3) > e ? Math.pow(f0, 3) : (116 * f0 - 16) / k;
		var y = l > k * e ? Math.pow(f1, 3) : l / k;
		var z = Math.pow(f2, 3) > e ? Math.pow(f2, 3) : (116 * f2 - 16) / k;
		return [x * 0.3457 / 0.3585, y, z * (1 - 0.3457 - 0.3585) / 0.3585];
	}

	// (Oklab to XYZ, D65)
	static function oklab(l:Float, a:Float, b:Float):Array<Float>
		return times(LMS_XYZ, [for (x in times(OKLAB_LMS, [l, a, b])) x * x * x]);

	static function times(m:Array<Array<Float>>, v:Array<Float>):Array<Float>
		return [for (row in m) row[0] * v[0] + row[1] * v[1] + row[2] * v[2]];

	static final XYZ_SRGB = [
		[3.2409699419045226, -1.537383177570094, -0.4986107602930034],
		[-0.9692436362808796, 1.8759675015077202, 0.04155505740717559],
		[0.05563007969699366, -0.20397695888897652, 1.0569715142428786]
	];
	static final D50_D65 = [
		[0.955473421488075, -0.02309845494876471, 0.06325924320057072],
		[-0.0283697093338637, 1.0099953980813041, 0.021041441191917323],
		[0.012314014864481998, -0.020507649298898964, 1.330365926242124]
	];
	static final P3 = [
		[0.48657094864821626, 0.26566769316909294, 0.1982172852343625],
		[0.22897456406974884, 0.6917385218365062, 0.079286914093745],
		[0, 0.04511338185890257, 1.0439443689009757]
	];
	static final A98 = [
		[0.5766690429101305, 0.1855582379065463, 0.1882286462349947],
		[0.29734497525053605, 0.6273635662554661, 0.07529145849399788],
		[0.02703136138641234, 0.07068885253582723, 0.9913375368376388]
	];
	static final PROPHOTO = [
		[0.7977666449006423, 0.13518129740053308, 0.0313477341283922],
		[0.2880748288194013, 0.711835234241873, 0.00008993693872564],
		[0, 0, 0.8251046025104602]
	];
	static final REC2020 = [
		[0.6369580483012914, 0.14461690358620832, 0.1688809751641721],
		[0.2627002120112671, 0.6779980715188708, 0.05930171646986196],
		[0, 0.028072693049087428, 1.060985057710791]
	];
	static final OKLAB_LMS = [
		[1, 0.3963377773761749, 0.2158037573099136],
		[1, -0.1055613458156586, -0.0638541728258133],
		[1, -0.0894841775298119, -1.2914855480194092]
	];
	static final LMS_XYZ = [
		[1.2268798758459243, -0.5578149944602171, 0.2813910456659647],
		[-0.0405757452148008, 1.112286803280317, -0.0717110580655164],
		[-0.0763729366746601, -0.4214933324022432, 1.5869240198367816]
	];

	public var current(get, never):Bool;

	inline function get_current():Bool
		return keyword == "currentcolor";

	// This colour, currentcolor as the given one.
	public function resolve(color:CssRgba):CssRgba {
		if (pending == null) return current ? color : this;
		var a = CssColors.absolute(pending, {space: "srgb", c: [color.r, color.g, color.b], alpha: color.a});
		return a == null ? color : of([Color(a)]);
	}
}
