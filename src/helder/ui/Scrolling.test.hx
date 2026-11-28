package helder.ui;

import helder.test.Test;

function tests() {
	test("a press ends a wheel's latch: the next wheel scrolls what it is over", () -> {
		Ui.now = () -> 0;
		var ui = new Ui(new helder.story.StoryText(), 200, 200);
		function scroller():Node {
			var s = new Node("scroll"), tall = new Node("tall");
			s.style = Style.of({width: 200, height: 100, flexShrink: 0, overflow: Scroll});
			tall.style = Style.of({height: 300, flexShrink: 0});
			s.append(tall);
			ui.root.append(s);
			return s;
		}
		var a = scroller(), b = scroller();
		ui.update();
		ui.wheel(10, 10, 0, 1e5);
		ui.pointerDown(10, 150, 1);
		ui.pointerUp(10, 150, 1);
		ui.wheel(10, 150, 0, 50);
		ui.update();
		equals([a.scrollY, b.scrollY], [200.0, 50.0]);
		Ui.now = haxe.Timer.stamp;
	});
}
