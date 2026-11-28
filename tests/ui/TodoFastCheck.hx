import helder.os.*;
import helder.ui.*;
import helder.ui.access.AccessTree;
import helder.ui.fast.FastTags.*;
import helder.view.*;

// The todo on fast nodes (examples/todo-fast/TodoFast.hx) driven headless
// through its Ui, as TodoCheck drives helder.ui's (the fast-probe lane):
// the field focused by a press and by Tab, typed into, its selection and
// keys; Enter, the buttons pressed by the pointer, Space and Enter; Tab's
// order; hover; text selected by a drag and copied; then the accessibility
// tree against helder.ui todo's with the same items.
class TodoFastCheck implements Markup {
	static inline var W = 420;
	static inline var H = 480;
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TodoFastCheck: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H);
		var app = new TodoFast(), tree:Null<helder.ui.fast.Tree> = null;
		Render.render(<Fast ref={t -> tree = t}>{app.view()}</Fast>, ui.root);
		ui.update();
		function find(tag:String, ?within:helder.ui.fast.Node):helder.ui.fast.Node {
			var stack = [within ?? tree.root];
			while (stack.length > 0) {
				var n = stack.shift();
				if (n.tag == tag) return n;
				for (c in n.children()) stack.push(c);
			}
			throw 'TodoFastCheck: no $tag';
		}
		function at(n:helder.ui.fast.Node):Array<Float> {
			var r = tree.rectOf(n);
			return [r[0] + r[2] / 2, r[1] + r[3] / 2];
		}
		function click(n:helder.ui.fast.Node) {
			var p = at(n);
			ui.pointerMove(p[0], p[1]);
			ui.pointerDown(p[0], p[1], 1);
			ui.pointerUp(p[0], p[1], 1);
			helder.view.graph.Graph.flush();
			ui.update();
		}
		function key(k:Int, mods = 0) {
			ui.keyDown(k, mods);
			helder.view.graph.Graph.flush();
			ui.update();
		}
		function type(s:String) {
			for (c in new haxe.iterators.StringIteratorUnicode(s)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
			helder.view.graph.Graph.flush();
			ui.update();
		}
		var focused = () -> @:privateAccess tree.active;
		var draft = find("draft");
		click(draft);
		check("a press focuses the field", ui.focus == tree && focused() == draft);
		type("Buy milk");
		check("typing edits the draft", app.draft() == "Buy milk", app.draft());
		key(Key.ENTER);
		check("Enter adds it", app.todos().length == 1 && app.draft() == "" && (cast draft : helder.ui.fast.FieldNode).value == "");
		type("Write the renderer");
		key(Key.LEFT, Mods.SHIFT);
		key(Key.LEFT, Mods.SHIFT);
		type("ER");
		check("a selection is replaced", app.draft() == "Write the renderER", app.draft());
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		type("er");
		key(Key.LEFT, Mods.META);
		type(">");
		check("Command+Left: the start", app.draft() == ">Write the renderer", app.draft());
		key(Key.BACKSPACE);
		key(Key.DELETE);
		check("Backspace before the caret, Delete after it", app.draft() == "rite the renderer", app.draft());
		type("W");
		click(find("add"));
		check("Add adds", app.todos().length == 2 && app.todos()[1].title == "Write the renderer", [for (t in app.todos()) t.title].join("|"));
		// (Tab: the field, Add, then each row's checkbox and Remove, then the filters)
		click(draft);
		type("Ship it");
		key(Key.TAB);
		check("Tab: the field to Add", focused() == find("add"), focused()?.tag);
		key(Key.ENTER);
		check("Enter presses Add", app.todos().length == 3, '${app.todos().length}');
		key(Key.TAB);
		check("Tab: Add to the first checkbox", focused()?.tag == "checkbox", focused()?.tag);
		key(Key.SPACE);
		check("Space presses the checkbox", app.todos()[0].done());
		check("its checked state is styled", bg(focused()) == 0xFF18181B, StringTools.hex(bg(focused())));
		key(Key.TAB, Mods.SHIFT);
		check("Shift+Tab: back to Add", focused() == find("add"), focused()?.tag);
		var left:helder.ui.fast.TextNode = cast find("left");
		check("the count follows", left.text == "2 items left", left.text);
		// (past the last stop: round again, the window's only stop)
		click(find("filter-done"));
		key(Key.TAB);
		check("Tab past the last stop: the first", focused() == draft, focused()?.tag);
		click(find("filter-all"));
		// (hover: a button's variant)
		var add = find("add"), p = at(add);
		ui.pointerMove(p[0], p[1]);
		ui.update();
		check("hover restyles Add", bg(add) == 0xFF3F3F46, StringTools.hex(bg(add)));
		ui.pointerMove(1, H - 1);
		ui.update();
		check("and back", bg(add) == 0xFF18181B, StringTools.hex(bg(add)));
		// (text selected by a drag over the title: copied)
		var title = tree.rectOf(tree.root.children()[0].children()[0]);
		ui.pointerMove(title[0] + 1, title[1] + title[3] / 2);
		ui.pointerDown(title[0] + 1, title[1] + title[3] / 2, 1);
		ui.pointerMove(title[0] + title[2] - 1, title[1] + title[3] / 2);
		ui.pointerUp(title[0] + title[2] - 1, title[1] + title[3] / 2, 1);
		ui.update();
		check("a drag selects the title's text", ui.selectedText() == "todos", '"${ui.selectedText()}"');
		// (a press on a button selects nothing)
		click(find("filter-all"));
		check("a press on a button selects nothing", ui.selectedText() == "", '"${ui.selectedText()}"');
		var rm = [for (r in find("list").children()) if (!@:privateAccess r.box.style.none) r];
		click(find("button", rm[rm.length - 1]));
		check("Remove removes", app.todos().length == 2, '${app.todos().length}');
		// (a long list scrolled to its end: its last row drawn and hit there, its Remove's hover)
		app.todos(app.todos().concat([for (i in 0...200) new TodoFast.Task('Row $i')]));
		helder.view.graph.Graph.flush();
		ui.update();
		var list = find("list"), lr = tree.rectOf(list);
		for (_ in 0...200) ui.wheel(lr[0] + lr[2] / 2, lr[1] + lr[3] / 2, 0, 400);
		ui.update();
		var rows = [for (r in list.children()) if (!@:privateAccess r.box.style.none) r], last = rows[rows.length - 1];
		var q = tree.rectOf(find("button", last));
		check("scrolled to its end, the last row is in view", q[1] >= lr[1] && q[1] + q[3] <= lr[1] + lr[3], '${q[1]} in ${lr[1]}..${lr[1] + lr[3]}');
		ui.pointerMove(q[0] + q[2] / 2, q[1] + q[3] / 2);
		ui.update();
		check("and hit there: its Remove hovered", bg(find("button", last)) == 0xFFF4F4F5, StringTools.hex(bg(find("button", last))));
		click(find("button", last));
		check("and pressed", app.todos().length == 201, '${app.todos().length}');
		app.todos(app.todos().slice(0, 2));
		helder.view.graph.Graph.flush();
		ui.update();
		// (assistive technology: the same tree as helder.ui todo's with the same items)
		var mine = access(ui);
		var other = new Ui(helder.ui.TextEngines.standard(), W, H);
		other.theme = Todo.sheet;
		var ref = new Todo();
		var items:Array<Todo.Item> = [];
		for (t in app.todos()) {
			var i = new Todo.Item(t.title);
			i.done(t.done());
			items.push(i);
		}
		ref.todos(items);
		Render.render(ref.view(), other.root);
		helder.view.graph.Graph.flush();
		other.update();
		var theirs = access(other);
		Sys.println("TodoFastCheck: access " + mine.join(", "));
		check("the accessibility tree is helder.ui todo's", mine.join("\n") == theirs.join("\n"), '\n  fast:  ${mine.join(", ")}\n  ui:    ${theirs.join(", ")}');
		Sys.println('TodoFastCheck: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function bg(n:helder.ui.fast.Node):Int
		return @:privateAccess n.box.style.backgroundColor;

	// (its nodes in order: role, name, checked, as AccessKit's adapters read them)
	static function access(ui:Ui):Array<String> {
		var t = ui.accessTree();
		return [
			for (id in t.order) {
				var a = t.nodes.get(id);
				if (id == t.root || a.role == Group || a.role == ScrollView) continue;
				'${a.role}:${a.name}' + (a.checked == null ? "" : a.checked ? "[x]" : "[ ]");
			}
		];
	}
}
