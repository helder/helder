package helder.ui.fast;

import helder.ui.Event;
import helder.ui.access.Semantics;
import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.flow.Contexts;
import helder.ui.flow.InlineBasicStyle;

// A node of a fast tree: a box made from code and styled by a Style, with
// no element, selector or cascade behind it. It is retained: its box is
// kept from one layout to the next and restyled only where its style,
// states, theme or what it inherits change. A Tree shows it in helder.ui.
//
//   final list = new Node(Style.of({rowGap: 4, padding: 8}));
//   list.append(new TextNode("Buy milk", Style.of({fontSize: 16})));
@:rendered(helder.ui.fast.FastRenderer)
class Node {
	// its style (markup's style={...}; its style attributes over it)
	public var style(default, set):Style;
	public var parent(default, null):Null<Node> = null;
	// its subtree's theme (null: its parent's)
	public var theme(default, set):Null<Theme> = null;
	// its states are its descendants' group states (a style's group: {...})
	public var group(default, set) = false;
	// a name to find it by (markup's tag)
	public var tag:Null<String> = null;
	// what it is to assistive technology (its role, label, checked...)
	public var semantics:Null<Semantics> = null;
	// focused by Tab and a press (a button and a field are)
	public var focusable = false;
	// above 0: first, in order; 0: in tree order; below 0: by a press alone
	public var tabIndex = 0;

	// pressed: a click let go over it, or Enter or Space while it has the focus (the innermost node with one)
	public var onPress:Null<Event->Void> = null;
	// a key while it or a node in it has the focus (then its parent's, unless stopped)
	public var onKeyDown:Null<Event->Void> = null;
	public var onFocus:Null<Event->Void> = null;
	public var onBlur:Null<Event->Void> = null;
	public var onPointerDown:Null<Event->Void> = null;
	public var onPointerUp:Null<Event->Void> = null;
	public var onPointerEnter:Null<Event->Void> = null;
	public var onPointerLeave:Null<Event->Void> = null;

	@:allow(helder.ui.fast) var box:Box;
	@:allow(helder.ui.fast) var tree:Null<Tree> = null;
	@:allow(helder.ui.fast) var accessId = 0;
	final kids:Array<Node> = [];
	final kind:Int;
	var states = 0;
	// (markup's style attributes; its style with them over it, what is resolved)
	// (as markup gave them, name and value in turn: parsed once for all the nodes given the same, Attrs.styled)
	var attrs:Null<Array<Dynamic>> = null;
	var look:Null<Style> = null;
	// (what it was resolved under: its parent's text part, the theme passed down, its group's states)
	var under:Null<InlineBasicStyle> = null;
	var passed:Null<Theme> = null;
	var groupStates = 0;

	public function new(?style:Style) {
		kind = textual() ? Resolve.TEXT : Resolve.VIEW;
		this.style = style ?? Style.none;
	}

	// A style attribute (markup's: padding={8}, color="#3b82f6"), over its style.
	public function attr(name:String, value:Dynamic):Bool {
		if (!Attrs.styles(name)) return false;
		var a = attrs ??= [], i = 0;
		while (i < a.length && a[i] != name) i += 2;
		if (i < a.length) {
			if (a[i + 1] == value) return true;
			a[i + 1] = value;
		} else {
			a.push(name);
			a.push(value);
		}
		if (fresh()) look = null else refresh();
		return true;
	}

	// (being made: no parent, no children, never resolved; markup's attributes on it resolved once, when it is put in)
	inline function fresh():Bool
		return under == null && parent == null && kids.length == 0 && box != null;

	// (its style and attributes, interned: resolved again where they changed)
	function refresh() {
		var next = attrs == null ? style : Attrs.styled(style, attrs);
		if (next == look) return;
		look = next;
		if (box == null) box = made(Resolve.of(next, 0, Resolve.root, Theme.base, kind));
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
	}

	// what its style says now, its states' variants over it
	@:allow(helder.ui.fast) function props():Style.Props
		return (look ??= attrs == null ? style : Attrs.styled(style, attrs)).at(states | groupStates << Style.GROUP, scope().dark);

	// (a text's: TextNode's)
	function textual():Bool
		return false;

	// A node as it was made, without its children: its style, attributes, states, focus and what it is to
	// assistive technology (a markup template's clone, FastRenderer.cloneNode).
	public function clone():Node {
		// (its look worked out once, for all its clones: a list's rows one)
		look ??= attrs == null ? style : Attrs.styled(style, attrs);
		var c = blank();
		c.tag = tag;
		c.focusable = focusable;
		c.tabIndex = tabIndex;
		c.semantics = semantics?.copy();
		c.states = states;
		c.group = group;
		c.theme = theme;
		c.attrs = attrs?.copy();
		c.style = style;
		c.look = look;
		copied(c);
		return c;
	}

	// (its parts for assistive technology that are no fast nodes, a DOM island's: null, none)
	@:allow(helder.ui.fast) function accessOwn(tree:Tree, out:Array<helder.ui.access.AccessNode>):Null<Array<Int>>
		return null;

	// (a new node of its kind; what it has besides a node's copied to its clone)
	function blank():Node
		return new Node();

	function copied(c:Node) {}

	// Its children, in order.
	public function children():Array<Node>
		return kids.copy();

	public function append(child:Node)
		insert(child, null);

	// child before another of its children (null: last); taken from where it was
	public function insert(child:Node, before:Null<Node>) {
		if (child.parent != null) child.remove();
		var i = before == null ? kids.length : kids.lastIndexOf(before);
		if (i < 0) throw "Not a child";
		kids.insert(i, child);
		child.parent = this;
		child.resolve(box.style.text, scope(), groupBelow());
		attach(child);
		changed(Resolve.LAYOUT);
	}

	// It out of its parent.
	public function remove() {
		var p = parent;
		if (p == null) return;
		p.kids.remove(this);
		box.remove();
		parent = null;
		p.changed(Resolve.LAYOUT);
	}

	// A state on or off: Style.HOVER, PRESSED, FOCUS, DISABLED, SELECTED, CHECKED.
	public function state(bit:Int, on:Bool) {
		var next = on ? states | bit : states & ~bit;
		if (next == states) return;
		states = next;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
	}

	public inline function has(bit:Int):Bool
		return states & bit != 0;

	function set_style(s:Style):Style {
		if (s == style) return s;
		style = s;
		if (fresh()) look = null else refresh();
		return s;
	}

	function set_theme(t:Null<Theme>):Null<Theme> {
		if (t == theme) return t;
		theme = t;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
		return t;
	}

	function set_group(g:Bool):Bool {
		if (g == group) return g;
		group = g;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
		return g;
	}

	inline function scope():Theme
		return theme ?? passed ?? Theme.base;

	// (what its children inherit with its group's states: whether the pointer passes through it)
	inline function groupBelow():Int
		return (group ? states : groupStates & ~Style.PASS) | (box.style.rare.pointerEvents == "none" ? Style.PASS : 0);

	// (its style resolved under what it inherits, then its children's where what they inherit changed)
	@:allow(helder.ui.fast) function resolve(text:InlineBasicStyle, theme:Theme, group:Int) {
		under = text;
		passed = theme;
		groupStates = group;
		look ??= attrs == null ? style : Attrs.styled(style, attrs);
		var s = Resolve.of(look, states | group << Style.GROUP, text, scope(), spanned() ? Resolve.SPAN : kind), was = box.style;
		if (s != was) restyled(was, s);
		var t = s.text, th = scope(), below = groupBelow();
		for (c in kids) if (c.under != t || c.passed != th || c.groupStates != below) c.resolve(t, th, below);
	}

	// (a style for another: its box's, made again when its kind changed, out of the box tree when display: none)
	function restyled(was:BoxStyle, now:BoxStyle) {
		var level = Resolve.level(was, now);
		if (kindOf(now) != box.kind) {
			var old = box, fresh = made(now);
			while (old.first != null) {
				var c = old.first;
				c.remove();
				fresh.append(c);
			}
			box = fresh;
			if (old.parent != null) {
				old.parent.insert(fresh, old);
				old.remove();
			}
			swapped(now);
			level = Resolve.LAYOUT;
		} else {
			box.restyle(now);
			// (flex to grid and back: the same kind of box, another formatting context)
			if (now.inner != was.inner && box.container) {
				box.context = contexts().of(now.inner, _ -> {});
				level = Resolve.LAYOUT;
			}
			swapped(now);
		}
		if (was.none != now.none && parent != null) {
			if (now.none) box.remove() else parent.attach(this);
			parent.changed(Resolve.LAYOUT);
			return;
		}
		changed(level);
	}

	// (a style swapped on its box: on the boxes it has inside too, TextNode's run)
	function swapped(now:BoxStyle) {}

	// (child's box into its box, after the shown child's before it (a box knows its next alone: no walk from the
	// first, a list's rows put in one after another))
	function attach(child:Node) {
		if (child.box.style.none) return;
		var i = kids.lastIndexOf(child) - 1;
		while (i >= 0 && kids[i].box.parent != box) i--;
		if (i >= 0) box.insertAfter(child.box, kids[i].box) else box.insert(child.box, box.first);
	}

	// (what a change takes, to its tree: at its box, or one in it)
	function changed(level:Int, ?at:Box) {
		if (level == Resolve.NOTHING) return;
		var n = this;
		while (n.parent != null) n = n.parent;
		if (n.tree != null) n.tree.changed(at ?? box, level);
	}

	function made(s:BoxStyle):Box {
		var b = new Box(kindOf(s), s, this);
		dressed(b);
		b.flags |= Box.MADE;
		if (b.container) b.context = contexts().of(s.inner, _ -> {});
		return b;
	}

	// (a text in a text: a run of it)
	inline function spanned():Bool
		return kind == Resolve.TEXT && parent != null && parent.kind == Resolve.TEXT;

	function kindOf(s:BoxStyle):BoxKind
		return s.outer == BoxStyle.INLINE ? Inline : s.inner == BoxStyle.FLEX || s.inner == BoxStyle.GRID ? Container : Block;

	// (a box made for it: what it holds besides its style, IconNode's svg)
	function dressed(b:Box) {}

	static var shared:Null<Contexts> = null;

	// (block and flex layout alone: grid and tables not linked)
	@:allow(helder.ui.fast) static function contexts():Contexts {
		if (shared != null) return shared;
		var flow = new helder.ui.flow.BlockFlow();
		var c = new Contexts(flow);
		c.flex = new helder.ui.flow.FlexFlow(flow);
		return shared = c;
	}

	// (the node a box is of)
	@:allow(helder.ui.fast) static inline function of(b:Null<Box>):Null<Node> {
		while (b != null && !Std.isOfType(b.source, Node)) b = b.parent;
		return b == null ? null : cast b.source;
	}
}
