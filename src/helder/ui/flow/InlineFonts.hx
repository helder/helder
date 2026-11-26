package helder.ui.flow;

import helder.text.FontFeature;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.SystemFonts;
import helder.ui.flow.InlineValues;

// The fonts of InlineStyles: font-family's list matched by SystemFonts (the
// first family it has, the others' faces tried after it for characters it
// lacks, then the system's fallbacks), the italic and weight asked for (an
// italic a face does not have drawn oblique), font-feature-settings,
// font-kerning and font-variant-ligatures as OpenType features. Each set
// is made once and numbered (id: the shaped-word cache's key), with its
// metrics as Blink rounds them (ascent, descent and line gap to whole
// pixels), what line-height: normal and vertical-align read.
class InlineFonts {
	public static final shared = new InlineFonts();

	final fonts:SystemFonts;
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

	public function new(?fonts:SystemFonts)
		this.fonts = fonts == null ? SystemFonts.get() : fonts;

	// the number of a style's FontSet (set(id) is the set)
	public function idOf(style:InlineStyle):Int {
		if (generation != FontFile.generation) clear();
		if (style == lastStyle) return lastId;
		// (each style object once: styles are interned, so most are seen again; the key only for a style not seen)
		var known = byStyle.get(style);
		if (known != null) {
			lastStyle = style;
			return lastId = known;
		}
		var families = style.fontFamilies(), size = style.fontSize(), weight = style.fontWeight(), slant = style.fontStyle() != Normal;
		var features = featuresOf(style), variations = style.fontVariations();
		var key = families.join(",") + "|" + size + "|" + weight + "|" + slant + "|" + (features == null ? "" : FontFeature.key(features)) + "|"
			+ (variations == null ? "" : [for (k => v in variations) k + "=" + v].join(","));
		var id = byKey.get(key);
		if (id == null) {
			id = sets.length;
			byKey.set(key, id);
			add(make(families, size, weight, slant, features, variations));
		}
		byStyle.set(style, id);
		lastStyle = style;
		return lastId = id;
	}

	public inline function set(id:Int):FontSet
		return sets[id];

	// the metrics of a set, pixels: above the baseline, below it, the line
	// gap (each rounded, as Blink rounds them), the x-height
	public inline function ascent(id:Int):Float
		return ascents[id];

	public inline function descent(id:Int):Float
		return descents[id];

	public inline function lineGap(id:Int):Float
		return gaps[id];

	public inline function xHeight(id:Int):Float
		return xHeights[id];

	// line-height: normal's
	public inline function normalLineHeight(id:Int):Float
		return ascents[id] + descents[id] + gaps[id];

	// (a font replaced since: every set made again)
	function clear() {
		byKey.clear();
		byStyle.clear();
		sets.resize(0);
		ascents.resize(0);
		descents.resize(0);
		gaps.resize(0);
		xHeights.resize(0);
		lastStyle = null;
		generation = FontFile.generation;
	}

	function add(set:FontSet) {
		var f = set.primary, s = set.scale(f);
		sets.push(set);
		ascents.push(Math.round(f.ascender * s));
		descents.push(Math.round(-f.descender * s));
		gaps.push(Math.round(f.lineGap * s));
		xHeights.push(xHeightOf(f) * s);
	}

	static function generic(name:String):Bool
		return switch name.toLowerCase() {
			case "serif" | "sans-serif" | "monospace" | "cursive" | "fantasy" | "system-ui" | "ui-sans-serif" | "ui-serif" | "ui-monospace" | "ui-rounded" | "math"
				| "emoji" | "fangsong":
				true;
			case _: false;
		}

	function make(families:Array<String>, size:Float, weight:Int, italic:Bool, features:Null<Array<FontFeature>>, variations:Null<Map<String, Float>>):FontSet {
		// (each family the system has, in order; a named one it lacks left out)
		var faces:Array<FontFile> = [];
		for (name in families) {
			var g = generic(name), f = fonts.match(name, weight, italic);
			if (f == null) continue;
			if (!g && f.family.toLowerCase() != name.toLowerCase()) continue;
			if (variations != null && f.axes.length > 0) f = f.instance(variations);
			if (!faces.contains(f)) faces.push(f);
		}
		if (faces.length == 0) {
			var f = fonts.match("sans-serif", weight, italic);
			if (f == null) throw new haxe.Exception("InlineFonts: no font at all");
			faces.push(f);
		}
		var set = new FontSet(faces[0], faces.slice(1).concat(fonts.fallbacks()), size, fonts.fallbackFor, fonts.emojiFor);
		set.oblique = italic && !faces[0].italic;
		if (features != null) set.features = features;
		return set;
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
