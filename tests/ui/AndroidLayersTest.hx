import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import hxmc.unsafe.*;

// Android's system layers (helder.ui.draw.ScLayers) on a device or emulator
// (tests/ui/android-layers.sh): a list under a header and a box that
// moves. The program blocks 300 ms while its own fling glides, then while
// the box animates: the compositor's frames keep the display's pace, the
// list's and the box's layers moved, not drawn (quads drawn a frame); then
// 3 s while the script swipes (the UI thread routing the finger to the
// compositor); stills for the script's screencaps (`still`); a steady
// scroll and an animation timed (the process's CPU a frame); a box that
// turns (drawn, SurfaceControl has no turn). The system property
// debug.helder.layers (setprop) is HELDER_SYSTEM_LAYERS: 0 runs the
// textured compositor, for the screencaps' comparison, its pace reported
// (an emulator's GPU may not keep it); stall withholds every transaction's
// presentation, as a misbehaving system would: the layers must fall back
// to the textured compositor while running, its pace reported; debug.helder.async 0: no
// compositor; debug.helder.damage: HELDER_DAMAGE.
//   helder build tests/ui/AndroidLayersTest.hx --target android-arm64 -o AndroidLayersTest.apk
@:hxmc.unsafe(gc)
class AndroidLayersTest {
	static var failed = 0;

	// (the textured compositor's own pace is the device's: reported, not checked)
	static var strict = true;

	static function check(what:String, ok:Bool, detail:String) {
		if (!ok && strict) failed++;
		Sys.println('AndroidLayersTest: ${ok ? "ok" : strict ? "FAIL" : "slow"}: $what ($detail)');
	}

	static function say(s:String)
		Sys.println("AndroidLayersTest: " + s);

	static function main() {
		var v = Mem.stack(96);
		Props.__system_property_get(Mem.cstr("debug.helder.layers"), v);
		var mode = (cast v : CString).toString();
		if (mode != "") Props.setenv(Mem.cstr("HELDER_SYSTEM_LAYERS"), v, 1);
		// (debug.helder.async: HELDER_ASYNC_SCROLL, 0 no compositor at all)
		Props.__system_property_get(Mem.cstr("debug.helder.async"), v);
		if ((cast v : CString).toString() != "") Props.setenv(Mem.cstr("HELDER_ASYNC_SCROLL"), v, 1);
		// (debug.helder.damage: HELDER_DAMAGE)
		Props.__system_property_get(Mem.cstr("debug.helder.damage"), v);
		if ((cast v : CString).toString() != "") Props.setenv(Mem.cstr("HELDER_DAMAGE"), v, 1);
		var w = new UiWindow("AndroidLayersTest", 0, 0);
		var root = w.root;
		root.style.set({direction: Column, background: 0xFFFFFFFF});
		var header = new Node();
		header.style.set({height: 120, shrink: 0, background: 0xFF18181B});
		root.append(header);
		var list = new Node();
		list.style.set({grow: 1, minHeight: 0, overflow: Scroll, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		var rows = [];
		for (i in 0...300) {
			var row = new Node();
			rows.push(row);
			row.style.set({direction: Row, padding: 6, columnGap: 8, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 16, height: 16, radius: 4, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		root.append(list);
		// (a node's system layer in the list, and a rounded scroller in the header: drawn, SurfaceControl has no rounded clip)
		var slotted = new Node();
		slotted.style.set({position: Absolute, left: 160, top: 6, width: 64, height: 16, background: 0xFF20C060});
		rows[14].style.position = Relative;
		rows[14].append(slotted);
		var round = new Node();
		round.style.set({position: Absolute, right: 16, top: 16, width: 120, height: 88, radius: 16, overflow: Scroll, background: 0xFFFFE08A});
		for (i in 0...12) {
			var r = new Node();
			r.style.set({height: 24, shrink: 0, background: i % 2 == 0 ? 0xFFF59E0B : 0xFFFFE08A});
			round.append(r);
		}
		header.append(round);
		var mover = new Node();
		mover.style.set({position: Absolute, left: 20, top: 30, width: 88, height: 64, radius: 10, background: 0xFF2A7AE2});
		mover.style.transform = Transform.parse("translate(0px, 0px)");
		mover.style.transition = Transition.parse("transform 1.2s linear, opacity 1.2s linear");
		root.append(mover);
		var c = w.compositor;
		var layers = c == null ? null : c.layers;
		strict = layers != null && mode != "stall";
		say('start: system layers ${mode == "" ? "default" : mode}, compositor ${c != null}, layers ${layers != null}');
		var baseline = 60.0;
		var presents:Array<Float> = [], offsets:Array<Float> = [], plock = new sys.thread.Mutex();
		if (c != null) c.onFrame = t -> {
			var o = c.offsets(list);
			plock.acquire();
			presents.push(t);
			offsets.push(o == null ? -1 : o.y);
			plock.release();
		};
		// (frames on the system's layers, which have not fallen back)
		function live():Bool
			return layers != null && layers.fell == null && layers.frames > 0;
		// (a phase blocking the program: frames presented meanwhile, their gaps, the layers' frames and quads)
		function blocked(what:String, seconds:Float, before:Void->Void, pace = true):{frames:Int, median:Float, from:Float, to:Float} {
			strict = live() && mode != "stall" && baseline >= 20;
			var sc = layers == null ? null : Std.downcast(layers, ScLayers), t0 = sc == null ? [] : sc.timing.copy();
			var f0 = layers == null ? 0 : layers.frames, q0 = layers == null ? 0 : layers.quadsTotal;
			var from = Timer.stamp();
			before();
			Sys.sleep(seconds);
			var to = Timer.stamp();
			plock.acquire();
			var during = [for (t in presents) if (t > from && t <= to) t];
			plock.release();
			// (the render thread busy showing (drawing, waiting on the system) most
			// of the phase: a device too slow for it, reported; idle with no
			// frames: the compositor's own fault, checked)
			var busy = sc == null ? 0.0 : (sc.timing[0] - t0[0]) / (to - from);
			if (strict && during.length < seconds * 20 && busy > 0.6) {
				say('note: $what: the render thread was busy ${Math.round(busy * 100)}% of the phase: reported, not checked');
				strict = false;
			}
			var gaps = [for (i in 1...during.length) during[i] - during[i - 1]];
			gaps.sort(Reflect.compare);
			var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
			check('$what: frames presented while the program was blocked ${Math.round(seconds * 1000)} ms', during.length >= seconds * 20,
				during.length + " frames");
			if (pace) check('$what: at the display\'s pace', gaps.length > 0 && median < 0.03, "median gap " + Math.round(median * 10000) / 10 + " ms")
			else say('$what: median gap ${Math.round(median * 10000) / 10} ms');
			if (sc != null) {
				var d = [for (i in 0...4) Math.round((sc.timing[i] - t0[i]) * 1000)];
				say('$what: the render thread: showing ${d[0]} ms, drawing ${d[1]}, waiting for buffers ${d[2]}, for the last transaction ${d[3]}, frames ${layers.frames - f0}');
			}
			if (layers != null && !layers.single) {
				var f = layers.frames - f0, q = layers.quadsTotal - q0;
				check('$what: on the system\'s layers, moved, not drawn', f > 0 && q <= 8 * f, '$f frames, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
			}
			return {frames: during.length, median: median, from: from, to: to};
		}
		function cpu():Float {
			var s = sys.io.File.getContent("/proc/self/stat");
			var f = s.substr(s.lastIndexOf(")") + 2).split(" ");
			return (Std.parseFloat(f[11]) + Std.parseFloat(f[12])) * 10;
		}
		var step = 0, phase = 0, at = 0.0, k = w.window.scale, flung = 0.0, timed = 0, cpu0 = 0.0, t0 = 0.0, q0 = 0;
		App.run(() -> {
			step++;
			var now = Timer.stamp();
			switch phase {
				case 0 if (step > 20 && list.height > 0):
					// (its layer one level off its own background: the screencap tells which shows)
					var sc = layers == null ? null : Std.downcast(layers, ScLayers);
					if (sc != null) @:privateAccess slotted.systemLayer = new LayerSlot(sc.solid(0x22C060));
					say('ready ${w.device.width}x${w.device.height}, scale $k');
					phase = 14;
					at = now;
				case 14 if (now - at > 3):
					// (after a launch's own work: an emulator's first seconds are its;
					// then the display's own pace, the program scrolling each frame)
					phase = 15;
					at = now;
					timed = 0;
				case 15:
					list.scrollY += 1;
					timed++;
					if (now - at > 1) {
						baseline = timed / (now - at);
						say('the display\'s pace here, the program scrolling: ${Math.round(baseline)} frames a second');
						if (baseline < 20) say('note: under 20 frames a second here: the blocked phases reported, not checked');
						phase = 1;
					}
				case 1:
					// (a fling of the program's own: the compositor glides it while the program is blocked)
					var t = now * 1000;
					for (i in 0...8)
						touch(w, i == 0 ? PointerDown : PointerMove, 200, 600 - i * 40, t + i * 16);
					touch(w, PointerUp, 200, 600 - 7 * 40, t + 8 * 16);
					phase = 11;
					at = step;
				case 11 if (step - at >= 4):
					// (its pace not checked: the list's layer gets a buffer for the area it
					// records as the fling passes it, which an emulator makes slowly)
					var r = blocked("a fling", 0.3, () -> {}, false);
					plock.acquire();
					var moved = [for (i in 0...presents.length) if (presents[i] > r.from && presents[i] <= r.to) offsets[i]];
					plock.release();
					check("a fling: the offset advancing", moved.length > 1 && moved[moved.length - 1] > moved[0], moved.length > 0 ? '${moved[0]} to ${moved[moved.length - 1]}' : "none");
					phase = 2;
					at = now;
				case 2 if (now - at > 2 && (c == null || !c.moving())):
					// (the box animating while the program is blocked)
					mover.style.transform = Transform.parse("translate(220px, 90px)");
					mover.style.opacity = 0.4;
					phase = 12;
					at = step;
				case 12 if (step - at >= 6):
					blocked("an animation", 0.3, () -> {});
					phase = 3;
					at = now;
				case 3 if (now - at > 2):
					// (the script's finger while the program is blocked: the UI thread routes it)
					flung = list.scrollY;
					blocked("a swipe", 3, () -> say("swipe now"));
					phase = 4;
					at = now;
				case 4 if (now - at > 1 && (c == null || !c.moving())):
					check("a swipe: the program has the compositor's offset", c == null || list.scrollY > flung, '$flung to ${list.scrollY}');
					// (still: a whole offset, the box at rest, for the screencaps)
					// (on whole pixels: 8 points are 21 pixels at 2.625)
					list.scrollY = 304;
					// (on whole pixels at 2.625, a phone's density: 8 points are 21 pixels)
					mover.style.transform = Transform.parse("translate(100px, 34px)");
					mover.style.opacity = 1;
					phase = 5;
					at = now;
				case 5 if (now - at > 3.5):
					say('slot at ${Math.round((slotted.absX + 32) * k)} ${Math.round((slotted.absY + 8 - list.scrollY) * k)}');
					say("still 1");
					phase = 6;
					at = now;
				case 6 if (now - at > 4):
					// (a steady scroll, the program's frames: timed)
					phase = 7;
					at = now;
					timed = 0;
					cpu0 = cpu();
					t0 = now;
					q0 = layers == null ? 0 : layers.quadsTotal;
				case 7:
					list.scrollY += 4;
					timed++;
					if (timed == 240) {
						var ms = (cpu() - cpu0) / timed, q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: steady scroll: $timed frames in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round(ms * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						mover.style.transition = Transition.parse("transform 4s linear, opacity 4s linear");
						mover.style.transform = Transform.parse("translate(240px, 300px)");
						mover.style.opacity = 1;
						phase = 8;
						at = now;
						timed = 0;
						cpu0 = cpu();
						t0 = now;
						q0 = layers == null ? 0 : layers.quadsTotal;
					}
				case 8:
					timed++;
					if (now - at > 3.9) {
						var ms = (cpu() - cpu0) / timed, q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: animation: $timed frames in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round(ms * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						// (a turn: SurfaceControl has none, the box drawn from then on)
						mover.style.transition = Transition.parse("transform 1s linear");
						mover.style.transform = Transform.parse("translate(244px, 298px) rotate(90deg)");
						phase = 9;
						at = now;
					}
				case 9 if (now - at > 3):
					phase = 13;
					at = now;
				case 13 if (now - at > 1):
					say("still 2");
					phase = 10;
					at = now;
				case 10 if (now - at > 4):
					var b = layers == null ? 0.0 : layers.bytes();
					say('layers\' buffers ${Math.round(b / 1e5) / 10} MB, frames shown on them ${layers == null ? 0 : layers.frames}');
					if (layers != null && layers.fell != null) say('system layers fell back: ${layers.fell}');
					// (stall: they must have, the textured compositor's frames after)
					if (mode == "stall") {
						strict = true;
						check("the system layers fell back to the textured compositor", layers != null && layers.fell != null && layers.single, '${layers == null ? null : layers.fell}');
					}
					say(failed == 0 ? "ok" : '$failed FAILED');
					say("done");
					w.close();
					Sys.exit(failed == 0 ? 0 : 1);
				case _:
			}
			if (w.needsFrame()) w.frame() else App.wait(0.004);
			w.device.settle();
		}, e -> if (e.kind == helder.os.Event.EventKind.Close) w.close() else w.handle(e));
	}

	static function touch(w:UiWindow, kind:helder.os.Event.EventKind, x:Float, y:Float, ms:Float) {
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
		Window.routed(e);
		w.handle(e);
	}
}

// (bionic's: a system property; setenv)
@:hxmc.c @:hxmc.fast extern class Props {
	static function __system_property_get(name:Ptr, value:Ptr):Int;
	static function setenv(name:Ptr, value:Ptr, overwrite:Int):Int;
}
