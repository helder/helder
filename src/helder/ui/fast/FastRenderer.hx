package helder.ui.fast;

import helder.ui.access.Role;
import helder.ui.access.Semantics;

// helder.view's renderer for fast nodes (Node names it: @:rendered; a
// <Fast>'s children). Its elements are helder.ui's names: view (a Node),
// text and HTML's text names (a TextNode of its text children; spans not
// yet), scroll (a Node that scrolls), field (a FieldNode), icon (an
// IconNode, its name), button (focusable, a Button to assistive
// technology), and the rest of HTML's names as views with their roles.
// Attributes: style={Style} (or StyleProps), the style's fields by name
// (Attrs: CSS's values as markup writes them), tag, role, aria-*,
// focusable, tabIndex, group, the states (hover... as checked={Bool},
// data-state="checked"), a field's value and placeholder, an icon's name,
// theme; the events helder.ui's (NodeEvents): onPress, onKeyDown, onInput,
// onFocus, onBlur, onPointerDown, onPointerUp, onPointerEnter, onPointerLeave.
@:events(helder.ui.view.NodeEvents)
class FastRenderer #if !macro implements helder.view.Renders<Node> #end {
	// (the neutral elements, view, text, button...: its own, made by createElement)
	public static inline var neutralNative = true;

	public static function createElement(tag:String):Node {
		var n:Node = switch tag {
			case "text" | "p" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "label" | "legend" | "a" | "strong" | "em" | "code" | "span": new TextNode("");
			case "field" | "input": new FieldNode();
			case "icon": new IconNode();
			case _: new Node();
		}
		n.tag = tag;
		var role:Null<Role> = switch tag {
			case "button": Button;
			case "nav": Navigation;
			case "main": Main;
			case "ul" | "ol": List;
			case "li": ListItem;
			case "h1" | "h2" | "h3" | "h4" | "h5" | "h6": Heading;
			case "a": Link;
			case _: null;
		}
		if (role != null) semantics(n).role = role;
		switch tag {
			case "button": n.focusable = true;
			case "scroll": n.attr("overflow", "scroll");
			case "h1" | "h2" | "h3" | "h4" | "h5" | "h6": semantics(n).level = Std.parseInt(tag.substr(1));
			case _:
		}
		return n;
	}

	public static inline function createText(text:String):Node
		return new TextNode(text);

	// (a node out of the box tree)
	public static function createMarker(name:String):Node {
		var n = new Node();
		n.attr("display", "none");
		return n;
	}

	public static inline function setText(node:Node, text:String)
		(cast node : TextNode).text = text;

	public static inline function holdsText(el:Node):Bool
		return Std.isOfType(el, TextNode) && !Std.isOfType(el, FieldNode);

	public static function insert(parent:Node, node:Node, before:Null<Node>)
		parent.insert(node, before);

	public static inline function remove(parent:Node, node:Node)
		node.remove();

	public static inline function parentOf(node:Node):Null<Node>
		return node.parent;

	public static function arrange(parent:Node, nodes:Array<Node>, before:Node)
		for (n in nodes) parent.insert(n, before);

	public static inline function isNode(v:Dynamic):Bool
		return Std.isOfType(v, Node);

	// a Style, StyleProps, or a list of them (the later over the earlier, nulls and false skipped)
	public static function setStyle(n:Node, v:Dynamic)
		n.style = styleOf(v);

	static function styleOf(v:Dynamic):Style {
		if (v == null || v == false) return Style.none;
		if (Std.isOfType(v, Style)) return v;
		if (Std.isOfType(v, Array)) {
			var s = Style.none;
			for (x in (v : Array<Dynamic>)) if (x != null && x != false) s = s.with(styleOf(x).props);
			return s;
		}
		return Style.of(v);
	}

	public static function setProperty(n:Node, name:String, v:Dynamic) {
		if (n.attr(name, v)) return;
		switch name {
			case "style": setStyle(n, v);
			case "tag": n.tag = v;
			case "role": semantics(n).role = roleOf(v);
			case "focusable": n.focusable = v == true;
			case "tabIndex": n.tabIndex = Std.int(v);
			case "group": n.group = v == true;
			case "theme": n.theme = v;
			case "hover": n.state(Style.HOVER, v == true);
			case "selected": n.state(Style.SELECTED, v == true);
			case "checked":
				n.state(Style.CHECKED, v == true);
				if (n.semantics != null && n.semantics.role == CheckBox) n.semantics.checked = v == true;
			case "disabled":
				n.state(Style.DISABLED, v == true);
				semantics(n).disabled = v == true;
			case "data-state":
				n.state(Style.CHECKED, v == "checked");
				n.state(Style.SELECTED, v == "selected" || v == "active");
			case "value" if (Std.isOfType(n, FieldNode)): (cast n : FieldNode).value = v == null ? "" : Std.string(v);
			case "placeholder" if (Std.isOfType(n, FieldNode)): (cast n : FieldNode).placeholder = v == null ? "" : Std.string(v);
			case "name" if (Std.isOfType(n, IconNode)): (cast n : IconNode).name = v;
			case "aria-label": semantics(n).label = v == null ? null : Std.string(v);
			case "aria-description": semantics(n).description = v == null ? null : Std.string(v);
			case "aria-checked" | "aria-pressed": semantics(n).checked = v == null ? null : v == true || v == "true";
			case "aria-selected": semantics(n).selected = v == null ? null : v == true || v == "true";
			case "aria-expanded": semantics(n).expanded = v == null ? null : v == true || v == "true";
			case "aria-hidden": semantics(n).hidden = v == true || v == "true";
			case "aria-disabled": semantics(n).disabled = v == true || v == "true";
			case "aria-current": semantics(n).current = v != null && v != false && v != "false";
			case "aria-level": semantics(n).level = v == null ? null : Std.int(v);
			case _ if (StringTools.startsWith(name, "data-")):
			case _:
				throw 'helder.ui.fast: <${n.tag}> has no attribute $name';
		}
	}

	public static function listen(n:Node, name:String, v:Dynamic) {
		var h:Null<Event->Void> = v;
		switch name {
			case "onPress": n.onPress = h;
			case "onKeyDown": n.onKeyDown = h;
			case "onFocus": n.onFocus = h;
			case "onBlur": n.onBlur = h;
			case "onPointerDown": n.onPointerDown = h;
			case "onPointerUp": n.onPointerUp = h;
			case "onPointerEnter": n.onPointerEnter = h;
			case "onPointerLeave": n.onPointerLeave = h;
			case "onInput" if (Std.isOfType(n, FieldNode)): (cast n : FieldNode).onInput = h;
			case _: throw 'helder.ui.fast: <${n.tag}> has no event $name';
		}
	}

	static function semantics(n:Node):Semantics
		return n.semantics ??= {};

	// (a role as ARIA writes it, or a Role)
	static function roleOf(v:Dynamic):Null<Role> {
		if (v == null || !Std.isOfType(v, String)) return v;
		for (r in ROLES) if (r.aria() == v) return r;
		return switch (v : String) {
			case "label": Label;
			case _: throw 'helder.ui.fast: role="$v" is not one of helder.ui.access.Role\'s';
		}
	}

	static final ROLES:Array<Role> = helder.ui.view.Enums.values(Role);
}
