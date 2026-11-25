import helder.os.*;
import helder.view.graph.Graph;
import hxmc.Platform;

class SettingsCheck {
	static function main() {
		var w = new Window({title: "SettingsCheck", width: 240, height: 320});
		var start = haxe.Timer.stamp();
		var original = Settings.orientation();
		var ready = false, copied = false;
		Graph.effect(() -> '${Settings.orientation()} scale=${Settings.textScale()} motion=${Settings.reducedMotion()} contrast=${Settings.contrast()} dark=${Settings.dark()}',
			v -> Sys.println('settings: $v'));
		Graph.flush();
		App.run(() -> {
			var elapsed = haxe.Timer.stamp() - start;
			if (Platform.target() >= 9) {
				if (!ready && elapsed > 0.5) {
					var text = "hélder 🚀\nclipboard";
					if (!copied) {
						Clipboard.write(w, text);
						copied = true;
					}
					Clipboard.read(w, value -> {
						if (value == text) {
							ready = true;
							Sys.println("settings: clipboard ok");
						} else if (elapsed > 5) throw "Android clipboard round trip failed";
					});
				}
			} else if (Platform.apple() < 1) {
				if (!ready) {
					if (original != Portrait || Settings.textScale() <= 0) throw "Invalid initial settings";
					w.resize(320, 240);
					ready = true;
				}
				if (Settings.orientation() == Landscape) App.quit();
				if (elapsed > 4) throw "Orientation signal did not update";
			}
			App.wait(0.25);
		}, _ -> {});
	}
}
