package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The sidebar: its volume's card (its name, how full, what is free of
// what), and a level entered sliding in from its side, a deeper one from
// the right, an enclosing one from the left (reduced motion: no slide)
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
			return {ui: ui, x: x};
		}
		function at(ui:Ui, dt:Float) {
			t += dt;
			Clock.tick(t);
			frame(ui);
		}
		// (the body's offset now: its transform's translation, 0 none)
		function shift(ui:Ui):Float {
			var tr = ui.root.find("sidebar-body").style.transform;
			return tr == null ? 0 : tr.toMatrix(1, 1).e;
		}
		function text(ui:Ui, tag:String):String {
			var n = ui.root.find(tag);
			return n == null ? "" : Std.isOfType(n, TextNode) ? (cast n : TextNode).text : [for (c in n.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join("");
		}
		test("the volume's card: its name, how full, what is free of what", () -> {
			var ui = mount().ui;
			equals(text(ui, "capacity-name"), "Macintosh HD");
			equals(text(ui, "capacity-used"), "91%");
			equals(text(ui, "capacity-free"), "45.3 GB free of 494.0 GB");
			assert(ui.root.find("capacity").style.radius > 0, "a card's corners");
		});
		test("a deeper level from the right, an enclosing one from the left", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			equals(x.sidebar.level.value, "tests/fixtures");
			x.sidebar.back();
			frame(ui);
			at(ui, 0);
			at(ui, 0.01);
			var back = shift(ui);
			x.sidebar.show("tests/fixtures");
			frame(ui);
			at(ui, 0);
			at(ui, 0.01);
			var deeper = shift(ui), half = ui.root.find("sidebar-body").style.opacity;
			assert(back < -2, 'back: from the left ($back)');
			assert(deeper > 2, 'deeper: from the right ($deeper)');
			assert(half > 0 && half < 1, 'fading in ($half)');
			Clock.finish();
			frame(ui);
			equals(shift(ui), 0.0);
			equals(ui.root.find("sidebar-body").style.opacity, 1.0);
		});
		test("reduced motion: no slide", () -> {
			var m = mount(), ui = m.ui, x = m.x;
			Clock.reducedMotion = true;
			x.sidebar.back();
			frame(ui);
			at(ui, 0);
			at(ui, 0.05);
			equals(shift(ui), 0.0);
			var o = ui.root.find("sidebar-body").style.opacity;
			assert(o > 0 && o < 1, 'a fade ($o)');
			Clock.reducedMotion = false;
			Clock.finish();
		});
	});
}
