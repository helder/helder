package viewer;

import helder.os.Rect;
import helder.image.Image;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// A file zoomed from its tile and back, headless: the picture in flight's
// rect at its start, half way and at its end, opening (from the tile to
// the image fitted) and closing (from the image to its tile); the tile
// hidden meanwhile; stepped through without a zoom; reduced motion's fade
// alone; a phone's file screen faded in place under the same zoom
function tests() {
	describe("Zoom", () -> {
		var t = 0.0;
		// (the zoom's length)
		final D = Flight.CURVE.duration;
		function frame(ui:Ui) {
			Graph.flush();
			ui.update();
			Graph.flush();
			ui.update();
		}
		function mount(w:Float, h:Float, dir = "tests/fixtures/folder"):{ui:Ui, x:Explorer} {
			t = 0;
			Ui.now = () -> t;
			Clock.tick(0);
			helder.ui.actions.Keymap.mac = false;
			var x = Fixtures.explorer([dir]);
			x.start(dir);
			// (thumbnails as the queue makes them: alpha.png's 13 by 11, photo 2.jpg's 256 by 216)
			for (e in x.browser.items.value)
				if (e.name == "alpha.png" || e.name == "photo 2.jpg") Tiles.remember(x, e, picture(e.name == "alpha.png" ? 13 : 256, e.name == "alpha.png" ? 11 : 216));
			var ui = new Ui(new StoryText(), w, h);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			frame(ui);
			return {ui: ui, x: x};
		}
		// (the clock at dt from now, then laid out)
		function at(ui:Ui, dt:Float) {
			t += dt;
			Clock.tick(t);
			frame(ui);
		}
		function box(ui:Ui):Null<Rect> {
			var n = ui.root.find("zoom");
			return n == null ? null : n.windowBounds();
		}
		function photo(ui:Ui, name:String):Node {
			var found:Null<Node> = null;
			function walk(n:Node) {
				if (found == null && n.slot == "photo" && near(n, ui.root.find("grid"), name)) found = n;
				for (c in n.children)
					walk(c);
			}
			walk(ui.root.find("grid"));
			return found;
		}
		function close(a:Float, b:Float, what:String)
			assert(Math.abs(a - b) < 1, '$what: $a, not $b');
		function same(r:Dynamic, s:Dynamic, what:String) {
			close(r.x, s.x, what + "'s left");
			close(r.y, s.y, what + "'s top");
			close(r.width, s.width, what + "'s width");
			close(r.height, s.height, what + "'s height");
		}
		test("opened from its tile, closed into it", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			var tile = photo(ui, "photo 2.jpg").windowBounds();
			x.browser.select("photo 2.jpg");
			Graph.flush();
			ui.keyDown(Key.ENTER, 0);
			frame(ui);
			equals(x.full.value, true);
			equals(x.zoom.flying.peek(), "tests/fixtures/folder/photo 2.jpg");
			// (the start: the tile's square, the tile itself hidden, the image under it not drawn)
			at(ui, 0);
			same(box(ui), tile, "the start");
			equals(hidden(photo(ui, "photo 2.jpg")), true);
			equals(x.zoom.shown.peek(), 0.0);
			// (the end: the photo fitted, 1242 by 1048 in the stage below the bar)
			var stage = ui.root.find("photo").windowBounds();
			var k = Math.min(1, Math.min(stage.width / 1242, stage.height / 1048));
			var fitted = {x: stage.x + (stage.width - 1242 * k) / 2, y: stage.y + (stage.height - 1048 * k) / 2, width: 1242 * k, height: 1048 * k};
			at(ui, D / 2);
			var mid = box(ui);
			assert(mid.width > tile.width + 20 && mid.width < fitted.width - 20, 'half way: ${mid.width} between');
			assert(mid.y < tile.y && mid.y > fitted.y, 'half way: ${mid.y} between');
			assert(x.zoom.shown.peek() > 0.5 && x.zoom.shown.peek() < 1, "the viewer fading in");
			at(ui, D / 2 - 0.0001);
			same(box(ui), fitted, "the end");
			at(ui, 0.01);
			equals(box(ui), null);
			equals(x.zoom.flying.peek(), "");
			equals(x.zoom.shown.peek(), 1.0);
			equals(hidden(photo(ui, "photo 2.jpg")), false);
			// (the decode where the thumbnail landed: the camera's, at the stage's size (a GPU's paint sets it))
			var c = x.viewer.camera;
			c.setView(stage.width, stage.height);
			var r = c.rect();
			same({x: stage.x + r.x, y: stage.y + r.y, width: r.width, height: r.height}, fitted, "the image shown");
			// (Escape: back into the tile, from the image)
			ui.keyDown(Key.ESCAPE, 0);
			frame(ui);
			equals(x.full.value, false);
			at(ui, 0);
			same(box(ui), fitted, "closing's start");
			at(ui, D / 2);
			var back = box(ui);
			assert(back.width < fitted.width - 20 && back.width > tile.width + 20, 'closing half way: ${back.width}');
			at(ui, D / 2 - 0.0001);
			same(box(ui), tile, "closing's end");
			at(ui, 0.01);
			equals(box(ui), null);
			equals(x.zoom.shown.peek(), 0.0);
		});
		test("a small image to its own size; stepped through without a zoom", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("alpha.png");
			frame(ui);
			at(ui, 0);
			at(ui, D - 0.0001);
			var stage = ui.root.find("photo").windowBounds(), end = box(ui);
			same(end, {x: stage.x + (stage.width - 13) / 2, y: stage.y + (stage.height - 11) / 2, width: 13, height: 11}, "13 by 11");
			Clock.finish();
			frame(ui);
			ui.keyDown(Key.RIGHT, 0);
			frame(ui);
			equals(x.viewer.folder.name, "anim.gif");
			equals(x.zoom.flying.peek(), "");
		});
		test("closed on a file the folder no longer shows: the fade alone", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("photo 2.jpg");
			Clock.finish();
			frame(ui);
			x.browser.search("lossy");
			frame(ui);
			x.close();
			frame(ui);
			at(ui, 0);
			at(ui, 0.3);
			equals(x.zoom.flying.peek(), "");
			Clock.finish();
			equals(x.zoom.shown.peek(), 0.0);
		});
		test("a document's page grows into its column, then gives way to it", () -> {
			var m = mount(1100, 700, "tests/fixtures/markdown"), ui = m.ui, x = m.x;
			var page = ui.root.find("document-tile").windowBounds();
			x.open("doc.md");
			frame(ui);
			at(ui, 0);
			same(box(ui), page, "the start");
			equals(ui.root.find("zoom-page").style.opacity, 1.0);
			at(ui, D - 0.0001);
			var stage = ui.root.find("photo").windowBounds();
			same(box(ui), {x: stage.x + (stage.width - 760) / 2, y: stage.y, width: 760.0, height: stage.height}, "the column");
			assert(ui.root.find("zoom-page").style.opacity < 0.01, "given way");
			Clock.finish();
			frame(ui);
			equals(box(ui), null);
		});
		test("a PDF from its first page's thumbnail to that page", () -> {
			var m = mount(1100, 700, "tests/fixtures/pdf"), ui = m.ui, x = m.x;
			var e = x.browser.entry("pages.pdf");
			Tiles.remember(x, e, picture(181, 256));
			x.browser.refresh();
			frame(ui);
			x.open("pages.pdf");
			frame(ui);
			at(ui, 0);
			at(ui, D - 0.0001);
			same(box(ui), ui.root.find("page").windowBounds(), "the first page");
			Clock.finish();
		});
		test("no thumbnail: the fade alone", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			// (no thumbnail for lossy.webp: no picture to fly)
			x.open("lossy.webp");
			frame(ui);
			equals(x.zoom.flying.peek(), "");
			at(ui, 0);
			at(ui, D / 2);
			assert(x.zoom.shown.peek() > 0 && x.zoom.shown.peek() < 1, "fading in");
			Clock.finish();
			equals(x.zoom.shown.peek(), 1.0);
		});
		test("reduced motion: a short fade, nothing flies", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			Clock.reducedMotion = true;
			x.open("photo 2.jpg");
			frame(ui);
			equals(x.zoom.flying.peek(), "");
			at(ui, 0);
			at(ui, 0.075);
			assert(x.zoom.shown.peek() > 0.2 && x.zoom.shown.peek() < 0.8, "half faded: " + x.zoom.shown.peek());
			at(ui, 0.08);
			equals(x.zoom.shown.peek(), 1.0);
			Clock.reducedMotion = false;
		});
		test("a phone: the file's screen faded in place, the picture zoomed", () -> {
			var m = mount(390, 844), ui = m.ui, x = m.x;
			var tile = ui.root.find("tile-photo 2.jpg");
			assert(tile != null, "the folder's grid");
			var from = tile.children[0].windowBounds();
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			same(box(ui), from, "the start");
			at(ui, D / 2);
			var screens = [for (n in ui.root.find("stack").children) if (n.tag == "screen") n];
			equals(screens.length, 3);
			var top = screens[2];
			equals(top.style.transform == null || top.style.transform.isIdentity(), true);
			assert(top.style.opacity > 0.5 && top.style.opacity < 1, "faded in: " + top.style.opacity);
			assert(box(ui).width > from.width, "growing");
			Clock.finish();
			frame(ui);
			equals(box(ui), null);
			// (back: into the tile again)
			x.close();
			frame(ui);

			at(ui, 0);
			at(ui, D - 0.0001);
			same(box(ui), tile.children[0].windowBounds(), "closing's end");
		});
	});
}

// (a thumbnail of a size: grey)
function picture(w:Int, h:Int):Image {
	var b = haxe.io.Bytes.alloc(w * h * 4);
	b.fill(0, b.length, 128);
	return new Image(w, h, b);
}

// (whether n or what holds it is see-through)
function hidden(n:Node):Bool {
	var a = n;
	while (a != null) {
		if (a.style.opacity == 0) return true;
		a = a.parent;
	}
	return false;
}

// (whether n is in the grid's cell of name)
function near(n:Node, grid:Node, name:String):Bool {
	var a = n;
	while (a != null && a != grid) {
		if (a.slot == "grid-tile") return Lambda.exists(cells(a), c -> Std.isOfType(c, helder.ui.TextNode) && (cast c : helder.ui.TextNode).text == name);
		a = a.parent;
	}
	return false;
}

function cells(n:Node):Array<Node> {
	var out = [n];
	for (c in n.children)
		out = out.concat(cells(c));
	return out;
}
