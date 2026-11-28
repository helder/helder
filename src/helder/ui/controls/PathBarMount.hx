package helder.ui.controls;

import helder.ui.*;
import helder.ui.actions.Actions.actions;
import helder.ui.box.Len.Lens;
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
	final options:PathBarProps;
	final controls:Look<Dynamic>;
	final size:String;
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

	public function new(options:PathBarProps) {
		super(options.tag ?? "pathbar");
		this.options = options;
		canEdit = options.editable != false;
		editing = options.editing ?? Graph.signal(false);
		controls = Look.current();
		size = options.size ?? PathBarSize.Small;
		style = piece("root");
		semantics = {role: Navigation, label: options.label ?? "Path"};
		if (Look.outside()) theme = controls.theme;

		row.style = Style.of({flexDirection: Row, alignItems: Center, width: "100%", minWidth: 0});
		append(row);
		overflow = button("overflow", "Hidden folders", showOverflow);
		overflow.append(caption("…"));
		overflowSeparator = chevron(null, null);
		actions("pathbar", PathBarAction);
		on(PathBarAction, a -> switch a {
			case Navigate(i):
				options.onNavigate(i);
				true;
		});

		if (canEdit) onClick = e -> {
			if (e.button == 1 && (e.target == this || e.target == row)) editing(true);
		};
	}

	public function bind() {
		// (make the presses in the computation's owner, then put their nodes in the row)
		Graph.renderEffect(() -> {
			var segments = options.segments();
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

	// (a part's style in the bar's size)
	function piece(part:String):Style
		return controls.style("pathbar", null, size, part);

	function crumb(s:PathSegment, index:Int, last:Bool):Crumb {
		var n = last ? new Node("pathbar-current") : button("segment", s.label, _ -> options.onNavigate(index), true);
		var label = caption(s.label);
		if (last) {
			n.style = piece("current");
			n.semantics = {role: Label, label: s.label, current: true};
			label.semantics = {hidden: true};
			label.style = label.style.with({minWidth: 0, textOverflow: Ellipsis});
			if (canEdit) {
				n.style = n.style.with({cursor: Text});
				n.onClick = e -> if (e.button == 1) editing(true);
			}
		}
		if (s.icon != null) {
			var icon = new ImageNode();
			icon.style = piece("segmentIcon");
			icon.svg = s.icon;
			n.append(icon);
		}
		n.append(label);
		return {segment: n, separator: last ? null : chevron(s.label, options.onSeparator == null ? null : anchor -> options.onSeparator(index, anchor))};
	}

	static function caption(text:String):TextNode {
		var n = new TextNode(text);
		n.style = Style.of({textWrap: NoWrap, lineClamp: 1});
		return n;
	}

	function button(part:String, label:String, activate:Node->Void, link = false):Node {
		var n = new Node('pathbar-$part');
		var p = new Press("pathbar", null, () -> activate(n));
		p.label = label;
		p.size = size;
		if (link) {
			@:privateAccess p.role = Link;
			// (links normally take Enter alone; a path segment takes Space too)
			n.onKeyDown = e -> if (e.key == Key.SPACE) {
				e.preventDefault();
				p.press();
			};
		}
		p.root(n, part);
		return n;
	}

	function chevron(label:Null<String>, activate:Null<Node->Void>):Node {
		var n = activate == null ? new Node("pathbar-separator") : button("separator", 'Children of $label', activate);
		if (activate == null) n.style = piece("separator") else n.style = n.style.with({cursor: Pointer});
		var icon = new ImageNode();
		icon.svg = Icons.svg("chevron-right");
		icon.style = Style.of({width: 11, height: 11, flexShrink: 0});
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
		var f = new TextField(options.text == null ? labels.join("/") : options.text.peek());
		field = f;
		f.style = f.style.with(piece("field"));
		f.semantics.label = semantics.label;
		f.onSubmit = text -> {
			editing(false);
			options.onSubmit(text);
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
		row.style = row.style.with({display: None});
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
		row.style = row.style.with({display: Flex});
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
		if (n.style.props.display == display) return false;
		n.style = n.style.with({display: display});
		if (!visible && ui.focus == n) ui.setFocus(overflow.used.none ? null : overflow, false);
		return true;
	}

	// (the border box of a part at its full width, even while it is hidden)
	function naturalWidth(n:Node):Float {
		var s = n.used, given = Lens.resolve(s.width, fittedWidth, Math.NaN);
		var w = s.paddingEdges.left + s.paddingEdges.right + s.borderEdges.left + s.borderEdges.right;
		if (!Math.isNaN(given)) return Math.max(given, w);
		if (n is TextNode) return w + n.minContentWidth(ui.text);
		for (i in 0...n.children.length)
			w += naturalWidth(n.children[i]) + (i == 0 ? 0 : Lens.resolve(s.columnGap, fittedWidth, 0));
		return w;
	}
}
