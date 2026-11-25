import helder.ui.*;
import helder.ui.UiWindow;
import helder.view.Render;
import fixtures.AccessFixture;

// AccessFixture's controls in a browser (web-access.mjs: wasm32-wasi in
// headless Chromium), for the ARIA mirror in the canvas: after each frame
// whose state changed it prints it ("state saved=0 open=false row=0
// volume=0.5").
class WebAccessPage {
	static function main() {
		var w = new UiWindow({title: "fixture", width: 400, height: 640});
		w.ui.policy["text-field"] = Host.Drawn;
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var last = "";
		w.onFrame = () -> {
			var s = 'state saved=${f.saved} open=${f.open.peek()} row=${f.row.peek()} volume=${f.volume.peek()}';
			if (s != last) Sys.println(s);
			last = s;
		};
		UiWindow.run();
	}
}
