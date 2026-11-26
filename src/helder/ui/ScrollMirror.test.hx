package helder.ui;

import helder.os.Event as OsEvent;
import helder.os.ScrollPhase;
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
			l.style.set({overflow: Scroll, width: 300, height: 200});
			c.style.set({height: 1000, flexShrink: 0});
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
			t.content.style.height = 100;
			ui.update();
			adopt(ui, m);
			equals(t.list.scrollY, 0.0);
			equals(m.offsets(t.list), null);
			t.content.style.height = 1000;
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
			t.list.style.pointerEvents = None;
			ui.update();
			adopt(ui, m);
			m.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
			equals(@:privateAccess ui.mirrorHeld.exists(t.list), false);
			equals(t.list.scrollY, 0.0);
		});
	});
}
