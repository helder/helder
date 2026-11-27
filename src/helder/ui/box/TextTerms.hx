package helder.ui.box;

import helder.css.CssTerm;
import helder.text.FontFeature;
import helder.ui.flow.InlineValues;

using StringTools;

// The text properties' computed terms as the inline engine's values (a
// BoxStyle's text part, read once from the cascade's style).
class TextTerms {
	public static function variations(t:Array<CssTerm>):Null<Map<String, Float>> {
		if (t.length == 0 || t[0].match(Keyword("normal"))) return null;
		var out = new Map<String, Float>(), tag:Null<String> = null;
		for (x in t) switch x {
			case Str(v): tag = v;
			case Number(v, _) if (tag != null): out.set(tag, v);
			case _:
		}
		return out;
	}

	// font-variant-caps, -numeric, -east-asian, -position and historical-forms
	// as their features, font-feature-settings' over them (CSS Fonts 4 §7.2)
	public static function features(s:CssBoxStyle):Null<Array<FontFeature>> {
		var out:Array<FontFeature> = [];
		for (p in ["font-variant-caps", "font-variant-numeric", "font-variant-east-asian", "font-variant-position", "font-variant-alternates"])
			for (t in s.terms(p)) switch t {
				case Keyword(v): for (tag in VARIANTS.get(v) ?? []) out.push({tag: tag, value: 1});
				case _:
			}
		var asked = settings(s.terms("font-feature-settings"));
		if (asked != null)
			for (f in asked) {
				for (o in out.copy())
					if (o.tag == f.tag) out.remove(o);
				out.push(f);
			}
		return out.length == 0 ? null : out;
	}

	static final VARIANTS = [
		"small-caps" => ["smcp"], "all-small-caps" => ["smcp", "c2sc"], "petite-caps" => ["pcap"], "all-petite-caps" => ["pcap", "c2pc"],
		"unicase" => ["unic"], "titling-caps" => ["titl"], "lining-nums" => ["lnum"], "oldstyle-nums" => ["onum"], "proportional-nums" => ["pnum"],
		"tabular-nums" => ["tnum"], "diagonal-fractions" => ["frac"], "stacked-fractions" => ["afrc"], "ordinal" => ["ordn"], "slashed-zero" => ["zero"],
		"jis78" => ["jp78"], "jis83" => ["jp83"], "jis90" => ["jp90"], "jis04" => ["jp04"], "simplified" => ["smpl"], "traditional" => ["trad"],
		"full-width" => ["fwid"], "proportional-width" => ["pwid"], "ruby" => ["ruby"], "sub" => ["subs"], "super" => ["sups"], "historical-forms" => ["hist"]
	];

	static function settings(t:Array<CssTerm>):Null<Array<FontFeature>> {
		if (t.length == 0 || t[0].match(Keyword("normal"))) return null;
		var text = [for (x in t) switch x {
			case Str(v): "'" + v + "'";
			case Number(v, _): Std.string(Std.int(v));
			case Keyword(v): v;
			case Delim(","): ",";
			case _: "";
		}].join(" ").replace(" ,", ",");
		return FontFeature.parse(text);
	}

	public static function ligatures(t:Array<CssTerm>):InlineLigatures {
		var v = 0;
		for (x in t) switch x {
			case Keyword("none"): v |= InlineLigatures.None;
			case Keyword("no-common-ligatures"): v |= InlineLigatures.NoCommon;
			case Keyword("no-contextual"): v |= InlineLigatures.NoContextual;
			case Keyword("discretionary-ligatures"): v |= InlineLigatures.Discretionary;
			case Keyword("historical-ligatures"): v |= InlineLigatures.Historical;
			case _:
		}
		return v;
	}

	public static function transform(t:Array<CssTerm>):InlineTransform {
		var v = 0;
		for (x in t) switch x {
			case Keyword("capitalize"): v |= InlineTransform.Capitalize;
			case Keyword("uppercase"): v |= InlineTransform.Uppercase;
			case Keyword("lowercase"): v |= InlineTransform.Lowercase;
			case Keyword("full-width"): v |= InlineTransform.FullWidth;
			case Keyword("full-size-kana"): v |= InlineTransform.FullSizeKana;
			case _:
		}
		return v;
	}

	public static function align(v:String, fallback:InlineAlign):InlineAlign
		return switch v {
			case "start": Start;
			case "end": End;
			case "left" | "-webkit-left": Left;
			case "right" | "-webkit-right": Right;
			case "center" | "-webkit-center": Center;
			case "justify": Justify;
			case "match-parent": MatchParent;
			case "auto": Auto;
			case _: fallback;
		}

	public static function vertical(kind:String):InlineVerticalAlign
		return switch kind {
			case "sub": Sub;
			case "super": Super;
			case "text-top": TextTop;
			case "text-bottom": TextBottom;
			case "middle": Middle;
			case "top": Top;
			case "bottom": Bottom;
			case "length": Length;
			case "percent": Percent;
			case _: Baseline;
		}

	public static function decoration(t:Array<CssTerm>):InlineDecoration {
		var v = 0;
		for (x in t) switch x {
			case Keyword("underline"): v |= InlineDecoration.Underline;
			case Keyword("overline"): v |= InlineDecoration.Overline;
			case Keyword("line-through"): v |= InlineDecoration.LineThrough;
			case _:
		}
		return v;
	}
}
