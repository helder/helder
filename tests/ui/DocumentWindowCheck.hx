import haxe.Timer;
import helder.dom.Dom;
import helder.os.*;
import helder.ui.*;
import helder.ui.box.DocumentNode;

// A long document in a real window (DocumentNode in a scroller, the
// compositor scrolling it), driven where the system's input comes in
// (Window.routed, then the window's handler): the wheel through the
// page, jumps far into it, the table of contents' anchors followed, the
// pointer moved meanwhile. A watchdog thread tells a stall: no frame of
// the loop for STALL s while steps are due; it prints what it saw and
// keeps the process (sample it), then fails. Each step's frame against
// a budget. With --real, the system's own input posted to it (a fast
// wheel, the thumb dragged and held, a live resize, text selected), and
// what the window server shows sampled meanwhile: the document's text
// there, not a blank window (macOS).
//   DocumentWindowCheck <page.html> [sheets.json] [--real] [--front]   (HELDER_BACKGROUND=1)
class DocumentWindowCheck {
	static inline var STALL = 3.0;
	// (a step's frame, ms: a far jump records the page there afresh, a collection may land in it)
	static inline var BUDGET = 400;
	// (frames in a row a drag may show what it brings into view not laid out yet)
	static inline var BLANK = 3;
	static var last = Timer.stamp();
	static var stepName = "start";
	// (once the steps begin: the load's layout is a few seconds of its own)
	static var armed = false;

	static function main() {
		var a = Sys.args();
		var html = sys.io.File.getContent(a[0]);
		var files:haxe.DynamicAccess<String> = a.length > 1 ? haxe.Json.parse(sys.io.File.getContent(a[1])) : {};
		var canonical = ~/<link[^>]*rel="?canonical"?[^>]*href="([^"]+)"/;
		var url = canonical.match(html) ? canonical.matched(1) : "file://" + a[0];
		var w = new helder.ui.UiWindow({title: "DocumentWindowCheck", width: 1024, height: 768});
		var t0 = Timer.stamp();
		var node = DocumentNode.html(Dom.parse(html), {url: url, load: u -> files.exists(u) ? sys.io.File.getContent(files[u]) : null});
		var scroller = new Node("scroll");
		scroller.style.overflow = Scroll;
		scroller.style.flexGrow = 1;
		scroller.style.minHeight = 0;
		scroller.append(node);
		w.root.append(scroller);
		// (anchors in the table of contents, far apart)
		var anchors = [];
		var ids = new Map<String, helder.dom.Element>(), hrefs = [];
		var n:Null<helder.dom.Node> = node.document.documentElement;
		while (n != null) {
			if (n.nodeType == helder.dom.Node.ELEMENT_NODE) {
				var el:helder.dom.Element = cast n, id = el.getAttribute("id");
				if (id != null && !ids.exists(id)) ids.set(id, el);
				var href = el.nodeName == "A" ? el.getAttribute("href") : null;
				if (href != null && StringTools.startsWith(href, "#") && href.length > 1) hrefs.push(href.substr(1));
			}
			n = n.firstChild ?? n.nextSibling ?? up(n);
		}
		for (h in hrefs) if (ids.exists(h)) anchors.push(ids.get(h));
		var stride = Std.int(Math.max(1, anchors.length / 40));
		anchors = [for (i in 0...anchors.length) if (i % stride == 0) anchors[i]];
		sys.thread.Thread.create(() -> {
			while (true) {
				Sys.sleep(0.5);
				var since = Timer.stamp() - last;
				if (armed && since > STALL) {
					Sys.println('DocumentWindowCheck: STALL: no frame for ${Math.round(since * 10) / 10} s at "$stepName"; sample it');
					Sys.sleep(30);
					Sys.exit(2);
				}
			}
		});
		var steps:Array<{name:String, run:Void->Void}> = [];

		// (the window resized a step a frame, narrower and back, as a live resize: a long document lays out
		// what is seen at each width, the rest as it comes near; what was at the top kept there)
		steps.push({name: 'resize start', run: () -> w.ui.scrollTo(scroller, 0, 400000)});
		for (i in 0...24) {
			var width = 1024 - (i < 12 ? i : 24 - i) * 28;
			steps.push({name: 'resize $i to $width', run: () -> w.window.resize(width, 768)});
		}
		steps.push({name: 'resize end', run: () -> w.ui.scrollTo(scroller, 0, 0)});
		for (i in 0...120) steps.push({name: 'wheel $i', run: () -> wheel(w, 600)});
		for (i in 0...40) steps.push({name: 'jump $i', run: () -> w.ui.scrollTo(scroller, 0, (i * 104729) % Std.int(Math.max(1, node.height - 768)))});
		for (i in 0...anchors.length) steps.push({name: 'anchor $i #${anchors[i].id}', run: () -> node.scrollTo(anchors[i])});
		// (the scrollbar's thumb pressed and dragged down the track and back, a move a frame, as a mouse drags it)
		steps.push({name: 'thumb down', run: () -> {
			w.ui.scrollTo(scroller, 0, 0);
			var t = @:privateAccess Scrolling.thumb(scroller, false);
			thumbX = t == null ? 1018 : t[0] + t[2] / 2;
			mouse(w, MouseMove, thumbX, 30);
			mouse(w, MouseDown, thumbX, 30);
		}});
		for (i in 0...150) steps.push({name: 'thumb drag $i', run: () -> mouse(w, MouseMove, thumbX, 30 + (i < 75 ? i : 150 - i) * 9)});
		steps.push({name: 'thumb up', run: () -> mouse(w, MouseUp, thumbX, 30)});
		// (text selected by a drag: short ranges, then one across many paragraphs as the page scrolls under it)
		for (r in 0...4) {
			steps.push({name: 'select $r down', run: () -> {
				w.ui.scrollTo(scroller, 0, (r + 1) * 300000);
				mouse(w, MouseMove, 120, 200);
				mouse(w, MouseDown, 120, 200);
			}});
			for (i in 0...30) steps.push({name: 'select $r drag $i', run: () -> mouse(w, MouseMove, 120 + i * 20, 200 + i * 10 + (r == 3 ? i * 8 : 0))});
			if (r == 3) for (i in 0...60) steps.push({name: 'select long $i', run: () -> {
				mouse(w, MouseMove, 700, 740);
				wheel(w, 300);
			}});
			steps.push({name: 'select $r up', run: () -> mouse(w, MouseUp, 700, 500)});
		}
		for (i in 0...200) steps.push({name: 'hover and wheel $i', run: () -> {
			move(w, 100 + (i * 37) % 800, 100 + (i * 53) % 600);
			wheel(w, i % 40 < 20 ? 900 : -900);
		}});
		// (--real: the drags posted to the application's queue from a thread at a mouse's pace, the
		// loop running as a window's does, its frames timed (HELDER_TEST_INPUT=1: Inject))
		if (a.indexOf("--real") >= 0) return real(w, node, scroller);
		var k = -1, frame = 0, slow:Array<String> = [], worst = 0.0, at = Timer.stamp();
		var layoutAt = 0.0, paintAt = 0.0, gcAt = 0.0, resizes:Array<Float> = [], seen = 0, unlaid:Array<String> = [];
		// (the heap's live bytes as the steps go: it should stay flat over repeated drags)
		var heaps = [];
		Sys.println('DocumentWindowCheck: loaded in ${Math.round((Timer.stamp() - t0) * 1000)} ms, ${anchors.length} anchors, ${steps.length} steps');
		// (after the load's frames, none drawn: laid out to its end all the same, between the loop's turns, as a
		// hidden window is)
		var hidden = -1.0, wholeIn = -1.0;
		App.run(() -> {
			var now = Timer.stamp();
			last = now;
			if (frame == 30 && wholeIn < 0) {
				if (hidden < 0) hidden = now;
				if (node.view.partial && now - hidden < 30) return;
				wholeIn = node.view.partial ? -2 : now - hidden;
				Sys.println('DocumentWindowCheck: ${wholeIn < 0 ? "not laid out whole in 30 s without frames" : "laid out whole without frames in " + Math.round(wholeIn * 1000) + " ms"}');
			}
			frame++;
			// (the load's frames first, then a step each frame)
			if (frame > 30 && k < steps.length) {
				if (k >= 0) {
					var ms = (now - at) * 1000;
					worst = Math.max(worst, ms);
					if (StringTools.startsWith(steps[k].name, "resize ")) resizes.push(ms);
					if (ms > BUDGET) {
						var st = node.stats;
						slow.push('${steps[k].name}: ${Math.round(ms)} ms (layout ${Math.round(st.layoutMs - layoutAt)} ms, paint ${Math.round(st.paintMs - paintAt)} ms, GC ${Math.round((hxmc.GcStats.totalPause() - gcAt) * 1000)} ms)');
					}
				}
				k++;
				if (k % 100 == 0 || k > 0 && k < steps.length && steps[k - 1].name == "thumb up") {
					hxmc.NativeGc.collect(true);
					var heap = Math.round(hxmc.GcStats.liveBytes() / 1048576);
					if (k % 100 == 0) heaps.push(heap) else seen = heap;
				}
				armed = true;
				if (k < steps.length) {
					stepName = steps[k].name;
					layoutAt = node.stats.layoutMs;
					paintAt = node.stats.paintMs;
					gcAt = hxmc.GcStats.totalPause();
					at = Timer.stamp();
					steps[k].run();
				}
			}
			var drew = w.needsFrame() || k < steps.length;
			if (drew) w.frame();
			w.device.settle();
			// (a frame drawn as the window is resized or the thumb dragged: what it shows laid out)
			if (drew && k >= 0 && k < steps.length && (StringTools.startsWith(steps[k].name, "resize ") || StringTools.startsWith(steps[k].name, "thumb"))) {
				var top = scroller.scrollY - (node.absY - scroller.absY);
				if (node.view.unlaid(top, top + scroller.height)) {
					unlaid.push(steps[k].name);
				}
			}
			if (k >= steps.length) {
				// (the live heap after the steps against once the resizes, the jumps and the thumb's drag have been
				// across the document at its widths, the fonts it shows loaded (a long one is laid out where it is
				// seen): the drags, jumps and hovers after it keep nothing)
				var flat = heaps[heaps.length - 1] <= seen * 1.1 + 64;
				Sys.println('DocumentWindowCheck: live heap every 100 steps: ${heaps.join(", ")} MB; $seen MB after the thumb${flat ? "" : " (grew)"}');
				Sys.println('DocumentWindowCheck: ${steps.length} steps, the slowest ${Math.round(worst)} ms; over $BUDGET ms: ${slow.length == 0 ? "none" : slow.join(", ")}');
				resizes.sort(Reflect.compare);
				Sys.println('DocumentWindowCheck: resized ${resizes.length} times, a frame each: median ${Math.round(resizes[resizes.length >> 1])} ms, worst ${Math.round(resizes[resizes.length - 1])} ms');
				// (and the whole document laid out at another width, as a test or print lays it out: what a resize cost before)
				var v = node.view;
				v.upTo(Math.POSITIVE_INFINITY);
				var t1 = Timer.stamp();
				v.layout(900, 768);
				Sys.println('DocumentWindowCheck: the whole document laid out at 900 wide: ${Math.round((Timer.stamp() - t1) * 1000)} ms');
				Sys.println('DocumentWindowCheck: frames drawn resizing or dragging the thumb with what is seen not laid out: ${unlaid.length == 0 ? "none" : unlaid.length + " (" + unlaid.slice(0, 5).join(", ") + ")"}');
				var ok = slow.length == 0 && flat && unlaid.length == 0 && wholeIn >= 0;
				Sys.println('DocumentWindowCheck: ${ok ? "ok" : "FAIL"}');
				w.close();
				Sys.exit(ok ? 0 : 1);
			}
		}, e -> w.handle(e));
	}

	static function up(n:helder.dom.Node):Null<helder.dom.Node> {
		while (n != null && n.nextSibling == null) n = n.parentNode;
		return n == null ? null : n.nextSibling;
	}

	// (the wheel at the window's middle, as the system's scroll comes: routed to the compositor first)
	static function wheel(w:helder.ui.UiWindow, dy:Float) {
		var e = new helder.os.Event(), s = w.window.scale;
		e.kind = Scroll;
		e.window = w.window;
		e.x = Std.int(512 * s);
		e.y = Std.int(384 * s);
		e.deltaY = dy;
		e.time = Timer.stamp() * 1000;
		helder.os.Window.routed(e);
		w.handle(e);
	}

	static var lowest:Array<Float> = [];

	// (the share of dark pixels below its title bar, left of its scrollbar)
	static function inked(px:haxe.io.Bytes, width:Int, height:Int, stride:Int):Float {
		var dark = 0, all = 0, edge = Std.int(width * 0.97), y = Std.int(height * 0.1);
		while (y < height) {
			var x = 0;
			while (x < edge) {
				var i = y * stride + x * 4;
				if (px.get(i) + px.get(i + 1) + px.get(i + 2) < 300) dark++;
				all++;
				x += 2;
			}
			y += 2;
		}
		return dark / Math.max(all, 1);
	}

	static var screens = 0;
	static final blankBy = new Map<String, Int>();
	static var blankScreens = 0;
	static var screenRun = 0;
	static var screenMost = 0;

	static function savePng(path:String, px:haxe.io.Bytes, width:Int, height:Int, stride:Int) {
		var rgba = haxe.io.Bytes.alloc(width * height * 4);
		for (y in 0...height) for (x in 0...width) {
			var i = y * stride + x * 4, o = (y * width + x) * 4;
			rgba.set(o, px.get(i + 2));
			rgba.set(o + 1, px.get(i + 1));
			rgba.set(o + 2, px.get(i));
			rgba.set(o + 3, 255);
		}
		sys.io.File.saveBytes(path, helder.image.PngEncoder.encode(rgba, width, height));
	}

	static var thumbX = 0.0;
	static var scrollTo = -1.0;
	static var resizeTo:Null<Array<Int>> = null;
	static var rssLoaded = 0.0;
	static var rssMost = 0.0;

	// (RSS before a full collection, the live heap after it, RSS after it: MB)
	static function memory(when:String) {
		var before = rss();
		hxmc.NativeGc.collect(true);
		var heap = hxmc.GcStats.liveBytes() / 1048576;
		Sys.println('DocumentWindowCheck --real: memory $when: RSS ${Math.round(before)} MB before a full collection, live heap ${Math.round(heap)} MB after it, RSS ${Math.round(rss())} MB after');
	}

	static function rss():Float {
		var p = new sys.io.Process("ps", ["-o", "rss=", "-p", Std.string(Pid.getpid())]);
		var v = Std.parseFloat(StringTools.trim(p.stdout.readAll().toString()));
		p.close();
		return v / 1024;
	}

	static function real(w:helder.ui.UiWindow, node:DocumentNode, scroller:Node) {
		if (!Inject.supported) {
			Sys.println("DocumentWindowCheck --real: HELDER_TEST_INPUT=1 posts the drags (to this application's queue alone): skipped");
			return;
		}
		var frames:Array<Float> = [], phase = "load", done = false, ready = false, count = 0;
		var whole = false, wholeAt = 0.0, startAt = Timer.stamp();
		// (--front: shown over the other windows, as a window in use presents, not made key: no focus taken)
		var front = Sys.args().indexOf("--front") >= 0;
		helder.os.OsThread.get(() -> {
			var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
			var win = M.id(w.window.surface.handle, O.sel("window"));
			if (front) {
				M.vInt(win, O.sel("setLevel:"), 3);
				M.v(win, O.sel("orderFrontRegardless"));
			}
			true;
		});
		inline function occlusion():Int
			return helder.os.OsThread.get(() -> {
				var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
				M.i(M.id(w.window.surface.handle, O.sel("window")), O.sel("occlusionState")).toInt();
			});
		var heaps = [];
		// (what the window server shows, every 50 ms while dragging or resizing: whether the document's text is there,
		// the compositor's layers composed as they are presented)
		sys.thread.Thread.create(() -> {
			while (!done) {
				Sys.sleep(0.05);
				if (!(StringTools.startsWith(phase, "thumb") || phase == "wheel" || phase == "live resize")) continue;
				var s = Inject.screen(w.window);
				if (s == null) continue;
				screens++;
				// (the least inked, saved to look at)
				var ink = inked(s.px, s.width, s.height, s.stride);
				if (Sys.getEnv("SHOTS") != null && (lowest.length < 3 || ink < lowest[lowest.length - 1])) {
					lowest.push(ink);
					lowest.sort(Reflect.compare);
					if (lowest.length > 3) lowest.pop();
					var k = lowest.indexOf(ink);
					savePng('bin/scratch/least-$k.png', s.px, s.width, s.height, s.stride);
					Sys.println('DocumentWindowCheck --real: a frame inked ${Math.round(ink * 10000) / 100}% at "$phase" saved as least-$k');
				}
				// (a page of text inks a percent or more of it; none, what a scrollbar's thumb inks alone)
				if (ink < 0.001) {
					blankScreens++;
					blankBy.set(phase, (blankBy.get(phase) ?? 0) + 1);
					screenRun++;
					if (screenRun > screenMost) screenMost = screenRun;
				} else
					screenRun = 0;
			}
		});
		sys.thread.Thread.create(() -> {
			// (the document whole first: laid out to its end a slice at a time after its first frame)
			var t0 = Timer.stamp();
			while (!ready || !whole && Timer.stamp() - t0 < 20) Sys.sleep(0.05);
			Sys.println('DocumentWindowCheck --real: the document whole ${whole ? "in " + Math.round((wholeAt - startAt) * 1000) + " ms" : "not in 20 s"}');
			// (shown on the screen first: what the window server shows is sampled)
			Sys.sleep(1);
			Sys.println('DocumentWindowCheck --real: the window ${occlusion() & 2 != 0 ? "visible" : "occluded"} (occlusionState ${occlusion()})');
			rssLoaded = rss();
			// (the wheel, a fast one: WHEEL_S seconds of 12 pixels a millisecond, posted as the system's are, the
			// compositor scrolling ahead of the program)
			phase = "wheel";
			Inject.start(w.window, Std.int(Std.parseFloat(Sys.getEnv("WHEEL_S") ?? "4") * 1000), 0.001).join();
			Sys.sleep(0.3);
			// (the thumb: pressed, dragged down the track and back three times, a move every 8 ms)
			var t = helder.os.OsThread.get(() -> @:privateAccess Scrolling.thumb(scroller, false));
			var tx = t == null ? 1018 : t[0] + t[2] / 2, ty = t == null ? 10 : t[1] + t[3] / 2;
			phase = "thumb drag";
			Inject.mouse(w.window, tx, ty, 5);
			Inject.mouse(w.window, tx, ty, 1);
			// (THUMB_HZ moves a second for THUMB_S seconds, down the track and back, as a fast mouse drags; RSS each second)
			var hz = Std.parseInt(Sys.getEnv("THUMB_HZ") ?? "125"), secs = Std.parseFloat(Sys.getEnv("THUMB_S") ?? "7"), t0 = Timer.stamp(), i = 0, mark = t0;
			while (Timer.stamp() - t0 < secs) {
				var k = i % 300;
				Inject.mouse(w.window, tx, ty + (k < 150 ? k : 300 - k) * 4.5, 6);
				i++;
				Sys.sleep(1 / hz);
				if (Timer.stamp() - mark > 1) {
					mark = Timer.stamp();
					var now = rss();
					rssMost = Math.max(rssMost, now);
					Sys.println('DocumentWindowCheck --real: ${Math.round(mark - t0)} s into the drag: RSS ${Math.round(now)} MB, $i moves posted');
				}
			}
			Inject.mouse(w.window, tx, ty, 2);
			Sys.sleep(0.5);
			// (the thumb pressed, dragged a third down and held there for HELD_S seconds, moved a little at THUMB_HZ, never
			// let go: what it brings into view laid out as it does, not when the button is up)
			phase = "thumb held";
			Inject.mouse(w.window, tx, ty, 5);
			Inject.mouse(w.window, tx, ty, 1);
			for (k in 0...60) {
				Inject.mouse(w.window, tx, ty + k * 4, 6);
				Sys.sleep(1 / hz);
			}
			var held = Std.parseFloat(Sys.getEnv("HELD_S") ?? "5"), h0 = Timer.stamp(), j = 0;
			while (Timer.stamp() - h0 < held) {
				Inject.mouse(w.window, tx, ty + 240 + (j++ % 8) * 3, 6);
				Sys.sleep(1 / hz);
			}
			Inject.mouse(w.window, tx, ty + 240, 2);
			Sys.sleep(0.5);
			// (a live resize for RESIZE_S seconds, narrower and back a step every 8 ms, in the middle of the document: as
			// an edge held, the window resized on the main thread and its frames drawn from AppKit's resize callback,
			// App.run's turn not running between them; what each width shows laid out as it does)
			scrollTo = 600000;
			Sys.sleep(0.3);
			phase = "live resize";
			var sc = w.window.scale, cw = Std.int(w.window.width / sc), ch = Std.int(w.window.height / sc);
			var secs = Std.parseFloat(Sys.getEnv("RESIZE_S") ?? "5"), r0 = Timer.stamp(), m = 0;
			while (Timer.stamp() - r0 < secs) {
				var k = m++ % 120, d = k < 60 ? k : 120 - k;
				resizeTo = [cw - d * 5, ch - d * 2, 1];
				Sys.sleep(0.008);
			}
			resizeTo = [cw, ch, 0];
			Sys.sleep(0.5);
			// (text selected by a drag across the page, three times)
			phase = "select drag";
			for (r in 0...Std.parseInt(Sys.getEnv("SELECTS") ?? "3")) {
				Inject.mouse(w.window, 120, 150, 5);
				Inject.mouse(w.window, 120, 150, 1);
				for (i in 0...300) {
					Inject.mouse(w.window, 120 + (i % 60) * 12, 150 + i * 2, 6);
					Sys.sleep(0.008);
				}
				Inject.mouse(w.window, 700, 750, 2);
				Sys.sleep(0.3);
			}
			phase = "end";
			Sys.sleep(1);
			done = true;
		});
		var blankRun = 0, blankMost = 0, blankFrames = 0, widths = new Map<Int, Bool>();
		var lastFrame = Timer.stamp(), gaps = new Map<String, Array<Float>>(), allocs = new Map<String, Array<Float>>(), was = phase, bytes = hxmc.GcStats.bytesAllocated();
		App.run(() -> {
			var now = Timer.stamp();
			last = now;
			// (what the drags' thread asked of the window: a scroll, a size in a live resize, set on the main thread,
			// as AppKit's loop does: the frames then drawn from its resize callback, this one entered again)
			if (scrollTo >= 0) {
				w.ui.scrollTo(scroller, 0, scrollTo);
				scrollTo = -1;
			}
			var r = resizeTo;
			if (r != null) {
				resizeTo = null;
				helder.os.OsThread.run(() -> {
					w.window.surface.resizing = r[2] == 1;
					w.window.resize(r[0], r[1]);
				});
			}
			// (laid out to its end: told from here, as a layout's own state is read between its passes only)
			if (!whole && count > 0 && !node.view.partial) {
				whole = true;
				wholeAt = Timer.stamp();
			}
			if (count++ > 30) {
				ready = true;
				armed = true;
				stepName = phase;
				var g = gaps.get(phase);
				if (g == null) gaps.set(phase, g = []);
				g.push((now - lastFrame) * 1000);
				var al = allocs.get(phase);
				if (al == null) allocs.set(phase, al = []);
				var b = hxmc.GcStats.bytesAllocated();
				al.push(b - bytes);
				bytes = b;
				// (each phase's end: RSS, a full collection, the live heap, RSS again)
				if (phase != was) {
					memory('after $was');
					was = phase;
					bytes = hxmc.GcStats.bytesAllocated();
				}
				if (count % 200 == 0) heaps.push(Math.round(hxmc.GcStats.liveBytes() / 1048576));
			}
			lastFrame = now;
			var drew = w.needsFrame();
			if (drew) w.frame();
			w.device.settle();
			// (a frame drawn while the thumb is dragged: what it shows laid out, within BLANK frames)
			if (drew && phase == "live resize") widths.set(w.window.width, true);
			if (drew && (StringTools.startsWith(phase, "thumb") || phase == "wheel" || phase == "live resize")) {
				var top = scroller.scrollY - (node.absY - scroller.absY);
				if (node.view.unlaid(top, top + scroller.height)) {
					blankRun++;
					blankFrames++;
					if (blankRun > blankMost) blankMost = blankRun;
				} else
					blankRun = 0;
			}
			if (done) {
				Sys.println('DocumentWindowCheck --real: the node allocated ${Math.round(node.stats.layoutBytes / 1048576)} MB laying out (${node.stats.layouts} times), ${Math.round(node.stats.paintBytes / 1048576)} MB painting (${node.stats.paints} times)');
				for (k => al in allocs) {
					var sum = 0.0;
					for (v in al) sum += v;
					al.sort(Reflect.compare);
					Sys.println('DocumentWindowCheck --real: $k: allocated ${Math.round(sum / 1048576)} MB in ${al.length} turns, median ${Math.round(al[al.length >> 1] / 1024)} KB a turn, most ${Math.round(al[al.length - 1] / 1048576)} MB');
				}
				for (k => g in gaps) {
					g.sort(Reflect.compare);
					Sys.println('DocumentWindowCheck --real: $k: ${g.length} turns, median ${Math.round(g[g.length >> 1] * 10) / 10} ms, worst ${Math.round(g[g.length - 1])} ms');
				}
				Sys.println('DocumentWindowCheck --real: heap ${heaps.join(", ")} MB (live, uncollected)');
				Sys.println('DocumentWindowCheck --real: GC: ${hxmc.GcStats.majorCollections()} major of ${hxmc.GcStats.collections()}, longest pause ${Math.round(hxmc.GcStats.maxPause() * 1000)} ms, ${Math.round(hxmc.GcStats.totalPause() * 1000)} ms all told');
				// (a hang: a turn of more than 1.5 s, a selection's per move once was 3.7)
				var worst = 0.0;
				for (k => g in gaps) worst = Math.max(worst, g[g.length - 1]);
				// (RSS through the drag bounded: garbage collected before it piles up, not seconds late)
				var bounded = rssMost <= rssLoaded * 1.5;
				var sizes = [for (k in widths.keys()) k];
				sizes.sort(Reflect.compare);
				Sys.println('DocumentWindowCheck --real: the live resize drew ${sizes.length} widths, ${sizes.length > 0 ? sizes[0] + " to " + sizes[sizes.length - 1] : "none"}');
				Sys.println('DocumentWindowCheck --real: frames drawn with what is seen not laid out while the thumb is dragged or the window resized: $blankFrames, $blankMost in a row at most');
				Sys.println('DocumentWindowCheck --real: the window as shown, every 50 ms while dragging or resizing: $screens, $blankScreens without text, $screenMost in a row at most');
				if (blankScreens > 0) Sys.println('DocumentWindowCheck --real: without text by phase: $blankBy');
				var ok = worst < 1500 && bounded && blankMost <= BLANK && screenMost <= 1;
				Sys.println('DocumentWindowCheck --real: ${ok ? "ok" : "FAIL"} (worst turn ${Math.round(worst)} ms; RSS ${Math.round(rssLoaded)} MB loaded, ${Math.round(rssMost)} MB the most in the drag${bounded ? "" : ", over 1.5 times"})');
				w.close();
				Sys.exit(ok ? 0 : 1);
			}
		}, e -> w.handle(e));
	}

	static function mouse(w:helder.ui.UiWindow, kind:helder.os.EventKind, x:Float, y:Float) {
		var e = new helder.os.Event(), s = w.window.scale;
		e.kind = kind;
		e.window = w.window;
		e.x = Std.int(x * s);
		e.y = Std.int(y * s);
		e.button = 1;
		helder.os.Window.routed(e);
		w.handle(e);
	}

	static function move(w:helder.ui.UiWindow, x:Float, y:Float) {
		var e = new helder.os.Event(), s = w.window.scale;
		e.kind = MouseMove;
		e.window = w.window;
		e.x = Std.int(x * s);
		e.y = Std.int(y * s);
		helder.os.Window.routed(e);
		w.handle(e);
	}
}

@:hxmc.c @:hxmc.lib("/usr/lib/libSystem.B.dylib") private extern class Pid {
	static function getpid():Int;
}
