package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The sidebar: its volume's card (its name, how full, what is free of
// what); going between levels as a push, both panes together on the
// spring at whole-point offsets, settled soon, the old one gone after;
// clicked again on the way, turned from where they are (no third pane, no
// restart); reduced motion: a cross-fade in place
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
			// (its first level landed and settled)
			Clock.finish();
			frame(ui);
			t = Clock.now;
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
