package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The window's content, headless: idle on a folder, nothing drawn again
// and the grid the same frame after frame (a tree taller than the window
// redrew forever, the grid swinging between its cells and none); the
// sidebar scrolling when its rows are taller than the window (the
// overview's, a level's subfolders)
function tests() {
	describe("Shell", () -> {
		function frame(ui:Ui) {
			Graph.flush();
			Clock.finish();
			ui.update();
			Graph.flush();
			ui.update();
		}
		function named(n:Node, text:String):Null<Node> {
			if (Std.isOfType(n, helder.ui.TextNode) && (cast n : helder.ui.TextNode).text == text) return n;
			for (c in n.children) {
				var f = named(c, text);
				if (f != null) return f;
			}
			return null;
		}
		test("idle on a folder: no frame asked for, the grid the same", () -> {
			var t = 0.0;
			Ui.now = () -> t;
			var files = new MemoryFiles();
			files.add("/pictures/");
			for (i in 0...100)
				files.add('/pictures/img$i.png', haxe.io.Bytes.alloc(10));
			var x = new Explorer(files, (_, _, _) -> {}, [for (i in 0...30) ({kind: Pictures, name: 'Place $i', path: "/pictures"} : helder.os.Places.Place)], [],
				Preview.now);
			// (the last selected: scrolled to the end)
			x.browser.go("/pictures", "img99.png");
			x.sidebar.show("");
			for (e in x.browser.items.value)
				Tiles.remember(x, e, new helder.image.Image(4, 3, haxe.io.Bytes.alloc(48)));
			var ui = new Ui(new StoryText(), 1212, 592), canvas = new Nothing();
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			var paints = 0;
			function tick() {
				t += 1 / 60;
				Clock.tick(t);
				Graph.flush();
				ui.update();
				if (!ui.needsFrame) return;
				paints++;
				ui.paint(canvas);
			}
			function grid():String {
				var g = ui.root.find("grid");
				return [for (c in cells(g)) if (c.slot == "grid-tile") Math.round(c.windowBounds().y) + ":" + Math.round(c.windowBounds().x)].join(" ");
			}
			for (_ in 0...60)
				tick();
			assert(ui.root.find("window").height <= 592, "within the window");
			var first = grid();
			assert(first != "", "the grid's cells");
			// (the pointer resting over a tile, then still)
			var b = ui.root.find("grid").windowBounds();
			ui.pointerMove(b.x + 60, b.y + 60, 1);
			for (_ in 0...10)
				tick();
			first = grid();
			paints = 0;
			for (_ in 0...120) {
				tick();
				equals(grid(), first);
			}
			equals(paints, 0);
		});
		// (the user's recording: a folder of two rows in Icons view, the pointer over the sidebar's rows, the grid's
		// offset swinging between its top and one row down from frame to frame)
		for (from in ["fresh", "from a scrolled folder"])
			test('the grid\'s offset stable while the pointer moves over the sidebar (${from})', () -> {
				var t = 0.0;
				Ui.now = () -> t;
				var files = new MemoryFiles();
				files.add("/ben/");
				for (i in 0...17)
					files.add('/ben/f$i/');
				for (n in ["build", "docs", "gen", "refs", "site", "sources", "tools"])
					files.add('/ben/f0/$n/');
				for (n in ["README.md", "serve.sh"])
					files.add('/ben/f0/$n', haxe.io.Bytes.ofString("x"));
				for (i in 0...200)
					files.add('/ben/f1/img$i.png', haxe.io.Bytes.alloc(10));
				var x = new Explorer(files, (_, _, _) -> {}, [], [], Preview.now);
				var ui = new Ui(new StoryText(), 1212, 592), canvas = new Nothing();
				Render.render(Shell.view(x), ui.root);
				Shell.attach(ui.root, x);
				function tick() {
					t += 1 / 60;
					Clock.tick(t);
					Graph.flush();
					ui.update();
					if (ui.needsFrame) ui.paint(canvas);
				}
				if (from == "fresh") x.start("/ben/f0") else {
					x.start("/ben/f1");
					for (_ in 0...10)
						tick();
					ui.root.find("grid").scrollY = 2000;
					for (_ in 0...10)
						tick();
					x.browser.go("/ben/f0");
				}
				for (_ in 0...30)
					tick();
				var grid = ui.root.find("grid"), side = ui.root.find("sidebar");
				equals(grid.scrollY, 0.0);
				// (its columns changed and back: the inspector hidden and shown)
				for (on in [false, true]) {
					x.browser.inspector(on);
					for (_ in 0...10)
						tick();
					equals(grid.scrollY, 0.0);
				}
				var first = cells(grid).filter(c -> c.slot == "grid-tile")[0].windowBounds().y;
				var rows = [for (c in cells(side)) if (c.slot == "side-row") c];
				assert(rows.length >= 17, "the sidebar's rows");
				for (r in rows) {
					var b = r.windowBounds();
					for (dy in [4.0, 14.0, 24.0]) {
						ui.pointerMove(b.x + 40, b.y + dy);
						tick();
						equals(grid.scrollY, 0.0);
						equals(cells(grid).filter(c -> c.slot == "grid-tile")[0].windowBounds().y, first);
					}
				}
			});
		// (the user's recording: the grid blank on still frames after a file
		// was opened and closed, drawn again on frames the pointer moved over
		// a tile)
		test("after a file opened and closed: the grid whole, every idle frame the same", () -> {
			var t = 0.0;
			Ui.now = () -> t;
			var files = new MemoryFiles();
			files.add("/pictures/");
			for (i in 0...9)
				files.add('/pictures/img$i.png', haxe.io.Bytes.alloc(10));
			var x = new Explorer(files, (_, _, _) -> {}, [], [], Preview.now);
			x.start("/pictures");
			for (e in x.browser.items.value)
				Tiles.remember(x, e, new helder.image.Image(4, 3, haxe.io.Bytes.alloc(48)));
			var ui = new Ui(new StoryText(), 1212, 592), log = new Log();
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			var asked = 0;
			function tick() {
				t += 1 / 60;
				Clock.tick(t);
				Graph.flush();
				ui.update();
				if (ui.needsFrame) {
					asked++;
					ui.paint(new Nothing());
				}
			}
			for (_ in 0...30)
				tick();
			x.view("img4.png");
			for (_ in 0...90)
				tick();
			x.close();
			for (_ in 0...120)
				tick();
			var grid = ui.root.find("grid"), browser = ui.root.find("browser");
			equals(x.full.value, false);
			assert(browser.visible() && browser.style.opacity == 1, 'the browser shown: ${browser.visible()} ${browser.style.opacity}');
			equals([for (c in cells(grid)) if (c.slot == "grid-tile" && c.visible()) c].length, 9);
			// (still: nothing asked for, and what a frame would draw the same each time, every tile's picture whole)
			asked = 0;
			var frames = [for (_ in 0...5) {
				tick();
				log.lines.resize(0);
				ui.paint(log);
				log.lines.join("\n");
			}];
			equals(asked, 0);
			for (f in frames)
				equals(f, frames[0]);
			// (the nine tiles' and the inspector's, of the file selected as it closed)
			equals([for (l in frames[0].split("\n")) if (StringTools.startsWith(l, "image 4x3")) l].length, 10);
			assert(frames[0].indexOf("alpha 0 ") < 0, "nothing at opacity 0");
		});
		test("pointer moves that change nothing ask for no frame", () -> {
			var t = 0.0;
			Ui.now = () -> t;
			var files = new MemoryFiles();
			files.add("/pictures/");
			for (i in 0...60)
				files.add('/pictures/img$i.png', haxe.io.Bytes.alloc(10));
			var x = new Explorer(files, (_, _, _) -> {}, [], [], Preview.now);
			x.start("/pictures");
			for (e in x.browser.items.value)
				Tiles.remember(x, e, new helder.image.Image(4, 3, haxe.io.Bytes.alloc(48)));
			var ui = new Ui(new StoryText(), 1212, 592);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function tick():Bool {
				t += 1 / 60;
				Clock.tick(t);
				Graph.flush();
				ui.update();
				var asked = ui.needsFrame;
				if (asked) ui.paint(new Nothing());
				return asked;
			}
			for (_ in 0...60)
				tick();
			var tile = [for (c in cells(ui.root.find("grid"))) if (c.slot == "grid-tile") c][0].windowBounds();
			var side = ui.root.find("sidebar").windowBounds();
			for (spot in [{x: tile.x + 30, y: tile.y + 30}, {x: side.x + 100, y: side.y + side.height - 10}]) {
				ui.pointerMove(spot.x, spot.y);
				for (_ in 0...120)
					tick();
				var asked = [for (k in 0...30) {
					ui.pointerMove(spot.x + (k % 3), spot.y + (k % 2));
					tick();
				}].filter(a -> a).length;
				equals(asked, 0);
			}
		});
		test("the sidebar scrolls: the wheel over it, its last row shown", () -> {
			Ui.now = () -> 0.0;
			var x = Fixtures.explorer();
			for (i in 0...30)
				x.sidebar.add({kind: Pictures, name: 'Place $i', path: "tests/fixtures"});
			x.start("tests/fixtures/folder");
			x.sidebar.show("");
			var ui = new Ui(new StoryText(), 1100, 300);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			frame(ui);
			var list = ui.root.find("overview");
			assert(list.windowBounds().y + list.height <= 300, "within the window");
			var last = named(list, "Place 29");
			assert(last != null, "the last row");
			var b = list.windowBounds();
			ui.wheel(b.x + 50, b.y + 50, 0, 2000);
			frame(ui);
			assert(list.scrollY > 0, "scrolled: " + list.scrollY);
			var r = last.windowBounds();
			assert(r.y + r.height <= b.y + b.height + 0.5, "the last row in view: " + r.y);
		});
		test("a level's many subfolders scroll", () -> {
			Ui.now = () -> 0.0;
			var files = new MemoryFiles();
			files.add("/many/");
			for (i in 0...40)
				files.add('/many/d$i/');
			var x = new Explorer(files, (_, _, _) -> {}, [], [], Preview.now);
			x.start("/many/d0");
			var ui = new Ui(new StoryText(), 1100, 300);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			frame(ui);
			equals(x.sidebar.level.value, "/many");
			var side = ui.root.find("sidebar"), last = named(side, "d39");
			var list = last.parent;
			while (list.style.overflow != Scroll)
				list = list.parent;
			var b = list.windowBounds();
			assert(b.y + b.height <= 300, "within the window");
			ui.wheel(b.x + 50, b.y + 50, 0, 4000);
			frame(ui);
			assert(list.scrollY > 0, "scrolled");
			var r = last.windowBounds();
			assert(r.y + r.height <= b.y + b.height + 0.5, "the last row in view: " + r.y);
		});
	});
}

function cells(n:Node):Array<Node> {
	var out = [n];
	for (c in n.children)
		out = out.concat(cells(c));
	return out;
}

// (draws nothing)
private class Nothing implements helder.ui.Canvas {
	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:helder.ui.Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float)
		pushOpacity(a);

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:helder.ui.Color, borderWidth:Float, border:helder.ui.Color,
		?corners:helder.ui.Corners, ?sides:helder.ui.Edges, style:helder.ui.BorderStyle = Solid) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.ui.Color, blur:Float, ?corners:helder.ui.Corners,
		?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.ui.Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:helder.ui.Corners) {}

	public function path(p:helder.ui.Path, fill:Null<helder.ui.Paint>, ?stroke:helder.ui.Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
		?corners:helder.ui.Corners) {}

	public function text(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.ui.Color,
		?colors:Array<helder.ui.Color>) {}

	public function textShadow(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.ui.Color, blur:Float,
		?colors:Array<helder.ui.Color>) {}
}

// (what is drawn, as lines: each picture and text with the opacity it is drawn at)
private class Log extends Nothing {
	public final lines:Array<String> = [];
	final alphas:Array<Float> = [1];

	override public function pushOpacity(alpha:Float)
		alphas.push(alphas[alphas.length - 1] * alpha);

	override public function popOpacity()
		alphas.pop();

	override public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
			?corners:helder.ui.Corners)
		lines.push('image ${img.width}x${img.height} alpha ${alphas[alphas.length - 1]} at $x,$y ${w}x$h');

	override public function text(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.ui.Color,
			?colors:Array<helder.ui.Color>)
		lines.push('text alpha ${alphas[alphas.length - 1]} at $x,$y');
}
