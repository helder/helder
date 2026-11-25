package helder.story;

import helder.story.Host;
import helder.story.Story;
import helder.test.Test;
import helder.ui.Clock;
import helder.view.View;

// the studio's canvas of stills (Host.still): each screen brought to its
// moment and left there, its clock not run; the hovered one's loop
// (Host.loop) run from its moment, from it again after its loop, a still
// again when let go
function tests() {
	test("stills at their moments; the loop runs from it, again, and stops", () -> {
		var ticks = 0;
		var s = new Story("Clock/count", c -> {
			Clock.add(_ -> {
				ticks++;
				true;
			});
			c.play(0.5);
			View.view(<view/>);
		}, 1, null, 100, 100, 1.0);
		var host = new Host([s], new HeadlessHost());
		host.still(true);
		host.show(["Clock/count"]);
		host.frame(0);
		// (its moment: 0.5 s of its clock, 30 frames)
		equals(ticks, 30);
		host.frame(1);
		host.frame(2);
		equals(ticks, 30);
		host.loop("Clock/count");
		host.frame(10);
		equals(ticks, 61);
		host.frame(10.5);
		equals(ticks, 62);
		// (past its loop's second: from its moment again)
		host.frame(11.2);
		equals(ticks, 93);
		host.loop(null);
		host.frame(20);
		host.frame(21);
		equals(ticks, 123);
	});
}
