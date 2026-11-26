import helder.os.Mods;
import helder.gfx.Color;
import helder.ui.*;
import helder.ui.UiWindow;

// The browser's scroll views driving the scrollers (web-scroll.mjs:
// wasm32-wasi in headless Chromium): a 400x300 window whose page scrolls
// down (20 rows, 40 high), a row of five cards scrolling sideways at its
// top, a "slider" (following the pointer's moves) and a "button" among the
// rows. After each frame whose state changed it prints it: "scroll page=y
// row=x | clicks=n | moves=n | wheels=n" (wheels: those the page heard with
// Control, a pinch's).
class WebScrollPage {
	static function main() {
		var w = new UiWindow("Scroll", 400, 300);
		var page = new Node("page"), row = new Node("row");
		page.style.set({width: 400, height: 300, overflow: Scroll, background: Color.rgb(0xffffff)});
		row.style.set({height: 80, flexShrink: 0, overflow: Scroll, flexDirection: Row, scrollbarWidth: None});
		for (i in 0...5) {
			var c = new Node("card" + i);
			c.style.set({width: 120, height: 80, flexShrink: 0, background: Color.rgb(i % 2 == 0 ? 0xdbeafe : 0xfde68a)});
			row.append(c);
		}
		page.append(row);
		var clicks = 0, moves = 0, wheels = 0, popupWheels = 0;
		for (i in 0...20) {
			var r = new Node(i == 2 ? "slider" : i == 3 ? "button" : "item" + i);
			r.style.set({height: 40, flexShrink: 0, background: Color.rgb(i % 2 == 0 ? 0xf4f4f5 : 0xe4e4e7)});
			if (i == 2) r.onPointerMove = _ -> {
				moves++;
				w.ui.requestFrame();
			}
			if (i == 3) r.onClick = _ -> {
				clicks++;
				w.ui.requestFrame();
			}
			page.append(r);
		}
		page.onWheel = e -> if (e.mods & Mods.CONTROL != 0) {
			wheels++;
			e.preventDefault();
			w.ui.requestFrame();
		}
		w.root.append(page);
		// (M opens a popup over the page, Escape closes it: the page's scroll view covered meanwhile)
		var menu = new Popup("menu");
		menu.onWheel = _ -> {
			popupWheels++;
			w.ui.requestFrame();
		};
		menu.style.set({width: 160, height: 120, background: Color.rgb(0xffffff)});
		page.focusable = true;
		page.onKeyDown = e -> {
			if (e.key == "m".code && menu.parent == null) w.ui.open(menu) else if (e.key == Key.ESCAPE && menu.parent != null) w.ui.close(menu);
			w.ui.requestFrame();
		};
		var last = "";
		w.onFrame = () -> {
			var s = 'scroll page=${page.scrollY} row=${row.scrollX} | clicks=$clicks | moves=$moves | wheels=$wheels | popup=$popupWheels';
			if (s != last) {
				last = s;
				Sys.println(s);
			}
		};
		UiWindow.run();
	}
}
