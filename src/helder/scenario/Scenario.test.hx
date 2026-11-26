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
	var environ = test("a screen's zone, locale and settings its own; none given, none of the machine's", () -> {
		var got = new Map<String, String>();
		function look(name:String)
			return () -> got.set(name, [
				Std.string(helder.os.Now.offset(0) / 60000),
				helder.os.Locale.current.peek(),
				Std.string(helder.os.Settings.textScale.peek()),
				Std.string(helder.os.Settings.reducedMotion.peek()),
				Std.string(helder.os.Settings.orientation.peek())
			].join(" "));
		var h = new Host([], new HeadlessHost(), 1.0, [
			scenario({name: "Delhi", zone: "+05:30", locale: "nl-BE", settings: {textScale: 1.5, reducedMotion: true}, boot: look("Delhi")}),
			scenario({name: "Plain", boot: look("Plain")})
		]);
		h.still(true);
		h.show(["Delhi", "Plain"]);
		h.frame(0);
		equals([got.get("Delhi"), got.get("Plain")], ["330 nl-BE 1.5 true landscape", "0 en-US 1 false landscape"]);
		// (outside the screens: the system's again)
		equals([helder.os.Now.zone == null, helder.os.Locale.screen == null, helder.os.Settings.screen == null], [true, true, true]);
		for (s in h.screens)
			s.reset();
	});
	var random = test("Math.random a screen's own: side by side, drawn in turn, as alone", () -> {
		function draws(names:Array<String>):Map<String, Array<Float>> {
			var out = [for (n in names) n => []];
			var h = new Host([], new HeadlessHost(), 1.0, [for (n in names) scenario({name: n, seed: 7})]);
			h.still(true);
			h.show(names);
			h.frame(0);
			for (_ in 0...3)
				for (s in h.screens)
					s.run(() -> out.get(s.name).push(Math.random()));
			for (s in h.screens)
				s.reset();
			return out;
		}
		var alone = draws(["R"]).get("R"), both = draws(["R", "S"]);
		equals([both.get("R"), both.get("S")], [alone, alone]);
	});
	var timers = test("a timer set in a screen runs on its clock, not the loop's", () -> {
		var fired = [];
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Clock"})]);
		h.still(true);
		h.show(["Clock"]);
		h.frame(0);
		var s = h.screens[0];
		s.run(() -> helder.os.Now.after(1000, () -> fired.push(ScreenContext.current.name)));
		// (real time passing runs nothing: its clock stands)
		turn(0.05);
		equals(fired, []);
		s.run(() -> Clock.tick(ScreenContext.current.now + 1.0));
		equals(fired, ["Clock"]);
		s.reset();
	});
	var http = test("http: its fixtures answer its requests, none goes out; one none matches fails its screen, named", () -> {
		var file = haxe.io.Path.join([Sys.getCwd(), "bin/scenario-test-answer.json"]);
		helder.cli.TestCommand.mkdirs(haxe.io.Path.directory(file));
		sys.io.File.saveContent(file, '{"from": "file"}');
		var got = [];
		function ask(url:String, ?method:String)
			return () -> helder.async.Async.launch(_ -> {
				var r = helder.async.http.Client.request(url, {method: method});
				got.push('${r.status} ${r.text()}');
			});
		var h = new Host([], new HeadlessHost(), 1.0, [
			scenario({
				name: "Served",
				http: {"api.test/v1/*": {a: 1}, "POST api.test/form": 201, "api.test/down": 503, "api.test/file": file},
				boot: () -> {
					ask("https://api.test/v1/items?x=1")();
					ask("https://api.test/form", "POST")();
					ask("http://api.test/down")();
					ask("https://api.test/file")();
				}
			}),
			scenario({name: "Strict", http: {"api.test/*": 200}, boot: ask("https://elsewhere.test/feed")})
		]);
		h.still(true);
		h.show(["Served", "Strict"]);
		h.frame(0);
		turn(0.05);
		h.frame(1);
		equals(got, ['200 {"a":1}', "201 ", "503 ", '200 {"from": "file"}']);
		equals([for (s in h.screens) s.failure?.message], [null, "no http fixture for GET https://elsewhere.test/feed"]);
		for (s in h.screens)
			s.reset();
	});
	var story = test("beside stories", () -> {
		var h = new Host([new Story("S", _ -> View.view(<view/>), 1, null, 50, 50)], new HeadlessHost(), 1.0, [scenario({name: "A"})]);
		equals([for (s in h.screens) s.name], ["S", "A"]);
		equals([for (s in h.screens) s.scenario != null], [false, true]);
	});
	// (as wasm32-wasi the host's device is the browser's, which node has not)
	#if (hxmc.target == "wasm32-wasi")
	for (t in [host, boot, apart, time, tasks, story, environ, random, timers, http])
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
