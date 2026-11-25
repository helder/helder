package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.gesture.LongPress;
import helder.view.Render;
import helder.view.graph.Graph;

// The viewer on a phone (390 by 844) and a tablet (820 by 1180), headless
// and touched: Browse's places, a folder pushed and popped (the browser
// following), a folder pushed at its top and the one under it where it
// was when popped back to, a subfolder, a file full size and back, a swipe to the
// next; select mode's taps and toolbar; a long press's menu and its Get
// Info sheet; the tablet's drawer and its inspector's popover
function tests() {
	describe("Viewer on a phone", () -> {
		var t = 0.0;
		function settle(ui:Ui) {
			Graph.flush();
			Clock.finish();
			ui.update();
			Graph.flush();
			ui.update();
		}
		// (the stack's top screen)
		function top(ui:Ui):Node {
			var stack = ui.root.find("stack");
			var shown = [for (n in stack.children) if (n.tag == "screen" && n.visible()) n];
			return shown[shown.length - 1];
		}
		function mount(w:Float, h:Float):{ui:Ui, x:Explorer} {
			t = 0;
			Ui.now = () -> t;
			var x = Fixtures.explorer(["tests/fixtures/folder", "tests/fixtures/pdf", "tests/fixtures/scripts"]);
			x.sidebar.add({kind: Pictures, name: "Fixtures", path: "tests/fixtures"});
			var ui = new Ui(new StoryText(), w, h);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			settle(ui);
			return {ui: ui, x: x};
		}
		function find(ui:Ui, tag:String):Node {
			var n = ui.overlay.find(tag) ?? top(ui).find(tag);
			if (n == null) throw 'no $tag';
			return n;
		}
		function press(ui:Ui, n:Node, hold = 0.0) {
			var b = n.windowBounds(), px = b.x + b.width / 2, py = b.y + b.height / 2;
			ui.pointerDown(px, py, 1, 1, Touch);
			if (hold > 0) {
				t += hold;
				Clock.tick(Clock.now + hold);
			}
			t += 0.05;
			ui.pointerUp(px, py, 1, 1);
			settle(ui);
		}
		function text(n:Null<Node>):String
			return n == null ? "" : Std.isOfType(n, TextNode) ? (cast n : TextNode).text : [for (c in n.children) text(c)].join("");
		test("Browse, a folder pushed and popped, a file full size and back", () -> {
			var m = mount(390, 844), ui = m.ui, x = m.x;
			assert(ui.root.find("phone") != null, "the phone's shell");
			equals(text(top(ui).find("nav-title")), "Browse");
			press(ui, find(ui, "place-Fixtures"));
			equals(x.browser.dir.value, "tests/fixtures");
			equals(text(top(ui).find("nav-title")), "Fixtures");
			equals(text(top(ui).find("nav-back")), "Browse");
			// (the grid's first row under the large title and the search field)
			var title = top(ui).find("search");
			assert(top(ui).find("tile-folder").windowBounds().y > title.windowBounds().y + title.height, "the grid under the header");
			press(ui, find(ui, "tile-folder"));
			equals(x.browser.dir.value, "tests/fixtures/folder");
			equals(text(top(ui).find("nav-back")), "Fixtures");
			// (a photo: full size, the stack's top)
			press(ui, find(ui, "tile-alpha.png"));
			equals(x.full.value, true);
			assert(top(ui).find("full-stage") != null, "the full view");
			equals(x.viewer.folder.name, "alpha.png");
			// (swiped left: the next)
			var s = find(ui, "full-stage").windowBounds();
			ui.pointerDown(300, 400, 1, 1, Touch);
			for (k in 1...6) {
				t += 0.016;
				ui.pointerMove(300 - k * 40, 400, 1);
			}
			ui.pointerUp(100, 400, 1, 1);
			settle(ui);
			equals(x.viewer.folder.name, "anim.gif");
			// (back: the folder, the file shown last selected)
			press(ui, find(ui, "nav-back"));
			equals(x.full.value, false);
			equals(x.browser.selected.value, "anim.gif");
			press(ui, find(ui, "nav-back"));
			equals(x.browser.dir.value, "tests/fixtures");
			equals(x.recent.value, ["tests/fixtures/folder/alpha.png"]);
		});
		test("a folder pushed shows its top; popped back to, the one under it where it was", () -> {
			t = 0;
			Ui.now = () -> t;
			Kinds.utc = true;
			Tiles.forget();
			var files = new MemoryFiles();
			files.add("/home/");
			files.add("/home/big/");
			files.add("/home/big/sub/");
			for (i in 0...300) {
				files.add('/home/big/file $i.txt', haxe.io.Bytes.ofString("x"));
				files.add('/home/big/sub/inner $i.txt', haxe.io.Bytes.ofString("x"));
			}
			var x = new Explorer(files, (_, _, _) -> {}, [{kind: Pictures, name: "Big", path: "/home/big"}], [], (_, _) -> () -> {});
			var p:Null<Phone.PhoneState> = null;
			var ui = new Ui(new StoryText(), 390, 844);
			Render.render(Fixtures.phone(x, s -> p = s), ui.root);
			settle(ui);
			press(ui, find(ui, "place-Big"));
			equals(x.browser.dir.value, "/home/big");
			var grid = top(ui).find("grid");
			equals(grid.scrollY, 0.0);
			grid.scrollY = 3000;
			settle(ui);
			var was = grid.scrollY;
			assert(was > 2000, 'scrolled: $was');
			p.open("sub");
			settle(ui);
			equals(x.browser.dir.value, "/home/big/sub");
			equals(top(ui).find("grid").scrollY, 0.0);
			// (popped: the folder read again, as a disk would, a frame later)
			files.hold = true;
			press(ui, find(ui, "nav-back"));
			equals(x.browser.dir.value, "/home/big");
			equals(grid.scrollY, was);
			files.release();
			settle(ui);
			equals(top(ui).find("grid") == grid, true);
			equals(grid.scrollY, was);
		});
		test("select mode: taps toggle, the toolbar acts on them", () -> {
			var m = mount(390, 844), ui = m.ui, x = m.x;
			press(ui, find(ui, "place-Fixtures"));
			press(ui, find(ui, "tile-folder"));
			press(ui, find(ui, "select"));
			equals(text(top(ui).find("nav-title")), "Select Items");
			assert(top(ui).find("tools") != null && top(ui).find("tabs") == null, "the toolbar for the tabs");
			press(ui, find(ui, "tile-alpha.png"));
			press(ui, find(ui, "tile-lossy.webp"));
			equals(x.browser.picked(), ["alpha.png", "lossy.webp"]);
			equals(text(top(ui).find("nav-title")), "2 Selected");
			equals(x.full.value, false);
			press(ui, find(ui, "info"));
			assert(ui.overlay.find("sheet") != null, "the inspector's sheet");
			equals(text(ui.overlay.find("inspector-name")), "2 items");
			// (the scrim: the sheet closed, slid away)
			ui.pointerDown(195, 100, 1, 1, Touch);
			ui.pointerUp(195, 100, 1, 1);
			settle(ui);
			equals(ui.overlay.find("sheet"), null);
			press(ui, find(ui, "done"));
			assert(top(ui).find("tabs") != null, "the tabs again");
		});
		test("a long press: the menu, Get Info's sheet", () -> {
			var m = mount(390, 844), ui = m.ui, x = m.x;
			press(ui, find(ui, "place-Fixtures"));
			press(ui, find(ui, "tile-folder"));
			press(ui, find(ui, "tile-photo 2.jpg"), LongPress.DURATION + 0.1);
			equals(x.full.value, false);
			var menu = ui.overlay.find("touch-menu");
			equals([for (n in menu.children) n.slot == "touch-menu-separator" ? "-" : text(n)], ["Open", "Get Info", "Copy", "Select", "-", ViewerActions.trashLabel()]);
			press(ui, ui.overlay.find("menu-Get Info"));
			equals(x.browser.selected.value, "photo 2.jpg");
			equals(text(ui.overlay.find("inspector-name")), "photo 2.jpg");
		});
	});
	describe("Viewer on a tablet", () -> {
		test("the toolbar's sidebar and Get Info: a drawer, a popover; no path bar", () -> {
			Ui.now = () -> 0.0;
			var x = Fixtures.explorer();
			var ui = new Ui(new StoryText(), 820, 1180);
			Render.render(Shell.view(x), ui.root);
			x.start("tests/fixtures/folder");
			Graph.flush();
			ui.update();
			assert(ui.root.find("phone") == null && ui.root.find("toolbar") != null, "the desktop's toolbar");
			equals(ui.root.find("sidebar"), null);
			equals(ui.root.find("pathbar"), null);
			equals(ui.root.find("inspector"), null);
			function click(tag:String) {
				var b = ui.root.find(tag).windowBounds();
				ui.pointerDown(b.x + b.width / 2, b.y + b.height / 2, 1, 1, Touch);
				ui.pointerUp(b.x + b.width / 2, b.y + b.height / 2, 1, 1);
				Graph.flush();
				Clock.finish();
				ui.update();
			}
			click("sidebar-toggle");
			assert(ui.root.find("drawer") != null && ui.root.find("sidebar") != null, "the drawer");
			click("drawer-scrim");
			equals(ui.root.find("drawer"), null);
			x.browser.select("photo 2.jpg");
			click("info-toggle");
			assert(ui.overlay.find("sheet-popover") != null, "the inspector's popover");
			equals(x.infoOpen.value, true);
		});
	});
}
