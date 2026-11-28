package helder.ui;

import helder.gfx.Color;
import helder.ui.Style.Edges;
import helder.ui.Style.Measure;
import helder.ui.Style.Props;
import helder.ui.Style.Tint;
import helder.ui.Style.TintValue;
import helder.ui.box.Len;

using StringTools;

// Markup's style attributes on a fast node (FastRenderer's): a name as
// StyleProps has it (CSS's in camel), its value as markup gives it, a
// number, a Bool, the field's own type or a string as CSS writes it
// ("8 12", "#3b82f6", "space-between", "50%"). A small parser of its own:
// no helder.css.
class Attrs {
	// (a style with attributes over it, by its key and theirs as markup gave them: the rows of a list one)
	static final made = new Map<String, Style>();

	// The style with attributes over it (name and value in turn).
	public static function styled(style:Style, attrs:Array<Dynamic>):Style {
		var key = new StringBuf();
		key.add(@:privateAccess style.key);
		var i = 0;
		while (i < attrs.length) {
			key.add("|");
			key.add(attrs[i]);
			key.add("=");
			var v:Dynamic = attrs[i + 1];
			// (a value written as itself: a string, a number, true; another (a Style's tint, a Len) by its text)
			key.add(Std.isOfType(v, String) ? (v : String) : Std.string(v));
			i += 2;
		}
		var k = key.toString(), s = made.get(k);
		if (s == null) {
			var p = new Props();
			i = 0;
			while (i < attrs.length) {
				set(p, attrs[i], attrs[i + 1]);
				i += 2;
			}
			made.set(k, s = style.over(p));
		}
		return s;
	}

	// whether a name is a style attribute's
	public static function styles(name:String):Bool
		return NAMES.exists(name);

	static final NAMES = [
		for (n in [
			"display", "flexDirection", "flexWrap", "alignItems", "alignSelf", "justifyContent", "alignContent", "flexGrow", "flexShrink", "flexBasis",
			"gap", "rowGap", "columnGap", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "padding", "margin", "borderWidth",
			"borderColor", "borderStyle", "borderRadius", "shadows", "outline", "background", "backgroundColor", "opacity", "overflow", "position", "top", "right", "bottom", "left",
			"zIndex", "color", "fontSize", "fontWeight", "fontFamily", "fontStyle", "lineHeight", "letterSpacing", "textAlign", "textWrap", "visibility", "userSelect", "textTransform", "wordSpacing", "overflowWrap", "wordBreak", "hyphens",
			"fontFeatureSettings", "order", "textDecorationColor", "textDecorationThickness", "textUnderlineOffset", "fieldSizing", "outlineStyle",
			"scrollbarColor", "scrollbarTrackColor", "textShadow", "transform", "transformOrigin", "transition", "backgroundImage", "flex", "inset",
			"textOverflow", "lineClamp", "textDecoration", "cursor", "pointerEvents", "direction", "fontVariantNumeric", "aspectRatio", "scrollbarWidth", "justifyItems", "justifySelf", "gridTemplateColumns", "gridTemplateRows",
			"gridTemplateAreas", "gridAutoColumns", "gridAutoRows", "gridAutoFlow", "gridColumn", "gridRow", "gridArea"
		]) n => true
	];

	// (v as p's field name; false: no such style attribute)
	public static function set(p:Props, name:String, v:Dynamic):Bool {
		// (an enum's value: typed, else its name as CSS writes it)
		inline function word():String
			return Std.string(v).toLowerCase();
		switch name {
			case "visibility":
				p.visibility = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.Visibility) : word() == "hidden" ? Hidden : Visible;
			case "userSelect":
				p.userSelect = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.UserSelect) : switch word() {
					case "none": None;
					case "text": Text;
					case "all": All;
					case _: Auto;
				}
			case "textTransform":
				p.textTransform = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.TextTransform) : switch word() {
					case "uppercase": Uppercase;
					case "lowercase": Lowercase;
					case "capitalize": Capitalize;
					case _: None;
				}
			case "wordSpacing":
				p.wordSpacing = num(v);
			case "overflowWrap":
				p.overflowWrap = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.OverflowWrap) : switch word() {
					case "normal": Normal;
					case "anywhere": Anywhere;
					case _: BreakWord;
				}
			case "wordBreak":
				p.wordBreak = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.WordBreak) : switch word() {
					case "break-all" | "breakall": BreakAll;
					case "keep-all" | "keepall": KeepAll;
					case _: Normal;
				}
			case "hyphens":
				p.hyphens = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.Hyphens) : switch word() {
					case "none": None;
					case "auto": Auto;
					case _: Manual;
				}
			case "fontFeatureSettings":
				p.fontFeatureSettings = v == null ? null : Std.string(v);
			case "order":
				p.order = v == null ? null : Std.int(num(v) ?? 0);
			case "textDecorationColor":
				p.textDecorationColor = tint(v);
			case "textDecorationThickness":
				p.textDecorationThickness = num(v);
			case "textUnderlineOffset":
				p.textUnderlineOffset = num(v);
			case "fieldSizing":
				p.fieldSizing = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.FieldSizing) : word() == "content" ? Content : Fixed;
			case "outlineStyle":
				p.outlineStyle = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.OutlineStyle) : switch word() {
					case "none": None;
					case "solid": Solid;
					case "dashed": Dashed;
					case "dotted": Dotted;
					case _: Auto;
				}
			case "scrollbarColor":
				p.scrollbarColor = tint(v);
			case "scrollbarTrackColor":
				p.scrollbarTrackColor = tint(v);
			case "textShadow":
				p.textShadow = v;
			case "transform":
				p.transform = v == null ? null : Std.isOfType(v, String) ? helder.ui.Transform.parse(v) : v;
			case "transformOrigin":
				p.transformOrigin = v == null ? null : Std.isOfType(v, String) ? helder.ui.Transform.origin(v) : v;
			case "backgroundImage":
				p.backgroundImage = v == null ? null : Std.isOfType(v, String) ? helder.ui.Gradient.parse(v) : v;
			case "flex":
				// (CSS's shorthand: a number grows, "none" 0 0 auto, "auto" 1 1 auto, "2 0 40px")
				var w = v == null ? [] : [for (x in Std.string(v).split(" ")) if (x != "") x];
				if (w.length == 1 && (w[0] == "none" || w[0] == "auto")) {
					p.flexGrow = p.flexShrink = w[0] == "none" ? 0 : 1;
					p.flexBasis = "auto";
				} else {
					if (w.length > 0) p.flexGrow = num(w[0]);
					p.flexShrink = w.length > 1 ? num(w[1]) : 1;
					p.flexBasis = w.length > 2 ? size(w[2]) : w.length == 1 ? 0.0 : "auto";
				}
			case "inset":
				var e:Null<Array<Float>> = edges(v);
				if (e != null) {
					p.top = e[0];
					p.right = e[1];
					p.bottom = e[2];
					p.left = e[3];
				}
			case "transition":
				p.transition = v == null ? null : Std.isOfType(v, String) ? helder.ui.Transition.parse(v) : v;
			case "display":
				p.display = v == null ? null : switch Std.string(v) {
					case "none": None;
					case "block": Block;
					case "grid": Grid;
					case _: Flex;
				}
			case "flexDirection":
				p.flexDirection = v == null ? null : switch Std.string(v) {
					case "row": Row;
					case "row-reverse": RowReverse;
					case "column-reverse": ColumnReverse;
					case _: Column;
				}
			case "flexWrap":
				p.flexWrap = v == null ? null : v == true || v == "wrap" || v == "wrap-reverse";
			case "alignItems":
				p.alignItems = align(v);
			case "alignSelf":
				p.alignSelf = align(v);
			case "justifyContent":
				p.justifyContent = v == null ? null : switch Std.string(v) {
					case "flex-end" | "end": End;
					case "center": Center;
					case "space-between": SpaceBetween;
					case "space-around": SpaceAround;
					case "space-evenly": SpaceEvenly;
					case "normal": Normal;
					case _: Start;
				}
			case "alignContent":
				p.alignContent = v == null ? null : switch Std.string(v) {
					case "flex-start" | "start": Start;
					case "flex-end" | "end": End;
					case "center": Center;
					case "stretch": Stretch;
					case "space-between": SpaceBetween;
					case "space-around": SpaceAround;
					case "space-evenly": SpaceEvenly;
					case _: Normal;
				}
			case "flexGrow":
				p.flexGrow = num(v);
			case "flexShrink":
				p.flexShrink = num(v);
			case "flexBasis":
				p.flexBasis = size(v);
			case "gap":
				// (CSS's: one for both, else the rows', then the columns')
				var w = v == null || !Std.isOfType(v, String) ? null : [for (x in (v : String).split(" ")) if (x != "") x];
				if (w != null && w.length == 2) {
					p.rowGap = num(w[0]);
					p.columnGap = num(w[1]);
				} else p.gap = num(v);
			case "rowGap":
				p.rowGap = num(v);
			case "columnGap":
				p.columnGap = num(v);
			case "width":
				p.width = size(v);
			case "height":
				p.height = size(v);
			case "minWidth":
				p.minWidth = size(v);
			case "minHeight":
				p.minHeight = size(v);
			case "maxWidth":
				p.maxWidth = size(v);
			case "maxHeight":
				p.maxHeight = size(v);
			case "padding":
				p.padding = edges(v);
			case "margin":
				p.margin = edges(v);
			case "borderWidth":
				p.borderWidth = edges(v);
			case "borderColor":
				p.borderColor = tint(v);
			case "borderRadius":
				var e = edges(v);
				p.borderRadius = e == null ? null : (e : Array<Float>);
			case "borderStyle":
				p.borderStyle = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.BorderStyle) : switch Std.string(v) {
					case "dashed": Dashed;
					case "dotted": Dotted;
					case _: Solid;
				}
			case "shadows":
				p.shadows = v;
			case "outline":
				p.outline = v;
			case "background" | "backgroundColor":
				p.background = tint(v);
			case "opacity":
				p.opacity = num(v);
			case "overflow":
				p.overflow = v == null ? null : switch Std.string(v) {
					case "hidden" | "clip": Hidden;
					case "scroll" | "auto": Scroll;
					case _: Visible;
				}
			case "position":
				p.position = v == null ? null : switch Std.string(v) {
					case "absolute": Absolute;
					case "sticky": Sticky;
					case _: Relative;
				}
			case "top":
				p.top = size(v);
			case "right":
				p.right = size(v);
			case "bottom":
				p.bottom = size(v);
			case "left":
				p.left = size(v);
			case "zIndex":
				p.zIndex = v == null ? null : Std.int(num(v));
			case "color":
				p.color = tint(v);
			case "fontSize":
				p.fontSize = num(v);
			case "fontWeight":
				p.fontWeight = v == null ? null : v == "bold" ? 700 : v == "normal" ? 400 : Std.int(num(v));
			case "fontFamily":
				p.fontFamily = v;
			case "fontStyle":
				p.fontStyle = v == null ? null : v == "italic" || v == helder.ui.FontStyle.Italic ? helder.ui.FontStyle.Italic : helder.ui.FontStyle.Normal;
			case "lineHeight":
				p.lineHeight = num(v);
			case "letterSpacing":
				p.letterSpacing = num(v);
			case "textAlign":
				p.textAlign = v;
			case "textWrap":
				p.textWrap = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.TextWrap) : switch Std.string(v) {
					case "nowrap": NoWrap;
					case "balance": Balance;
					case _: Wrap;
				}
			case "textOverflow":
				p.textOverflow = v == null ? null : v == "ellipsis" || v == helder.ui.TextOverflow.Ellipsis ? helder.ui.TextOverflow.Ellipsis : helder.ui.TextOverflow.Clip;
			case "lineClamp":
				p.lineClamp = v == null ? null : Std.int(num(v));
			case "textDecoration":
				p.textDecoration = v == null ? null : Std.isOfType(v, Int) ? v : decoration(Std.string(v));
			case "cursor":
				p.cursor = v;
			case "pointerEvents":
				p.pointerEvents = v == null ? null : Std.string(v) == "none" ? None : Auto;
			case "direction":
				p.direction = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.Dir) : Std.string(v) == "rtl" ? Rtl : Ltr;
			case "fontVariantNumeric":
				p.fontVariantNumeric = v == null ? null : Std.string(v);
			case "aspectRatio":
				p.aspectRatio = ratio(v);
			case "scrollbarWidth":
				p.scrollbarWidth = v == null ? null : Std.isOfType(v, Int) ? (v : helder.ui.ScrollbarWidth) : switch Std.string(v) {
					case "thin": Thin;
					case "none": None;
					case _: Auto;
				}
			case "justifyItems":
				p.justifyItems = align(v);
			case "justifySelf":
				p.justifySelf = align(v);
			case "gridTemplateColumns" | "gridTemplateRows" | "gridTemplateAreas" | "gridAutoColumns" | "gridAutoRows" | "gridAutoFlow" | "gridColumn"
				| "gridRow" | "gridArea":
				var t:Null<String> = v == null ? null : Std.string(v);
				switch name {
					case "gridTemplateColumns": p.gridTemplateColumns = t;
					case "gridTemplateRows": p.gridTemplateRows = t;
					case "gridTemplateAreas": p.gridTemplateAreas = t;
					case "gridAutoColumns": p.gridAutoColumns = t;
					case "gridAutoRows": p.gridAutoRows = t;
					case "gridAutoFlow": p.gridAutoFlow = t;
					case "gridColumn": p.gridColumn = t;
					case "gridRow": p.gridRow = t;
					case _: p.gridArea = t;
				}
			case _:
				return false;
		}
		return true;
	}

	static function align(v:Dynamic):Null<Align>
		return v == null ? null : switch Std.string(v) {
			case "flex-start" | "start": Start;
			case "flex-end" | "end": End;
			case "center": Center;
			case "baseline": Baseline;
			case "auto": Auto;
			case _: Stretch;
		}

	// (CSS's text-decoration-line words: underline, line-through, overline, none)
	static function decoration(s:String):Int {
		var bits = 0;
		for (w in s.split(" ")) switch w {
			case "underline": bits |= (helder.ui.TextDecoration.Underline : Int);
			case "line-through": bits |= (helder.ui.TextDecoration.LineThrough : Int);
			case "overline": bits |= (helder.ui.TextDecoration.Overline : Int);
			case _:
		}
		return bits;
	}

	// (a number, or CSS's "16 / 9")
	static function ratio(v:Dynamic):Null<Float> {
		if (v == null || Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
		var parts = Std.string(v).split("/");
		var a = num(parts[0]), b = parts.length > 1 ? num(parts[1]) : 1.0;
		return a == null || b == null || b == 0 ? null : a / b;
	}

	static function num(v:Dynamic):Null<Float> {
		if (v == null) return null;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
		var s = Std.string(v).trim();
		if (s.endsWith("px")) s = s.substr(0, s.length - 2);
		var f = Std.parseFloat(s);
		return Math.isNaN(f) ? null : f;
	}

	static function size(v:Dynamic):Null<Measure> {
		if (v == null) return null;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float);
		if (Std.isOfType(v, String)) return (v : String);
		return (v : Len);
	}

	static function edges(v:Dynamic):Null<Edges> {
		if (v == null) return null;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float);
		if (Std.isOfType(v, Array)) return (v : Array<Float>);
		// (auto: NaN, a margin's)
		return [for (w in Std.string(v).trim().split(" ")) if (w != "") w == "auto" ? Math.NaN : num(w) ?? 0.0];
	}

	static function tint(v:Dynamic):Null<Tint> {
		if (v == null) return null;
		if (Std.isOfType(v, Int)) return (v : Int);
		if (Std.isOfType(v, String)) {
			var s:String = v;
			if (s == "currentColor" || s == "currentcolor") return Tint.current;
			if (s.startsWith("var(--")) return (Token(s.substring(6, s.indexOf(")"))) : TintValue);
			if (s == "transparent") return 0;
			return (Color.parse(s) : Int);
		}
		return (v : TintValue);
	}
}
