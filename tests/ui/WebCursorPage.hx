import helder.ui.*;
import helder.ui.UiWindow;
import helder.view.*;

// The pointer's shape in a browser (web-cursor.mjs: wasm32-wasi in headless
// Chromium): a button, a disabled one, a link, a field and plain text, none
// with a cursor of its own. Once laid out it prints their boxes ("boxes
// save=x,y,w,h off=... link=... field=... plain=...").
class WebCursorPage implements Markup {
	static function main() {
		var w = new UiWindow({title: "Cursor", width: 400, height: 100});
		w.ui.policy["text-field"] = Host.Drawn;
		Render.render(<view flexDirection="row" alignItems="center" columnGap={8} padding={8}>
			<button tag="save" padding={8} onPress={() -> {}}>Save</button>
			<view tag="off" role="button" disabled padding={8}>Off</view>
			<a tag="link" href="https://helder.build" padding={8}>Docs</a>
			<field tag="field" width={80}/>
			<text tag="plain">Plain</text>
		</view>, w.root);
		var last = "";
		w.onFrame = () -> {
			var parts = [];
			for (tag in ["save", "off", "link", "field", "plain"]) {
				var n = w.root.find(tag);
				if (n != null) parts.push('$tag=${n.absX},${n.absY},${n.width},${n.height}');
			}
			var s = "boxes " + parts.join(" ");
			if (s != last) Sys.println(last = s);
		};
		UiWindow.run();
	}
}
