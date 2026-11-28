package helder.ui.fast;

import helder.css.CssTerm;
import helder.ui.box.BoxStyle;
import helder.ui.box.Len;
import helder.ui.fast.Style.Props;
import helder.ui.fast.Style.Tint;
import helder.ui.flow.InlineBasicStyle;

// A style resolved for a node: in its states, under its parent's text
// part (what it inherits) and in its theme, as the box tree's typed style
// (BoxStyle), once for each of those it meets (a style on a thousand rows
// in one state, parent and theme: one resolve). A view is what helder.ui's
// is (ua/app.css's): a column flex container, relative, border-box sizes,
// flex 0 1 auto; a text a block of inline runs.
class Resolve {
	public static inline var VIEW = 0;
	public static inline var TEXT = 1;
	// (a text in a text: one of its runs, an inline box)
	public static inline var SPAN = 2;

	// what a change of one resolved style to another takes (Tree's): nothing, a paint, a paint order, a layout
	public static inline var NOTHING = 0;
	public static inline var PAINT = 1;
	public static inline var ORDER = 2;
	public static inline var LAYOUT = 3;

	// the root's text: app.css's :root, sans-serif 14px, a line 1.25 of it, black, words broken to fit
	public static final root:InlineBasicStyle = {
		var t = new InlineBasicStyle();
		t.families = ["sans-serif"];
		t.size = 14;
		t.height = 14 * 1.25;
		t.colour = 0xFF000000;
		t.overflow = BreakWord;
		t;
	}

	// (each style's resolutions: mask, parent text, theme, kind, the box style, 5 a resolution)
	static final cache = new haxe.ds.ObjectMap<Style, Array<Dynamic>>();

	public static function of(style:Style, mask:Int, parent:InlineBasicStyle, theme:Theme, kind:Int):BoxStyle {
		// (states it has no variant for change nothing: one resolution for them all)
		mask &= style.states;
		var list = cache.get(style);
		if (list == null) cache.set(style, list = []);
		var k = 0;
		while (k < list.length) {
			if (list[k] == mask && list[k + 1] == parent && list[k + 2] == theme && list[k + 3] == kind) return list[k + 4];
			k += 5;
		}
		var s = make(style.at(mask, theme.dark), parent, theme, kind);
		list.push(mask);
		list.push(parent);
		list.push(theme);
		list.push(kind);
		list.push(s);
		return s;
	}

	public static function level(a:BoxStyle, b:BoxStyle):Int {
		if (a == b) return NOTHING;
		var x:Resolved = cast a, y:Resolved = cast b;
		if (x.layoutKey() != y.layoutKey()) return LAYOUT;
		if (x.stacking() != y.stacking() || x.props.zIndex != y.props.zIndex) return ORDER;
		return PAINT;
	}

	static function make(p:Props, parent:InlineBasicStyle, theme:Theme, kind:Int):BoxStyle {
		var s = new Resolved(p);
		var t = text(p, parent, theme);
		s.textPart = t;
		// (display: a view a column flex container, or a block where it says; a text a block of inline runs, whatever
		// it says but none)
		s.displayRead = true;
		var d = p.display;
		if (d == None) s.displayNone = true;
		s.displayOuter = kind == SPAN ? BoxStyle.INLINE : BoxStyle.BLOCK;
		s.displayInner = kind != VIEW || d == Block ? BoxStyle.FLOW : BoxStyle.FLEX;
		// (the box model: border-box)
		var pad = p.padding, mar = p.margin, bw = p.borderWidth;
		for (k in 0...4) {
			s.margin.push(Px(mar == null ? 0 : (mar : Array<Float>)[k]));
			s.padding.push(Px(pad == null ? 0 : (pad : Array<Float>)[k]));
			s.border.push(bw == null ? 0 : (bw : Array<Float>)[k]);
		}
		s.width = p.width ?? Auto;
		s.height = p.height ?? Auto;
		s.minWidth = p.minWidth ?? Auto;
		s.minHeight = p.minHeight ?? Auto;
		s.maxWidth = p.maxWidth ?? Auto;
		s.maxHeight = p.maxHeight ?? Auto;
		s.borderBox = true;
		s.modelRead = true;
		// (flex and alignment)
		s.orderValue = 0;
		s.growValue = p.flexGrow ?? 0;
		s.shrinkValue = p.flexShrink ?? 1;
		s.basisValue = p.flexBasis ?? Auto;
		s.basisWord = p.flexBasis == null ? "auto" : "";
		s.directionValue = switch p.flexDirection {
			case Row: "row";
			case RowReverse: "row-reverse";
			case ColumnReverse: "column-reverse";
			case _: "column";
		}
		s.wrapValue = p.flexWrap == true ? "wrap" : "nowrap";
		s.aligns.push(justify(p.justifyContent));
		s.aligns.push(content(p.alignContent));
		s.aligns.push(align(p.alignItems, "stretch"));
		s.aligns.push(align(p.alignSelf, "auto"));
		s.aligns.push("legacy");
		s.aligns.push("auto");
		var rg = p.rowGap ?? p.gap, cg = p.columnGap ?? p.gap;
		s.rowGapValue = rg == null ? Auto : Px(rg);
		s.columnGapValue = cg == null ? Auto : Px(cg);
		for (v in [p.top, p.right, p.bottom, p.left]) s.insets.push(v ?? Auto);
		s.layoutRead = true;
		// (traits: relative, or absolute; its overflow; its text's)
		s.positionWord = switch p.position {
			case Absolute: "absolute";
			case Sticky: "sticky";
			case _: "relative";
		}
		var ov = p.overflow, cut = p.textOverflow != null && p.textOverflow != Clip;
		var bits = (ov != null && ov != Visible ? BoxStyle.CLIPS : 0) | (cut ? BoxStyle.CUTS : 0) | (ov == Scroll ? BoxStyle.SCROLLS : 0)
			| (ov == Hidden ? BoxStyle.HIDDEN_OVERFLOW : 0) | BoxStyle.VISIBLE | BoxStyle.COLLAPSE
			| (t.wrap == Wrap ? BoxStyle.WRAPS : 0);
		var opacity = p.opacity ?? 1.0;
		if (opacity < 1 || p.zIndex != null) bits |= BoxStyle.STACKS;
		s.traits = bits;
		s.opacityValue = opacity;
		if (p.zIndex != null) {
			var r = new helder.ui.box.BoxRare();
			r.zIndex = p.zIndex;
			s.rareRead = r;
		}
		// (paint: its background, corners, borders)
		s.bgColor = p.background == null ? 0 : tint(p.background, theme, t.colour);
		var r = p.borderRadius;
		if (r != null && r > 0) s.radiusTerms = [for (_ in 0...8) Dimension(r, "px")];
		var bc = p.borderColor == null ? 0 : tint(p.borderColor, theme, t.colour);
		for (k in 0...4) {
			s.sideStyles.push(bw != null && (bw : Array<Float>)[k] > 0 ? "solid" : "none");
			s.sideColors.push(bc);
		}
		s.paintRead = true;
		return s;
	}

	// (the text part: the parent's where the style says nothing inherited; else a copy with what it says, for
	// all that resolve it under that parent)
	static function text(p:Props, parent:InlineBasicStyle, theme:Theme):InlineBasicStyle {
		if (p.color == null && p.fontSize == null && p.fontWeight == null && p.fontFamily == null && p.fontStyle == null && p.lineHeight == null
			&& p.letterSpacing == null && p.textAlign == null && p.wrap == null && p.textOverflow == null && p.lineClamp == null && p.textDecoration == null) return parent;
		var t = parent.copy();
		if (p.fontSize != null) {
			// (a line height a multiple of the size: the parent's multiple at the new size)
			var multiple = parent.height / parent.size;
			t.size = p.fontSize;
			if (p.lineHeight == null && multiple == multiple) t.height = multiple * t.size;
		}
		if (p.lineHeight != null) t.height = p.lineHeight * t.size;
		if (p.fontWeight != null) t.weight = p.fontWeight;
		if (p.fontFamily != null) t.families = [p.fontFamily];
		if (p.fontStyle != null) t.style = p.fontStyle == Italic ? Italic : Normal;
		if (p.letterSpacing != null) t.letters = p.letterSpacing;
		if (p.textAlign != null) t.align = switch p.textAlign {
			case Center: Center;
			case Right: Right;
			case Justify: Justify;
			case _: Left;
		}
		if (p.wrap != null) t.wrap = p.wrap ? Wrap : NoWrap;
		// (not inherited in CSS: a text's alone, its runs' in it)
		if (p.textOverflow != null) t.textOverflowEnd = p.textOverflow == Clip ? Clip : Ellipsis;
		if (p.lineClamp != null) t.clamp = p.lineClamp;
		if (p.textDecoration != null) {
			var d = p.textDecoration;
			t.decoration = (d & (helder.ui.TextDecoration.Underline : Int) != 0 ? 1 : 0) | (d & (helder.ui.TextDecoration.Overline : Int) != 0 ? 2 : 0) | (d & (helder.ui.TextDecoration.LineThrough : Int) != 0 ? 4 : 0);
		}
		if (p.color != null) t.colour = tint(p.color, theme, parent.colour);
		t.decorationColour = t.colour;
		return t;
	}

	static function tint(v:Tint, theme:Theme, current:Int):Int
		return switch (v : Style.TintValue) {
			case Plain(c): c;
			case Token(name): theme.color(name);
			case Current: current;
		}

	static function justify(j:Null<helder.ui.Justify>):String
		return switch j {
			case null | Normal: "normal";
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case SpaceBetween: "space-between";
			case SpaceAround: "space-around";
			case SpaceEvenly: "space-evenly";
		}

	static function content(a:Null<helder.ui.AlignContent>):String
		return switch a {
			case null | Normal: "normal";
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case Stretch: "stretch";
			case SpaceBetween: "space-between";
			case SpaceAround: "space-around";
			case SpaceEvenly: "space-evenly";
		}

	static function align(a:Null<helder.ui.Align>, fallback:String):String
		return switch a {
			case null: fallback;
			case Auto: "auto";
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case Stretch: "stretch";
			case Baseline: "baseline";
		}
}

// (a style resolved: what it was resolved from, what of it a layout reads written out once)
private class Resolved extends BoxStyle {
	public final props:Props;
	var key:Null<String> = null;

	public function new(props:Props) {
		super();
		this.props = props;
	}

	// (all but what paints alone: colours, corners, opacity and z-index; its text's size and font in it)
	public function layoutKey():String {
		if (key != null) return key;
		var p = new Props();
		p.display = props.display;
		p.flexDirection = props.flexDirection;
		p.flexWrap = props.flexWrap;
		p.alignItems = props.alignItems;
		p.alignSelf = props.alignSelf;
		p.justifyContent = props.justifyContent;
		p.alignContent = props.alignContent;
		p.flexGrow = props.flexGrow;
		p.flexShrink = props.flexShrink;
		p.flexBasis = props.flexBasis;
		p.gap = props.gap;
		p.rowGap = props.rowGap;
		p.columnGap = props.columnGap;
		p.width = props.width;
		p.height = props.height;
		p.minWidth = props.minWidth;
		p.minHeight = props.minHeight;
		p.maxWidth = props.maxWidth;
		p.maxHeight = props.maxHeight;
		p.padding = props.padding;
		p.margin = props.margin;
		p.borderWidth = props.borderWidth;
		p.overflow = props.overflow;
		p.position = props.position;
		p.top = props.top;
		p.right = props.right;
		p.bottom = props.bottom;
		p.left = props.left;
		return key = Style.write(p) + "|" + text.size + " " + text.height + " " + text.weight + " " + text.families.join(",") + " " + text.style + " " + text.letters
			+ " " + text.align + " " + text.wrap + " " + text.textOverflowEnd + " " + text.clamp;
	}
}
