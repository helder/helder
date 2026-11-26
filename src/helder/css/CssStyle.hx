package helder.css;

import helder.css.CssComputed;
import helder.css.CssDisplay;
import helder.css.CssGroups;
import helder.css.CssKeywords;
import helder.css.CssProperty;
import helder.css.CssTerm;

// An element's (or a pseudo-element's) computed style: a pointer per group
// of properties (CssGroups), typed values in each, the inherited groups its
// parent's unless something in them is set, every group interned. Shared
// by the elements whose cascade and parent style are the same, and never
// changed. Read typed (style.box.display, style.length(Width)) or as text
// (getComputedStyle's, for tests and tools).
//
//   var s = styles.computed(el);
//   s.spacing.marginTop.value;          // px
//   s.box.position == Absolute;
//   s.text("margin");                   // "8px 0px"
class CssStyle extends CssStyleGroups {
	// the custom properties: name to value, null for the guaranteed-invalid one
	public final customs:Map<String, Null<Array<CssValue>>>;
	@:allow(helder.css) final styles:CssStyles;
	@:allow(helder.css) var id = -1;

	@:allow(helder.css)
	function new(styles:CssStyles, groups:Array<CssGroup>, customs:Map<String, Null<Array<CssValue>>>) {
		this.styles = styles;
		this.customs = customs;
		for (k in 0...groups.length) setGroup(k, groups[k]);
	}

	// ---- typed

	// The property's computed value as terms (a logical one's physical one's).
	public function terms(p:CssProperty):Array<CssTerm> {
		p = physical(p);
		return group(CssProperties.groupOf(p)).terms(p);
	}

	inline function physical(p:CssProperty):CssProperty
		return CssProperties.logical(p) ? CssProperties.physical(p, inheritedText.direction == Rtl) : p;

	// The typed reads below return what the group holds, no allocation, for
	// a property of their kind (a length's, a colour's...); one kept as terms
	// (text-indent) is read from its terms.

	// A length, percentage, number or keyword property's value (a margin, a
	// size, line-height...); OTHER (kind Other) for anything else.
	public function length(p:CssProperty):CssLength {
		p = physical(p);
		var g = group(CssProperties.groupOf(p));
		var l = g.lengthOf(p);
		if (l != null) return l;
		// (a value kept as terms, text-indent's: its one term read, interned)
		return switch g.terms(p) {
			case [t]: styles.intern.length([t]) ?? CssLength.OTHER;
			case _: CssLength.OTHER;
		}
	}

	// The length in px against what a percentage refers to (NaN for a keyword).
	public inline function resolve(p:CssProperty, basis:Float):Float
		return length(p).resolve(basis);

	// A value that is always absolute (border widths, spacing), in px; NaN otherwise.
	public function px(p:CssProperty):Float {
		var l = length(p);
		return l.kind == Px ? l.value : Math.NaN;
	}

	// A colour property's value, currentcolor as the element's color.
	public function color(p:CssProperty):CssRgba {
		p = physical(p);
		var g = group(CssProperties.groupOf(p));
		var c = g.rgbaOf(p) ?? switch g.terms(p) {
			case [t]: styles.intern.rgba([t]) ?? CssRgba.OTHER;
			case _: CssRgba.OTHER;
		}
		return c.resolve(inheritedText.color);
	}

	// A number property's value (opacity, z-index, flex-grow...); NaN for a keyword.
	public function number(p:CssProperty):Float {
		p = physical(p);
		var g = group(CssProperties.groupOf(p));
		var n = g.numberOf(p);
		if (n == n) return n;
		var l = g.lengthOf(p);
		if (l != null) return l.kind == Plain ? l.value : Math.NaN;
		return switch g.terms(p) {
			case [Number(v, _)]: v;
			case _: Math.NaN;
		}
	}

	// A value that is one keyword: it; else null.
	public function keyword(p:CssProperty):Null<String> {
		p = physical(p);
		var g = group(CssProperties.groupOf(p));
		var k = g.keywordOf(p);
		if (k >= 0) return CssProperties.keywords(p)[k];
		var l = g.lengthOf(p);
		if (l != null) return l.keyword;
		var c = g.rgbaOf(p);
		if (c != null) return c.keyword;
		// (a keyword the field can't hold, or a value kept as terms: read there)
		if (k != -2 && CssProperties.kindOf(p) != 5 && CssProperties.kindOf(p) != 4) return null;
		return switch g.terms(p) {
			case [Keyword(w)]: w;
			case _: null;
		}
	}

	// The background layers, each list repeated to background-image's length.
	public inline function backgrounds():Array<CssItems.CssBackgroundLayer>
		return CssItems.backgrounds(this);

	// The generated content as items; null for normal and none.
	public inline function generated():Null<Array<CssItems.CssContentItem>>
		return CssItems.content(terms(Content));

	// counter-reset's, counter-increment's or counter-set's counters.
	public inline function counters(p:CssProperty):Array<CssItems.CssCounter>
		return CssItems.counters(terms(p));

	// The font families, generics as their keywords.
	public inline function families():Array<String>
		return CssItems.families(font.fontFamily);

	public var display(get, never):CssDisplay;

	inline function get_display():CssDisplay
		return box.display;

	// The font size in px (em's for every property but font-size).
	public inline function fontSize():Float
		return font.fontSize.kind == Px ? font.fontSize.value : 16;

	// The line height in px (lh's); null for normal, the first available
	// font's metrics, which wait on fonts.
	public function lineHeight():Null<Float> {
		var l = font.lineHeight;
		return l.kind == Px ? l.value : l.kind == Plain ? l.value * fontSize() : null;
	}

	// ---- as text

	// The computed value as getComputedStyle writes it (a shorthand's from
	// its longhands; a custom property's as substituted).
	public function get(property:String):Array<CssTerm> {
		var p = CssProperties.of(Css.lower(property));
		return p == null ? [] : terms(p);
	}

	public function text(property:String):String {
		if (StringTools.startsWith(property, "--")) {
			var v = customs.get(property);
			return v == null ? "" : StringTools.trim(Css.serialize(v));
		}
		var name = Css.lower(property);
		var d = CssGrammars.property(name);
		if (d == null) return "";
		if (d.alias != null) name = d.alias;
		if (CssShorthands.isShorthand(name)) {
			var ls = CssShorthands.longhands(name);
			var texts = [for (l in ls) l => text(l)];
			var initials = [for (l in ls) l => styles.initialText(l, this)];
			return CssShorthands.serialize(name, texts, true, initials);
		}
		// (page-break-* as Break 3 §3.4 maps break-*'s values)
		if (StringTools.startsWith(name, "page-break-")) return switch text("break-" + name.substr(11)) {
			case "page": "always";
			case v = "left" | "right" | "avoid": v;
			case _: "auto";
		}
		var p = CssProperties.of(name);
		return p == null ? "" : CssValues.written(name, terms(p), context());
	}

	// (what writing needs: currentcolor's colour, and em for colours' math)
	@:allow(helder.css)
	function context():CssComputeContext {
		var media = styles.media;
		return {
			fontSize: fontSize(),
			parentFontSize: fontSize(),
			rootFontSize: styles.rootFontSize(),
			viewport: {width: media.width, height: media.height},
			color: CssValues.written("color", terms(Color), {})
		};
	}
}
