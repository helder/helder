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
		var os2 = f.table("OS/2");
		var scale = size / f.unitsPerEm;
		if (os2 != null && os2.length >= 30) {
			var thick = os2.get(26) << 8 | os2.get(27), pos = os2.get(28) << 8 | os2.get(29);
			if (pos > 32767) pos -= 65536;
			if (thick > 0 && pos > 0) return {offset: pos * scale, thickness: Math.max(1, thick * scale)};
		}
		var u = underline(f, size);
		return {offset: xHeight(f, size) / 2 + u.thickness / 2, thickness: u.thickness};
	}

	// the underline's centre below the baseline and its thickness (the post
	// table's: its position the stroke's top, FreeType's centre half its
	// thickness lower, which Chromium draws around), in px
	public static function underline(f:FontFile, size:Float):{offset:Float, thickness:Float} {
		var post = f.table("post");
		var scale = size / f.unitsPerEm;
		if (post == null || post.length < 12) return {offset: size / 10, thickness: Math.max(1, size / 16)};
		var pos = (post.get(8) << 8 | post.get(9)), thick = post.get(10) << 8 | post.get(11);
		if (pos > 32767) pos -= 65536;
		return {offset: (-pos + thick / 2) * scale, thickness: Math.max(1, thick * scale)};
	}
}
