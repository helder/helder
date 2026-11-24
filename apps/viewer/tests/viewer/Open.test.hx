package viewer;

import haxe.io.Bytes;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Ui;
import helder.view.Render;
import sys.io.File;
import viewer.Browser.Layout;

// Opening from the browser as a user does: a folder of mixed kinds in the
// grid and the list, an entry double-clicked (and nudged between the two
// clicks), each kind: an image and a PDF full size, a folder entered, a
// file the viewer does not show handed to the system's app; back again;
// the inspector showing a thumbnail before its preview
function tests() {
	describe("Opening from the browser", () -> {
		function mixed():Explorer {
			var files = Fixtures.files(["tests/fixtures/folder"]);
			files.add("tests/fixtures/folder/pages.pdf", File.getBytes("tests/fixtures/pdf/pages.pdf"));
			for (n in ["gesso.psd", "gift.ai", "talk.odp", "resume.docx"])
				files.add('tests/fixtures/folder/$n', Bytes.ofString("not an image"));
			files.add("tests/fixtures/folder/CyFun/bundle.zip", Bytes.alloc(10));
			return new Explorer(files, (path, side, done) -> done(Decode.file({path: path, side: side})), [], [], Preview.now);
		}
		// (a frame: the clock's callbacks run (the image's focus, the list's scroll), laid out)
		var now = 0.0;
		function frame(ui:Ui) {
			helder.view.graph.Graph.flush();
			for (_ in 0...3) {
				helder.ui.Clock.tick(now += 1 / 60);
				helder.view.graph.Graph.flush();
				ui.update();
			}
		}
		function mount(x:Explorer):Ui {
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			x.viewer.camera.setView(800, 600);
			x.start("tests/fixtures/folder");
			helder.view.graph.Graph.flush();
			ui.update();
			return ui;
		}
		// (a double click at the middle of the entry's name, scrolled to, the second press nudged by 3 points)
		function doubleClick(x:Explorer, ui:Ui, name:String) {
			// (scrolled to first: selected, kept in view)
			x.browser.select(name);
			frame(ui);
			var n = find(ui.root, name);
			assert(n != null, name);
			var r = n.rect(), cx = r.x + r.width / 2, cy = r.y + r.height / 2;
			ui.pointerDown(cx, cy, 1);
			ui.pointerUp(cx, cy, 1);
			ui.pointerDown(cx, cy, 1);
			ui.pointerMove(cx + 3, cy, 0);
			ui.pointerUp(cx + 3, cy, 1);
			frame(ui);
		}
		for (layout in [Layout.Grid, Layout.List])
			test('every kind, in the $layout', () -> {
				var x = mixed(), opened = [];
				x.openDefault = p -> opened.push(p);
				x.browser.layout(layout);
				var ui = mount(x);
				for (name in ["photo 2.jpg", "anim.gif", "pages.pdf", "broken.jpg"]) {
					doubleClick(x, ui, name);
					equals(x.full.value, true, name);
					equals(x.viewer.folder.name, name);
					frame(ui);
					// (back with Escape, the keys the image's now)
					ui.keyDown(helder.ui.Key.ESCAPE, 0);
					frame(ui);
					equals(x.full.value, false, name);
					equals(x.browser.selected.value, name);
				}
				// (the others: the system's app; a folder: entered)
				for (name in ["gesso.psd", "resume.docx", "talk.odp", "notes.txt"]) {
					assert(x.open(name), name);
					frame(ui);
					equals(x.full.value, false, name);
				}
				equals(opened.length, 0);
				doubleClick(x, ui, "CyFun");
				equals(x.browser.dir.value, "tests/fixtures/folder/CyFun");
				frame(ui);
				x.browser.goBack();
				frame(ui);
				equals(x.browser.selected.value, "CyFun");
			});
		test("a selection's thumbnail shown while its preview comes (the crash opening a file)", () -> {
			var files = Fixtures.files(["tests/fixtures/folder"]);
			// (a preview that has not answered yet)
			var x = new Explorer(files, (path, side, done) -> done(Decode.file({path: path, side: side})), [], [], (_, _) -> () -> {});
			var ui = mount(x);
			for (name in ["photo 2.jpg", "anim.gif"])
				Tiles.remember(x, x.browser.entry(name), new helder.image.Image(4, 3, Bytes.alloc(48)));
			x.browser.select("photo 2.jpg");
			frame(ui);
			assert(ui.root.find("preview-image") != null, "the thumbnail in the inspector");
			x.open("anim.gif");
			frame(ui);
			equals(x.full.value, true);
		});
	});
}

// (the node whose text is the name)
private function find(n:helder.ui.Node, text:String):Null<helder.ui.Node> {
	if (Std.isOfType(n, helder.ui.TextNode) && (cast n : helder.ui.TextNode).text == text) return n;
	for (c in n.children) {
		var f = find(c, text);
		if (f != null) return f;
	}
	return null;
}
