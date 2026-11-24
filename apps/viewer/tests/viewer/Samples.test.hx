package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Key;
import helder.ui.Ui;
import helder.view.Render;

// The web build's sample folder as its browser has it (Fixtures.samples:
// Samples' files, decoded from their bytes as the web's decodes are): at
// Samples, its files and subfolder listed, the sidebar's place, the PDF
// opened with its pages, a photo of the subfolder full size
function tests() {
	describe("Samples", () -> {
		beforeEach(() -> helder.ui.actions.Keymap.mac = false);
		test("the folder, the PDF, a photo of the subfolder", () -> {
			var x = Fixtures.samples(), viewer = x.viewer;
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function frame() {
				helder.view.graph.Graph.flush();
				ui.update();
				helder.view.graph.Graph.flush();
				ui.update();
			}
			x.browser.go(Samples.ROOT);
			frame();
			var names = [for (e in x.browser.items.value) e.name];
			equals(names[0], "More");
			for (n in ["About Viewer.pdf", "Chimes.m4a", "Murmuration.jpg", "Planet.jpg", "Starlings.mp4"])
				assert(names.contains(n), n);
			equals(x.sidebar.title(Samples.ROOT), "Samples");
			equals(x.sidebar.level.value, Samples.ROOT);
			equals([for (r in x.sidebar.rows.value) r.name], ["More"]);
			x.open("About Viewer.pdf");
			frame();
			equals(viewer.state.peek(), Shown);
			equals(viewer.pages, 3);
			assert(StringTools.startsWith(viewer.title.peek(), "About Viewer.pdf · 1 / "), viewer.title.peek());
			assert(StringTools.endsWith(viewer.title.peek(), " · page 1 / 3"), viewer.title.peek());
			ui.keyDown(Key.ESCAPE, 0);
			frame();
			equals(x.full.value, false);
			x.open("More");
			frame();
			equals(x.browser.dir.value, Samples.ROOT + "/More");
			x.open("Seahorse valley.jpg");
			frame();
			equals(viewer.state.peek(), Shown);
			assert(StringTools.endsWith(viewer.title.peek(), " · 1200×900"), viewer.title.peek());
		});
	});
}
