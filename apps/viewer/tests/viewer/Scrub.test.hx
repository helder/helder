package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Ui;

// The video's scrub bar headless (MediaView's): a press and a drag seek
// to keyframes, the release exactly; its fill at the pointer while held,
// though the player says its keyframe's time, then the player's again
function tests() {
	describe("Scrub", () -> {
		function bar():{scrub:Scrub, ui:Ui, seeks:Array<String>, fill:Void->Float} {
			var seeks = [];
			var s = new Scrub((t, exact) -> seeks.push('$t ${exact ? "exact" : "keyframe"}'));
			s.duration = 10;
			var ui = new Ui(new StoryText(), 200, 14);
			ui.root.append(s.node);
			ui.update();
			return {
				scrub: s,
				ui: ui,
				seeks: seeks,
				fill: () -> {
					ui.update();
					s.node.children[0].children[0].width;
				}
			};
		}
		test("a drag seeks to keyframes, its release exactly there", () -> {
			var b = bar(), s = b.scrub, ui = b.ui;
			ui.pointerDown(50, 7, 1);
			s.show(0);
			ui.pointerMove(100, 7);
			s.show(0);
			equals(b.fill(), 100.0);
			equals(s.time, 5.0);
			ui.pointerUp(150, 7, 1);
			equals(b.seeks, ["2.5 keyframe", "5 keyframe", "7.5 exact"]);
			equals(b.fill(), 150.0);
			// (the player on from there)
			s.show(7.5);
			s.show(8);
			equals(b.fill(), 160.0);
			equals(s.time, 8.0);
		});
		test("a press taken away: exact where it was", () -> {
			var b = bar(), ui = b.ui;
			ui.pointerDown(20, 7, 1);
			ui.pointerMove(40, 7);
			ui.pointerCancel(0);
			equals(b.seeks, ["1 keyframe", "2 keyframe", "2 exact"]);
			b.scrub.show(2.5);
			equals(b.fill(), 50.0);
		});
	});
}
