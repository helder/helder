package helder.ui.box;

import haxe.io.Bytes;
import helder.css.CssSheet;
import helder.css.CssTerm;
import helder.text.FontFile;
import helder.text.SystemFonts;

using StringTools;

// A computed font (family list, weight, style, stretch, size) matched to
// a helder.text face, as Fonts 4 §5 matches: each family in turn, a
// generic one the system's, a named one only when it is there (fonts
// registered here, @font-face's, then the system's), the closest weight
// and style of it. Metrics are rounded to pixels as Chromium's are.
class FontMatch {
	public final system:SystemFonts;

	final faces = new Map<String, Array<FontFile>>();
	final found = new Map<String, FontFile>();
	var families:Null<Map<String, Bool>> = null;

	public function new(?system:SystemFonts)
		this.system = system ?? SystemFonts.get();

	// a font file's faces under a family name (its own when null): Ahem for tests, @font-face's
	public function register(data:Bytes, ?family:String) {
		// (the inline layout's fonts are the system's: there by their own names too)
		system.add(data);
		for (i in 0...FontFile.faceCount(data)) {
			var f = try FontFile.parse(data, i) catch (_:Dynamic) null;
			if (f == null) continue;
			add(family ?? f.family, f);
		}
	}

	function add(family:String, f:FontFile) {
		var key = family.toLowerCase();
		var list = faces.get(key);
		if (list == null) faces.set(key, list = []);
		list.push(f);
		found.clear();
	}

	// @font-face rules (CssStyles.fontFaces), their sources loaded by URL (resolved against the sheet's)
	public function fontFaces(rules:Array<CssFontFace>, load:(url:String) -> Null<Bytes>) {
		for (r in rules) {
			var family:Null<String> = null, src:Null<String> = null;
			for (d in r.descriptors) {
				var text = helder.css.Css.serialize(d.value).trim();
				switch d.name.toLowerCase() {
					case "font-family": family = unquote(text);
					case "src": src = text;
					case _:
				}
			}
			if (family == null || src == null) continue;
			for (url in ~/url\(\s*["']?([^"')]+)["']?\s*\)/g.map(src, m -> m.matched(1) + "\n").split("\n")) {
				url = url.trim();
				if (url == "") continue;
				var bytes = load(helder.css.CssUrl.resolve(r.url, url));
				if (bytes != null) {
					register(bytes, family);
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
		var names = familyNames(style.terms("font-family"));
		var key = names.join(",") + "/" + weight + (italic ? "i" : "");
		var f = found.get(key);
		if (f != null) return f;
		for (name in names) {
			f = named(name, weight, italic);
			if (f != null) break;
		}
		if (f == null) f = system.match("serif", weight, italic);
		found.set(key, f);
		return f;
	}

	static function familyNames(terms:Array<CssTerm>):Array<String> {
		var out = [], word = [];
		for (t in terms) switch t {
			case Delim(","):
				if (word.length > 0) out.push(word.join(" "));
				word = [];
			case Ident(v) | Str(v): word.push(v);
			case Keyword(v): word.push(v);
			case _:
		}
		if (word.length > 0) out.push(word.join(" "));
		return out;
	}

	function named(name:String, weight:Int, italic:Bool):Null<FontFile> {
		var key = name.toLowerCase();
		var list = faces.get(key);
		if (list != null) return closest(list, weight, italic);
		switch key {
			case "serif" | "sans-serif" | "monospace": return system.match(key, weight, italic);
			case "cursive" | "fantasy" | "math" | "fangsong": return system.match("serif", weight, italic);
			case "system-ui" | "ui-sans-serif": return system.match("sans-serif", weight, italic);
			case "ui-serif": return system.match("serif", weight, italic);
			case "ui-monospace": return system.match("monospace", weight, italic);
			case _:
		}
		if (families == null) families = [for (f in system.families()) f.toLowerCase() => true];
		return families.exists(key) ? system.match(name, weight, italic) : null;
	}

	// (Fonts 4 §5.2: the style first, then the nearest weight, lighter below 400, heavier above 500)
	static function closest(list:Array<FontFile>, weight:Int, italic:Bool):FontFile {
		var styled = list.filter(f -> f.italic == italic);
		if (styled.length == 0) styled = list;
		var best = styled[0], score = Math.POSITIVE_INFINITY;
		for (f in styled) {
			var d = f.weight - weight;
			var s:Float = d == 0 ? 0 : weight < 400 ? (d < 0 ? -d : 1000 + d) : weight > 500 ? (d > 0 ? d : 1000 - d) : (d > 0 && f.weight <= 500 ? d : d < 0 ? 2000 - d : 3000 + d);
			if (s < score) {
				score = s;
				best = f;
			}
		}
		return best;
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

	// the underline's offset below the baseline and its thickness (the post table's), in px
	public static function underline(f:FontFile, size:Float):{offset:Float, thickness:Float} {
		var post = f.table("post");
		var scale = size / f.unitsPerEm;
		if (post == null || post.length < 12) return {offset: size / 10, thickness: Math.max(1, size / 16)};
		var pos = (post.get(8) << 8 | post.get(9)), thick = post.get(10) << 8 | post.get(11);
		if (pos > 32767) pos -= 65536;
		return {offset: -pos * scale, thickness: Math.max(1, thick * scale)};
	}
}
