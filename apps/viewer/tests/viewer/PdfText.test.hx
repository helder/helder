package viewer;

import helder.pdf.Pdf;
import helder.story.StoryText;
import helder.test.Gen;
import helder.test.Test;
import helder.os.Mods;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;
import helder.pdf.PageText;
import helder.pdf.ui.PdfText;

using StringTools;

// A PDF's text selectable over its pages (tests/fixtures/text/text.pdf: two
// paragraphs; a turned page with a line up its side and codes that map to
// nothing): a drag copied, a double click a word, a triple a line, Mod+A
// every page's, the I-beam over text alone, a range copied as it is, the
// same characters selected after a zoom
function tests() {
	describe("PDF text", () -> {
		beforeEach(() -> helder.ui.actions.Keymap.mac = false);
		var path = "tests/fixtures/text/text.pdf";
		function open() {
			var x = new Explorer(Fixtures.files(["tests/fixtures/text"]), (key, side, done) -> done(Decode.file({path: key, side: side})), [], [],
				Preview.now);
			var ui = new Ui(new StoryText(), 800, 600);
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function frame() {
				helder.view.graph.Graph.flush();
				ui.update();
				helder.view.graph.Graph.flush();
				ui.update();
			}
			x.start(path);
			frame();
			// (each press a second after the last: no double click unless asked)
			var t = 100.0;
			Ui.now = () -> t;
			function press(a:{x:Float, y:Float}, b:{x:Float, y:Float}, clicks = 1) {
				for (_ in 0...clicks) {
					ui.pointerDown(a.x, a.y, 1);
					t += 0.1;
				}
				ui.pointerMove(b.x, b.y);
				ui.pointerUp(b.x, b.y, 1);
				t += 1;
				frame();
			}
			return {x: x, ui: ui, frame: frame, doc: x.viewer.pdf.peek(), press: press};
		}
		function pages(ui:Ui):Array<Node>
			return ui.root.find("pdf-text").children;
		// (a point on index i: in its character's box at its start, else in the one before's at its end)
		function at(n:Node, i:Int):{x:Float, y:Float} {
			var t = (cast n : PdfText).text, b = t.boxes, k = i * 6, f = 0.02;
			if (k >= b.length || Math.isNaN(b[k])) {
				k -= 6;
				f = 0.98;
			}
			var r = n.windowBounds(), z = r.width / (cast n : PdfText).points;
			return {x: r.x + (b[k] + b[k + 2] * f + b[k + 4] / 2) * z, y: r.y + (b[k + 1] + b[k + 3] * f + b[k + 5] / 2) * z};
		}
		afterEach(() -> Ui.now = haxe.Timer.stamp);

		test("a page's text and a box for each of its characters but the gaps", () -> {
			var doc = Pdf.open(sys.io.File.getBytes(path));
			for (pg in doc.pages) {
				var t = PageTexts.of(Pdf.runs(pg));
				equals(t.text, Pdf.text(pg));
				equals(t.boxes.length, t.text.length * 6);
			}
			var t = PageTexts.of(Pdf.runs(doc.pages[0]));
			// (H's box: 72 points in, at 0.5 em of 12; the newline none)
			equals([t.boxes[0], t.boxes[2]], [72.0, 6.0]);
			var end:Float = t.boxes[t.text.indexOf("\n") * 6];
			assert(Math.isNaN(end), "no box for a line's end");
		});
		test("a drag copied; a word, a line; Mod+A every page's", () -> {
			var o = open(), ui = o.ui;
			var p = pages(ui);
			equals(p.length, 2);
			equals(p[0].selectableText(), "The quick brown fox\njumps over the lazy dog.\nA second paragraph\nof two lines.");
			o.press(at(p[0], 4), at(p[0], 25));
			equals(ui.selectedText(), "quick brown fox\njumps");
			ui.keyDown("c".code, Mods.CONTROL);
			var copied = "";
			ui.clipboard.read(s -> copied = s);
			equals(copied, "quick brown fox\njumps");
			// (a right click on it: kept, the menu's Copy enabled)
			var r = at(p[0], 6);
			ui.pointerDown(r.x, r.y, 3);
			ui.pointerUp(r.x, r.y, 3);
			o.frame();
			equals(ui.selectedText(), "quick brown fox\njumps");
			equals(ui.actionState(helder.ui.actions.Actions.StandardAction.Copy), Enabled);
			ui.keyDown(helder.ui.Key.ESCAPE, 0);
			o.frame();
			o.press(at(p[0], 11), at(p[0], 11), 2);
			equals(ui.selectedText(), "brown");
			o.press(at(p[0], 11), at(p[0], 11), 3);
			equals(ui.selectedText(), "The quick brown fox");
			// (Mod+A: the document, its other page read for it)
			ui.keyDown("a".code, Mods.CONTROL);
			o.frame();
			equals(ui.selectedText(), "The quick brown fox\njumps over the lazy dog.\nA second paragraph\nof two lines.\n\nA turned page\nUp the side\n and");
		});
		test("the I-beam over text alone; a press beside it selects nothing", () -> {
			var o = open(), ui = o.ui, p = pages(ui)[0];
			var a = at(p, 1);
			ui.pointerMove(a.x, a.y);
			equals(ui.cursor(), helder.ui.Cursor.Text);
			var b = p.windowBounds();
			ui.pointerMove(b.x + 10, b.y + b.height - 10);
			notEquals(ui.cursor(), helder.ui.Cursor.Text);
			o.press({x: b.x + 10, y: b.y + b.height - 10}, {x: b.x + 10, y: b.y + b.height - 10});
			equals(ui.textSelection, null);
		});
		test("the same characters selected after a zoom", () -> {
			var o = open(), ui = o.ui, p = pages(ui)[0];
			o.press(at(p, 4), at(p, 15));
			var text = ui.selectedText(), range = ui.textSelection.rangeIn(p, p.selectableText().length);
			for (k in [2.0, 0.4]) {
				o.doc.zoomBy(k, 400, 300);
				o.frame();
				equals(ui.selectedText(), text);
				equals(ui.textSelection.rangeIn(p, p.selectableText().length), range);
				// (and the caret where the text is drawn now: the page's box scaled)
				var b = p.windowBounds(), c = p.selectableCaret(0);
				approx((c.x - b.x) / b.width, 72 / 612, 1e-6);
			}
		});
		test("a range dragged over copies exactly its characters", () -> {
			var o = open(), ui = o.ui;
			property(c -> {page: c.draw(int(0, 1)), a: c.draw(int(0, 200)), b: c.draw(int(0, 200))}, r -> {
				var p = pages(ui)[r.page];
				o.doc.goTo(r.page);
				o.frame();
				var t = p.selectableText(), a = r.a % (t.length + 1), b = r.b % (t.length + 1);
				// (a point of each: a character with a box, or a line's end after one)
				assume(p.selectableCaret(a) != null && p.selectableCaret(b) != null);
				o.press(at(p, a), at(p, b));
				equals(ui.selectedText(), t.substring(Std.int(Math.min(a, b)), Std.int(Math.max(a, b))));
			}, {cases: 60});
		});
	});
}
