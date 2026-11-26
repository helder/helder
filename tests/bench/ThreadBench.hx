import helder.gfx.Color;
import helder.ui.*;
import helder.ui.UiWindow;

// The program on the page's thread against the program in a worker
// (thread-bench.mjs): a 480x360 window of 200 rows, a dot following the
// pointer and a box turning on every frame (--still: not turning, no
// frame asked for); with --work ms, the program busy that long after each
// frame.
class ThreadBench {
	static function main() {
		var args = Sys.args(), i = args.indexOf("--work"), work = i >= 0 ? Std.parseFloat(args[i + 1]) : 0.0, still = args.contains("--still");
		var w = new UiWindow({title: "Bench", width: 480, height: 360});
		var list = new Node("list");
		list.style.set({width: 480, height: 360, overflow: Scroll, background: Color.rgb(0xffffff)});
		for (r in 0...200) {
			var row = new TextNode('Row $r: the quick brown fox jumps over the lazy dog');
			row.style.set({height: 28, flexShrink: 0, padding: 6, fontSize: 14, background: Color.rgb(r % 2 == 0 ? 0xf4f4f5 : 0xffffff)});
			list.append(row);
		}
		var dot = new Node("dot"), spin = new Node("spin");
		dot.style.set({position: Absolute, left: 0, top: 0, width: 12, height: 12, borderRadius: 6, background: Color.rgb(0xe11d48)});
		spin.style.set({position: Absolute, left: 400, top: 20, width: 50, height: 50, borderRadius: 8, background: Color.rgb(0x2563eb)});
		w.root.append(list);
		w.root.append(dot);
		w.root.append(spin);
		w.root.onPointerMove = e -> {
			dot.style.left = e.x - 6;
			dot.style.top = e.y - 6;
		};
		var turn = 0.0;
		w.onFrame = () -> {
			if (still) return;
			turn += 3;
			spin.style.transform = Transform.parse('rotate(${turn}deg)');
			w.ui.requestFrame();
			if (work > 0) {
				var end = haxe.Timer.stamp() + work / 1000;
				while (haxe.Timer.stamp() < end) {}
			}
		};
		UiWindow.run();
	}
}
