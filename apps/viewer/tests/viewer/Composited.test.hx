package viewer;

import helder.test.Gen;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The browser as the compositor shows it between the program's frames (a
// hover's colour moving on its own) after hovers, selections, the wheel,
// the keys, folders that scroll and one that fits, back, and a trackpad's
// gestures as a window reads them (the compositor's first): with momentum,
// the program busy, fingers resting on the trackpad and lifted, the list
// taking no input a while (a folder slow to read) or another folder
// shown mid-gesture. Its frames the program's at the same time, pixel for
// pixel within a level, each tile in view showing its thumbnail or its
// icon in both; after a gesture the program's offset within its range,
// the compositor's the same (none where the folder fits), nothing held.
// Without the fix: a folder that fits shown after one scrolled kept that
// one's offset in the compositor's frames (the folder jumped by it at each
// hover), and a scroller the compositor let go while a trackpad held it
// stayed held, never put back within its range
function tests() {
	describe("Composited", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("a folder that fits after one scrolled: the hovers' frames the program's", () -> {
			var w = new Window();
			w.go("/more");
			w.scroll(300);
			w.go("/few");
			for (i in 0...3)
				w.hover(i, 100);
			w.check();
			w.dispose();
		});
		test("hovers, selections and scrolls: the compositor's frames the program's", () -> stateful({
			setup: () -> new Window(),
			steps: [
				{name: "hover", run: (w, c) -> w.hover(c.draw(int(0, 11)), c.draw(int(0, 40)))},
				{name: "off", run: (w, c) -> w.off(c.draw(int(0, 40)))},
				{name: "select", run: (w, c) -> w.select(c.draw(int(0, 11)))},
				{name: "scroll", run: (w, c) -> w.scroll(c.draw(int(-200, 200)))},
				{name: "go", run: (w, c) -> w.go(c.draw(pick(["/docs", "/more", "/few"])))},
				{name: "back", run: (w, c) -> w.back()},
				{name: "key", run: (w, c) -> w.key(c.draw(pick([helder.ui.Key.DOWN, helder.ui.Key.UP, helder.ui.Key.END, helder.ui.Key.HOME])))},
				{name: "trackpad", run: (w, c) -> w.trackpad(c.draw(int(-60, 60)), c.draw(int(1, 12)), c.draw(bool()), c.draw(int(0, 6)), c.draw(int(-1, 30)),
					c.draw(int(1, 60)), c.draw(pick(["", "/docs", "/more", "/few"])), c.draw(int(-1, 20)), c.draw(int(0, 20)))}
			],
			check: w -> w.check(),
			teardown: w -> w.dispose()
		}, {cases: 60, steps: 10}));
		#end
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (the viewer's window at scale 2 on a headless device: a folder of
// pictures (their thumbnails) and documents (their icons) in the grid, the
// renderer's tiles and the compositor as a window's)
private class Window {
	static inline var W = 1100;
	static inline var H = 560;
	static inline var S = 2;
	static final pass:helder.gfx.PassDesc = {colors: [{load: Clear, clear: new helder.math.Vec4(0, 0, 0, 1)}]};

	final device = helder.gfx.Device.create(helder.os.Surface.headless(W * S, H * S));
	final r:helder.ui.draw.Renderer;
	final ui:Ui;
	final c:helder.ui.layers.Compositor;
	final x:Explorer;
	final dispose0:Void->Void;
	final mine = haxe.io.Bytes.alloc(W * S * H * S * 4);
	final theirs = haxe.io.Bytes.alloc(W * S * H * S * 4);
	var now = 10.0;
	var failed = "";

	public function new() {
		Ui.now = () -> now;
		Clock.tick(now);
		var files = new MemoryFiles();
		files.add("/docs/");
		files.add("/docs/CyFun/");
		files.add("/few/");
		for (i in 0...3)
			files.add('/few/f$i.png', haxe.io.Bytes.alloc(100));
		files.add("/more/");
		for (i in 0...40)
			files.add('/more/m$i.png', haxe.io.Bytes.alloc(100));
		for (n in ["gift.ai", "Swetha.docx", "notes.txt", "pp uitvaart.odp", "ben.odp", "gesso.psd", "doc.pdf", "a.key"])
			files.add('/docs/$n', haxe.io.Bytes.alloc(100));
		for (n in ["bg.png", "gesso.png", "gesso2.png"])
			files.add('/docs/$n', haxe.io.Bytes.alloc(100));
		x = new Explorer(files, (_, _, _) -> {}, [{kind: Documents, name: "Documents", path: "/docs"}], [], Preview.now);
		var k = 0;
		for (d in ["/few", "/more", "/docs"]) {
			x.browser.go(d);
			for (e in x.browser.items.value)
				if (StringTools.endsWith(e.name, ".png")) Tiles.remember(x, e, swatch(k++));
		}
		r = new helder.ui.draw.Renderer(device);
		r.tiles = r.groups = true;
		r.scale = S;
		ui = new Ui(new helder.ui.draw.DrawText(), W, H);
		ui.scale = S;
		// (macOS's: a trackpad's stretch past the ends)
		ui.elastic = true;
		dispose0 = Render.render(Shell.view(x), ui.root);
		Shell.attach(ui.root, x);
		c = new helder.ui.layers.Compositor(device);
		ui.onAnswer = c.answer;
		for (_ in 0...20)
			step();
	}

	// (a picture's thumbnail: bands of colour, so that one moved or gone shows)
	static function swatch(k:Int):helder.image.Image {
		var img = new helder.image.Image(96, 72);
		for (y in 0...72)
			for (x in 0...96)
				img.pixels.setInt32((y * 96 + x) * 4, 0xFF000000 | (((k * 53 + y * 3) & 255) << 16) | (((x * 2 + k * 17) & 255) << 8) | ((k * 91) & 255));
		return img;
	}

	function frame(composite:Bool, ?pixels:haxe.io.Bytes) {
		Clock.tick(now);
		Graph.flush();
		ui.update();
		Graph.flush();
		r.tiles = composite;
		var enc = device.beginFrame();
		r.begin(W * S, H * S);
		if (composite) c.begin(r);
		ui.paint(r);
		r.prepare(enc);
		enc.beginPass(pass);
		r.end(enc);
		enc.endPass();
		if (pixels != null) device.readPixels(pixels);
		if (composite) c.end(ui, r);
		device.endFrame();
	}

	// (a vsync: the program's frame)
	function step() {
		now += 1 / 60;
		frame(true);
	}

	// (the program's last frame a while ago: the compositor's frames, then
	// the program's at the same times, compared)
	function held(what:String) {
		var t = now;
		for (d in [1, 3, 7]) {
			now = t + d / 60;
			c.drawNow(mine);
			frame(false, theirs);
			compare('$what, ${d} vsyncs after the program\'s last');
			shown(theirs, '$what, the program\'s frame');
			shown(mine, '$what, the compositor\'s frame ${d} vsyncs after');
		}
		step();
	}

	// (each tile wholly in the grid's view showing its picture: its image's
	// rect not one colour, a thumbnail's bands or an icon's strokes)
	function shown(pixels:haxe.io.Bytes, what:String) {
		if (failed != "") return;
		var g = ui.root.find("grid");
		if (g == null) return;
		var v = g.windowBounds();
		for (t in tiles()) {
			var b = t.windowBounds();
			if (b.y < v.y || b.y + b.height > v.y + v.height) continue;
			var img = image(t);
			if (img == null) {
				failed = '$what: a tile with no image';
				return;
			}
			var r = img.windowBounds(), first = -1, varied = false;
			for (j in 1...6)
				for (i in 1...6) {
					var px = Std.int((r.x + r.width * i / 6) * S), py = Std.int((r.y + r.height * j / 6) * S);
					var c = pixels.getInt32((py * W * S + px) * 4);
					if (first == -1) first = c else if (c != first) varied = true;
				}
			if (!varied) {
				failed = '$what: the tile at ${Math.round(b.x)},${Math.round(b.y)} shows no picture';
				return;
			}
		}
	}

	static function image(n:Node):Null<Node> {
		if (Std.isOfType(n, helder.ui.ImageNode)) return n;
		for (c in n.children) {
			var i = image(c);
			if (i != null) return i;
		}
		return null;
	}

	function compare(what:String) {
		if (failed != "") return;
		var w = W * S, off = 0, most = 0, x0 = w, y0 = H * S, x1 = -1, y1 = -1;
		for (i in 0...w * H * S)
			if (mine.getInt32(i * 4) != theirs.getInt32(i * 4)) {
				var d = 0;
				for (k in 0...3)
					d = Std.int(Math.max(d, Math.abs(mine.get(i * 4 + k) - theirs.get(i * 4 + k))));
				if (d <= 2) continue;
				off++;
				most = Std.int(Math.max(most, d));
				var px = i % w, py = Std.int(i / w);
				x0 = Std.int(Math.min(x0, px));
				y0 = Std.int(Math.min(y0, py));
				x1 = Std.int(Math.max(x1, px));
				y1 = Std.int(Math.max(y1, py));
			}
		if (off == 0) return;
		failed = '$what: $off pixels differ, by $most at most, in $x0,$y0 to $x1,$y1 (device pixels)';
		if (Sys.getEnv("COMPOSITED_PNG") != null) {
			sys.io.File.saveBytes(Sys.getEnv("COMPOSITED_PNG") + "-compositor.png", helder.image.PngEncoder.encode(mine, w, H * S));
			sys.io.File.saveBytes(Sys.getEnv("COMPOSITED_PNG") + "-program.png", helder.image.PngEncoder.encode(theirs, w, H * S));
		}
	}

	function tiles():Array<Node> {
		var out = [];
		function walk(n:Node) {
			if (n.slot == "grid-tile") out.push(n);
			for (k in n.children)
				walk(k);
		}
		walk(ui.root.find("grid"));
		return out;
	}

	public function hover(i:Int, ms:Int) {
		var t = tiles();
		if (t.length == 0) return;
		var b = t[i % t.length].windowBounds();
		ui.pointerMove(b.x + b.width / 2, b.y + b.height / 3);
		for (_ in 0...1 + Std.int(ms / 16))
			step();
		held("a hover");
	}

	public function off(ms:Int) {
		var g = ui.root.find("grid").windowBounds();
		ui.pointerMove(g.x + g.width - 8, g.y + g.height - 8);
		for (_ in 0...1 + Std.int(ms / 16))
			step();
		held("the pointer off the tiles");
	}

	public function select(i:Int) {
		var t = tiles();
		if (t.length == 0) return;
		var b = t[i % t.length].windowBounds(), px = b.x + b.width / 2, py = b.y + b.height / 3;
		ui.pointerDown(px, py, 1);
		ui.pointerUp(px, py, 1);
		step();
		held("a selection");
	}

	public function scroll(dy:Int) {
		var g = ui.root.find("grid").windowBounds();
		ui.wheel(g.x + 100, g.y + 100, 0, dy);
		step();
		step();
		held("a scroll");
	}

	// (a trackpad's gesture over the grid, as a window reads it: the
	// compositor's first (route), the mirror drained at each turn's start,
	// then the program's; dy each step (points; up past the top: a
	// stretch), its momentum after, the program busy for some vsyncs)
	// (drop: the vsync from which the list takes no input, as while a folder
	// is slow to read, for so many: the compositor's no more; -1 none)
	// (rest: the vsyncs after it from which fingers rest on the trackpad,
	// still (macOS's MayBegin, a Began), lifted (Cancelled) so many after; -1 none)
	public function trackpad(dy:Int, steps:Int, momentum:Bool, busy:Int, drop:Int, dropped:Int, to = "", rest = -1, lifted = 0) {
		var g = ui.root.find("grid").windowBounds(), px = Std.int((g.x + 100) * S), py = Std.int((g.y + 100) * S), k = 0;
		var events:Array<Array<helder.os.Event>> = [];
		function pad(d:Float, phase:Int, mom:Int):helder.os.Event {
			var e = new helder.os.Event();
			e.kind = Scroll;
			e.x = px;
			e.y = py;
			e.deltaY = d * S;
			e.phase = phase;
			e.momentum = mom;
			e.time = now * 1000;
			return e;
		}
		events.push([pad(0, helder.os.ScrollPhase.Began, 0)]);
		for (_ in 0...steps)
			events.push([pad(dy, helder.os.ScrollPhase.Changed, 0)]);
		events.push([pad(0, helder.os.ScrollPhase.Ended, 0)]);
		if (momentum) {
			events.push([pad(dy, 0, helder.os.ScrollPhase.Began)]);
			for (i in 0...8)
				events.push([pad(dy * (8 - i) / 8, 0, helder.os.ScrollPhase.Changed)]);
			events.push([pad(0, 0, helder.os.ScrollPhase.Ended)]);
		}
		if (rest >= 0) {
			for (_ in 0...rest)
				events.push([]);
			events.push([pad(0, helder.os.ScrollPhase.Began, 0)]);
			for (_ in 0...lifted)
				events.push([]);
			events.push([pad(0, helder.os.ScrollPhase.Cancelled, 0)]);
		}
		var waiting:Array<helder.os.Event> = [];
		for (i in 0...events.length + 90) {
			now += 1 / 60;
			if (i == drop) to == "" ? x.browser.waiting(true) : x.browser.go(to);
			if (i == drop + dropped) x.browser.waiting(false);
			for (e in events[i] ?? []) {
				e.time = now * 1000;
				c.route(e);
				waiting.push(e);
			}
			// (the program busy: the compositor's frames alone)
			if (i >= 2 && i < 2 + busy) {
				@:privateAccess c.mirror.step(now);
				c.drawNow(mine);
				continue;
			}
			c.drain(ui);
			for (e in waiting)
				helder.ui.UiEvents.deliver(ui, e, S);
			waiting.resize(0);
			frame(true);
		}
		x.browser.waiting(false);
		for (_ in 0...10)
			step();
		var g = ui.root.find("grid"), max = @:privateAccess helder.ui.Scrolling.maxScroll(g, false), o = @:privateAccess c.mirror.offsets(g);
		var kept = @:privateAccess ui.mirrorHeld.exists(g) || @:privateAccess ui.stretched.length > 0 || @:privateAccess ui.trackpad.holds(g);
		if (failed == "" && (g.scrollY < 0 || g.scrollY > max + 0.01 || (o == null ? max > 0 : o.y != g.scrollY) || kept))
			failed = 'after a trackpad\'s gesture: the program\'s offset ${g.scrollY} (its range 0 to $max${kept ? ", held still" : ""}), the compositor\'s ${o == null ? null : o.y}';
		held("a trackpad's gesture");
	}

	public function go(d:String) {
		x.browser.go(d);
		for (_ in 0...6)
			step();
		held("a folder");
	}

	public function back() {
		x.browser.goBack();
		for (_ in 0...6)
			step();
		held("back");
	}

	public function key(k:Int) {
		var g = ui.root.find("grid");
		ui.setFocus(g, false);
		ui.keyDown(k, 0);
		ui.keyUp(k, 0);
		for (_ in 0...20)
			step();
		held("a key");
	}

	public function check()
		equals(failed, "");

	public function dispose() {
		dispose0();
		c.dispose();
		device.dispose();
	}
}
#end
