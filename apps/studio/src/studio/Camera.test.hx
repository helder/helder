package studio;

import helder.test.Test;
import helder.ui.Cursor;

// The watched canvas' hand: open while Space is held, closed while a drag pans it, else the arrow
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
	});
}
