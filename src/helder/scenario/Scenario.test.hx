package helder.scenario;

import helder.scenario.Scenario;
import helder.story.Host;
import helder.story.Story;
import helder.test.Test;
import helder.ui.*;
import helder.view.Named;
import helder.view.View;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// a scenario is the program's main run in a screen of the preview host:
// no window, its <Surface>'s size the screen's, its named signals set by
// name as they are made, each screen's apart
function tests() {
	// (what each screen's main made, by its screen)
	var made = new Map<String, Signal<Array<Int>>>();
	var runs = 0;
	function main() {
		runs++;
		var score = Named.add(Graph.signal([0, 0]), "Game.score");
		Named.add(Graph.signal({x: 1.0, y: 2.0}), "Game.ball");
		made.set(ScreenContext.current.name, score);
		UiWindow.run(UiWindow.Surface({title: "Pong", width: 120, height: 80, children: View.view(<view/>)}));
	}
	var host = test("main in host mode: no window, its surface's size", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "A"})], main);
		equals([h.screens[0].width, h.screens[0].height], [120, 80]);
		h.show(["A"]);
		equals(h.frame(0), 1);
		equals(h.screens[0].failure, null);
		equals(made.get("A")?.peek(), [0, 0]);
	});
	var set = test("set by name, as it is made", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Won", set: {"Game.score": [7, 5]}})], main);
		h.show(["Won"]);
		h.frame(0);
		equals(made.get("Won")?.peek(), [7, 5]);
		equals(h.screens[0].context.names.names(), ["Game.ball", "Game.score"]);
	});
	var apart = test("two scenarios of one program apart", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "P", set: {"Game.score": [1, 0]}}), scenario({name: "Q"})], main);
		h.show(["P", "Q"]);
		h.frame(0);
		var p = made.get("P");
		if (p != null) p([3, 3]);
		Graph.flush();
		equals(made.get("P")?.peek(), [3, 3]);
		equals(made.get("Q")?.peek(), [0, 0]);
		equals(h.screens[1].context.names.get("Game.score")?.peek(), [0, 0]);
	});
	var unknown = test("a name no signal took, a value of another shape: the screen fails, saying so", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [
			scenario({name: "Typo", set: {"Game.scor": [1, 1]}}),
			scenario({name: "Shape", set: {"Game.ball": {x: 1, z: 2}}})
		], main);
		h.show(["Typo", "Shape"]);
		h.frame(0);
		equals(h.screens[0].failure?.message, 'scenario "Typo": no signal named "Game.scor" (did you mean "Game.score"?) (named: Game.ball, Game.score)');
		equals(h.screens[1].failure?.message, 'Game.ball: no field "z"');
	});
	var time = test("its time: the wall clock of its screen", () -> {
		var at = 0.0;
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "T", time: "2026-11-26T09:00Z"})], () -> {
			at = helder.os.Now.get == null ? -1 : helder.os.Now.get();
			UiWindow.run(UiWindow.Surface({width: 10, height: 10, children: View.view(<view/>)}));
		});
		h.show(["T"]);
		h.frame(0);
		equals(at, 1795683600000.0);
		equals(helder.os.Now.get, null);
		equals(Scenario.instant("2026-11-26T09:00+01:00"), 1795680000000.0);
	});
	var story = test("beside stories", () -> {
		var h = new Host([new Story("S", _ -> View.view(<view/>), 1, null, 50, 50)], new HeadlessHost(), 1.0, [scenario({name: "A"})], main);
		equals([for (s in h.screens) s.name], ["S", "A"]);
		equals([for (s in h.screens) s.scenario != null], [false, true]);
	});
	// (as wasm32-wasi the host's device is the browser's, which node has not)
	#if (hxmc.target == "wasm32-wasi")
	for (t in [host, set, apart, unknown, time, story])
		t.skip();
	#end
}
