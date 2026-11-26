import helder.gfx.Color;
import helder.ui.*;
import helder.ui.UiWindow;

// The browser as the compositor (web-layers.mjs: wasm32-wasi in headless
// Chromium): a 400x300 window, a header over a list of 60 rows (its
// content a layer of the page's in its scroll view, taller than the
// window: tiles), a round button over the list (what is over it: a layer
// of its own), a box in the header that M slides 200 points and back (a
// transition of 1 s: a layer that moves on its own). B keeps the program
// busy 1.5 s. After each frame whose state changed it prints "layers
// list=y | busy=n | slid=n | bars=page|drawn" (the list's scrollbars the
// page's own, or drawn).
class WebLayersPage {
	static function main() {
		var w = new UiWindow("Layers", 400, 300);
		var page = new Node("page");
		page.style.set({width: 400, height: 300, background: Color.rgb(0xffffff)});
		var header = new TextNode("Layers");
		header.style.set({height: 40, flexShrink: 0, padding: 10, fontSize: 16, color: Color.rgb(0xffffff), background: Color.rgb(0x1d4ed8)});
		var list = new Node("list");
		list.style.set({flexGrow: 1, overflow: Scroll, background: Color.rgb(0xffffff)});
		for (i in 0...60) {
			var r = new TextNode('Row $i: the quick brown fox');
			r.style.set({height: 30, flexShrink: 0, padding: 6, fontSize: 14, background: Color.rgb(i % 2 == 0 ? 0xf4f4f5 : 0xfef3c7)});
			list.append(r);
		}
		var fab = new Node("fab");
		fab.style.set({position: Absolute, right: 20, bottom: 20, width: 44, height: 44, borderRadius: 22, background: Color.rgb(0xdc2626)});
		var box = new Node("box");
		box.style.set({position: Absolute, left: 120, top: 8, width: 24, height: 24, borderRadius: 4, background: Color.rgb(0xfacc15)});
		box.style.transform = Transform.parse("translate(0px, 0px)");
		box.style.transition = Transition.parse("transform 1s linear");
		page.append(header);
		page.append(list);
		page.append(fab);
		page.append(box);
		w.root.append(page);
		var busy = 0, slid = 0;
		page.focusable = true;
		page.onKeyDown = e -> if (e.key == "m".code) {
			slid++;
			box.style.transform = Transform.parse(slid % 2 == 1 ? "translate(200px, 0px)" : "translate(0px, 0px)");
		} else if (e.key == "b".code) {
			busy++;
			var end = haxe.Timer.stamp() + 1.5;
			while (haxe.Timer.stamp() < end) {}
			w.ui.requestFrame();
		}
		var last = "";
		w.onFrame = () -> {
			var bars = @:privateAccess w.ui.barsOf;
			var s = 'layers list=${list.scrollY} | busy=$busy | slid=$slid | bars=${bars != null && bars(list) ? "page" : "drawn"}';
			if (s != last) {
				last = s;
				Sys.println(s);
			}
		};
		UiWindow.run();
	}
}
