import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.platform.WebView;
import helder.ui.widgets.TextField;
import sys.io.File;

// The system's layers in a real window (helder.ui.draw.CaLayers; macOS,
// bun run test ui-draw): one scene run twice on a clock of its own (each
// frame a 60th of a second, so both runs draw the same frames), once
// composited by Core Animation and once by the textured compositor
// (HELDER_SYSTEM_LAYERS=0), the window captured at each checkpoint
// (CGWindowListCreateImage: a process's own windows need no permission)
// and compared: a list scrolled by the program, a rounded scroller (kept
// drawn), a card moving and a card of overlapping children fading on
// their own, a native field and a web view in the list; then, the program
// blocked 300 ms, the compositor's frames: the list at its offset, the
// cards as sampled, the native views moved with them. Both captures pass
// through the same colour matching, so they compare level for level.
//   SystemLayersWindow: both runs, compared
//   SystemLayersWindow --run dir: one run, its captures into dir
//   SystemLayersWindow --time s [anim]: a steady scroll for s seconds (or
//   a layer moving on its own), the process's CPU and GPU time and
//   WindowServer's CPU time (HELDER_SYSTEM_LAYERS=0: the textured compositor's)
//   SystemLayersWindow --time s header: a header's label changed each
//   frame over a list filling the window: those, and the pixels the
//   layers drew a frame (HELDER_DAMAGE=full: each drawn whole)
@:hxmc.unsafe(gc)
class SystemLayersWindow {
	static final checkpoints = ["first", "scrolled", "moving", "busy"];
	static var width = 800;

	static function main() {
		var a = Sys.args(), r = a.indexOf("--run"), t = a.indexOf("--time");
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (r >= 0) return scene(a[r + 1], -1);
		if (a.indexOf("--nan") >= 0) return lost();
		if (t >= 0 && a.indexOf("header") >= 0) return header(Std.parseFloat(a[t + 1]));
		if (t >= 0) return scene(null, Std.parseFloat(a[t + 1]), a.indexOf("anim") >= 0, a.indexOf("round") >= 0);
		var dir = Sys.getEnv("TMPDIR") + "/system-layers-" + Std.random(1 << 30);
		var self = Sys.programPath(), failed = 0;
		for (mode in ["1", "flat", "0"]) {
			sys.FileSystem.createDirectory('$dir/$mode');
			var p = new sys.io.Process("/usr/bin/env", ["HELDER_SYSTEM_LAYERS=" + mode, self, "--run", '$dir/$mode']);
			var out = p.stdout.readAll().toString(), code = p.exitCode();
			p.close();
			Sys.print(out);
			if (code != 0) {
				Sys.println('SystemLayersWindow: FAIL: the run with HELDER_SYSTEM_LAYERS=$mode ended with $code');
				Sys.exit(1);
			}
		}
		// (a layout gone wrong: NaN everywhere, the window's frames on Core Animation's layers all the same)
		var p = new sys.io.Process(self, ["--nan"]), out = p.stdout.readAll().toString(), code = p.exitCode();
		p.close();
		Sys.print(out);
		if (code != 0) {
			Sys.println('SystemLayersWindow: FAIL: a layout of NaN ended with $code');
			failed++;
		}
		if (!sys.FileSystem.exists('$dir/1/first.raw')) {
			Sys.println("SystemLayersWindow: no window capture here: skipped");
			return;
		}
		// (the field and the system layer at offset 0, the list, the rounded scroller, the popup: the capture's pixels)
		var boxes = [for (l in File.getContent('$dir/1/boxes.txt').split("\n")) [for (v in l.split(" ")) Std.parseInt(v)]];
		var field = boxes[0], slot = boxes[1], list = boxes[2], round = boxes[3], popup = boxes[4], web = boxes[5], k = width / 400;
		var card = [for (v in File.getContent('$dir/1/card.txt').split(" ")) Std.parseInt(v)];
		// (the list's offset at each checkpoint, in points: the compositor's while the program is busy)
		var offsets = [0, 150, 150, 90];
		inline function check(ok:Bool, what:String) {
			if (!ok) failed++;
			Sys.println('SystemLayersWindow: ${ok ? "ok" : "FAIL"}: $what');
		}
		for (j => c in checkpoints) {
			var on = File.getBytes('$dir/1/$c.raw'), flat = File.getBytes('$dir/flat/$c.raw'), off = File.getBytes('$dir/0/$c.raw'), n = off.length / 4;
			// (the compositor's state split and drawn as layers, all on the window's: the textured compositor's
			// pixels; at a rounded clip's corners, the program's first frames replay where the compositor draws tiles)
			// (and at "first" a rounded scroller's corners: the textured compositor's first frames are the program's, replayed, not its tiles)
			var m = Math.ceil(14 * k), corner = (r:Array<Int>, x:Int, y:Int) -> inBox(r, x, y) && (x < r[0] + m || x >= r[2] - m) && (y < r[1] + m || y >= r[3] - m);
			var d = diff(flat, off, (x, y) -> j > 0 || !corner(round, x, y) && !corner(list, x, y));
			check(flat.length == off.length && d.max <= 5 && d.over1 < 0.001 * n,
				'$c: the layers drawn onto the window\'s against the textured compositor: ${d.count} pixels differ, ${d.over1} by more than 1 level, at most ${d.max}');
			// (Core Animation's: opaque layers to the level; a translucent layer's pixels (an edge, a fade)
			// blended by the window server in the display's colours, a few levels off UiShader's blending in
			// sRGB. Left out: the field (its focus is AppKit's: hidden on the window's when scrolled out,
			// which resigns it; in the tree it keeps it) and the system layer (the window's has none),
			// but where the popup is over them; the web view (on the window's, a view over all of it)
			var dy = Math.round(offsets[j] * k), at = (b:Array<Int>) -> [b[0], b[1] - dy, b[2], b[3] - dy];
			var f = at(field), sl = at(slot), wv = at(web);
			var e = diff(on, flat, (x, y) -> !inBox(card, x, y) && !inBox(wv, x, y) && (inBox(popup, x, y) || !inBox(f, x, y) && !inBox(sl, x, y)));
			var g = diff(on, flat, (x, y) -> inBox(card, x, y));
			check(on.length == flat.length && e.max <= 16 && e.over1 < 0.002 * n && g.max <= 16,
				'$c: Core Animation\'s layers against the same on the window\'s: ${e.count} pixels differ, ${e.over1} by more than 1 level, at most ${e.max}; in the fading card ${g.count}, at most ${g.max}');
			// (the rounded scrollers' corners: their clip's coverage, the content's pixels exact elsewhere)
			for (r in [round, list]) {
				var inner = diff(on, flat, (x, y) -> inBox(r, x, y) && !corner(r, x, y) && !inBox(popup, x, y) && !inBox(f, x, y) && !inBox(sl, x, y) && !inBox(wv, x, y));
				var corners = diff(on, flat, (x, y) -> corner(r, x, y) && !inBox(sl, x, y) && !inBox(wv, x, y) && !inBox(f, x, y));
				check(inner.max <= 1 && corners.max <= 16, '$c: a rounded scroller ${r == round ? "of its own" : "with native views"}: ${inner.count} pixels differ inside, at most ${inner.max}; at its corners ${corners.count}, at most ${corners.max}');
			}
			// (the system layer: shown in the list as it scrolls, under the popup, cut by the list's rounded corner)
			// (the web view: under the popup, cut by the list's rounded corner)
			if (c == "first") {
				// (its bottom right pixel, outside the list's corner: the window's background)
				var cut = pixel(on, wv[2] - 1, list[3] - 1), bg = pixel(off, list[2] + 4, list[3] - 2);
				check(wv[3] >= list[3] && same(cut, bg), 'first: the web view cut by the list\'s rounded corner ($cut against $bg)');
			}
			if (c == "scrolled") {
				var over = pixel(on, popup[0] + 10, (wv[1] + wv[3]) >> 1), plain = pixel(flat, popup[0] + 10, popup[1] + 10);
				check(wv[1] < popup[3] && same(over, plain), 'scrolled: the popup over the web view ($over against $plain)');
			}
			if (c == "first") {
				var mid = pixel(on, sl[0] + 10, (sl[1] + sl[3]) >> 1), under = pixel(on, popup[0] + 10, (sl[1] + sl[3]) >> 1);
				var popupFlat = pixel(flat, popup[0] + 10, (sl[1] + sl[3]) >> 1);
				check(mid[2] > 180 && mid[0] < 120 && same(under, popupFlat), 'first: the system layer shown ($mid), the popup over it (${under} against $popupFlat)');
			}
			if (c == "busy") {
				var inside = pixel(on, list[0] + Math.round(60 * k), list[1] + Math.round(3 * k));
				var cut = pixel(on, list[0] + Math.round(4 * k) + 1, list[1] + 1), cutFlat = pixel(flat, list[0] + Math.round(4 * k) + 1, list[1] + 1);
				check(sl[1] < list[1] && inside[2] > 180 && inside[0] < 120 && same(cut, cutFlat),
					'busy: the system layer moved with the list ($inside at its top), cut by its rounded corner (${cut} against $cutFlat)');
			}
		}
		Sys.println("SystemLayersWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
		#else
		Sys.println("SystemLayersWindow: Core Animation is macOS's and iOS's: skipped");
		#end
	}

	static inline function inBox(b:Array<Int>, x:Int, y:Int):Bool
		return x >= b[0] && x < b[2] && y >= b[1] && y < b[3];

	// (a pixel's red, green, blue)
	static function pixel(b:haxe.io.Bytes, x:Int, y:Int):Array<Int> {
		var i = 4 * (y * width + x);
		return [b.get(i + 2), b.get(i + 1), b.get(i)];
	}

	static function same(a:Array<Int>, b:Array<Int>):Bool
		return Math.abs(a[0] - b[0]) <= 1 && Math.abs(a[1] - b[1]) <= 1 && Math.abs(a[2] - b[2]) <= 1;

	// (the pixels where counted says so: how many differ, by more than a level, by how much at most)
	static function diff(x:haxe.io.Bytes, y:haxe.io.Bytes, counted:(Int, Int) -> Bool):{count:Int, over1:Int, max:Int} {
		var count = 0, over1 = 0, max = 0, n = Std.int(Math.min(x.length, y.length) / 4), W = width;
		for (i in 0...n) {
			if (!counted(i % W, Std.int(i / W))) continue;
			var m = 0;
			for (k in 0...3)
				m = Std.int(Math.max(m, Math.abs(x.get(4 * i + k) - y.get(4 * i + k))));
			if (m > 0) count++;
			if (m > 1) over1++;
			if (m > max) max = m;
		}
		return {count: count, over1: over1, max: max};
	}

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	// (dir: the captures' (null: timing for seconds))
	static function scene(dir:Null<String>, seconds:Float, anim = false, rounded = true) {
		var frame = 0;
		var clock = () -> 1000 + frame / 60;
		if (dir != null) {
			UiWindow.clock = clock;
			Ui.now = clock;
		}
		var w = new UiWindow("SystemLayersWindow", 400, 300);
		w.root.style.set({direction: Row, background: 0xFFF4F4F4});
		var list = new Node();
		list.style.set({overflow: Scroll, width: 240, height: 300, rowGap: 2, padding: 4, background: 0xFFFFFFFF, radius: rounded ? 10 : 0});
		var field:Null<TextField> = null, slotted:Null<Node> = null, web:Null<WebView> = null;
		for (i in 0...200) {
			var row = new Node();
			row.style.set({direction: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 12, height: 12, radius: 3, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
			if (i == 2) {
				// (a system layer of its own: a CALayer of one colour, the Video series' kind)
				slotted = new Node();
				slotted.style.set({height: 30, shrink: 0});
				@:privateAccess slotted.systemLayer = new LayerSlot(solidLayer(0.2, 0.75, 0.9));
				list.append(slotted);
			}
			if (i == 4) {
				field = new TextField();
				field.host = Native;
				field.text = "native";
				field.style.set({height: 22, shrink: 0});
				list.append(field);
			}
			if (i == 7) {
				web = new WebView();
				web.html = "<body style='margin:0;background:#3a8a5a'></body>";
				web.style.set({height: 40, shrink: 0});
				list.append(web);
			}
		}
		var side = new Node();
		side.style.set({grow: 1, padding: 8, rowGap: 8});
		// (a rounded scroller, its content opaque to its corners: masked by its clip's coverage)
		var round = new Node();
		round.style.set({overflow: Scroll, height: 80, radius: 12, background: 0xFFFFF4E0});
		for (i in 0...20) {
			var item = new Node();
			item.style.set({background: i % 2 == 0 ? 0xFFFFD8A0 : 0xFF90C8F0, padding: 2});
			item.append(new TextNode("Item " + i));
			round.append(item);
		}
		var mover = new Node();
		mover.style.set({width: 60, height: 40, radius: 8, background: 0xFF2A7AE2});
		mover.style.transform = Transform.parse("translate(0px, 0px)");
		mover.style.transition = Transition.parse("transform 1s linear");
		var card = new Node();
		card.style.set({height: 70, padding: 6, background: 0xFFE24A2A, radius: 6});
		card.style.transition = Transition.parse("opacity 1s linear");
		for (k in 0...3) {
			var c = new Node();
			c.style.set({position: Absolute, left: 10 + k * 22, top: 10 + k * 8, width: 40, height: 40, radius: 20, background: [0xFF20C060, 0xFF2060E0, 0xFFF0C020][k]});
			card.append(c);
		}
		side.append(round);
		side.append(mover);
		side.append(card);
		w.root.append(list);
		w.root.append(side);
		// (a popup over the list: over the field and the system layer, drawn over them)
		var popup = new Node();
		popup.style.set({position: Absolute, left: 150, top: 60, width: 80, height: 90, background: 0xFF6A3AB0, radius: 6});
		if (dir != null) w.ui.overlay.append(popup);
		var c = w.compositor, step = 0;
		// (the capture's width: the window's)
		width = Std.int(w.window.width);
		if (seconds > 0) return time(w, list, mover, seconds, anim);
		App.run(() -> {
			step++;
			switch step {
				case 12:
					var k = w.window.width / 400;
					inline function box(n:Node, dy = 0.0)
						return [n.absX, n.absY + dy, n.absX + n.width, n.absY + n.height + dy].map(v -> Std.string(Math.round(v * k))).join(" ");
					File.saveContent('$dir/card.txt', box(card));
					// (the field and the system layer in the list's content at offset 0; the list's box, the rounded scroller's, the popup's)
					File.saveContent('$dir/boxes.txt', [box(field, list.scrollY), box(slotted, list.scrollY), box(list), box(round), box(popup), box(web, list.scrollY)].join("\n"));
					capture(w, dir, "first");
				case 14:
					list.scrollY = 150;
					round.scrollY = 30;
					w.ui.requestFrame();
				case 18:
					capture(w, dir, "scrolled");
				case 20:
					mover.style.transform = Transform.parse("translate(60px, 0px)");
					card.style.opacity = 0.4;
				case 34:
					capture(w, dir, "moving");
				case 38 if (c != null):
					// (the program busy: the compositor's frames, the clock held where it is)
					c.nativeScrolled(list, 0, 90);
					Sys.sleep(0.05);
					capture(w, dir, "busy");
					Sys.sleep(0.1);
				case 38:
					capture(w, dir, "busy");
				case 44:
					var l = c == null ? null : c.layers;
					Sys.println('SystemLayersWindow: ${l == null ? "textured" : "system layers"}: tiles ${Math.round(@:privateAccess w.renderer.tileBytes / 1e5) / 10} MB'
						+ (l == null ? "" : ', layers\' drawables ${Math.round(l.bytes() / 1e5) / 10} MB'));
					w.close();
					return;
				case _:
			}
			// (the web view's page loaded before the frames that count)
			if (step == 7 && !loaded(w)) step = 6;
			if (w.needsFrame() || step < 44) {
				w.frame();
				frame++;
			}
			w.device.settle();
		}, e -> w.handle(e));
	}

	static function loaded(w:UiWindow):Bool {
		var found = true;
		function walk(n:Node) {
			if (Std.isOfType(n, WebView)) {
				var v:WebView = cast n;
				if (v.loading || v.progress < 1) found = false;
			}
			for (k in n.children)
				walk(k);
		}
		walk(w.root);
		Sys.sleep(0.05);
		return found;
	}

	// (a padding of NaN, as a markup value read wrong once gave (Little
	// Skies, PR #86): a popup laid out at NaN over a list on a layer of its
	// own, a scroller, a native field and a system layer in it; frames
	// drawn for a second, Core Animation handed none of its NaN)
	static function lost() {
		var w = new UiWindow("SystemLayersWindow NaN", 300, 200);
		w.root.style.set({background: 0xFFF4F4F4});
		var fine = new Node();
		fine.style.set({overflow: Scroll, height: 150, background: 0xFFFFFFFF});
		for (i in 0...30)
			fine.append(new TextNode("Fine " + i));
		w.root.append(fine);
		var popup = new Node();
		popup.style.set({position: Absolute, left: 20, top: 20, width: 200, height: 120, padding: Math.NaN, background: 0xFF6A3AB0});
		// (fading: a layer that moves on its own, its quads NaN)
		popup.style.transition = Transition.parse("opacity 2s linear");
		w.ui.overlay.append(popup);
		var list = new Node();
		list.style.set({overflow: Scroll, height: 100, radius: 8, background: 0xFFFFFFFF});
		for (i in 0...30)
			list.append(new TextNode("Lost " + i));
		var field = new TextField();
		field.host = Native;
		field.text = "lost";
		list.append(field);
		var slotted = new Node();
		slotted.style.set({height: 20});
		@:privateAccess slotted.systemLayer = new LayerSlot(solidLayer(1, 0, 0));
		list.append(slotted);
		var mover = new Node();
		mover.style.set({width: 40, height: 20, background: 0xFF2A7AE2});
		mover.style.transition = Transition.parse("transform 2s linear");
		popup.append(list);
		popup.append(mover);
		var t0 = haxe.Timer.stamp(), step = 0;
		App.run(() -> {
			step++;
			if (step == 3) {
				mover.style.transform = Transform.parse("translate(100px, 0px)");
				popup.style.opacity = 0.5;
			}
			if (step > 3) {
				list.scrollY = step * 3;
				fine.scrollY = step * 2;
			}
			if (haxe.Timer.stamp() - t0 > 1) {
				var l = w.compositor == null ? null : w.compositor.layers;
				Sys.println('SystemLayersWindow: ok: a layout of NaN: ${l == null ? 0 : l.frames} frames on the system\'s layers, no exception');
				w.close();
				return;
			}
			w.ui.requestFrame();
			w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}

	// (s seconds of a steady scroll, or of a layer moving on its own (anim):
	// the process's CPU time, its GPU time, WindowServer's CPU time)
	static function time(w:UiWindow, list:Node, mover:Node, s:Float, anim:Bool) {
		var t0 = 0.0, cpu0 = 0.0, gpu0 = 0.0, ws0 = 0.0, frames = 0, step = 0;
		var mb = () -> {
			var v = 0.0;
			w.device.inOrder(r -> v = (cast r.impl : helder.gfx.metal.MetalBackend).gpuSeconds);
			w.device.settle();
			v;
		};
		App.run(() -> {
			step++;
			if (step == 30) {
				if (anim) {
					mover.style.transition = Transition.parse('transform ${s + 2}s linear');
					mover.style.transform = Transform.parse("translate(140px, 300px) rotate(90deg)");
				}
				t0 = haxe.Timer.stamp();
				cpu0 = Cpu.seconds();
				gpu0 = mb();
				ws0 = windowServer();
			}
			if (step > 30 && !anim) list.scrollY = (list.scrollY + 2) % 3000;
			if (step > 30) frames++;
			if (step > 30 && haxe.Timer.stamp() - t0 > s) {
				var wall = haxe.Timer.stamp() - t0, cpu = Cpu.seconds() - cpu0, gpu = mb() - gpu0, ws = windowServer() - ws0;
				inline function pc(v:Float)
					return Math.round(v / wall * 1000) / 10;
				var l = w.compositor != null && w.compositor.layers != null;
				Sys.println('SystemLayersWindow: ${anim ? "a layer moving" : "a steady scroll"}, ${l ? "system layers" : "textured"}: $frames frames in ${Math.round(wall * 100) / 100} s; CPU ${pc(cpu)}% of a core, GPU ${pc(gpu)}% (${Math.round(gpu / frames * 1e5) / 100} ms a frame), WindowServer CPU ${pc(ws)}%');
				w.close();
				return;
			}
			w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}

	// (a header's label changed each frame over a list filling the window)
	static function header(s:Float) {
		var w = new UiWindow("SystemLayersWindow", 400, 600);
		var root = w.root;
		root.style.set({direction: Column, background: 0xFFFFFFFF});
		var head = new Node(), title = new TextNode("Header");
		head.style.set({height: 56, shrink: 0, padding: 14, background: 0xFF18181B});
		title.style.set({color: 0xFFFFFFFF, fontSize: 18});
		head.append(title);
		root.append(head);
		var list = new Node();
		list.style.set({grow: 1, minHeight: 0, overflow: Scroll, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...300) {
			var row = new Node();
			row.style.set({direction: Row, padding: 6, columnGap: 8, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 16, height: 16, radius: 4, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		root.append(list);
		var t0 = 0.0, cpu0 = 0.0, gpu0 = 0.0, frames = 0, step = 0, px0 = 0.0, cut0 = 0;
		var mb = () -> {
			var v = 0.0;
			w.device.inOrder(r -> v = (cast r.impl : helder.gfx.metal.MetalBackend).gpuSeconds);
			w.device.settle();
			v;
		};
		var ca = () -> w.compositor == null ? null : Std.downcast(w.compositor.layers, helder.ui.draw.CaLayers);
		App.run(() -> {
			step++;
			if (step == 30) {
				t0 = haxe.Timer.stamp();
				cpu0 = Cpu.seconds();
				gpu0 = mb();
				var c = ca();
				if (c != null) {
					px0 = c.pixelsTotal;
					cut0 = c.cutTotal;
				}
			}
			if (step > 30) {
				title.text = "Header " + step;
				frames++;
			}
			if (step > 30 && haxe.Timer.stamp() - t0 > s) {
				var wall = haxe.Timer.stamp() - t0, cpu = Cpu.seconds() - cpu0, gpu = mb() - gpu0, c = ca();
				var drawn = c == null ? "" : ', ${c.cutTotal - cut0} layers drawn in part, ${Math.round((c.pixelsTotal - px0) / frames)} pixels a frame of ${w.device.width * w.device.height}';
				Sys.println('SystemLayersWindow: a header changed, ${c != null ? "system layers" : "textured"}${Sys.getEnv("HELDER_DAMAGE") == "full" ? " drawn whole" : ""}: $frames frames in ${Math.round(wall * 100) / 100} s; CPU ${Math.round(cpu / wall * 1000) / 10}% of a core, GPU ${Math.round(gpu / frames * 1e5) / 100} ms a frame$drawn');
				w.close();
				return;
			}
			w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}

	// (WindowServer's CPU time so far, seconds: ps; other apps' compositing counts too)
	static function windowServer():Float {
		var p = new sys.io.Process("/bin/sh", ["-c", "ps -A -o time=,comm= | grep WindowServer | head -1"]);
		var t = StringTools.trim(p.stdout.readAll().toString()).split(" ")[0];
		p.close();
		var parts = t.split(":").map(Std.parseFloat), v = 0.0;
		for (x in parts)
			v = v * 60 + x;
		return v;
	}

	// (a CALayer of one colour, sRGB)
	static function solidLayer(r:Float, g:Float, b:Float):hxmc.unsafe.Ptr {
		var l = OsThread.get(() -> {
			var l = helder.os.objc.Runtime.objc_retain(helder.os.objc.Msg.id(helder.os.objc.ObjC.cls("CALayer"), helder.os.objc.ObjC.sel("layer")));
			var c = CG.CGColorCreateSRGB(r, g, b, 1);
			helder.os.objc.Msg.vPtr(l, helder.os.objc.ObjC.sel("setBackgroundColor:"), c);
			CG.CGColorRelease(c);
			l;
		});
		return l;
	}

	// (the window's content, its pixels as the display shows them, into dir/name.raw)
	static function capture(w:UiWindow, dir:String, name:String) {
		w.device.settle();
		// (what was committed on the screen: the window server shows it a frame or two later)
		Sys.sleep(0.15);
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.objc.Msg.i(helder.os.objc.Msg.id(view, helder.os.objc.ObjC.sel("window")), helder.os.objc.ObjC.sel("windowNumber")).toInt());
		var img = Capture.window(id);
		if (img == null) return;
		// (the content only: the title bar shows what is behind it)
		var h = Std.int(w.window.height), row = img.width * 4, top = img.height - h;
		var out = haxe.io.Bytes.alloc(row * h);
		out.blit(0, img.pixels, top * row, row * h);
		File.saveBytes('$dir/$name.raw', out);
	}
	#end
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
// (CoreGraphics' window capture, its pixels BGRA)
@:hxmc.unsafe(gc)
class Capture {
	public static function window(id:Int):Null<{width:Int, height:Int, pixels:haxe.io.Bytes}> {
		var img = hxmc.unsafe.Arena.scopedValue(a -> {
			var r = a.make(helder.os.objc.CGRect);
			// (CGRectNull: the window's own bounds)
			r.value.origin.x = Math.POSITIVE_INFINITY;
			r.value.origin.y = Math.POSITIVE_INFINITY;
			r.value.size.width = 0;
			r.value.size.height = 0;
			// (kCGWindowListOptionIncludingWindow; boundsIgnoreFraming | bestResolution)
			CG.CGWindowListCreateImage(r.value, 1 << 3, id, 1 | 8);
		});
		if (img.isNull()) return null;
		var w = CG.CGImageGetWidth(img).toInt(), h = CG.CGImageGetHeight(img).toInt(), row = CG.CGImageGetBytesPerRow(img).toInt();
		var data = CG.CGDataProviderCopyData(CG.CGImageGetDataProvider(img));
		var src:hxmc.unsafe.Ptr<hxmc.unsafe.UInt8> = CF.CFDataGetBytePtr(data);
		var out = haxe.io.Bytes.alloc(w * h * 4);
		for (y in 0...h)
			for (x in 0...w * 4)
				out.set(y * w * 4 + x, src[y * row + x]);
		CF.CFRelease(data);
		CG.CGImageRelease(img);
		return w == 0 ? null : {width: w, height: h, pixels: out};
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFDataGetBytePtr(d:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function CFRelease(o:hxmc.unsafe.Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CG {
	static function CGWindowListCreateImage(r:helder.os.objc.CGRect, list:hxmc.unsafe.UInt32, id:hxmc.unsafe.UInt32, image:hxmc.unsafe.UInt32):hxmc.unsafe.Ptr;
	static function CGImageGetWidth(i:hxmc.unsafe.Ptr):hxmc.unsafe.Int64;
	static function CGImageGetHeight(i:hxmc.unsafe.Ptr):hxmc.unsafe.Int64;
	static function CGImageGetBytesPerRow(i:hxmc.unsafe.Ptr):hxmc.unsafe.Int64;
	static function CGImageGetDataProvider(i:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function CGDataProviderCopyData(p:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function CGImageRelease(i:hxmc.unsafe.Ptr):Void;
	static function CGColorCreateSRGB(r:Float, g:Float, b:Float, a:Float):hxmc.unsafe.Ptr;
	static function CGColorRelease(c:hxmc.unsafe.Ptr):Void;
}

// (the process's CPU time, user and system: getrusage)
@:hxmc.unsafe(gc)
class Cpu {
	public static function seconds():Float {
		var r:hxmc.unsafe.Ptr<hxmc.unsafe.Int64> = hxmc.unsafe.LibC.malloc(144);
		Rusage.getrusage(0, cast r);
		var s = r[0].toInt() + (r[1].toInt() & 0xFFFFFFF) / 1e6 + r[2].toInt() + (r[3].toInt() & 0xFFFFFFF) / 1e6;
		hxmc.unsafe.LibC.free(cast r);
		return s;
	}
}

@:hxmc.c extern class Rusage {
	static function getrusage(who:Int, r:hxmc.unsafe.Ptr):Int;
}
#end
