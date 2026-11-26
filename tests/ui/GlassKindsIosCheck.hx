import helder.ui.*;

// GlassKindsCheck's scene under the system's glass on iOS 26 (UIGlassEffect each,
// helder.ui.Glass), 140 points from the top: the simulator's screenshot is
// the active glass's reference (always a key window's), as GlassKindsCheck
// compares helder's with it (--compare ... 3)
class GlassKindsIosCheck {
	static function main() {
		var w = new UiWindow({title: "GlassKindsCheck", width: GlassKindsCheck.W, height: 600});
		var holder = new Node();
		holder.style.set({position: Absolute, left: 0, top: 140, width: GlassKindsCheck.W, height: GlassKindsCheck.H});
		GlassKindsCheck.build(holder);
		w.root.append(holder);
		UiWindow.run();
	}
}
