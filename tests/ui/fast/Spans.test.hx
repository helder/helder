package ui.fast;

import helder.test.Test;
import helder.ui.fast.FastTags.*;
import helder.view.*;
import helder.view.graph.Graph.*;

// A text's spans: its runs and its elements inline boxes in its paragraph.
function tests() {
	describe("spans", () -> {
		test("a text's spans: one paragraph, each run its own style", () -> {
			var ui = new helder.ui.Ui(null, 400, 200), tree:Null<helder.ui.fast.Tree> = null, n = signal(3);
			Render.render(<Fast ref={t -> {
				tree = t;
				t.fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
			}}>
				<text tag="p" fontFamily="Ahem" fontSize={10} lineHeight={1}>Saved <strong fontWeight={700}>{Std.string(n())}</strong> files</text>
			</Fast>, ui.root);
			flush();
			ui.update();
			var p:helder.ui.fast.TextNode = cast tree.root.children()[0];
			equals(p.allText(), "Saved 3 files");
			var strong = p.children().filter(c -> c.tag == "strong")[0];
			equals(@:privateAccess strong.box.kind, Inline);
			equals(@:privateAccess strong.box.style.text.weight, 700);
			equals(@:privateAccess p.box.style.text.weight, 400);
			// (one line: the paragraph's height a line's, its width its 13 characters')
			equals(tree.rectOf(p)[3], 10);
			equals(tree.rectOf(strong)[2], 10);
			n(12);
			flush();
			ui.update();
			equals(p.allText(), "Saved 12 files");
			// (one label for assistive technology, its spans' text in it)
			var names = [for (id in ui.accessTree().order) ui.accessTree().nodes.get(id).name];
			equals(names.indexOf("Saved 12 files") >= 0, true);
		});
	});
}
