package helder.ui.controls;

import helder.ui.*;
import helder.ui.actions.Actions.actions;
import helder.ui.controls.Props;
import helder.ui.controls.Variant.PathBarSize;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.menu.Menus;
import helder.ui.controls.Icons;
import helder.ui.controls.TextField;
import helder.view.Flow.Mountable;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

@:noCompletion @:typescript.hide
enum PathBarAction {
	Navigate(index:Int);
}

@:typescript.hide
class PathBarMount implements Mountable<Node> {
	final props:PathBarProps;

	public function new(props:PathBarProps)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var bar = new PathBarNode(props);
		parent.insert(bar, before == null ? parent.children.length : parent.indexOf(before));
		bar.bind();
		return [bar];
	}
}

private typedef Crumb = {
	final segment:Node;
	final separator:Null<Node>;
}

private class PathBarNode extends Node {
	final props:PathBarProps;
	final editing:Signal<Bool>;
	final canEdit:Bool;
	final row = new Node("pathbar-segments");
	final overflow:Node;
	final overflowSeparator:Node;
	var crumbs:Array<Crumb> = [];
	var labels:Array<String> = [];
	var field:Null<TextField>;
	var firstHidden = 0;
	var endHidden = 0;
	var fittedWidth = -1.0;
	var generation = -1;

	public function new(props:PathBarProps) {
		super(props.tag ?? "pathbar");
		this.props = props;
		canEdit = props.editable != false;
		editing = props.editing ?? Graph.signal(false);
		slot = "pathbar";
		size = props.size ?? PathBarSize.Small;
		semantics = {role: Navigation, label: props.label ?? "Path"};
		if (Graph.use(Look.context) == null) theme = Look.base.sheet();

		row.style.set({flexDirection: Row, alignItems: Center, width: "100%", minWidth: 0});
		append(row);
		overflow = button("overflow", "Hidden folders", showOverflow);
		overflow.append(caption("…"));
		overflowSeparator = chevron(null, null);
		actions("pathbar", PathBarAction);
		on(PathBarAction, a -> switch a {
			case Navigate(i):
				props.onNavigate(i);
				true;
		});

		if (canEdit) onClick = e -> {
			if (e.button == 1 && (e.target == this || e.target == row)) editing(true);
		};
	}

	public function bind() {
		// (make the presses in the computation's owner, then put their nodes in the row)
		Graph.renderEffect(() -> {
			var segments = props.segments();
			return {labels: [for (s in segments) s.label], crumbs: [for (i in 0...segments.length) crumb(segments[i], i, i == segments.length - 1)]};
		}, data -> {
			row.removeChildren();
			labels = data.labels;
			crumbs = data.crumbs;
			for (i in 0...crumbs.length) {
				// (the menu belongs between the first segment and the rest)
				if (i == 1) {
					row.append(overflow);
					row.append(overflowSeparator);
				}
				var c = crumbs[i];
				row.append(c.segment);
				if (c.separator != null) row.append(c.separator);
			}
			fittedWidth = -1;
		});
		if (canEdit) Graph.renderEffect(() -> editing(), on -> {
			if (on) startEditing() else stopEditing();
		});
	}

	function crumb(s:PathSegment, index:Int, last:Bool):Crumb {
		var n = last ? new Node("pathbar-current") : button("segment", s.label, _ -> props.onNavigate(index), true);
		var label = caption(s.label);
		if (last) {
			n.slot = "pathbar-current";
			n.semantics = {role: Label, label: s.label, current: true};
			label.semantics = {hidden: true};
			label.style.minWidth = 0;
			label.style.textOverflow = Ellipsis;
			if (canEdit) {
				n.style.cursor = Text;
				n.onClick = e -> if (e.button == 1) editing(true);
			}
		}
		if (s.icon != null) {
			var icon = new ImageNode();
			icon.slot = "pathbar-segment-icon";
			icon.svg = s.icon;
			n.append(icon);
		}
		n.append(label);
		return {segment: n, separator: last ? null : chevron(s.label, props.onSeparator == null ? null : anchor -> props.onSeparator(index, anchor))};
	}

	static function caption(text:String):TextNode {
		var n = new TextNode(text);
		n.style.textWrap = NoWrap;
		n.style.lineClamp = 1;
		return n;
	}

	static function button(part:String, label:String, activate:Node->Void, link = false):Node {
		var slot = 'pathbar-$part', n = new Node(slot);
		var p = new Press(slot, null, () -> activate(n));
		p.label = label;
		if (link) {
			@:privateAccess p.role = Link;
			// (links normally take Enter alone; a path segment takes Space too)
			n.onKeyDown = e -> if (e.key == Key.SPACE) {
				e.preventDefault();
				p.press();
			};
		}
		p.root(n);
		return n;
	}

	static function chevron(label:Null<String>, activate:Null<Node->Void>):Node {
		var n = activate == null ? new Node("pathbar-separator") : button("separator", 'Children of $label', activate);
		n.slot = "pathbar-separator";
		if (activate != null) n.style.cursor = Pointer;
		var icon = new ImageNode();
		icon.svg = Icons.svg("chevron-right");
		icon.style.set({width: 11, height: 11, flexShrink: 0});
		icon.mirrored = true;
		n.append(icon);
		return n;
	}

	function showOverflow(anchor:Node) {
		var items:Array<MenuItem> = [for (i in firstHidden...endHidden) Item(labels[i], Navigate(i))];
		if (items.length == 0 || anchor.ui == null) return;
		var b = anchor.windowBounds();
		Menus.popup(anchor.ui, items, b.x, b.y + b.height, anchor);
	}

	function startEditing() {
		var f = new TextField(props.text == null ? labels.join("/") : props.text.peek());
		field = f;
		f.slot = "pathbar-field";
		f.semantics.label = semantics.label;
		f.onSubmit = text -> {
			editing(false);
			props.onSubmit(text);
		};
		var key = f.onKeyDown, blur = f.onBlur;
		f.onKeyDown = e -> {
			if (e.key == Key.ESCAPE) {
				e.preventDefault();
				e.stop();
				editing(false);
			} else key(e);
		};
		f.onBlur = e -> {
			blur(e);
			if (field == f) editing(false);
		};
		row.style.display = None;
		append(f);
		if (ui != null) ui.setFocus(f, false);
		f.selectAll();
	}

	function stopEditing() {
		var f = field;
		if (f == null) return;
		field = null;
		if (ui != null && ui.focus == f) ui.setFocus(null);
		remove(f);
		row.style.display = Flex;
	}

	override function attach(u:Null<Ui>) {
		if (ui != null && ui != u) ui.settlers.remove(this);
		super.attach(u);
		if (u != null && u.settlers.indexOf(this) < 0) u.settlers.push(this);
	}

	// (after styles and layout, before drawing: measure the uncut labels,
	// then hide one run of segments. The current segment alone can shrink)
	override function settle():Bool {
		if (ui == null || field != null || crumbs.length < 2) return false;
		var w = row.width, g = ui.text.generation();
		if (w == fittedWidth && g == generation) return false;
		fittedWidth = w;
		generation = g;
		var last = crumbs.length - 1, total = 0.0;
		var widths = [for (c in crumbs) {
			var width = naturalWidth(c.segment) + (c.separator == null ? 0 : naturalWidth(c.separator));
			total += width;
			width;
		}];
		firstHidden = endHidden = 0;
		if (total > w) {
			total += naturalWidth(overflow) + naturalWidth(overflowSeparator);
			firstHidden = 1;
			endHidden = 1;
			while (endHidden < last && total > w) total -= widths[endHidden++];
			if (total > w) firstHidden = 0;
		}
		var hidden = endHidden > firstHidden;
		var changed = show(overflow, hidden);
		if (show(overflowSeparator, hidden)) changed = true;
		for (i in 0...crumbs.length) {
			var c = crumbs[i], visible = i < firstHidden || i >= endHidden;
			if (show(c.segment, visible)) changed = true;
			if (c.separator != null && show(c.separator, visible)) changed = true;
		}
		return changed;
	}

	function show(n:Node, visible:Bool):Bool {
		var display:Display = visible ? Flex : None;
		if (n.style.display == display) return false;
		n.style.display = display;
		if (!visible && ui.focus == n) ui.setFocus(overflow.style.display == None ? null : overflow, false);
		return true;
	}

	// (the border box of a part at its full width, even while it is hidden)
	function naturalWidth(n:Node):Float {
		var s = n.style, given = s.width.resolve(fittedWidth);
		var w = s.padding.left + s.padding.right + s.borderEdges.left + s.borderEdges.right;
		if (!Math.isNaN(given)) return Math.max(given, w);
		if (n is TextNode) return w + n.minContentWidth(ui.text);
		for (i in 0...n.children.length)
			w += naturalWidth(n.children[i]) + (i == 0 ? 0 : s.columnGap);
		return w;
	}
}
