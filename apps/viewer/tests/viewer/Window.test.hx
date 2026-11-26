package viewer;

import helder.story.StoryText;
import helder.test.Choices;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.Node;
import helder.ui.menu.Menu.MenuItem;
import helder.ui.Ui;
import helder.view.Render;
import viewer.Files;
import viewer.ViewerActions.ViewerAction;

// The window's content within the window at desktop sizes, with a large
// folder among many: the panels and the path bar end at its bottom, the
// sidebar's level of 30 folders scrolls (its content's height pushed the
// window's content 450 points past a 488-point window's bottom once); a
// desktop window under random presses never shows the touch menu's glass
function tests() {
	describe("Window", () -> {
		function bottom(n:Null<Node>):Float
			return n == null ? -1 : n.absY + n.height;
		function big():Explorer {
			Kinds.utc(true);
			Tiles.forget();
			var m = new MemoryFiles();
			m.add("/home/");
			for (i in 0...30)
				m.add('/home/folder $i/');
			for (i in 0...300)
				m.add('/home/folder 0/file $i.txt', haxe.io.Bytes.ofString("x"));
			m.add("/home/folder 0/sub/");
			for (i in 0...300)
				m.add('/home/folder 0/sub/inner $i.txt', haxe.io.Bytes.ofString("x"));
			return new Explorer(m, (_, _, done) -> {}, [], [], (_, _) -> () -> {});
		}
		for (size in [{w: 1000, h: 488, layout: Browser.Layout.List}, {w: 1212, h: 592, layout: Browser.Layout.Grid}, {w: 1440, h: 900, layout: Browser.Layout.List}])
			test('${size.w} x ${size.h}, as a ${size.layout}: everything ends at the window\'s bottom', () -> {
				var x = big(), ui = new Ui(new StoryText(), size.w, size.h);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				x.start("/home/folder 0");
				x.browser.layout(size.layout);
				for (_ in 0...2) {
					helder.view.graph.Graph.flush();
					ui.update();
				}
				var r = ui.root, h:Float = size.h;
				equals(x.sidebar.rows().length, 30);
				for (t in ["window", "browser", "sidebar", "main", "pathbar", "inspector"])
					equals('$t ${bottom(r.find(t))}', '$t $h');
				var bar = r.find("pathbar");
				assert(bar.absY >= 0 && bar.height == ContentView.FOOT, '${bar.absY} ${bar.height}');
				var side = r.find("scroll");
				equals(bottom(side), h);
				assert(side.contentHeight > side.height, 'the sidebar scrolls: ${side.contentHeight} in ${side.height}');
			});
		for (layout in [Browser.Layout.List, Browser.Layout.Grid])
			test('a folder entered shows its top, back its old place (${layout})', () -> {
				var x = big(), ui = new Ui(new StoryText(), 1212, 592);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				function frame()
					for (_ in 0...3) {
						helder.view.graph.Graph.flush();
						ui.update();
					}
				x.start("/home/folder 0");
				x.browser.layout(layout);
				frame();
				var view = ui.root.find(layout == List ? "rows" : "grid");
				equals(view.scrollY, 0.0);
				view.scrollY = 3000;
				frame();
				var was = view.scrollY;
				assert(was > 2000, 'scrolled: $was');
				x.browser.go("/home/folder 0/sub");
				frame();
				view = ui.root.find(layout == List ? "rows" : "grid");
				equals(view.scrollY, 0.0);
				// (back: read again, as a disk would, a frame later; its offset once its items are in)
				var files:MemoryFiles = cast x.files;
				files.hold = true;
				x.browser.goBack();
				frame();
				files.release();
				frame();
				view = ui.root.find(layout == List ? "rows" : "grid");
				equals(view.scrollY, was);
			});
		for (layout in [Browser.Layout.List, Browser.Layout.Grid])
			test('a file picked at a folder\'s end, a sibling, back by the sidebar: the folder at its top (${layout})', () -> {
				var x = big(), ui = new Ui(new StoryText(), 1212, 592);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				function frame()
					for (_ in 0...3) {
						helder.view.graph.Graph.flush();
						ui.update();
					}
				x.start("/home/folder 0");
				x.browser.layout(layout);
				frame();
				var view = ui.root.find(layout == List ? "rows" : "grid");
				// (the last file pressed, as a user does at the folder's end)
				view.scrollY = 1e6;
				frame();
				var shown = [for (r in (cast view : helder.ui.VirtualScroll).rows()) if (r.node.style.display != None) r];
				var last = shown[shown.length - 1].node;
				var b = (layout == List ? last : last.children[last.children.length - 1]).windowBounds();
				ui.pointerDown(b.x + 10, b.y + 10, 1);
				ui.pointerUp(b.x + 10, b.y + 10, 1);
				frame();
				x.browser.go("/home/folder 1");
				frame();
				x.browser.go("/home/folder 0");
				frame();
				equals(ui.root.find(layout == List ? "rows" : "grid").scrollY, 0.0);
			});
		for (layout in [Browser.Layout.List, Browser.Layout.Grid])
			test('scrolled to its end, a sibling, back, the sibling again, the folder by the sidebar: at its top (${layout})', () -> {
				var x = big(), ui = new Ui(new StoryText(), 1212, 592);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				function frame()
					for (_ in 0...3) {
						helder.view.graph.Graph.flush();
						ui.update();
					}
				function view()
					return ui.root.find(layout == List ? "rows" : "grid");
				// (each folder read a frame later, as a disk answers)
				var files:MemoryFiles = cast x.files;
				function later(go:Void->Void) {
					files.hold = true;
					go();
					frame();
					files.release();
					frame();
				}
				x.start("/home/folder 0");
				x.browser.layout(layout);
				frame();
				view().scrollY = 1e6;
				frame();
				var end = view().scrollY;
				later(() -> x.browser.go("/home/folder 1"));
				later(() -> x.browser.goBack());
				equals(view().scrollY, end);
				later(() -> x.browser.go("/home/folder 1"));
				equals(view().scrollY, 0.0);
				later(() -> x.browser.go("/home/folder 0"));
				equals(view().scrollY, 0.0);
			});
		for (layout in [Browser.Layout.List, Browser.Layout.Grid])
			test('a folder read in batches, each sorting above the last, stays at its top (${layout})', () -> {
				Kinds.utc(true);
				Tiles.forget();
				var m = new Trickle();
				m.size = 50;
				m.add("/home/");
				m.add("/home/many/");
				for (i in 0...400)
					m.add('/home/many/file $i.txt', haxe.io.Bytes.ofString("x"));
				var x = new Explorer(m, (_, _, done) -> {}, [], [], (_, _) -> () -> {});
				var ui = new Ui(new StoryText(), 1212, 592);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				x.browser.layout(layout);
				x.start("/home/many");
				function frame() {
					helder.view.graph.Graph.flush();
					ui.update();
				}
				frame();
				while (m.queue.length > 0) {
					m.queue.shift()();
					frame();
				}
				frame();
				equals(x.browser.items.value.length, 400);
				equals(ui.root.find(layout == List ? "rows" : "grid").scrollY, 0.0);
			});
		test("the full-size viewer closed: the folder where it was, the last file viewed in view", () -> {
			Kinds.utc(true);
			Tiles.forget();
			var m = new MemoryFiles();
			m.add("/home/");
			m.add("/home/pics/");
			for (i in 0...300)
				m.add('/home/pics/pic $i.png', haxe.io.Bytes.ofString("x"));
			var x = new Explorer(m, (_, _, _) -> {}, [], [], (_, _) -> () -> {});
			var ui = new Ui(new StoryText(), 1212, 592);
			Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
			function frame()
				for (_ in 0...3) {
					helder.view.graph.Graph.flush();
					ui.update();
				}
			x.browser.layout(List);
			x.start("/home/pics");
			frame();
			var rows = ui.root.find("rows");
			rows.scrollY = 3000;
			frame();
			// (rows 100 to 116 in view: one of them opened, flipped twice, closed)
			x.browser.select("pic 105.png");
			x.view("pic 105.png");
			frame();
			x.viewer.next();
			x.viewer.next();
			x.close();
			frame();
			equals(x.browser.selected.value, "pic 107.png");
			equals(ui.root.find("rows").scrollY, 3000.0);
			// (flipped past what was in view: scrolled to show it)
			x.view("pic 107.png");
			frame();
			for (_ in 0...40)
				x.viewer.next();
			x.close();
			frame();
			var y = ui.root.find("rows").scrollY, at = 147 * 30.0;
			equals(x.browser.selected.value, "pic 147.png");
			assert(at >= y && at + 30 <= y + 490, 'pic 147 at $at in view from $y');
		});
		for (layout in [Browser.Layout.List, Browser.Layout.Grid])
			test('scrolled to the end, the last row whole in view with room; each row\'s text inside its row (${layout})', () -> {
				var x = big(), ui = new Ui(new StoryText(), 1212, 592);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				function frame()
					for (_ in 0...3) {
						helder.view.graph.Graph.flush();
						ui.update();
					}
				x.start("/home/folder 0");
				x.browser.layout(layout);
				frame();
				var v:helder.ui.VirtualScroll = cast ui.root.find(layout == List ? "rows" : "grid");
				// (by the scroll's end, and by the keys' End: scrolled to the last item)
				for (way in ["scroll", "key"]) {
					if (way == "scroll") v.scrollY = 1e6 else {
						v.scrollY = 0;
						frame();
						v.scrollToIndex(x.browser.items.value.length - 1);
					}
					frame();
					var shown = [for (r in v.rows()) if (r.node.style.display != None) r];
					var last = shown[shown.length - 1].node, end = last.absY - v.scrollY + last.height;
					var room = v.absY + v.height - end, bar = ui.root.find("pathbar");
					assert(room >= 6 && room <= 12, '$way: the last row ends $room above the view\'s end');
					assert(v.absY + v.height <= bar.absY, '$way: the view ends above the path bar');
				}
				function inside(n:Node, row:Node) {
					if (Std.isOfType(n, helder.ui.TextNode))
						assert(n.absY >= row.absY - 0.01 && n.absY + n.height <= row.absY + row.height + 0.01,
							'"${(cast n : helder.ui.TextNode).text}" at ${n.absY}+${n.height} in ${row.absY}+${row.height}');
					for (c in n.children)
						inside(c, row);
				}
				for (r in v.rows())
					for (c in (layout == List ? [r.node] : r.node.children))
						inside(c, c);
			});
		test("each grid cell asks for its thumbnail once (a hole's picture made once, not twice)", () -> {
			Kinds.utc(true);
			Tiles.forget();
			var m = new OnDisk();
			m.add("tests/fixtures/folder/");
			for (n in sys.FileSystem.readDirectory("tests/fixtures/folder"))
				m.add('tests/fixtures/folder/$n', sys.io.File.getBytes('tests/fixtures/folder/$n'));
			var x = new Explorer(m, (_, _, _) -> {}, [], [], (_, _) -> () -> {});
			var dir = helder.os.Paths.temp() + "/viewer-window-thumbs-" + Std.random(0x40000000);
			x.thumbnails = new Thumbnails(new ThumbCache(1 << 20, 128 << 10, dir), 1);
			var ui = new Ui(new StoryText(), 1212, 592);
			var before:Int = @:privateAccess Tiles.serial;
			Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
			x.start("tests/fixtures/folder");
			for (_ in 0...3) {
				helder.view.graph.Graph.flush();
				ui.update();
			}
			var asked = @:privateAccess Tiles.serial - before, cells = [for (e in x.browser.items.value) if (Kinds.viewable(e) && !FolderModel.isMarkdown(e.name)) e];
			x.thumbnails.close();
			equals(asked, cells.length);
		});
		test("going between folders: the old entries and level shown until the new are read, never an empty grid", () -> {
			var x = big(), ui = new Ui(new StoryText(), 1212, 592);
			Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
			function frame()
				for (_ in 0...3) {
					helder.view.graph.Graph.flush();
					ui.update();
				}
			function tiles():Int {
				var n = 0;
				function walk(c:Node) {
					if (c.slot == "grid-tile" && c.visible()) n++;
					for (k in c.children)
						walk(k);
				}
				walk(ui.root.find("grid"));
				return n;
			}
			x.start("/home/folder 0");
			frame();
			var before = tiles(), level = x.sidebar.level.value, sideRows = x.sidebar.rows.value.length;
			assert(before > 0, "the folder's tiles");
			var files:MemoryFiles = cast x.files;
			files.hold = true;
			x.browser.go("/home/folder 0/sub");
			x.sidebar.show("/home/folder 0");
			frame();
			// (not read yet: the last folder's tiles and level still shown)
			equals(tiles(), before);
			equals(x.sidebar.level.value, level);
			equals(x.sidebar.rows.value.length, sideRows);
			files.release();
			frame();
			equals(x.browser.items.value.length, 300);
			equals(x.browser.items.value[0].name, "inner 0.txt");
			equals(x.sidebar.level.value, "/home/folder 0");
		});
		function shown(path:String):{x:Explorer, ui:Ui, frame:Void->Void} {
			var x = big(), ui = new Ui(new StoryText(), 1212, 592);
			Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
			function frame()
				for (_ in 0...3) {
					helder.view.graph.Graph.flush();
					ui.update();
				}
			x.start(path);
			frame();
			return {x: x, ui: ui, frame: frame};
		}
		function texts(n:Node):Array<String> {
			var out = [];
			function walk(c:Node) {
				if (Std.isOfType(c, helder.ui.TextNode)) out.push((cast c : helder.ui.TextNode).text);
				for (k in c.children)
					walk(k);
			}
			walk(n);
			return out;
		}
		function tile(ui:Ui, name:String):Node {
			var found:Null<Node> = null;
			function walk(c:Node) {
				if (found == null && c.slot == "grid-tile" && c.visible() && texts(c).contains(name)) found = c;
				for (k in c.children)
					walk(k);
			}
			walk(ui.root.find("grid"));
			return found;
		}
		test("a right press on the empty space: the folder's menu; a new folder renamed in place", () -> {
			var w = shown("/home/folder 1"), ui = w.ui, x = w.x;
			var grid = ui.root.find("grid"), px = grid.absX + 200, py = grid.absY + 200;
			ui.pointerDown(px, py, 3);
			ui.pointerUp(px, py, 3);
			w.frame();
			var menu = texts(ui.overlay);
			for (label in ["New Folder", "View", "Get Info"])
				assert(menu.contains(label), '$label in $menu');
			assert(!menu.contains("Open"), 'no entry\'s items: $menu');
			ui.keyDown(helder.ui.Key.ESCAPE, 0);
			w.frame();
			assert(x.perform(NewFolder));
			w.frame();
			// (the field focused a step later)
			helder.ui.Clock.tick(helder.ui.Clock.now + 0.1);
			w.frame();
			equals(x.files.stat("/home/folder 1/untitled folder")?.kind, Folder);
			notEquals(ui.root.find("rename"), null);
			ui.keyDown(helder.ui.Key.ESCAPE, 0);
			w.frame();
			equals(ui.root.find("rename"), null);
			equals(x.browser.selected.value, "untitled folder");
		});
		test("files dragged onto a folder's tile: moved in, the tile marked while over it; undone", () -> {
			var w = shown("/home/folder 0"), ui = w.ui, x = w.x;
			var from = tile(ui, "file 0.txt"), to = tile(ui, "sub");
			notEquals(from, null);
			notEquals(to, null);
			var ax = from.absX + from.width / 2, ay = from.absY + 30, bx = to.absX + to.width / 2, by = to.absY + 30;
			ui.pointerDown(ax, ay, 1);
			ui.pointerMove(ax + 10, ay);
			ui.pointerMove(bx, by);
			w.frame();
			notEquals(to.find("drop-mark"), null);
			ui.pointerUp(bx, by, 1);
			w.frame();
			equals(to.find("drop-mark"), null);
			notEquals(x.files.stat("/home/folder 0/sub/file 0.txt"), null);
			equals(x.files.stat("/home/folder 0/file 0.txt"), null);
			equals(x.browser.entry("file 0.txt"), null);
			assert(x.perform(UndoTrash));
			notEquals(x.files.stat("/home/folder 0/file 0.txt"), null);
		});
		test("another app's files dropped on a folder's tile: copied in; on the space, into the folder shown", () -> {
			var w = shown("/home/folder 0"), ui = w.ui, x = w.x;
			var m:MemoryFiles = cast x.files;
			m.add("/elsewhere/photo.jpg", haxe.io.Bytes.ofString("jpg"));
			var to = tile(ui, "sub");
			assert(Drops.external(x, ui, ["/elsewhere/photo.jpg"], to.absX + to.width / 2, to.absY + 30));
			equals(x.files.stat("/home/folder 0/sub/photo.jpg")?.size, 3);
			notEquals(x.files.stat("/elsewhere/photo.jpg"), null);
			var grid = ui.root.find("grid");
			assert(Drops.external(x, ui, ["/elsewhere/photo.jpg"], grid.absX + grid.width - 10, grid.absY + 5));
			notEquals(x.browser.entry("photo.jpg"), null);
			assert(!Drops.external(x, ui, ["/elsewhere/photo.jpg"], 2, 2), "the toolbar takes none");
		});
		test("a sidebar folder's menu; renamed in place, the folder shown followed", () -> {
			var w = shown("/home/folder 3"), ui = w.ui, x = w.x;
			x.sidebar.show("/home");
			w.frame();
			var labels = [for (i in ViewerActions.sidebarFolder("/home/folder 3")) switch i {
				case Item(label, _): label;
				default: "-";
			}];
			for (label in ["Open", "Rename…", "Copy Path"])
				assert(labels.contains(label), '$label in $labels');
			assert(x.perform(RenameFolder("/home/folder 3")));
			w.frame();
			notEquals(ui.root.find("sidebar").find("rename"), null);
			equals(x.renameFolder("/home/folder 3", "folder 4"), '"folder 4" is already there');
			equals(x.renameFolder("/home/folder 3", "three"), null);
			w.frame();
			equals(x.browser.dir.value, "/home/three");
			assert(Lambda.exists(x.sidebar.rows.value, r -> r.path == "/home/three"));
		});
		function sideRow(ui:Ui, name:String):Null<Node> {
			var found:Null<Node> = null;
			function walk(c:Node) {
				if (found == null && c.slot == "side-row" && texts(c).contains(name)) found = c;
				for (k in c.children)
					walk(k);
			}
			walk(ui.root.find("sidebar"));
			return found;
		}
		// (the folder 3 shown, its level scrolled a little)
		function sidebarScrolled():{x:Explorer, ui:Ui, frame:Void->Void, scroll:Node} {
			var w = shown("/home/folder 3"), ui = w.ui;
			var scroll = ui.root.find("sidebar").find("scroll");
			ui.wheel(scroll.absX + 40, scroll.absY + 40, 0, 120);
			w.frame();
			assert(scroll.scrollY > 0, "the level scrolled");
			return {x: w.x, ui: ui, frame: w.frame, scroll: scroll};
		}
		function folderNames(x:Explorer):Array<String>
			return [for (r in x.sidebar.rows.value) r.name];
		test("a sibling folder trashed by its sidebar menu: no navigation, the level and its scroll kept; undo puts its row back", () -> {
			var w = sidebarScrolled(), ui = w.ui, x = w.x, at = w.scroll.scrollY;
			var row = sideRow(ui, "folder 9");
			notEquals(row, null);
			var cx = row.absX + 30, cy = row.absY + row.height / 2;
			// (the right click: the menu, and no press on the row, which would go into it)
			ui.pointerDown(cx, cy, 3);
			ui.pointerUp(cx, cy, 3);
			w.frame();
			assert(texts(ui.overlay).contains(ViewerActions.trashLabel()), 'the menu: ${texts(ui.overlay)}');
			equals(x.browser.dir.value, "/home/folder 3");
			ui.keyDown(helder.ui.Key.ESCAPE, 0);
			w.frame();
			// (its Move to Trash, as the menu dispatches it)
			assert(x.perform(TrashFolder("/home/folder 9")));
			w.frame();
			equals(x.files.stat("/home/folder 9"), null);
			equals(x.browser.dir.value, "/home/folder 3");
			equals(x.sidebar.level.value, "/home");
			equals(folderNames(x).length, 29);
			assert(!folderNames(x).contains("folder 9"), "its row gone");
			equals(w.scroll.scrollY, at);
			assert(x.perform(UndoTrash));
			w.frame();
			equals(x.files.stat("/home/folder 9")?.kind, Folder);
			equals(x.browser.dir.value, "/home/folder 3");
			equals(x.sidebar.level.value, "/home");
			equals(folderNames(x).indexOf("folder 9"), 9);
			equals(w.scroll.scrollY, at);
		});
		test("the folder shown trashed from the sidebar: its parent shown, at the level that shows it; undo", () -> {
			var w = shown("/home/folder 0/sub"), x = w.x;
			equals(x.sidebar.level.value, "/home/folder 0");
			assert(x.perform(TrashFolder("/home/folder 0/sub")));
			w.frame();
			equals(x.browser.dir.value, "/home/folder 0");
			equals(x.sidebar.level.value, "/home");
			equals(x.browser.entry("sub"), null);
			assert(x.perform(UndoTrash));
			w.frame();
			equals(x.browser.dir.value, "/home/folder 0");
			equals(x.browser.entry("sub")?.kind, Folder);
		});
		test("a sibling folder renamed from the sidebar: in place, no navigation, the scroll kept; undone", () -> {
			var w = sidebarScrolled(), x = w.x, at = w.scroll.scrollY;
			assert(x.perform(RenameFolder("/home/folder 9")));
			w.frame();
			equals(x.renameFolder("/home/folder 9", "folder 9b"), null);
			w.frame();
			equals(x.browser.dir.value, "/home/folder 3");
			equals(x.sidebar.level.value, "/home");
			equals(folderNames(x).length, 30);
			equals(folderNames(x)[9], "folder 9b");
			notEquals(sideRow(w.ui, "folder 9b"), null);
			equals(w.scroll.scrollY, at);
			assert(x.perform(UndoTrash));
			w.frame();
			equals(folderNames(x)[9], "folder 9");
			assert(!folderNames(x).contains("folder 9b"), "the new name gone");
			equals(x.browser.dir.value, "/home/folder 3");
			equals(w.scroll.scrollY, at);
		});
		test("a desktop window under random presses, held or not, right clicks, Escape, folders and sizes: never the touch menu's glass", () -> stateful({
			setup: () -> new Pressed(big()),
			steps: [
				{name: "press", run: (f, c) -> f.press(c.draw(int(0, 999)), c.draw(pick([0.0, 0.2, 0.6, 1.2])), c.draw(bool()))},
				{name: "escape", run: (f, c) -> f.escape()},
				{name: "go", run: (f, c) -> f.go(c.draw(int(0, 31)))},
				{name: "resize", run: (f, c) -> f.resize(c.draw(int(600, 1600)), c.draw(int(420, 1000)))}
			],
			check: f -> f.check(),
			teardown: f -> f.dispose()
		}, {cases: 30, steps: 20}));
	});
}

// (the shell at a desktop's size, pressed with the mouse where its rows and tiles are)
private class Pressed {
	final x:Explorer;
	final ui:Ui;
	final close:Void->Void;
	var t = 0.0;

	public function new(x:Explorer) {
		this.x = x;
		Ui.now = () -> t;
		ui = new Ui(new StoryText(), 1212, 592);
		close = Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
		x.start("/home/folder 0");
		settle();
	}

	// (a sidebar row or a tile in view, the index modulo them; held hold seconds; right: the right button)
	public function press(at:Int, hold:Float, right:Bool) {
		var spots = [];
		function walk(n:Node) {
			if (!n.visible()) return;
			if (n.slot == "side-row" || n.slot == "grid-tile") {
				var b = n.windowBounds();
				if (b.width > 4 && b.height > 4 && b.x >= 0 && b.y >= 0 && b.x + b.width / 2 < ui.width && b.y + b.height / 2 < ui.height)
					spots.push({x: b.x + b.width / 2, y: b.y + b.height / 2});
			}
			for (c in n.children)
				walk(c);
		}
		walk(ui.root);
		if (spots.length == 0) return;
		var p = spots[at % spots.length], button = right ? 3 : 1;
		ui.pointerDown(p.x, p.y, button);
		if (hold > 0) {
			t += hold;
			helder.ui.Clock.tick(helder.ui.Clock.now + hold);
		}
		ui.pointerUp(p.x, p.y, button);
		settle();
	}

	public function escape() {
		ui.keyDown(helder.ui.Key.ESCAPE, 0);
		settle();
	}

	// (a folder of /home's, home itself, or back)
	public function go(i:Int) {
		if (i == 31) x.browser.goBack() else x.browser.go(i == 30 ? "/home" : '/home/folder $i');
		settle();
	}

	public function resize(w:Int, h:Int) {
		ui.resize(w, h);
		settle();
	}

	public function check() {
		equals(ui.overlay.find("touch-menu-layer"), null, "the touch menu");
		var glass = false;
		function walk(n:Node) {
			if (n.slot == "touch-menu-scrim") glass = true;
			for (c in n.children)
				walk(c);
		}
		walk(ui.overlay);
		assert(!glass, "a glass over the window");
	}

	public function dispose()
		close();

	function settle()
		for (_ in 0...2) {
			helder.view.graph.Graph.flush();
			ui.update();
		}
}

// (a folder's batches one a frame, the names from the last: each batch sorts above what came before)
private class Trickle extends MemoryFiles {
	public final queue:Array<Void->Void> = [];

	override public function list(dir:String, batch:Batch->Void):Void->Void {
		var got = [];
		var stop = super.list(dir, b -> got.push(b));
		for (b in got)
			queue.push(() -> batch(b));
		return stop;
	}

	override function children(dir:String):Array<Entry> {
		var all = super.children(dir);
		all.sort((a, b) -> Reflect.compare(b.name.length, a.name.length) * 2 + Reflect.compare(b.name, a.name));
		return all;
	}
}

// (files whose paths are on this disk: the thumbnails' queue reads them)
private class OnDisk extends MemoryFiles {
	override public function localPath(path:String):Null<String>
		return path;
}
