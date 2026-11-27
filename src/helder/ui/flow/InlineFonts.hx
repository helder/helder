package helder.ui.flow;

import helder.text.FontFaces;
import helder.text.FontFaces.FontFaceDescriptors;
import helder.text.FontFaces.FontFaceStyle;
import helder.text.FontFaces.FontStyle;
import helder.text.FontFaces.Range;
import helder.text.FontFeature;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.SystemFonts;
import helder.ui.flow.InlineValues;

// The fonts of InlineStyles: font-family's list matched, a family the
// document's @font-face rules name by FontFaces (CSS Fonts 4 §5.2: its
// descriptors' ranges, unicode-range's composite faces), the others by
// SystemFonts (the first family there is, the others' faces tried after it
// for characters it lacks, then the system's fallbacks). A variable face
// is the instance the style asks for: wght, wdth, slnt or ital and opsz (at
// the size, font-optical-sizing: auto) from font-weight, font-stretch,
// font-style and font-size, font-variation-settings over them. A weight or
// style the face lacks is synthesized as font-synthesis allows: bold
// emboldened, italic or oblique slanted. font-feature-settings,
// font-kerning and font-variant-ligatures as OpenType features. Each set
// is made once and numbered (id: the shaped-word cache's key), with its
// metrics as Blink rounds them (ascent, descent and line gap to whole
// pixels), what line-height: normal and vertical-align read.
class InlineFonts {
	public static final shared = new InlineFonts(null, null, InlineShaper.shared);

	final fonts:SystemFonts;
	final faces:Null<FontFaces>;
	// the shaper of these sets (its cache keyed by their numbers: another InlineFonts' would collide)
	public final shaper:InlineShaper;
	final byKey = new Map<String, Int>();
	final byStyle = new haxe.ds.ObjectMap<InlineStyle, Int>();
	final sets:Array<FontSet> = [];
	final ascents:Array<Float> = [];
	final descents:Array<Float> = [];
	final gaps:Array<Float> = [];
	final xHeights:Array<Float> = [];
	// (the last style asked for, and its set: runs of one style)
	var lastStyle:Null<InlineStyle> = null;
	var lastId = -1;
	var generation = FontFile.generation;
	var facesGeneration = 0;
	// (the first set's number since the last clear)
	var base = 0;

	public function new(?fonts:SystemFonts, ?faces:FontFaces, ?shaper:InlineShaper) {
		this.fonts = fonts == null ? SystemFonts.get() : fonts;
		this.faces = faces;
		this.shaper = shaper ?? new InlineShaper();
	}

	// the number of a style's FontSet (set(id) is the set)
	public function idOf(style:InlineStyle):Int {
		if (generation != FontFile.generation || faces != null && facesGeneration != faces.generation) clear();
		if (style == lastStyle) return lastId;
		// (each style object once: styles are interned, so most are seen again; the key only for a style not seen)
		var known = byStyle.get(style);
		if (known != null) {
			lastStyle = style;
			return lastId = known;
		}
		var r:Request = {
			families: style.fontFamilies(),
			size: style.fontSize(),
			weight: style.fontWeight(),
			stretch: style.fontStretch(),
			style: switch style.fontStyle() {
				case InlineFontStyle.Italic: FontStyle.Italic;
				case InlineFontStyle.Oblique: FontStyle.Oblique(style.fontStyleAngle());
				case _: FontStyle.Normal;
			},
			synthesis: style.fontSynthesis(),
			optical: style.fontOpticalSizing(),
			features: featuresOf(style),
			variations: style.fontVariations(),
			emoji: style.fontEmoji()
		};
		var key = r.families.join(",") + "|" + r.size + "|" + r.weight + "|" + r.stretch + "|" + Std.string(r.style) + "|" + (r.synthesis : Int) + "|"
			+ r.optical + "|" + (r.emoji : Int) + "|" + (r.features == null ? "" : FontFeature.key(r.features)) + "|"
			+ (r.variations == null ? "" : [for (k => v in r.variations) k + "=" + v].join(","));
		var id = byKey.get(key);
		if (id == null) {
			id = base + sets.length;
			byKey.set(key, id);
			add(make(r));
		}
		byStyle.set(style, id);
		lastStyle = style;
		return lastId = id;
	}

	public inline function set(id:Int):FontSet
		return sets[id - base];

	// the metrics of a set, pixels: above the baseline, below it, the line
	// gap (each rounded, as Blink rounds them), the x-height
	public inline function ascent(id:Int):Float
		return ascents[id - base];

	public inline function descent(id:Int):Float
		return descents[id - base];

	public inline function lineGap(id:Int):Float
		return gaps[id - base];

	public inline function xHeight(id:Int):Float
		return xHeights[id - base];

	// line-height: normal's
	public inline function normalLineHeight(id:Int):Float
		return ascents[id - base] + descents[id - base] + gaps[id - base];

	// (a font replaced since: every set made again)
	function clear() {
		byKey.clear();
		fallbackSets.clear();
		byStyle.clear();
		// (numbers never given twice: the shaper's cache keeps the old ones' words)
		base += sets.length;
		sets.resize(0);
		ascents.resize(0);
		descents.resize(0);
		gaps.resize(0);
		xHeights.resize(0);
		lastStyle = null;
		generation = FontFile.generation;
		if (faces != null) facesGeneration = faces.generation;
	}

	function add(set:FontSet) {
		var f = set.first, s = set.scale(f);
		sets.push(set);
		ascents.push(Math.round(f.ascender * s));
		descents.push(Math.round(-f.descender * s));
		gaps.push(Math.round(f.lineGap * s));
		xHeights.push(xHeightOf(f) * s);
	}

	// (a generic family's keyword; a name in quotes, "serif", is a family's)
	public static function generic(name:String):Bool
		return switch name.toLowerCase() {
			case "serif" | "sans-serif" | "monospace" | "cursive" | "fantasy" | "system-ui" | "ui-sans-serif" | "ui-serif" | "ui-monospace" | "ui-rounded" | "math"
				| "emoji" | "fangsong":
				true;
			case _: false;
		}

	function make(r:Request):FontSet {
		// (each family there is, in order: the document's, else the system's; a named one neither has left out)
		var faces:Array<FontFile> = [], italic = !r.style.match(FontStyle.Normal);
		// (what the first family's face lacks: synthesized)
		var lacks:Null<{weight:Float, slanted:Bool}> = null;
		for (family in r.families) {
			var quoted = family.length > 1 && family.charAt(0) == '"' && family.charAt(family.length - 1) == '"';
			var name = quoted ? family.substr(1, family.length - 2) : family;
			var g = !quoted && generic(name);
			if (!g && this.faces != null && this.faces.has(name)) {
				var matched = this.faces.match(name, r.weight, r.stretch, r.style);
				for (k in 0...matched.length) {
					var m = matched[k], v = vary(m.file, m.weight, m.stretch, m.angle, m.style, r);
					if (!faces.contains(v.face)) faces.push(v.face);
					// (a face of a slanted style, whatever its axes give, or slanted by them: none synthesized)
					if (k == 0 && lacks == null) lacks = {weight: clamp(r.weight, m.weight), slanted: m.style != FontFaceStyle.Normal || v.slanted};
				}
				continue;
			}
			var f = g ? fonts.match(standIn(name), r.weight, italic) : fonts.named(name, r.weight, italic);
			if (f == null) continue;
			if (!g && f.family.toLowerCase() != name.toLowerCase()) continue;
			var own = FontFaceDescriptors.of(f), v = vary(f, own.weight, own.stretch, own.angle, own.style, r);
			f = v.face;
			if (!faces.contains(f)) faces.push(f);
			if (lacks == null) lacks = {weight: f.weight, slanted: f.italic && f.axes.length == 0 || v.slanted};
		}
		if (faces.length == 0) {
			var f = fonts.match("sans-serif", r.weight, italic);
			if (f == null) throw new haxe.Exception("InlineFonts: no font at all");
			faces.push(f);
			lacks = {weight: f.weight, slanted: f.italic};
		}
		var set = new FontSet(faces[0], faces.slice(1).concat(fallbacksAt(r.weight, italic)), r.size, fonts.fallbackFor, fonts.emojiFor);
		// (the first available font: the first whose unicode-range has the space)
		for (f in faces)
			if (inRange(f, " ".code)) {
				set.first = f;
				break;
			}
		var s:Int = r.synthesis;
		set.bold = r.weight >= 600 && lacks.weight < 600 && s & InlineSynthesis.Weight != 0;
		set.oblique = italic && !lacks.slanted && (s & InlineSynthesis.Style != 0 || r.style.match(FontStyle.Oblique(_)) && s & InlineSynthesis.Oblique != 0);
		if (r.features != null) set.features = r.features;
		set.presentation = r.emoji;
		return set;
	}

	// (a variable face's instance for the request: its axes the style's, as
	// far as its descriptors' ranges go (a face whose font-style is normal
	// is not slanted by its axes), font-variation-settings over them; the
	// face when that is its default. slanted: its slnt or ital set)
	static function vary(f:FontFile, weight:Range, stretch:Range, angle:Range, style:FontFaceStyle, r:Request):{face:FontFile, slanted:Bool} {
		var axes = f.axes;
		if (axes.length == 0) return {face: f, slanted: false};
		var v = new Map<String, Float>(), plain = true, slanted = false;
		for (a in axes) {
			var x = switch a.tag {
				case "wght": clamp(r.weight, weight);
				case "wdth": clamp(r.stretch, stretch);
				case "slnt": switch r.style {
						case FontStyle.Oblique(deg): -clamp(deg, angle);
						case FontStyle.Italic if (!hasAxis(f, "ital")): -clamp(14, angle);
						case _: 0;
					}
				case "ital": r.style.match(FontStyle.Italic) && style != FontFaceStyle.Normal ? 1 : 0;
				case "opsz": r.optical ? r.size : a.def;
				case _: a.def;
			}
			if (r.variations != null && r.variations.exists(a.tag)) x = r.variations.get(a.tag);
			x = Math.max(a.min, Math.min(a.max, x));
			if (x != a.def) plain = false;
			if (a.tag == "slnt" && x != 0 || a.tag == "ital" && x >= 1) slanted = true;
			v.set(a.tag, x);
		}
		// (SystemFonts' instance at a weight: the base face's default asked for again)
		return {face: plain && !f.varied ? f : f.instance(v), slanted: slanted};
	}

	static function hasAxis(f:FontFile, tag:String):Bool {
		for (a in f.axes) if (a.tag == tag) return true;
		return false;
	}

	static function inRange(f:FontFile, cp:Int):Bool {
		var r = f.unicodeRange, i = 0;
		while (r != null && i < r.length) {
			if (cp >= r[i] && cp <= r[i + 1]) return true;
			i += 2;
		}
		return r == null;
	}

	static inline function clamp(v:Float, r:Range):Float
		return v < r.min ? r.min : v > r.max ? r.max : v;

	// (the system's fallback faces at a weight and style: each fallback
	// family's face closest to them, as a browser's fallback keeps the text's
	// weight and style (bold Arabic in DejaVu Sans Bold), its regular face
	// where it has no other)
	final fallbackSets = new Map<String, Array<FontFile>>();

	function fallbacksAt(weight:Int, italic:Bool):Array<FontFile> {
		var key = weight + (italic ? "i" : "");
		var out = fallbackSets.get(key);
		if (out != null) return out;
		out = [];
		for (f in fonts.fallbacks()) {
			var g = weight == 400 && !italic ? f : fonts.named(f.family, weight, italic);
			if (g == null || g.family.toLowerCase() != f.family.toLowerCase()) g = f;
			if (!out.contains(g)) out.push(g);
		}
		fallbackSets.set(key, out);
		return out;
	}

	// (the generic families SystemFonts has no list for, as FontMatch takes them)
	static function standIn(name:String):String
		return switch name.toLowerCase() {
			case "cursive" | "fantasy" | "math" | "fangsong" | "ui-serif": "serif";
			case "system-ui" | "ui-sans-serif" | "ui-rounded": "sans-serif";
			case "ui-monospace": "monospace";
			case n: n;
		}

	// font-feature-settings with font-kerning and font-variant-ligatures as features
	static function featuresOf(style:InlineStyle):Null<Array<FontFeature>> {
		var out:Array<FontFeature> = [];
		if (style.fontKerning() == None) out.push({tag: "kern", value: 0});
		var l:Int = style.fontLigatures();
		if (l & (InlineLigatures.NoCommon | InlineLigatures.None) != 0) {
			out.push({tag: "liga", value: 0});
			out.push({tag: "clig", value: 0});
		}
		if (l & (InlineLigatures.NoContextual | InlineLigatures.None) != 0) out.push({tag: "calt", value: 0});
		if (l & InlineLigatures.Discretionary != 0 && l & InlineLigatures.None == 0) out.push({tag: "dlig", value: 1});
		if (l & InlineLigatures.Historical != 0 && l & InlineLigatures.None == 0) out.push({tag: "hlig", value: 1});
		var asked = style.fontFeatures();
		if (asked != null)
			for (f in asked) {
				for (o in out.copy())
					if (o.tag == f.tag) out.remove(o);
				out.push(f);
			}
		return out.length == 0 ? null : out;
	}

	// (OS/2's sxHeight, else the top of x's glyph, else half the em: font units)
	static function xHeightOf(f:FontFile):Float {
		var os2 = f.table("OS/2");
		if (os2 != null && os2.length >= 90 && (os2.get(0) << 8 | os2.get(1)) >= 2) {
			var v = os2.get(86) << 8 | os2.get(87);
			if (v > 0 && v < 0x8000) return v;
		}
		var g = f.glyph("x".code);
		if (g != 0) {
			var b = f.bounds(g);
			if (b != null && b.length >= 4 && b[3] > 0) return b[3];
		}
		return f.unitsPerEm / 2;
	}
}

private typedef Request = {
	families:Array<String>,
	size:Float,
	weight:Int,
	stretch:Float,
	style:FontStyle,
	synthesis:InlineSynthesis,
	optical:Bool,
	features:Null<Array<FontFeature>>,
	variations:Null<Map<String, Float>>,
	emoji:InlineEmoji
}
