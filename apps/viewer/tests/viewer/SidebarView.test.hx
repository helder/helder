package viewer;

import helder.story.StoryText;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The sidebar: its volume's card (its name, how full, what is free of
// what); going between levels as a push of the levels alone (the bar over
// them, its back row's chevron and the overview's button, and the foot's
// card where they were on every frame), both panes together on the
// spring at whole-point offsets, settled soon, the old one gone after;
// clicked again on the way, turned from where they are (no third pane, no
// restart); clicked fast, a burst of levels: two at most on screen, the
// ones between never shown, settled on the last within a spring's time;
// a folder's double click, at any speed: its level entered when quick and
// near, the folder shown once either way; back retracing the way in (a
// place or a device chosen: back to the overview); reduced motion: a
// cross-fade in place
function tests() {
	describe("SidebarView", () -> {
		var t = 0.0;
		function frame(ui:Ui) {
			Graph.flush();
			ui.update();
			Graph.flush();
			ui.update();
		}
		function mount():{ui:Ui, x:Explorer} {
			t = 0;
			Ui.now = () -> t;
			Clock.tick(0);
			var x = Fixtures.explorer(null, [Fixtures.DISK]);
			x.start("tests/fixtures/folder");
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			frame(ui);
			// (its first level landed and settled; a while shown)
			Clock.finish();
			frame(ui);
			t = Clock.now + 0.2;
			Clock.tick(t);
			frame(ui);
			return {ui: ui, x: x};
		}
		function at(ui:Ui, dt:Float) {
			t += dt;
			Clock.tick(t);
			frame(ui);
		}
		function text(n:Null<helder.ui.Node>):String
			return n == null ? "" : Std.isOfType(n, TextNode) ? (cast n : TextNode).text : [for (c in n.children) text(c)].join("");
		// (the panes now: each one's offset, opacity and title ("" the overview))
		function panes(ui:Ui):Array<{x:Float, o:Float, title:String}> {
			var body = ui.root.find("sidebar-body");
			return [for (n in body.children) if (n.tag == "sidebar-pane") {
				var tr = n.style.transform, title = n.find("level-title");
				{x: tr == null ? 0.0 : tr.toMatrix(1, 1).e, o: n.style.opacity, title: title == null ? "" : text(title)};
			}];
		}
		function pane(ui:Ui, title:String):Null<{x:Float, o:Float, title:String}> {
			for (p in panes(ui))
				if (p.title == title) return p;
			return null;
		}
		test("the volume's card: its name, how full, what is free of what", () -> {
			var ui = mount().ui;
			equals(text(ui.root.find("capacity-name")), "Macintosh HD");
			equals(text(ui.root.find("capacity-used")), "91%");
			equals(text(ui.root.find("capacity-free")), "45.3 GB free of 494.0 GB");
			assert(ui.root.find("capacity").style.radius > 0, "a card's corners");
		});
		test("back: both levels moving together, whole points, settled soon", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			equals(x.sidebar.level.value, "tests/fixtures");
			x.sidebar.back();
			frame(ui);
			equals(x.sidebar.level.value, "tests");
			at(ui, 0);
			var inX:Array<Float> = [], outX:Array<Float> = [], n = 0;
			while (panes(ui).length > 1 && n++ < 60) {
				at(ui, 1 / 60);
				var a = pane(ui, "Macintosh HD"), b = pane(ui, "fixtures");
				if (a == null || b == null) break;
				inX.push(a.x);
				outX.push(b.x);
			}
			// (the enclosing level from the left, the deeper one out to the right, together)
			assert(inX[0] < -10 && outX[0] > 10, 'both moving: ${inX[0]}, ${outX[0]}');
			for (k in 1...inX.length) {
				assert(inX[k] >= inX[k - 1] - 0.01, 'in, monotone: ${inX[k - 1]} then ${inX[k]}');
				assert(outX[k] >= outX[k - 1] - 0.01, 'out, monotone: ${outX[k - 1]} then ${outX[k]}');
				equals(inX[k], Math.round(inX[k]));
			}
			assert(n * 1 / 60 < 0.5, 'settled in ${n / 60} s');
			equals(panes(ui).length, 1);
			equals(panes(ui)[0].x, 0.0);
			equals(panes(ui)[0].title, "Macintosh HD");
		});
		test("the bar and the foot stay: the same frames on every frame of a level change", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			function rect(tag:String):String {
				var n = ui.root.find(tag);
				if (n == null) return tag + ": none";
				var b = n.windowBounds();
				return '$tag: ${b.x} ${b.y} ${b.width} ${b.height}';
			}
			// (the back row's chevron: its first child)
			function chevron():String {
				var b = ui.root.find("level-back").children[0].windowBounds();
				return 'chevron: ${b.x} ${b.y} ${b.width} ${b.height}';
			}
			function change(go:() -> Void, still:Array<String>) {
				function frames():Array<String>
					return [for (t in still) rect(t)].concat([chevron()]);
				var first = frames(), n = 0;
				go();
				frame(ui);
				equals(frames(), first);
				at(ui, 0);
				while ((panes(ui).length > 1 || n < 2) && n++ < 60) {
					at(ui, 1 / 60);
					equals(frames(), first);
				}
				assert(n < 60, "settled");
			}
			// (within the volume: the foot's card too)
			change(() -> x.sidebar.back(), ["level-bar", "level-home", "capacity"]);
			equals(x.sidebar.level.value, "tests");
			change(() -> x.sidebar.show("tests/fixtures"), ["level-bar", "level-home", "capacity"]);
			// (to the overview: the back row faded where it is, the overview's button put)
			change(() -> x.sidebar.show(""), ["level-bar", "level-home"]);
			equals(ui.root.find("level-back").style.opacity, 0.0);
			change(() -> x.sidebar.show("tests/fixtures"), ["level-bar", "level-home"]);
			equals(ui.root.find("level-back").style.opacity, 1.0);
		});
		test("clicked again on the way: turned from where it is, not restarted", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			x.sidebar.back();
			frame(ui);
			at(ui, 0);
			for (_ in 0...4)
				at(ui, 1 / 60);
			var going = pane(ui, "fixtures").x;
			assert(going > 10, 'on its way out: $going');
			// (back into the level just left: the same pane, turned)
			x.sidebar.show("tests/fixtures");
			frame(ui);
			at(ui, 1 / 60);
			var turned = pane(ui, "fixtures").x;
			assert(Math.abs(turned - going) < 60, 'from where it was: $going then $turned');
			equals(panes(ui).length, 2);
			var n = 0;
			while (panes(ui).length > 1 && n++ < 60)
				at(ui, 1 / 60);
			equals(panes(ui).length, 1);
			equals(panes(ui)[0].title, "fixtures");
			equals(panes(ui)[0].x, 0.0);
		});
		test("Back clicked fast: no queue, the ones between never shown, settled on the last", () -> {
			var w = new Levels();
			w.x.browser.go("/r/a/b/c/d");
			w.settle();
			var seen = [];
			for (_ in 0...5) {
				w.x.browser.up();
				w.wait(20);
				var p = w.panes();
				assert(p.length <= 2, 'at most two levels: $p');
				for (t in p)
					if (!seen.contains(t)) seen.push(t);
			}
			// (from c's level to the overview's by way of r's: a, b only on the way, if at all)
			var t = 0.0;
			while (w.panes().length > 1 && t < 0.6) {
				w.wait(1000 / 60);
				t += 1 / 60;
			}
			assert(t < 0.6, 'settled in $t s');
			equals(w.panes(), [w.title()]);
		});
		// (the way in, as the user took it: the levels back goes through, last
		// first, "" the overview; null when the main view moved the level)
		test("bursts of Back, Forward, Go and the way in: two levels at most, back retracing it, settled on the last", () -> stateful({
			setup: () -> {
				var w = new Levels();
				w.settle();
				w;
			},
			steps: [
				{name: "go", run: (w, c) -> {
					w.x.browser.go(c.draw(pick(["/r", "/r/a", "/r/a/b", "/r/a/b/c", "/r/a/b/c/d", "/r/x", "/v/w/u"])));
					w.way = null;
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "back", run: (w, c) -> {
					w.x.browser.goBack();
					w.way = null;
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "forward", run: (w, c) -> {
					w.x.browser.goForward();
					w.way = null;
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "sidebar's back", run: (w, c) -> {
					var to = w.way == null ? null : w.way.pop();
					w.x.sidebar.back();
					if (to != null) equals(w.x.sidebar.level.value, to, "back along the way in");
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "sidebar's level", run: (w, c) -> {
					var l = c.draw(pick(["", "/r", "/r/a", "/r/a/b"]));
					w.x.sidebar.show(l);
					w.way = l == "" ? [] : null;
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "a place or a device", run: (w, c) -> {
					w.x.choose(c.draw(pick(["/r/a/b", "/v"])));
					w.way = [""];
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "into a folder (›)", run: (w, c) -> {
					var s = w.x.sidebar, r = s.rows.value;
					if (s.level.value == "" || r.length == 0) return;
					var at = s.level.value;
					s.show(r[c.draw(int(0, r.length - 1))].path);
					if (w.way != null) w.way.push(at);
					w.wait(c.draw(int(0, 50)));
				}},
				{name: "a folder clicked twice", run: (w, c) -> {
					// (in place first: a level sliding in takes no presses; a fresh click)
					w.settle();
					w.wait(500);
					var s = w.x.sidebar, r = s.rows.value;
					if (s.level.value == "" || r.length == 0) return;
					var at = s.level.value, row = r[c.draw(int(0, r.length - 1))];
					var gap = c.draw(pick([0, 100, 300, 440, 460, 700])), dx = c.draw(int(0, 8)), p = w.spot(row.name);
					w.gone.resize(0);
					w.clickAt(p.x, p.y);
					// (a device's row: its own level at once, sliding under the pointer)
					var moved = s.level.value != at;
					w.wait(gap);
					w.clickAt(p.x + dx, p.y);
					// (the folder shown, nothing else: the second press on another row none)
					for (d in w.gone)
						equals(d, row.path, "one folder shown");
					if (moved) {
						w.way = null;
						equals(s.level.value, row.path, "the device's level");
					} else if (gap < 450 && dx < 5) {
						if (w.way != null) w.way.push(at);
						equals(s.level.value, row.path, "into its level");
					} else equals(s.level.value, at, "two clicks");
					w.wait(c.draw(int(0, 50)));
				}}
			],
			check: w -> {
				assert(w.panes().length <= 2, 'at most two levels drawn: ${w.panes()}');
				// (the back row says where it goes)
				if (w.way != null && w.way.length > 0) {
					var to = w.way[w.way.length - 1];
					equals(w.back(), to == "" ? "Overview" : w.x.sidebar.title(to), 'the back row at ${w.x.sidebar.level.value}');
				}
			},
			teardown: w -> {
				// (the last step's writes landed: a case shrunk may end inside one)
				w.wait(0);
				var t = 0.0;
				while (w.panes().length > 1 && t < 0.6) {
					w.wait(1000 / 60);
					t += 1 / 60;
				}
				assert(t < 0.6, 'settled in $t s');
				equals(w.panes(), [w.title()], 'at ${w.x.sidebar.level.value}');
			}
		}, {cases: 60, steps: 15}));
		test("a folder's double click: into its level when quick and near, shown once, a third click on none", () -> property(c -> {
			gap: c.draw(int(0, 900)),
			dx: c.draw(int(0, 8)),
			third: c.draw(int(0, 1200))
		}, k -> {
			// (a gap on the line: either way; a third click once its level is in place, or before)
			assume(Math.abs(k.gap - 450) > 2 && (k.third < 448 || k.third > 700));
			var w = new Levels();
			// (another folder shown: a's click shows it; under a, b's row of a's level)
			w.x.browser.go("/r/x");
			w.settle();
			equals(w.x.sidebar.level.value, "/r");
			w.gone.resize(0);
			var p = w.spot("a");
			w.clickAt(p.x, p.y);
			w.wait(k.gap);
			w.clickAt(p.x + k.dx, p.y);
			var double = k.gap < 450 && k.dx < 5;
			equals(w.x.sidebar.level.value, double ? "/r/a" : "/r");
			w.wait(k.third);
			w.clickAt(p.x, p.y);
			w.settle();
			// (the third: of a triple, none; later, a click on b; after two clicks, their double)
			var next = k.third < 448 && k.dx < 5;
			equals(w.gone, double && !next ? ["/r/a", "/r/a/b"] : ["/r/a"]);
			equals(w.x.sidebar.level.value, double || next ? "/r/a" : "/r");
			equals(w.panes(), [w.title()]);
		}, {cases: 100}));
		test("back retraces the way in: a place's or a device's to the overview, past it the real parent", () -> {
			var w = new Levels(), s = w.x.sidebar;
			w.settle();
			// (a place chosen: back to the overview, not its parent)
			w.x.choose("/r/a/b");
			w.settle();
			equals(w.back(), "Overview");
			s.show("/r/a/b/c");
			w.settle();
			equals(w.back(), "B");
			s.back();
			w.settle();
			equals(s.level.value, "/r/a/b");
			s.back();
			w.settle();
			equals(s.level.value, "");
			// (a device: the same)
			w.x.choose("/v");
			w.settle();
			equals(w.back(), "Overview");
			s.show("/v/w");
			w.settle();
			equals(w.back(), "V");
			s.back();
			s.back();
			w.settle();
			equals(s.level.value, "");
			// (entered by the main view: the real parent)
			w.x.browser.go("/r/a/b/c");
			w.settle();
			equals(s.level.value, "/r/a/b");
			equals(w.back(), "a");
			// (a place's, gone up past it in the main view: the real parent again)
			w.x.choose("/r/a/b");
			w.x.browser.go("/r/a/b/c/d");
			w.settle();
			equals(w.back(), "B");
			w.x.browser.go("/r/a");
			w.x.browser.go("/r/a/b/c");
			w.settle();
			equals(s.level.value, "/r/a/b");
			equals(w.back(), "a");
		});
		test("reduced motion: a cross-fade in place", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			Clock.reducedMotion = true;
			x.sidebar.back();
			frame(ui);
			at(ui, 0);
			at(ui, 0.05);
			var a = pane(ui, "Macintosh HD"), b = pane(ui, "fixtures");
			equals([a.x, b.x], [0.0, 0.0]);
			assert(a.o > 0 && a.o < 1 && b.o > 0 && b.o < 1, 'crossing: ${a.o}, ${b.o}');
			Clock.reducedMotion = false;
			Clock.finish();
			frame(ui);
			equals(panes(ui).length, 1);
		});
	});
}

// (an explorer of nested folders in a window: /r/a/b/c/d, /r/x)
private class Levels {
	public final x:Explorer;
	// (the folders the main view went to)
	public final gone:Array<String> = [];
	// (the way in, the stateful property's model of it)
	public var way:Null<Array<String>> = null;
	final ui:Ui;
	var t = 0.0;

	public function new() {
		t = 0;
		Ui.now = () -> t;
		Clock.tick(0);
		var files = new MemoryFiles().add("/r/a/b/c/d/").add("/r/x/").add("/r/a/b/c/d/f.png", haxe.io.Bytes.alloc(1)).add("/v/w/u/");
		x = new Explorer(files, (_, _, _) -> {}, [{kind: Pictures, name: "B", path: "/r/a/b"}],
			[{name: "V", path: "/v", total: 0, free: 0, removable: true, network: false, root: true}], Preview.now);
		x.browser.go("/r/a");
		var on = x.browser.onDir;
		x.browser.onDir = d -> {
			gone.push(d);
			on(d);
		};
		ui = new Ui(new StoryText(), 1100, 700);
		Render.render(Shell.view(x), ui.root);
		frame();
	}

	function frame() {
		Graph.flush();
		ui.update();
		Graph.flush();
		ui.update();
	}

	// (ms of frames)
	public function wait(ms:Float) {
		var end = t + ms / 1000;
		frame();
		while (t < end - 1e-9) {
			t = Math.min(end, t + 1 / 60);
			Clock.tick(t);
			frame();
		}
	}

	public function settle() {
		wait(200);
		Clock.finish();
		frame();
		t = Clock.now;
		wait(200);
	}

	// (the levels drawn: each pane's title, "" the overview's)
	public function panes():Array<String> {
		var body = ui.root.find("sidebar-body");
		return [for (n in body.children) if (n.tag == "sidebar-pane") {
			var title = n.find("level-title");
			title == null ? "" : text(title);
		}];
	}

	// (the back row's label as shown)
	public function back():String
		return text(ui.root.find("level-back"));

	// (a folder's row of the level shown, clicked dx points right of its middle)
	public function click(name:String, dx:Float) {
		var p = spot(name);
		clickAt(p.x + dx, p.y);
	}

	public function clickAt(px:Float, py:Float) {
		ui.pointerDown(px, py, 1);
		ui.pointerUp(px, py, 1);
		frame();
	}

	// (the middle of a folder's row of the level shown)
	public function spot(name:String):{x:Float, y:Float} {
		var row:Null<helder.ui.Node> = null;
		function named(n:helder.ui.Node):Bool
			return Std.isOfType(n, TextNode) && (cast n : TextNode).text == name || Lambda.exists(n.children, named);
		function walk(n:helder.ui.Node) {
			if (n.slot == "side-row" && named(n)) row = n;
			for (c in n.children)
				walk(c);
		}
		walk(ui.root.find("sidebar-body"));
		var b = row.windowBounds();
		return {x: b.x + b.width / 2, y: b.y + b.height / 2};
	}

	// (the level's title now)
	public function title():String
		return x.sidebar.level.value == "" ? "" : x.sidebar.title(x.sidebar.level.value);

	static function text(n:helder.ui.Node):String
		return Std.isOfType(n, TextNode) ? (cast n : TextNode).text : [for (c in n.children) text(c)].join("");
}
