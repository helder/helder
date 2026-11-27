package viewer;

import helder.scenario.Scenario.scenario;
import helder.story.Host;
import helder.test.Test;
import helder.ui.Hosting;
import viewer.Shell.act;
import viewer.Shell.with;

// The viewer in a preview host (the studio's scenarios): main run once,
// each screen its own explorer of the Sandbox, booted through its actions
function tests() {
	// (as wasm32-wasi the host's device is the browser's, which node has not)
	#if (hxmc.target != "wasm32-wasi")
	Hosting.on = true;
	Shell.main([]);
	Hosting.on = false;
	// (its screens rendered as a preview host's: their windows the Sandbox's)
	function host(scenarios:Array<helder.scenario.Scenario>):Host {
		Hosting.on = true;
		var h = new Host([], new HeadlessHost(), 1.0, scenarios);
		h.show([for (s in scenarios) s.name]);
		h.frame(0);
		Hosting.on = false;
		for (s in h.screens)
			equals(s.failure, null);
		return h;
	}
	function explorer(h:Host, i:Int):Explorer
		return h.screens[i].run(() -> Shell.explorer.peek());
	test("each screen its own explorer, booted through its actions", () -> {
		var h = host([
			scenario({name: "A", size: [1100, 700]}),
			scenario({name: "B", size: [1100, 700], boot: () -> act(ShowList)}),
			scenario({name: "C", size: [1100, 700], boot: () -> act(Go(Sandbox.EMPTY))})
		]);
		var a = explorer(h, 0), b = explorer(h, 1), c = explorer(h, 2);
		equals([a != b, b != c], [true, true]);
		equals([a.browser.layout.value, b.browser.layout.value], [Grid, List]);
		equals([a.browser.dir.value, b.browser.dir.value, c.browser.dir.value], [Sandbox.HOME, Sandbox.HOME, Sandbox.EMPTY]);
		// (a boot's Go in place of the start: nothing to go back to)
		equals(c.browser.canBack.value, false);
		equals(Shell.explorer.peek(), null);
	});
	test("a file opened by boot, full size; a folder that cannot be read", () -> {
		var h = host([
			scenario({name: "Photo", size: [1100, 700], boot: () -> act(OpenRecent(Sandbox.HOME + "/photo 2.jpg"))}),
			scenario({name: "Locked", size: [1100, 700], boot: () -> act(Go(Sandbox.LOCKED))}),
			scenario({name: "Several", size: [1100, 700], boot: () -> {
				act(Go(Sandbox.HOME));
				with(x -> {
					x.browser.select("alpha.png");
					x.browser.selection.extend(x.browser.indexOf("lossy.webp"));
					x.browser.selectionChanged();
				});
			}})
		]);
		var photo = explorer(h, 0);
		equals(photo.full.value, true);
		equals([photo.viewer.folder.name, photo.viewer.state.peek()], ["photo 2.jpg", "shown"]);
		equals(explorer(h, 1).browser.error.value, "denied");
		equals(explorer(h, 2).browser.picked(), ["alpha.png", "anim.gif", "broken.jpg", "lossy.webp"]);
	});
	test("a screen opens no store: what one kept not read, what it opens not kept", () -> {
		var was = Sys.getEnv("HELDER_HOME") ?? "";
		Sys.putEnv("HELDER_HOME", haxe.io.Path.join([Sys.getCwd(), "bin/scenario-home"]));
		var kept = helder.os.Store.open("helder-viewer");
		kept.set("layout", "list");
		kept.remove("recent");
		var h = host([scenario({name: "Kept", size: [1100, 700], boot: () -> act(OpenRecent(Sandbox.HOME + "/photo 2.jpg"))})]);
		var x = explorer(h, 0);
		equals(x.browser.layout.value, Grid);
		equals(x.full.value, true);
		equals(helder.os.Store.open("helder-viewer").get("recent"), null);
		Sys.putEnv("HELDER_HOME", was);
	});
	test("a screen rendered outside a preview host: its real files refused, its failure; none made", () -> {
		var h = new Host([], new HeadlessHost(), 1.0, [scenario({name: "Outside", size: [1100, 700]})]);
		h.show(["Outside"]);
		// (Hosting off as it renders: the Window makes NativeFiles, which the screen's seal refuses)
		h.frame(0);
		h.frame(1);
		equals((h.screens[0].failure?.message ?? "").split(" refused")[0], "viewer.NativeFiles");
	});
	test("a phone's photo dragged up a little and let go: nothing held, nothing ticking after", () -> {
		var h = host([scenario({
			name: "Dragged",
			size: [390, 844],
			boot: () -> act(OpenRecent(Sandbox.HOME + "/photo 2.jpg")),
			steps: [helder.scenario.Steps.drag({x: 195, y: 422}, {dx: 0, dy: -11})]
		})]);
		var x = explorer(h, 0), s = h.screens[0];
		equals([x.full.value, x.zoom.holding(), s.run(() -> helder.ui.Clock.active)], [true, false, false]);
	});
	test("a phone's shell made with a file open: its full screen on top, one of it", () -> {
		var h = host([scenario({name: "Opened", size: [390, 844], boot: () -> act(OpenRecent(Samples.ROOT + "/Starlings.jpg"))})]);
		var stack = h.screens[0].ui.root.find("stack");
		var full = [for (n in stack.children) if (n.find("full-stage") != null) n];
		equals(full.length, 1);
		equals(full[0].visible(), true);
	});
	test("a phone's size: the phone's shell", () -> {
		var h = host([scenario({name: "Phone", size: [390, 844], boot: () -> act(Go(Samples.ROOT))})]);
		var ui = h.screens[0].ui;
		assert(ui != null && ui.root.find("phone") != null, "the phone's shell");
		equals(explorer(h, 0).browser.dir.value, Samples.ROOT);
	});
	#end
}
