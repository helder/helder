package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.ImageNode;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;

// A Markdown document in the viewer, the shell's tree headless on
// MemoryFiles (tests/fixtures/markdown): opened full size among its
// folder's files, its column, words and headings; its links (an anchor
// scrolled to, another document of the folder and a heading of it, a web
// address given to the browser, a missing file left alone); its picture
// decoded as the viewer decodes, a remote one's alt text; the source
// (Mod+U, the bar's button); the keys scrolling; the inspector's preview and
// the grid's tile
function tests() {
	describe("Markdown", () -> {
		beforeEach(() -> helder.ui.actions.Keymap.mac = false);
		var dir = "tests/fixtures/markdown";
		function all(n:Node, slot:String, out:Array<Node>):Array<Node> {
			if (n.slot == slot) out.push(n);
			for (c in n.children)
				all(c, slot, out);
			return out;
		}
		function open():{x:Explorer, ui:Ui, frame:Void->Void, urls:Array<String>} {
			var x = Fixtures.explorer([dir]), urls = [];
			x.openUrl = u -> {
				urls.push(u);
				true;
			};
			var ui = new Ui(new StoryText(), 1100, 320);
			ui.scrollDuration = 0;
			Render.render(Shell.view(x), ui.root);
			Shell.attach(ui.root, x);
			function frame() {
				for (_ in 0...2) {
					helder.view.graph.Graph.flush();
					ui.update();
					Clock.finish();
				}
			}
			frame();
			return {x: x, ui: ui, frame: frame, urls: urls};
		}
		test("opened, its column, its picture, its links", () -> {
			var t = open(), x = t.x, viewer = x.viewer;
			x.start('$dir/doc.md');
			t.frame();
			equals(x.full.value, true);
			equals(viewer.state.peek(), Shown);
			equals(viewer.title.peek(), "doc.md · 1 / 3");
			var md = viewer.markdownDoc();
			equals(md.headings, 2);
			equals(viewer.status.peek(), '${md.words} words · Markdown · ${Viewer.size(md.size)} · 1 / 3');
			// (the page's: the inspector, under it, shows the document too)
			var root = t.ui.root.find("markdown-page");
			assert(root != null, "the page");
			equals(all(root, "markdown-h2", []).length, 1);
			var img:ImageNode = cast all(root, "markdown-image", [])[0];
			assert(img.image != null, "the picture decoded");
			equals([for (n in all(root, "markdown-image-alt", [])) (cast n : TextNode).text], ["A remote one"]);
			var links = all(root, "markdown-link", []), scroller = md.view.scroller;
			equals(links.length, 5);
			// (an anchor: its heading scrolled to)
			equals(scroller.scrollY, 0.0);
			links[0].onClick(null);
			t.frame();
			assert(scroller.scrollY > 0, "scrolled to Usage");
			// (a web address: the browser's; a file not there: nothing)
			links[3].onClick(null);
			links[4].onClick(null);
			t.frame();
			equals(t.urls, ["https://example.com"]);
			equals(viewer.title.peek(), "doc.md · 1 / 3");
			// (another document of the folder, at a heading of it)
			links[2].onClick(null);
			t.frame();
			equals(viewer.title.peek(), "other.md · 2 / 3");
			var other = viewer.markdownDoc();
			assert(other.view.scroller.scrollY > 0, "at Install");
			// (the folder's next file from there: the picture)
			t.ui.keyDown(Key.RIGHT, 0);
			t.frame();
			equals(viewer.markdown.peek(), null);
			equals(viewer.title.peek(), "pic.png · 3 / 3 · 13×11");
			t.ui.keyDown(Key.ESCAPE, 0);
			t.frame();
			equals(x.full.value, false);
			equals(x.browser.selected.value, "pic.png");
		});
		test("the source, the keys", () -> {
			var t = open(), x = t.x, viewer = x.viewer;
			x.start('$dir/other.md');
			t.frame();
			var md = viewer.markdownDoc(), page = md.view.scroller;
			equals(t.ui.root.find("markdown-source").style.display, None);
			// (the keys: a line, a screen, the end, the top)
			t.ui.keyDown(Key.DOWN, 0);
			t.frame();
			equals(page.scrollY, MarkdownDoc.LINE);
			t.ui.keyDown(Key.SPACE, 0);
			t.frame();
			assert(page.scrollY > MarkdownDoc.LINE, "a screen down");
			t.ui.keyDown(Key.HOME, 0);
			t.frame();
			equals(page.scrollY, 0.0);
			t.ui.keyDown(Key.END, 0);
			t.frame();
			assert(page.scrollY > 0, "the end");
			// (Mod+U: the source; the bar's button: the document again)
			t.ui.keyDown("u".code, Key.MOD_CONTROL);
			t.frame();
			equals(md.source.peek(), true);
			equals(t.ui.root.find("markdown-doc").style.display, None);
			equals(md.code.model.text(), md.text);
			assert(md.code.model.readOnly);
			x.perform(ToggleSource);
			t.frame();
			equals(md.source.peek(), false);
			equals(x.actionState(ToggleSource), Unchecked);
		});
		test("the inspector's preview, the grid's tile", () -> {
			var t = open(), x = t.x;
			x.browser.go(dir);
			x.browser.inspector(true);
			x.browser.select("doc.md");
			t.frame();
			var root = t.ui.root;
			assert(root.find("preview-page") != null, "the first screen");
			var kind:TextNode = cast root.find("inspector-kind");
			assert(StringTools.startsWith(kind.text, "Markdown document · "), kind.text);
			var titles = [];
			function walk(n:Node) {
				if (n.tag == "document-title") titles.push((cast n : TextNode).text);
				for (c in n.children)
					walk(c);
			}
			walk(root);
			titles.sort(Reflect.compare);
			equals(titles, ["Other", "The document"]);
		});
	});
}
