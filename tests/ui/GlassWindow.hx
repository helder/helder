import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// The system's Liquid Glass in a real window (macOS 26: NSGlassEffectView,
// helder.ui.Glass; bun run test ui-draw, HELDER_BACKGROUND=1): each glass
// a view in the layer tree, in a host that takes no press, at its node's
// box, its corners its radius; the window captured, the stripes behind it
// blurred (their contrast inside the glass well under theirs outside it).
//   GlassWindow: the checks
//   GlassWindow --capture dir: GlassScene's backgrounds captured into
//   dir/<background>.raw (BGRA, the content's pixels; dir/boxes.txt: the
//   glass's boxes, the scale), as the drawn glass is compared with them
@:hxmc.unsafe(gc)
class GlassWindow {
	static function main() {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var a = Sys.args(), c = a.indexOf("--capture");
		run(c >= 0 ? a[c + 1] : null);
		#else
		Sys.println("GlassWindow: the system's glass is macOS's and iOS's: skipped");
		#end
	}

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	static function run(dir:Null<String>) {
		var w = new helder.ui.UiWindow("GlassWindow", GlassScene.W, GlassScene.H);
		var scenes = dir == null ? ["stripes"] : GlassScene.backgrounds, at = 0, step = 0, failed = 0, glass:Array<Glass> = [];
		inline function check(ok:Bool, what:String) {
			if (!ok) failed++;
			Sys.println('GlassWindow: ${ok ? "ok" : "FAIL"}: $what');
		}
		function show() {
			while (w.root.children.length > 0)
				w.root.remove(w.root.children[0]);
			var r = new Node();
			glass = GlassScene.build(r, scenes[at]);
			w.root.append(r);
			// (a group of two, merging: the system's container, their views in it)
			if (dir == null) {
				var g = new GlassGroup();
				g.spacing = 20;
				g.style.set({position: Absolute, left: 200, top: 110, width: 180, height: 44, direction: Row, columnGap: 8});
				for (_ in 0...2) {
					var c = new Glass();
					c.style.set({width: 44, height: 44});
					g.append(c);
				}
				r.append(g);
			}
		}
		show();
		App.run(() -> {
			step++;
			if (step == 10) {
				var k = w.window.width > 0 ? Scale.of(w) : 1.0;
				if (!@:privateAccess w.ui.layered || @:privateAccess glass[0].systemLayer == null) {
					Sys.println('GlassWindow: no system glass here (${@:privateAccess w.ui.layered ? "macOS before 26" : "the window\'s layers are not the system\'s"}): skipped');
					w.close();
					return;
				}
				var px = capture(w);
				if (dir != null) {
					File.saveBytes('$dir/${scenes[at]}.raw', px.pixels);
					File.saveContent('$dir/boxes.txt', [for (g in glass) GlassScene.box(g, k).join(" ")].concat(['$k ${px.width} ${px.height}']).join("\n"));
				} else {
					// (the views: each glass an NSGlassEffectView in a passive host, at its box)
					var found = views(w), grouped = views(w, true);
					check(grouped.length == 2, 'the group: an NSGlassEffectContainerView in a passive host, ${grouped.length} NSGlassEffectViews in it, of 2');
					check(found.length == glass.length, 'the glass in the layer tree: ${found.length} NSGlassEffectViews in passive hosts, of ${glass.length}');
					for (i => g in glass) {
						var f = i < found.length ? found[i] : [0.0, 0, 0, 0, 0];
						check(f[2] == g.width && f[3] == g.height && f[4] == g.radius(),
							'glass $i: its view ${f[2]} x ${f[3]} points, radius ${f[4]}, against its box ${g.width} x ${g.height}, ${g.radius()}');
					}
					// (the stripes under the capsule: blurred, their contrast far under theirs outside it)
					var b = GlassScene.box(glass[0], k), y = (b[1] + b[3]) >> 1, inner = spread(px, b[0] + Math.round(30 * k), b[2] - Math.round(30 * k), y),
						outer = spread(px, b[0] + Math.round(30 * k), b[2] - Math.round(30 * k), b[3] + Math.round(30 * k));
					// (a capture of nothing but black: the process may not read the screen (macOS 15 on, Screen Recording))
					if (outer == 0) Sys.println("GlassWindow: the window's capture is black (no Screen Recording permission): its pixels not checked")
					else check(inner < outer * 0.5, 'the capsule blurs the stripes: ${Math.round(inner)} levels apart inside, ${Math.round(outer)} outside');
				}
				at++;
				if (at < scenes.length) {
					step = 0;
					show();
				} else {
					Sys.println("GlassWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
					w.close();
					Sys.exit(failed == 0 ? 0 : 1);
					return;
				}
			}
			if (w.needsFrame() || step < 10) w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}

	// (the content's pixels, BGRA, as the display shows them)
	static function capture(w:helder.ui.UiWindow):{width:Int, height:Int, pixels:haxe.io.Bytes} {
		w.device.settle();
		// (the glass's material settles over a few of the window server's frames)
		Sys.sleep(0.6);
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.apple.objc.Msg.i(helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window")), helder.os.apple.objc.ObjC.sel("windowNumber")).toInt());
		var img = SystemLayersWindow.Capture.window(id);
		if (img == null) throw "GlassWindow: no window capture";
		var h = Math.round(w.window.height * Scale.of(w)), row = img.width * 4, top = img.height - h;
		var out = haxe.io.Bytes.alloc(row * h);
		out.blit(0, img.pixels, top * row, row * h);
		return {width: img.width, height: h, pixels: out};
	}

	// (the largest step between neighbours' greens along row y from x0 to x1, smoothed over a few pixels)
	static function spread(px:{width:Int, height:Int, pixels:haxe.io.Bytes}, x0:Int, x1:Int, y:Int):Float {
		var lo = 255.0, hi = 0.0;
		for (x in x0...x1) {
			var v = px.pixels.get(4 * (y * px.width + x) + 1);
			lo = Math.min(lo, v);
			hi = Math.max(hi, v);
		}
		return hi - lo;
	}

	// (the glass views in passive hosts under the window's content view, in order: x, y, w, h, corner radius in points)
	// (grouped: those in a container's content view instead)
	static function views(w:helder.ui.UiWindow, grouped = false):Array<Array<Float>> {
		var view = w.window.surface.handle;
		return OsThread.get(() -> {
			var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC, out = [];
			var glassClass = O.cls("NSGlassEffectView"), passive = O.cls("HxmcPassiveView"), container = O.cls("NSGlassEffectContainerView");
			function walk(v:hxmc.unsafe.Ptr) {
				var subs = M.id(v, O.sel("subviews")), n = M.i(subs, O.sel("count")).toInt();
				for (i in 0...n) {
					var s = M.idInt(subs, O.sel("objectAtIndex:"), i);
					var sv = M.id(v, O.sel("superview"));
					var inGroup = !sv.isNull() && M.bPtr(sv, O.sel("isKindOfClass:"), container);
					if (M.bPtr(s, O.sel("isKindOfClass:"), glassClass) && M.bPtr(v, O.sel("isKindOfClass:"), passive) && !M.b(v, O.sel("isHidden")) && inGroup == grouped) {
						var f = M.rect(s, O.sel("frame"));
						out.push([f.origin.x, f.origin.y, f.size.width, f.size.height, M.f(s, O.sel("cornerRadius"))]);
					}
					walk(s);
				}
			}
			walk(M.id(M.id(view, O.sel("window")), O.sel("contentView")));
			out;
		});
	}
	#end
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
private class Scale {
	// (the window's pixels a point)
	public static function of(w:helder.ui.UiWindow):Float
		return w.device.surface.width / w.window.width;
}
#end
