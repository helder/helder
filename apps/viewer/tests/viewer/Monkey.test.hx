package viewer;

import helder.scenario.Monkey;
import helder.scenario.Scenario.scenario;
import helder.test.Test;
import helder.ui.Hosting;
import viewer.Shell.act;

// (the made folder, beside the viewer's own moments: a folder of names and kinds a case draws)
final made = scenario({name: "Monkey/Made folder", size: [1100, 700], dark: true, boot: () -> act(Go(Sandbox.MADE))});
final madePhone = scenario({name: "Monkey/Made folder, phone", size: [390, 844], boot: () -> act(Go(Sandbox.MADE))});

// The viewer under a UI monkey (helder.scenario.Monkey): its scenarios and a
// made folder (huge, right to left, emoji and combining names, many
// entries, broken and cut files, video and audio) in the Sandbox's memory,
// under a HELDER_HOME of its own; the monkey's invariants and media's: at
// most one player playing, the shown file's in the viewer
function tests() {
	#if (hxmc.target != "wasm32-wasi")
	var home = Sys.getEnv("HELDER_HOME") ?? "";
	Sys.putEnv("HELDER_HOME", haxe.io.Path.join([Sys.getCwd(), "bin/monkey-home"]));
	afterAll(() -> Sys.putEnv("HELDER_HOME", home));
	// (no sound device: each player silent, on the monotonic clock)
	@:privateAccess helder.media.Player.quiet = true;
	if (Hosting.root == null) {
		Hosting.on = true;
		Shell.main([]);
		Hosting.on = false;
	}
	test("media's check: a video shown plays alone, the viewer's; closed, none", () -> {
		Hosting.on = true;
		var h = new helder.story.Host([], new helder.story.Host.HeadlessHost(), 1.0, [scenario({name: "Video", size: [1100, 700], boot: () -> {
			Sandbox.made([{name: "clip", kind: Video}, {name: "song", kind: Audio}]);
			act(OpenRecent(Sandbox.MADE + "/clip.mp4"));
		}})]);
		h.still(true);
		h.show(["Video"]);
		h.frame(0);
		var s = h.screens[0];
		function played(f:Void->Void):String
			return s.run(() -> {
				f();
				for (_ in 0...60) @:privateAccess helder.scenario.Steps.frame(s.ui, s.context);
				'${media()} ${[for (p in @:privateAccess helder.media.Player.live) if (p.playing()) p].length}';
			});
		// (where the system decodes no H.264 (no libavcodec), nothing plays: nothing to check)
		var shown = played(() -> {});
		if (s.run(() -> Lambda.exists(@:privateAccess helder.media.Player.live, p -> p.error() != null))) {
			s.reset();
			Hosting.on = false;
			return;
		}
		equals(shown, "null 1");
		equals(played(() -> @:privateAccess helder.scenario.Steps.act(helder.scenario.Steps.press("Escape"), s.ui, s.context, w -> throw w)), "null 0");
		s.reset();
		Hosting.on = false;
	});
	// (first, with no steps: each scenario's files the Sandbox's, in memory, nothing refused)
	test("each case's files the Sandbox's", () -> {
		var f = Monkey.find({from: Monkey.from("viewer.Viewer_scenario", made, madePhone), atoms: [Monkey.atom(Sandbox.made)], steps: 0,
			checks: [{name: "sandbox", check: sandbox}], except: ["window", "settles", "steady"]}, {cases: 60});
		equals(f?.failure, null);
	});
	test("the viewer under a monkey", () -> Monkey.check({
		from: Monkey.from("viewer.Viewer_scenario", made, madePhone),
		atoms: [Monkey.atom(Sandbox.made)],
		checks: [{name: "sandbox", check: sandbox}, {name: "media", check: media}]
	}, {cases: 20, limit: 60}));
	#end
}

#if (hxmc.target != "wasm32-wasi")
// (the explorer's files: the Sandbox's, in memory, never the machine's)
function sandbox():Null<String> {
	var x = Shell.explorer.peek();
	if (x == null) return null;
	return Std.isOfType(x.files, MemoryFiles) ? null : 'the explorer\'s files are ${Type.getClassName(Type.getClass(x.files))}, not the Sandbox\'s';
}

// (what plays: one player at most, the viewer's, its file shown)
function media():Null<String> {
	var playing = [for (p in @:privateAccess helder.media.Player.live) if (p.playing()) p];
	if (playing.length == 0) return null;
	if (playing.length > 1) return '${playing.length} players playing at once';
	var x = Shell.explorer.peek(), v = x?.viewer;
	if (x == null || v == null) return "a player playing with no explorer";
	var node = v.video, path = v.media.peek();
	if (node == null || node.player != playing[0]) return 'a player playing that is not the viewer\'s ($path)';
	if (node.ui == null) return 'the viewer\'s player playing, out of the tree ($path)';
	if (path == "") return "the viewer's player playing, no media shown";
	if (!x.full.value) return 'the viewer\'s player playing, the viewer closed ($path)';
	return null;
}
#end
