package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Node;
import helder.ui.Ui;
import helder.view.Render;

// The window's content within the window at desktop sizes, with a large
// folder among many: the panels and the path bar end at its bottom, the
// sidebar's level of 30 folders scrolls (its content's height pushed the
// window's content 450 points past a 488-point window's bottom once)
function tests() {
	describe("Window", () -> {
		function bottom(n:Null<Node>):Float
			return n == null ? -1 : n.absY + n.height;
		function big():Explorer {
			Kinds.utc = true;
			Tiles.forget();
			var m = new MemoryFiles();
			m.add("/home/");
			for (i in 0...30)
				m.add('/home/folder $i/');
			for (i in 0...300)
				m.add('/home/folder 0/file $i.txt', haxe.io.Bytes.ofString("x"));
			return new Explorer(m, (_, _, done) -> {}, [], [], (_, _) -> () -> {});
		}
		for (size in [{w: 1000, h: 488, layout: Browser.Layout.List}, {w: 1212, h: 592, layout: Browser.Layout.Grid}, {w: 1440, h: 900, layout: Browser.Layout.List}])
			test('${size.w} x ${size.h}, as a ${size.layout}: everything ends at the window\'s bottom', () -> {
				var x = big(), ui = new Ui(new StoryText(), size.w, size.h);
				Render.render(Shell.view(x, () -> helder.ui.SizeClass.Expanded), ui.root);
				x.start("/home/folder 0");
				x.browser.layout(size.layout);
				for (_ in 0...2) {
					helder.view.graph.Graph.flush();
					ui.update();
				}
				var r = ui.root, h:Float = size.h;
				equals(x.sidebar.rows().length, 30);
				for (t in ["window", "browser", "sidebar", "main", "pathbar", "inspector"])
					equals('$t ${bottom(r.find(t))}', '$t $h');
				var bar = r.find("pathbar");
				assert(bar.absY >= 0 && bar.height == ContentView.FOOT, '${bar.absY} ${bar.height}');
				var side = r.find("scroll");
				equals(bottom(side), h);
				assert(side.contentHeight > side.height, 'the sidebar scrolls: ${side.contentHeight} in ${side.height}');
			});
	});
}
