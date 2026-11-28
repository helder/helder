package ui.fast;

import helder.test.Test;
import helder.ui.fast.*;

// A DOM island in a fast tree: its boxes in the tree's own, its text
// selected across it and the fast nodes around it; its root inheriting the
// island's text.
function tests() {
	describe("islands", () -> {
		test("text selected from a fast node through an island to another", () -> {
			var ui = new helder.ui.Ui(null, 400, 300);
			var root = new Node(Style.of({fontFamily: "Ahem", fontSize: 10, lineHeight: 1, color: 0xFF112233}));
			var before = new TextNode("Before"), after = new TextNode("After");
			var island = new Island(helder.dom.Dom.parse("<!doctype html><style>body { margin: 0 } p { margin: 0 }</style><p>Hello <b>world</b></p>"));
			root.append(before);
			root.append(island);
			root.append(after);
			var tree = new Tree(root);
			tree.fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
			tree.style.flexGrow = 1;
			ui.root.append(tree);
			ui.update();
			// (the island's text in the island's font and colour: its root inherits them)
			var p = tree.rectOf(island);
			equals(p[3], 10);
			var a = tree.rectOf(before), z = tree.rectOf(after);
			ui.pointerMove(a[0] + 1, a[1] + 5);
			ui.pointerDown(a[0] + 1, a[1] + 5, 1);
			ui.pointerMove(z[0] + 49, z[1] + 5);
			ui.pointerUp(z[0] + 49, z[1] + 5, 1);
			equals(ui.selectedText(), "Before\nHello world\nAfter");
			// (assistive technology: the island's text a label in the tree)
			var names = [for (id in ui.accessTree().order) ui.accessTree().nodes.get(id).name];
			equals(names.indexOf("Hello world") >= 0, true);
		});
	});
}
