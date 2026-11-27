import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.fast.*;
import helder.view.*;

// A todo-shaped app of fast nodes (the ui lane's fast-probe): a title, an
// entry row, a list of rows with checkboxes and delete buttons, a footer;
// hover, pressed and checked as state variants, colours from a theme. Built
// with -dce full and symbols, it links no helder.dom and no cascade,
// matcher or CSS parser; with -D fast.island, a DocumentNode beside it
// does (the check's control). `layout` lays it out and prints, else a window.
class FastProbe implements Markup {
	static final app = new Theme(["fg" => [0xFF18181B, 0xFFFAFAFA], "muted" => [0xFF71717A, 0xFFA1A1AA], "line" => [0xFFE4E4E7, 0xFF3F3F46],
		"surface" => [0xFFFFFFFF, 0xFF18181B], "hover" => [0xFFF4F4F5, 0xFF27272A]]);

	static final page = Style.of({padding: 24, rowGap: 12, background: Theme.token("surface"), color: Theme.token("fg")});
	static final title = Style.of({fontSize: 28, fontWeight: 600});
	static final entry = Style.of({flexDirection: Row, columnGap: 8});
	static final input = Style.of({flexGrow: 1, padding: [8, 12], borderRadius: 6, borderWidth: 1, borderColor: Theme.token("line"), color: Theme.token("muted")});
	static final button = Style.of({flexDirection: Row, alignItems: Center, justifyContent: Center, padding: [6, 12], borderRadius: 6, background: 0xFF18181B,
		color: 0xFFFAFAFA, hover: {background: 0xFF3F3F46}, pressed: {opacity: 0.8}});
	static final ghost = button.with({background: 0, color: Theme.token("muted"), padding: [4, 8], hover: {background: Theme.token("hover"), color: Theme.token("fg")}});
	static final row = Style.of({flexDirection: Row, alignItems: Center, columnGap: 8, padding: [4, 6], borderRadius: 6, hover: {background: Theme.token("hover")}});
	static final check = Style.of({width: 16, height: 16, borderRadius: 4, borderWidth: 1, borderColor: 0xFFA1A1AA, checked: {background: 0xFF18181B, borderColor: 0xFF18181B}});
	static final label = Style.of({flexGrow: 1, group: {checked: {color: Theme.token("muted")}}});
	static final footer = Style.of({color: Theme.token("muted"), fontSize: 12});

	final list = new Node(Style.of({rowGap: 2}));
	final left = new TextNode("", footer);

	function new() {}

	function view():Node {
		var root = new Node(page);
		root.append(new TextNode("todos", title));
		var bar = new Node(entry), add = new Node(button);
		bar.append(new TextNode("What needs to be done?", input));
		add.append(new TextNode("Add"));
		add.onPress = () -> item('Task ${list.children().length + 1}');
		bar.append(add);
		root.append(bar);
		root.append(list);
		root.append(left);
		for (t in ["Write the docs", "Ship it", "Measure the fast nodes"]) item(t);
		return root;
	}

	function item(text:String) {
		var r = new Node(row), box = new Node(check), x = new Node(ghost);
		r.group = true;
		box.onPress = () -> {
			r.state(Style.CHECKED, !r.has(Style.CHECKED));
			box.state(Style.CHECKED, r.has(Style.CHECKED));
			count();
		}
		x.append(new TextNode("×"));
		x.onPress = () -> {
			r.remove();
			count();
		}
		r.append(box);
		r.append(new TextNode(text, label));
		r.append(x);
		list.append(r);
		count();
	}

	function count() {
		var n = [for (r in list.children()) if (!r.has(Style.CHECKED)) r].length;
		left.text = '$n item${n == 1 ? "" : "s"} left';
	}

	static function main() {
		var probe = new FastProbe(), tree = new Tree(probe.view(), app);
		if (Sys.args()[0] == "layout") {
			var space = new helder.ui.flow.Space(new helder.ui.box.Fragments(), tree.fonts, 480, 560);
			var root = @:privateAccess tree.root.box, f = @:privateAccess space.fragments;
			var id = (root.context ?? @:privateAccess Node.contexts().flow).layout(root, space);
			Sys.println('laid out ${f.width(id)}x${Math.round(f.height(id))} ${probe.list.children().length} rows ${probe.left.text}');
			return;
		}
		#if fast.island
		var doc = helder.dom.Dom.parse("<!doctype html><p>An island");
		UiWindow.run(<Surface title="Fast" width={480} height={560}><view flexGrow={1}>{tree}{helder.ui.box.DocumentNode.html(doc)}</view></Surface>);
		#else
		UiWindow.run(<Surface title="Fast" width={480} height={560}><view flexGrow={1}>{tree}</view></Surface>);
		#end
	}
}
