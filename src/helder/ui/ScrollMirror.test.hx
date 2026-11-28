package helder.ui;

import helder.os.Event as OsEvent;
import helder.os.ScrollPhase;
import helder.test.Gen;
import helder.test.Test;

// The compositor's mirror of the scrollers, as one stops being its: its
// range gone (a folder that fits after one that scrolled; still a gate,
// for its wheel), it has no offsets of the mirror's, so that the
// compositor's frames draw it where the program does, and a scroller
// again it takes the program's; let go while a trackpad held it past its
// end, the program is told and puts it back within its range
function tests() {
	describe("ScrollMirror", () -> {
		var now = 1.0;
		function list(ui:Ui):{list:Node, content:Node} {
			var l = new Node("list"), c = new Node();
			l.style = Style.of({overflow: Scroll, width: 300, height: 200});
			c.style = Style.of({height: 1000, flexShrink: 0});
			// (a wheel of its own: a gate where it has no range)
			l.onWheel = _ -> {};
			l.append(c);
			ui.root.append(l);
			ui.update();
			return {list: l, content: c};
		}
		function adopt(ui:Ui, m:ScrollMirror) {
			var shot = new ScrollShot();
			ScrollShot.take(ui, shot);
			m.adopt(shot);
		}
		test("its range gone: none of the mirror's offsets; a scroller again: the program's", () -> {
			Ui.now = () -> now;
			var ui = new Ui(null, 300, 200), m = new ScrollMirror(), t = list(ui);
			ui.scrollTo(t.list, 0, 300);
			ui.update();
			adopt(ui, m);
			equals(m.offsets(t.list).y, 300.0);
			// (another folder, which fits)
			t.content.style = t.content.style.with({height: 100});
			ui.update();
			adopt(ui, m);
			equals(t.list.scrollY, 0.0);
			equals(m.offsets(t.list), null);
			t.content.style = t.content.style.with({height: 1000});
			ui.update();
			ui.scrollTo(t.list, 0, 50);
			ui.update();
			adopt(ui, m);
			equals(m.offsets(t.list).y, 50.0);
		});
		test("let go held past its end: the program told, back within its range", () -> {
			Ui.now = () -> now;
			var ui = new Ui(null, 300, 200), m = new ScrollMirror(), t = list(ui);
			ui.elastic = true;
			// (no wheel of its own: the compositor's gesture from its start)
			t.list.onWheel = null;
			ui.update();
			adopt(ui, m);
			function pad(dy:Float, phase:Int) {
				var e = new OsEvent();
				e.kind = Scroll;
				e.x = 150;
				e.y = 100;
				e.deltaY = dy;
				e.phase = phase;
				e.time = now * 1000;
				UiEvents.route(m, e);
				now += 1 / 60;
				m.step(now);
				m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
			}
			// (up past the start, the fingers still down)
			pad(0, ScrollPhase.Began);
			for (_ in 0...6)
				pad(-60, ScrollPhase.Changed);
			assert(t.list.scrollY < 0, 'stretched: ${t.list.scrollY}');
			equals(@:privateAccess ui.mirrorHeld.exists(t.list), true);
			// (no longer the compositor's: under a node that takes no input)
			t.list.style = t.list.style.with({pointerEvents: None});
			ui.update();
			adopt(ui, m);
			m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
			equals(@:privateAccess ui.mirrorHeld.exists(t.list), false);
			equals(t.list.scrollY, 0.0);
		});
	});
	// The compositor's mirror of the scrollers (ScrollMirror) against the
	// program's frames in any order (a stateful property, headless): a wheel's
	// notches the mirror takes while the program is busy, the program's turns
	// (the mirror's offsets drained, the events, its frame taken), frames
	// taken before a drain (a frame at the end of a turn that blocked: the
	// system's layers falling back meanwhile ask for one, as in
	// WinLayersWindowCheck's stall run, whose list the program had at 80 of
	// the compositor's 640), the program's own scrolls. After each step the
	// mirror is where the program last put the list and the notches since
	// took it, and after a turn the program is there too.
	describe("ScrollMirror against the program's frames", () -> {
		test("the mirror's offsets against the program's frames, in any order", () -> stateful({
			setup: () -> new Fixture(),
			steps: [
				{name: "wheel", run: (f, c) -> f.wheel(c.draw(int(1, 4)))},
				{name: "turn", run: (f, _) -> f.turn()},
				{name: "frame before a drain", run: (f, _) -> f.frame()},
				{name: "the program's scroll", run: (f, c) -> f.scroll(c.draw(int(0, 40)) * 20)}
			],
			check: f -> f.check()
		}, {cases: 150, steps: 30}));
		test("a frame taken before a drain: the compositor's offset kept", () -> {
			var f = new Fixture();
			f.wheel(3);
			f.frame();
			f.check();
			f.turn();
			f.check();
		});
	});
}

private class Fixture {
	static inline var ROWS = 200;
	static inline var ROW = 20;
	static inline var H = 200;

	final ui:Ui;
	final list = new Node("list");
	final m = new ScrollMirror();
	final shot = new ScrollShot();
	final waiting:Array<OsEvent> = [];
	// (where the program last put the list, moved by the notches since: the mirror's offset)
	var expected = 0.0;
	var turned = true;

	public function new() {
		Ui.now = () -> 0;
		ui = new Ui(new helder.story.StoryText(), 300, H);
		list.style = Style.of({width: 300, height: H, overflow: Scroll});
		for (_ in 0...ROWS) {
			var r = new Node();
			r.style = Style.of({height: ROW, flexShrink: 0});
			list.append(r);
		}
		ui.root.append(list);
		take();
	}

	// (the program's frame: laid out, its scrollers to the mirror)
	function take() {
		ui.update();
		ScrollShot.take(ui, shot);
		m.adopt(shot);
	}

	// (a turn's start: the mirror's offsets to the program, the events read meanwhile)
	function drain() {
		m.step(Ui.now());
		m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
		for (e in waiting)
			UiEvents.deliver(ui, e, 1);
		waiting.resize(0);
	}

	// n of a wheel's notches over the list, 40 points down each, routed to the mirror as read
	public function wheel(n:Int) {
		for (_ in 0...n) {
			var e = new OsEvent();
			e.kind = Scroll;
			e.x = 150;
			e.y = 100;
			e.deltaY = 40;
			UiEvents.route(m, e);
			// (the compositor's frame at the next vsync: the mirror stepped)
			m.step(Ui.now());
			waiting.push(e);
			expected = Math.min(ROWS * ROW - H, expected + 40);
		}
		turned = false;
	}

	public function turn() {
		drain();
		take();
		turned = true;
	}

	public function frame() {
		take();
		turned = false;
	}

	// a turn whose program puts the list at y
	public function scroll(y:Float) {
		drain();
		list.scrollY = y;
		take();
		expected = y;
		turned = true;
	}

	public function check() {
		var o = m.offsets(list);
		equals(o == null ? -1.0 : o.y, expected, "the mirror's offset");
		if (turned) equals(list.scrollY, expected, "the program's, after its turn");
	}
}
