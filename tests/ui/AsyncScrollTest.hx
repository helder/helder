import helder.gfx.shader.Vec4;
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
// lets them through scrolls once answered. What moves on its own
// (helder.ui.Mover, taken as the compositor takes them: from the nodes
// painted on a layer of their own): transitions of transform and
// opacity, one declared (by the program, by a hover's rule in the update)
// with the program blocked from the next vsync, a spring retargeted
// mid-flight, a tween, sticky headers in a scrolled list; the
// compositor's samples each vsync the program is held against the
// program's own, and its frames (those, overlay scrollbars shown and
// fading) against the program's pixel for pixel.
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
		for (c in motionCases())
			motion(c);
		comesBack();
		#if (target.name == "hxmc")
		if (Sys.args().indexOf("--no-frames") < 0) for (scale in [1, 2]) {
			frames(scale);
			moving(scale);
		}
		#end
		Sys.println('AsyncScrollTest: $checks checks, ' + (failures == 0 ? "ok" : '$failures failed'));
		if (failures > 0) Sys.exit(1);
	}

	// a scroller the compositor left at 600, the program moving it to 120,
	// then back to 600 by steps: the mirror at the program's 600 (#98: it kept 596)
	static function comesBack() {
		var ui = new Ui(new MonoText(), 300, 200), list = new Node(), m = new ScrollMirror(), shot = new ScrollShot();
		list.style.set({width: 300, height: 200, overflow: Scroll});
		for (i in 0...100) {
			var row = new Node();
			row.style.set({height: 20, shrink: 0});
			list.append(row);
		}
		ui.root.append(list);
		function frame() {
			ui.update();
			ScrollShot.take(ui, shot);
			m.adopt(shot);
			m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
		}
		frame();
		ui.mirrored(list, 0, 600, false, false);
		frame();
		list.scrollY = 120;
		frame();
		while (list.scrollY < 600) {
			list.scrollY += 4;
			frame();
		}
		var o = m.offsets(list);
		check("a scroller the compositor left at 600, the program back at 600: the mirror's", o != null && o.y == 600, o == null ? "none" : '${o.y}');
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

	// ---- what moves on its own: the program's transform and opacity at each
	// vsync against the compositor's samples of what it took at its last frame

	static function motionCases():Array<MotionCase> {
		var out:Array<MotionCase> = [];
		out.push({
			name: "transitions of transform and opacity",
			frames: 40,
			holdFrom: 6,
			holdTo: 30,
			build: ui -> [
				box(ui, b -> {
					b.style.transform = Transform.parse("translate(0px, 0px) rotate(0deg) scale(1)");
					b.style.transition = Transition.parse("transform 0.4s ease-out, opacity 0.3s linear");
				})
			],
			act: (k, n) -> if (k == 3) {
				n[0].style.transform = Transform.parse("translate(40px, 12px) rotate(25deg) scale(1.2)");
				n[0].style.opacity = 0.25;
			}
		});
		// (declared, then the program blocked at once: handed over in the
		// declaring frame, set by the program or by a rule's restyle in its update)
		out.push({
			name: "a transition declared and the program blocked",
			frames: 40,
			holdFrom: 4,
			holdTo: 34,
			build: ui -> [
				box(ui, b -> {
					b.style.transform = Transform.parse("translate(0px, 0px)");
					b.style.transition = Transition.parse("transform 0.3s ease-out, opacity 0.25s linear");
				})
			],
			act: (k, n) -> if (k == 3) {
				n[0].style.transform = Transform.parse("translate(60px, 20px)");
				n[0].style.opacity = 0.3;
			}
		});
		out.push({
			name: "a hover's transition declared in the update and the program blocked",
			frames: 40,
			holdFrom: 4,
			holdTo: 34,
			build: ui -> {
				ui.theme = {rules: [
					{slot: "m", style: {transform: Transform.parse("translate(0px, 0px)"), transition: Transition.parse("transform 0.3s ease-out, opacity 0.25s linear")}},
					{slot: "m", when: ["hover"], style: {transform: Transform.parse("translate(60px, 20px)"), opacity: 0.3}}
				]};
				[box(ui, b -> b.slot = "m")];
			},
			act: (k, n) -> if (k == 3) n[0].ui.pointerMove(n[0].absX + 5, n[0].absY + 5)
		});
		out.push({
			name: "a spring retargeted mid-flight",
			frames: 70,
			holdFrom: 12,
			holdTo: 60,
			build: ui -> [box(ui, b -> b.motion = helder.ui.motion.MotionSpec.of({curve: helder.ui.motion.Curve.spring(0.5, 0.3)}))],
			act: (k, n) -> {
				if (k == 2) {
					n[0].style.transform = Transform.translate(80, 0);
					n[0].style.opacity = 0.4;
				}
				if (k == 10) {
					n[0].style.transform = Transform.parse("translate(-30px, 20px) rotate(15deg)");
					n[0].style.opacity = 0.9;
				}
			}
		});
		out.push({
			name: "a tween",
			frames: 40,
			holdFrom: 4,
			holdTo: 32,
			build: ui -> [box(ui, b -> b.motion = helder.ui.motion.MotionSpec.of({curve: helder.ui.motion.Curve.tween(0.35, Transition.EASE_IN_OUT)}))],
			act: (k, n) -> if (k == 2) {
				n[0].style.transform = Transform.scale(1.5, 0.75);
				n[0].style.opacity = 0.1;
			}
		});
		out.push({
			name: "sticky headers in a scrolled list",
			frames: 70,
			holdFrom: 5,
			holdTo: 60,
			build: ui -> {
				var list = new Node();
				list.style.set({width: 300, height: 200, overflow: Scroll, padding: 4});
				var heads = [];
				for (i in 0...6) {
					var sec = new Node(), head = new Node();
					head.style.set({position: Sticky, top: 0, height: 24, shrink: 0});
					sec.append(head);
					for (j in 0...5) {
						var r = new Node();
						r.style.set({height: 30, shrink: 0});
						sec.append(r);
					}
					list.append(sec);
					heads.push(head);
				}
				ui.root.append(list);
				[list].concat(heads);
			},
			act: (k, n) -> {},
			scroll: k -> k * 6.5,
			from: 1
		});
		return out;
	}

	static function box(ui:Ui, f:Node->Void):Node {
		var b = new Node();
		b.style.set({width: 60, height: 40, background: 0xFF3366CC});
		ui.root.append(b);
		f(b);
		return b;
	}

	static function drawn(n:Node) {
		@:privateAccess n.style.drawn = true;
		for (c in n.children)
			drawn(c);
	}

	// (its transform's matrix and its opacity, as the program draws it)
	static function values(n:Node):Array<Float> {
		var m = n.transformMatrix(), p = n.present;
		var o = p == null ? n.style.opacity : n.style.opacity * p.presenceOpacity();
		return m == null ? [1, 0, 0, 1, 0, 0, o] : [m.a, m.b, m.c, m.d, m.e, m.f, o];
	}

	static function motion(c:MotionCase) {
		var sync = motionRun(c, false), held = motionRun(c, true), diverged = -1;
		for (k in 0...sync.length)
			if (!same(sync[k], held[k])) {
				diverged = k;
				break;
			}
		check(c.name + ": the compositor's transforms and opacities at each vsync, the program held for vsyncs " + c.holdFrom + " to " + c.holdTo, diverged < 0,
			diverged < 0 ? null : 'vsync $diverged: ${sync[diverged]} against ${held[diverged]}');
		var first = sync[0], moved = false;
		for (v in sync)
			if (!same(v, first)) moved = true;
		check(c.name + ": it moved", moved);
	}

	static function motionRun(c:MotionCase, hold:Bool):Array<Array<Float>> {
		now = 1;
		Clock.tick(now);
		var ui = new Ui(new MonoText(), 300, 200), nodes = c.build(ui), from = c.from ?? 0;
		ui.update();
		drawn(ui.root);
		var movers:Array<Null<Mover>> = [], out = [], last:Array<Array<Float>> = [];
		for (k in 0...c.frames) {
			now = 1 + k / 60;
			var y = c.scroll == null ? 0.0 : c.scroll(k);
			if (!(hold && k >= c.holdFrom && k < c.holdTo)) {
				c.act(k, nodes);
				if (c.scroll != null) ui.scrollTo(nodes[0], 0, y);
				Clock.tick(now);
				ui.update();
				// (painted: the compositor takes those with a layer of their own, and sticky ones)
				ui.paint(@:privateAccess Ui.nowhere);
				movers = [
					for (i in from...nodes.length)
						@:privateAccess nodes[i].paintLayer != null || nodes[i].style.position == Sticky ? Mover.of(nodes[i], nodes[i].transformMatrix(), values(nodes[i])[6]) : null
				];
				last = [for (i in from...nodes.length) values(nodes[i])];
				out.push([for (v in last) for (x in v) x]);
			} else {
				var m = new helder.canvas.Matrix(), row = [];
				for (i => mv in movers) {
					var o = mv == null ? 0.0 : mv.sample(now, 0, Math.min(y, @:privateAccess Scrolling.maxScroll(nodes[0], false)), m);
					var vs = mv == null ? last[i] : [m.a, m.b, m.c, m.d, m.e, m.f, o];
					for (v in vs)
						row.push(v);
				}
				out.push(row);
			}
		}
		Clock.finish();
		return out;
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

	static function touch(kind:helder.os.EventKind, x:Float, y:Float, frame:Int):OsEvent {
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

	static function mouse(kind:helder.os.EventKind, x:Float, y:Float):OsEvent {
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

	static final pass:helder.gfx.PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

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
		var c = new helder.ui.layers.Compositor(device), mine = haxe.io.Bytes.alloc(w * h * 4), theirs = haxe.io.Bytes.alloc(w * h * 4);
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
	// ---- the compositor's frames of what moves on its own: a layer turning
	// and fading under a transition, sticky headers, overlay scrollbars shown
	// and fading; against the program's own at the same time and offsets

	static function moving(scale:Int) {
		var W = 320, H = 240, device = helder.gfx.Device.create(helder.os.Surface.headless(W * scale, H * scale));
		var w = W * scale, h = H * scale, r = new helder.ui.draw.Renderer(device);
		r.tiles = true;
		r.groups = true;
		r.scale = scale;
		now = 10;
		Clock.tick(now);
		var ui = new Ui(new helder.ui.draw.DrawText(), W, H);
		ui.scale = scale;
		ui.overlayBars = true;
		var list = new Node();
		list.style.set({overflow: Scroll, height: H, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...12) {
			var sec = new Node(), head = new Node();
			head.style.set({position: Sticky, top: 0, height: 22, padding: 3, shrink: 0, background: 0xFFDDE6F0});
			head.append(new TextNode("Section " + i));
			sec.append(head);
			for (j in 0...4) {
				var row = new Node();
				row.style.set({height: 26, padding: 3, shrink: 0, background: j % 2 == 0 ? 0xFFFFFFFF : 0xFFF6F6F6});
				row.append(new TextNode("Row " + j + " of section " + i));
				sec.append(row);
			}
			list.append(sec);
		}
		var spin = new Node();
		spin.style.set({position: Absolute, left: 200, top: 60, width: 70, height: 50, radius: 8, background: 0xFF2A7AE2});
		spin.style.transform = Transform.parse("translate(0px, 0px) rotate(0deg)");
		spin.style.transition = Transition.parse("transform 0.5s ease-in-out, opacity 0.5s linear");
		// (a card whose children overlap: faded whole, as CSS's opacity and the program's group fade it)
		var card = new Node();
		card.style.set({position: Absolute, left: 150, top: 150, width: 130, height: 70, radius: 10, padding: 8, background: 0xFFFFE08A});
		card.style.transition = Transition.parse("opacity 0.6s linear");
		for (i in 0...3) {
			var b = new Node();
			b.style.set({position: Absolute, left: 10 + i * 30, top: 10 + i * 8, width: 50, height: 40, radius: 6, background: [0xFFE2462A, 0xFF2AA84A, 0xFF2A62E2][i]});
			card.append(b);
		}
		card.append(new TextNode("overlapping"));
		ui.root.append(list);
		ui.root.append(spin);
		ui.root.append(card);
		var c = new helder.ui.layers.Compositor(device), mine = haxe.io.Bytes.alloc(w * h * 4), theirs = haxe.io.Bytes.alloc(w * h * 4);
		function frame(composite:Bool, ?pixels:haxe.io.Bytes) {
			Clock.tick(now);
			ui.update();
			// (the reference drawn directly: a moving layer's tiles are resampled where the compositor draws its quads)
			r.tiles = composite;
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
		function compare(what:String, within = 0) {
			var off = 0, most = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
			for (i in 0...w * h)
				if (mine.getInt32(i * 4) != theirs.getInt32(i * 4)) {
					off++;
					for (k in 0...3)
						most = Std.int(Math.max(most, Math.abs(mine.get(i * 4 + k) - theirs.get(i * 4 + k))));
					var x = i % w, y = Std.int(i / w);
					x0 = Std.int(Math.min(x0, x));
					y0 = Std.int(Math.min(y0, y));
					x1 = Std.int(Math.max(x1, x));
					y1 = Std.int(Math.max(y1, y));
				}
			check('frames at scale $scale: $what', most <= within, '$off pixels differ, by $most at most, in $x0,$y0 to $x1,$y1');
			if (off > 0 && Sys.getEnv("ASYNC_SCROLL_PNG") != null) {
				var k = ~/[^a-z0-9]+/g.replace(what, "-");
				sys.io.File.saveBytes('bin/ui/moving-$scale-$k-compositor.png', helder.image.PngEncoder.encode(mine, w, h));
				sys.io.File.saveBytes('bin/ui/moving-$scale-$k-program.png', helder.image.PngEncoder.encode(theirs, w, h));
			}
		}
		function mirror(y:Float)
			@:privateAccess c.mirror.byNode.get(list).scrollY = y;
		// (at rest: the tiles drawn; then the layer's transition begun, its layer made as it moves)
		for (_ in 0...8) {
			now += 1 / 60;
			frame(true);
		}
		spin.style.transform = Transform.parse("translate(-30px, 40px) rotate(35deg)");
		spin.style.opacity = 0.35;
		for (_ in 0...4) {
			now += 1 / 60;
			frame(true);
		}
		// (the transition sampled by the compositor a while after the program's last frame)
		for (d in [0.05, 0.12]) {
			now += d;
			c.drawNow(mine);
			frame(false, theirs);
			// (within a level: the turned corners are rounded to 32-bit floats once more)
			compare('the compositor\'s at ${d} s after the program\'s last, a layer turning and fading: the program\'s then (within a level)', 1);
			now += 1 / 60;
			frame(true);
		}
		// (a fade of the card, the program held: the compositor's frames at
		// vsyncs from its last against the program's then, the card a group)
		now += 1;
		frame(true);
		card.style.opacity = 0.2;
		for (_ in 0...3) {
			now += 1 / 60;
			frame(true);
		}
		var held = now;
		for (k in [4, 12, 24]) {
			now = held + k / 60;
			c.drawNow(mine);
			frame(false, theirs);
			compare('the compositor\'s $k vsyncs after the program\'s last, a card with overlapping children fading whole: the program\'s then (within a level)', 1);
		}
		// (the transition done; sticky headers and overlay bars: scrolled by the mirror)
		now += 1;
		frame(true);
		frame(true);
		for (y in [37.0, 150, 236]) {
			now += 1 / 60;
			mirror(y);
			c.drawNow(mine);
			ui.scrollTo(list, 0, y);
			frame(false, theirs);
			compare('the compositor\'s at $y, sticky headers and the overlay bar shown: the program\'s at $y');
			// (the bar fading: no scroll since)
			now += 0.6;
			c.drawNow(mine);
			frame(false, theirs);
			compare('the compositor\'s at $y 0.6 s later, the overlay bar fading: the program\'s');
			ui.scrollTo(list, 0, 0);
			now += 1;
			frame(true);
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

private typedef MotionCase = {
	name:String,
	frames:Int,
	holdFrom:Int,
	holdTo:Int,
	build:Ui->Array<Node>,
	act:(Int, Array<Node>)->Void,
	?scroll:Int->Float,
	?from:Int
}
