import helder.ui.*;

// GlassKinds' scene under the system's glass on iOS 26 (UIGlassEffect each,
// helder.ui.Glass), 140 points from the top: the simulator's screenshot is
// the active glass's reference (always a key window's), as GlassKinds
// compares helder's with it (--compare ... 3)
class GlassKindsIos {
	static function main() {
		var w = new UiWindow("GlassKinds", GlassKinds.W, 600);
		var holder = new Node();
		holder.style.set({position: Absolute, left: 0, top: 140, width: GlassKinds.W, height: GlassKinds.H});
		GlassKinds.build(holder);
		w.root.append(holder);
		UiWindow.run();
	}
}
