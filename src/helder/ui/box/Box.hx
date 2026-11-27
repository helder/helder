package helder.ui.box;

import helder.canvas.Bitmap;
import helder.dom.Node;
import helder.ui.flow.FormattingContext;

// One box of the box tree (CSS 2.1 §9.2, Display 3): what the DOM and its
// computed styles generate, anonymous boxes included. Layout reads it,
// and keeps its cache here; fragments are apart (Fragments).
class Box {
	public final kind:BoxKind;
	// (another as a live document is restyled, DocumentView.update)
	public var style(default, null):BoxStyle;
	// the element or text node it is for: null for an anonymous box
	public final node:Null<Node>;
	public var parent(default, null):Null<Box> = null;
	public var first(default, null):Null<Box> = null;
	public var last(default, null):Null<Box> = null;
	public var next(default, null):Null<Box> = null;
	// a text run's text, as the DOM has it (white space is the inline layout's)
	public var text = "";
	// (offset of text in node's data: generated text has none)
	public var offset = 0;
	// (what few boxes have, and layout's state, which text and inline boxes
	// do without: apart, made when first set to other than its default, so a
	// box of a long document's hundreds of thousands holds its tree and
	// little else)
	var extra:Null<BoxExtra> = null;
	var state:Null<BoxState> = null;
	// "before", "after", "marker": generated content's
	public var pseudo(get, never):Null<String>;
	// a leader's fill (LEADER: its text that repeated)
	public var fill(get, set):String;
	// the formatting context it establishes for its contents, if any
	public var context(get, set):Null<FormattingContext>;
	public var image(get, set):Null<Bitmap>;
	// a replaced element's SVG (an image's, or inline <svg>): drawn as vectors, sized by its natural width,
	// height and ratio where it has them (Images 3 §4)
	public var svg(get, set):Null<helder.canvas.Svg>;
	// a table box's grid as laid out (its columns, rows, collapsed borders)
	public var table(get, set):Null<TableGrid>;
	public var flags = 0;
	// (its place in its tree, depth first: PaintOrder's tree order; -1 until asked)
	public var rank = -1;

	// an inline box split around a block: no start edge here (a later part), or no end edge
	public static inline var NO_START = 1;
	public static inline var NO_END = 2;
	// a list item's marker, outside its principal box
	public static inline var OUTSIDE = 4;
	// a table's box or part in the collapsing border model: its borders are the table's to paint
	public static inline var COLLAPSED = 8;
	// a table cell with no content (empty-cells)
	public static inline var EMPTY = 16;
	// (its last layout left absolutely positioned boxes for a containing block outside it)
	public static inline var ESCAPES = 32;
	// where a running element was (GCPM 3 §2.1): nothing, its page the element's
	public static inline var RUNNING = 64;
	// a leader's fill (GCPM 3 §3): its text repeated to its line's room
	public static inline var LEADER = 128;
	// a monolithic box sliced across fragmentainers: on each, clipped to its area (its overflow on the next)
	public static inline var SLICED = 256;

	// (layout's: the constraints of the last layout and its result, LayoutNG's cache)
	public var cacheWidth(get, set):Float;
	public var cacheHeight(get, set):Float;
	// (and the fixed height it was laid out at, whether its height was ignored: a flex or grid item's passes)
	public var cacheFixedHeight(get, set):Float;
	public var cacheIgnore(get, set):Bool;
	// (the layouts before the last at other constraints, kept beside it, 5
	// numbers each: the width's key, the height, the fixed height, the
	// height ignored (1), the fragment; a flex or grid item's measuring and
	// final passes each hit their own)
	public var cacheMore(get, set):Null<Array<Float>>;

	// its layouts let go: laid out again when next asked
	public function uncache() {
		if (state == null) return;
		state.cacheFragment = -1;
		state.cacheMore = null;
	}

	public var cacheFragment(get, set):Int;
	public var minContent(get, set):Float;
	public var maxContent(get, set):Float;
	// (its inline content as BlockLines built it, kept while its text and styles stay: BlockLines' Built)
	public var inlineCache(get, set):Null<Any>;
	// (its lines' last layout, kept for hit testing, carets and selection)
	public var lines(get, set):Null<helder.ui.flow.BlockText>;
	// (its used side margins; the margins that collapse through its top and
	// its bottom, the largest positive and the most negative; whether its
	// top and bottom margins collapse together, §8.3.1)
	public var marginLeft(get, set):Float;
	public var marginRight(get, set):Float;
	public var topPositive(get, set):Float;
	public var topNegative(get, set):Float;
	public var bottomPositive(get, set):Float;
	public var bottomNegative(get, set):Float;
	public var through(get, set):Bool;

	public function new(kind:BoxKind, style:BoxStyle, ?node:Node, ?pseudo:String) {
		this.kind = kind;
		this.style = style;
		this.node = node;
		if (pseudo != null) own().pseudo = pseudo;
	}

	inline function own():BoxExtra
		return extra ??= new BoxExtra();

	inline function laid():BoxState
		return state ??= new BoxState();

	inline function get_pseudo():Null<String>
		return extra == null ? null : extra.pseudo;

	inline function get_fill():String
		return extra == null ? "" : extra.fill;

	inline function set_fill(v:String):String
		return extra == null && v == "" ? v : own().fill = v;

	inline function get_context():Null<FormattingContext>
		return extra == null ? null : extra.context;

	inline function set_context(v:Null<FormattingContext>):Null<FormattingContext>
		return extra == null && v == null ? v : own().context = v;

	inline function get_image():Null<Bitmap>
		return extra == null ? null : extra.image;

	inline function set_image(v:Null<Bitmap>):Null<Bitmap>
		return extra == null && v == null ? v : own().image = v;

	inline function get_svg():Null<helder.canvas.Svg>
		return extra == null ? null : extra.svg;

	inline function set_svg(v:Null<helder.canvas.Svg>):Null<helder.canvas.Svg>
		return extra == null && v == null ? v : own().svg = v;

	inline function get_table():Null<TableGrid>
		return extra == null ? null : extra.table;

	inline function set_table(v:Null<TableGrid>):Null<TableGrid>
		return extra == null && v == null ? v : own().table = v;

	inline function get_cacheWidth():Float
		return state == null ? Math.NaN : state.cacheWidth;

	inline function set_cacheWidth(v:Float):Float
		return state == null && v != v ? v : laid().cacheWidth = v;

	inline function get_cacheHeight():Float
		return state == null ? Math.NaN : state.cacheHeight;

	inline function set_cacheHeight(v:Float):Float
		return state == null && v != v ? v : laid().cacheHeight = v;

	inline function get_cacheFixedHeight():Float
		return state == null ? Math.NaN : state.cacheFixedHeight;

	inline function set_cacheFixedHeight(v:Float):Float
		return state == null && v != v ? v : laid().cacheFixedHeight = v;

	inline function get_cacheIgnore():Bool
		return state == null ? false : state.cacheIgnore;

	inline function set_cacheIgnore(v:Bool):Bool
		return state == null && !v ? v : laid().cacheIgnore = v;

	inline function get_cacheMore():Null<Array<Float>>
		return state == null ? null : state.cacheMore;

	inline function set_cacheMore(v:Null<Array<Float>>):Null<Array<Float>>
		return state == null && v == null ? v : laid().cacheMore = v;

	inline function get_cacheFragment():Int
		return state == null ? -1 : state.cacheFragment;

	inline function set_cacheFragment(v:Int):Int
		return state == null && v == -1 ? v : laid().cacheFragment = v;

	inline function get_minContent():Float
		return state == null ? Math.NaN : state.minContent;

	inline function set_minContent(v:Float):Float
		return state == null && v != v ? v : laid().minContent = v;

	inline function get_maxContent():Float
		return state == null ? Math.NaN : state.maxContent;

	inline function set_maxContent(v:Float):Float
		return state == null && v != v ? v : laid().maxContent = v;

	inline function get_inlineCache():Null<Any>
		return state == null ? null : state.inlineCache;

	inline function set_inlineCache(v:Null<Any>):Null<Any>
		return state == null && v == null ? v : laid().inlineCache = v;

	inline function get_lines():Null<helder.ui.flow.BlockText>
		return state == null ? null : state.lines;

	inline function set_lines(v:Null<helder.ui.flow.BlockText>):Null<helder.ui.flow.BlockText>
		return state == null && v == null ? v : laid().lines = v;

	inline function get_marginLeft():Float
		return state == null ? 0 : state.marginLeft;

	inline function set_marginLeft(v:Float):Float
		return state == null && v == 0 ? v : laid().marginLeft = v;

	inline function get_marginRight():Float
		return state == null ? 0 : state.marginRight;

	inline function set_marginRight(v:Float):Float
		return state == null && v == 0 ? v : laid().marginRight = v;

	inline function get_topPositive():Float
		return state == null ? 0 : state.topPositive;

	inline function set_topPositive(v:Float):Float
		return state == null && v == 0 ? v : laid().topPositive = v;

	inline function get_topNegative():Float
		return state == null ? 0 : state.topNegative;

	inline function set_topNegative(v:Float):Float
		return state == null && v == 0 ? v : laid().topNegative = v;

	inline function get_bottomPositive():Float
		return state == null ? 0 : state.bottomPositive;

	inline function set_bottomPositive(v:Float):Float
		return state == null && v == 0 ? v : laid().bottomPositive = v;

	inline function get_bottomNegative():Float
		return state == null ? 0 : state.bottomNegative;

	inline function set_bottomNegative(v:Float):Float
		return state == null && v == 0 ? v : laid().bottomNegative = v;

	inline function get_through():Bool
		return state == null ? false : state.through;

	inline function set_through(v:Bool):Bool
		return state == null && !v ? v : laid().through = v;

	@:allow(helder.ui.box) function restyle(s:BoxStyle)
		style = s;

	public function append(child:Box) {
		child.parent = this;
		if (last == null) first = child else last.next = child;
		last = child;
	}

	public var anonymous(get, never):Bool;

	inline function get_anonymous():Bool
		return node == null && pseudo == null;

	public var blockLevel(get, never):Bool;

	function get_blockLevel():Bool
		return switch kind {
			case Block | BlockReplaced: true;
			case Container: style.outer == BoxStyle.BLOCK && style.inner != BoxStyle.TABLE_PART;
			case TableWrapper: style.outer == BoxStyle.BLOCK;
			case _: false;
		}

	// out of flow (§9.3): a float, or absolutely positioned (a text run's and an inline box's style is
	// their element's, never theirs: floats and absolute positioning make blocks)
	public var floating(get, never):Bool;

	inline function get_floating():Bool
		return kind != Text && kind != Inline && kind != Break && style.floating;

	public var absolute(get, never):Bool;

	inline function get_absolute():Bool
		return kind != Text && kind != Inline && kind != Break && style.absolute;

	// a block container (CSS 2.1 §9.2.1): its contents are blocks or lines
	public var container(get, never):Bool;

	function get_container():Bool
		return kind == Block || kind == InlineBlock || kind == Container;

	public function children():Array<Box> {
		var out = [];
		var c = first;
		while (c != null) {
			out.push(c);
			c = c.next;
		}
		return out;
	}

	public function toString():String {
		var name = node == null ? "" : node.nodeType == Node.ELEMENT_NODE ? " " + node.nodeName.toLowerCase() : "";
		if (pseudo != null) name += '::$pseudo';
		if (kind == Text) name += ' "${text}"';
		return '$kind$name';
	}
}

private class BoxExtra {
	public var pseudo:Null<String> = null;
	public var fill = "";
	public var context:Null<FormattingContext> = null;
	public var image:Null<Bitmap> = null;
	public var svg:Null<helder.canvas.Svg> = null;
	public var table:Null<TableGrid> = null;

	public function new() {}
}

private class BoxState {
	public var cacheWidth = Math.NaN;
	public var cacheHeight = Math.NaN;
	public var cacheFixedHeight = Math.NaN;
	public var cacheIgnore = false;
	public var cacheMore:Null<Array<Float>> = null;
	public var cacheFragment = -1;
	public var minContent = Math.NaN;
	public var maxContent = Math.NaN;
	public var inlineCache:Null<Any> = null;
	public var lines:Null<helder.ui.flow.BlockText> = null;
	public var marginLeft = 0.0;
	public var marginRight = 0.0;
	public var topPositive = 0.0;
	public var topNegative = 0.0;
	public var bottomPositive = 0.0;
	public var bottomNegative = 0.0;
	public var through = false;

	public function new() {}
}
