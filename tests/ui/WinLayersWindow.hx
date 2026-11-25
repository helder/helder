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
		var presents:Array<Float> = [], offsets:Array<Float> = [], plock = new sys.thread.Mutex();
		// (each compositor frame's timing, printed for a phase whose pace failed)
		if (c != null) c.probe = [];
		if (c != null) c.onFrame = t -> {
			var o = c.offsets(list);
			plock.acquire();
			presents.push(t);
			offsets.push(o == null ? -1 : o.y);
			plock.release();
		};
		function live():Bool
			return layers != null && layers.fell == null;
		// (frames n in s seconds no faster than the display's (the compositor's period, learnt from its frames), a third over it at most)
		// (the window's own swap chain's too: one frame queued at most, the program's and the compositor's each waiting for it)
		function paced(what:String, n:Int, s:Float) {
			var rate = n / s, hz = c == null ? 60.0 : 1 / @:privateAccess c.period, was = strict;
			strict = was && (mode == "textured" || live());
			check('$what: paced to the display', rate <= hz * 1.33, '${Math.round(rate)} frames a second, the display ${Math.round(hz)}');
			strict = was;
		}
		// (a phase blocking the program: frames presented meanwhile, their gaps, the layers' frames and quads)
		function blocked(what:String, before:Void->Void):Array<Float> {
			var was = strict;
			strict = was && (mode == "textured" || live());
			var t0 = dc == null ? [] : dc.timing.copy(), f0 = layers == null ? 0 : layers.frames, q0 = layers == null ? 0 : layers.quadsTotal;
			var from = Timer.stamp();
			before();
			Sys.sleep(0.3);
			var to = Timer.stamp();
			plock.acquire();
			var during = [for (t in presents) if (t > from && t <= to) t];
			var moved = [for (i in 0...presents.length) if (presents[i] > from && presents[i] <= to) offsets[i]];
			plock.release();
			var gaps = [for (i in 1...during.length) during[i] - during[i - 1]];
			gaps.sort(Reflect.compare);
			var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
			check('$what: frames presented while the program was blocked 300 ms', during.length >= 10, during.length + " frames");
			var paced = gaps.length > 0 && median < 0.03, gap = "median gap " + Math.round(median * 10000) / 10 + " ms";
			var bound = paced || c == null ? null : gpuBound(c, from, to);
			if (bound == null) check('$what: at the display\'s pace', paced, gap) else {
				var was = strict;
				strict = false;
				check('$what: at the display\'s pace', false, '$gap: bound by the software adapter (its GPU or DWM on it), $bound');
				strict = was;
			}
			if (c != null) summary(what, c, from, to);
			if (!paced && c != null) probes(what, c, from - 0.05, to);
			if (dc != null) {
				var d = [for (i in 0...4) Math.round((dc.timing[i] - t0[i]) * 1000)];
				say('$what: the render thread: showing ${d[0]} ms, drawing ${d[1]}, waiting for the last commit ${d[2]}, for DWM\'s next composition ${d[3]}, frames ${layers.frames - f0}');
			}
			if (live() && !layers.single) {
				var f = layers.frames - f0, q = layers.quadsTotal - q0;
				check('$what: on the system\'s layers, moved, not drawn', f > 0 && q <= 8 * f, '$f frames, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
			}
			strict = was;
			return moved;
		}
		var step = 0, phase = 0, at = 0.0, k = w.window.scale, timed = 0, cpu0 = 0.0, t0 = 0.0, q0 = 0, f0 = 0, n0 = 0, scrolled = 0.0;
		// (pixels over LEVELS in rows 0 to rows of two captures, a few of them: x,y a>b)
		function band(a:Bytes, b:Bytes, W:Int, rows:Int):{over:Int, samples:String} {
			var over = 0, samples = [];
			for (i in 0...W * rows) {
				var d = 0;
				for (j in 0...3)
					d = Std.int(Math.max(d, Math.abs(a.get(4 * i + j) - b.get(4 * i + j))));
				if (d <= LEVELS) continue;
				over++;
				if (samples.length < 8) samples.push('${i % W},${Std.int(i / W)} ${StringTools.hex(a.get(4 * i) << 16 | a.get(4 * i + 1) << 8 | a.get(4 * i + 2), 6)}>${StringTools.hex(b.get(4 * i) << 16 | b.get(4 * i + 1) << 8 | b.get(4 * i + 2), 6)}');
			}
			return {over: over, samples: samples.join(" ")};
		}
		function still(n:Int) {
			var px = capture(w.window, w.device.width, w.device.height);
			if (px == null) {
				check('still $n: captured', false, "no capture");
				return;
			}
			var file = '$dir/still$n-$mode.rgba';
			sys.io.File.saveBytes(file, px);
			// (and for the job's artifacts: bin/text/*.png)
			sys.FileSystem.createDirectory("bin/text");
			sys.io.File.saveBytes('bin/text/winlayers-still$n-$mode.png', helder.image.PngEncoder.encode(px, w.device.width, w.device.height, true));
			var o = c == null ? null : c.offsets(list);
			say('still $n: the list at ${list.scrollY} (the compositor\'s ${o == null ? null : o.y}), the slot\'s node at ${slotted.absX}, ${slotted.absY}');
			// (the system layer's colour where it is: which shows)
			var sx = Math.round((slotted.absX + 30) * k), sy = Math.round((slotted.absY + 6) * k);
			if (sy > 40 * k && sy < w.device.height) {
				var o = 4 * (sy * w.device.width + sx);
				say('still $n: at the system layer ($sx, $sy) ${StringTools.hex(px.get(o) << 16 | px.get(o + 1) << 8 | px.get(o + 2), 6)} (its own 31a050, its node\'s 30a050)');
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
			var over = 0, some = 0, most = 0, x0 = W, y0 = H, x1 = -1, y1 = -1, samples:Array<String> = [];
			// (the rounded scroller's corners: what over LEVELS falls within its radius and a pixel of each, and its most)
			var rx0 = Math.round(round.absX * k), ry0 = Math.round(round.absY * k), rx1 = Math.round((round.absX + 120) * k), ry1 = Math.round((round.absY + 100) * k);
			var rr = Math.round(14 * k) + 1, corner = [0, 0, 0, 0], cornerMost = [0, 0, 0, 0], inside = 0;
			for (i in 0...W * H) {
				var d = 0;
				for (j in 0...3)
					d = Std.int(Math.max(d, Math.abs(b.get(4 * i + j) - px.get(4 * i + j))));
				if (d > 2) some++;
				if (d > most) most = d;
				if (d > LEVELS) {
					over++;
					var x = i % W, y = Std.int(i / W);
					if (samples.length < 6) samples.push('$x,$y ${StringTools.hex(b.get(4 * i) << 16 | b.get(4 * i + 1) << 8 | b.get(4 * i + 2), 6)}>${StringTools.hex(px.get(4 * i) << 16 | px.get(4 * i + 1) << 8 | px.get(4 * i + 2), 6)}');
					var cx = x < rx0 + rr ? 0 : x >= rx1 - rr ? 1 : -1, cy = y < ry0 + rr ? 0 : y >= ry1 - rr ? 1 : -1;
					if (x >= rx0 && x < rx1 && y >= ry0 && y < ry1) {
						inside++;
						if (cx >= 0 && cy >= 0) {
							var j = cy * 2 + cx;
							corner[j]++;
							if (d > cornerMost[j]) cornerMost[j] = d;
						}
					}
					x0 = Std.int(Math.min(x0, x));
					y0 = Std.int(Math.min(y0, y));
					x1 = Std.int(Math.max(x1, x));
					y1 = Std.int(Math.max(y1, y));
				}
			}
			if (over > 0) say('still $n: over $LEVELS levels (textured>here): ${samples.join(" ")}; in the rounded scroller $inside, at its corners (top left, top right, bottom left, bottom right) $corner, at most $cornerMost');
			var was = strict;
			strict = true;
			check('still $n: against the textured compositor\'s, at most ${SHARE * 100}% of the pixels over $LEVELS levels', over <= SHARE * W * H,
				'$over over $LEVELS${over > 0 ? ' in $x0,$y0..$x1,$y1' : ""}, $some over 2, at most $most, of ${W * H}');
			// (the header, its label changed each frame before still 3: drawn in part, as the textured compositor's)
			var h = band(b, px, W, Math.round(40 * k));
			check('still $n: the header as the textured compositor\'s, none over $LEVELS levels', h.over == 0, '${h.over} over $LEVELS${h.over > 0 ? ": " + h.samples : ""}');
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
					var moved = blocked("a scroll", () -> inject = Inject.start(w.window, 300));
					inject.join();
					// (the compositor's offsets of the list as its frames drew it: the program has them at its next turn)
					var was = strict;
					strict = true;
					check("a scroll: the list's offset advancing in the compositor's frames", moved.length > 1 && moved[moved.length - 1] > moved[0],
						'${inject.sent} wheel events, ' + (moved.length > 0 ? '${moved[0]} to ${moved[moved.length - 1]}' : "no frame"));
					strict = was;
					scrolled = moved.length > 0 ? moved[moved.length - 1] : 0;
					phase = 2;
					at = now;
				case 2 if (now - at > 1 && (c == null || !c.moving())):
					var was = strict;
					strict = true;
					check("a scroll: the program has the compositor's offset", list.scrollY > 0 && list.scrollY >= scrolled, '$scrolled, the list at ${list.scrollY}');
					strict = was;
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
						say('timed: steady scroll: $timed frames in ${Math.round((now - t0) * 10) / 10} s (${Math.round(timed / (now - t0))} a second), CPU ${Math.round((cpu() - cpu0) / timed * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						paced("timed: steady scroll", timed, now - t0);
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
						// (the program's frames drawn, not the loop's turns: an idle turn waits 4 ms)
						n0 = @:privateAccess w.device.frames;
					}
				case 7:
					if (now - at > 3.2) {
						n0 = @:privateAccess w.device.frames - n0;
						var f = (c == null ? 0 : c.count - f0) + n0, q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: animation: $f frames ($n0 the program\'s) in ${Math.round((now - t0) * 10) / 10} s (${Math.round(f / (now - t0))} a second), CPU ${Math.round((cpu() - cpu0) / Math.max(1, f) * 100) / 100} ms a frame, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
						paced("timed: animation", f, now - t0);
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
					if (dc != null) say('still 3: "${title.text}", the window\'s layer drawn ${@:privateAccess layers.base.serial} times, last in part over ${dc.lastCut}, the label at ${Math.round(title.absX * k)},${Math.round(title.absY * k)} ${Math.round(title.width * k)}x${Math.round(title.height * k)}');
					phase = live() || mode == "textured" ? 12 : 11;
					at = now;
				case 12 if (timed == 1):
					// (the same frame drawn whole: the layers drawn again; the textured
					// compositor's frame kept let go, the next drawn whole)
					timed = 2;
					if (dc != null) @:privateAccess for (p in dc.all())
						p.invalidate()
					else @:privateAccess w.renderer.keptValid = false;
					w.ui.requestFrame();
				case 12 if (now - at > 1.5):
					var W = w.device.width, rows = Math.round(40 * k);
					var cut = sys.io.File.getBytes('$dir/still3-$mode.rgba'), px = capture(w.window, W, w.device.height);
					if (px == null) {
						check("still 3 drawn whole: captured", false, "no capture");
						phase = 11;
					} else {
						sys.io.File.saveBytes('$dir/still3w-$mode.rgba', px);
						sys.io.File.saveBytes('bin/text/winlayers-still3w-$mode.png', helder.image.PngEncoder.encode(px, W, w.device.height, true));
						var h = band(cut, px, W, rows), was = strict;
						if (mode == "textured") {
							// (its frame kept, drawn where it changed and presented with those rectangles)
							strict = true;
							check("still 3: the textured compositor's header drawn in part as drawn whole", h.over == 0, '${h.over} over $LEVELS (in part>whole)${h.over != 0 ? ": " + h.samples : ""}');
						} else {
							strict = true;
							check("still 3: the layers' header drawn in part as the same frame drawn whole, none over 8 levels", h.over == 0, '${h.over} over $LEVELS (in part>whole)${h.over != 0 ? ": " + h.samples : ""}');
							var ref = '$dir/still3w-textured.rgba';
							var t = sys.FileSystem.exists(ref) ? band(sys.io.File.getBytes(ref), cut, W, rows) : {over: -1, samples: "no " + ref};
							check("still 3: the layers' header drawn in part as the textured compositor's drawn whole, none over 8 levels", t.over == 0, '${t.over} over $LEVELS (textured whole>layers in part)${t.over != 0 ? ": " + t.samples : ""}');
						}
						strict = was;
						phase = 11;
					}
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

	// (the compositor's frames from t0 to t1, ms from t0: when the render
	// thread came to each (due: right after the last frame's end if that one
	// was paced, else half a period after it, or the program's turn after
	// input), the swap chain's wait, its end, paced, the 1 ms timer, Present's HRESULT)
	// (the compositor's frames drawn from t0 to t1, each its PROBE values)
	static function probed(c:Compositor, t0:Float, t1:Float):Array<Array<Float>> {
		var p = @:privateAccess c.lock;
		p.acquire();
		var a = c.probe.copy();
		p.release();
		var n = Compositor.PROBE;
		return [for (i in 0...Std.int(a.length / n)) if (a[i * n] >= t0 && a[i * n] <= t1) a.slice(i * n, i * n + n)];
	}

	static function middle(v:Array<Float>):Float {
		if (v.length == 0) return -1;
		v.sort(Reflect.compare);
		return Math.round(v[v.length >> 1] * 10) / 10;
	}

	// (a phase's frames: how many, their quads, the pixels they cover, their GPU time, their swap chain's wait)
	static function summary(what:String, c:Compositor, t0:Float, t1:Float) {
		var f = [for (p in probed(c, t0, t1)) if (p[4] >= 0) p];
		say('$what: the compositor\'s ${f.length} frames, medians: ${middle([for (p in f) p[9]])} quads, ${middle([for (p in f) p[10]])}k pixels covered, '
			+ 'GPU ${middle([for (p in f) p[8]])} ms, the swap chain\'s wait ${middle([for (p in f) p[3]])} ms${f.length > 0 && f[0][11] == 1 ? " (a software adapter)" : ""}');
	}

	// (a phase slower than the display's pace whose frames were all on time:
	// each paced (its swap chain's wait the one before it) and presented
	// (Present's S_OK, not OCCLUDED), the time in that wait itself, over
	// most of a period: what the adapter took to show the last one, its
	// GPU's work or DWM's composition of it. Only Microsoft's software
	// adapter's (WARP, the Basic Render Driver: CI's runners, where both run
	// on the CPU's few threads, a frame's own GPU time 4 ms) is let go so;
	// on a GPU the display's pace is the check's. The lock's
	// signatures fail wherever they show: frames not paced, OCCLUDED, the
	// time before the wait (a coarse timer). Why, else null)
	static function gpuBound(c:Compositor, t0:Float, t1:Float):Null<String> {
		var f = [for (p in probed(c, t0, t1)) if (p[4] >= 0) p];
		if (f.length < 3 || f[0][11] != 1) return null;
		var period = @:privateAccess c.period * 1000;
		for (i in 0...f.length) {
			var p = f[i];
			if (p[7] != 0 || p[5] != 1 || (i > 0 && p[2] != 1)) return null;
		}
		var wait = middle([for (p in f) p[3]]);
		if (wait < period * 0.75) return null;
		return 'each frame paced and presented, the swap chain\'s wait $wait ms of a ${Math.round(period * 10) / 10} ms period';
	}

	static function probes(what:String, c:Compositor, t0:Float, t1:Float) {
		var ms = (t:Float) -> Math.round((t - t0) * 10000) / 10;
		say('$what: probes (ms from the phase; came, last end, last paced, waited, end, paced, 1 ms timer, Present 0x, GPU ms, quads, k pixels)');
		for (p in probed(c, t0, t1))
			say('  ${ms(p[0])} ${ms(p[1])} ${p[2]} ${Math.round(p[3] * 10) / 10} ${p[4] < 0 ? "turn" : "" + ms(p[4])} ${p[5]} ${p[6]} ${StringTools.hex(Std.int(p[7]))} ${Math.round(p[8] * 10) / 10} ${p[9]} ${Math.round(p[10])}');
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
