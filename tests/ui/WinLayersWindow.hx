import haxe.Timer;
import haxe.io.Bytes;
import helder.os.*;
import helder.os.win32.User32;
import helder.ui.*;
import helder.ui.draw.*;
import hxmc.unsafe.*;

// Windows' system layers (helder.ui.draw.DcLayers, DirectComposition) in
// a real window (the window lane, CI's desktop-windows job): a list with
// a system layer in a row, a rounded scroller, a box that moves. The
// program blocks 300 ms while the wheel scrolls the list (SendInput), then
// while the box animates: the frames keep the display's pace, the list's
// and the box's visuals moved, not drawn (quads drawn a frame); stills of
// the window (PrintWindow, else the screen's pixels) against the textured
// compositor's (its own run's, written to dir); a steady scroll and an
// animation timed (the process's CPU a frame: on CI's runner WARP draws,
// so the GPU's work is the process's too), then a header's label changed
// each frame (each layer drawn where it changed) and a still after it.
//   WinLayersWindow <dir> textured|layers|stall (HELDER_SYSTEM_LAYERS=0
//   for textured, =stall for stall: no commit reported processed, the
//   layers must fall back while running, its stills the textured's after)
@:hxmc.unsafe(gc)
class WinLayersWindow {
	static var failed = 0;
	static var strict = true;

	static function check(what:String, ok:Bool, detail:String) {
		if (!ok && strict) failed++;
		Sys.println('WinLayersWindow: ${ok ? "ok" : strict ? "FAIL" : "reported"}: $what ($detail)');
	}

	static function say(s:String)
		Sys.println("WinLayersWindow: " + s);

	// (pixels over this many levels, at most this share of them: the
	// layers blended by DirectComposition, not UiShader, at translucent edges)
	static inline var LEVELS = 8;
	static inline var SHARE = 0.002;

	static function main() {
		var a = Sys.args(), dir = a[0], mode = a[1];
		if (dir == null || !["textured", "layers", "stall"].contains(mode)) {
			Sys.println("usage: WinLayersWindow <dir> textured|layers|stall");
			Sys.exit(2);
		}
		sys.FileSystem.createDirectory(dir);
		var w = new UiWindow("WinLayersWindow", 400, 300);
		var root = w.root;
		root.style.set({direction: Column, background: 0xFFFFFFFF});
		var header = new Node();
		header.style.set({height: 40, shrink: 0, background: 0xFF18181B, padding: 10});
		var title = new TextNode("Header");
		title.style.set({color: 0xFFFFFFFF, fontSize: 14});
		header.append(title);
		root.append(header);
		var list = new Node();
		list.style.set({grow: 1, minHeight: 0, width: 240, overflow: Scroll, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		var rows = [];
		for (i in 0...200) {
			var row = new Node();
			rows.push(row);
			row.style.set({direction: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 12, height: 12, radius: 3, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		root.append(list);
		// (a node's system layer in a row: its colour a level off the node's own)
		var slotted = new Node();
		slotted.style.set({position: Absolute, left: 120, top: 2, width: 60, height: 12, background: 0xFF30A050});
		rows[40].style.position = Relative;
		rows[40].append(slotted);
		var round = new Node();
		round.style.set({position: Absolute, left: 260, top: 56, width: 120, height: 100, radius: 14, overflow: Scroll, background: 0xFFFFE08A});
		for (i in 0...12) {
			var r = new Node();
			r.style.set({height: 20, shrink: 0, background: i % 2 == 0 ? 0xFFF59E0B : 0xFFFFE08A});
			round.append(r);
		}
		root.append(round);
		var mover = new Node();
		mover.style.set({position: Absolute, left: 270, top: 180, width: 80, height: 50, radius: 8, background: 0xFF2A7AE2});
		mover.style.transform = Transform.parse("translate(0px, 0px)");
		mover.style.transition = Transition.parse("transform 1.5s linear, opacity 1.5s linear");
		root.append(mover);
		var c = w.compositor;
		var layers = c == null ? null : c.layers, dc = layers == null ? null : Std.downcast(layers, DcLayers);
		strict = mode != "stall";
		say('start: $mode, compositor ${c != null}, system layers ${layers != null}');
		if (mode != "textured" && dc == null) {
			say("FAIL: no system layers (DirectComposition) here");
			w.close();
			Sys.exit(1);
		}
		var presents:Array<Float> = [], plock = new sys.thread.Mutex();
		if (c != null) c.onFrame = t -> {
			plock.acquire();
			presents.push(t);
			plock.release();
		};
		function live():Bool
			return layers != null && layers.fell == null;
		// (a phase blocking the program: frames presented meanwhile, their gaps, the layers' frames and quads)
		function blocked(what:String, before:Void->Void) {
			var was = strict;
			strict = was && (mode == "textured" || live());
			var t0 = dc == null ? [] : dc.timing.copy(), f0 = layers == null ? 0 : layers.frames, q0 = layers == null ? 0 : layers.quadsTotal;
			var from = Timer.stamp();
			before();
			Sys.sleep(0.3);
			var to = Timer.stamp();
			plock.acquire();
			var during = [for (t in presents) if (t > from && t <= to) t];
			plock.release();
			var gaps = [for (i in 1...during.length) during[i] - during[i - 1]];
			gaps.sort(Reflect.compare);
			var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
			check('$what: frames presented while the program was blocked 300 ms', during.length >= 10, during.length + " frames");
			check('$what: at the display\'s pace', gaps.length > 0 && median < 0.03, "median gap " + Math.round(median * 10000) / 10 + " ms");
			if (dc != null) {
				var d = [for (i in 0...3) Math.round((dc.timing[i] - t0[i]) * 1000)];
				say('$what: the render thread: showing ${d[0]} ms, drawing ${d[1]}, waiting for the last commit ${d[2]}, frames ${layers.frames - f0}');
			}
			if (live() && !layers.single) {
				var f = layers.frames - f0, q = layers.quadsTotal - q0;
				check('$what: on the system\'s layers, moved, not drawn', f > 0 && q <= 8 * f, '$f frames, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
			}
			strict = was;
		}
		var step = 0, phase = 0, at = 0.0, k = w.window.scale, timed = 0, cpu0 = 0.0, t0 = 0.0, q0 = 0, f0 = 0, n0 = 0;
		function still(n:Int) {
			var px = capture(w.window, w.device.width, w.device.height);
			if (px == null) {
				check('still $n: captured', false, "no capture");
				return;
			}
			var file = '$dir/still$n-$mode.rgba';
			sys.io.File.saveBytes(file, px);
			// (the system layer's colour where it is: which shows)
			var sx = Math.round((slotted.absX + 30) * k), sy = Math.round((slotted.absY + 6 - list.scrollY) * k);
			if (sy > 40 * k && sy < w.device.height) {
				var o = 4 * (sy * w.device.width + sx);
				say('still $n: at the system layer ${StringTools.hex(px.get(o) << 16 | px.get(o + 1) << 8 | px.get(o + 2), 6)} (its own 31a050, its node\'s 30a050)');
			}
			if (mode == "textured") {
				say('still $n: written');
				return;
			}
			var ref = '$dir/still$n-textured.rgba';
			if (!sys.FileSystem.exists(ref)) {
				check('still $n: against the textured compositor\'s', false, "no " + ref);
				return;
			}
			var b = sys.io.File.getBytes(ref), W = w.device.width, H = w.device.height;
			if (b.length != px.length) {
				check('still $n: against the textured compositor\'s', false, 'sizes ${b.length} and ${px.length}');
				return;
			}
			var over = 0, some = 0, most = 0, x0 = W, y0 = H, x1 = -1, y1 = -1;
			for (i in 0...W * H) {
				var d = 0;
				for (j in 0...3)
					d = Std.int(Math.max(d, Math.abs(b.get(4 * i + j) - px.get(4 * i + j))));
				if (d > 2) some++;
				if (d > most) most = d;
				if (d > LEVELS) {
					over++;
					var x = i % W, y = Std.int(i / W);
					x0 = Std.int(Math.min(x0, x));
					y0 = Std.int(Math.min(y0, y));
					x1 = Std.int(Math.max(x1, x));
					y1 = Std.int(Math.max(y1, y));
				}
			}
			var was = strict;
			strict = true;
			check('still $n: against the textured compositor\'s, at most ${SHARE * 100}% of the pixels over $LEVELS levels', over <= SHARE * W * H,
				'$over over $LEVELS${over > 0 ? ' in $x0,$y0..$x1,$y1' : ""}, $some over 2, at most $most, of ${W * H}');
			strict = was;
		}
		App.run(() -> {
			step++;
			var now = Timer.stamp();
			switch phase {
				case 0 if (step > 10 && list.height > 0):
					if (dc != null) @:privateAccess slotted.systemLayer = new LayerSlot(dc.solid(0x31A050));
					OsThread.get(() -> User32.SetForegroundWindow(w.window.surface.handle));
					say('ready ${w.device.width}x${w.device.height}, scale $k');
					phase = 1;
					at = now;
				case 1 if (now - at > 1):
					// (the wheel while the program is blocked: the compositor scrolls)
					var inject:Null<Inject> = null;
					blocked("a scroll", () -> inject = Inject.start(w.window, 300));
					inject.join();
					say('a scroll: ${inject.sent} wheel events injected, the list at ${list.scrollY}');
					phase = 2;
					at = now;
				case 2 if (now - at > 1 && (c == null || !c.moving())):
					mover.style.transform = Transform.parse("translate(-200px, -20px)");
					mover.style.opacity = 0.5;
					phase = 3;
					at = step;
				case 3 if (step - at >= 3 && (c == null || c.due() >= 0 || step - at > 60)):
					blocked("an animation", () -> {});
					phase = 4;
					at = now;
				case 4 if (now - at > 2 && !Clock.active && (c == null || !c.moving())):
					// (whole offsets, the box at rest: a still)
					list.scrollY = 120;
					round.scrollY = 24;
					phase = 5;
					at = now;
					timed = 0;
				case 5 if (now - at > 0.5 && timed == 0):
					// (a frame of the program's once the tiles are drawn: the list from them in every mode)
					timed = 1;
					w.ui.requestFrame();
				case 5 if (now - at > 1.5):
					still(1);
					phase = 6;
					at = now;
					timed = 0;
					cpu0 = cpu();
					t0 = now;
					q0 = layers == null ? 0 : layers.quadsTotal;
				case 6:
					// (a steady scroll, the program's frames: timed)
					list.scrollY += 4;
					timed++;
					if (timed == 120) {
						var q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: steady scroll: $timed frames in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round((cpu() - cpu0) / timed * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						// (an animation the compositor draws, the program idle)
						mover.style.transition = Transition.parse("transform 3s linear, opacity 3s linear");
						mover.style.transform = Transform.parse("translate(0px, 0px)");
						mover.style.opacity = 1;
						phase = 7;
						at = now;
						cpu0 = cpu();
						t0 = now;
						q0 = layers == null ? 0 : layers.quadsTotal;
						f0 = c == null ? 0 : c.count;
						n0 = 0;
					}
				case 7:
					n0++;
					if (now - at > 3.2) {
						var f = (c == null ? 0 : c.count - f0) + n0, q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: animation: $f frames ($n0 the program\'s) in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round((cpu() - cpu0) / Math.max(1, f) * 100) / 100} ms a frame, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
						list.scrollY = 120 + 4 * 120;
						phase = 8;
						at = now;
						timed = 0;
					}
				case 8 if (now - at > 0.5 && timed == 0):
					timed = 1;
					w.ui.requestFrame();
				case 8 if (now - at > 1.5):
					still(2);
					phase = 9;
					at = now;
					timed = 0;
				case 9:
					// (the header's label each frame: the window's layer drawn where it changed)
					if (timed == 0) {
						t0 = now;
						cpu0 = cpu();
						q0 = layers == null ? 0 : layers.quadsTotal;
						f0 = layers == null ? 0 : layers.frames;
						n0 = dc == null ? 0 : dc.cutTotal;
					}
					timed++;
					title.text = "Header " + timed;
					if (timed == 60) {
						var f = layers == null ? 0 : layers.frames - f0;
						say('timed: header: $timed changes in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round((cpu() - cpu0) / timed * 100) / 100} ms a change, ${dc == null ? 0 : dc.cutTotal - n0} layers drawn in part over $f frames');
						phase = 10;
						at = now;
						timed = 0;
					}
				case 10 if (now - at > 0.5 && timed == 0):
					timed = 1;
					w.ui.requestFrame();
				case 10 if (now - at > 1.5):
					still(3);
					phase = 11;
					at = now;
				case 11:
					if (layers != null) say('layers\' surfaces ${Math.round(layers.bytes() / 1e5) / 10} MB, frames shown on them ${layers.frames}');
					if (layers != null && layers.fell != null) say('system layers fell back: ${layers.fell}');
					if (mode == "stall") {
						strict = true;
						check("the system layers fell back to the window's own frames", layers != null && layers.fell != null && layers.single, '${layers == null ? null : layers.fell}');
					}
					if (mode == "layers") {
						strict = true;
						check("the system layers stayed on", live(), '${layers == null ? null : layers.fell}');
					}
					say(failed == 0 ? "ok" : '$failed FAILED');
					w.close();
					Sys.exit(failed == 0 ? 0 : 1);
				case _:
			}
			if (w.needsFrame()) w.frame() else App.wait(0.004);
			w.device.settle();
		}, e -> if (e.kind == helder.os.Event.EventKind.Close) w.close() else w.handle(e));
	}

	// (the process's CPU time, ms: its kernel's and user's)
	static function cpu():Float
		return Arena.scopedValue(a -> {
			var t:Ptr<Int64> = a.alloc(32);
			ProcessTimes.GetProcessTimes(ProcessTimes.GetCurrentProcess(), t, t.offset(1), t.offset(2), t.offset(3));
			var k:Ptr<Int32> = t.raw();
			inline function ft(i:Int):Float
				return (k[2 * i + 1] * 4294967296.0 + (k[2 * i] < 0 ? k[2 * i] + 4294967296.0 : k[2 * i])) / 1e4;
			ft(2) + ft(3);
		});

	// (the client area's pixels as RGBA, on the main thread: PrintWindow,
	// which composes the window's DirectComposition content, else the
	// screen's where the window is)
	static function capture(w:Window, width:Int, height:Int):Null<Bytes> {
		var hwnd = w.surface.handle;
		return OsThread.get(() -> {
			var rgba:Null<Bytes> = null;
			Arena.scoped(a -> {
				var screen = User32.GetDC(Ptr.nil());
				var dc = Gdi32.CreateCompatibleDC(screen);
				var info = a.make(BITMAPINFOHEADER);
				info.value.biSize = 40;
				info.value.biWidth = width;
				info.value.biHeight = -height;
				info.value.biPlanes = 1;
				info.value.biBitCount = 32;
				var bits:Ptr<Ptr> = a.alloc(8);
				var bmp = Gdi32.CreateDIBSection(dc, info, 0, bits, Ptr.nil(), 0);
				if (!bmp.isNull()) {
					var old = Gdi32.SelectObject(dc, bmp);
					var px:Ptr<UInt8> = bits.value;
					var ok = User32.PrintWindow(hwnd, dc, WM.PW_CLIENTONLY | WM.PW_RENDERFULLCONTENT) != 0;
					Gdi32.GdiFlush();
					var c = 4 * ((height >> 1) * width + (width >> 1));
					if (!ok || px[c] + px[c + 1] + px[c + 2] == 0) {
						Sys.println("WinLayersWindow: PrintWindow drew nothing: the screen's pixels");
						var p = a.make(POINT);
						User32.ClientToScreen(hwnd, p);
						ok = Gdi32.BitBlt(dc, 0, 0, width, height, screen, p.value.x, p.value.y, WM.SRCCOPY) != 0;
						Gdi32.GdiFlush();
					}
					if (ok) {
						var out = Bytes.alloc(width * height * 4);
						for (i in 0...width * height) {
							out.set(4 * i, px[4 * i + 2]);
							out.set(4 * i + 1, px[4 * i + 1]);
							out.set(4 * i + 2, px[4 * i]);
							out.set(4 * i + 3, 255);
						}
						rgba = out;
					}
					Gdi32.SelectObject(dc, old);
					Gdi32.DeleteObject(bmp);
				}
				Gdi32.DeleteDC(dc);
				User32.ReleaseDC(Ptr.nil(), screen);
			});
			rgba;
		});
	}
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class ProcessTimes {
	static function GetCurrentProcess():Ptr;
	static function GetProcessTimes(process:Ptr, creation:Ptr<Int64>, exit:Ptr<Int64>, kernel:Ptr<Int64>, user:Ptr<Int64>):Int;
}
