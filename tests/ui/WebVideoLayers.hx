import helder.media.ui.VideoNode;
import helder.ui.*;
import helder.ui.UiWindow;

// A video between the browser's layers (web-video-layers.mjs: wasm32-wasi
// in headless Chromium): a 400x300 window, a <Video> of long.webm on its
// system layer (a canvas of the page: helder.media's WebSample), a box
// drawn after it over its corner (a layer over the video's), and a list
// beside it (a layer in its scroll view). Prints "video frames=n layer=b"
// as frames show.
class WebVideoLayers {
	static function main() {
		var w = new UiWindow("Video", 400, 300);
		var page = new Node("page");
		page.style.set({width: 400, height: 300, background: Color.rgb(0x333333)});
		var v = new VideoNode();
		v.style.set({position: Absolute, left: 20, top: 20, width: 240, height: 180});
		v.layer = true;
		v.muted = true;
		v.loop = true;
		v.autoplay = true;
		v.open("long.webm");
		var box = new Node("box");
		box.style.set({position: Absolute, left: 200, top: 150, width: 80, height: 80, background: Color.rgb(0xdc2626)});
		var list = new Node("list");
		list.style.set({position: Absolute, left: 290, top: 20, width: 100, height: 260, overflow: Scroll, background: Color.rgb(0xffffff)});
		for (i in 0...30) {
			var r = new Node();
			r.style.set({height: 30, shrink: 0, background: Color.rgb(i % 2 == 0 ? 0xf4f4f5 : 0xfef3c7)});
			list.append(r);
		}
		page.append(v);
		page.append(box);
		page.append(list);
		w.root.append(page);
		var frames = 0, last = -1.0, said = "";
		w.onFrame = () -> {
			var p = v.player, f = p == null ? null : p.shown;
			if (f != null && f.time != last) {
				last = f.time;
				frames++;
			}
			var s = @:privateAccess v.sample, on = s != null && s.showing;
			var line = 'video frames=${frames > 5 ? "many" : Std.string(frames)} layer=$on';
			if (line != said) {
				said = line;
				Sys.println(line);
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
	}
}
