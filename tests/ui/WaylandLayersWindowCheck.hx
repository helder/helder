import haxe.Timer;
import haxe.io.Bytes;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// Wayland's system layers (helder.ui.layers.linux.Layers, subsurfaces) in a
// real window under a headless weston (the wayland lane, tests/os/wayland.sh;
// its kiosk shell, the output the window's size: the window at its corner): a list with a system layer in a row, a rounded scroller, a
// square box that moves. A finger flings the list and the program blocks
// 300 ms, then the box animates while it blocks: frames keep coming, the
// list's and the box's layers moved, not drawn (quads drawn a frame), the
// list's offset advancing; the list is a layer of its own, the box one
// colour's (a single-pixel buffer); stills of the output
// (weston-screenshooter) against the textured compositor's (its own run's,
// written to dir), one with the list at rest where the program put it, one
// with the system layer cut by the list's clip; a steady scroll and an
// animation timed (the process's CPU a frame: llvmpipe draws, so the GPU's
// work is the process's too), then the header's label changed each frame
// (the window's layer drawn where it changed) and a still after it. A
// headless compositor's clock is its own: the pace is checked loosely (no
// faster than twice its period, frames at most 50 ms apart).
//   WaylandLayersWindowCheck <dir> textured|layers|stall [--quick]
//   (HELDER_SYSTEM_LAYERS=0 for textured, =stall for stall: nothing
//   counted shown, the layers must fall back while running, its stills the
//   textured's after; --quick: nothing timed, no header phase, no still 3)
class WaylandLayersWindowCheck {
	static var failed = 0;
	static var strict = true;

	static function check(what:String, ok:Bool, detail:String) {
		if (!ok && strict) failed++;
		Sys.println('WaylandLayersWindowCheck: ${ok ? "ok" : strict ? "FAIL" : "reported"}: $what ($detail)');
	}

	static function say(s:String)
		Sys.println("WaylandLayersWindowCheck: " + s);

	// (pixels over this many levels, at most this share of them)
	static inline var LEVELS = 8;
	static inline var SHARE = 0.002;

	static function main() {
		var a = Sys.args(), dir = a[0], mode = a[1], quick = a.indexOf("--quick") >= 0;
		if (dir == null || !["textured", "layers", "stall"].contains(mode)) {
			Sys.println("usage: WaylandLayersWindowCheck <dir> textured|layers|stall");
			Sys.exit(2);
		}
		sys.FileSystem.createDirectory(dir);
		var w = new helder.ui.UiWindow({title: "WaylandLayersWindowCheck", width: 400, height: 300});
		var root = w.root;
		root.style = root.style.with({flexDirection: Column, background: 0xFFFFFFFF});
		var header = new Node();
		header.style = Style.of({height: 40, flexShrink: 0, background: 0xFF18181B, padding: 10});
		var title = new TextNode("Header");
		title.style = title.style.with({color: 0xFFFFFFFF, fontSize: 14});
		header.append(title);
		root.append(header);
		var list = new Node();
		list.style = Style.of({flexGrow: 1, minHeight: 0, width: 240, overflow: Scroll, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		var rows = [];
		for (i in 0...200) {
			var row = new Node();
			rows.push(row);
			row.style = Style.of({flexDirection: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style = Style.of({width: 12, height: 12, borderRadius: 3, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		root.append(list);
		// (a node's system layer in a row: its colour a level off the node's own)
		var slotted = new Node();
		slotted.style = Style.of({position: Absolute, left: 120, top: 2, width: 60, height: 12, background: 0xFF30A050});
		rows[40].style = rows[40].style.with({position: Relative});
		rows[40].append(slotted);
		var round = new Node();
		round.style = Style.of({position: Absolute, left: 260, top: 56, width: 120, height: 100, borderRadius: 14, overflow: Scroll, background: 0xFFFFE08A});
		for (i in 0...12) {
			var r = new Node();
			r.style = Style.of({height: 20, flexShrink: 0, background: i % 2 == 0 ? 0xFFF59E0B : 0xFFFFE08A});
			round.append(r);
		}
		root.append(round);
		// (square, of one colour: a single-pixel buffer on the layers)
		var mover = new Node();
		mover.style = Style.of({position: Absolute, left: 270, top: 180, width: 80, height: 50, background: 0xFF2A7AE2, transform: Transform.parse("translate(0px, 0px)"), transition: Transition.parse("transform 1.5s linear")});
		root.append(mover);
		var c = w.compositor;
		var layers = c == null ? null : c.layers, wl = layers == null ? null : Std.downcast(layers, helder.ui.layers.linux.Layers);
		strict = mode != "stall";
		say('start: $mode, compositor ${c != null}, system layers ${layers != null}');
		if (c == null || mode != "textured" && wl == null) {
			say('FAIL: ${c == null ? "no compositor" : "no system layers (subsurfaces)"} here');
			w.close();
			Sys.exit(1);
		}
		var presents:Array<Float> = [], offsets:Array<Float> = [], plock = new sys.thread.Mutex();
		c.onFrame = t -> {
			var o = c.offsets(list);
			plock.acquire();
			presents.push(t);
			offsets.push(o == null ? -1 : o.y);
			plock.release();
		};
		function live():Bool
			return layers != null && layers.fell == null;
		// (frames n in s seconds no faster than twice the compositor's period: a headless one keeps its own)
		function paced(what:String, n:Int, s:Float) {
			var rate = n / s, hz = 1 / @:privateAccess c.period, was = strict;
			// (the window's own frames on Wayland are not paced: its swap interval 0, the loop's own pace; reported)
			strict = was && mode != "textured" && live();
			check('$what: paced', rate <= hz * 2, '${Math.round(rate)} frames a second, the compositor\'s period ${Math.round(1000 / hz * 10) / 10} ms');
			strict = was;
		}
		// (a phase blocking the program: frames presented meanwhile, their gaps, the layers' frames and quads)
		// (the compositor scrolls no farther than what the program's last frame recorded (#479): the list recorded
		// again around what is seen, a viewport each way as at first, so what the block scrolls fits, as #494)
		function prime() {
			var cl = @:privateAccess list.contentLayer;
			if (cl != null) @:privateAccess {
				cl.recordedAt = -1;
				cl.x0 = cl.y0 = cl.x1 = cl.y1 = 0;
			}
			w.ui.requestFrame();
		}
		function blocked(what:String, before:Void->Void):Array<Float> {
			var was = strict;
			strict = was && (mode == "textured" || live());
			var t0 = wl == null ? [] : wl.timing.copy(), f0 = layers == null ? 0 : layers.frames, q0 = layers == null ? 0 : layers.quadsTotal;
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
			check('$what: frames presented while the program was blocked 300 ms', during.length >= 6, during.length + " frames");
			check('$what: frames at most 50 ms apart', gaps.length > 0 && median < 0.05, "median gap " + Math.round(median * 10000) / 10 + " ms");
			if (wl != null) {
				var d = [for (i in 0...4) Math.round((wl.timing[i] - t0[i]) * 1000)];
				say('$what: the render thread: showing ${d[0]} ms, drawing ${d[1]}, waiting for a buffer ${d[2]}, for the last commit\'s presentation ${d[3]}, frames ${layers.frames - f0}');
			}
			if (live() && !layers.single) {
				var f = layers.frames - f0, q = layers.quadsTotal - q0;
				check('$what: on the system\'s layers, moved, not drawn', f > 0 && q <= 8 * f, '$f frames, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
			}
			strict = was;
			return moved;
		}
		var step = 0, phase = 0, at = 0.0, k = 1.0, timed = 0, cpu0 = 0.0, t0 = 0.0, q0 = 0, f0 = 0, n0 = 0, flung = 0.0;
		// (the pixels of two captures over LEVELS in a rectangle, a few of them: x,y a>b)
		function over(a:Bytes, b:Bytes, W:Int, x0:Int, y0:Int, x1:Int, y1:Int):{over:Int, most:Int, samples:String} {
			var n = 0, most = 0, samples = [];
			for (y in y0...y1)
				for (x in x0...x1) {
					var i = y * W + x, d = 0;
					for (j in 0...3)
						d = Std.int(Math.max(d, Math.abs(a.get(4 * i + j) - b.get(4 * i + j))));
					if (d > most) most = d;
					if (d <= LEVELS) continue;
					n++;
					if (samples.length < 8) samples.push('$x,$y ${hex(a, i)}>${hex(b, i)}');
				}
			return {over: n, most: most, samples: samples.join(" ")};
		}
		var W = 0, H = 0;
		function still(n:Int):Null<Bytes> {
			var px = capture(dir);
			if (px == null) {
				check('still $n: captured', false, "no capture (weston-screenshooter)");
				return null;
			}
			W = px.width;
			H = px.height;
			var file = '$dir/still$n-$mode.rgba';
			sys.io.File.saveBytes(file, px.rgba);
			sys.io.File.saveBytes('$dir/wllayers-still$n-$mode.png', helder.image.PngEncoder.encode(px.rgba, W, H, true));
			var o = c.offsets(list);
			say('still $n: ${W}x$H, the list at ${list.scrollY} (the compositor\'s ${o == null ? null : o.y}), the slot\'s node at ${slotted.absX}, ${slotted.absY}');
			if (mode == "textured") return px.rgba;
			var ref = '$dir/still$n-textured.rgba';
			if (!sys.FileSystem.exists(ref)) {
				check('still $n: against the textured compositor\'s', false, "no " + ref);
				return px.rgba;
			}
			var b = sys.io.File.getBytes(ref);
			if (b.length != px.rgba.length) {
				check('still $n: against the textured compositor\'s', false, 'sizes ${b.length} and ${px.rgba.length}');
				return px.rgba;
			}
			var was = strict, all = over(b, px.rgba, W, 0, 0, W, H);
			strict = true;
			check('still $n: against the textured compositor\'s, at most ${SHARE * 100}% of the pixels over $LEVELS levels', all.over <= SHARE * W * H,
				'${all.over} over $LEVELS, at most ${all.most}, of ${W * H}${all.over > 0 ? ": " + all.samples : ""}');
			var h = over(b, px.rgba, W, 0, 0, W, Math.round(40 * k));
			check('still $n: the header as the textured compositor\'s, none over $LEVELS levels', h.over == 0, '${h.over} over $LEVELS${h.over > 0 ? ": " + h.samples : ""}');
			strict = was;
			return px.rgba;
		}
		// (the system layer's colour where its node is (its own 31a050, its
		// node's 30a050), its top half over the header, cut by the list's clip)
		function slot(px:Bytes, n:Int) {
			var y = slotted.absY - list.scrollY, x = Math.round((slotted.absX + 30) * k), top = Math.round(list.absY * k);
			var inY = Math.round((y + 9) * k), outY = Math.round((y + 3) * k);
			if (px == null || W == 0 || inY < top || inY >= H || outY >= top) {
				check('still $n: the system layer across the list\'s top edge', false, 'its node at $y, the list\'s top ${list.absY}');
				return;
			}
			var i = inY * W + x, ok = hex(px, i) == "31a050";
			say('still $n: at the system layer ($x, $inY) ${hex(px, i)}' + (outY < top ? ', above the list\'s clip ($x, $outY) ${hex(px, outY * W + x)}' : ""));
			if (mode == "layers") check('still $n: the system layer shown at its node, its own colour', ok, hex(px, i));
			if (mode == "layers") check('still $n: the system layer cut by the list\'s clip', hex(px, outY * W + x) != "31a050", hex(px, outY * W + x));
		}
		App.run(() -> {
			step++;
			var now = Timer.stamp();
			switch phase {
				case 0 if (step > 10 && list.height > 0):
					phase = 1;
					at = now;
				case 1 if (now - at > 1):
					k = w.window.scale;
					if (wl != null) @:privateAccess slotted.systemLayer = new LayerSlot(wl.solid(0x31A050));
					say('ready ${w.device.width}x${w.device.height}, scale $k');
					phase = 2;
					at = now;
					f0 = layers == null ? 0 : layers.frames;
				case 2 if (now - at < 3 && live() && layers.frames < f0 + 2):
					// (frames of the program's on the layers first: their first draw not the fling's)
					w.ui.requestFrame();
				case 2 if (now - at > 0.5):
					if (live()) {
						var was = strict;
						strict = mode == "layers";
						var units = @:privateAccess layers.units;
						var scrolls = [for (u in units) if (u.kind == helder.ui.layers.LayerPlane.SCROLL) u], movers = [for (u in units) if (u.kind == helder.ui.layers.LayerPlane.MOVER) u];
						check("the list on a layer of its own", Lambda.exists(scrolls, u -> u.key == list), '${units.length} units, ${scrolls.length} scrollers\', the rest drawn: ${layers.reasons}');
						check("the rounded scroller drawn", !Lambda.exists(scrolls, u -> u.key == round), "rounds false");
						strict = was;
					}
					prime();
					phase = 21;
					at = step;
				case 21 if (step - at >= 3):
					// (a finger's fling, then the program busy: the compositor glides, gently: about 150 points, within
					// what was recorded)
					var t = Timer.stamp() * 1000;
					for (i in 0...8)
						touch(w, i == 0 ? PointerDown : PointerMove, 120, 250 - i * 8, t + i * 16);
					touch(w, PointerUp, 120, 250 - 7 * 8, t + 8 * 16);
					flung = list.scrollY;
					var moved = blocked("a fling", () -> {});
					var was = strict;
					strict = true;
					check("a fling: the list's offset advancing in the compositor's frames", moved.length > 1 && moved[moved.length - 1] > moved[0],
						moved.length > 0 ? '${moved[0]} to ${moved[moved.length - 1]}' : "no frame");
					strict = was;
					phase = 3;
					at = now;
				case 3 if (now - at > 1 && !c.moving()):
					var o = c.offsets(list), was = strict;
					strict = true;
					check("a fling: the program has the compositor's offset", o != null && list.scrollY == o.y && list.scrollY > flung, '$flung to ${list.scrollY} ${o == null ? null : o.y}');
					strict = was;
					mover.style = mover.style.with({transform: Transform.parse("translate(-200px, -20px)")});
					phase = 4;
					at = step;
				case 4 if (step - at >= 3 && (c.due() >= 0 || step - at > 60)):
					blocked("an animation", () -> {});
					if (live()) {
						var was = strict, movers = [for (u in @:privateAccess layers.units) if (u.kind == helder.ui.layers.LayerPlane.MOVER) u];
						strict = mode == "layers";
						check("the box on a layer of its own while it moves", movers.length == 1, '${movers.length} movers\'');
						strict = was;
					}
					phase = 5;
					at = now;
				case 5 if (now - at > 2 && !Clock.active && !c.moving()):
					// (whole offsets, the box at rest: a still)
					list.scrollY = 120;
					round.scrollY = 24;
					phase = 6;
					at = now;
					timed = 0;
				case 6 if (now - at > 0.5 && timed == 0):
					// (a frame of the program's once the tiles are drawn: the list from them in every mode)
					timed = 1;
					w.ui.requestFrame();
				case 6 if (now - at > 1.5):
					still(1);
					if (wl != null) say('still 1: one colour\'s layers ${wl.solidTotal}, buffers: ${wl.dmabufTotal} dma-bufs, ${wl.shmTotal} of wl_shm');
					if (mode == "layers") check("the box a single-pixel buffer", wl.solidTotal > 0, '${wl.solidTotal} layers of one colour');
					phase = 7;
					if (quick) {
						// (as the timed phases leave it: the box back, the list at the system layer)
						mover.style = mover.style.with({transition: Transition.parse("transform 0.05s linear"), transform: Transform.parse("translate(0px, 0px)")});
						list.scrollY = slotted.absY - list.absY + 6;
						phase = 9;
						at = now;
					}
					timed = 0;
					cpu0 = Sys.cpuTime();
					t0 = now;
					q0 = layers == null ? 0 : layers.quadsTotal;
				case 7:
					// (a steady scroll, the program's frames: timed)
					list.scrollY += 4;
					timed++;
					if (timed == 120) {
						var q = layers == null ? 0 : layers.quadsTotal - q0;
						say('timed: steady scroll: $timed frames in ${Math.round((now - t0) * 10) / 10} s (${Math.round(timed / (now - t0))} a second), CPU ${Math.round((Sys.cpuTime() - cpu0) * 1000 / timed * 100) / 100} ms a frame, ${Math.round(q / timed * 10) / 10} quads drawn a frame');
						paced("timed: steady scroll", timed, now - t0);
						// (an animation the compositor draws, the program idle)
						mover.style = mover.style.with({transition: Transition.parse("transform 3s linear"), transform: Transform.parse("translate(0px, 0px)")});
						phase = 8;
						at = now;
						cpu0 = Sys.cpuTime();
						t0 = now;
						q0 = layers == null ? 0 : layers.quadsTotal;
						f0 = c.count;
						n0 = @:privateAccess w.device.frames;
					}
				case 8 if (now - at > 3.2):
					n0 = @:privateAccess w.device.frames - n0;
					var f = c.count - f0 + n0, q = layers == null ? 0 : layers.quadsTotal - q0;
					say('timed: animation: $f frames ($n0 the program\'s) in ${Math.round((now - t0) * 10) / 10} s (${Math.round(f / (now - t0))} a second), CPU ${Math.round((Sys.cpuTime() - cpu0) * 1000 / Math.max(1, f) * 100) / 100} ms a frame, ${Math.round(q / Math.max(1, f) * 10) / 10} quads drawn a frame');
					paced("timed: animation", f, now - t0);
					// (row 40's system layer across the list's top edge: cut by its clip)
					list.scrollY = slotted.absY - list.absY + 6;
					phase = 9;
					at = now;
					timed = 0;
				case 9 if (now - at > 0.5 && timed == 0):
					timed = 1;
					w.ui.requestFrame();
				case 9 if (now - at > 1.5):
					slot(still(2), 2);
					phase = quick ? 12 : 10;
					at = now;
					timed = 0;
				case 10:
					// (the header's label each frame: the window's layer drawn where it changed)
					if (timed == 0) {
						t0 = now;
						cpu0 = Sys.cpuTime();
						f0 = layers == null ? 0 : layers.frames;
						n0 = wl == null ? 0 : wl.cutTotal;
					}
					timed++;
					title.text = "Header " + timed;
					if (timed == 60) {
						var f = layers == null ? 0 : layers.frames - f0;
						say('timed: header: $timed changes in ${Math.round((now - t0) * 10) / 10} s, CPU ${Math.round((Sys.cpuTime() - cpu0) * 1000 / timed * 100) / 100} ms a change, ${wl == null ? 0 : wl.cutTotal - n0} layers drawn in part over $f frames');
						if (mode == "layers") check("the header: the window's layer drawn in part", wl.cutTotal - n0 > 30, '${wl.cutTotal - n0} of $f frames');
						phase = 11;
						at = now;
						timed = 0;
					}
				case 11 if (now - at > 0.5 && timed == 0):
					timed = 1;
					w.ui.requestFrame();
				case 11 if (now - at > 1.5):
					still(3);
					phase = 12;
				case 12:
					if (layers != null) say('layers\' buffers ${Math.round(layers.bytes() / 1e5) / 10} MB, frames shown on them ${layers.frames}');
					if (layers != null && layers.fell != null) say('system layers fell back: ${layers.fell}');
					strict = true;
					if (mode == "stall") check("the system layers fell back to the window's own frames", layers != null && layers.fell != null && layers.single, '${layers == null ? null : layers.fell}');
					if (mode == "layers") check("the system layers stayed on", live(), '${layers == null ? null : layers.fell}');
					say(failed == 0 ? "ok" : '$failed FAILED');
					w.close();
					Sys.exit(failed == 0 ? 0 : 1);
				case _:
			}
			if (w.needsFrame()) w.frame() else App.wait(0.004);
			w.device.settle();
		}, e -> if (e.kind == helder.os.EventKind.Close) w.close() else w.handle(e));
	}

	static function hex(px:Bytes, i:Int):String
		return StringTools.hex(px.get(4 * i) << 16 | px.get(4 * i + 1) << 8 | px.get(4 * i + 2), 6).toLowerCase();

	// (the output's pixels as RGBA: weston-screenshooter's PNG, written in dir; weston run with --debug)
	static function capture(dir:String):Null<{width:Int, height:Int, rgba:Bytes}> {
		inline function shots()
			return [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.startsWith(f, "wayland-screenshot")) '$dir/$f'];
		for (f in shots())
			sys.FileSystem.deleteFile(f);
		if (Sys.command("sh", ["-c", 'cd "$dir" && timeout 10 weston-screenshooter > /dev/null 2>&1']) != 0) return null;
		var s = shots();
		if (s.length == 0) return null;
		var png = helder.image.PngDecoder.decode(sys.io.File.getBytes(s[0]));
		sys.FileSystem.deleteFile(s[0]);
		return png;
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
