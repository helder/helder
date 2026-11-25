import helder.ui.*;
import helder.ui.draw.UiWindow;

// GlassScene's backgrounds under the system's glass on iOS 26 (a
// UIGlassEffect each, helder.ui.Glass), each shown 4 s in turn, 140 points
// from the top: the simulator's screenshots are GlassTest's iOS references
// (the render server's own glass: its lens and rim light, its tint)
class GlassIos {
	static function main() {
		var w = new UiWindow("GlassIos", GlassScene.W, 600);
		var at = -1;
		function show() {
			var k = Std.int(helder.ui.Clock.now / 4) % 3;
			if (k == at) return;
			at = k;
			while (w.root.children.length > 0)
				w.root.remove(w.root.children[0]);
			var holder = new Node();
			holder.style.set({position: Absolute, left: 0, top: 140, width: GlassScene.W, height: GlassScene.H});
			GlassScene.build(holder, GlassScene.backgrounds[k], true, false);
			w.root.append(holder);
		}
		show();
		helder.ui.Clock.add(_ -> {
			show();
			true;
		});
		UiWindow.run();
	}
}
