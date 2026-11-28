package helder.ui;

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
import helder.ui.Token.Length;
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
	?flexBasis:Measure,
	?gap:Pixels,
	?rowGap:Pixels,
	?columnGap:Pixels,
	?width:Measure,
	?height:Measure,
	?minWidth:Measure,
	?minHeight:Measure,
	?maxWidth:Measure,
	?maxHeight:Measure,
	?padding:Edges,
	?margin:Edges,
	?borderWidth:Edges,
	?borderColor:Tint,
	// (Solid where a width is set)
	?borderStyle:helder.ui.BorderStyle,
	?borderRadius:Radii,
	?background:Tint,
	// CSS's box-shadow: the first on top
	?shadows:Array<ShadowLayer>,
	?outline:Outline,
	?opacity:Float,
	?overflow:Overflow,
	?position:Position,
	?top:Measure,
	?right:Measure,
	?bottom:Measure,
	?left:Measure,
	?zIndex:Int,
	?color:Tint,
	?fontSize:Pixels,
	?fontWeight:Int,
	?fontFamily:String,
	?fontStyle:FontStyle,
	// a multiple of the font size
	?lineHeight:Float,
	?letterSpacing:Pixels,
	?textAlign:TextAlign,
	// false: nowrap
	?textWrap:helder.ui.TextWrap,
	// what a line cut at its end shows (Ellipsis: its box clips)
	?textOverflow:helder.ui.TextOverflow,
	// at most so many lines (0: no limit)
	?lineClamp:Int,
	// lines drawn through its text (TextDecoration's bits; 0: none)
	?textDecoration:Int,
	// the pointer over it (inherited)
	?cursor:helder.ui.Cursor,
	// whether the pointer finds it (inherited: None lets presses and hovers through, its Auto descendants aside)
	?pointerEvents:helder.ui.PointerEvents,
	// the inline direction (inherited): Rtl mirrors rows and aligns text right
	?direction:helder.ui.Dir,
	// figures' forms as CSS writes them ("tabular-nums"; inherited)
	?fontVariantNumeric:String,
	// width / height where one of them is auto
	?aspectRatio:Float,
	// a scroller's bar: Auto, Thin, None (none drawn or grabbed; the wheel still scrolls)
	?scrollbarWidth:helder.ui.ScrollbarWidth,
	// a grid's items in their areas, across (Stretch)
	?justifyItems:Align,
	?justifySelf:Align,
	// a grid's tracks as CSS writes them ("1fr 200px", "repeat(3, 1fr)", "[a] minmax(100px, 1fr)"); grid layout linked where a program says grid
	?gridTemplateColumns:String,
	?gridTemplateRows:String,
	// its areas: rows' names, CSS's strings ("'head head' 'side main'")
	?gridTemplateAreas:String,
	?gridAutoColumns:String,
	?gridAutoRows:String,
	?gridAutoFlow:String,
	// an item's lines as CSS writes them ("1 / 3", "span 2", an area's name)
	?gridColumn:String,
	?gridRow:String,
	?gridArea:String,
	// seen or not (inherited): Hidden keeps its place, drawing and hitting nothing
	?visibility:helder.ui.Visibility,
	// whether its text can be selected by the pointer (inherited)
	?userSelect:helder.ui.UserSelect,
	// its letters' case as shown (inherited)
	?textTransform:helder.ui.TextTransform,
	?wordSpacing:Pixels,
	// where a word too long breaks (inherited)
	?overflowWrap:helder.ui.OverflowWrap,
	?wordBreak:helder.ui.WordBreak,
	?hyphens:helder.ui.Hyphens,
	// its OpenType features as CSS writes them (inherited)
	?fontFeatureSettings:String,
	// its place among its siblings in layout and paint
	?order:Int,
	// the lines' colour (null: the text's)
	?textDecorationColor:Tint,
	?textDecorationThickness:Pixels,
	?textUnderlineOffset:Pixels,
	// a field's size where none is given: Fixed or Content
	?fieldSizing:helder.ui.FieldSizing,
	// the focus ring: Auto (the window's) or None
	?outlineStyle:helder.ui.OutlineStyle,
	// a scroller's thumb and track colours (inherited; null: the window's)
	?scrollbarColor:Tint,
	?scrollbarTrackColor:Tint,
	// its text's shadows (inherited), CSS's text-shadow: the first on top
	?textShadow:Array<ShadowLayer>,
	// how it and its subtree are drawn and hit, not laid out (Transform.parse)
	?transform:TransformRef,
	// the point the transform is about: x, y in its border box (null: its centre)
	?transformOrigin:Array<helder.ui.Dim>,
	// what eases to a new value, and how it enters and leaves (Transition.parse)
	?transition:TransitionRef,
	// a CSS gradient over the background colour, under the border (Gradient.parse)
	?backgroundImage:GradientRef,
	// its state variants, over it where the state is on (a later one's over an earlier's)
	?hover:StyleProps,
	?pressed:StyleProps,
	?focus:StyleProps,
	?disabled:StyleProps,
	?selected:StyleProps,
	?checked:StyleProps,
	// a checkbox's while neither checked nor not (indeterminate)
	?mixed:StyleProps,
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
	?checked:StyleProps,
	?mixed:StyleProps
}

// (a transform's and a transition's types: Dynamic where Style's macros run, so that they load no canvas or motion)
#if macro
typedef TransformRef = Dynamic;
typedef TransitionRef = Dynamic;
typedef GradientRef = Dynamic;
#else
typedef TransformRef = helder.ui.Transform;
typedef TransitionRef = helder.ui.Transition;
typedef GradientRef = helder.ui.Gradient;
#end

// A colour: one, a theme's token (Token<Color>: its value in the theme in
// scope), or the text's (current).
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

	@:from static inline function ofToken(t:Token<Color>):Tint
		return Token(t.name);

	public static var current(get, never):Tint;

	static inline function get_current():Tint
		return Current;
}

// A length: px, or a percentage ("50%"); null: auto.
abstract Measure(Len) from Len to Len {
	@:from static inline function ofFloat(v:Float):Measure
		return Px(v);

	@:from static inline function ofInt(v:Int):Measure
		return Px(v);

	@:from static inline function ofToken(t:Token<Length>):Measure
		return Px(Pixels.ofToken(t));

	@:from static function ofString(s:String):Measure {
		var t = StringTools.trim(s);
		if (t == "auto") return Auto;
		if (StringTools.endsWith(t, "%")) return Percent(Std.parseFloat(t.substr(0, t.length - 1)));
		var v = Std.parseFloat(StringTools.endsWith(t, "px") ? t.substr(0, t.length - 2) : t);
		return Math.isNaN(v) ? Auto : Px(v);
	}
}

// A length in px, or a theme's length token (Token<Length>): its value in
// the theme in scope. (A token is a float far below any length, as
// helder.ui's Length.token.)
abstract Pixels(Float) from Float from Int to Float {
	@:from @:allow(helder.ui) static function ofToken(t:Token<Length>):Pixels {
		names ??= [];
		ids ??= new Map();
		var k = ids.get(t.name);
		if (k == null) {
			ids.set(t.name, k = names.length);
			names.push(t.name);
		}
		return cast -(BASE + k);
	}

	static inline var BASE = 1e15;
	// (no initializers: a style made in another class's static initializer may come first)
	static var names:Array<String>;
	static var ids:Map<String, Int>;

	@:allow(helder.ui) static inline function isToken(v:Float):Bool
		return v <= -BASE;

	// (v in a theme: a token's value there, else itself)
	@:allow(helder.ui) static inline function resolve(v:Float, theme:Theme):Float
		return v <= -BASE ? theme.length(names[Std.int(-v - BASE)]) : v;
}

// Four corners' radii in px (top left, top right, bottom right, bottom
// left): one for all, or all four.
abstract Radii(Array<Float>) to Array<Float> {
	inline function new(a:Array<Float>)
		this = a;

	@:from static inline function ofFloat(v:Float):Radii
		return new Radii([v, v, v, v]);

	@:from static inline function ofInt(v:Int):Radii
		return new Radii([v, v, v, v]);

	@:from static inline function ofToken(t:Token<Length>):Radii
		return ofFloat(Pixels.ofToken(t));

	@:from static function ofArray(a:Array<Pixels>):Radii
		return new Radii(a.length == 1 ? [a[0], a[0], a[0], a[0]] : a.length == 2 ? [a[0], a[1], a[0], a[1]] : a.length == 3 ? [a[0], a[1], a[2], a[1]] : [a[0], a[1], a[2], a[3]]);
}

typedef ShadowLayer = {
	x:Pixels,
	y:Pixels,
	?blur:Pixels,
	?spread:Pixels,
	color:Tint,
	?inset:Bool
}

// drawn outside the border box (offset further out), Solid unless said
typedef Outline = {
	width:Pixels,
	color:Tint,
	?style:helder.ui.BorderStyle,
	?offset:Pixels
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

	@:from static inline function ofToken(t:Token<Length>):Edges
		return ofFloat(Pixels.ofToken(t));


	@:from static function ofArray(a:Array<Pixels>):Edges
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
@:allow(helder.ui)
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
	public var flexBasis:Null<Measure> = null;
	public var gap:Null<Pixels> = null;
	public var rowGap:Null<Pixels> = null;
	public var columnGap:Null<Pixels> = null;
	public var width:Null<Measure> = null;
	public var height:Null<Measure> = null;
	public var minWidth:Null<Measure> = null;
	public var minHeight:Null<Measure> = null;
	public var maxWidth:Null<Measure> = null;
	public var maxHeight:Null<Measure> = null;
	public var padding:Null<Edges> = null;
	public var margin:Null<Edges> = null;
	public var borderWidth:Null<Edges> = null;
	public var borderColor:Null<Tint> = null;
	public var borderStyle:Null<helder.ui.BorderStyle> = null;
	public var borderRadius:Null<Radii> = null;
	public var background:Null<Tint> = null;
	public var shadows:Null<Array<ShadowLayer>> = null;
	public var outline:Null<Outline> = null;
	public var opacity:Null<Float> = null;
	public var overflow:Null<Overflow> = null;
	public var position:Null<Position> = null;
	public var top:Null<Measure> = null;
	public var right:Null<Measure> = null;
	public var bottom:Null<Measure> = null;
	public var left:Null<Measure> = null;
	public var zIndex:Null<Int> = null;
	public var color:Null<Tint> = null;
	public var fontSize:Null<Pixels> = null;
	public var fontWeight:Null<Int> = null;
	public var fontFamily:Null<String> = null;
	public var fontStyle:Null<FontStyle> = null;
	public var lineHeight:Null<Float> = null;
	public var letterSpacing:Null<Pixels> = null;
	public var textAlign:Null<TextAlign> = null;
	public var textWrap:Null<helder.ui.TextWrap> = null;
	public var textOverflow:Null<helder.ui.TextOverflow> = null;
	public var lineClamp:Null<Int> = null;
	public var textDecoration:Null<Int> = null;
	public var cursor:Null<helder.ui.Cursor> = null;
	public var pointerEvents:Null<helder.ui.PointerEvents> = null;
	public var direction:Null<helder.ui.Dir> = null;
	public var fontVariantNumeric:Null<String> = null;
	public var aspectRatio:Null<Float> = null;
	public var scrollbarWidth:Null<helder.ui.ScrollbarWidth> = null;
	public var justifyItems:Null<Align> = null;
	public var justifySelf:Null<Align> = null;
	public var gridTemplateColumns:Null<String> = null;
	public var gridTemplateRows:Null<String> = null;
	public var gridTemplateAreas:Null<String> = null;
	public var gridAutoColumns:Null<String> = null;
	public var gridAutoRows:Null<String> = null;
	public var gridAutoFlow:Null<String> = null;
	public var gridColumn:Null<String> = null;
	public var gridRow:Null<String> = null;
	public var gridArea:Null<String> = null;
	public var visibility:Null<helder.ui.Visibility> = null;
	public var userSelect:Null<helder.ui.UserSelect> = null;
	public var textTransform:Null<helder.ui.TextTransform> = null;
	public var wordSpacing:Null<Pixels> = null;
	public var overflowWrap:Null<helder.ui.OverflowWrap> = null;
	public var wordBreak:Null<helder.ui.WordBreak> = null;
	public var hyphens:Null<helder.ui.Hyphens> = null;
	public var fontFeatureSettings:Null<String> = null;
	public var order:Null<Int> = null;
	public var textDecorationColor:Null<Tint> = null;
	public var textDecorationThickness:Null<Pixels> = null;
	public var textUnderlineOffset:Null<Pixels> = null;
	public var fieldSizing:Null<helder.ui.FieldSizing> = null;
	public var outlineStyle:Null<helder.ui.OutlineStyle> = null;
	public var scrollbarColor:Null<Tint> = null;
	public var scrollbarTrackColor:Null<Tint> = null;
	public var textShadow:Null<Array<ShadowLayer>> = null;
	public var transform:Null<TransformRef> = null;
	public var transformOrigin:Null<Array<helder.ui.Dim>> = null;
	public var transition:Null<TransitionRef> = null;
	public var backgroundImage:Null<GradientRef> = null;
	public var hover:Null<Props> = null;
	public var pressed:Null<Props> = null;
	public var focus:Null<Props> = null;
	public var disabled:Null<Props> = null;
	public var selected:Null<Props> = null;
	public var checked:Null<Props> = null;
	public var mixed:Null<Props> = null;
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
		o.borderStyle = p.borderStyle;
		o.borderRadius = p.borderRadius;
		o.background = p.background;
		o.shadows = p.shadows;
		o.outline = p.outline;
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
		o.textWrap = p.textWrap;
		o.textOverflow = p.textOverflow;
		o.lineClamp = p.lineClamp;
		o.textDecoration = p.textDecoration;
		o.cursor = p.cursor;
		o.pointerEvents = p.pointerEvents;
		o.direction = p.direction;
		o.fontVariantNumeric = p.fontVariantNumeric;
		o.aspectRatio = p.aspectRatio;
		o.scrollbarWidth = p.scrollbarWidth;
		o.justifyItems = p.justifyItems;
		o.justifySelf = p.justifySelf;
		o.gridTemplateColumns = p.gridTemplateColumns;
		o.gridTemplateRows = p.gridTemplateRows;
		o.gridTemplateAreas = p.gridTemplateAreas;
		o.gridAutoColumns = p.gridAutoColumns;
		o.gridAutoRows = p.gridAutoRows;
		o.gridAutoFlow = p.gridAutoFlow;
		o.gridColumn = p.gridColumn;
		o.gridRow = p.gridRow;
		o.gridArea = p.gridArea;
		o.visibility = p.visibility;
		o.userSelect = p.userSelect;
		o.textTransform = p.textTransform;
		o.wordSpacing = p.wordSpacing;
		o.overflowWrap = p.overflowWrap;
		o.wordBreak = p.wordBreak;
		o.hyphens = p.hyphens;
		o.fontFeatureSettings = p.fontFeatureSettings;
		o.order = p.order;
		o.textDecorationColor = p.textDecorationColor;
		o.textDecorationThickness = p.textDecorationThickness;
		o.textUnderlineOffset = p.textUnderlineOffset;
		o.fieldSizing = p.fieldSizing;
		o.outlineStyle = p.outlineStyle;
		o.scrollbarColor = p.scrollbarColor;
		o.scrollbarTrackColor = p.scrollbarTrackColor;
		o.textShadow = p.textShadow;
		o.transform = p.transform;
		o.transformOrigin = p.transformOrigin;
		o.transition = p.transition;
		o.backgroundImage = p.backgroundImage;
		o.hover = from(p.hover);
		o.pressed = from(p.pressed);
		o.focus = from(p.focus);
		o.disabled = from(p.disabled);
		o.selected = from(p.selected);
		o.checked = from(p.checked);
		o.mixed = from(p.mixed);
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
			q.mixed = from(g.mixed);
			o.group = q;
		}
		return o;
	}
}

@:allow(helder.ui)
final class GroupProps {
	public var hover:Null<Props> = null;
	public var pressed:Null<Props> = null;
	public var focus:Null<Props> = null;
	public var disabled:Null<Props> = null;
	public var selected:Null<Props> = null;
	public var checked:Null<Props> = null;
	public var mixed:Null<Props> = null;

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
//   final picked = row.with({background: app.accent});  // app: a Theme.load
final class Style {
	// what it says, its variants in it
	public final props:Props;
	// (its interning key: what it says, written out)
	final key:String;

	// (each by its key; before none, made of it)
	static final interned = new Map<String, Style>();
	static var internedCount = 0;

	// the style that says nothing
	public static final none = intern(new Props());

	// (whether it reads the theme: a token, a dark variant; one that doesn't is resolved once for every theme)
	@:allow(helder.ui) final themed:Bool;

	function new(props:Props, key:String, themed:Bool) {
		this.props = props;
		this.key = key;
		this.themed = themed;
	}

	// The style of props: the one made of the same before, else a new one.
	public static macro function of(props:haxe.macro.Expr):haxe.macro.Expr.ExprOf<Style>
		return switch props.expr {
			case EObjectDecl(_) if (grid(props)): macro {
					helder.ui.Grids.use();
					helder.ui.Style.intern(${typed(props)});
				};
			case EObjectDecl(_): macro helder.ui.Style.intern(${typed(props)});
			case _: macro helder.ui.Style.ofProps($props);
		}

	// (a style of props an object read when the program runs)
	public static function ofProps(props:StyleProps):Style
		return intern(Props.from(props));

	// (props made typed: the one of the same before, else a style of them)
	@:noCompletion public static function intern(p:Props):Style {
		tokens = false;
		var k = write(p);
		var s = interned.get(k);
		if (s != null) return s;
		// (styles made of values that change every frame, a dragged width's: forgotten past a bound, their nodes
		// keeping theirs, only sharing lost)
		if (internedCount >= BOUND) {
			interned.clear();
			internedCount = 0;
		}
		interned.set(k, s = new Style(p, k, tokens || dark(p)));
		internedCount++;
		return s;
	}

	@:allow(helder.ui) static inline var BOUND = 4096;

	// This style with p over it (a variant's too: merged); p a literal, an object, or a Style.
	public macro function with(self:haxe.macro.Expr, p:haxe.macro.Expr):haxe.macro.Expr.ExprOf<Style>
		return switch p.expr {
			case EObjectDecl(_) if (grid(p)): macro {
					helder.ui.Grids.use();
					$self.over(${typed(p)});
				};
			case EObjectDecl(_): macro $self.over(${typed(p)});
			case _ if (isStyle(p)): macro $self.over(($p : helder.ui.Style).props);
			case _: macro $self.over(helder.ui.Style.Props.from($p));
		}

	// This style with typed props over it.
	@:noCompletion public function over(p:Props):Style
		return intern(merge(props, p));

	#if macro
	// (a literal as typed fields: each name one of Props', its value typed as that field is, where it is written)
	static function typed(e:Expr):Expr {
		var fields = switch e.expr {
			case EObjectDecl(f): f;
			case _: return macro helder.ui.Style.Props.from($e);
		}
		var sets = [macro var p = new helder.ui.Style.Props()];
		for (f in fields) {
			var n = f.field, v = f.expr;
			if (VARIANTS.indexOf(n) >= 0) sets.push(macro @:pos(v.pos) p.$n = ${typed(v)}) else if (n == "group") sets.push(macro @:pos(v.pos) p.group = ${group(v)}) else if (FIELDS.indexOf(n) >= 0)
				sets.push(macro @:pos(v.pos) p.$n = $v) else Context.error('helder.ui: a style has no field $n' + near(n), v.pos);
		}
		sets.push(macro p);
		return macro @:pos(e.pos) $b{sets};
	}

	// (a literal that says grid, its variants' too: grid layout linked where it is written)
	static function grid(e:Expr):Bool {
		var fields = switch e.expr {
			case EObjectDecl(f): f;
			case _: return false;
		}
		for (f in fields) {
			if (StringTools.startsWith(f.field, "grid") || grid(f.expr)) return true;
			if (f.field == "display") switch f.expr.expr {
				case EConst(CIdent("Grid")) | EField(_, "Grid"): return true;
				case _:
			}
		}
		return false;
	}

	static function group(e:Expr):Expr {
		var fields = switch e.expr {
			case EObjectDecl(f): f;
			case _: Context.error("helder.ui: a style's group is a literal of its states' styles", e.pos);
		}
		var sets = [macro var g = new helder.ui.Style.GroupProps()];
		for (f in fields) {
			var n = f.field;
			if (GROUP_STATES.indexOf(n) < 0) Context.error('helder.ui: a group has no state $n (${GROUP_STATES.join(", ")})', f.expr.pos);
			sets.push(macro g.$n = ${typed(f.expr)});
		}
		sets.push(macro g);
		return macro $b{sets};
	}

	static function isStyle(e:Expr):Bool
		return try switch Context.follow(Context.typeof(e)) {
			case TInst(_.get() => c, _): c.name == "Style" && c.pack.join(".") == "helder.ui";
			case _: false;
		} catch (_:Dynamic) false;

	// (the field meant: one a letter or two away)
	static function near(n:String):String {
		for (f in FIELDS.concat(VARIANTS)) if (StringTools.startsWith(f.toLowerCase(), n.toLowerCase().substr(0, 3))) return '; did you mean $f?';
		return "";
	}
	static final FIELDS = ["display", "flexDirection", "flexWrap", "alignItems", "alignSelf", "justifyContent", "alignContent", "flexGrow", "flexShrink", "flexBasis", "gap", "rowGap", "columnGap", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "padding", "margin", "borderWidth", "borderColor", "borderStyle", "borderRadius", "background", "shadows", "outline", "opacity", "overflow", "position", "top", "right", "bottom", "left", "zIndex", "color", "fontSize", "fontWeight", "fontFamily", "fontStyle", "lineHeight", "letterSpacing", "textAlign", "textWrap", "textOverflow", "lineClamp", "textDecoration", "cursor", "pointerEvents", "direction", "fontVariantNumeric", "aspectRatio", "scrollbarWidth", "justifyItems", "justifySelf", "gridTemplateColumns", "gridTemplateRows", "gridTemplateAreas", "gridAutoColumns", "gridAutoRows", "gridAutoFlow", "gridColumn", "gridRow", "gridArea", "visibility", "userSelect", "textTransform", "wordSpacing", "overflowWrap", "wordBreak", "hyphens", "fontFeatureSettings", "order", "textDecorationColor", "textDecorationThickness", "textUnderlineOffset", "fieldSizing", "outlineStyle", "scrollbarColor", "scrollbarTrackColor", "textShadow", "transform", "transformOrigin", "transition", "backgroundImage"];
	static final VARIANTS = ["hover", "pressed", "focus", "disabled", "selected", "checked", "mixed", "placeholder", "dark"];
	static final GROUP_STATES = ["hover", "pressed", "focus", "disabled", "selected", "checked", "mixed"];
	#end

	// a state's bit (Node.state's): hover, pressed, focus, disabled, selected, checked, placeholder; a group's, it shifted by GROUP
	public static inline var HOVER = 1;
	public static inline var PRESSED = 2;
	public static inline var FOCUS = 4;
	public static inline var DISABLED = 8;
	public static inline var SELECTED = 16;
	public static inline var CHECKED = 32;
	public static inline var PLACEHOLDER = 64;
	public static inline var MIXED = 128;
	public static inline var GROUP = 8;
	// (passed down with the group's states, what it inherits besides its text: an ancestor's pointerEvents None,
	// its visibility Hidden)
	@:allow(helder.ui) static inline var PASS = 1 << 12;
	@:allow(helder.ui) static inline var HIDE = 1 << 13;

	// (what it says in states: its own (mask's low bits) and its group's (shifted by GROUP), the variants over it
	// in order; dark: the theme's tone)
	public function at(mask:Int, dark = false):Props {
		var p = props;
		if (mask == 0 && (!dark || p.dark == null)) return p;
		return apply(p, mask, dark);
	}

	// (p in states: its variants over it, each with its own variants (selected: {hover: ...}) applied first)
	static function apply(p:Props, mask:Int, dark:Bool):Props {
		var out = p;
		inline function over(bit:Int, v:Null<Props>)
			if (mask & bit != 0 && v != null) out = merge(out, apply(v, mask, dark));
		if (dark && p.dark != null) out = merge(out, apply(p.dark, mask, dark));
		var g = p.group;
		if (g != null) {
			over(HOVER << GROUP, g.hover);
			over(PRESSED << GROUP, g.pressed);
			over(FOCUS << GROUP, g.focus);
			over(DISABLED << GROUP, g.disabled);
			over(SELECTED << GROUP, g.selected);
			over(CHECKED << GROUP, g.checked);
			over(MIXED << GROUP, g.mixed);
		}
		over(HOVER, p.hover);
		over(PRESSED, p.pressed);
		over(FOCUS, p.focus);
		over(DISABLED, p.disabled);
		over(SELECTED, p.selected);
		over(CHECKED, p.checked);
		over(MIXED, p.mixed);
		over(PLACEHOLDER, p.placeholder);
		return out;
	}

	// (the states it has a variant for: what a change of the others leaves it as it is)
	public var states(get, never):Int;

	function get_states():Int
		return statesOf(props);

	// (the states p has a variant for, its variants' variants' too)
	static function statesOf(p:Null<Props>):Int {
		if (p == null) return 0;
		var m = 0;
		inline function has(bit:Int, v:Null<Props>)
			if (v != null) m |= bit | statesOf(v);
		has(HOVER, p.hover);
		has(PRESSED, p.pressed);
		has(FOCUS, p.focus);
		has(DISABLED, p.disabled);
		has(SELECTED, p.selected);
		has(CHECKED, p.checked);
		has(MIXED, p.mixed);
		has(PLACEHOLDER, p.placeholder);
		if (p.dark != null) m |= statesOf(p.dark);
		var g = p.group;
		if (g != null) {
			has(HOVER << GROUP, g.hover);
			has(PRESSED << GROUP, g.pressed);
			has(FOCUS << GROUP, g.focus);
			has(DISABLED << GROUP, g.disabled);
			has(SELECTED << GROUP, g.selected);
			has(CHECKED << GROUP, g.checked);
			has(MIXED << GROUP, g.mixed);
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
		o.borderStyle = b.borderStyle ?? a.borderStyle;
		o.borderRadius = b.borderRadius ?? a.borderRadius;
		o.background = b.background ?? a.background;
		o.shadows = b.shadows ?? a.shadows;
		o.outline = b.outline ?? a.outline;
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
		o.textWrap = b.textWrap ?? a.textWrap;
		o.textOverflow = b.textOverflow ?? a.textOverflow;
		o.lineClamp = b.lineClamp ?? a.lineClamp;
		o.textDecoration = b.textDecoration ?? a.textDecoration;
		o.cursor = b.cursor ?? a.cursor;
		o.pointerEvents = b.pointerEvents ?? a.pointerEvents;
		o.direction = b.direction ?? a.direction;
		o.fontVariantNumeric = b.fontVariantNumeric ?? a.fontVariantNumeric;
		o.aspectRatio = b.aspectRatio ?? a.aspectRatio;
		o.scrollbarWidth = b.scrollbarWidth ?? a.scrollbarWidth;
		o.justifyItems = b.justifyItems ?? a.justifyItems;
		o.justifySelf = b.justifySelf ?? a.justifySelf;
		o.gridTemplateColumns = b.gridTemplateColumns ?? a.gridTemplateColumns;
		o.gridTemplateRows = b.gridTemplateRows ?? a.gridTemplateRows;
		o.gridTemplateAreas = b.gridTemplateAreas ?? a.gridTemplateAreas;
		o.gridAutoColumns = b.gridAutoColumns ?? a.gridAutoColumns;
		o.gridAutoRows = b.gridAutoRows ?? a.gridAutoRows;
		o.gridAutoFlow = b.gridAutoFlow ?? a.gridAutoFlow;
		o.gridColumn = b.gridColumn ?? a.gridColumn;
		o.gridRow = b.gridRow ?? a.gridRow;
		o.gridArea = b.gridArea ?? a.gridArea;
		o.visibility = b.visibility ?? a.visibility;
		o.userSelect = b.userSelect ?? a.userSelect;
		o.textTransform = b.textTransform ?? a.textTransform;
		o.wordSpacing = b.wordSpacing ?? a.wordSpacing;
		o.overflowWrap = b.overflowWrap ?? a.overflowWrap;
		o.wordBreak = b.wordBreak ?? a.wordBreak;
		o.hyphens = b.hyphens ?? a.hyphens;
		o.fontFeatureSettings = b.fontFeatureSettings ?? a.fontFeatureSettings;
		o.order = b.order ?? a.order;
		o.textDecorationColor = b.textDecorationColor ?? a.textDecorationColor;
		o.textDecorationThickness = b.textDecorationThickness ?? a.textDecorationThickness;
		o.textUnderlineOffset = b.textUnderlineOffset ?? a.textUnderlineOffset;
		o.fieldSizing = b.fieldSizing ?? a.fieldSizing;
		o.outlineStyle = b.outlineStyle ?? a.outlineStyle;
		o.scrollbarColor = b.scrollbarColor ?? a.scrollbarColor;
		o.scrollbarTrackColor = b.scrollbarTrackColor ?? a.scrollbarTrackColor;
		o.textShadow = b.textShadow ?? a.textShadow;
		o.transform = b.transform ?? a.transform;
		o.transformOrigin = b.transformOrigin ?? a.transformOrigin;
		o.transition = b.transition ?? a.transition;
		o.backgroundImage = b.backgroundImage ?? a.backgroundImage;
		o.hover = both(a.hover, b.hover);
		o.pressed = both(a.pressed, b.pressed);
		o.focus = both(a.focus, b.focus);
		o.disabled = both(a.disabled, b.disabled);
		o.selected = both(a.selected, b.selected);
		o.checked = both(a.checked, b.checked);
		o.mixed = both(a.mixed, b.mixed);
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
			g.mixed = both(a.group.mixed, b.group.mixed);
			g;
		}
		return o;
	}

	static function both(a:Null<Props>, b:Null<Props>):Null<Props>
		return a == null ? b : b == null ? a : merge(a, b);

	// (what it says written out: its key. Floats as their bits or integers:
	// hxmc's Float to String throws in a static initializer, where styles are
	// made)
	@:allow(helder.ui) static function write(p:Null<Props>):String {
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
		if (p.borderStyle != null) word(out, "bs", p.borderStyle);
		if (p.borderRadius != null) edges(out, "br", p.borderRadius);
		if (p.background != null) tint(out, "bg", p.background);
		if (p.shadows != null) for (sh in p.shadows) {
			out.add("sh");
			edges(out, sh.inset == true ? "i" : "", [sh.x, sh.y, sh.blur ?? 0, sh.spread ?? 0]);
			tint(out, "", sh.color);
		}
		if (p.outline != null) {
			var o = p.outline;
			edges(out, "ol" + (o.style ?? Solid), [o.width, o.offset ?? 0]);
			tint(out, "", o.color);
		}
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
		if (p.textWrap != null) word(out, "wr", p.textWrap);
		if (p.textOverflow != null) word(out, "to", p.textOverflow);
		if (p.lineClamp != null) word(out, "lc", p.lineClamp);
		if (p.textDecoration != null) word(out, "td", p.textDecoration);
		if (p.cursor != null) word(out, "cu", p.cursor);
		if (p.pointerEvents != null) word(out, "pe", p.pointerEvents);
		if (p.direction != null) word(out, "dir", p.direction);
		if (p.fontVariantNumeric != null) word(out, "fvn", p.fontVariantNumeric);
		if (p.aspectRatio != null) num(out, "ar", p.aspectRatio);
		if (p.scrollbarWidth != null) word(out, "sbw", p.scrollbarWidth);
		if (p.justifyItems != null) word(out, "ji", p.justifyItems);
		if (p.justifySelf != null) word(out, "js", p.justifySelf);
		if (p.gridTemplateColumns != null) word(out, "gtc", p.gridTemplateColumns);
		if (p.gridTemplateRows != null) word(out, "gtr", p.gridTemplateRows);
		if (p.gridTemplateAreas != null) word(out, "gta", p.gridTemplateAreas);
		if (p.gridAutoColumns != null) word(out, "gac", p.gridAutoColumns);
		if (p.gridAutoRows != null) word(out, "gar", p.gridAutoRows);
		if (p.gridAutoFlow != null) word(out, "gaf", p.gridAutoFlow);
		if (p.gridColumn != null) word(out, "gc", p.gridColumn);
		if (p.gridRow != null) word(out, "gr", p.gridRow);
		if (p.gridArea != null) word(out, "ga", p.gridArea);
		if (p.visibility != null) word(out, "vis", p.visibility);
		if (p.userSelect != null) word(out, "us", p.userSelect);
		if (p.textTransform != null) word(out, "ttf", p.textTransform);
		if (p.wordSpacing != null) num(out, "ws", p.wordSpacing);
		if (p.overflowWrap != null) word(out, "ow", p.overflowWrap);
		if (p.wordBreak != null) word(out, "wbk", p.wordBreak);
		if (p.hyphens != null) word(out, "hyp", p.hyphens);
		if (p.fontFeatureSettings != null) word(out, "ffs", p.fontFeatureSettings);
		if (p.order != null) word(out, "ord", p.order);
		if (p.textDecorationColor != null) tint(out, "tdc", p.textDecorationColor);
		if (p.textDecorationThickness != null) num(out, "tdt", p.textDecorationThickness);
		if (p.textUnderlineOffset != null) num(out, "tuo", p.textUnderlineOffset);
		if (p.fieldSizing != null) word(out, "fsz", p.fieldSizing);
		if (p.outlineStyle != null) word(out, "os", p.outlineStyle);
		if (p.scrollbarColor != null) tint(out, "sbc", p.scrollbarColor);
		if (p.scrollbarTrackColor != null) tint(out, "sbt", p.scrollbarTrackColor);
		if (p.textShadow != null) for (sh in p.textShadow) {
			out.add("tsh");
			edges(out, "", [sh.x, sh.y, sh.blur ?? 0, sh.spread ?? 0]);
			tint(out, "", sh.color);
		}
		if (p.transform != null) word(out, "tf", @:privateAccess p.transform.key());
		if (p.transformOrigin != null) for (d in p.transformOrigin) size(out, "tfo", switch (d : helder.ui.DimValue) {
			case Px(v): Px(v);
			case Percent(v): Percent(v);
			case _: Auto;
		});
		if (p.transition != null) word(out, "tr", @:privateAccess p.transition.key());
		if (p.backgroundImage != null) word(out, "bgi", @:privateAccess p.backgroundImage.key());
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
		sub("mixed", p.mixed);
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
			sub("mixed", g.mixed);
			out.add("}");
		}
		return out.toString();
	}

	// (a token seen by the last write)
	static var tokens = false;

	// (a dark variant anywhere in it)
	static function dark(p:Null<Props>):Bool {
		if (p == null) return false;
		if (p.dark != null) return true;
		for (v in [p.hover, p.pressed, p.focus, p.disabled, p.selected, p.checked, p.placeholder]) if (dark(v)) return true;
		var g = p.group;
		return g != null && (dark(g.hover) || dark(g.pressed) || dark(g.focus) || dark(g.disabled) || dark(g.selected) || dark(g.checked));
	}

	static function word(out:StringBuf, k:String, v:Any) {
		out.add(k);
		out.add("=");
		out.add(v);
		out.add(";");
	}

	static function float(out:StringBuf, v:Float) {
		if (Pixels.isToken(v)) tokens = true;
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
				tokens = true;
				out.add("$");
				out.add(name);
			case Current:
				out.add("=current");
		}
		out.add(";");
	}
}
