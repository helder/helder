package helder.ui.fast;

import helder.gfx.Color;
import helder.ui.Align;
import helder.ui.AlignContent;
import helder.ui.Direction;
import helder.ui.Display;
import helder.ui.FontStyle;
import helder.ui.Justify;
import helder.ui.Overflow;
import helder.ui.Position;
import helder.ui.TextAlign;
import helder.ui.box.Len;

// What a style says, each optional: unset, the initial value (an
// inherited one's: the parent's). The inherited ones are the text's:
// color, fontSize, fontWeight, fontFamily, fontStyle, lineHeight,
// letterSpacing, textAlign, wrap.
typedef StyleProps = {
	// (Grid: laid out as flex, grid layout not linked yet)
	?display:Display,
	?flexDirection:Direction,
	?flexWrap:Bool,
	?alignItems:Align,
	?alignSelf:Align,
	?justifyContent:Justify,
	?alignContent:AlignContent,
	?flexGrow:Float,
	?flexShrink:Float,
	?flexBasis:Size,
	?gap:Float,
	?rowGap:Float,
	?columnGap:Float,
	?width:Size,
	?height:Size,
	?minWidth:Size,
	?minHeight:Size,
	?maxWidth:Size,
	?maxHeight:Size,
	?padding:Edges,
	?margin:Edges,
	?borderWidth:Edges,
	?borderColor:Tint,
	?borderRadius:Float,
	?background:Tint,
	?opacity:Float,
	?overflow:Overflow,
	?position:Position,
	?top:Size,
	?right:Size,
	?bottom:Size,
	?left:Size,
	?zIndex:Int,
	?color:Tint,
	?fontSize:Float,
	?fontWeight:Int,
	?fontFamily:String,
	?fontStyle:FontStyle,
	// a multiple of the font size
	?lineHeight:Float,
	?letterSpacing:Float,
	?textAlign:TextAlign,
	// false: nowrap
	?wrap:Bool,
	// what a line cut at its end shows (Ellipsis: its box clips)
	?textOverflow:helder.ui.TextOverflow,
	// at most so many lines (0: no limit)
	?lineClamp:Int,
	// lines drawn through its text (TextDecoration's bits; 0: none)
	?textDecoration:Int,
	// the pointer over it (inherited)
	?cursor:helder.ui.Cursor,
	// its state variants, over it where the state is on (a later one's over an earlier's)
	?hover:StyleProps,
	?pressed:StyleProps,
	?focus:StyleProps,
	?disabled:StyleProps,
	?selected:StyleProps,
	?checked:StyleProps,
	// a field's while it shows its placeholder
	?placeholder:StyleProps,
	// the nearest ancestor marked group's states
	?group:StateProps
}

typedef StateProps = {
	?hover:StyleProps,
	?pressed:StyleProps,
	?focus:StyleProps,
	?disabled:StyleProps,
	?selected:StyleProps,
	?checked:StyleProps
}

// A colour: one, a theme's token (Theme.token: its light and dark), or
// the text's (current).
enum TintValue {
	Plain(argb:Int);
	Token(name:String);
	Current;
}

abstract Tint(TintValue) from TintValue to TintValue {
	@:from static inline function ofColor(c:Color):Tint
		return Plain(c);

	@:from static inline function ofInt(c:Int):Tint
		return Plain(c);

	public static var current(get, never):Tint;

	static inline function get_current():Tint
		return Current;
}

// A length: px, or a percentage ("50%"); null: auto.
abstract Size(Len) from Len to Len {
	@:from static inline function ofFloat(v:Float):Size
		return Px(v);

	@:from static inline function ofInt(v:Int):Size
		return Px(v);

	@:from static function ofString(s:String):Size {
		var t = StringTools.trim(s);
		if (t == "auto") return Auto;
		if (StringTools.endsWith(t, "%")) return Percent(Std.parseFloat(t.substr(0, t.length - 1)));
		var v = Std.parseFloat(StringTools.endsWith(t, "px") ? t.substr(0, t.length - 2) : t);
		return Math.isNaN(v) ? Auto : Px(v);
	}
}

// Four sides' px (top, right, bottom, left): one for all, [vertical,
// horizontal], or all four.
abstract Edges(Array<Float>) to Array<Float> {
	inline function new(a:Array<Float>)
		this = a;

	@:from static inline function ofFloat(v:Float):Edges
		return new Edges([v, v, v, v]);

	@:from static inline function ofInt(v:Int):Edges
		return new Edges([v, v, v, v]);

	@:from static function ofArray(a:Array<Float>):Edges
		return new Edges(switch a.length {
			case 1: [a[0], a[0], a[0], a[0]];
			case 2: [a[0], a[1], a[0], a[1]];
			case 3: [a[0], a[1], a[2], a[1]];
			case _: [a[0], a[1], a[2], a[3]];
		});
}

// A node's style: an immutable value, interned (equal styles are one
// object, a style on a thousand rows resolved once for each state, parent
// text and theme it meets), with its state variants. with() makes another
// over it.
//
//   final row = Style.of({flexDirection: Row, padding: [4, 6], hover: {background: 0xFFF4F4F5}});
//   final picked = row.with({background: Theme.token("accent")});
final class Style {
	// what it says, its variants in it
	public final props:StyleProps;
	// (its interning key: what it says, written out)
	final key:String;

	// (each by its key; before none, made of it)
	static final interned = new Map<String, Style>();

	// the style that says nothing
	public static final none = of({});

	function new(props:StyleProps, key:String) {
		this.props = props;
		this.key = key;
	}

	// The style of props: the one made of the same before, else a new one.
	public static function of(props:StyleProps):Style {
		var k = write(props);
		var s = interned.get(k);
		if (s == null) interned.set(k, s = new Style(full(props), k));
		return s;
	}

	// This style with p over it (a variant's too: merged).
	public function with(p:StyleProps):Style
		return of(merge(props, p));

	// a state's bit (Node.state's): hover, pressed, focus, disabled, selected, checked; a group's, it shifted by GROUP
	public static inline var HOVER = 1;
	public static inline var PRESSED = 2;
	public static inline var FOCUS = 4;
	public static inline var DISABLED = 8;
	public static inline var SELECTED = 16;
	public static inline var CHECKED = 32;
	public static inline var PLACEHOLDER = 64;
	public static inline var GROUP = 8;

	// (what it says in states: its own (mask's low bits) and its group's (shifted by GROUP), the variants over it in order)
	public function at(mask:Int):StyleProps {
		var p = props;
		if (mask == 0) return p;
		var out = p;
		inline function over(bit:Int, v:Null<StyleProps>)
			if (mask & bit != 0 && v != null) out = merge(out, v);
		var g = p.group;
		if (g != null) {
			over(HOVER << GROUP, g.hover);
			over(PRESSED << GROUP, g.pressed);
			over(FOCUS << GROUP, g.focus);
			over(DISABLED << GROUP, g.disabled);
			over(SELECTED << GROUP, g.selected);
			over(CHECKED << GROUP, g.checked);
		}
		over(HOVER, p.hover);
		over(PRESSED, p.pressed);
		over(FOCUS, p.focus);
		over(DISABLED, p.disabled);
		over(SELECTED, p.selected);
		over(CHECKED, p.checked);
		over(PLACEHOLDER, p.placeholder);
		return out;
	}

	// (the states it has a variant for: what a change of the others leaves it as it is)
	public var states(get, never):Int;

	function get_states():Int {
		var p = props, m = 0;
		if (p.hover != null) m |= HOVER;
		if (p.pressed != null) m |= PRESSED;
		if (p.focus != null) m |= FOCUS;
		if (p.disabled != null) m |= DISABLED;
		if (p.selected != null) m |= SELECTED;
		if (p.checked != null) m |= CHECKED;
		if (p.placeholder != null) m |= PLACEHOLDER;
		var g = p.group;
		if (g != null) {
			if (g.hover != null) m |= HOVER << GROUP;
			if (g.pressed != null) m |= PRESSED << GROUP;
			if (g.focus != null) m |= FOCUS << GROUP;
			if (g.disabled != null) m |= DISABLED << GROUP;
			if (g.selected != null) m |= SELECTED << GROUP;
			if (g.checked != null) m |= CHECKED << GROUP;
		}
		return m;
	}

	// (b over a, field by field; variants merged too)
	public static function merge(a:StyleProps, b:StyleProps):StyleProps
		return {
			display: b.display ?? a.display,
			flexDirection: b.flexDirection ?? a.flexDirection,
			flexWrap: b.flexWrap ?? a.flexWrap,
			alignItems: b.alignItems ?? a.alignItems,
			alignSelf: b.alignSelf ?? a.alignSelf,
			justifyContent: b.justifyContent ?? a.justifyContent,
			alignContent: b.alignContent ?? a.alignContent,
			flexGrow: b.flexGrow ?? a.flexGrow,
			flexShrink: b.flexShrink ?? a.flexShrink,
			flexBasis: b.flexBasis ?? a.flexBasis,
			gap: b.gap ?? a.gap,
			rowGap: b.rowGap ?? (b.gap != null ? b.gap : a.rowGap),
			columnGap: b.columnGap ?? (b.gap != null ? b.gap : a.columnGap),
			width: b.width ?? a.width,
			height: b.height ?? a.height,
			minWidth: b.minWidth ?? a.minWidth,
			minHeight: b.minHeight ?? a.minHeight,
			maxWidth: b.maxWidth ?? a.maxWidth,
			maxHeight: b.maxHeight ?? a.maxHeight,
			padding: b.padding ?? a.padding,
			margin: b.margin ?? a.margin,
			borderWidth: b.borderWidth ?? a.borderWidth,
			borderColor: b.borderColor ?? a.borderColor,
			borderRadius: b.borderRadius ?? a.borderRadius,
			background: b.background ?? a.background,
			opacity: b.opacity ?? a.opacity,
			overflow: b.overflow ?? a.overflow,
			position: b.position ?? a.position,
			top: b.top ?? a.top,
			right: b.right ?? a.right,
			bottom: b.bottom ?? a.bottom,
			left: b.left ?? a.left,
			zIndex: b.zIndex ?? a.zIndex,
			color: b.color ?? a.color,
			fontSize: b.fontSize ?? a.fontSize,
			fontWeight: b.fontWeight ?? a.fontWeight,
			fontFamily: b.fontFamily ?? a.fontFamily,
			fontStyle: b.fontStyle ?? a.fontStyle,
			lineHeight: b.lineHeight ?? a.lineHeight,
			letterSpacing: b.letterSpacing ?? a.letterSpacing,
			textAlign: b.textAlign ?? a.textAlign,
			wrap: b.wrap ?? a.wrap,
			textOverflow: b.textOverflow ?? a.textOverflow,
			lineClamp: b.lineClamp ?? a.lineClamp,
			textDecoration: b.textDecoration ?? a.textDecoration,
			cursor: b.cursor ?? a.cursor,
			hover: both(a.hover, b.hover),
			pressed: both(a.pressed, b.pressed),
			focus: both(a.focus, b.focus),
			disabled: both(a.disabled, b.disabled),
			selected: both(a.selected, b.selected),
			checked: both(a.checked, b.checked),
			placeholder: both(a.placeholder, b.placeholder),
			group: a.group == null ? b.group : b.group == null ? a.group : {
				hover: both(a.group.hover, b.group.hover),
				pressed: both(a.group.pressed, b.group.pressed),
				focus: both(a.group.focus, b.group.focus),
				disabled: both(a.group.disabled, b.group.disabled),
				selected: both(a.group.selected, b.group.selected),
				checked: both(a.group.checked, b.group.checked)
			}
		};

	// (every field there, null: what the fields read fast in, an object of a literal's layout)
	public static function blank():StyleProps
		return {
			display: null,
			flexDirection: null,
			flexWrap: null,
			alignItems: null,
			alignSelf: null,
			justifyContent: null,
			alignContent: null,
			flexGrow: null,
			flexShrink: null,
			flexBasis: null,
			gap: null,
			rowGap: null,
			columnGap: null,
			width: null,
			height: null,
			minWidth: null,
			minHeight: null,
			maxWidth: null,
			maxHeight: null,
			padding: null,
			margin: null,
			borderWidth: null,
			borderColor: null,
			borderRadius: null,
			background: null,
			opacity: null,
			overflow: null,
			position: null,
			top: null,
			right: null,
			bottom: null,
			left: null,
			zIndex: null,
			color: null,
			fontSize: null,
			fontWeight: null,
			fontFamily: null,
			fontStyle: null,
			lineHeight: null,
			letterSpacing: null,
			textAlign: null,
			wrap: null,
			textOverflow: null,
			lineClamp: null,
			textDecoration: null,
			cursor: null,
			hover: null,
			pressed: null,
			focus: null,
			disabled: null,
			selected: null,
			checked: null,
			placeholder: null,
			group: null
		};

	// (p with every field there, its variants' too: read fast from then on)
	static function full(p:StyleProps):StyleProps {
		var f = merge(blank(), p);
		f.hover = whole(f.hover);
		f.pressed = whole(f.pressed);
		f.focus = whole(f.focus);
		f.disabled = whole(f.disabled);
		f.selected = whole(f.selected);
		f.checked = whole(f.checked);
		f.placeholder = whole(f.placeholder);
		var g = f.group;
		if (g != null) f.group = {
			hover: whole(g.hover),
			pressed: whole(g.pressed),
			focus: whole(g.focus),
			disabled: whole(g.disabled),
			selected: whole(g.selected),
			checked: whole(g.checked)
		};
		return f;
	}

	static inline function whole(p:Null<StyleProps>):Null<StyleProps>
		return p == null ? null : merge(blank(), p);

	static function both(a:Null<StyleProps>, b:Null<StyleProps>):Null<StyleProps>
		return a == null ? b : b == null ? a : merge(a, b);

	// (what it says written out: its key. Floats as their bits or integers:
	// hxmc's Float to String throws in a static initializer, where styles are
	// made)
	@:allow(helder.ui.fast) static function write(p:Null<StyleProps>):String {
		if (p == null) return "";
		var out = new StringBuf();
		if (p.display != null) word(out, "d", p.display);
		if (p.flexDirection != null) word(out, "fd", p.flexDirection);
		if (p.flexWrap != null) word(out, "fw", p.flexWrap);
		if (p.alignItems != null) word(out, "ai", p.alignItems);
		if (p.alignSelf != null) word(out, "as", p.alignSelf);
		if (p.justifyContent != null) word(out, "jc", p.justifyContent);
		if (p.alignContent != null) word(out, "ac", p.alignContent);
		if (p.flexGrow != null) num(out, "fg", p.flexGrow);
		if (p.flexShrink != null) num(out, "fs", p.flexShrink);
		if (p.flexBasis != null) size(out, "fb", p.flexBasis);
		if (p.gap != null) num(out, "g", p.gap);
		if (p.rowGap != null) num(out, "rg", p.rowGap);
		if (p.columnGap != null) num(out, "cg", p.columnGap);
		if (p.width != null) size(out, "w", p.width);
		if (p.height != null) size(out, "h", p.height);
		if (p.minWidth != null) size(out, "mw", p.minWidth);
		if (p.minHeight != null) size(out, "mh", p.minHeight);
		if (p.maxWidth != null) size(out, "xw", p.maxWidth);
		if (p.maxHeight != null) size(out, "xh", p.maxHeight);
		if (p.padding != null) edges(out, "p", p.padding);
		if (p.margin != null) edges(out, "m", p.margin);
		if (p.borderWidth != null) edges(out, "bw", p.borderWidth);
		if (p.borderColor != null) tint(out, "bc", p.borderColor);
		if (p.borderRadius != null) num(out, "br", p.borderRadius);
		if (p.background != null) tint(out, "bg", p.background);
		if (p.opacity != null) num(out, "o", p.opacity);
		if (p.overflow != null) word(out, "ov", p.overflow);
		if (p.position != null) word(out, "pos", p.position);
		if (p.top != null) size(out, "t", p.top);
		if (p.right != null) size(out, "r", p.right);
		if (p.bottom != null) size(out, "b", p.bottom);
		if (p.left != null) size(out, "l", p.left);
		if (p.zIndex != null) word(out, "z", p.zIndex);
		if (p.color != null) tint(out, "c", p.color);
		if (p.fontSize != null) num(out, "fz", p.fontSize);
		if (p.fontWeight != null) word(out, "fwt", p.fontWeight);
		if (p.fontFamily != null) word(out, "ff", p.fontFamily);
		if (p.fontStyle != null) word(out, "fst", p.fontStyle);
		if (p.lineHeight != null) num(out, "lh", p.lineHeight);
		if (p.letterSpacing != null) num(out, "ls", p.letterSpacing);
		if (p.textAlign != null) word(out, "ta", p.textAlign);
		if (p.wrap != null) word(out, "wr", p.wrap);
		if (p.textOverflow != null) word(out, "to", p.textOverflow);
		if (p.lineClamp != null) word(out, "lc", p.lineClamp);
		if (p.textDecoration != null) word(out, "td", p.textDecoration);
		if (p.cursor != null) word(out, "cu", p.cursor);
		inline function sub(name:String, v:Null<StyleProps>)
			if (v != null) {
				out.add(name);
				out.add("{");
				out.add(write(v));
				out.add("}");
			}
		sub("hover", p.hover);
		sub("pressed", p.pressed);
		sub("focus", p.focus);
		sub("disabled", p.disabled);
		sub("selected", p.selected);
		sub("checked", p.checked);
		sub("placeholder", p.placeholder);
		var g = p.group;
		if (g != null) {
			out.add("group{");
			sub("hover", g.hover);
			sub("pressed", g.pressed);
			sub("focus", g.focus);
			sub("disabled", g.disabled);
			sub("selected", g.selected);
			sub("checked", g.checked);
			out.add("}");
		}
		return out.toString();
	}

	static function word(out:StringBuf, k:String, v:Any) {
		out.add(k);
		out.add("=");
		out.add(v);
		out.add(";");
	}

	static function float(out:StringBuf, v:Float) {
		var i = Std.int(v);
		if (i == v) out.add(i) else {
			var b = haxe.io.FPHelper.doubleToI64(v);
			out.add("~");
			out.add(b.high);
			out.add(":");
			out.add(b.low);
		}
	}

	static function num(out:StringBuf, k:String, v:Float) {
		out.add(k);
		out.add("=");
		float(out, v);
		out.add(";");
	}

	static function size(out:StringBuf, k:String, v:Len) {
		out.add(k);
		switch v {
			case Px(n):
				out.add("=");
				float(out, n);
			case Percent(n):
				out.add("%");
				float(out, n);
			case _:
				out.add("=a");
		}
		out.add(";");
	}

	static function edges(out:StringBuf, k:String, v:Array<Float>) {
		out.add(k);
		out.add("=");
		for (e in v) {
			float(out, e);
			out.add(",");
		}
		out.add(";");
	}

	static function tint(out:StringBuf, k:String, v:TintValue) {
		out.add(k);
		switch v {
			case Plain(c):
				out.add("=");
				out.add(c);
			case Token(name):
				out.add("$");
				out.add(name);
			case Current:
				out.add("=current");
		}
		out.add(";");
	}
}
