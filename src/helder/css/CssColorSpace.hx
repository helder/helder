package helder.css;

// A colour's components from one space to another (CSS Color 4 §10, its
// sample code), each space in its own numbers as CssColors keeps them:
// "rgb" sRGB 0 to 255, "hsl" and "hwb" a hue in degrees and percentages,
// "lab" and "lch" L 0 to 100, "oklab" and "oklch" L 0 to 1, color()'s
// spaces 0 to 1 (XYZ as it is). None is NaN: 0 while converted, then
// carried to the analogous component where the other space has one
// (§12.4); a hue made powerless by the conversion is none too.
class CssColorSpace {
	public static function convert(from:String, c:Array<Float>, to:String):Array<Float> {
		if (from == to) return c.copy();
		if (rgbs(from) && rgbs(to)) return [for (x in c) x * scale(to) / scale(from)];
		var zeros = [for (x in c) Math.isNaN(x) ? 0.0 : x];
		// (an origin whose hue is powerless as achromatic: its chroma 0, its hue missing)
		c = c.copy();
		switch from {
			case "lch" | "oklch" if (zeros[1] <= (from == "lch" ? LCH : OKLCH)):
				zeros[1] = 0;
				c[2] = Math.NaN;
			case "hsl" if (Math.abs(zeros[1]) / 100 <= HSL):
				zeros[1] = 0;
				c[0] = Math.NaN;
			case "hwb" if ((zeros[1] + zeros[2]) / 100 >= 1 - HSL - 1e-12):
				var sum = zeros[1] + zeros[2];
				zeros[1] = zeros[1] / sum * 100;
				zeros[2] = zeros[2] / sum * 100;
				c[0] = Math.NaN;
			case _:
		}
		var out = fromXyz(to, toXyz(from, zeros));
		// (rounding's dust in a converted grey: 0)
		for (k in 0...3) if (Math.abs(out[k]) < 1e-10) out[k] = 0;
		for (k in 0...3) if (Math.isNaN(c[k])) {
			var j = analogous(to, kind(from, k));
			if (j >= 0) out[j] = Math.NaN;
		}
		// (missing together, missing together: all three; Lab's a and b as a polar
		// space's chroma and hue; HSL's saturation and lightness as HWB's whiteness
		// and blackness, and back)
		inline function none(ks:Array<Int>)
			return Lambda.foreach(ks, k -> Math.isNaN(c[k]));
		inline function drop(ks:Array<Int>)
			for (k in ks) out[k] = Math.NaN;
		if (none([0, 1, 2])) drop([0, 1, 2]);
		var polar = kinds(to).indexOf(HUE);
		if ((from == "lab" || from == "oklab") && none([1, 2]) && polar >= 0) drop([polar, kinds(to).indexOf(COLORFULNESS)].filter(k -> k >= 0));
		// (a polar space's two other components missing: the other polar space's two)
		var a = pair(from), b = pair(to);
		if (a != null && b != null && none(a)) drop(b);
		return out;
	}

	// ---- to and from XYZ, D65

	static function toXyz(space:String, c:Array<Float>):Array<Float>
		return switch space {
			case "rgb" | "hsl" | "hwb": toXyz("srgb", [for (x in CssColors.srgb({space: space, c: c, alpha: 1})) x / 255]);
			case "srgb": times(SRGB_XYZ, [for (x in c) CssRgba.linear(x)]);
			case "srgb-linear": times(SRGB_XYZ, c);
			case "display-p3": times(CssRgba.P3, [for (x in c) CssRgba.linear(x)]);
			case "display-p3-linear": times(CssRgba.P3, c);
			case "a98-rgb": times(CssRgba.A98, [for (x in c) CssRgba.signed(x, 563 / 256)]);
			case "prophoto-rgb": times(CssRgba.D50_D65, times(CssRgba.PROPHOTO, [for (x in c) Math.abs(x) <= 16 / 512 ? x / 16 : CssRgba.signed(x, 1.8)]));
			case "rec2020": times(CssRgba.REC2020, [for (x in c) CssRgba.rec2020(x)]);
			case "xyz-d50": times(CssRgba.D50_D65, c);
			case "lab": times(CssRgba.D50_D65, CssRgba.lab(c[0], c[1], c[2]));
			case "lch": toXyz("lab", lab(c));
			case "oklab": CssRgba.oklab(c[0], c[1], c[2]);
			case "oklch": toXyz("oklab", lab(c));
			case _: c;
		}

	static function fromXyz(space:String, xyz:Array<Float>):Array<Float>
		return switch space {
			case "rgb": [for (x in fromXyz("srgb", xyz)) x * 255];
			case "hsl": hsl(fromXyz("srgb", xyz));
			case "hwb": hwb(fromXyz("srgb", xyz));
			case "srgb": [for (x in times(CssRgba.XYZ_SRGB, xyz)) CssRgba.gamma(x)];
			case "srgb-linear": times(CssRgba.XYZ_SRGB, xyz);
			case "display-p3": [for (x in times(XYZ_P3, xyz)) CssRgba.gamma(x)];
			case "display-p3-linear": times(XYZ_P3, xyz);
			case "a98-rgb": [for (x in times(XYZ_A98, xyz)) CssRgba.signed(x, 256 / 563)];
			case "prophoto-rgb": [for (x in times(XYZ_PROPHOTO, times(D65_D50, xyz))) Math.abs(x) >= 1 / 512 ? CssRgba.signed(x, 1 / 1.8) : 16 * x];
			case "rec2020": [for (x in times(XYZ_REC2020, xyz)) rec2020(x)];
			case "xyz-d50": times(D65_D50, xyz);
			case "lab": labOf(times(D65_D50, xyz));
			case "lch": lch(labOf(times(D65_D50, xyz)), LCH);
			case "oklab": oklabOf(xyz);
			case "oklch": lch(oklabOf(xyz), OKLCH);
			case _: xyz;
		}

	// (polar to rectangular: L, C, H to L, a, b)
	static function lab(c:Array<Float>):Array<Float> {
		var h = c[2] * Math.PI / 180;
		return [c[0], c[1] * Math.cos(h), c[1] * Math.sin(h)];
	}

	// (rectangular to polar: at chroma eps or below, achromatic, its hue powerless)
	static function lch(c:Array<Float>, eps:Float):Array<Float> {
		var chroma = Math.sqrt(c[1] * c[1] + c[2] * c[2]), hue = Math.atan2(c[2], c[1]) * 180 / Math.PI;
		if (hue < 0) hue += 360;
		return chroma <= eps ? [c[0], 0, Math.NaN] : [c[0], chroma, hue];
	}

	// (the powerless thresholds: LCH's and Oklch's chroma, HSL's saturation and HWB's whiteness and blackness, 0 to 1;
	// compared with a hair to spare, 49.999% and 50% summing a little under)
	static inline var LCH = 0.0015;
	static inline var OKLCH = 0.000004;
	static inline var HSL = 1e-5;

	// (XYZ D50 to Lab)
	static function labOf(xyz:Array<Float>):Array<Float> {
		var k = 24389 / 27, e = 216 / 24389;
		var white = [0.3457 / 0.3585, 1, (1 - 0.3457 - 0.3585) / 0.3585];
		var f = [for (i in 0...3) {
			var v = xyz[i] / white[i];
			v > e ? Math.pow(v, 1 / 3) : (k * v + 16) / 116;
		}];
		return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])];
	}

	static function oklabOf(xyz:Array<Float>):Array<Float>
		return times(LMS_OKLAB, [for (x in times(XYZ_LMS, xyz)) x < 0 ? -Math.pow(-x, 1 / 3) : Math.pow(x, 1 / 3)]);

	static function rec2020(x:Float):Float
		return CssRgba.signed(x, 1 / 2.4);

	// (sRGB 0 to 1 to HSL: negative saturation turned by 180 degrees, as Color 4's code)
	static function hsl(c:Array<Float>):Array<Float> {
		var r = c[0], g = c[1], b = c[2];
		var max = Math.max(r, Math.max(g, b)), min = Math.min(r, Math.min(g, b));
		var hue = Math.NaN, sat = 0.0, light = (min + max) / 2, d = max - min;
		if (d != 0) {
			sat = light == 0 || light == 1 ? 0 : (max - light) / Math.min(light, 1 - light);
			hue = (max == r ? (g - b) / d + (g < b ? 6 : 0) : max == g ? (b - r) / d + 2 : (r - g) / d + 4) * 60;
		}
		if (sat < 0) {
			hue += 180;
			sat = -sat;
		}
		// (a grey, or one come through XYZ with its dust: achromatic)
		if (sat <= HSL) {
			sat = 0;
			hue = Math.NaN;
		}
		if (hue >= 360) hue -= 360;
		return [hue, sat * 100, light * 100];
	}

	// (its hue HSL's without turning: an out of gamut colour comes back as it was)
	static function hwb(c:Array<Float>):Array<Float> {
		var r = c[0], g = c[1], b = c[2];
		var max = Math.max(r, Math.max(g, b)), min = Math.min(r, Math.min(g, b)), d = max - min;
		var hue = d == 0 ? Math.NaN : (max == r ? (g - b) / d + (g < b ? 6 : 0) : max == g ? (b - r) / d + 2 : (r - g) / d + 4) * 60;
		var white = min, black = 1 - max;
		return [white + black >= 1 - HSL - 1e-12 ? Math.NaN : hue, white * 100, black * 100];
	}

	// ---- analogous components (§12.4)

	static inline var RED = 0;
	static inline var GREEN = 1;
	static inline var BLUE = 2;
	static inline var LIGHTNESS = 3;
	static inline var COLORFULNESS = 4;
	static inline var HUE = 5;
	static inline var A = 6;
	static inline var B = 7;
	static inline var OTHER = 8;

	static function kinds(space:String):Array<Int>
		return switch space {
			case "hsl": [HUE, COLORFULNESS, LIGHTNESS];
			case "hwb": [HUE, OTHER, OTHER];
			case "lab" | "oklab": [LIGHTNESS, A, B];
			case "lch" | "oklch": [LIGHTNESS, COLORFULNESS, HUE];
			case _: [RED, GREEN, BLUE];
		}

	static function kind(space:String, k:Int):Int
		return kinds(space)[k];

	static function analogous(space:String, kind:Int):Int
		return kind == OTHER ? -1 : kinds(space).indexOf(kind);

	// (a polar space's components but its hue)
	static function pair(space:String):Null<Array<Int>>
		return switch space {
			case "hsl" | "hwb": [1, 2];
			case "lch" | "oklch": [0, 1];
			case _: null;
		}

	// (the RGB spaces whose components are the same but for their scale: rgb()'s 0 to 255, color(srgb)'s 0 to 1)
	static function rgbs(space:String):Bool
		return space == "rgb" || space == "srgb";

	static function scale(space:String):Float
		return space == "rgb" ? 255 : 1;

	static function times(m:Array<Array<Float>>, v:Array<Float>):Array<Float>
		return [for (row in m) row[0] * v[0] + row[1] * v[1] + row[2] * v[2]];

	static function invert(m:Array<Array<Float>>):Array<Array<Float>> {
		var a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2];
		var det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
		return [
			[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
			[(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
			[(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
		];
	}

	static final SRGB_XYZ = invert(CssRgba.XYZ_SRGB);
	static final XYZ_P3 = invert(CssRgba.P3);
	static final XYZ_A98 = invert(CssRgba.A98);
	static final XYZ_PROPHOTO = invert(CssRgba.PROPHOTO);
	static final XYZ_REC2020 = invert(CssRgba.REC2020);
	static final D65_D50 = invert(CssRgba.D50_D65);
	static final XYZ_LMS = invert(CssRgba.LMS_XYZ);
	static final LMS_OKLAB = invert(CssRgba.OKLAB_LMS);
}
