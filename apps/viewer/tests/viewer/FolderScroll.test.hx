package viewer;

import haxe.io.Bytes;
import helder.story.StoryText;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.ScrollShot;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The folder scrolls after a PDF is closed, whatever came before: random
// opens, closes (called, Escape) mid-flight or settled, frames, a page's
// render landing late, scrolls, a folder gone to and back; once settled
// in the browser, a wheel over the grid moves it, the program's way and the
// compositor's (the scroller on top at that point in its shot is the
// grid's: a closed PDF's column kept drawn transparent over it took its
// wheels on a real window)
function tests() {
	describe("Folder scroll", () -> {
		test("after a PDF, the folder always scrolls", () -> stateful({
			setup: () -> new Folder(),
			steps: [
				{name: "open the PDF", run: (f, c) -> f.open()},
				{name: "close", run: (f, c) -> f.close()},
				{name: "Escape", run: (f, c) -> f.escape()},
				{name: "frames", run: (f, c) -> f.frames(c.draw(int(1, 15)))},
				{name: "renders land", run: (f, c) -> f.renders()},
				{name: "scroll", run: (f, c) -> f.scroll(c.draw(bool()) ? 120 : -120)},
				{name: "a folder and back", run: (f, c) -> f.away()}
			],
			check: f -> f.check()
		}, {cases: 60, steps: 20}));
	});
}

private class Folder {
	final ui:Ui;
	final x:Explorer;
	final pending:Array<Void->Void> = [];
	var t = 0.0;
	static inline var DIR = "tests/fixtures/pdf";

	public function new() {
		t = 0;
		Ui.now = () -> t;
		Clock.tick(0);
		var files = Fixtures.files([DIR]);
		for (i in 0...40)
			files.add('$DIR/img$i.png', Bytes.alloc(10));
		files.add('$DIR/sub/');
		// (decodes, a PDF's pages too, landing when a step says)
		x = new Explorer(files, (path, side, done) -> pending.push(() -> done(Decode.file({path: path, side: side}))), [], [], Preview.now, null,
			(path, done) -> done(files.text(path)));
		x.viewer.measure = (paths, done) -> done([for (p in paths) null]);
		x.start(DIR);
		Tiles.remember(x, x.browser.entry("pages.pdf"), new helder.image.Image(181, 256, Bytes.alloc(181 * 256 * 4)));
		ui = new Ui(new StoryText(), 1100, 420);
		Render.render(Shell.view(x), ui.root);
		Shell.attach(ui.root, x);
		frame();
	}

	function frame() {
		Graph.flush();
		ui.update();
		Graph.flush();
		ui.update();
	}

	public function frames(n:Int)
		for (_ in 0...n) {
			t += 1 / 60;
			Clock.tick(t);
			frame();
		}

	public function open() {
		if (x.full.value) return;
		x.open("pages.pdf");
		frame();
	}

	public function close() {
		x.close();
		frame();
	}

	public function escape() {
		ui.keyDown(Key.ESCAPE, 0);
		frame();
	}

	public function renders() {
		for (f in pending.splice(0, pending.length))
			f();
		frame();
	}

	public function scroll(dy:Float) {
		var g = ui.root.find("grid");
		if (x.full.value || g == null) return;
		var b = g.windowBounds();
		ui.wheel(b.x + b.width / 2, b.y + b.height / 2, 0, dy);
		frame();
	}

	public function away() {
		if (x.full.value) return;
		x.browser.go('$DIR/sub');
		frame();
		x.browser.goBack();
		frame();
	}

	// (settled in the browser: a wheel over the grid moves it, both ways it may go)
	public function check() {
		if (x.full.value) return;
		for (_ in 0...120)
			if (x.zoom.flying.peek() != "" || Clock.active) frames(1);
		if (x.full.value) return;
		var g = ui.root.find("grid");
		assert(g != null, "the grid");
		var b = g.windowBounds(), cx = b.x + b.width / 2, cy = b.y + b.height / 2;
		// (the compositor's: the scroller on top there is the grid)
		var shot = new ScrollShot();
		ScrollShot.take(ui, shot);
		var top:Null<Node> = null;
		for (i in 0...shot.count) {
			var e = shot.entries[i];
			if (e.up == -1 && e.kind == ScrollShot.SCROLLER && cx >= e.x && cx < e.x + e.w && cy >= e.y && cy < e.y + e.h) top = e.node;
		}
		assert(top == g, 'the compositor\'s scroller there: ${top == null ? "none" : top.tag}');
		// (the program's: the wheel moves it)
		var max = @:privateAccess helder.ui.Scrolling.maxScroll(g, false);
		if (max <= 0) return;
		var was = g.scrollY;
		ui.wheel(cx, cy, 0, was < max / 2 ? 120 : -120);
		frames(30);
		assert(g.scrollY != was, 'the grid scrolled from $was');
	}
}
