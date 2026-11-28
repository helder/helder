package helder.scenario;

import helder.scenario.Scenario;
import helder.story.Host;
import helder.story.Host.HostScreen;
import helder.view.Flow.*;
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
// (what steps do: taps of Add, the field's draft, the items added, the row picked)
final taps = Graph.signal(0);
final draft = Graph.signal("");
final items = Graph.signal(([] : Array<String>));
final picked = Graph.signal(-1);

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
	var resumed = test("resumed (a reload's, Player's): neither boot nor steps run over the signals the reload kept", () -> {
		var ran = 0;
		var sc = scenario({name: "R", boot: () -> {
			ran++;
			score([2, 2]);
		}});
		var context = new helder.ui.ScreenContext("resumed", true, null, new helder.view.graph.Atoms("resumed"));
		var ui = new Ui(helder.ui.TextEngines.standard(), 120, 80);
		var d = context.run(() -> Act.mount(sc, Hosting.root, context, ui, null, true));
		equals([ran, context.run(() -> total())], [0, 0]);
		context.run(() -> d());
		d = context.run(() -> Act.mount(sc, Hosting.root, context, ui));
		equals([ran, context.run(() -> total())], [1, 4]);
		context.run(() -> d());
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
	// (one scenario of steps built and shown: its screen, after them)
	function stepped(steps:Array<Steps.Step>):HostScreen {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Steps", size: [300, 400], steps: steps})]);
		h.still(true);
		h.show(["Steps"]);
		h.frame(0);
		return h.screens[0];
	}
	var steps = test("steps: tap, type, press, as a user would, after boot and before the still", () -> {
		var s = stepped([Steps.tap("Add"), Steps.type("Item", "Stretch"), Steps.press("Enter")]);
		equals(s.failure?.message, null);
		equals(s.run(() -> [Std.string(taps.peek()), items.peek().join(","), draft.peek()]), ["1", "Stretch", ""]);
		s.reset();
	});
	var rests = test("steps: each waited for until the screen rests, not a minute of its clock", () -> {
		var s = stepped([Steps.tap("Add"), Steps.tap("Add")]);
		equals(s.failure?.message, null);
		// (a second's pause before each, then each at rest at once)
		assert(s.context.now < 2 * @:privateAccess Steps.PAUSE + 1, 'its clock at ${s.context.now} s');
		s.reset();
	});
	var latched = test("steps: two scrollers wheeled in turn, each on its screen's clock (no wheel latched across steps, at any host's speed)", () -> {
		var s = stepped([Steps.scroll("Rows", "end"), Steps.scroll("More", "end")]);
		equals(s.failure?.message, null);
		equals(s.run(() -> [for (v in s.ui.scrollViews()) Math.round(v.offsetY) == Math.round(v.contentHeight - v.height)]), [true, true]);
		s.reset();
	});
	var scrolled = test("steps: a scroll until a row is shown, then a tap on it", () -> {
		var s = stepped([Steps.scroll("Rows", {text: "Row 30"}), Steps.tap({text: "Row 30"})]);
		equals(s.failure?.message, null);
		equals(s.run(() -> picked.peek()), 30);
		s.reset();
	});
	var missing = test("a step that finds nothing fails its screen: its number, the near miss, what is shown", () -> {
		var s = stepped([Steps.tap("Add"), Steps.tap("Ad")]);
		var m = s.failure?.message ?? "";
		equals(m.split("\n")[0], 'step 2: no "Ad" (near: button "Add")');
		assert(m.indexOf('textbox "Item"') > 0, 'the tree in it: $m');
		s.reset();
		var t = stepped([Steps.tap("Twin")]);
		equals((t.failure?.message ?? "").split("\n")[0], 'step 1: "Twin" is 2 nodes: button "Twin", button "Twin" (a role, a label or an id tells them apart)');
		t.reset();
	});
	var sealed = test("a scenario's screen sealed off the machine: its places refused, caught or not, its failure", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Places", boot: () -> try helder.os.Places.user() catch (_:Dynamic) {}})]);
		h.still(true);
		h.show(["Places"]);
		h.frame(0);
		h.frame(1);
		equals((h.screens[0].failure?.message ?? "").split(" refused")[0], "helder.os.Places.user()");
		equals(helder.os.Seal.current, null);
	});
	var story = test("beside stories", () -> {
		var h = new Host([new Story("S", _ -> View.view(<view/>), 1, null, 50, 50)], new HeadlessHost(), 1.0, [scenario({name: "A"})]);
		equals([for (s in h.screens) s.name], ["S", "A"]);
		equals([for (s in h.screens) s.scenario != null], [false, true]);
	});
	// (as wasm32-wasi the host's device is the browser's, which node has not)
	#if (hxmc.target == "wasm32-wasi")
	for (t in [host, boot, apart, resumed, time, tasks, story, environ, random, timers, http, steps, rests, scrolled, missing, sealed, latched])
		t.skip();
	#end
}

class Game implements helder.view.Markup {
	public static function main()
		UiWindow.run(<Surface title="Pong" width={120} height={80}><Court/></Surface>);

	static function Court(_:{}):View {
		Graph.renderEffect(() -> score(), v -> seen.set(ScreenContext.current.name, v));
		function add() {
			if (draft() == "") return;
			items(l -> l.concat([draft()]));
			draft("");
		}
		return <view flexGrow={1} rowGap={4}>
			<button onPress={() -> taps(t -> t + 1)}>Add</button>
			<field value={draft} aria-label="Item" onInput={e -> draft(e.text)} onKeyDown={e -> if (e.key == helder.ui.Key.ENTER) add()}/>
			<button>Twin</button>
			<button>Twin</button>
			<scroll role="list" aria-label="Rows" height={120} flexShrink={0}>
				<For each={[for (i in 0...40) i]}>{i -> <button height={20} flexShrink={0} onPress={() -> picked(i())}>{'Row ${i()}'}</button>}</For>
			</scroll>
			<scroll role="list" aria-label="More" height={60} flexShrink={0}>
				<For each={[for (i in 0...20) i]}>{i -> <view height={20} flexShrink={0}><text>{'More ${i()}'}</text></view>}</For>
			</scroll>
		</view>;
	}
}
