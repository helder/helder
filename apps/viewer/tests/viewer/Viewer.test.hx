package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Key;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;

// A scripted run, headless: the shell's tree in a Ui without a window or
// a GPU, the fixture folder browsed (tests/fixtures/folder: a PNG, an
// animated GIF, a JPEG cut short, a WebP, a photo and a JPEG turned by
// EXIF, a text file), a file opened full size, flipped through with the
// keys and the wheel, zoomed, the status line shown, back to the folder,
// as a user would
function tests() {
	describe("Viewer, scripted", () -> {
		// (the keys as pressed off a Mac: secondary is Control, whichever host runs it)
		beforeEach(() -> helder.ui.actions.Keymap.mac = false);
		var dir = "tests/fixtures/folder";
		function text(ui:Ui, tag:String):String {
			var n = ui.root.find(tag);
			if (n == null) return "";
			if (Std.isOfType(n, TextNode)) return (cast n : TextNode).text;
			for (c in n.children)
				if (Std.isOfType(c, TextNode)) return (cast c : TextNode).text;
			return "";
		}
		test("browse, open, flip, zoom, the status line, back", () -> {
			var x = Fixtures.explorer(), viewer = x.viewer;
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			viewer.camera.setView(800, 600);
			x.start(dir);
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.state.peek(), Empty);
			equals(ContentView.count(x), "7 items");
			assert(ui.root.find("grid") != null, "the grid");
			// (Mod+2 the list, Mod+1 the grid again)
			ui.keyDown("2".code, Key.MOD_CONTROL);
			ui.update();
			assert(ui.root.find("rows") != null && ui.root.find("grid") == null, "the list");
			ui.keyDown("1".code, Key.MOD_CONTROL);
			ui.update();
			assert(ui.root.find("grid") != null, "the grid again");
			// (Enter on the first: the viewer, its list the folder's images in the browser's order)
			x.browser.select("alpha.png");
			helder.view.graph.Graph.flush();
			ui.keyDown(Key.ENTER, 0);
			helder.view.graph.Graph.flush();
			ui.update();
			equals(x.full.value, true);
			equals(viewer.title.peek(), "alpha.png · 1 / 6 · 13×11");
			// (the next: an animated GIF, its frames played)
			ui.keyDown(Key.RIGHT, 0);
			ui.update();
			equals(viewer.title.peek(), "anim.gif · 2 / 6 · 37×29");
			equals(viewer.shown.frames.length, 2);
			viewer.tick(0, 0);
			viewer.tick(0.15, 0.15);
			equals(viewer.frame, 1);
			// (a JPEG cut short: its message in place, flipping goes on)
			ui.keyDown(Key.PAGE_DOWN, 0);
			ui.update();
			equals(viewer.state.peek(), Failed);
			assert(StringTools.startsWith(text(ui, "title"), "Damaged or cut short"), text(ui, "title"));
			equals(viewer.title.peek(), "broken.jpg · 3 / 6");
			// (the wheel, fitted: the next)
			viewer.wheel(400, 300, 40, false, 10);
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.title.peek(), "lossy.webp · 4 / 6 · 50×40");
			ui.keyDown(Key.RIGHT, 0);
			ui.update();
			equals(viewer.title.peek(), "photo 2.jpg · 5 / 6 · 1242×1048");
			equals(viewer.camera.fitted, true);
			equals(viewer.camera.percent(), 57);
			// (the zoom: + (Shift and =), 1, the wheel about the cursor, 0; the viewer's keymap)
			ui.keyDown("=".code, Key.MOD_SHIFT);
			equals(viewer.camera.percent(), 67);
			ui.keyDown("1".code, 0);
			equals(viewer.camera.percent(), 100);
			viewer.wheel(100, 100, -40, true, 11);
			equals(viewer.camera.percent(), 125);
			viewer.pan(50, 0);
			ui.keyDown("0".code, 0);
			equals(viewer.camera.fitted, true);
			// (the status line)
			ui.keyDown("i".code, 0);
			ui.update();
			equals(text(ui, "status"), "57% · 1242×1048 · JPEG · 197 KB · 5 / 6");
			// (EXIF's orientation 6: 37x29 stored, shown 29x37)
			ui.keyDown(Key.END, 0);
			ui.update();
			equals(viewer.title.peek(), "photo 10.jpg · 6 / 6 · 29×37");
			// (wrapping, Home)
			ui.keyDown(Key.RIGHT, 0);
			equals(viewer.folder.name, "alpha.png");
			ui.keyDown(Key.LEFT, 0);
			equals(viewer.folder.name, "photo 10.jpg");
			ui.keyDown(Key.HOME, 0);
			equals(viewer.folder.name, "alpha.png");
			// (Escape: back to the folder, the file viewed last selected)
			ui.keyDown(Key.ESCAPE, 0);
			helder.view.graph.Graph.flush();
			equals(x.full.value, false);
			equals(x.browser.selected.value, "alpha.png");
			x.open("photo 2.jpg");
			helder.view.graph.Graph.flush();
			// (fullscreen: F11 and Enter, Escape leaves)
			ui.keyDown(Key.F1 + 10, 0);
			equals(viewer.fullscreen.peek(), true);
			ui.keyDown(Key.ESCAPE, 0);
			equals(viewer.fullscreen.peek(), false);
			// (decoded at the size shown: a small view, the photo at 1/4; at 100% decoded again whole)
			viewer.camera.setView(300, 200);
			viewer.cache.clear();
			x.start(dir + "/photo 2.jpg");
			helder.view.graph.Graph.flush();
			equals([viewer.shown.width, viewer.shown.pixelsWidth], [1242, 311]);
			viewer.actual();
			equals([viewer.shown.width, viewer.shown.pixelsWidth], [1242, 1242]);
			viewer.camera.setView(800, 600);
			// (Mod+Up: the folder again)
			ui.keyDown(Key.UP, Key.MOD_CONTROL);
			helder.view.graph.Graph.flush();
			equals(x.full.value, false);
			equals(x.browser.selected.value, "photo 2.jpg");
			// (the browser's keys: Mod+2 the list, Mod+I the inspector, Mod+F search)
			ui.keyDown("i".code, Key.MOD_CONTROL);
			helder.view.graph.Graph.flush();
			equals(x.browser.inspector.value, false);
			ui.keyDown("f".code, Key.MOD_CONTROL);
			helder.view.graph.Graph.flush();
			equals(x.browser.searching.value, true);
			x.browser.search("photo");
			equals([for (e in x.browser.items.value) e.name], ["photo 2.jpg", "photo 10.jpg"]);
			ui.keyDown(Key.ESCAPE, 0);
			equals(x.browser.query.value, "");
		});
		test("the grid's marquee: drawn in the look's accent while it is dragged", () -> {
			var x = Fixtures.explorer(), ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Fixtures.themed(x, true), ui.root);
			x.start(dir);
			helder.view.graph.Graph.flush();
			ui.update();
			var grid = ui.root.find("grid");
			// (from the empty space under the cells, up over the first row)
			var bottom = grid.absY + grid.height - 20, right = grid.absX + grid.width - 20;
			ui.pointerDown(right, bottom, 1);
			ui.pointerMove(right - 100, bottom - 100);
			ui.pointerMove(grid.absX + 40, grid.absY + 40);
			helder.view.graph.Graph.flush();
			ui.update();
			var band = grid.find("marquee");
			notEquals(band, null);
			equals(band.style.background, Shell.look.sheet().dark.get("accentSoft"));
			equals(band.style.borderWidth, 1.0);
			assert(band.width > 300 && band.height > 300, '${band.width} x ${band.height}');
			assert(x.browser.selection.size() > 1, "the cells it crosses selected");
			ui.pointerUp(grid.absX + 40, grid.absY + 40, 1);
			equals(grid.find("marquee"), null);
		});
		test("the View menu: open as the mouse goes down, closed by a press on its button", () -> {
			var x = Fixtures.explorer(), ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Fixtures.themed(x, true), ui.root);
			x.start(dir);
			helder.view.graph.Graph.flush();
			ui.update();
			var button = ui.root.find("view-menu"), at = {x: button.absX + 8, y: button.absY + 8};
			ui.pointerDown(at.x, at.y, 1);
			ui.update();
			equals(ui.overlay.children.length, 1);
			ui.pointerUp(at.x, at.y, 1);
			equals(ui.overlay.children.length, 1);
			ui.pointerDown(at.x, at.y, 1);
			ui.pointerUp(at.x, at.y, 1);
			ui.update();
			equals(ui.overlay.children.length, 0);
		});
		test("what a broken file says", () -> {
			equals(Decode.decode(haxe.io.Bytes.alloc(0)).error, "The file is empty");
			var bad = Decode.decode(haxe.io.Bytes.ofString("%PDF-1.4\nnonsense"));
			assert(StringTools.startsWith(bad.error, "A damaged PDF: "), bad.error);
			equals(bad.errorKind, "corrupt");
			assert(StringTools.startsWith(Decode.decode(haxe.io.Bytes.ofString("hello")).error, "Not an image this viewer reads"), "not an image");
		});
		test("a PDF: its pages in one column, the keys scrolling it, go to page, the zoom", () -> {
			var asked = [];
			var x = new Explorer(Fixtures.files(["tests/fixtures/pdf"]), (path, side, done) -> {
				asked.push(Decode.parseKey(path).page);
				done(Decode.file({path: path, side: side}));
			}, [], [], Preview.now), viewer = x.viewer;
			var ui = new Ui(new StoryText(), 800, 600);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function frame() {
				helder.view.graph.Graph.flush();
				ui.update();
				helder.view.graph.Graph.flush();
				ui.update();
			}
			x.start("tests/fixtures/pdf/pages.pdf");
			frame();
			equals(viewer.state.peek(), Shown);
			equals(viewer.pages, 3);
			equals(viewer.title.peek(), "pages.pdf · 1 / 1 · page 1 / 3");
			var doc = viewer.pdf.peek();
			assert(doc != null, "the column");
			// (the stage below the bar: 800 by 548; fitted to its width, the first page drawn and the next)
			equals([doc.layout.viewWidth, doc.layout.viewHeight], [800.0, 548.0]);
			equals(doc.layout.zoom, doc.layout.fitWidth());
			assert(ui.root.find("pdf-scroll") != null && ui.root.find("page") != null, "pages made");
			equals(asked.slice(0, 2), [0, 1]);
			assert(doc.image(0) != null, "page 1 drawn");
			// (Page Down a screen; ] the next page, its title; End the last, Home the first)
			ui.keyDown(Key.PAGE_DOWN, 0);
			frame();
			equals(doc.y, 548 * 0.9);
			ui.keyDown("]".code, 0);
			frame();
			equals(doc.y, doc.layout.scrollFor(1));
			equals(viewer.title.peek(), "pages.pdf · 1 / 1 · page 2 / 3");
			ui.keyDown(Key.END, 0);
			frame();
			equals(viewer.page, 2);
			ui.keyDown(Key.HOME, 0);
			frame();
			equals([viewer.page, Std.int(doc.y)], [0, 4]);
			// (go to page: G, a number, Enter; past the last: the last)
			ui.keyDown("g".code, 0);
			frame();
			equals(viewer.gotoOpen.peek(), true);
			assert(ui.root.find("goto") != null, "the go to page card");
			equals(viewer.goToTyped("3"), true);
			frame();
			equals(viewer.page, 2);
			equals(viewer.gotoOpen.peek(), false);
			viewer.goToTyped("99");
			equals(viewer.page, 2);
			// (1: 100%; 0: fitted again; the status line says the zoom and the page)
			ui.keyDown("1".code, 0);
			frame();
			equals(doc.percent(), 100);
			ui.keyDown("0".code, 0);
			frame();
			equals(doc.layout.zoom, doc.layout.fitWidth());
			ui.keyDown("i".code, 0);
			frame();
			equals(text(ui, "status"), '${doc.percent()}% · page ${viewer.page + 1} / 3 · PDF · 1 KB · 1 / 1');
			// (past the last page: nothing)
			equals(viewer.toPage(5), false);
		});
	});
}
