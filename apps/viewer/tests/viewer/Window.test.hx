package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import viewer.Files;

// The window's content within the window at desktop sizes, with a large
// folder among many: the panels and the path bar end at its bottom, the
// sidebar's level of 30 folders scrolls (its content's height pushed the
// window's content 450 points past a 488-point window's bottom once)
function tests() {
	describe("Window", () -> {
		function bottom(n:Null<Node>):Float
			return n == null ? -1 : n.absY + n.height;
		function big():Explorer {
			Kinds.utc = true;
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
				Kinds.utc = true;
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
			Kinds.utc = true;
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
			Kinds.utc = true;
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
	});
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
