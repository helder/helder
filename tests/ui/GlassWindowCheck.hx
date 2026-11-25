import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// The system's Liquid Glass in a real window (macOS 26: NSGlassEffectView,
// helder.ui.Glass; bun run test ui-draw, HELDER_BACKGROUND=1): each glass
// a view in the layer tree, in a host that takes no press, at its node's
// box, its corners its radius; the window captured, the stripes behind it
// blurred (their contrast inside the glass well under theirs outside it).
//   GlassWindowCheck: the checks
//   GlassWindowCheck --capture dir: GlassScene's backgrounds captured into
//   dir/<background>.raw (BGRA, the content's pixels; dir/boxes.txt: the
//   glass's boxes, the scale), as the drawn glass is compared with them
@:hxmc.unsafe(gc)
class GlassWindowCheck {
	static function main() {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var a = Sys.args(), c = a.indexOf("--capture");
		run(c >= 0 ? a[c + 1] : null);
		#else
		Sys.println("GlassWindowCheck: the system's glass is macOS's and iOS's: skipped");
		#end
	}

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	static function run(dir:Null<String>) {
		var w = new helder.ui.UiWindow("GlassWindowCheck", GlassScene.W, GlassScene.H);
		var scenes = dir == null ? ["stripes"] : GlassScene.backgrounds, at = 0, step = 0, failed = 0, glass:Array<Glass> = [];
		inline function check(ok:Bool, what:String) {
			if (!ok) failed++;
			Sys.println('GlassWindowCheck: ${ok ? "ok" : "FAIL"}: $what');
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
		var input:Null<Input> = null;
		App.run(() -> {
			step++;
			if (input != null) {
				var ok = input.step(step);
				if (ok != null) {
					if (!ok) failed++;
					Sys.println("GlassWindowCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
					w.close();
					Sys.exit(failed == 0 ? 0 : 1);
					return;
				}
			} else if (step == 10) {
				var k = w.window.width > 0 ? Scale.of(w) : 1.0;
				if (!@:privateAccess w.ui.layered || @:privateAccess glass[0].systemLayer == null) {
					Sys.println('GlassWindowCheck: no system glass here (${@:privateAccess w.ui.layered ? "macOS before 26" : "the window\'s layers are not the system\'s"}): its views skipped, the input under drawn glass');
					step = 0;
					input = new Input(w);
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
					if (outer == 0) Sys.println("GlassWindowCheck: the window's capture is black (no Screen Recording permission): its pixels not checked")
					else check(inner < outer * 0.5, 'the capsule blurs the stripes: ${Math.round(inner)} levels apart inside, ${Math.round(outer)} outside');
				}
				at++;
				if (at < scenes.length) {
					step = 0;
					show();
				} else if (dir == null) {
					step = 0;
					input = new Input(w);
				} else {
					Sys.println("GlassWindowCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
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
		var img = SystemLayersWindowCheck.Capture.window(id);
		if (img == null) throw "GlassWindowCheck: no window capture";
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
// (input in a window with glass, the system's or drawn (the window's
// layers not the system's), sent to this process alone by Inject.at, CI's
// or HELDER_TEST_INPUT=1's: a list of rows under a glass button and a
// group of two scrolled where no glass is; a scroll over the button, a
// press on it and one on the group's second glass: each reaching helder's
// view under the passive hosts)
@:hxmc.unsafe(gc)
private class Input {
	final w:helder.ui.UiWindow;
	final list = new Node();
	final button = new Glass();
	final grouped = new Glass();
	var presses = 0;
	var wheels = 0;
	var before = 0;
	var listBefore = 0.0;
	// (the phase, when it began; when the first scroll was seen in the list)
	var phase = 0;
	var at = 0.0;
	var seen = 0.0;

	public function new(w:helder.ui.UiWindow) {
		this.w = w;
		while (w.root.children.length > 0)
			w.root.remove(w.root.children[0]);
		var r = new Node();
		r.style.set({width: GlassScene.W, height: GlassScene.H, background: 0xFFFFFFFF});
		r.onWheel = _ -> wheels++;
		list.style.set({overflow: Scroll, height: GlassScene.H, rowGap: 4, padding: 4});
		for (i in 0...60) {
			var row = new Node();
			row.style.set({height: 30, shrink: 0, background: i % 2 == 0 ? 0xFF2F7FE8 : 0xFFE8463A});
			list.append(row);
		}
		r.append(list);
		button.interactive = true;
		button.style.set({position: Absolute, left: 40, top: 40, width: 120, height: 50});
		button.onClick = _ -> presses++;
		r.append(button);
		var g = new GlassGroup();
		g.spacing = 12;
		g.style.set({position: Absolute, left: 240, top: 40, direction: Row, columnGap: 6});
		var first = new Glass();
		first.style.set({width: 50, height: 50});
		grouped.interactive = true;
		grouped.style.set({width: 50, height: 50});
		grouped.onClick = _ -> presses += 10;
		g.append(first);
		g.append(grouped);
		r.append(g);
		w.root.append(r);
	}

	var passed = true;

	function check(ok:Bool, what:String):Bool {
		Sys.println('GlassWindowCheck: ${ok ? "ok" : "FAIL"}: $what');
		if (!ok) passed = false;
		return ok;
	}

	// (n's middle, in points)
	function middle(n:Node):Array<Float> {
		var k = w.window.width / w.device.surface.width;
		return [(n.absX + n.width / 2) * k, (n.absY + n.height / 2) * k];
	}

	// (the view AppKit's hit test finds at x, y points of the content: "" if
	// neither a glass view nor a passive host nor in one, else its class)
	function hit(x:Float, y:Float):String {
		var view = w.window.surface.handle;
		return OsThread.get(() -> {
			var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
			var content = M.id(M.id(view, O.sel("window")), O.sel("contentView"));
			var p:hxmc.unsafe.Ptr<helder.os.apple.objc.CGPoint> = hxmc.unsafe.LibC.malloc(16);
			p.value.x = x;
			p.value.y = M.rect(content, O.sel("frame")).size.height - y;
			var v = M.idPoint(M.id(content, O.sel("superview")), O.sel("hitTest:"), p.value), found = "";
			hxmc.unsafe.LibC.free(p);
			while (!v.isNull() && found == "") {
				for (c in [O.cls("NSGlassEffectView"), O.cls("NSGlassEffectContainerView"), O.cls("HxmcPassiveView")])
					if (!c.isNull() && M.bPtr(v, O.sel("isKindOfClass:"), c)) found = helder.os.apple.objc.ObjC.string(M.id(v, O.sel("className")));
				v = M.id(v, O.sel("superview"));
			}
			found;
		});
	}

	// (how long an input may take to reach helder: the main thread reads the
	// application's queue, then the program's turn; seconds)
	static inline var WAIT = 3.0;

	// at step n: whether all passed, once done, else null. Each input's
	// outcome waited for, WAIT at most: not a count of the loop's turns,
	// which take well under a millisecond while nothing is drawn (a press
	// or a wheel at the root changes nothing on screen), so that one posted
	// was not read yet when the check came (CI: "0 wheel events at the root")
	public function step(n:Int):Null<Bool> {
		if (n < 10) return null;
		var now = haxe.Timer.stamp();
		switch phase {
			case 0:
				if (!Inject.at(w.window, 200, 200, false, 6)) {
					Sys.println("GlassWindowCheck: input not sent (CI's, or HELDER_TEST_INPUT=1): skipped");
					return true;
				}
				next(now);
			case 1 if (list.scrollY > 0 || now - at > WAIT):
				if (!check(list.scrollY > 0, 'a scroll where no glass is reaches the list under it: scrolled ${list.scrollY} (${ms(now - at)} ms)')) return false;
				seen = now;
				next(now);
			// (past the wheel's latch to the list (ScrollHost.WHEEL_LATCH, the
			// mirror's too: 0.5 s from the last notch, which came before it was
			// seen scrolled): else the next scroll is the list's)
			case 2 if (now - seen > @:privateAccess helder.ui.ScrollHost.WHEEL_LATCH + 0.3):
				before = wheels;
				listBefore = list.scrollY;
				var m = middle(button);
				Inject.at(w.window, m[0], m[1], false, 6);
				next(now);
			case 3 if (wheels > before || now - at > WAIT):
				// (the list's offset: whether a lost scroll went to the list (its latch) or nowhere)
				if (!check(wheels > before, 'a scroll over the glass button reaches helder: ${wheels - before} wheel events at the root (${ms(now - at)} ms), the list at ${list.scrollY} (${listBefore} before it)')) return false;
				before = presses;
				var m = middle(button);
				Inject.at(w.window, m[0], m[1], true);
				next(now);
			case 4 if (presses > before || now - at > WAIT):
				for (g in [button, grouped]) {
					var m = middle(g), hit = hit(m[0], m[1]);
					check(hit == "", 'AppKit\'s hit test at a glass: ${hit == "" ? "no glass view, no host" : hit}');
				}
				var m = middle(grouped);
				Inject.at(w.window, m[0], m[1], true);
				next(now);
			// (and a moment on: a press that reached both would be seen)
			case 5 if ((presses >= 11 && now - at > 0.2) || now - at > WAIT):
				check(presses == 11, 'a press on the glass button and one on a group\'s glass reach helder: $presses (of 11: 1 and 10)');
				return passed;
			case _:
		}
		return null;
	}

	function next(now:Float) {
		phase++;
		at = now;
	}

	static function ms(s:Float):Int
		return Math.round(s * 1000);
}

private class Scale {
	// (the window's pixels a point)
	public static function of(w:helder.ui.UiWindow):Float
		return w.device.surface.width / w.window.width;
}
#end
