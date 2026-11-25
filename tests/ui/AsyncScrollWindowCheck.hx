import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// The compositor's scrolling in a real window (helder.ui.layers.Compositor;
// bun run test ui-draw; Linux: Xvfb, and weston for Wayland): a list of
// 300 rows flung by a finger, then the program blocked for 300 ms, scroll
// input injected meanwhile where the main thread reads it (Inject): the
// frames keep coming at the display's pace, the offset advancing, and the
// program sees the compositor's final offset afterwards.
//   AsyncScrollWindowCheck [--latency n [--work ms]]: input to present, n scrolls,
//   the program's own work after each frame (ms)
//   AsyncScrollWindowCheck --anim [--pace s [--work ms]]: a layer's transition
//   while the program blocks (Pacing), or its frames' pacing over s seconds
//   AsyncScrollWindowCheck --native: a native field over the list moved with
//   the compositor's scroll (NativeCheck; macOS)
class AsyncScrollWindowCheck {
	static var failed = 0;
	static var layerFrames = -1;
	static var layerQuads = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failed++;
		Sys.println('AsyncScrollWindowCheck: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : ' ($detail)'));
	}

	static function main() {
		var a = Sys.args(), l = a.indexOf("--latency"), k = a.indexOf("--work"), p = a.indexOf("--pace");
		var w = new helder.ui.UiWindow("AsyncScrollWindowCheck", 400, 300);
		var list = new Node();
		list.style.set({overflow: Scroll, height: 300, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...300) {
			var row = new Node();
			row.style.set({direction: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 12, height: 12, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		w.root.append(list);
		if (l >= 0) return Latency.run(w, list, Std.parseInt(a[l + 1]) ?? 60, k >= 0 ? Std.parseFloat(a[k + 1]) / 1000 : 0);
		if (a.indexOf("--native") >= 0) return NativeCheck.run(w, list);
		if (a.indexOf("--anim") >= 0) {
			Pacing.run(w, p >= 0 ? Std.parseFloat(a[p + 1]) : 0, k >= 0 ? Std.parseFloat(a[k + 1]) / 1000 : 0);
			return;
		}
		var c = w.compositor;
		if (c == null) {
			Sys.println("AsyncScrollWindowCheck: no compositor here (HELDER_ASYNC_SCROLL=0, no render thread, or the program on the main thread): skipped");
			w.close();
			return;
		}
		var step = 0, presents:Array<Float> = [], blockedFrom = 0.0, blockedTo = 0.0, offsets:Array<Float> = [];
		c.onFrame = t -> {
			presents.push(t);
			var o = c.offsets(list);
			offsets.push(o == null ? -1 : o.y);
		};
		var blocked = false, flung = 0.0, injected = 0;
		App.run(() -> {
			step++;
			if (step == 10) {
				// (a finger's fling: down, moves a frame apart, up; read as the main thread reads them)
				var t = Timer.stamp() * 1000;
				for (i in 0...8)
					touch(w, i == 0 ? PointerDown : PointerMove, 200, 250 - i * 20, t + i * 16);
				touch(w, PointerUp, 200, 250 - 7 * 20, t + 8 * 16);
			}
			if (step > 12 && !blocked && !c.moving()) {
				// (the program busy, its fling at rest: scroll input injected meanwhile where
				// the system's comes in, or a fling of its own where none can be yet)
				blocked = true;
				flung = list.scrollY;
				if (!Inject.supported) {
					var t = Timer.stamp() * 1000;
					for (i in 0...8)
						touch(w, i == 0 ? PointerDown : PointerMove, 200, 250 - i * 20, t + i * 16);
					touch(w, PointerUp, 200, 250 - 7 * 20, t + 8 * 16);
				}
				#if (!helder.os || helder.os == "macos" || helder.os == "ios" || helder.os == "windows" || helder.os == "linux")
				var l = c.layers;
				if (l != null) {
					layerFrames = l.frames;
					layerQuads = l.quadsTotal;
				}
				#end
				blockedFrom = Timer.stamp();
				var inject = Inject.start(w.window, 300);
				Sys.sleep(0.3);
				blockedTo = Timer.stamp();
				#if (!helder.os || helder.os == "macos" || helder.os == "ios" || helder.os == "windows" || helder.os == "linux")
				if (l != null) {
					layerFrames = l.frames - layerFrames;
					layerQuads = l.quadsTotal - layerQuads;
				}
				#end
				inject.join();
				injected = inject.sent;
				step = 20;
			}
			if (w.needsFrame()) w.frame();
			w.device.settle();
			// (at rest again, its last offsets taken)
			if (step > 30 && c.moving()) step = 30;
			if (step == 32) {
				var during = [for (i in 0...presents.length) if (presents[i] > blockedFrom && presents[i] <= blockedTo) i];
				var gaps = [for (i in 1...during.length) presents[during[i]] - presents[during[i - 1]]];
				gaps.sort(Reflect.compare);
				var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
				if (Inject.supported) check("input injected meanwhile", injected > 10, injected + " events");
				// (Wayland's system layers: each commit's frame callback, which a headless weston answers every other refresh)
				var slow = Sys.getEnv("WAYLAND_DISPLAY") != null && c.layers != null;
				check("frames presented while the program was blocked for 300 ms", during.length >= (slow ? 6 : 10), during.length + " frames");
				check("at the display's pace", gaps.length > 0 && median < (slow ? 0.05 : 0.03), "median gap " + Math.round(median * 10000) / 10 + " ms");
				var advancing = during.length > 1 && offsets[during[during.length - 1]] > offsets[during[0]] && offsets[during[0]] >= flung;
				check("the offset advancing", advancing, during.length > 0 ? flung + ": " + offsets[during[0]] + " to " + offsets[during[during.length - 1]] : "none");
				// (Core Animation's, DirectComposition's, Wayland's: the list's content moved as a layer, only its scrollbar drawn again)
				if (layerFrames >= 0) check("on the system's layers: the list's layer moved, not drawn", layerFrames > 0 && layerQuads <= 8 * layerFrames,
					'$layerFrames frames committed, ${Math.round(layerQuads / Math.max(1, layerFrames) * 10) / 10} quads drawn a frame');
				var o = c.offsets(list);
				check("the program has the compositor's offset", o != null && list.scrollY == o.y && list.scrollY > flung, flung + " to " + list.scrollY + " " + (o == null ? null : o.y));
				w.close();
				Sys.println("AsyncScrollWindowCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
				Sys.exit(failed == 0 ? 0 : 1);
			}
		}, e -> w.handle(e));
	}

	static function touch(w:helder.ui.UiWindow, kind:helder.os.EventKind, x:Float, y:Float, ms:Float) {
		var e = new helder.os.Event(), p = @:privateAccess new Pointer(1), s = w.window.scale;
		@:privateAccess {
			p.type = Touch;
			p.x = x * s;
			p.y = y * s;
			p.time = ms;
			p.pressure = 1;
		}
		e.kind = kind;
		e.window = w.window;
		e.pointer = p;
		helder.os.Window.routed(e);
		w.handle(e);
	}
}
