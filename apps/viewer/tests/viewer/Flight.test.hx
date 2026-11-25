package viewer;

import helder.os.Rect;
import helder.image.Image;
import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Ui;
import helder.ui.motion.Track;
import helder.view.Render;
import helder.view.graph.Graph;

// A file flown from its tile and back, headless. The spring: a quick
// start, a soft settle under 1% over, turned back with its speed. The
// crop: a tile's square, none at the picture's own shape. A gesture's
// progress: the fingers' size followed, a drag down toward the tile, let
// go on or back. The flights: opened from the tile to the image fitted
// and closed into it (the tile hidden, the browser behind smaller and
// darker meanwhile), turned back mid-way without a jump, uncropping as it
// grows, the sharp decode faded in; a trackpad's pinch out on a tile, a
// pinch in at the fit and a swipe down following the fingers, a small
// one springing back; reduced motion's fade alone; a phone's swipe down
function tests() {
	describe("Flight's motion", () -> {
		// (a track sprung from a to b, sampled every 1/120 s for 3 s: its values)
		function spring(a:Float, b:Float):Array<Float> {
			var tr = new Track(a, 1e-3), out = [];
			tr.animate(0, b, Flight.SPRING);
			for (i in 0...360) {
				tr.sample(i / 120);
				out.push(tr.value);
			}
			return out;
		}
		test("the spring: a quick start, a soft settle, under 1% over", () -> {
			var v = spring(0, 1), max = Lambda.fold(v, Math.max, 0.0);
			assert(max <= 1.01, 'over by ${max - 1}');
			assert(v[6] > 0.15, 'quick from the start: ${v[6]} at 50 ms');
			// (settled by its thresholds, well within a second)
			var tr = new Track(0, 1e-3);
			tr.animate(0, 1, Flight.SPRING);
			var t = 0.0;
			while (tr.moving() && t < 3) {
				t += 1 / 120;
				tr.sample(t);
			}
			assert(t < 1, 'settled at $t s');
			equals(tr.value, 1.0);
		});
		test("turned back mid-way: from where it is, as fast", () -> {
			var tr = new Track(0, 1e-3);
			tr.animate(0, 1, Flight.SPRING);
			tr.sample(0.08);
			var at = tr.value, speed = tr.velocity;
			assert(at > 0.2 && at < 0.9 && speed > 0, 'mid-way, going: $at, $speed');
			tr.animate(0.08, 0, Flight.SPRING);
			tr.sample(0.08);
			assert(Math.abs(tr.value - at) < 1e-9 && Math.abs(tr.velocity - speed) < 1e-6, 'carried on: ${tr.value}, ${tr.velocity}');
			// (on a little further first, then back: no jump, under 1% past the tile)
			tr.sample(0.09);
			assert(tr.value > at, "still going on");
			var low = 1.0, t = 0.08;
			while (tr.moving() && t < 3) {
				t += 1 / 120;
				tr.sample(t);
				low = Math.min(low, tr.value);
			}
			assert(low >= -0.01, 'past the tile by ${-low}');
			equals(tr.value, 0.0);
		});
		test("the crop: a tile's square, none at the picture's own shape", () -> {
			var c = Flight.cover(108, 108, 256, 216);
			equals([Math.round(c.x), Math.round(c.y), Math.round(c.width), Math.round(c.height)], [-10, 0, 128, 108]);
			c = Flight.cover(256 * 2.5, 216 * 2.5, 256, 216);
			equals([c.x, c.y, c.width, c.height], [0.0, 0.0, 640.0, 540.0]);
			// (half way between their shapes: half cropped)
			c = Flight.cover(374, 324, 256, 216);
			assert(c.x < 0 && c.x > -10, 'less cropped: ${c.x}');
		});
		test("a gesture's progress: the fingers followed, let go on or back", () -> {
			// (a 100-point tile to a 500-point picture: twice as wide a quarter of the way)
			equals(Flight.scaled(100, 500, 0, 2), 0.25);
			equals(Flight.scaled(100, 500, 1, 0.5), 0.375);
			equals(Flight.scaled(100, 100, 0.4, 3), 0.4);
			// (dragged down half the view: at the tile)
			equals(Flight.dragged(1, 300, 600), 0.0);
			equals(Flight.dragged(1, 150, 600), 0.5);
			equals(Flight.commits(0.5, 0, true), true);
			equals(Flight.commits(0.2, 0, true), false);
			equals(Flight.commits(0.2, 2, true), true);
			equals(Flight.commits(0.5, -2, true), false);
			equals(Flight.commits(0.9, 0, false), false);
			equals(Flight.commits(0.9, -2, false), true);
			equals(Flight.commits(0.5, 0, false), true);
			equals(Flight.commits(0.5, 2, false), false);
		});
	});
	describe("Zoom", () -> {
		var t = 0.0;
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
		// (frames of 1/60 s until the flight is over: the boxes it went through)
		function flown(ui:Ui, x:Explorer):Array<Rect> {
			var out = [], n = 0;
			while (x.zoom.flying.peek() != "" && n++ < 300) {
				at(ui, 1 / 60);
				var b = box(ui);
				if (b != null) out.push(b);
			}
			// (where it landed: its last place)
			out.push(x.zoom.box.peek());
			return out;
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
		// (photo 2.jpg, 1242 by 1048, fitted in the stage)
		function fitted(ui:Ui):Rect {
			var stage = ui.root.find("photo").windowBounds();
			var k = Math.min(1, Math.min(stage.width / 1242, stage.height / 1048));
			return {x: stage.x + (stage.width - 1242 * k) / 2, y: stage.y + (stage.height - 1048 * k) / 2, width: 1242 * k, height: 1048 * k};
		}
		test("opened from its tile, closed into it, the browser behind it deeper", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			var tile = photo(ui, "photo 2.jpg").windowBounds();
			x.browser.select("photo 2.jpg");
			Graph.flush();
			ui.keyDown(Key.ENTER, 0);
			frame(ui);
			equals(x.full.value, true);
			equals(x.zoom.flying.peek(), "tests/fixtures/folder/photo 2.jpg");
			at(ui, 0);
			same(box(ui), tile, "the start");
			equals(hidden(photo(ui, "photo 2.jpg")), true);
			at(ui, 0.05);
			// (the folder behind darker; nothing of the browser moved or scaled)
			var depth = ui.root.find("content").find("depth");
			assert(depth != null && depth.style.opacity > 0, "the folder darker");
			for (n in [ui.root.find("browser"), ui.root.find("sidebar"), ui.root.find("toolbar")])
				assert(n.style.transform == null || n.style.transform.isIdentity(), n.tag + " not moved");
			var fit = fitted(ui), boxes = flown(ui, x);
			assert(boxes.length > 5, 'its frames: ${boxes.length}');
			for (b in boxes)
				assert(b.width <= fit.width * 1.01 + 1, 'over by ${b.width - fit.width}');
			same(boxes[boxes.length - 1], fit, "the end");
			equals(x.zoom.shown.peek(), 1.0);
			equals(hidden(photo(ui, "photo 2.jpg")), false);
			// (the decode where it landed: the camera's, at the stage's size (a GPU's paint sets it))
			var c = x.viewer.camera, stage = ui.root.find("photo").windowBounds();
			c.setView(stage.width, stage.height);
			var r = c.rect();
			same({x: stage.x + r.x, y: stage.y + r.y, width: r.width, height: r.height}, fit, "the image shown");
			// (Escape: back into the tile, from the image)
			ui.keyDown(Key.ESCAPE, 0);
			frame(ui);
			equals(x.full.value, false);
			at(ui, 0);
			same(box(ui), fit, "closing's start");
			boxes = flown(ui, x);
			same(boxes[boxes.length - 1], tile, "closing's end");
			equals(x.zoom.shown.peek(), 0.0);
			equals(ui.root.find("depth"), null);
		});
		test("the sidebar and the bars still through a flight", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			var side = ui.root.find("sidebar").windowBounds(), bar = ui.root.find("toolbar").windowBounds();
			x.open("photo 2.jpg");
			frame(ui);
			for (_ in 0...30) {
				at(ui, 1 / 60);
				same(ui.root.find("sidebar").windowBounds(), side, "the sidebar");
				same(ui.root.find("toolbar").windowBounds(), bar, "the toolbar");
			}
			x.close();
			frame(ui);
			for (_ in 0...30) {
				at(ui, 1 / 60);
				same(ui.root.find("sidebar").windowBounds(), side, "the sidebar closing");
			}
		});
		test("the spring's tail ends at once: no crawl", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			var w:Array<Float> = [x.zoom.box.peek().width], n = 0;
			while (x.zoom.flying.peek() != "" && n++ < 120) {
				at(ui, 1 / 60);
				if (x.zoom.flying.peek() != "") w.push(x.zoom.box.peek().width);
			}
			// (once a frame moves under half a pixel, none moves again)
			var slow = -1;
			for (k in 1...w.length) {
				var d = Math.abs(w[k] - w[k - 1]);
				if (slow < 0 && d > 0 && d < 0.5) slow = k;
				if (slow >= 0 && k > slow) equals(d, 0.0);
			}
			assert(n / 60 <= 0.45, 'settled in ${n / 60} s');
		});
		test("small and large pictures: from the tile straight to their own size, a small one after a big one too", () -> {
			t = 0;
			Ui.now = () -> t;
			Clock.tick(0);
			var files = new MemoryFiles(), sizes = ["big.jpg" => [6000, 4000], "small.png" => [120, 80], "icon.png" => [64, 64], "pano.jpg" => [12000, 1500]];
			files.add("/pics/");
			for (name in sizes.keys())
				files.add('/pics/$name', haxe.io.Bytes.alloc(100));
			// (decodes that never land: where it goes from the header alone)
			var x = new Explorer(files, (_, _, _) -> {}, [], [], Preview.now);
			x.viewer.measure = (paths, done) -> done([for (p in paths) {
				var s = sizes.get(Browser.name(p));
				s == null ? null : {width: s[0], height: s[1]};
			}]);
			x.start("/pics");
			for (e in x.browser.items.value) {
				var s = sizes.get(e.name), k = Math.min(1, 256 / Math.max(s[0], s[1]));
				Tiles.remember(x, e, picture(Std.int(Math.max(1, Math.round(s[0] * k))), Std.int(Math.max(1, Math.round(s[1] * k)))));
			}
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			frame(ui);
			function own(name:String):Rect {
				var s = sizes.get(name), b = ui.root.find("photo").windowBounds(), f = Math.min(1, Math.min(b.width / s[0], b.height / s[1]));
				return {x: b.x + (b.width - s[0] * f) / 2, y: b.y + (b.height - s[1] * f) / 2, width: s[0] * f, height: s[1] * f};
			}
			for (name in ["big.jpg", "small.png", "icon.png", "pano.jpg"]) {
				x.open(name);
				frame(ui);
				at(ui, 0);
				same(x.zoom.landing(), own(name), '$name lands');
				var start = x.zoom.box.peek(), to = own(name), edges = [];
				for (_ in 0...40) {
					at(ui, 1 / 60);
					var b = x.zoom.box.peek();
					edges.push([b.x, b.y, b.x + b.width, b.y + b.height]);
					if (x.zoom.progress() >= 0.999) break;
				}
				var from = [start.x, start.y, start.x + start.width, start.y + start.height], goal = [to.x, to.y, to.x + to.width, to.y + to.height];
				for (e in 0...4) {
					var way = goal[e] > from[e] ? 1 : -1, last = from[e];
					for (v in edges) {
						assert((v[e] - last) * way >= -0.05, '$name edge $e back from $last to ${v[e]}');
						last = v[e];
					}
				}
				x.close();
				frame(ui);
				flown(ui, x);
				for (_ in 0...10)
					at(ui, 1 / 60);
			}
		});
		test("the grid scrolled under it: closing, the tile itself at once; opening, with its tile", () -> {
			var m = mount(1100, 320), ui = m.ui, x = m.x;
			x.browser.select("photo 2.jpg");
			for (_ in 0...5)
				at(ui, 1 / 60);
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			at(ui, 1 / 60);
			at(ui, 1 / 60);
			var grid = ui.root.find("grid");
			grid.scrollY = Math.max(0, grid.scrollY - 30);
			frame(ui);
			at(ui, 1 / 60);
			if (x.zoom.flying.peek() != "") {
				var tile = photo(ui, "photo 2.jpg").windowBounds(), to = x.zoom.landing(), k = x.zoom.progress(), b = x.zoom.box.peek();
				close(b.x, tile.x + (to.x - tile.x) * k, "with its tile: left");
				close(b.y, tile.y + (to.y - tile.y) * k, "with its tile: top");
			}
			flown(ui, x);
			x.close();
			frame(ui);
			at(ui, 0);
			for (_ in 0...8)
				at(ui, 1 / 60);
			assert(x.zoom.flying.peek() != "", "still closing");
			grid.scrollY = grid.scrollY > 30 ? grid.scrollY - 30 : grid.scrollY + 30;
			frame(ui);
			at(ui, 1 / 60);
			equals(x.zoom.flying.peek(), "");
			equals(ui.root.find("zoom"), null);
			equals(hidden(photo(ui, "photo 2.jpg")), false);
		});
		test("closed mid-flight: back from where it is, no jump", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			var tile = photo(ui, "photo 2.jpg").windowBounds();
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			for (_ in 0...4)
				at(ui, 1 / 60);
			var before = box(ui);
			assert(before.width > tile.width + 20, 'on its way: ${before.width}');
			x.close();
			frame(ui);
			at(ui, 1 / 60);
			var after = box(ui);
			// (a frame's move, not a jump to either end)
			assert(Math.abs(after.width - before.width) < 100, 'from ${before.width} to ${after.width}');
			assert(Math.abs(after.width - tile.width) > 20, "not snapped to the tile");
			var boxes = flown(ui, x);
			same(boxes[boxes.length - 1], tile, "the end");
		});
		test("uncropped as it grows, the sharp picture faded in", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			// (at the tile: the thumbnail wider than its square box, cropped)
			var b = box(ui), thumb = ui.root.find("zoom-thumb").windowBounds();
			assert(thumb.width > b.width + 5, 'cropped at the tile: ${thumb.width} in ${b.width}');
			var sharp = 0.0;
			for (_ in 0...9) {
				at(ui, 1 / 60);
				var s = ui.root.find("zoom-sharp");
				if (s != null) sharp = Math.max(sharp, s.style.opacity);
			}
			assert(sharp > 0.9, 'the sharp picture: $sharp');
			// (near the end: the whole picture, all but uncropped)
			b = box(ui);
			thumb = ui.root.find("zoom-thumb").windowBounds();
			assert(Math.abs(thumb.width - b.width) < b.width * 0.01 && Math.abs(thumb.height - b.height) < b.height * 0.01, 'uncropped: ${thumb.width} by ${thumb.height} in ${b.width} by ${b.height}');
			flown(ui, x);
		});
		// (a trackpad's pinch: Control and a wheel's -180 ln(scale), over a node)
		function pinch(ui:Ui, n:Node, scale:Float) {
			var b = n.windowBounds();
			ui.wheel(b.x + b.width / 2, b.y + b.height / 2, 0, -180 * Math.log(scale), false, helder.os.Mods.CONTROL);
			at(ui, 1 / 60);
		}
		test("a pinch out on a tile opens it with the fingers; a small one springs back", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			var tile = photo(ui, "photo 2.jpg");
			pinch(ui, tile, 1.7);
			var a = x.zoom.progress();
			assert(a > 0 && x.zoom.holding(), 'following: $a');
			pinch(ui, tile, 1.7);
			pinch(ui, tile, 1.7);
			assert(x.zoom.progress() > a, "further with the fingers");
			equals(x.full.value, false);
			// (let go: past a third, on to full size)
			for (_ in 0...20)
				at(ui, 1 / 60);
			equals(x.full.value, true);
			equals(x.viewer.folder.name, "photo 2.jpg");
			flown(ui, x);
			equals(x.zoom.progress() > 0.99, true);
			// (back, then a small pinch: back to the tile, not opened)
			x.close();
			frame(ui);
			flown(ui, x);
			for (_ in 0...30)
				at(ui, 1 / 60);
			pinch(ui, photo(ui, "photo 2.jpg"), 1.05);
			for (_ in 0...20)
				at(ui, 1 / 60);
			flown(ui, x);
			equals(x.full.value, false);
			assert(x.zoom.progress() < 0.01, 'back: ${x.zoom.progress()}');
		});
		test("full size: a pinch in at the fit, a swipe down, close it with the fingers", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("photo 2.jpg");
			frame(ui);
			flown(ui, x);
			x.viewer.camera.setView(ui.root.find("photo").width, ui.root.find("photo").height);
			var view = ui.root.find("photo");
			pinch(ui, view, 0.7);
			pinch(ui, view, 0.7);
			assert(x.zoom.progress() < 0.9 && x.zoom.holding(), 'following: ${x.zoom.progress()}');
			for (_ in 0...20)
				at(ui, 1 / 60);
			equals(x.full.value, false);
			flown(ui, x);
			// (opened again; a trackpad's swipe down: its scroll up, not a wheel's notches)
			x.open("photo 2.jpg");
			frame(ui);
			flown(ui, x);
			var b = view.windowBounds();
			for (_ in 0...4) {
				ui.wheel(b.x + 100, b.y + 100, 0, -60, false, 0);
				at(ui, 1 / 60);
			}
			assert(x.zoom.progress() < 0.8, 'down with the fingers: ${x.zoom.progress()}');
			for (_ in 0...20)
				at(ui, 1 / 60);
			equals(x.full.value, false);
			flown(ui, x);
		});
		test("no thumbnail: the fade alone", () -> {
			var m = mount(1100, 700), ui = m.ui, x = m.x;
			x.open("lossy.webp");
			frame(ui);
			equals(x.zoom.flying.peek(), "");
			at(ui, 0);
			at(ui, 0.05);
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
		test("a phone: in and out of its tile, a swipe down following the finger", () -> {
			var m = mount(390, 844), ui = m.ui, x = m.x;
			var tile = ui.root.find("tile-photo 2.jpg");
			assert(tile != null, "the folder's grid");
			var from = tile.children[0].windowBounds();
			x.open("photo 2.jpg");
			frame(ui);
			at(ui, 0);
			same(box(ui), from, "the start");
			flown(ui, x);
			equals(x.full.value, true);
			// (a swipe down on the file: it shrinks with the finger, let go it closes)
			ui.pointerDown(195, 300, 1, 1, Touch);
			for (k in 1...8) {
				t += 0.016;
				ui.pointerMove(195, 300 + k * 40, 1);
				at(ui, 0);
				if (k == 4) assert(x.zoom.holding() && x.zoom.progress() < 1, 'following: ${x.zoom.progress()}');
			}
			ui.pointerUp(195, 580, 1, 1);
			frame(ui);
			flown(ui, x);
			for (_ in 0...30)
				at(ui, 1 / 60);
			equals(x.full.value, false);
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
