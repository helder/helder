package helder.scenario;

import helder.scenario.Scenario;
import helder.story.Host;
import helder.story.Story;
import helder.test.Test;
import helder.ui.*;
import helder.ui.UiWindow.Surface;
import helder.view.View;
import helder.view.graph.Graph;

// (the program's atoms: made at its top level)
final score = Graph.signal([0, 0]);
final over = Graph.signal(false);
final total = Graph.memo(() -> score()[0] + score()[1]);
// (what each screen's render read, by its screen)
final seen = new Map<String, Array<Int>>();

// (the loop turned for that long, outside every screen)
function turn(seconds:Float) {
	var done = false;
	helder.async.Async.launch(_ -> {
		helder.async.Async.delay(seconds);
		done = true;
	});
	helder.async.Loop.current().runUntil(() -> done);
}

function win() {
	score([7, 5]);
	over(true);
}

// a scenario is the program's root (what main gave UiWindow.run, once) in
// a screen of the preview host: no window, its <Surface>'s size the
// screen's, its atoms in a store of its own that boot writes first
function tests() {
	Hosting.on = true;
	Game.main();
	Hosting.on = false;
	var host = test("main in host mode: its root kept, no window, its surface's size", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "A"})]);
		equals([h.screens[0].width, h.screens[0].height], [120, 80]);
		h.show(["A"]);
		equals(h.frame(0), 1);
		equals(h.screens[0].failure, null);
		equals(seen.get("A"), [0, 0]);
	});
	var boot = test("boot before the root renders, calling the app's own function", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Won", boot: win})]);
		h.show(["Won"]);
		h.frame(0);
		equals(seen.get("Won"), [7, 5]);
		equals(h.screens[0].run(() -> [over(), total() == 12]), [true, true]);
		equals(score.peek(), [0, 0]);
		equals(over.peek(), false);
	});
	var apart = test("two scenarios of one program apart", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "P", boot: () -> score([1, 0])}), scenario({name: "Q"})]);
		h.show(["P", "Q"]);
		h.frame(0);
		h.screens[0].run(() -> {
			score([3, 3]);
			Graph.flush();
		});
		h.frame(1);
		equals(seen.get("P"), [3, 3]);
		equals(seen.get("Q"), [0, 0]);
		equals(h.screens[1].run(() -> total()), 0);
	});
	var time = test("its time: the wall clock of its screen", () -> {
		var at = -1.0;
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "T", time: "2026-11-26T09:00Z", boot: () -> at = helder.os.Now.get()})]);
		h.show(["T"]);
		h.frame(0);
		equals(at, 1795683600000.0);
		equals(helder.os.Now.get, null);
		equals(Scenario.instant("2026-11-26T09:00+01:00"), 1795680000000.0);
	});
	var tasks = test("a screen let go (reset: a park) drops the tasks its boot started; built again, its own run", () -> {
		var ran = 0;
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Task", boot: () -> helder.async.Async.launch(_ -> {
			helder.async.Async.delay(0.01);
			score([1, 1]);
			ran++;
		})})]);
		h.show(["Task"]);
		h.frame(0);
		h.screens[0].reset();
		turn(0.03);
		equals(ran, 0);
		h.frame(1);
		turn(0.03);
		equals(ran, 1);
		equals(h.screens[0].run(() -> {
			Graph.flush();
			score.peek();
		}), [1, 1]);
		equals(score.peek(), [0, 0]);
	});
	var story = test("beside stories", () -> {
		var h = new Host([new Story("S", _ -> View.view(<view/>), 1, null, 50, 50)], new HeadlessHost(), 1.0, [scenario({name: "A"})]);
		equals([for (s in h.screens) s.name], ["S", "A"]);
		equals([for (s in h.screens) s.scenario != null], [false, true]);
	});
	// (as wasm32-wasi the host's device is the browser's, which node has not)
	#if (hxmc.target == "wasm32-wasi")
	for (t in [host, boot, apart, time, tasks, story])
		t.skip();
	#end
}

class Game implements helder.view.Markup {
	public static function main()
		UiWindow.run(<Surface title="Pong" width={120} height={80}><Court/></Surface>);

	static function Court(_:{}):View {
		Graph.renderEffect(() -> score(), v -> seen.set(ScreenContext.current.name, v));
		return <view/>;
	}
}
