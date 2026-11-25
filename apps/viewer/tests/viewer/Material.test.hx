package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Color;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// The sidebar's material: asked for on macOS, Windows 11 (22H2 on) and
// KDE, not on Windows 10, GNOME nor elsewhere; with it the window clear
// and the sidebar drawing no background, the folder's side and its panels
// opaque; without it (or on a tablet's width) the window's canvas as ever
function tests() {
	describe("Material", () -> {
		test("asked for where the system has the sidebar's", () -> {
			equals(Shell.material("Mac", "15.4", ""), true);
			equals(Shell.material("Windows", "10.0.22621", ""), true);
			equals(Shell.material("Windows", "10.0.26100", ""), true);
			equals(Shell.material("Windows", "10.0.22000", ""), false);
			equals(Shell.material("Windows", "10.0.19045", ""), false);
			equals(Shell.material("Windows", "", ""), false);
			equals(Shell.material("Linux", "", "KDE"), true);
			equals(Shell.material("Linux", "", "ubuntu:GNOME"), false);
			equals(Shell.material("Linux", "", ""), false);
			equals(Shell.material("BSD", "", "KDE"), false);
		});
		function mount(material:Bool, width:Float):Ui {
			Ui.now = () -> 0.0;
			var x = Fixtures.explorer();
			x.start("tests/fixtures/folder");
			var ui = new Ui(new StoryText(), width, 700);
			Render.render(Shell.view(x, null, () -> material), ui.root);
			Graph.flush();
			ui.update();
			return ui;
		}
		function opaque(n:Node):Bool {
			var c = n.style.background;
			return c.isToken || c.a == 255;
		}
		test("through the sidebar alone", () -> {
			var ui = mount(true, 1100);
			var window = ui.root.find("window"), side = ui.root.find("sidebar");
			equals(window.style.background, Color.TRANSPARENT);
			equals(side.style.background, Color.TRANSPARENT);
			// (the folder's side, its panel and the inspector: opaque)
			assert(opaque(ui.root.find("main").parent), "the folder's side");
			assert(opaque(ui.root.find("main")), "the folder's panel");
			assert(opaque(ui.root.find("inspector")), "the inspector");
			assert(opaque(ui.root.find("viewer")), "the full view");
		});
		test("without it, and on a tablet's width: the canvas", () -> {
			assert(opaque(mount(false, 1100).root.find("window")), "no material");
			assert(opaque(mount(true, 820).root.find("window")), "a tablet's");
		});
	});
}
