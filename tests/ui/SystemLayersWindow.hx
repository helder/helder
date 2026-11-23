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
@:hxmc.unsafe(gc)
class SystemLayersWindow {
	static final checkpoints = ["first", "scrolled", "moving", "busy"];
	static var width = 800;

	static function main() {
		var a = Sys.args(), r = a.indexOf("--run"), t = a.indexOf("--time");
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (r >= 0) return scene(a[r + 1], -1);
		if (t >= 0) return scene(null, Std.parseFloat(a[t + 1]), a.indexOf("anim") >= 0);
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
		if (!sys.FileSystem.exists('$dir/1/first.raw')) {
			Sys.println("SystemLayersWindow: no window capture here: skipped");
			return;
		}
		for (c in checkpoints) {
			var on = File.getBytes('$dir/1/$c.raw'), flat = File.getBytes('$dir/flat/$c.raw'), off = File.getBytes('$dir/0/$c.raw');
			// (the compositor's state split and drawn as layers, all on the window's: the textured compositor's
			// pixels; at a rounded clip's corners, the program's first frames replay where the compositor draws tiles)
			var d = diff(flat, off), n = off.length / 4;
			var ok = flat.length == off.length && d.max <= 5 && d.over1 < 0.001 * n;
			if (!ok) failed++;
			Sys.println('SystemLayersWindow: ${ok ? "ok" : "FAIL"}: $c: the layers drawn onto the window\'s against the textured compositor: ${d.count} pixels differ, ${d.over1} by more than 1 level, at most ${d.max}');
			// (Core Animation's: opaque layers to the level; a translucent layer's pixels (an edge, a fade)
			// blended by the window server in the display's colours, a few levels off UiShader's blending in sRGB)
			var box = [for (v in File.getContent('$dir/1/card.txt').split(" ")) Std.parseInt(v)];
			var e = diff(on, flat, box), f = diff(on, flat, box, true);
			ok = on.length == flat.length && e.max <= 16 && e.over1 < 0.002 * n && f.max <= 16;
			if (!ok) failed++;
			Sys.println('SystemLayersWindow: ${ok ? "ok" : "FAIL"}: $c: Core Animation\'s layers against the same on the window\'s: ${e.count} pixels differ, ${e.over1} by more than 1 level, at most ${e.max}; in the fading card ${f.count}, at most ${f.max}');
		}
		Sys.println("SystemLayersWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
		#else
		Sys.println("SystemLayersWindow: Core Animation is macOS's and iOS's: skipped");
		#end
	}

	// (box: x0, y0, x1, y1 in the capture's pixels, left out, or alone: inside)
	static function diff(x:haxe.io.Bytes, y:haxe.io.Bytes, ?box:Array<Int>, inside = false):{count:Int, over1:Int, max:Int} {
		var count = 0, over1 = 0, max = 0, n = Std.int(Math.min(x.length, y.length) / 4), W = width;
		for (i in 0...n) {
			if (box != null) {
				var px = i % W, py = Std.int(i / W), in_ = px >= box[0] && px < box[2] && py >= box[1] && py < box[3];
				if (in_ != inside) continue;
			}
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
	static function scene(dir:Null<String>, seconds:Float, anim = false) {
		var frame = 0;
		var clock = () -> 1000 + frame / 60;
		if (dir != null) {
			UiWindow.clock = clock;
			Ui.now = clock;
		}
		var w = new UiWindow("SystemLayersWindow", 400, 300);
		w.root.style.set({direction: Row, background: 0xFFF4F4F4});
		var list = new Node();
		list.style.set({overflow: Scroll, width: 240, height: 300, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...200) {
			var row = new Node();
			row.style.set({direction: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center});
			var box = new Node();
			box.style.set({width: 12, height: 12, radius: 3, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF)});
			row.append(box);
			row.append(new TextNode("Row " + i));
			list.append(row);
			if (i == 4) {
				var field = new TextField();
				field.host = Native;
				field.text = "native";
				field.style.set({height: 22, shrink: 0});
				list.append(field);
			}
			if (i == 7) {
				var web = new WebView();
				web.html = "<body style='margin:0;background:#3a8a5a'></body>";
				web.style.set({height: 40, shrink: 0});
				list.append(web);
			}
		}
		var side = new Node();
		side.style.set({grow: 1, padding: 8, rowGap: 8});
		// (a rounded scroller: Core Animation's corners would not be UiShader's, so it stays drawn)
		var round = new Node();
		round.style.set({overflow: Scroll, height: 80, radius: 12, background: 0xFFFFF4E0});
		for (i in 0...20)
			round.append(new TextNode("Item " + i));
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
		var c = w.compositor, step = 0;
		// (the capture's width: the window's)
		width = Std.int(w.window.width);
		if (seconds > 0) return time(w, list, mover, seconds, anim);
		App.run(() -> {
			step++;
			switch step {
				case 12:
					var k = w.window.width / 400;
					File.saveContent('$dir/card.txt', [card.absX, card.absY, card.absX + card.width, card.absY + card.height].map(v -> Std.string(Math.round(v * k)))
						.join(" "));
					capture(w, dir, "first");
				case 14:
					list.scrollY = 150;
					round.scrollY = 30;
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
