package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Ui;
import helder.view.Render;

// The inspector while the browser's items change under it (a search's
// keystrokes): the selected entry's preview asked for once, its nodes kept
function tests() {
	describe("Inspector", () -> {
		test("search keeps the selected entry's preview", () -> {
			Kinds.utc(true);
			Tiles.forget();
			var m = Fixtures.files(["tests/fixtures/folder"]), asked = [];
			var x = new Explorer(m, (path, side, done) -> done(Decode.file({path: path, side: side})), [], [], (path, done) -> {
				asked.push(path);
				Preview.now(path, done);
			});
			var ui = new Ui(new StoryText(), 1100, 700);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function frame() {
				helder.view.graph.Graph.flush();
				ui.update();
				helder.view.graph.Graph.flush();
				ui.update();
			}
			x.start("tests/fixtures/folder");
			frame();
			x.browser.select("alpha.png");
			frame();
			equals(asked.length, 1);
			var image = ui.root.find("preview-image"), details = ui.root.find("details");
			notEquals(image, null);
			x.browser.searching(true);
			for (q in ["a", "al", "alp"]) {
				x.browser.search(q);
				frame();
			}
			equals(asked.length, 1);
			equals(ui.root.find("preview-image") == image, true);
			equals(ui.root.find("details") == details, true);
			// (another entry: its own)
			x.browser.search("");
			x.browser.select("lossy.webp");
			frame();
			equals(asked, ["tests/fixtures/folder/alpha.png", "tests/fixtures/folder/lossy.webp"]);
		});
	});
}
