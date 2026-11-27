package helder.text;

using StringTools;

// A document's @font-face faces (CSS Fonts 4 §4): each under a family name,
// with its descriptors' ranges (weight, stretch, style) and unicode-range,
// and CSS Fonts 4 §5.2's matching among a family's faces: font-stretch
// first, then font-style, then font-weight, each the nearest in the order
// the spec gives. A family named here hides the system's of that name. The
// faces matched are those of the chosen descriptors: one, or several that
// differ in their unicode-range, the last defined first (a composite face).
class FontFaces {
	final families = new Map<String, Array<FontFace>>();
	var defined = 0;
	// the faces added so far (keep: truncate's count)
	public var size(default, null) = 0;
	// bumped by each change (what is matched from them made again)
	public var generation(default, null) = 0;

	public function new() {}

	// the first count faces kept, those added after them taken out (a page's @font-face rules, the next page's)
	public function truncate(count:Int) {
		if (count >= size) return;
		for (k => list in families) {
			var kept = list.filter(f -> f.index < count);
			if (kept.length == 0) families.remove(k) else families.set(k, kept);
		}
		size = count;
		generation++;
	}

	public function has(family:String):Bool
		return families.exists(family.toLowerCase());

	// each face of a font file's data under family: descriptors null for the
	// font's own (auto: its weight, width and style, a variable font's axes' ranges)
	public function add(family:String, file:FontFile, ?descriptors:FontFaceDescriptors):FontFace {
		var face = new FontFace(file, descriptors ?? FontFaceDescriptors.of(file), defined++, size++);
		generation++;
		var key = family.toLowerCase(), list = families.get(key);
		if (list == null) families.set(key, list = []);
		list.push(face);
		if (face.ranges != null) file.unicodeRange = face.ranges;
		return face;
	}

	// a family's faces for a style (null: none of that name)
	public function match(family:String, weight:Float, stretch:Float, style:FontStyle):Null<Array<FontFace>> {
		var list = families.get(family.toLowerCase());
		if (list == null) return null;
		var c = nearest(list, f -> f.stretch, stretch, stretch <= 100 ? Below : Above);
		c = styled(c, style);
		c = nearest(c, f -> f.weight, weight, weight >= 400 && weight <= 500 ? Up500 : weight < 400 ? Below : Above);
		// (the chosen descriptors' faces, the last defined first)
		var out = [for (f in c) f];
		out.sort((a, b) -> b.order - a.order);
		return out;
	}

	// (faces whose range holds v, else the nearest on the side order says first)
	static function nearest(list:Array<FontFace>, range:FontFace->Range, v:Float, order:Side):Array<FontFace> {
		var within = list.filter(f -> range(f).min <= v && v <= range(f).max);
		if (within.length > 0) return within;
		var below = list.filter(f -> range(f).max < v), above = list.filter(f -> range(f).min > v);
		function highest(l:Array<FontFace>) {
			var m = Math.NEGATIVE_INFINITY;
			for (f in l) m = Math.max(m, range(f).max);
			return l.filter(f -> range(f).max == m);
		}
		function lowest(l:Array<FontFace>) {
			var m = Math.POSITIVE_INFINITY;
			for (f in l) m = Math.min(m, range(f).min);
			return l.filter(f -> range(f).min == m);
		}
		return switch order {
			case Below: below.length > 0 ? highest(below) : lowest(above);
			case Above: above.length > 0 ? lowest(above) : highest(below);
			// (400 to 500: heavier up to 500, then lighter, then heavier than 500)
			case Up500:
				var near = above.filter(f -> range(f).min <= 500);
				near.length > 0 ? lowest(near) : below.length > 0 ? highest(below) : lowest(above);
		}
	}

	// (§5.2 4b: italic: italic faces, then positive oblique ones, then the
	// others; oblique at a positive angle: positive ones by angle, then
	// italic, then the others (at zero or below: the mirror of it); normal:
	// normal faces and oblique ones by angle, then italic)
	static function styled(list:Array<FontFace>, style:FontStyle):Array<FontFace> {
		var italic = list.filter(f -> f.style == Italic), slanted = list.filter(f -> f.style != Italic);
		var positive = slanted.filter(f -> f.angle.max > 0), down = slanted.filter(f -> f.angle.min <= 0);
		return switch style {
			case Italic:
				italic.length > 0 ? italic : positive.length > 0 ? nearest(positive, f -> f.angle, 14, Above) : nearest(slanted, f -> f.angle, 0, Above);
			case Oblique(a) if (a > 0):
				positive.length > 0 ? nearest(positive, f -> f.angle, a, Above) : italic.length > 0 ? italic : nearest(slanted, f -> f.angle, a, Below);
			case Oblique(a):
				down.length > 0 ? nearest(down, f -> f.angle, a, Below) : italic.length > 0 ? italic : nearest(slanted, f -> f.angle, a, Above);
			case Normal:
				slanted.length > 0 ? nearest(slanted, f -> f.angle, 0, Above) : italic;
		}
	}
}

// what a face is matched with, and what it gives a variable font's axes
class FontFace {
	public final file:FontFile;
	public final weight:Range;
	public final stretch:Range;
	public final style:FontFaceStyle;
	// an oblique face's angles in degrees (normal: 0)
	public final angle:Range;
	// unicode-range: inclusive pairs (null: every character)
	public final ranges:Null<Array<Int>>;
	public final order:Int;
	// (its place among the faces there are: truncate's)
	public final index:Int;

	public function new(file:FontFile, d:FontFaceDescriptors, order:Int, index:Int) {
		this.index = index;
		this.file = file;
		weight = d.weight;
		stretch = d.stretch;
		style = d.style;
		angle = d.angle;
		ranges = d.ranges;
		this.order = order;
	}
}

// @font-face's descriptors, parsed (FontFaceDescriptors.parse) or the font's own
class FontFaceDescriptors {
	public var weight:Range;
	public var stretch:Range;
	public var style:FontFaceStyle;
	public var angle:Range;
	public var ranges:Null<Array<Int>> = null;

	public function new(weight, stretch, style, angle) {
		this.weight = weight;
		this.stretch = stretch;
		this.style = style;
		this.angle = angle;
	}

	// a font's own: its weight (a variable font's wght range), width (wdth),
	// italic or oblique (slnt: its angles, negated)
	public static function of(f:FontFile):FontFaceDescriptors {
		var w:Range = {min: f.weight, max: f.weight}, s:Range = {min: widths[f.width], max: widths[f.width]};
		var style:FontFaceStyle = f.italic ? Italic : Normal, angle:Range = {min: 0, max: 0};
		for (a in f.axes) switch a.tag {
			case "wght": w = {min: a.min, max: a.max};
			case "wdth": s = {min: a.min, max: a.max};
			case "slnt" if (!f.italic):
				style = Oblique;
				angle = {min: -a.max, max: -a.min};
			case "ital" if (a.max >= 1):
				style = Italic;
			case _:
		}
		return new FontFaceDescriptors(w, s, style, angle);
	}

	// (OS/2's usWidthClass 1 to 9 as font-stretch percentages)
	static final widths = [100.0, 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200];

	// a rule's descriptors over the font's own: font-weight (auto, a number
	// or keyword, a range), font-stretch (percentages or keywords),
	// font-style (normal, italic, oblique and its angles), unicode-range
	public static function parse(f:FontFile, weight:Null<String>, stretch:Null<String>, style:Null<String>, ranges:Null<String>):FontFaceDescriptors {
		var d = of(f);
		if (weight != null && weight != "auto") {
			var v = [for (w in words(weight)) switch w {
				case "normal": 400.0;
				case "bold": 700.0;
				case n: Std.parseFloat(n);
			}].filter(n -> !Math.isNaN(n));
			if (v.length > 0) d.weight = sorted(v[0], v[v.length - 1]);
		}
		if (stretch != null && stretch != "auto") {
			var v = [for (w in words(stretch)) w.endsWith("%") ? Std.parseFloat(w) : STRETCH.get(w) ?? Math.NaN].filter(n -> !Math.isNaN(n));
			if (v.length > 0) d.stretch = sorted(v[0], v[v.length - 1]);
		}
		if (style != null && style != "auto") {
			var w = words(style);
			switch w[0] {
				case "normal":
					d.style = Normal;
					d.angle = {min: 0, max: 0};
				case "italic":
					d.style = Italic;
				case "oblique":
					var a = [for (x in w.slice(1)) degrees(x)].filter(n -> !Math.isNaN(n));
					d.style = Oblique;
					d.angle = a.length == 0 ? {min: 14, max: 14} : sorted(a[0], a[a.length - 1]);
				case _:
			}
		}
		if (ranges != null) d.ranges = unicodeRanges(ranges);
		return d;
	}

	public static final STRETCH = ["ultra-condensed" => 50.0, "extra-condensed" => 62.5, "condensed" => 75.0, "semi-condensed" => 87.5, "normal" => 100.0,
		"semi-expanded" => 112.5, "expanded" => 125.0, "extra-expanded" => 150.0, "ultra-expanded" => 200.0];

	// (U+XXXX, U+XXXX-YYYY, U+XX??, comma-separated: inclusive pairs)
	public static function unicodeRanges(s:String):Array<Int> {
		var out = [];
		for (part in s.split(",")) {
			var p = StringTools.trim(part).toUpperCase();
			if (!StringTools.startsWith(p, "U+")) continue;
			p = p.substr(2);
			var dash = p.indexOf("-");
			var lo:Null<Int>, hi:Null<Int>;
			if (dash >= 0) {
				lo = Std.parseInt("0x" + p.substr(0, dash));
				hi = Std.parseInt("0x" + p.substr(dash + 1));
			} else {
				lo = Std.parseInt("0x" + StringTools.replace(p, "?", "0"));
				hi = Std.parseInt("0x" + StringTools.replace(p, "?", "F"));
			}
			if (lo == null || hi == null || hi < lo) continue;
			out.push(lo);
			out.push(hi > 0x10FFFF ? 0x10FFFF : hi);
		}
		return out;
	}

	static function words(s:String):Array<String>
		return [for (w in ~/\s+/g.split(StringTools.trim(s.toLowerCase()))) if (w != "") w];

	// (an angle in degrees: deg, grad, rad, turn)
	static function degrees(s:String):Float
		return s.endsWith("deg") ? Std.parseFloat(s) : s.endsWith("grad") ? Std.parseFloat(s) * 0.9 : s.endsWith("rad") ? Std.parseFloat(s) * 180 / Math.PI
			: s.endsWith("turn") ? Std.parseFloat(s) * 360 : Math.NaN;

	static function sorted(a:Float, b:Float):Range
		return a <= b ? {min: a, max: b} : {min: b, max: a};
}

typedef Range = {min:Float, max:Float}

enum abstract FontFaceStyle(Int) {
	var Normal;
	var Italic;
	var Oblique;
}

// the style asked for (font-style: oblique's angle in degrees)
enum FontStyle {
	Normal;
	Italic;
	Oblique(angle:Float);
}

private enum Side {
	Below;
	Above;
	Up500;
}
