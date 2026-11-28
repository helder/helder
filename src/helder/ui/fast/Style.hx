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
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// What a style says, each optional: unset, the initial value (an
// inherited one's: the parent's). The inherited ones are the text's:
// color, fontSize, fontWeight, fontFamily, fontStyle, lineHeight,
// letterSpacing, textAlign, wrap. A literal given to Style.of or with()
// is checked and made typed when the program is built (Props); another
// is read when it runs.
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
	// in a dark theme (Theme.dark: a CSS module's prefers-color-scheme: dark)
	?dark:StyleProps,
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

// (what a style says as a class's fields: read fast and small where an
// anonymous object's are neither; a literal made one when the program is
// built, Style.of's)
@:allow(helder.ui.fast)
final class Props {
	public var display:Null<Display> = null;
	public var flexDirection:Null<Direction> = null;
	public var flexWrap:Null<Bool> = null;
	public var alignItems:Null<Align> = null;
	public var alignSelf:Null<Align> = null;
	public var justifyContent:Null<Justify> = null;
	public var alignContent:Null<AlignContent> = null;
	public var flexGrow:Null<Float> = null;
	public var flexShrink:Null<Float> = null;
	public var flexBasis:Null<Size> = null;
	public var gap:Null<Float> = null;
	public var rowGap:Null<Float> = null;
	public var columnGap:Null<Float> = null;
	public var width:Null<Size> = null;
	public var height:Null<Size> = null;
	public var minWidth:Null<Size> = null;
	public var minHeight:Null<Size> = null;
	public var maxWidth:Null<Size> = null;
	public var maxHeight:Null<Size> = null;
	public var padding:Null<Edges> = null;
	public var margin:Null<Edges> = null;
	public var borderWidth:Null<Edges> = null;
	public var borderColor:Null<Tint> = null;
	public var borderRadius:Null<Float> = null;
	public var background:Null<Tint> = null;
	public var opacity:Null<Float> = null;
	public var overflow:Null<Overflow> = null;
	public var position:Null<Position> = null;
	public var top:Null<Size> = null;
	public var right:Null<Size> = null;
	public var bottom:Null<Size> = null;
	public var left:Null<Size> = null;
	public var zIndex:Null<Int> = null;
	public var color:Null<Tint> = null;
	public var fontSize:Null<Float> = null;
	public var fontWeight:Null<Int> = null;
	public var fontFamily:Null<String> = null;
	public var fontStyle:Null<FontStyle> = null;
	public var lineHeight:Null<Float> = null;
	public var letterSpacing:Null<Float> = null;
	public var textAlign:Null<TextAlign> = null;
	public var wrap:Null<Bool> = null;
	public var textOverflow:Null<helder.ui.TextOverflow> = null;
	public var lineClamp:Null<Int> = null;
	public var textDecoration:Null<Int> = null;
	public var cursor:Null<helder.ui.Cursor> = null;
	public var hover:Null<Props> = null;
	public var pressed:Null<Props> = null;
	public var focus:Null<Props> = null;
	public var disabled:Null<Props> = null;
	public var selected:Null<Props> = null;
	public var checked:Null<Props> = null;
	public var placeholder:Null<Props> = null;
	public var dark:Null<Props> = null;
	public var group:Null<GroupProps> = null;

	public function new() {}

	// (an object's, read when the program runs: a style not given as a literal)
	public static function from(p:Null<StyleProps>):Null<Props> {
		if (p == null) return null;
		var o = new Props();
		o.display = p.display;
		o.flexDirection = p.flexDirection;
		o.flexWrap = p.flexWrap;
		o.alignItems = p.alignItems;
		o.alignSelf = p.alignSelf;
		o.justifyContent = p.justifyContent;
		o.alignContent = p.alignContent;
		o.flexGrow = p.flexGrow;
		o.flexShrink = p.flexShrink;
		o.flexBasis = p.flexBasis;
		o.gap = p.gap;
		o.rowGap = p.rowGap;
		o.columnGap = p.columnGap;
		o.width = p.width;
		o.height = p.height;
		o.minWidth = p.minWidth;
		o.minHeight = p.minHeight;
		o.maxWidth = p.maxWidth;
		o.maxHeight = p.maxHeight;
		o.padding = p.padding;
		o.margin = p.margin;
		o.borderWidth = p.borderWidth;
		o.borderColor = p.borderColor;
		o.borderRadius = p.borderRadius;
		o.background = p.background;
		o.opacity = p.opacity;
		o.overflow = p.overflow;
		o.position = p.position;
		o.top = p.top;
		o.right = p.right;
		o.bottom = p.bottom;
		o.left = p.left;
		o.zIndex = p.zIndex;
		o.color = p.color;
		o.fontSize = p.fontSize;
		o.fontWeight = p.fontWeight;
		o.fontFamily = p.fontFamily;
		o.fontStyle = p.fontStyle;
		o.lineHeight = p.lineHeight;
		o.letterSpacing = p.letterSpacing;
		o.textAlign = p.textAlign;
		o.wrap = p.wrap;
		o.textOverflow = p.textOverflow;
		o.lineClamp = p.lineClamp;
		o.textDecoration = p.textDecoration;
		o.cursor = p.cursor;
		o.hover = from(p.hover);
		o.pressed = from(p.pressed);
		o.focus = from(p.focus);
		o.disabled = from(p.disabled);
		o.selected = from(p.selected);
		o.checked = from(p.checked);
		o.placeholder = from(p.placeholder);
		o.dark = from(p.dark);
		var g = p.group;
		if (g != null) {
			var q = new GroupProps();
			q.hover = from(g.hover);
			q.pressed = from(g.pressed);
			q.focus = from(g.focus);
			q.disabled = from(g.disabled);
			q.selected = from(g.selected);
			q.checked = from(g.checked);
			o.group = q;
		}
		return o;
	}
}

@:allow(helder.ui.fast)
final class GroupProps {
	public var hover:Null<Props> = null;
	public var pressed:Null<Props> = null;
	public var focus:Null<Props> = null;
	public var disabled:Null<Props> = null;
	public var selected:Null<Props> = null;
	public var checked:Null<Props> = null;

	public function new() {}
}

// A node's style: an immutable value, interned (equal styles are one
// object, a style on a thousand rows resolved once for each state, parent
// text and theme it meets), with its state variants. with() makes another
// over it. A literal given to Style.of or with() is checked when the
// program is built (a misspelt name, a value of another type: an error
// there) and made as typed fields, no object read field by name at run
// time.
//
//   final row = Style.of({flexDirection: Row, padding: [4, 6], hover: {background: 0xFFF4F4F5}});
//   final picked = row.with({background: Theme.token("accent")});
final class Style {
	// what it says, its variants in it
	public final props:Props;
	// (its interning key: what it says, written out)
	final key:String;

	// (each by its key; before none, made of it)
	static final interned = new Map<String, Style>();

	// the style that says nothing
	public static final none = intern(new Props());

	function new(props:Props, key:String) {
		this.props = props;
		this.key = key;
	}

	// The style of props: the one made of the same before, else a new one.
	public static macro function of(props:haxe.macro.Expr):haxe.macro.Expr.ExprOf<Style>
		return switch props.expr {
			case EObjectDecl(_): macro helder.ui.fast.Style.intern(${typed(props)});
			case _: macro helder.ui.fast.Style.ofProps($props);
		}

	// (a style of props an object read when the program runs)
	public static function ofProps(props:StyleProps):Style
		return intern(Props.from(props));

	// (props made typed: the one of the same before, else a style of them)
	@:noCompletion public static function intern(p:Props):Style {
		var k = write(p);
		var s = interned.get(k);
		if (s == null) interned.set(k, s = new Style(p, k));
		return s;
	}

	// This style with p over it (a variant's too: merged); p a literal, an object, or a Style.
	public macro function with(self:haxe.macro.Expr, p:haxe.macro.Expr):haxe.macro.Expr.ExprOf<Style>
		return switch p.expr {
			case EObjectDecl(_): macro $self.over(${typed(p)});
			case _ if (isStyle(p)): macro $self.over(($p : helder.ui.fast.Style).props);
			case _: macro $self.over(helder.ui.fast.Style.Props.from($p));
		}

	// This style with typed props over it.
	@:noCompletion public function over(p:Props):Style
		return intern(merge(props, p));

	#if macro
	// (a literal as typed fields: each name one of Props', its value typed as that field is, where it is written)
	static function typed(e:Expr):Expr {
		var fields = switch e.expr {
			case EObjectDecl(f): f;
			case _: return macro helder.ui.fast.Style.Props.from($e);
		}
		var sets = [macro var p = new helder.ui.fast.Style.Props()];
		for (f in fields) {
			var n = f.field, v = f.expr;
			if (VARIANTS.indexOf(n) >= 0) sets.push(macro @:pos(v.pos) p.$n = ${typed(v)}) else if (n == "group") sets.push(macro @:pos(v.pos) p.group = ${group(v)}) else if (FIELDS.indexOf(n) >= 0)
				sets.push(macro @:pos(v.pos) p.$n = $v) else Context.error('helder.ui.fast: a style has no field $n' + near(n), v.pos);
		}
		sets.push(macro p);
		return macro @:pos(e.pos) $b{sets};
	}

	static function group(e:Expr):Expr {
		var fields = switch e.expr {
			case EObjectDecl(f): f;
			case _: Context.error("helder.ui.fast: a style's group is a literal of its states' styles", e.pos);
		}
		var sets = [macro var g = new helder.ui.fast.Style.GroupProps()];
		for (f in fields) {
			var n = f.field;
			if (GROUP_STATES.indexOf(n) < 0) Context.error('helder.ui.fast: a group has no state $n (${GROUP_STATES.join(", ")})', f.expr.pos);
			sets.push(macro g.$n = ${typed(f.expr)});
		}
		sets.push(macro g);
		return macro $b{sets};
	}

	static function isStyle(e:Expr):Bool
		return try switch Context.follow(Context.typeof(e)) {
			case TInst(_.get() => c, _): c.name == "Style" && c.pack.join(".") == "helder.ui.fast";
			case _: false;
		} catch (_:Dynamic) false;

	// (the field meant: one a letter or two away)
	static function near(n:String):String {
		for (f in FIELDS.concat(VARIANTS)) if (StringTools.startsWith(f.toLowerCase(), n.toLowerCase().substr(0, 3))) return '; did you mean $f?';
		return "";
	}
	static final FIELDS = ["display", "flexDirection", "flexWrap", "alignItems", "alignSelf", "justifyContent", "alignContent", "flexGrow", "flexShrink", "flexBasis", "gap", "rowGap", "columnGap", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "padding", "margin", "borderWidth", "borderColor", "borderRadius", "background", "opacity", "overflow", "position", "top", "right", "bottom", "left", "zIndex", "color", "fontSize", "fontWeight", "fontFamily", "fontStyle", "lineHeight", "letterSpacing", "textAlign", "wrap", "textOverflow", "lineClamp", "textDecoration", "cursor"];
	static final VARIANTS = ["hover", "pressed", "focus", "disabled", "selected", "checked", "placeholder", "dark"];
	static final GROUP_STATES = ["hover", "pressed", "focus", "disabled", "selected", "checked"];
	#end

	// a state's bit (Node.state's): hover, pressed, focus, disabled, selected, checked, placeholder; a group's, it shifted by GROUP
	public static inline var HOVER = 1;
	public static inline var PRESSED = 2;
	public static inline var FOCUS = 4;
	public static inline var DISABLED = 8;
	public static inline var SELECTED = 16;
	public static inline var CHECKED = 32;
	public static inline var PLACEHOLDER = 64;
	public static inline var GROUP = 8;

	// (what it says in states: its own (mask's low bits) and its group's (shifted by GROUP), the variants over it
	// in order; dark: the theme's tone)
	public function at(mask:Int, dark = false):Props {
		var p = props;
		if (mask == 0 && (!dark || p.dark == null)) return p;
		var out = p;
		inline function over(bit:Int, v:Null<Props>)
			if (mask & bit != 0 && v != null) out = merge(out, v);
		if (dark && p.dark != null) out = merge(out, p.dark);
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
	@:noCompletion public static function merge(a:Props, b:Props):Props {
		var o = new Props();
		o.display = b.display ?? a.display;
		o.flexDirection = b.flexDirection ?? a.flexDirection;
		o.flexWrap = b.flexWrap ?? a.flexWrap;
		o.alignItems = b.alignItems ?? a.alignItems;
		o.alignSelf = b.alignSelf ?? a.alignSelf;
		o.justifyContent = b.justifyContent ?? a.justifyContent;
		o.alignContent = b.alignContent ?? a.alignContent;
		o.flexGrow = b.flexGrow ?? a.flexGrow;
		o.flexShrink = b.flexShrink ?? a.flexShrink;
		o.flexBasis = b.flexBasis ?? a.flexBasis;
		o.gap = b.gap ?? a.gap;
		o.rowGap = b.rowGap ?? (b.gap != null ? b.gap : a.rowGap);
		o.columnGap = b.columnGap ?? (b.gap != null ? b.gap : a.columnGap);
		o.width = b.width ?? a.width;
		o.height = b.height ?? a.height;
		o.minWidth = b.minWidth ?? a.minWidth;
		o.minHeight = b.minHeight ?? a.minHeight;
		o.maxWidth = b.maxWidth ?? a.maxWidth;
		o.maxHeight = b.maxHeight ?? a.maxHeight;
		o.padding = b.padding ?? a.padding;
		o.margin = b.margin ?? a.margin;
		o.borderWidth = b.borderWidth ?? a.borderWidth;
		o.borderColor = b.borderColor ?? a.borderColor;
		o.borderRadius = b.borderRadius ?? a.borderRadius;
		o.background = b.background ?? a.background;
		o.opacity = b.opacity ?? a.opacity;
		o.overflow = b.overflow ?? a.overflow;
		o.position = b.position ?? a.position;
		o.top = b.top ?? a.top;
		o.right = b.right ?? a.right;
		o.bottom = b.bottom ?? a.bottom;
		o.left = b.left ?? a.left;
		o.zIndex = b.zIndex ?? a.zIndex;
		o.color = b.color ?? a.color;
		o.fontSize = b.fontSize ?? a.fontSize;
		o.fontWeight = b.fontWeight ?? a.fontWeight;
		o.fontFamily = b.fontFamily ?? a.fontFamily;
		o.fontStyle = b.fontStyle ?? a.fontStyle;
		o.lineHeight = b.lineHeight ?? a.lineHeight;
		o.letterSpacing = b.letterSpacing ?? a.letterSpacing;
		o.textAlign = b.textAlign ?? a.textAlign;
		o.wrap = b.wrap ?? a.wrap;
		o.textOverflow = b.textOverflow ?? a.textOverflow;
		o.lineClamp = b.lineClamp ?? a.lineClamp;
		o.textDecoration = b.textDecoration ?? a.textDecoration;
		o.cursor = b.cursor ?? a.cursor;
		o.hover = both(a.hover, b.hover);
		o.pressed = both(a.pressed, b.pressed);
		o.focus = both(a.focus, b.focus);
		o.disabled = both(a.disabled, b.disabled);
		o.selected = both(a.selected, b.selected);
		o.checked = both(a.checked, b.checked);
		o.placeholder = both(a.placeholder, b.placeholder);
		o.dark = both(a.dark, b.dark);
		o.group = a.group == null ? b.group : b.group == null ? a.group : {
			var g = new GroupProps();
			g.hover = both(a.group.hover, b.group.hover);
			g.pressed = both(a.group.pressed, b.group.pressed);
			g.focus = both(a.group.focus, b.group.focus);
			g.disabled = both(a.group.disabled, b.group.disabled);
			g.selected = both(a.group.selected, b.group.selected);
			g.checked = both(a.group.checked, b.group.checked);
			g;
		}
		return o;
	}

	static function both(a:Null<Props>, b:Null<Props>):Null<Props>
		return a == null ? b : b == null ? a : merge(a, b);

	// (what it says written out: its key. Floats as their bits or integers:
	// hxmc's Float to String throws in a static initializer, where styles are
	// made)
	@:allow(helder.ui.fast) static function write(p:Null<Props>):String {
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
		inline function sub(name:String, v:Null<Props>)
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
		sub("dark", p.dark);
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
