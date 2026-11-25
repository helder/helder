package studio;

import helder.test.Test;
import helder.ui.Cursor;

// The watched canvas' hand: open while Space is held, closed while a drag pans it, else the arrow; a fit; what the framing fits
function tests() {
	describe("Camera", () -> {
		test("the hand", () -> {
			var c = new Camera();
			assert(c.hand() == Default);
			c.held(true);
			helder.view.graph.Graph.flush();
			assert(c.hand() == Grab);
			c.dragging(true);
			helder.view.graph.Graph.flush();
			assert(c.hand() == Grabbing);
			c.dragging(false);
			c.held(false);
			helder.view.graph.Graph.flush();
			assert(c.hand() == Default);
		});
		test("a fit at most 1:1: a small frame centred, not blown up", () -> {
			equals(Camera.fit(0, 0, 100, 100, 400, 400, 0, 0, 0).k, 4.0);
			equals(Camera.fit(0, 0, 100, 100, 400, 400, 0, 0, 0, 0, 0, 1), {x: 150.0, y: 150.0, k: 1.0});
		});
		test("frameBox: every frame; after an answer the program's alone, not the options' sketches", () -> {
			var rs = [{name: "s.helder#Dusk", x: 0.0, y: -900.0, w: 300.0, h: 600.0}, {name: "Pong/Serve", x: 0.0, y: 0.0, w: 480.0, h: 320.0},
				{name: "Pong/Rally", x: 520.0, y: 0.0, w: 480.0, h: 320.0}];
			function design(n:String)
				return n.indexOf("#") > 0;
			equals(Studio.frameBox(rs, design, false), {x: 0.0, y: -900.0, w: 1000.0, h: 1220.0});
			equals(Studio.frameBox(rs, design, true), {x: 0.0, y: 0.0, w: 1000.0, h: 320.0});
			equals(Studio.frameBox([rs[0]], design, true), {x: 0.0, y: -900.0, w: 300.0, h: 600.0});
			equals(Studio.frameBox([], design, true), null);
		});
	});
}
