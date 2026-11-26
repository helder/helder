package helder.scenario;

import helder.ui.*;
import helder.view.RootView;
import helder.view.graph.Atoms;
import helder.view.graph.Graph;

// The studio's Play from here for a scenario: a window of the real app at
// the scenario's moment, run as the preview host runs a scenario's screen
// (helder.story.Host: Act). Its main (`.helder-play.tsx`, helder dev's
// entry) holds the program's root first (hold: Hosting on, its top-level
// effects recorded), imports the scenarios and the app's main (whose
// UiWindow.run keeps the root), then plays one: the window made once, its
// frames and events in one ScreenContext with a store of its own, the
// scenario's boot run there, the root rendered into it. Another one played
// (Scenario.play {name} on the devtools connection: the studio's Play from
// here again) lets the store go as the host resets a screen (its root let
// go, Atoms.clear: the top-level effects made again, its clock's steps and
// timers dropped) and mounts the root after that one's boot: the window,
// its place and size, hot reload kept, nothing built. Across a reload the
// one playing is kept (Hot's snapshot), unless the main names another.
//
//   import "./.helder-play-boot";            // hold()
//   import { dusk, night } from "./app.scenario";
//   import "./main";
//   import { play } from "helder/scenario";
//   play([dusk, night], "Harbour at night/Dusk sweep");
class Player {
	// (main's root held, its top-level effects recorded: before the app's modules run)
	public static function hold() {
		Hosting.on = true;
		Atoms.record = true;
	}

	// the window of one of list, by its name (another of them played later
	// in it); no name: the one the page's ?scenario= names (a share's web
	// build, helder.run's Play from here), else the app from its start
	public static function run(list:Array<Scenario>, ?name:String) {
		var root = Hosting.root;
		if (root == null) throw "helder.scenario.Player: the program's main gave UiWindow.run no root (hold() before its main)";
		name = name ?? asked();
		if (name == null) {
			Hosting.on = false;
			UiWindow.run(root);
			return;
		}
		var p = new Player(list, root);
		var start = name;
		#if hxmc.dev
		// (kept across a reload: the one playing, unless the main names another now)
		var kept:Null<Array<String>> = helder.dev.Hot.load("helder.scenario.playing", helder.dev.Hot.typeOf((_ : Array<String>)));
		if (kept != null && kept[0] == name && p.find(kept[1]) != null) start = kept[1];
		helder.dev.Hot.onSnapshot(() -> helder.dev.Hot.save("helder.scenario.playing", [name, p.playing], helder.dev.Hot.typeOf((_ : Array<String>))));
		helder.dev.Agent.method("Scenario.play", q -> {
			p.play(Std.string(q?.name));
			return {playing: p.playing};
		});
		#end
		p.play(start);
		Hosting.on = false;
		UiWindow.run();
	}

	// (the page's ?scenario=, null: none, or not a page)
	static function asked():Null<String> {
		var at = helder.os.History.location();
		var q = at == null ? -1 : at.indexOf("?");
		if (q < 0) return null;
		for (kv in at.substr(q + 1).split("&")) {
			var eq = kv.indexOf("=");
			if (eq > 0 && kv.substr(0, eq) == "scenario") return StringTools.urlDecode(kv.substr(eq + 1).split("+").join(" "));
		}
		return null;
	}

	public var playing(default, null) = "";

	final list:Array<Scenario>;
	final root:RootView;
	final context:ScreenContext;
	final window:UiWindow;
	var unrender:Null<Void->Void> = null;

	function new(list:Array<Scenario>, root:RootView) {
		this.list = list;
		this.root = root;
		context = new ScreenContext("helder.scenario.play", false, null, new Atoms("helder.scenario.play"));
		// (a page's window its canvas, the page's size, as a <Surface> has it)
		var size = Act.size(root), web = hxmc.Platform.os() == 3;
		window = context.run(() -> new UiWindow({title: size.title ?? "helder", width: size.width ?? (web ? 0 : 800), height: size.height ?? (web ? 0 : 600)}));
		window.screen = context;
	}

	function find(name:Null<String>):Null<Scenario>
		return Lambda.find(list, s -> s.name == name);

	// one of its scenarios played: the last one's store let go, its boot, the root again
	public function play(name:String) {
		var sc = find(name);
		if (sc == null) throw 'no scenario "$name" (${[for (s in list) s.name].join(", ")})';
		var u = unrender;
		unrender = null;
		if (u != null) context.run(() -> u());
		// (what it put in the window's root: a host's screen gets a new Ui, this window keeps its own)
		window.ui.root.removeChildren();
		context.atoms?.clear();
		@:privateAccess context.steps.resize(0);
		@:privateAccess context.timers.resize(0);
		playing = name;
		unrender = context.run(() -> helder.dev.Hot.scope("helder.scenario.play", () -> {
			helder.os.Seed.random(sc.seed);
			var d = Act.mount(sc, root, context, window.ui);
			Graph.flush();
			d;
		}));
		window.ui.requestFrame();
	}
}
