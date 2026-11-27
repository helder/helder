package helder.ui.fast;

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
class Node {
	public var style(default, set):Style;
	public var parent(default, null):Null<Node> = null;
	// its subtree's theme (null: its parent's)
	public var theme(default, set):Null<Theme> = null;
	// its states are its descendants' group states (a style's group: {...})
	public var group(default, set) = false;
	// pressed and let go over it (the innermost node with one)
	public var onPress:Null<Void->Void> = null;

	@:allow(helder.ui.fast) var box:Box;
	@:allow(helder.ui.fast) var tree:Null<Tree> = null;
	final kids:Array<Node> = [];
	final kind:Int;
	var states = 0;
	// (what it was resolved under: its parent's text part, the theme passed down, its group's states)
	var under:Null<InlineBasicStyle> = null;
	var passed:Null<Theme> = null;
	var groupStates = 0;

	public function new(?style:Style) {
		kind = textual() ? Resolve.TEXT : Resolve.VIEW;
		this.style = style ?? Style.none;
	}

	// (a text's: TextNode's)
	function textual():Bool
		return false;

	// Its children, in order.
	public function children():Array<Node>
		return kids.copy();

	public function append(child:Node)
		insert(child, null);

	// child before another of its children (null: last); taken from where it was
	public function insert(child:Node, before:Null<Node>) {
		if (child.parent != null) child.remove();
		var i = before == null ? kids.length : kids.indexOf(before);
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
		if (box == null) box = made(Resolve.of(s, 0, Resolve.root, Theme.base, kind));
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
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

	inline function groupBelow():Int
		return group ? states : groupStates;

	// (its style resolved under what it inherits, then its children's where what they inherit changed)
	@:allow(helder.ui.fast) function resolve(text:InlineBasicStyle, theme:Theme, group:Int) {
		under = text;
		passed = theme;
		groupStates = group;
		var s = Resolve.of(style, states | group << Style.GROUP, text, scope(), kind), was = box.style;
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
			level = Resolve.LAYOUT;
		} else {
			box.restyle(now);
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

	// (child's box into its box, before the next shown child's)
	function attach(child:Node) {
		if (child.box.style.none) return;
		var i = kids.indexOf(child) + 1;
		while (i < kids.length && kids[i].box.parent != box) i++;
		box.insert(child.box, i < kids.length ? kids[i].box : null);
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
		b.flags |= Box.MADE;
		if (b.container) b.context = contexts().of(s.inner, _ -> {});
		return b;
	}

	static function kindOf(s:BoxStyle):BoxKind
		return s.inner == BoxStyle.FLEX || s.inner == BoxStyle.GRID ? Container : Block;

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
