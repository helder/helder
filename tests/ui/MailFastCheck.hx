import helder.os.*;
import helder.ui.*;
import helder.view.*;
import MailFast.MailFastAction;

// The mail client on fast nodes (examples/mail-fast/MailFast.hx) driven
// headless (the fast-probe lane): a folder chosen, a message selected by a
// press and by Up and Down in the focused list, a column sorted, the
// search typed into, Archive and its Undo, the E shortcut through the
// keymap, dark mode; then the accessibility tree against helder.ui
// mail's.
class MailFastCheck {
	static inline var W = 860;
	static inline var H = 560;
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('MailFastCheck: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		MailFast.declare();
		helder.ui.actions.Keymap.global.bind("e", MailFastAction.Archive);
		var ui = new Ui(helder.ui.TextEngines.standard(), W, H);
		var app = new MailFast();
		Render.render(app.window(), ui.root);
		helder.view.graph.Graph.flush();
		ui.update();
		var tree:helder.ui.fast.Tree = cast ui.root.children[0];
		function all(tag:String):Array<helder.ui.fast.Node> {
			var out = [], stack = [tree.root];
			while (stack.length > 0) {
				var n = stack.shift();
				if (n.tag == tag && !@:privateAccess n.box.style.none) out.push(n);
				for (c in n.children()) stack.push(c);
			}
			return out;
		}
		function find(tag:String):helder.ui.fast.Node {
			var a = all(tag);
			if (a.length == 0) throw 'MailFastCheck: no $tag';
			return a[0];
		}
		function settle() {
			helder.view.graph.Graph.flush();
			ui.update();
		}
		function click(n:helder.ui.fast.Node) {
			var r = tree.rectOf(n), x = r[0] + Math.min(20, r[2] / 2), y = r[1] + r[3] / 2;
			ui.pointerMove(x, y);
			ui.pointerDown(x, y, 1);
			ui.pointerUp(x, y, 1);
			settle();
		}
		function key(k:Int, mods = 0) {
			ui.keyDown(k, mods);
			settle();
		}
		var search = find("search");
		check("the search's placeholder in its module's muted colour", @:privateAccess search.box.style.text.colour == 0xFF71717A,
			StringTools.hex(@:privateAccess search.box.style.text.colour));
		var list = find("list");
		var rows = () -> [for (r in list.children()) if (!@:privateAccess r.box.style.none) r];
		check("the inbox's seven messages", rows().length == 7, '${rows().length}');
		click(rows()[1]);
		check("a press selects a message", app.selected() != null && app.selected().subject == "Compiler meeting moved", app.selected()?.subject);
		check("its row in the selected state", bg(rows()[1]) == 0xFFDBEAFE, StringTools.hex(bg(rows()[1])));
		var subject:helder.ui.fast.TextNode = cast find("reader-subject");
		check("the reader shows it", subject.text == "Compiler meeting moved", subject.text);
		check("the press focused the list", @:privateAccess tree.active == list);
		key(Key.DOWN);
		check("Down: the next message", app.selected()?.subject == "Re: patch for the scheduler", app.selected()?.subject);
		key(Key.UP);
		key(Key.UP);
		check("Up twice: the first", app.selected()?.subject == "Draft of the layout chapter", app.selected()?.subject);
		click(find("sort-from"));
		var first:helder.ui.fast.TextNode = cast rows()[0].children()[0];
		check("sorted by sender", first.text == "Ada" && app.sort().by == "from", first.text);
		click(find("sort-date"));
		// (the search: typed into, the list filtered)
		click(find("search"));
		for (c in new haxe.iterators.StringIteratorUnicode("lunch")) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		settle();
		check("the search filters", rows().length == 1 && app.query() == "lunch", '${rows().length} "${app.query()}"');
		key(Key.BACKSPACE, Mods.CONTROL);
		check("a word deleted: all again", app.query() == "" && rows().length == 7, '"${app.query()}" ${rows().length}');
		// (Archive, the undo line, Undo)
		click(rows()[0]);
		var archived = app.selected();
		click(find("archive"));
		check("Archive moves it", archived.folder() == "Archive" && rows().length == 6, '${archived.folder()} ${rows().length}');
		check("the undo line shows", all("undo").length == 1);
		click(find("undo"));
		check("Undo brings it back", archived.folder() == "Inbox" && rows().length == 7, '${archived.folder()} ${rows().length}');
		// (the shortcut: E with the list focused, its actions the <Fast>'s)
		click(rows()[0]);
		var shortcut = app.selected();
		key("e".code);
		check("E archives through the keymap", shortcut.folder() == "Archive", shortcut.folder());
		// (and typed in the search field, an e is text)
		click(find("search"));
		ui.keyDown("e".code, 0);
		ui.textInput("e");
		settle();
		check("in the field an e is typed", app.query() == "e" && app.undo() != null, '"${app.query()}"');
		key(Key.BACKSPACE);
		// (a folder chosen)
		click(all("button").filter(b -> (cast b.children()[0] : helder.ui.fast.TextNode).text == "Travel")[0]);
		check("a folder chosen: its messages", app.folder().name == "Travel" && rows().length == 2, '${app.folder().name} ${rows().length}');
		click(all("button").filter(b -> (cast b.children()[0] : helder.ui.fast.TextNode).text == "Inbox")[0]);
		// (dark mode: the theme's other tone)
		var body = tree.root.children()[0], light = bg(body);
		click(find("dark"));
		check("dark mode: the body's background its dark token", light == 0xFFFFFFFF && bg(body) == 0xFF09090B, StringTools.hex(bg(body)));
		click(find("dark"));
		// (assistive technology: helder.ui mail's tree, in the same state)
		var mine = access(ui);
		Mail.declare();
		var other = new Ui(helder.ui.TextEngines.standard(), W, H);
		other.theme = Mail.sheet;
		var ref = new Mail();
		for (k in 0...ref.messages.peek().length) {
			var a = app.messages.peek()[k], b = ref.messages.peek()[k];
			b.folder(a.folder.peek());
			b.unread(a.unread.peek());
		}
		ref.undo(app.undo.peek() == null ? null : {text: app.undo.peek().text, run: () -> {}});
		Render.render(ref.view(), other.root);
		settle();
		other.update();
		var theirs = access(other);
		Sys.println("MailFastCheck: access " + mine.length + " nodes");
		check("the accessibility tree is helder.ui mail's", mine.join("\n") == theirs.join("\n"), diff(mine, theirs));
		Sys.println('MailFastCheck: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function bg(n:helder.ui.fast.Node):Int
		return @:privateAccess n.box.style.backgroundColor;

	static function access(ui:Ui):Array<String> {
		var t = ui.accessTree();
		return [
			for (id in t.order) {
				var a = t.nodes.get(id);
				if (id == t.root || a.role == Group && !a.focusable || a.role == ScrollView) continue;
				'${a.role}:${a.name}' + (a.selected == null ? "" : a.selected ? "[sel]" : "") + (a.checked == null ? "" : a.checked ? "[x]" : "[ ]");
			}
		];
	}

	// (where two lists first part)
	static function diff(a:Array<String>, b:Array<String>):String {
		var i = 0;
		while (i < a.length && i < b.length && a[i] == b[i]) i++;
		return 'at $i: fast ${a.slice(i, i + 4).join(", ")} | ui ${b.slice(i, i + 4).join(", ")}';
	}
}
