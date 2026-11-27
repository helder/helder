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
	// "before", "after", "marker": generated content's
	public final pseudo:Null<String>;
	public var parent(default, null):Null<Box> = null;
	public var first(default, null):Null<Box> = null;
	public var last(default, null):Null<Box> = null;
	public var next(default, null):Null<Box> = null;
	// a text run's text, as the DOM has it (white space is the inline layout's)
	public var text = "";
	// (offset of text in node's data: generated text has none)
	public var offset = 0;
	// a leader's fill (LEADER: its text that repeated)
	public var fill = "";
	// the formatting context it establishes for its contents, if any
	public var context:Null<FormattingContext> = null;
	public var image:Null<Bitmap> = null;
	// a replaced element's SVG (an image's, or inline <svg>): drawn as vectors, sized by its natural width,
	// height and ratio where it has them (Images 3 §4)
	public var svg:Null<helder.canvas.Svg> = null;
	// a table box's grid as laid out (its columns, rows, collapsed borders)
	public var table:Null<TableGrid> = null;
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
	public var cacheWidth = Math.NaN;
	public var cacheHeight = Math.NaN;
	// (and the fixed height it was laid out at, whether its height was ignored: a flex or grid item's passes)
	public var cacheFixedHeight = Math.NaN;
	public var cacheIgnore = false;
	// (the layouts before the last at other constraints, kept beside it, 5
	// numbers each: the width's key, the height, the fixed height, the
	// height ignored (1), the fragment; a flex or grid item's measuring and
	// final passes each hit their own)
	public var cacheMore:Null<Array<Float>> = null;

	// its layouts let go: laid out again when next asked
	public function uncache() {
		cacheFragment = -1;
		cacheMore = null;
	}
	public var cacheFragment = -1;
	public var minContent = Math.NaN;
	public var maxContent = Math.NaN;
	// (its lines' last layout, kept for hit testing, carets and selection)
	public var lines:Null<helder.ui.flow.BlockText> = null;
	// (its used side margins; the margins that collapse through its top and
	// its bottom, the largest positive and the most negative; whether its
	// top and bottom margins collapse together, §8.3.1)
	public var marginLeft = 0.0;
	public var marginRight = 0.0;
	public var topPositive = 0.0;
	public var topNegative = 0.0;
	public var bottomPositive = 0.0;
	public var bottomNegative = 0.0;
	public var through = false;

	public function new(kind:BoxKind, style:BoxStyle, ?node:Node, ?pseudo:String) {
		this.kind = kind;
		this.style = style;
		this.node = node;
		this.pseudo = pseudo;
	}

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
