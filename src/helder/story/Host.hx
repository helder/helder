package helder.story;

import helder.math.Vec4;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.Surface;
import helder.scenario.Act;
import helder.scenario.Scenario;
import helder.story.Story;
import helder.ui.*;
import helder.ui.draw.*;
import helder.view.Render;

// Many stories in one program, each mounted as a root of its own: the
// studio's preview host (apps/studio). The program runs once; each screen
// (a story) has a Ui of its story's size and a ScreenContext of its own
// (its clock and timers, keymap, safe area, dark or light, settings), so
// screens animate, bind keys and keep settings apart, and a screen off
// screen stops all of it.
//
// What draws: only the screens shown (show: the names in view). The
// focused one (focus: the screen zoomed into) draws every frame; the
// others when something in them changed (their Ui asks for a frame, their
// clock animates). A screen hidden is suspended (its clock and timers
// stop) and keeps its last frame where it was shown (the studio's). A
// screen out of view is built and drawn once all the same, one a turn while
// nothing in view draws (a still drawn again when it changes): every screen
// has a frame to show, snap or keep, none of them waited on in view.
//
// Stills (stills: the studio's canvas, a storyboard): each screen built is
// brought to its moment (Stories.settle: its Controls.play, its transitions)
// and stays there, its clock not ticked (what changes it, a live literal, an
// event, still draws). The one looping (loop: the frame hovered, a story
// with a loop) runs live from its moment for its loop's seconds, then from
// its moment again; let go, it is its still again. All screens draw with one GPU device, one Renderer and one
// text engine (their glyph atlas and image pages shared), each frame into
// the runtime's target at the screen's size, handed over as it is drawn.
//
// A screen that throws (built, in its turn, drawn) is let go and passed
// over until the program starts again: its failure (HostFailure: the
// message, where its markup wrote what threw) told (onFailure); the others
// go on.
//
// The runtime is the host's way to pixels (HostRuntime): headless natively
// (HeadlessHost: an offscreen surface, each frame read back), an
// OffscreenCanvas in a web worker (helder.story.web.WorkerHost: each frame
// an ImageBitmap posted to the page), the studio's native preview process
// (helder.story.NativeHost's SharedFrames: each frame drawn into a GPU
// texture the studio's process opens, or copied through shared memory).
//
//   var host = new Host(Stories.of("Todo_story"), new HeadlessHost((s, pixels) -> ...));
//   host.show([for (s in host.screens) s.name]);
//   while (true) host.frame(haxe.Timer.stamp());
class Host {
	public final screens:Array<HostScreen> = [];
	public final runtime:HostRuntime;
	public final text:TextEngine;
	public final device:Device;
	public final renderer:Renderer;
	// pixels per point of every screen's frames
	public var scale(default, null) = 1.0;
	// the colour under a screen's tree (a window's default, as UiWindow's)
	public var background:Color = Color.rgb(0xF4F4F5);
	public var focused(default, null):Null<HostScreen> = null;
	// screens are stills (their moments, not run); the one running its loop (null: none)
	public var stills(default, null) = false;
	public var looping(default, null):Null<HostScreen> = null;
	// frames drawn, of every screen
	public var frames(default, null) = 0;
	// told: a screen's frame drawn and handed over
	public var onFrame:Null<HostScreen->Void> = null;
	// told: a screen threw (its failure; the others go on)
	public var onFailure:Null<HostScreen->Void> = null;

	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	// what the program's main gave UiWindow.run, each scenario's to render (helder.scenario; null: none)
	public final root:Null<helder.view.RootView>;

	public function new(stories:Array<Story>, runtime:HostRuntime, scale = 1.0, ?scenarios:Array<Scenario>) {
		root = Hosting.root;
		this.runtime = runtime;
		this.scale = scale;
		// (helder.text's own shaping: a screen looks the same everywhere)
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		text = new DrawText();
		device = Device.create(runtime.surface, {antialias: false});
		renderer = new Renderer(device);
		renderer.groups = true;
		for (s in stories)
			if (s != null) screens.push(new HostScreen(this, s));
		if (scenarios != null && scenarios.length > 0) {
			var main = root;
			if (main == null) throw "helder.story.Host: scenarios, but the program's main gave UiWindow.run no root";
			var size = Lambda.exists(scenarios, s -> s.width == null) ? Act.size(main) : null;
			for (s in scenarios)
				screens.push(new HostScreen(this, new Story(s.name, _ -> throw "helder.story: a scenario has no view of its own", s.seed, null, s.width ?? size?.width, s.height ?? size?.height, s.loop), s));
		}
		if (screens.length == 0) throw "helder.story.Host: no stories (a release build has none)";
		for (k => s in screens)
			if (Lambda.exists(screens.slice(0, k), o -> o.name == s.name)) throw 'helder.story.Host: two screens named "${s.name}" (a story\'s and a scenario\'s names are one list)';
	}

	public function screen(name:String):Null<HostScreen>
		return Lambda.find(screens, s -> s.name == name);

	// the screens in view (the others suspended, their last frames kept where they were shown)
	public function show(names:Array<String>) {
		for (s in screens) {
			var on = names.contains(s.name);
			if (on && !s.visible) s.redraw = true;
			s.visible = on;
			if (on) s.seen = true;
			s.context.suspended = !on;
		}
	}

	// stills or not (a screen already built: brought to its moment, or run from it)
	public function still(on:Bool) {
		if (on == stills) return;
		stills = on;
		for (s in screens)
			if (s.ui != null) s.reset();
	}

	// the screen running its loop from its moment (null, or a story without
	// a loop: none); the one before its still again
	public function loop(name:Null<String>) {
		var next = name == null ? null : screen(name);
		if (next != null && next.story.loop == null) next = null;
		if (next == looping) return;
		var was = looping;
		looping = next;
		if (was != null && was.ui != null) was.reset();
		if (next != null && next.ui != null) next.reset();
	}

	// whether a screen's clock runs: not a still's
	inline function runs(s:HostScreen):Bool
		return !stills || s == looping;

	// the screen drawn every frame (null: none; every one shown draws on
	// change), at its own pixels per point (the studio's zoom into it: its
	// frames sharp at the canvas' scale; the others at the host's)
	public function focus(name:Null<String>, ?scale:Float) {
		var was = focused, next = name == null ? null : screen(name);
		if (was != null && was != next && was.scale != this.scale) {
			was.scale = this.scale;
			was.redraw = true;
		}
		focused = next;
		if (next == null) return;
		var k = scale ?? this.scale;
		if (k != next.scale) next.scale = k;
		next.redraw = true;
	}

	// one turn at now (seconds): each screen shown built the first time,
	// its clock ticked, laid out, and drawn when it changed (the focused one
	// always): how many were drawn
	public function frame(now:Float):Int {
		var drawn = 0;
		for (s in screens)
			if (s.visible && s.failure == null && guard(s, () -> turn(s, now))) drawn++;
		if (drawn > 0) return drawn;
		for (s in screens)
			if (aside(s)) return guard(s, () -> {
				s.mount();
				var ui = s.ui, v = s.version;
				if (ui != null) s.context.run(() -> ui.update());
				draw(s, true);
				s.version > v;
			}) ? 1 : 0;
		return 0;
	}

	// (a screen's error: its failure, the screen let go and passed over until
	// the program starts again; the others go on)
	public function guard(s:HostScreen, f:Void->Bool):Bool
		return try f() catch (e:haxe.Exception) {
			s.failure = HostFailure.of(e);
			try s.reset() catch (_:haxe.Exception) {}
			if (onFailure != null) onFailure(s);
			false;
		}

	// (a screen in view's turn: whether it drew)
	function turn(s:HostScreen, now:Float):Bool {
		s.mount();
		// (a loop: its clock from its moment, its loop's seconds, then again)
		if (s == looping) {
			var loop:Float = s.story.loop ?? 0;
			if (s.loopFrom < 0) s.loopFrom = now;
			if (now - s.loopFrom > loop) {
				s.reset();
				s.mount();
				s.loopFrom = now;
			}
		}
		var ui = s.ui;
		if (ui == null) return false;
		var running = runs(s);
		var changed = s.context.run(() -> {
			if (running) Clock.tick(s == looping ? s.moment + now - s.loopFrom : now);
			ui.update();
			ui.needsFrame || running && s.context.animating;
		});
		if (!(changed || s.redraw || (s == focused && running))) return false;
		draw(s, changed || s.redraw);
		return true;
	}

	// (out of view: never drawn, or a still that changed; not the looping one)
	function aside(s:HostScreen):Bool
		return !s.visible && s != looping && s.failure == null && (s.version == 0 || stills && (s.ui == null || s.redraw || s.ui.needsFrame));

	// a screen's frame as data (FrameWriter's: the studio's stills, its
	// frames file), on the host's background as drawn; null: not built
	// (a pass's box: its picture, read back from the GPU). fps: a loop
	// story's loop too, its frames from its moment on its clock (as hovered,
	// Host.loop), the screen built again after (its moment); none when a
	// pass draws in it (played live)
	public function written(s:HostScreen, fps = 0):Null<FrameWriter.Frame> {
		var ui = s.ui;
		if (ui == null) return null;
		var w = new FrameWriter();
		// (a pass's box its picture at CAPTURE pixels a point: the screen drawn
		// so into the runtime's surface, the writer painted in that frame's
		// wake, the passes' textures read back as it left them)
		var k = Math.max(CAPTURE, s.scale);
		if (captured(s, k)) w.gpu(renderer);
		w.rect(0, 0, s.width, s.height, 0, background, 0, 0);
		s.context.run(() -> ui.paint(w));
		renderer.scale = ui.scale = s.scale;
		// (a loop recorded once a build: its program's frames the same each time, randomness seeded)
		var loop:Float = s.story.loop ?? 0;
		if (fps <= 0 || loop <= 0 || s.looped) return w.frame();
		s.looped = true;
		w.loop(fps);
		s.reset();
		s.mount();
		var u = s.ui;
		if (u == null) return w.frame();
		for (f in 0...Math.ceil(loop * fps)) {
			if (f > 0) w.next();
			w.rect(0, 0, s.width, s.height, 0, background, 0, 0);
			s.context.run(() -> {
				if (f > 0) Clock.tick(s.moment + f / fps);
				u.update();
				u.paint(w);
			});
		}
		s.reset();
		return w.frame();
	}

	// pixels a point of a still's passes' pictures (Host.written)
	public static inline var CAPTURE = 2.0;

	// (a screen drawn at k pixels a point into the runtime's surface, not handed over: whether it was)
	function captured(s:HostScreen, k:Float):Bool {
		var ui = s.ui;
		if (ui == null) return false;
		var w = Math.round(s.width * k), h = Math.round(s.height * k), surface = runtime.surface;
		if (surface.width != w || surface.height != h) @:privateAccess surface.resized(w, h);
		var enc = device.beginFrame();
		if (enc == null) return false;
		renderer.scale = k;
		ui.scale = k;
		s.context.run(() -> {
			renderer.begin(device.width, device.height);
			ui.paint(renderer);
			renderer.prepare(enc);
		});
		enc.beginPass(pass);
		renderer.end(enc);
		enc.endPass();
		device.endFrame();
		return true;
	}

	// whether anything shown would draw in the next turn (else the loop may sleep until the next event or timer)
	public function busy():Bool {
		for (s in screens)
			if (s.visible && (s.ui == null || s.redraw || s.ui.needsFrame || runs(s) && (s == focused || s.context.animating)) || aside(s)) return true;
		return false;
	}

	// the earliest timer of the screens shown (Clock's time; infinity: none)
	public function nextTimer():Float {
		var t = Math.POSITIVE_INFINITY;
		for (s in screens)
			if (s.visible) t = Math.min(t, s.context.nextTimer());
		return t;
	}

	// a screen's frame: the target at its size, its tree painted, handed over
	// (changed: something in it changed since its last frame; else the focused one's frame of every turn)
	function draw(s:HostScreen, changed:Bool) {
		var ui = s.ui;
		if (ui == null) return;
		var scale = s.scale;
		var w = Math.round(s.width * scale), h = Math.round(s.height * scale);
		// (not now: the runtime has no target free for it, or the same pixels are there; again at a next turn when it changed)
		if (!runtime.begin(s, device, w, h, changed)) {
			if (changed) s.redraw = true;
			return;
		}
		var enc = device.beginFrame();
		if (enc == null) {
			s.redraw = true;
			return;
		}
		s.redraw = false;
		var t = pass.colors[0], c = t.clear;
		if (c != null) helder.gfx.ColorTarget.ClearValue.set(t, background.r / 255, background.g / 255, background.b / 255, c.w);
		renderer.scale = scale;
		ui.scale = scale;
		try s.context.run(() -> {
			renderer.begin(device.width, device.height);
			ui.paint(renderer);
			renderer.prepare(enc);
		}) catch (e:haxe.Exception) {
			device.endFrame();
			throw helder.async.Errors.kept(e);
		}
		enc.beginPass(pass);
		renderer.end(enc);
		enc.endPass();
		runtime.capture(s, device);
		device.endFrame();
		s.version++;
		frames++;
		runtime.present(s, changed);
		if (onFrame != null) onFrame(s);
	}
}

// One screen of a host: its story, its context, its Ui (made when first shown)
class HostScreen {
	public final host:Host;
	public final story:Story;
	public final name:String;
	public final context:ScreenContext;
	// its size in points (the story's, a phone's without)
	public final width:Int;
	public final height:Int;
	public var ui(default, null):Null<Ui> = null;
	public var controls(default, null):Null<Controls> = null;
	// what it shows when it is a scenario's (the program's main, its data), else its story's view
	public final scenario:Null<Scenario>;
	public var visible = false;
	// (its loop recorded: Host.written's, once a build)
	public var looped = false;
	// what it threw (null: fine): passed over until the program starts again
	public var failure:Null<HostFailure> = null;
	// whether it was ever in view (its state kept across a reload: built again before the first frame)
	public var seen = false;
	// its frames' pixels per point (the host's, or its focus's)
	public var scale:Float;
	// frames drawn
	@:allow(helder.story.Host) public var version(default, null) = 0;
	// (shown again, focused: a frame due whatever changed)
	@:allow(helder.story.Host) var redraw = true;
	// when it was built (haxe.Timer.stamp; -1: not yet)
	public var mountedAt(default, null) = -1.0;
	// its clock's time at its moment (a still's), and when its loop began (the host's time; -1: not yet)
	public var moment(default, null) = 0.0;
	@:allow(helder.story.Host) var loopFrom = -1.0;
	// (its view's owner let go: reset)
	var unrender:Null<Void->Void> = null;

	public function new(host:Host, story:Story, ?scenario:Scenario) {
		this.host = host;
		this.story = story;
		this.scenario = scenario;
		name = story.name;
		width = story.width ?? Stories.WIDTH;
		height = story.height ?? Stories.HEIGHT;
		// (its values a store of its own: a scenario's apart from the others')
		context = new ScreenContext(name, true, null, new helder.view.graph.Atoms(name));
		var dark = scenario?.dark;
		if (dark != null) context.dark(dark);
		scale = host.scale;
	}

	// built: its Ui made in its context, its story's view rendered into the root
	public function mount() {
		if (ui != null) return;
		mountedAt = haxe.Timer.stamp();
		// (its state's keys in a scope of its name: kept across a reload whichever screens mount first, helder.dev.Hot)
		context.run(() -> helder.dev.Hot.scope(name, () -> {
			// (its randomness from its seed: built again, the same still, the same loop)
			helder.os.Seed.random(story.seed);
			var u = new Ui(host.text, width, height);
			u.dark = context.dark.peek();
			ui = u;
			var c = new Controls(story.seed);
			controls = c;
			var sc = scenario, main = host.root;
			if (sc != null && main != null) {
				if (sc.play != null) c.play(sc.play);
				unrender = Act.mount(sc, main, context, u);
			} else
				unrender = Render.render(story.build(c), u.root);
			// (a still, or a loop's start: brought to its moment; one that never settles is left where it got;
			// a scenario's clock stands at its moment unless it plays to it)
			if (host.stills && (sc == null || !c.settled())) bring(u, c);
			moment = Clock.now;
			true;
		}));
		redraw = true;
	}

	// (a still's moment: its Controls.play run frame by frame, 60 a second of
	// its clock, at most a minute; else its transitions run on for 2 s of its
	// clock at most: Stories.settle's Clock.finish would run a game's endless
	// step a hundred thousand times)
	static function bring(ui:Ui, c:Controls) {
		helder.view.graph.Graph.flush();
		var start = Clock.now, t = start;
		if (c.settled()) {
			while (Clock.active && t < start + 2) {
				t += 0.1;
				Clock.tick(t);
				ui.update();
			}
			return;
		}
		var frames = 0;
		while (!c.settled() && frames < 60 * Stories.FPS) {
			frames++;
			Clock.tick(start + frames / Stories.FPS);
			ui.update();
		}
	}

	// let go and built again at its next turn (from its clock's start: its moment again)
	public function reset() {
		if (ui == null) return;
		context.run(() -> {
			if (unrender != null) unrender();
			if (controls != null) controls.dispose();
		});
		unrender = null;
		// (built again from its start: its values too)
		context.atoms?.clear();
		@:privateAccess context.steps.resize(0);
		@:privateAccess context.timers.resize(0);
		@:privateAccess context.now = 0;
		ui = null;
		loopFrom = -1;
		redraw = true;
	}

	// something to do in it (an event's handling, a devtools method): f with its context current
	public inline function run<T>(f:Void->T):T
		return context.run(f);
}

// A host's way to pixels: its target (a surface the device renders to),
// made ready for each screen's frame (begin: the surface sized, or a texture
// the frame goes into; false: no frame of it now, changed or not: drawn
// later; changed: whether anything in it changed since its last frame, else
// the focused screen's frame of every turn, the same pixels), each frame
// read (capture: before it is presented) and handed over (present: after)
interface HostRuntime {
	var surface(default, null):Surface;
	function begin(s:HostScreen, device:Device, width:Int, height:Int, changed:Bool):Bool;
	function capture(s:HostScreen, device:Device):Void;
	function present(s:HostScreen, changed:Bool):Void;
}

// Natively, offscreen: each screen's frame read back into its pixels
// (RGBA8, rows top to bottom), handed to frame
class HeadlessHost implements HostRuntime {
	public var surface(default, null):Surface;
	// each screen's last frame
	public final pixels = new Map<String, Bytes>();
	final framed:Null<(s:HostScreen, pixels:Bytes) -> Void>;

	public function new(?framed:(s:HostScreen, pixels:Bytes) -> Void) {
		this.framed = framed;
		surface = Surface.headless(1, 1);
	}

	public function begin(s:HostScreen, device:Device, width:Int, height:Int, changed:Bool):Bool {
		if (surface.width != width || surface.height != height) @:privateAccess surface.resized(width, height);
		return true;
	}

	public function capture(s:HostScreen, device:Device) {
		var n = device.width * device.height * 4;
		var b = pixels.get(s.name);
		if (b == null || b.length != n) {
			b = Bytes.alloc(n);
			pixels.set(s.name, b);
		}
		device.readPixels(b);
	}

	public function present(s:HostScreen, changed:Bool) {
		var f = framed, b = pixels.get(s.name);
		if (f != null && b != null) f(s, b);
	}
}

// A screen's error: its message, and where its markup wrote what threw
// ("file:line", when it says: helder.view.MarkupError)
@:structInit class HostFailure {
	public final message:String;
	public final at:Null<String>;

	public static function of(e:haxe.Exception):HostFailure {
		var m = Std.downcast(e, helder.view.MarkupError), at = m?.at;
		return {message: e.message, at: at == null ? null : '${at.file}:${at.line}'};
	}
}
