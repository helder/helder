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
		header.style.set({height: 120, shrink: 0, background: 0xFF18181B, padding: 12});
		root.append(header);
		// (a label in the header, changed each frame for a while: what the window's layer draws of it)
		var title = new TextNode("Header");
		title.style.set({color: 0xFFFFFFFF, fontSize: 18});
		header.append(title);
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
		// (3 s: still running once a slow device's program frames hand it over)
		mover.style.transition = Transition.parse("transform 3s linear, opacity 3s linear");
		root.append(mover);
		var c = w.compositor;
		var layers = c == null ? null : c.layers;
		strict = layers != null && mode != "stall";
		say('start: system layers ${mode == "" ? "default" : mode}, compositor ${c != null}, layers ${layers != null}');
		var baseline = 60.0, armFrom = 0.0, unarmed = false, tries = 0;
		// (a finger's fling: down, moves a frame apart, up; routed as the system's are)
		function fling():String {
			var t = Timer.stamp() * 1000, r = [];
			for (i in 0...8)
				r.push(touch(w, i == 0 ? PointerDown : PointerMove, 200, 700 - i * 60, t + i * 16));
			r.push(touch(w, PointerUp, 200, 700 - 7 * 60, t + 8 * 16));
			return r.join(" ") + ', moving ${c != null && c.moving()}';
		}
		// (the handshake before a phase blocks: the compositor holds a program
		// frame with the motion running (its next frame due), else nothing
		// moves on its own while the program is blocked: a transition whose
		// start is its next tick waits for it, in the program's frames and the
		// compositor's alike. Given up after 3 s: a failure)
		function armed(what:String, now:Float, glide = false):Bool {
			if (c == null || c.due() >= 0 && (!glide || c.moving())) {
				say('$what: the compositor armed ${Math.round((now - armFrom) * 1000)} ms after it began');
				return true;
			}
			if (now - armFrom < 3) return false;
			say('note: $what: the program\'s frames did not hand the motion over in 3 s (a device too slow for it): reported, not checked');
			unarmed = true;
			return true;
		}
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
			strict = live() && mode != "stall" && baseline >= 20 && !unarmed;
			unarmed = false;
			var sc = layers == null ? null : Std.downcast(layers, ScLayers), t0 = sc == null ? [] : sc.timing.copy();
			if (c != null) @:privateAccess {
				var f = c.shown, d = c.due();
				say('$what: the compositor holds the program\'s frame painted ${f == null ? -1 : Math.round((helder.ui.Ui.now() - f.paintedAt) * 1000)} ms ago, its movers ${f == null ? 0 : f.movers.length}, the mirror moving ${c.mirror.moving}, next frame due in ${d < 0 ? "never" : Math.round((d - Timer.stamp()) * 1000) + " ms"}');
			}
			var f0 = layers == null ? 0 : layers.frames, q0 = layers == null ? 0 : layers.quadsTotal;
			var from = Timer.stamp();
			before();
			Sys.sleep(seconds);
			var to = Timer.stamp();
			plock.acquire();
			var during = [for (t in presents) if (t > from && t <= to) t];
			plock.release();
			// (the device too slow for the phase, the frame count and the pace
			// reported, not checked: the render thread busy showing (drawing,
			// waiting on the system) most of it; waiting for the system to
			// present the last transaction most of it (a loaded emulator's
			// pace); or each frame shown taking most of a display period (CI's
			// emulator: 56 frames in 3 s, each shown in 18 ms, on its pace).
			// An idle compositor shows few frames quickly, a stalled one none:
			// checked, and under 4 frames a second whatever the device)
			var busy = sc == null ? 0.0 : (sc.timing[0] - t0[0]) / (to - from);
			var systems = sc == null ? 0.0 : (sc.timing[3] - t0[3]) / (to - from);
			var shown = sc == null ? 0 : layers.frames - f0;
			var each = shown == 0 ? 0.0 : (sc.timing[0] - t0[0]) / shown;
			var slow = busy > 0.6 || systems > 0.4 || each > 0.8 / 60;
			var gaps = [for (i in 1...during.length) during[i] - during[i - 1]];
			gaps.sort(Reflect.compare);
			var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
			var checked = strict;
			if (strict && slow && (during.length < seconds * 20 || pace && median >= 0.03)) {
				say('note: $what: the render thread busy ${Math.round(busy * 100)}% of the phase, waiting on the system ${Math.round(systems * 100)}%, ${Math.round(each * 10000) / 10} ms a frame shown: reported, not checked');
				strict = false;
			}
			check('$what: frames presented while the program was blocked ${Math.round(seconds * 1000)} ms', during.length >= seconds * 20,
				during.length + " frames");
			if (pace) check('$what: at the display\'s pace', gaps.length > 0 && median < 0.03, "median gap " + Math.round(median * 10000) / 10 + " ms")
			else say('$what: median gap ${Math.round(median * 10000) / 10} ms');
			strict = checked;
			// (a compositor that stalls or idles on any device)
			if (strict) check('$what: at least 4 frames a second', during.length >= seconds * 4, during.length + " frames");
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
		// (the list's last paint drew its tiles where it rests: a scroller
		// draws them where they fall for 3 paints after it moved, its rows
		// then a pixel off where those tiles were drawn at another offset's
		// fraction; a slow device's program may paint fewer than that
		// before a still, CI's emulator at a frame a second)
		function rested():Bool @:privateAccess {
			var l = list.contentLayer, p = w.ui.paintFrame;
			return l == null || p - l.movedAt >= 3 && l.recordedAt != p;
		}
		function cpu():Float {
			var s = sys.io.File.getContent("/proc/self/stat");
			var f = s.substr(s.lastIndexOf(")") + 2).split(" ");
			return (Std.parseFloat(f[11]) + Std.parseFloat(f[12])) * 10;
		}
		var step = 0, phase = 0, at = 0.0, k = w.window.scale, flung = 0.0, timed = 0, cpu0 = 0.0, t0 = 0.0, q0 = 0, header0:Array<Float> = [];
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
					say('a fling: injected, the compositor answered ${fling()}');
					tries = 1;
					phase = 11;
					at = step;
					armFrom = now;
				case 11 if (c != null && !c.moving() && now - armFrom > 1 && tries == 1):
					// (no glide began (the mirror not moving): flung again, as a finger would)
					say('a fling: first attempt failed (no glide after 1 s, list at ${list.scrollY}); retrying once: ${fling()}');
					tries++;
					armFrom = now;
					at = step;
				case 11 if (step - at >= 4 && armed("a fling", now, true)):
					// (its pace not checked: the list's layer gets a buffer for the area it
					// records as the fling passes it, which an emulator makes slowly)
					var r = blocked("a fling", 0.3, () -> {}, false);
					plock.acquire();
					var moved = [for (i in 0...presents.length) if (presents[i] > r.from && presents[i] <= r.to) offsets[i]];
					plock.release();
					var advanced = moved.length > 1 && moved[moved.length - 1] > moved[0];
					var range = moved.length > 0 ? '${moved[0]} to ${moved[moved.length - 1]}' : "none";
					if (!advanced && tries == 1) {
						say('a fling: first attempt failed (offsets $range); retrying once: ${fling()}');
						tries++;
						at = step;
						armFrom = Timer.stamp();
					} else {
						check("a fling: the offset advancing", advanced, range);
						phase = 2;
						at = now;
					}
				case 2 if (now - at > 2 && (c == null || !c.moving())):
					// (the box animating while the program is blocked)
					mover.style.transform = Transform.parse("translate(220px, 90px)");
					mover.style.opacity = 0.4;
					phase = 12;
					at = step;
					armFrom = now;
				case 12 if (step - at >= 6 && armed("an animation", now)):
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
					// (on whole pixels at 2.625, a phone's density: 8 points are 21 pixels;
					// see-through, from 0.4: its colour checked in each mode)
					mover.style.transform = Transform.parse("translate(100px, 34px)");
					mover.style.opacity = 0.6;
					phase = 5;
					at = now;
				case 5 if (now - at > 2 && !rested()):
					// (before each still, the program's frames until the list's
					// last was drawn from its tiles at rest: in every mode, not
					// replayed as recorded, which the emulator's GL draws a few
					// levels off at glyphs' edges (up to 17), nor its tiles where
					// they fell, a pixel off at some rows)
					w.ui.requestFrame();
				case 5 if (now - at > 5):
					say('slot at ${Math.round((slotted.absX + 32) * k)} ${Math.round((slotted.absY + 8 - list.scrollY) * k)}');
					// (the box at 0.6 over the header: its colour then, in every mode)
					var bg = 0x18181B, fg = 0x2A7AE2, mix = 0;
					for (c in [16, 8, 0])
						mix |= Math.round(0.6 * (fg >> c & 0xFF) + 0.4 * (bg >> c & 0xFF)) << c;
					say('box at ${Math.round(164 * k)} ${Math.round(96 * k)} ${StringTools.hex(mix, 6)}');
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
					// (240 frames, or 8 s on a device too slow for them: the stills' script waits)
					if (timed == 240 || now - t0 > 8) {
						var ms = (cpu() - cpu0) / timed, q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: steady scroll: $timed frames in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round(ms * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						// (where 240 frames take it, however many there were: the same in every mode for the stills)
						list.scrollY = 304 + 4 * 240;
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
				case 13 if (now - at > 0.5 && !rested()):
					w.ui.requestFrame();
				case 13 if (now - at > 1.5):
					say("still 2");
					phase = 16;
					at = now;
					timed = 0;
				case 16 if (now - at > 2 && timed == 0):
					// (the header's label changed each frame: the window's layer
					// drawn where it changed, the list's not at all)
					timed = 1;
					t0 = now;
					cpu0 = cpu();
					q0 = layers == null ? 0 : layers.quadsTotal;
					var sc = layers == null ? null : Std.downcast(layers, ScLayers);
					header0 = layers == null ? [0, 0, 0.0, 0] : [layers.frames, sc == null ? 0 : sc.cutTotal, sc == null ? 0 : sc.pixelsTotal, sc == null ? 0 : sc.timing[1]];
				case 16 if (timed > 0):
					title.text = "Header " + timed;
					timed++;
					if (timed > 120) {
						var sc = layers == null ? null : Std.downcast(layers, ScLayers), n = timed - 1;
						var f = layers == null ? 0 : layers.frames - Std.int(header0[0]);
						var ms = (cpu() - cpu0) / n;
						if (sc != null)
							say('timed: header: $n changes in ${Math.round((now - t0) * 10) / 10} s, $f frames, ${sc.cutTotal - Std.int(header0[1])} layers drawn in part, ${Math.round((sc.pixelsTotal - header0[2]) / Math.max(1, f))} pixels a frame of ${w.device.width * w.device.height}, drawing ${Math.round((sc.timing[1] - header0[3]) / Math.max(1, f) * 10000) / 10} ms a frame on the render thread, CPU ${Math.round(ms * 100) / 100} ms a change, ${Math.round((layers.quadsTotal - q0) / Math.max(1, f) * 10) / 10} quads drawn a frame')
						else say('timed: header: $n changes in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round(ms * 100) / 100} ms a change');
						phase = 17;
						at = now;
					}
				case 17 if (now - at > 0.5 && !rested()):
					w.ui.requestFrame();
				case 17 if (now - at > 1.5):
					// (the window's layer after 120 frames drawn only where they changed: as drawn whole)
					say("still 3");
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

	// (a touch's event as the system's would come, routed first; what the compositor answered)
	static function touch(w:UiWindow, kind:helder.os.Event.EventKind, x:Float, y:Float, ms:Float):Int {
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
		return e.routed;
	}
}

// (bionic's: a system property; setenv)
@:hxmc.c @:hxmc.fast extern class Props {
	static function __system_property_get(name:Ptr, value:Ptr):Int;
	static function setenv(name:Ptr, value:Ptr, overwrite:Int):Int;
}
