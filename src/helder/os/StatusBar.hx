package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract BarStyle(String) to String {
	// light text and icons, for a dark app
	var Light = "light";
	// dark ones, for a light app
	var Dark = "dark";
	// the system's appearance's (Settings.dark: light ones when dark)
	var Auto = "auto";
}

// A phone's status bar: its style and whether it shows (iOS's and
// Android's; nothing elsewhere). Android's navigation bar takes the style
// too. Window.immersive hides it as well.
class StatusBar {
	static var current = Auto;
	static var hide = false;
	static var following = false;

	@:typescript public static function style(s:BarStyle) {
		current = s;
		apply();
	}

	@:typescript public static function hidden(h:Bool) {
		hide = h;
		apply();
	}

	static function apply() {
		#if (target.name == "hxmc" && !helder.headless)
		if (Platform.apple() >= 1) {
			// (UIStatusBarStyle: default 0, the system's own Auto; lightContent 1; darkContent 3)
			@:privateAccess helder.os.uikit.UIKitWindow.statusBar(current == Light ? 1 : current == Dark ? 3 : 0, hide);
		} else if (Platform.target() >= 9) {
			if (current == Auto && !following) {
				following = true;
				helder.view.graph.Graph.root(_ -> helder.view.graph.Graph.effect(() -> Settings.dark(), _ -> if (current == Auto) apply()));
			}
			helder.os.android.AndroidStatusBar.set(current == Light || (current == Auto && Settings.dark.peek()), hide);
		}
		#end
	}
}
