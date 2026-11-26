package helder.story;

import helder.story.Host;
import helder.story.Story;
import helder.test.Test;
import helder.ui.Clock;
import helder.view.View;

// the studio's canvas of stills (Host.still): each screen brought to its
// moment and left there, its clock not run; the hovered one's loop
// (Host.loop) run from its moment, from it again after its loop, a still
// again when let go; a screen out of view drawn once, after those in view
function tests() {
	var stills = test("stills at their moments; the loop runs from it, again, and stops", () -> {
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
	var throws = test("a screen that throws: its failure, the others drawn", () -> {
		var a = new Story("A", _ -> View.view(<view/>), 1, null, 100, 100);
		var b = new Story("B", _ -> throw "boom", 1, null, 100, 100);
		var host = new Host([a, b], new HeadlessHost());
		var told = [];
		host.onFailure = s -> told.push(s.name);
		host.show(["A", "B"]);
		equals(host.frame(0), 1);
		equals(told, ["B"]);
		equals([for (x in host.screens) x.failure?.message], [null, "boom"]);
		equals([for (x in host.screens) x.version], [1, 0]);
		equals(host.frame(1), 0);
		equals(told, ["B"]);
	});
	var outOfView = test("out of view: drawn once, after those in view", () -> {
		var a = new Story("A", _ -> View.view(<view/>), 1, null, 100, 100);
		var b = new Story("B", _ -> View.view(<view/>), 1, null, 100, 100);
		var host = new Host([a, b], new HeadlessHost());
		host.still(true);
		host.show(["A"]);
		equals(host.frame(0), 1);
		equals([for (x in host.screens) x.version], [1, 0]);
		equals(host.busy(), true);
		equals(host.frame(1), 1);
		equals([for (x in host.screens) x.version], [1, 1]);
		equals(host.frame(2), 0);
		equals(host.busy(), false);
	});
	var sharp = test("sharp: those in view drawn at the studio's zoom; out of view, again at the host's", () -> {
		var a = new Story("A", _ -> View.view(<view/>), 1, null, 100, 100);
		var b = new Story("B", _ -> View.view(<view/>), 1, null, 100, 100);
		var sizes = [];
		var host = new Host([a, b], new HeadlessHost((s, _) -> sizes.push(s.name + " " + s.drawnScale)));
		host.still(true);
		host.show(["A", "B"], 2.5);
		host.frame(0);
		host.show(["B"], 2.5);
		host.frame(1);
		host.frame(2);
		equals(sizes, ["A 2.5", "B 2.5", "A 1"]);
	});
	var recorded = test("a loop recorded once a build; a story's randomness seeded: built again, the same still", () -> {
		var s = new Story("Random/loop", _ -> View.view(<view width={10 + Math.random() * 80} height={10} background="#000000"/>), 1, null, 100, 100, 1.0);
		var host = new Host([s], new HeadlessHost());
		host.still(true);
		host.show(["Random/loop"]);
		host.frame(0);
		var a = host.written(host.screens[0], 10);
		// (its loop's recording built it again: built a third time, its still the same)
		host.frame(1);
		var b = host.written(host.screens[0], 10);
		if (a == null || b == null) throw "not written";
		equals({still: b.bytes.toHex() == a.bytes.toHex(), first: a.loop?.frames.length, again: b.loop}, {still: true, first: 10, again: null});
	});
	var parked = test("stills: at most MOUNTED built at once, the settled let go (their stills told), the parked built again after a patch", () -> {
		var stories = [for (i in 0...12) new Story('S/$i', _ -> View.view(<view/>), 1, null, 100, 100)];
		var host = new Host(stories, new HeadlessHost()), told = [], most = 0;
		host.onPark = s -> told.push(s.name);
		host.still(true);
		host.show([for (s in stories) s.name]);
		function run(from:Float)
			for (f in 0...120) {
				host.frame(from + f / 10);
				most = Std.int(Math.max(most, [for (s in host.screens) if (s.ui != null) s].length));
			}
		run(0);
		equals(most, Host.MOUNTED);
		equals([for (s in host.screens) s.version], [for (_ in stories) 1]);
		equals(told.length, stories.length - Host.MOUNTED);
		equals(host.busy(), false);
		// (the parked built again and drawn; the built drew what changed: nothing)
		var was = told.copy();
		host.unpark();
		run(100);
		equals(most, Host.MOUNTED);
		equals([for (s in host.screens) s.version == (was.contains(s.name) ? 2 : 1)], [for (_ in stories) true]);
	});
	// (as wasm32-wasi the host's device is the browser's WebGPU or WebGL2, which node has not)
	#if (hxmc.target == "wasm32-wasi")
	recorded.skip();
	sharp.skip();
	stills.skip();
	outOfView.skip();
	throws.skip();
	parked.skip();
	#end
}
