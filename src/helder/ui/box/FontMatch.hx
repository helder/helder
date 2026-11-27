package helder.ui.box;

import haxe.io.Bytes;
import helder.css.CssFontMetrics;
import helder.css.CssSheet;
import helder.css.CssTerm;
import helder.text.FontFaces;
import helder.text.FontFaces.FontFaceDescriptors;
import helder.text.FontFaces.FontStyle;
import helder.text.FontFile;
import helder.text.SystemFonts;
import helder.ui.flow.InlineValues.InlineFontStyle;

using StringTools;

// A computed font (family list, weight, style, stretch, size) matched to
// a helder.text face, as Fonts 4 §5 matches: each family in turn, a
// generic one the system's, a named one only when it is there (the
// document's faces, @font-face's and those registered here, by FontFaces'
// matching: their descriptors' ranges, unicode-range; then the system's),
// the closest stretch, style and weight of it. The inline layout's fonts
// (inlines) match the same faces. Metrics are rounded to pixels as
// Chromium's are.
class FontMatch {
	public final system:SystemFonts;
	// the document's faces: @font-face's, and those registered
	public final faces = new FontFaces();
	// the inline formatting context's fonts, over the same faces
	public final inlines:helder.ui.flow.InlineFonts;

	final found = new Map<String, FontFile>();
	var families:Null<Map<String, Bool>> = null;

	public function new(?system:SystemFonts) {
		this.system = system ?? SystemFonts.get();
		inlines = new helder.ui.flow.InlineFonts(this.system, faces);
	}

	// a font file's faces under a family name (its own when null): Ahem for
	// tests, @font-face's (its descriptors' text: weight, stretch, style,
	// unicode-range; null: the font's own)
	public function register(data:Bytes, ?family:String, ?weight:String, ?stretch:String, ?style:String, ?ranges:String) {
		// (the system's too: the fallbacks find it by its own name)
		system.add(data);
		add(data, family, weight, stretch, style, ranges);
		installed = faces.size;
	}

	// (the faces registered: what a document's @font-face rules come after)
	var installed = 0;

	function add(data:Bytes, family:Null<String>, weight:Null<String>, stretch:Null<String>, style:Null<String>, ranges:Null<String>) {
		for (i in 0...FontFile.faceCount(data)) {
			var f = try FontFile.parse(data, i) catch (_:Dynamic) null;
			if (f == null) continue;
			faces.add(family ?? f.family, f, FontFaceDescriptors.parse(f, weight, stretch, style, ranges));
		}
		found.clear();
		measured.clear();
	}

	// a document's @font-face rules (CssStyles.fontFaces; the last document's
	// taken out), their sources loaded by URL (resolved against the sheet's):
	// found by their family's name alone, not the font's own
	public function fontFaces(rules:Array<CssFontFace>, load:(url:String) -> Null<Bytes>) {
		faces.truncate(installed);
		found.clear();
		measured.clear();
		for (r in rules) {
			var family:Null<String> = null, src:Null<String> = null;
			var weight:Null<String> = null, stretch:Null<String> = null, style:Null<String> = null, ranges:Null<String> = null;
			for (d in r.descriptors) {
				var text = helder.css.Css.serialize(d.value).trim();
				switch d.name.toLowerCase() {
					case "font-family": family = unquote(text);
					case "src": src = text;
					case "font-weight": weight = text;
					case "font-stretch" | "font-width": stretch = text;
					case "font-style": style = text;
					case "unicode-range": ranges = text;
					case _:
				}
			}
			if (family == null || src == null) continue;
			for (url in ~/url\(\s*["']?([^"')]+)["']?\s*\)/g.map(src, m -> m.matched(1) + "\n").split("\n")) {
				url = url.trim();
				if (url == "") continue;
				var bytes = load(helder.css.CssUrl.resolve(r.url, url));
				if (bytes != null) {
					add(bytes, family, weight, stretch, style, ranges);
					break;
				}
			}
		}
	}

	static function unquote(s:String):String
		return s.length > 1 && (s.startsWith('"') || s.startsWith("'")) ? s.substr(1, s.length - 2) : s;

	// The face for a style: its first family there is.
	public function face(style:BoxStyle):FontFile {
		var weight = Std.int(style.number("font-weight", 400));
		var italic = style.keyword("font-style") != "normal" && style.keyword("font-style") != "";
		var stretch = switch style.terms("font-width") {
			case [Percentage(p)]: p;
			case [Keyword(k)]: FontFaceDescriptors.STRETCH.get(k) ?? 100;
			case _: 100;
		}
		var slant:FontStyle = switch style.terms("font-style") {
			case [Keyword("italic")]: Italic;
			case [Keyword("oblique"), Dimension(v, "deg")]: Oblique(v);
			case [Keyword("oblique")]: Oblique(14);
			case _: Normal;
		}
		var names = familyNames(style.terms("font-family"));
		var key = [for (n in names) (n.generic ? "@" : "") + n.name].join(",") + "/" + weight + "/" + stretch + "/" + Std.string(slant);
		var f = found.get(key);
		if (f != null) return f;
		for (n in names) {
			f = n.generic ? generic(n.name, weight, italic) : named(n.name, weight, stretch, slant);
			if (f != null) break;
		}
		if (f == null) f = system.match("serif", weight, italic);
		found.set(key, f);
		return f;
	}
	// (each family: a name, or a generic family's keyword, which a font named
	// like it, "serif" quoted, isn't)
	static function familyNames(terms:Array<CssTerm>):Array<{name:String, generic:Bool}> {
		var out = [], word = [], generic = false;
		function flush() {
			if (word.length > 0) out.push({name: word.join(" "), generic: generic});
			word = [];
			generic = false;
		}
		for (t in terms) switch t {
			case Delim(","): flush();
			case Ident(v) | Str(v) | Raw(v): word.push(v);
			case Keyword(v):
				word.push(v);
				generic = true;
			case _:
		}
		flush();
		return out;
	}

	function named(name:String, weight:Int, stretch:Float, slant:FontStyle):Null<FontFile> {
		var m = faces.match(name, weight, stretch, slant);
		if (m != null && m.length > 0) return m[0].file;
		if (families == null) families = [for (f in system.families()) f.toLowerCase() => true];
		return families.exists(name.toLowerCase()) ? system.match(name, weight, !slant.match(Normal)) : null;
	}

	function generic(name:String, weight:Int, italic:Bool):Null<FontFile>
		return switch name.toLowerCase() {
			case "serif" | "sans-serif" | "monospace": system.match(name.toLowerCase(), weight, italic);
			case "cursive" | "fantasy" | "math" | "fangsong" | "ui-serif": system.match("serif", weight, italic);
			case "system-ui" | "ui-sans-serif" | "ui-rounded": system.match("sans-serif", weight, italic);
			case "ui-monospace": system.match("monospace", weight, italic);
			// (a keyword that isn't a generic family: a name)
			case _: named(name, weight, 100, italic ? Italic : Normal);
		}

	// (the document's @font-palette-values: each a name, families, base palette and overrides)
	var paletteRules:Array<{name:String, families:Array<String>, base:Null<String>, overrides:Array<{entry:Int, color:Int}>}> = [];
	final palettes = new Map<String, Null<Array<Int>>>();

	// a document's @font-palette-values rules (CssStyles.fontPaletteValues; the last document's replaced)
	public function fontPalettes(rules:Array<helder.css.CssSheet.CssFontPaletteValues>) {
		paletteRules = [];
		palettes.clear();
		for (r in rules) {
			var families = [], base:Null<String> = null, overrides = [];
			for (d in r.descriptors) switch d.name.toLowerCase() {
				case "font-family":
					for (f in helder.css.Css.serialize(d.value).split(",")) families.push(unquote(f.trim()).toLowerCase());
				case "base-palette": base = helder.css.Css.serialize(d.value).trim().toLowerCase();
				case "override-colors":
					// (an index and a colour, comma-separated: each colour computed as color's value)
					for (pair in split(d.value)) {
						var entry = switch pair[0] {
							case Token(_.kind => Number(n, true, _)): Std.int(n);
							case Function(_):
								switch helder.css.CssValues.reading("z-index", [pair[0]]) {
									case Terms(t): switch helder.css.CssComputed.terms("z-index", t, helder.css.CssValues.DEFAULT) {
											case [Number(n, _)]: Std.int(n);
											case _: -1;
										}
									case _: -1;
								}
							case _: -1;
						}
						var color = switch helder.css.CssValues.reading("color", pair.slice(1)) {
							case Terms(t): helder.css.CssRgba.argb(helder.css.CssComputed.terms("color", helder.css.CssCanonical.terms("color", t), helder.css.CssValues.DEFAULT));
							case _: null;
						}
						if (entry >= 0 && color != null) overrides.push({entry: entry, color: color});
					}
				case _:
			}
			paletteRules.push({name: r.name, families: families, base: base, overrides: overrides});
		}
	}

	// (component values split at their top-level commas, whitespace dropped)
	static function split(values:Array<helder.css.CssValue>):Array<Array<helder.css.CssValue>> {
		var out = [[]];
		for (v in values) switch v {
			case Token(_.kind => Comma): out.push([]);
			case Token(_.kind => Whitespace):
			case _: out[out.length - 1].push(v);
		}
		return [for (p in out) if (p.length >= 2) p];
	}

	// a colour face's palette for an element's font-palette (Fonts 4 §9): normal the
	// font's first, light and dark the first marked so (else the first), a
	// @font-palette-values name for the face's family (its base-palette, its
	// override-colors over it; the last rule of the name; none: normal),
	// palette-mix() of two of them; null: the font's first
	public function palette(face:FontFile, style:BoxStyle):Null<Array<Int>> {
		var c = face.colr;
		if (c == null || c.palettes.length == 0) return null;
		var terms = style.terms("font-palette");
		if (terms.length == 0 || terms[0].match(Keyword("normal"))) return null;
		var family = (face.alias ?? face.family).toLowerCase(), key = face.id + "|" + Std.string(terms) + "|" + family;
		if (palettes.exists(key)) return palettes.get(key);
		var out = paletteOf(c, terms, family);
		palettes.set(key, out);
		return out;
	}

	function paletteOf(c:helder.text.Colr, terms:Array<CssTerm>, family:String):Array<Int>
		return switch terms {
			case [Keyword(k = "light" | "dark")]: c.palettes[marked(c, k)];
			case [Ident(name)]:
				var rule = null;
				for (r in paletteRules) if (r.name == name && r.families.contains(family)) rule = r;
				if (rule == null) return c.palettes[0];
				var base = switch rule.base {
					case null: 0;
					case "light" | "dark": marked(c, rule.base);
					case n: Std.parseInt(n) ?? 0;
				}
				var out = (base >= 0 && base < c.palettes.length ? c.palettes[base] : c.palettes[0]).copy();
				for (o in rule.overrides) if (o.entry < out.length) out[o.entry] = o.color;
				out;
			case [Func("palette-mix", args)]: mix(c, args, family);
			case _: c.palettes[0];
		}

	// (palette-mix(in <space>, a [p%], b [p%]): each entry mixed as color-mix() mixes,
	// premultiplied; srgb, srgb-linear or oklab, others as srgb)
	function mix(c:helder.text.Colr, args:Array<CssTerm>, family:String):Array<Int> {
		var parts = [[]];
		for (t in args) if (t.match(Delim(","))) parts.push([]) else parts[parts.length - 1].push(t);
		if (parts.length != 3) return c.palettes[0];
		var space = switch parts[0] {
			case [Keyword("in"), Keyword(s)] | [Keyword("in"), Keyword(s), _, _]: s;
			case _: "srgb";
		}
		var sides = [for (i in 1...3) {
			var p = parts[i], pct:Null<Float> = null;
			var last = p[p.length - 1];
			switch last {
				case Percentage(v):
					pct = v;
					p = p.slice(0, p.length - 1);
				case _:
			}
			{palette: paletteOf(c, p, family), pct: pct};
		}];
		var p1 = sides[0].pct, p2 = sides[1].pct;
		if (p1 == null && p2 == null) p1 = p2 = 50 else if (p1 == null) p1 = 100 - p2 else if (p2 == null) p2 = 100 - p1;
		var sum = p1 + p2;
		if (sum <= 0) return c.palettes[0];
		var w = p2 / sum, scale = sum < 100 ? sum / 100 : 1;
		var a = sides[0].palette, b = sides[1].palette;
		return [for (i in 0...a.length) mixed(a[i], i < b.length ? b[i] : a[i], w, scale, space)];
	}

	static function mixed(c0:Int, c1:Int, w:Float, scale:Float, space:String):Int {
		inline function ch(c:Int, s:Int)
			return ((c >> s) & 255) / 255;
		var a0 = ((c0 >>> 24) & 255) / 255, a1 = ((c1 >>> 24) & 255) / 255;
		var x0 = toSpace([ch(c0, 16), ch(c0, 8), ch(c0, 0)], space), x1 = toSpace([ch(c1, 16), ch(c1, 8), ch(c1, 0)], space);
		var a = a0 + (a1 - a0) * w;
		var v = [for (k in 0...3) a <= 0 ? 0 : (x0[k] * a0 + (x1[k] * a1 - x0[k] * a0) * w) / a];
		var rgb = fromSpace(v, space);
		inline function byte(x:Float)
			return Std.int(Math.max(0, Math.min(255, Math.round(x * 255))));
		return byte(a * scale) << 24 | byte(rgb[0]) << 16 | byte(rgb[1]) << 8 | byte(rgb[2]);
	}

	static inline function linear(x:Float):Float
		return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);

	static inline function gamma(x:Float):Float
		return x <= 0.0031308 ? x * 12.92 : 1.055 * Math.pow(x, 1 / 2.4) - 0.055;

	static function toSpace(c:Array<Float>, space:String):Array<Float>
		return switch space {
			case "srgb-linear": [for (x in c) linear(x)];
			case "oklab":
				var r = linear(c[0]), g = linear(c[1]), b = linear(c[2]);
				var l = Math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3);
				var m = Math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3);
				var s = Math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3);
				[0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
					0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
			case _: c;
		}

	static function fromSpace(v:Array<Float>, space:String):Array<Float>
		return switch space {
			case "srgb-linear": [for (x in v) gamma(x)];
			case "oklab":
				var l = Math.pow(v[0] + 0.3963377774 * v[1] + 0.2158037573 * v[2], 3);
				var m = Math.pow(v[0] - 0.1055613458 * v[1] - 0.0638541728 * v[2], 3);
				var s = Math.pow(v[0] - 0.0894841775 * v[1] - 1.2914855480 * v[2], 3);
				[gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
					gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)];
			case _: v;
		}

	// (the first palette marked usable on a light background, or a dark one; else the first)
	static function marked(c:helder.text.Colr, which:String):Int {
		var flag = which == "light" ? 1 : 2;
		for (i in 0...c.paletteFlags.length) if (c.paletteFlags[i] & flag != 0) return i;
		return 0;
	}

	final measured = new Map<String, CssFontMetrics>();

	// the first available font's metrics for a font's computed values (CssStyles.metrics,
	// Values 4 §6.1.1): the x-height (OS/2's sxHeight, else x's top, else half the em), the
	// advance of 0 (else half the em), the cap height (OS/2's sCapHeight, else H's top, else
	// the ascent), the advance of 水 in the face that has it (else the em), line-height:
	// normal as the inline layout has it
	public function metrics(q:CssFontQuery):CssFontMetrics {
		var s = new helder.ui.flow.InlineBasicStyle();
		s.families = BoxStyle.familiesOf(q.family);
		s.size = q.size;
		s.weight = switch q.weight {
			case [Number(v, _)]: Std.int(v);
			case _: 400;
		}
		switch q.style {
			case [Keyword("italic")]: s.style = InlineFontStyle.Italic;
			case [Keyword("oblique"), Dimension(v, "deg")]:
				s.style = InlineFontStyle.Oblique;
				s.angle = v;
			case [Keyword("oblique")] | [Keyword("oblique"), _]: s.style = InlineFontStyle.Oblique;
			case _:
		}
		s.stretch = switch q.stretch {
			case [Percentage(p)]: p;
			case [Keyword(k)]: FontFaceDescriptors.STRETCH.get(k) ?? 100;
			case _: 100;
		}
		var tag:Null<String> = null;
		for (t in q.variations) switch t {
			case Str(v): tag = v;
			case Number(v, _) if (tag != null):
				if (s.variations == null) s.variations = new Map();
				s.variations.set(tag, v);
			case _:
		}
		s.opticalSizing = !(q.opticalSizing.length == 1 && q.opticalSizing[0].match(Keyword("none")));
		var key = s.families.join(",") + "|" + s.size + "|" + s.weight + "|" + s.style + "|" + s.angle + "|" + s.stretch + "|" + s.opticalSizing + "|"
			+ (s.variations == null ? "" : [for (k => v in s.variations) k + "=" + v].join(","));
		var m = measured.get(key);
		if (m != null) return m;
		var id = inlines.idOf(s), set = inlines.set(id), em = s.size, first = set.first;
		function advance(cp:Int, otherwise:Float):Float {
			var f = set.faceFor(cp);
			return f.has(cp) ? f.advance(f.glyph(cp)) * set.scale(f) : otherwise;
		}
		m = {
			ex: inlines.xHeight(id),
			ch: advance("0".code, em / 2),
			cap: capHeight(first) * set.scale(first),
			ic: advance(0x6C34, em),
			lineHeight: inlines.normalLineHeight(id)
		};
		measured.set(key, m);
		return m;
	}

	// (OS/2's sCapHeight, version 2 on; else the top of H; else the ascent: font units)
	static function capHeight(f:FontFile):Float {
		var os2 = f.table("OS/2");
		if (os2 != null && os2.length >= 90 && (os2.get(0) << 8 | os2.get(1)) >= 2) {
			var v = os2.get(88) << 8 | os2.get(89);
			if (v > 0 && v < 0x8000) return v;
		}
		var g = f.glyph("H".code);
		if (g != 0) {
			var b = f.bounds(g);
			if (b != null && b.length >= 4 && b[3] > 0) return b[3];
		}
		return f.ascender;
	}

	public static function size(style:BoxStyle):Float
		return style.css.fontSize();

	// ascent, descent (positive, below) and line gap in px, rounded as Chromium's SimpleFontData does
	public static function ascent(f:FontFile, size:Float):Float
		return Math.round(f.ascender * size / f.unitsPerEm);

	public static function descent(f:FontFile, size:Float):Float
		return Math.round(-f.descender * size / f.unitsPerEm);

	public static function lineGap(f:FontFile, size:Float):Float
		return Math.round(f.lineGap * size / f.unitsPerEm);

	// the x-height in px: OS/2's sxHeight (version 2 on), else half the size
	public static function xHeight(f:FontFile, size:Float):Float {
		var os2 = f.table("OS/2");
		if (os2 == null || os2.length < 90 || (os2.get(0) << 8 | os2.get(1)) < 2) return size / 2;
		var v = os2.get(86) << 8 | os2.get(87);
		return v == 0 ? size / 2 : v * size / f.unitsPerEm;
	}

	// the line-through's top above the baseline and its thickness, in px:
	// the OS/2 table's strikeout (yStrikeoutPosition, yStrikeoutSize), as
	// Chromium reads it; else half the x-height and the underline's
	public static function strikeout(f:FontFile, size:Float):{offset:Float, thickness:Float} {
		var m = lines(f), scale = size / f.unitsPerEm;
		if (m[2] > 0 && m[3] > 0) return {offset: m[3] * scale, thickness: Math.max(1, m[2] * scale)};
		var u = underline(f, size);
		return {offset: xHeight(f, size) / 2 + u.thickness / 2, thickness: u.thickness};
	}

	// (a face's underline position and thickness (post; 0x10000 none), its strikeout's thickness and position
	// (OS/2), in its units: read once, as each text a paint decorates asks)
	static function lines(f:FontFile):Array<Int> {
		var m = decorationLines.get(f);
		if (m != null) return m;
		var post = f.table("post"), os2 = f.table("OS/2");
		m = [0x10000, 0, 0, 0];
		if (post != null && post.length >= 12) {
			var pos = post.get(8) << 8 | post.get(9);
			m[0] = pos > 32767 ? pos - 65536 : pos;
			m[1] = post.get(10) << 8 | post.get(11);
		}
		if (os2 != null && os2.length >= 30) {
			var pos = os2.get(28) << 8 | os2.get(29);
			m[2] = os2.get(26) << 8 | os2.get(27);
			m[3] = pos > 32767 ? pos - 65536 : pos;
		}
		decorationLines.set(f, m);
		return m;
	}

	static final decorationLines = new haxe.ds.ObjectMap<FontFile, Array<Int>>();

	// the underline's centre below the baseline and its thickness (the post
	// table's: its position the stroke's top, FreeType's centre half its
	// thickness lower, which Chromium draws around), in px
	public static function underline(f:FontFile, size:Float):{offset:Float, thickness:Float} {
		var m = lines(f), scale = size / f.unitsPerEm;
		if (m[0] == 0x10000) return {offset: size / 10, thickness: Math.max(1, size / 16)};
		return {offset: (-m[0] + m[1] / 2) * scale, thickness: Math.max(1, m[1] * scale)};
	}
}
