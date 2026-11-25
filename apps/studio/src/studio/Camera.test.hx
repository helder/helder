package studio;

import helder.test.Test;
import helder.ui.Cursor;

// The watched canvas' hand: open while Space is held, closed while a drag pans it, else the arrow; a fit
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
	});
}
