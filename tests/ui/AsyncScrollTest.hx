import helder.os.Event as OsEvent;
import helder.os.Pointer;
import helder.os.ScrollPhase;
import helder.ui.*;


// The compositor's scrolling (helder.ui.ScrollMirror) against the program's
// own (the synchronous path): the same scripted input (the wheel's notches,
// eased ones, a trackpad's gesture and momentum past an end, a touch's
// fling, the keys, a thumb dragged, a nested scroller chaining to its page)
// at the same vsyncs, the program held for some of them and catching up
// after; the offsets at each vsync and the program's at the end the same.
// A gated gesture (a slider in the page: it may claim the drag) asks the
// program and is the slider's, a wheel over a node that hears wheels and
// lets them through scrolls once answered.
class AsyncScrollTest {
	static var failures = 0;
	static var checks = 0;
	static var now = 0.0;

	static function check(name:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failures++;
			Sys.println('FAIL $name' + (detail != null ? ': $detail' : ''));
		}
	}

	static function main() {
		Ui.now = () -> now;
		for (s in scripts()) {
			var sync = run(s, false, -1, -1), held = run(s, true, s.holdFrom, s.holdTo), free = run(s, true, -1, -1);
			check(s.name + ": the program's offsets, synchronous and with the compositor", same(sync.end, held.end) && same(sync.end, free.end),
				sync.end + " " + held.end + " " + free.end);
			if (s.gated) {
				check(s.name + ": " + s.expect, s.verify(held), "" + held.end);
				continue;
			}
			var diverged = -1;
			for (k in 0...sync.frames.length)
				if (!same(sync.frames[k], held.frames[k])) {
					diverged = k;
					break;
				}
			check(s.name + ": the compositor's offsets at each vsync, the program held for vsyncs " + s.holdFrom + " to " + s.holdTo, diverged < 0,
				diverged < 0 ? null : 'vsync $diverged: ${sync.frames[diverged]} against ${held.frames[diverged]}');
			check(s.name + ": it scrolled", moved(sync.frames), "" + sync.end);
			if (s.verify != null) check(s.name + ": " + s.expect, s.verify(sync), "" + sync.end);
		}
		#if (target.name == "hxmc")
		if (Sys.args().indexOf("--no-frames") < 0) for (scale in [1, 2]) frames(scale);
		#end
		Sys.println('AsyncScrollTest: $checks checks, ' + (failures == 0 ? "ok" : '$failures failed'));
		if (failures > 0) Sys.exit(1);
	}

	static function same(a:Array<Float>, b:Array<Float>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (Math.abs(a[i] - b[i]) > 1e-9) return false;
		return true;
	}

	static function moved(frames:Array<Array<Float>>):Bool {
		for (f in frames)
			for (v in f)
				if (v != 0) return true;
		return false;
	}

	// ---- the tree: a page with a nested scroller, rows, a slider and a node that hears wheels

	static var slid = 0.0;
	static var wheels = 0;

	static function tree(ui:Ui):Array<Node> {
		var page = new Node("page"), inner = new Node("inner"), slider = new Node("slider"), hears = new Node("hears");
		page.style.set({width: 300, height: 200, overflow: Scroll});
		inner.style.set({height: 100, shrink: 0, overflow: Scroll});
		for (i in 0...10) {
			var r = new Node("i" + i);
			r.style.set({height: 30, shrink: 0});
			inner.append(r);
		}
		slider.style.set({height: 40, shrink: 0});
		slider.onPointerDown = e -> {
			slider.capture();
			slid = e.x;
		};
		slider.onPointerMove = e -> slid = e.x;
		hears.style.set({height: 40, shrink: 0});
		hears.onWheel = e -> wheels++;
		page.append(inner);
		page.append(slider);
		page.append(hears);
		for (i in 0...40) {
			var r = new Node("r" + i);
			r.style.set({height: 30, shrink: 0});
			page.append(r);
		}
		ui.root.append(page);
		return [page, inner];
	}

	// ---- the scripts: events at vsyncs (60 a second)

	static function scripts():Array<Script> {
		var out:Array<Script> = [];
		// (notches over the inner scroller: to its end, then, latched, none; after a rest, the page)
		var s = new Script("wheel", 90, 10, 40);
		for (i in 0...8)
			s.at(2 + i * 2, wheel(150, 50, 0, 40));
		for (i in 0...4)
			s.at(50 + i * 3, wheel(150, 50, 0, 40));
		s.expect = "the inner scroller to its end, then the page (chained)";
		s.verify = r -> r.end[1] == 200 && r.end[0] == 160;
		out.push(s);
		// (macOS's mouse: eased notches, gliding)
		var s = new Script("eased wheel", 80, 3, 30);
		for (i in 0...5) {
			var e = wheel(150, 190, 0, 40);
			e.eased = true;
			s.at(2 + i * 2, e);
		}
		s.expect = "glided to all of it";
		s.verify = r -> r.end[0] == 200;
		out.push(s);
		// (a trackpad: a gesture, its momentum, a fling past the end bouncing back)
		var s = new Script("trackpad", 160, 6, 70);
		s.elastic = true;
		s.at(2, pad(150, 190, 0, ScrollPhase.Began, 0, 2));
		for (i in 0...10)
			s.at(3 + i, pad(150, 190, 25 + i, ScrollPhase.Changed, 0, 3 + i));
		s.at(13, pad(150, 190, 0, ScrollPhase.Ended, 0, 13));
		s.at(14, pad(150, 190, 30, 0, ScrollPhase.Began, 14));
		for (i in 0...40)
			s.at(15 + i, pad(150, 190, 40 - i, 0, ScrollPhase.Changed, 15 + i));
		s.at(56, pad(150, 190, 0, 0, ScrollPhase.Ended, 56));
		// (back up past the start: stretched, springing back)
		s.at(100, pad(150, 190, 0, ScrollPhase.Began, 0, 100));
		for (i in 0...12)
			s.at(101 + i, pad(150, 190, -200, ScrollPhase.Changed, 0, 101 + i));
		s.at(113, pad(150, 190, 0, ScrollPhase.Ended, 0, 113));
		s.expect = "back at the start, sprung back";
		s.verify = r -> r.end[0] == 0;
		out.push(s);
		// (a finger's fling)
		var s = new Script("touch fling", 120, 4, 50);
		s.at(2, touch(PointerDown, 150, 180, 2));
		for (i in 0...8)
			s.at(3 + i, touch(PointerMove, 150, 180 - (i + 1) * 12, 3 + i));
		s.at(11, touch(PointerUp, 150, 180 - 8 * 12, 11));
		s.expect = "glided on past the drag";
		s.verify = r -> r.end[0] > 96;
		out.push(s);
		// (the keys: Page Down, the arrows, End)
		var s = new Script("keys", 90, 5, 30);
		s.at(2, mouse(MouseMove, 150, 150));
		s.at(3, key(helder.ui.Key.PAGE_DOWN));
		s.at(12, key(helder.ui.Key.DOWN));
		s.at(14, key(helder.ui.Key.DOWN));
		s.at(30, key(helder.ui.Key.END));
		s.at(60, key(helder.ui.Key.UP));
		s.expect = "at the end less an arrow's 40";
		s.verify = r -> r.end[0] == 1180 - 40;
		out.push(s);
		// (the page's thumb dragged down, then a click on its track)
		var s = new Script("thumb", 60, 3, 20);
		s.at(2, mouse(MouseDown, 296, 10));
		for (i in 0...10)
			s.at(3 + i, mouse(MouseMove, 296, 10 + (i + 1) * 5));
		s.at(14, mouse(MouseUp, 296, 60));
		s.at(30, mouse(MouseDown, 296, 190));
		s.at(31, mouse(MouseUp, 296, 190));
		s.expect = "the inner one's thumb dragged, then the page's track paged";
		s.verify = r -> r.end[1] > 100 && r.end[0] == 200;
		out.push(s);
		// (gated: a finger on the slider: the slider's drag, no scroll)
		var s = new Script("slider", 40, 3, 20);
		s.gated = true;
		s.at(2, touch(PointerDown, 100, 125, 2));
		for (i in 0...8)
			s.at(3 + i, touch(PointerMove, 100 + (i + 1) * 10, 125 - (i + 1) * 10, 3 + i));
		s.at(11, touch(PointerUp, 180, 45, 11));
		s.expect = "the slider dragged, the page still";
		s.verify = r -> r.end[0] == 0 && slid == 180;
		out.push(s);
		// (gated: a wheel over a node that hears wheels and lets them through: asked, then scrolled)
		var s = new Script("heard wheel", 40, 3, 20);
		s.gated = true;
		for (i in 0...3)
			s.at(2 + i, wheel(150, 160, 0, 40));
		s.expect = "heard and scrolled";
		s.verify = r -> r.end[0] == 120 && wheels > 0;
		out.push(s);
		return out;
	}

	static function wheel(x:Float, y:Float, dx:Float, dy:Float):OsEvent {
		var e = new OsEvent();
		e.kind = Scroll;
		e.x = Std.int(x);
		e.y = Std.int(y);
		e.deltaX = dx;
		e.deltaY = dy;
		return e;
	}

	static function pad(x:Float, y:Float, dy:Float, phase:Int, momentum:Int, frame:Int):OsEvent {
		var e = wheel(x, y, 0, dy);
		e.phase = phase;
		e.momentum = momentum;
		e.time = frame * 1000 / 60 + 1000;
		return e;
	}

	static function touch(kind:helder.os.Event.EventKind, x:Float, y:Float, frame:Int):OsEvent {
		var e = new OsEvent();
		e.kind = kind;
		var p = @:privateAccess new Pointer(1);
		@:privateAccess {
			p.type = Touch;
			p.x = x;
			p.y = y;
			p.time = frame * 1000 / 60 + 1000;
			p.pressure = 1;
		}
		e.pointer = p;
		return e;
	}

	static function mouse(kind:helder.os.Event.EventKind, x:Float, y:Float):OsEvent {
		var e = new OsEvent();
		e.kind = kind;
		e.x = Std.int(x);
		e.y = Std.int(y);
		e.button = 1;
		return e;
	}

	static function key(k:Int):OsEvent {
		var e = new OsEvent();
		e.kind = KeyDown;
		e.key = k;
		return e;
	}

	// ---- a run: the program alone (synchronous), or with the mirror, held from vsync a to b

	static function run(s:Script, mirror:Bool, a:Int, b:Int):{frames:Array<Array<Float>>, end:Array<Float>} {
		now = 1;
		slid = 0;
		wheels = 0;
		var ui = new Ui(new MonoText(), 300, 200);
		ui.elastic = s.elastic;
		var nodes = tree(ui);
		ui.update();
		var m = mirror ? new ScrollMirror() : null, shot = new ScrollShot(), waiting:Array<OsEvent> = [];
		if (m != null) {
			ScrollShot.take(ui, shot);
			m.adopt(shot);
			ui.onAnswer = (g, through) -> m.answer(g, through);
		}
		var frames = [];
		for (k in 0...s.frames) {
			now = 1 + k / 60;
			for (e in s.events[k] ?? []) {
				var c = copy(e);
				if (m != null) UiEvents.route(m, c);
				if (m == null) UiEvents.deliver(ui, c, 1) else waiting.push(c);
			}
			if (m != null) m.step(now);
			var busy = m != null && k >= a && k < b;
			if (!busy) {
				if (m != null) {
					m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
					for (e in waiting)
						UiEvents.deliver(ui, e, 1);
					waiting.resize(0);
				}
				Clock.tick(now);
				ui.update();
						if (m != null) {
					ScrollShot.take(ui, shot);
					m.adopt(shot);
				}
			}
			frames.push(m == null ? [nodes[0].scrollY, nodes[1].scrollY] : [for (n in nodes) m.offsets(n).y]);
		}
		// (caught up: the program's own)
		return {frames: frames, end: [nodes[0].scrollY, nodes[1].scrollY]};
	}

	#if (target.name == "hxmc")
	// ---- the compositor's frames: from the program's last at the mirror's
	// offsets, against the program's own at the same offsets, pixel for pixel

	static final pass:helder.gfx.PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};

	static function frames(scale:Int) {
		var W = 320, H = 240, device = helder.gfx.Device.create(helder.os.Surface.headless(W * scale, H * scale));
		var w = W * scale, h = H * scale, r = new helder.ui.draw.Renderer(device);
		r.tiles = true;
		r.groups = true;
		r.scale = scale;
		var ui = new Ui(new helder.ui.draw.DrawText(), W, H);
		ui.scale = scale;
		var list = new Node(), inner = new Node();
		list.style.set({overflow: Scroll, height: H, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...120) {
			var row = new Node();
			row.style.set({direction: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center, shrink: 0});
			var box = new Node();
			box.style.set({width: 12, height: 12, background: 0xFF000000 | ((i * 40503) & 0xFFFFFF), radius: 3});
			row.append(box);
			row.append(new TextNode("Row " + i + " of the compositor's frames"));
			list.append(row);
		}
		ui.root.append(list);
		var c = new helder.ui.draw.Compositor(device), mine = haxe.io.Bytes.alloc(w * h * 4), theirs = haxe.io.Bytes.alloc(w * h * 4);
		function frame(composite:Bool, ?pixels:haxe.io.Bytes) {
			ui.update();
			var enc = device.beginFrame();
			r.begin(w, h);
			if (composite) c.begin(r);
			ui.paint(r);
			r.prepare(enc);
			enc.beginPass(pass);
			r.end(enc);
			enc.endPass();
			if (pixels != null) device.readPixels(pixels);
			if (composite) c.end(ui, r);
			device.endFrame();
		}
		// (the program's frames at rest: the tiles around the view drawn)
		for (_ in 0...12)
			frame(true);
		var first = list.scrollY;
		for (y in [37.0, 120, 233.5, 240]) {
			// (the compositor's frame at y: the mirror moved there)
			var m = @:privateAccess c.mirror;
			@:privateAccess {
				var n = m.byNode.get(list);
				n.scrollY = y;
			}
			c.drawNow(mine);
			// (the program's own at y, from the same last frame's layers)
			ui.scrollTo(list, 0, y);
			frame(false, theirs);
			var off = 0;
			for (i in 0...w * h)
				if (mine.getInt32(i * 4) != theirs.getInt32(i * 4)) off++;
			var whole = y * scale == Math.fround(y * scale);
			check('frames at scale $scale: the compositor\'s at $y those of the program at $y' + (whole ? "" : " (a fraction of a pixel: within the snap)"),
				whole ? off == 0 : off < w * h / 2, '$off pixels differ');
			if (off > 0 && Sys.getEnv("ASYNC_SCROLL_PNG") != null) {
				sys.io.File.saveBytes('bin/ui/async-$scale-$y-compositor.png', helder.image.PngEncoder.encode(mine, w, h));
				sys.io.File.saveBytes('bin/ui/async-$scale-$y-program.png', helder.image.PngEncoder.encode(theirs, w, h));
			}
			ui.scrollTo(list, 0, first);
			frame(true);
		}
		c.dispose();
		device.dispose();
	}
	#end

	static function copy(e:OsEvent):OsEvent {
		var c = new OsEvent();
		c.kind = e.kind;
		c.x = e.x;
		c.y = e.y;
		c.deltaX = e.deltaX;
		c.deltaY = e.deltaY;
		c.eased = e.eased;
		c.phase = e.phase;
		c.momentum = e.momentum;
		c.time = e.time;
		c.mods = e.mods;
		c.key = e.key;
		c.button = e.button;
		c.pointer = e.pointer;
		return c;
	}
}

private class Script {
	public final name:String;
	public final frames:Int;
	public final holdFrom:Int;
	public final holdTo:Int;
	public final events = new Map<Int, Array<OsEvent>>();
	public var elastic = false;
	public var gated = false;
	public var expect = "";
	public var verify:Null<{frames:Array<Array<Float>>, end:Array<Float>}->Bool> = null;

	public function new(name, frames, holdFrom, holdTo) {
		this.name = name;
		this.frames = frames;
		this.holdFrom = holdFrom;
		this.holdTo = holdTo;
	}

	public function at(frame:Int, e:OsEvent) {
		var l = events.get(frame);
		if (l == null) events.set(frame, l = []);
		l.push(e);
	}
}
