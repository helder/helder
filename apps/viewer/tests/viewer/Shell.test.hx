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
