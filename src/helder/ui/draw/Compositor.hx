package helder.ui.draw;

#if (hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.Event as OsEvent;
import helder.ui.*;
import sys.thread.Mutex;

// A window's compositor (Layers' step 4b): scrolling at the display's rate
// while the program is busy. The main thread hands it each input event as
// it reads it (route), before the program gets it; its mirror of the
// scrollers (ScrollMirror) takes the scrolls that are its own and runs the
// physics; on the render thread (RenderIdle) it draws a frame each vsync
// the program misses, from the program's last frame (CompositeFrame: its
// quads, each scroller's moved by the mirror's offsets, its tiles where
// they fall), and the program takes the offsets at its next turn (drain)
// and draws from them. Its state is under one lock, taken by the three
// threads in turn, each for a short while: the mirror's step, an event
// routed, the offsets drained, a frame's state adopted. Its own frames are
// drawn whole (no damage told; the program's next frame tells all of it
// changed). What moves on its own between the program's frames moves in
// its frames too, sampled at the time each is drawn: a layer's transform
// and opacity (helder.ui.Mover: a transition, a spring, a tween, the same
// closed forms the program samples), sticky nodes by the mirror's offsets,
// overlay scrollbars shown and faded as the program's are; the native
// views over a scroller (a macOS field, a web view) moved on the main
// thread as each frame is drawn (helder.os.OsThread.post). Where the
// platform's own scroll views drive the scrollers (iOS's UIScrollView:
// IosScroll), their offsets come to it on the main thread as they move
// (nativeScrolled), its frames drawn at them, the physics the system's.
// Where the system composites layers (macOS and iOS: CaLayers; Android:
// ScLayers; Windows: DcLayers; Wayland: WlLayers; LayerSplit), every
// frame, the program's too, is handed to it from the same state, a
// scroller's content and a mover on layers the system moves. Off with
// HELDER_ASYNC_SCROLL=0, and where the program has no thread of its own
// (helder.os.OsThread), headless and for screenshots.
@:hxmc.unsafe(gc)
@:access(helder.ui.Ui)
@:access(helder.ui.ScrollMirror)
@:access(helder.ui.draw.CompositeFrame)
class Compositor implements RenderIdle {
	public final mirror = new ScrollMirror();
	final device:Device;
	final lock = new Mutex();
	final shot = new ScrollShot();
	// (the frames the program fills in turn; the one adopted on the render thread)
	final frames = [new CompositeFrame(), new CompositeFrame()];
	var filling = 0;
	var shown:Null<CompositeFrame> = null;
	// (the instance buffers, in a ring: one written while the GPU may read another)
	final buffers:Array<Buffer> = [];
	var capacity = 0;
	var ring = 0;
	// (the render thread's: what it composes into, its commands, the offsets now)
	var out = Bytes.alloc(0);
	final commands = new Commands();
	final now:Array<Float> = [];
	final shownAt:Array<Float> = [];
	final runTextures:Array<Null<Texture>> = [];
	final runs:Array<Int> = [];
	// (timing: the display's period (learnt from its own frames drawn back
	// to back, as their presents wait for the vsync), when the program last
	// drained, the mirror stepped, the compositor drew)
	var period = 1 / 60;
	var drained = -1e9;
	var stepped = -1e9;
	var drew = -1e9;
	// (whether the last frame was presented to a swap chain whose latency
	// object paces the next (Direct3D 11's): due as soon as it is drawn.
	// Half a period after the draw, the render thread's timed wait, is
	// Windows' 15.6 ms tick, or two of them after a slow draw (WARP's): the
	// next vblank missed, the frames locked at half the display's rate)
	var paced = false;
	// (the render thread's: the overlay bars' last moves and how far they
	// show, per frame; the time its last frame was drawn at, Ui.now's)
	final barAt:Array<Float> = [];
	final barShown:Array<Float> = [];
	var animAt = -1e9;
	// (the native views over scrollers, from the program's last frame; the moves to post)
	var spots:Array<Spot> = [];
	final posts:Array<Spot> = [];
	// (the last input it took; whether the program is in a turn, not asleep)
	var routedAt = -1e9;
	var turn = true;
	// whether it drew a frame since the program's last (that one tells all of it changed)
	public var drewSince(default, null) = false;
	// frames drawn, and the time of each one's input to its present (tests, the latency's numbers)
	public var count(default, null) = 0;
	public var onFrame:Null<Float->Void> = null;

	public function new(device:Device) {
		this.device = device;
		#if (!helder.os || helder.os == "macos" || helder.os == "ios")
		if (hxmc.Platform.os() == 1 && CaLayers.wanted(device)) layers = new CaLayers(device);
		#end
		#if (!helder.os || helder.os == "android")
		if (hxmc.Platform.target() >= 9 && ScLayers.wanted(device)) layers = ScLayers.make(device);
		#end
		#if (!helder.os || helder.os == "windows")
		if (hxmc.Platform.os() == 2 && DcLayers.wanted(device)) layers = new DcLayers(device);
		#end
		#if (!helder.os || helder.os == "linux")
		if (hxmc.Platform.os() == 0 && hxmc.Platform.target() < 9 && WlLayers.wanted(device)) layers = new WlLayers(device);
		#end
	}

	// the system's layers (Core Animation's, SurfaceControl's, DirectComposition's, Wayland's), where its
	// frames go (null: drawn onto the window's one layer)
	public var layers(default, null):Null<LayerSplit> = null;
	// (the window's frames drawn onto its layer last, as the textured compositor draws: not quiet)
	var loud = true;

	// whether the program's frames go to the system's layers
	public function planes():Bool {
		if (layers != null) layers.prepare();
		return layers != null && !layers.single && !layers.priming;
	}

	// (before the program's frame: whether it draws onto the window's layer
	// (a frame read back) or only into targets, the system's layers drawn
	// from it after (present))
	public function quiet(on:Bool) {
		var l = layers;
		if (l == null || loud == !on) return;
		loud = !on;
		device.inOrder(r -> {
			l.quiet(r, on);
			if (!on) l.suspend();
		});
	}

	// (after the program's frame ended: it shown on the system's layers, as
	// drawn; drawn onto the window's layer (planes false), split only, for the next)
	public function present(planes:Bool) {
		var l = layers;
		if (l == null) return;
		device.inOrder(r -> {
			var f = shown;
			if (f == null) return;
			if (!planes) {
				l.check(f);
				l.windowShown();
				return;
			}
			// (its overlay bars as the program faded them when it painted)
			var t = f.paintedAt, bars = f.overlay ? [for (v in f.barAt) {
				var age = t - v;
				age >= SHOWN + FADE ? 0 : age <= SHOWN ? 1 : 1 - (age - SHOWN) / FADE;
			}] : null;
			l.show(r, f, f.offsets, t, bars, true, []);
			// (shown at the display's pace: the program keeps it, its next frame the next vsync's)
			lock.acquire();
			drained = drew = haxe.Timer.stamp();
			lock.release();
		});
		// (handed over now: recorded after the frame's end, it would wait for
		// the next frame where the loop does not settle, a still window's last never shown)
		if (planes) @:privateAccess device.flush();
	}

	// whether the compositor runs here: a window's GPU on the render thread,
	// the program on its own thread (Android's always is: the activity's
	// glue, its input routed on the UI thread as it is read)
	public static function wanted(device:Device):Bool {
		#if (helder.headless || hxmc.target == "wasm32-wasi")
		return false;
		#else
		var own = helder.os.OsThread.wanted() || hxmc.Platform.target() >= 9 && device.surface.kind == Android;
		return device.threaded && own && Sys.getEnv("HELDER_ASYNC_SCROLL") != "0";
		#end
	}

	// whether its mirror moves anything still (a glide, a spring, a fling)
	public function moving():Bool {
		lock.acquire();
		var m = mirror.moving;
		lock.release();
		return m || layers != null && layers.redraw;
	}

	// the mirror's offsets of the program's node n (null: none), from any thread
	public function offsets(n:Node):Null<{x:Float, y:Float}> {
		lock.acquire();
		var o = mirror.offsets(n);
		lock.release();
		return o;
	}

	public function start():Bool
		return device.addIdle(this);

	public function stop()
		device.removeIdle(this);

	// ---- the main thread's (or the program's, where it reads input)

	// e, as it is read: the compositor's first (e.routed, e.gesture)
	public function route(e:OsEvent) {
		lock.acquire();
		var r = try UiEvents.route(mirror, e) catch (x:haxe.Exception) {
			lock.release();
			throw x;
		}
		if (r == ScrollMirror.TAKEN) routedAt = haxe.Timer.stamp();
		lock.release();
		if (r == ScrollMirror.TAKEN) device.wake();
	}

	// a platform's scroll view moved the program's n to x, y (its scrollX
	// and scrollY), as it moves (iOS's deceleration and bounce, the program busy)
	public function nativeScrolled(n:Node, x:Float, y:Float) {
		lock.acquire();
		var o = native.get(n);
		if (o == null) native.set(n, o = [0, 0]);
		o[0] = x;
		o[1] = y;
		mirror.place(n, x, y);
		routedAt = haxe.Timer.stamp();
		lock.release();
		// (the system's layers: its content's layer follows in UIKit's own transaction)
		if (layers != null) layers.scrolled(n, x, y);
		device.wake();
	}

	// (the platform's offsets, the latest: kept over each program frame's, which may be older)
	final native = new Map<Node, Array<Float>>();

	// the program goes to sleep, nothing to draw (UiWindow.run, before App.wait):
	// an input then wakes it, the compositor drawing only if it does not drain soon
	public function rest() {
		lock.acquire();
		turn = false;
		lock.release();
	}

	// ---- the program's

	// at the start of its turn: the mirror stepped, its offsets given to ui (Ui.mirrored)
	public function drain(ui:Ui) {
		var t = haxe.Timer.stamp();
		lock.acquire();
		drained = t;
		turn = true;
		// (each turn: its frame shows the motion as its own glide's would)
		mirror.step(Ui.now());
		stepped = t;
		mirror.drain((n, x, y, held, moving) -> ui.mirrored(n, x, y, held, moving));
		lock.release();
	}

	// its answer to a gesture's question
	public function answer(gesture:Int, through:Bool) {
		lock.acquire();
		mirror.answer(gesture, through);
		lock.release();
		device.wake();
	}

	// before the program's frame paints: what it fills (Renderer.composite)
	public function begin(r:Renderer) {
		r.composite = frames[filling];
	}

	// after it painted, before it ends: its scrollers to the mirror, its
	// frame's state to the render thread with the frame (in order)
	public function end(ui:Ui, r:Renderer) {
		var f = frames[filling];
		r.composite = null;
		ScrollShot.take(ui, shot);
		// (a native view in the system's layer tree: moved with its layers, in their transaction)
		var made = shot.natives.length == 0 ? [] : [for (s in Spot.of(shot)) if (s.node.systemLayer == null) s];
		lock.acquire();
		mirror.adopt(shot);
		for (n in [for (n in native.keys()) n]) {
			var o = native.get(n);
			if (mirror.offsets(n) == null) native.remove(n) else mirror.place(n, o[0], o[1]);
		}
		spots = made;
		lock.release();
		drewSince = false;
		if (!f.ready || !r.ended(f)) return;
		// (room for every quad it may draw, in each buffer of the ring)
		var need = (f.quads() + 64) * CompositeFrame.STRIDE;
		if (need > capacity) {
			for (b in buffers)
				device.destroyBuffer(b);
			buffers.resize(0);
			capacity = need * 2;
			for (_ in 0...QuadBatch.RING)
				buffers.push(device.createBuffer({size: capacity, usage: Vertex}));
		}
		f.paintedAt = Ui.now();
		f.buffers = buffers.copy();
		f.capacity = capacity;
		filling = 1 - filling;
		device.inOrder(_ -> adopt(f));
	}

	public function dispose() {
		var l = layers;
		if (l != null) device.inOrder(_ -> l.dispose());
		layers = null;
		stop();
		for (b in buffers)
			device.destroyBuffer(b);
		buffers.resize(0);
	}

	// ---- the render thread's

	// (the program's frame's state, run in order with it)
	function adopt(f:CompositeFrame) {
		lock.acquire();
		shown = f;
		shownAt.resize(0);
		for (v in f.offsets)
			shownAt.push(v);
		barAt.resize(0);
		for (v in f.barAt)
			barAt.push(v);
		animAt = Ui.now();
		lock.release();
		if (layers != null) layers.adopt();
	}

	public function due():Float {
		lock.acquire();
		var f = shown, d = -1.0;
		if (f != null && (mirror.moving || moved(f) || f.moves(animAt) || fading(animAt))) {
			// (the program's to draw while it keeps the pace: it drained this vsync)
			// (asleep: it wakes for the input and draws it, unless it has not drained since)
			d = Math.max(paced ? drew : drew + period * 0.5, turn ? drained + period * 0.6 : drained > routedAt ? drained + period * 0.6 : routedAt + period * 0.6);
		}
		lock.release();
		return d;
	}

	// (whether the mirror's offsets differ from those last shown)
	function moved(f:CompositeFrame):Bool {
		for (i in 0...f.nodes.length) {
			var o = mirror.offsets(f.nodes[i]);
			if (o != null && (o.x != shownAt[2 * i] || o.y != shownAt[2 * i + 1])) return true;
		}
		return false;
	}

	public function idle(r:Replay) {
		// (the program's frame is being drawn: it shows the latest)
		if (r.framing) return;
		var t = haxe.Timer.stamp();
		lock.acquire();
		var f = shown, s = device.surface;
		// (one of another size than the window's now: a live resize's frame is the program's)
		// (one with a backdrop: the program's, which draws what it reads at the offsets it drains)
		if (f == null || f.backdrops > 0 || f.width != s.width || f.height != s.height || t - drained < period * 0.6
			|| !turn && drained > routedAt && t - routedAt < period * 0.6) {
			lock.release();
			return;
		}
		var at = Ui.now();
		if (t - stepped > period / 2) {
			mirror.step(at);
			stepped = t;
		}
		var changed = offsetsNow(f, at);
		if (!changed && !f.moves(animAt) && !fading(animAt)) {
			drew = t;
			lock.release();
			return;
		}
		// (onto the window's swap chain: until it takes the frame without
		// queueing it (Device.waitFrame), then sampled; the program's, if it
		// drained meanwhile)
		if (layers == null || layers.single) {
			lock.release();
			r.impl.waitFrame();
			lock.acquire();
			if (haxe.Timer.stamp() - drained < period * 0.6) {
				lock.release();
				return;
			}
			at = Ui.now();
			mirror.step(at);
			stepped = haxe.Timer.stamp();
			offsetsNow(f, at);
		}
		for (i in 0...now.length)
			shownAt[i] = now[i];
		animAt = at;
		natives();
		lock.release();
		// (the native views moved on the main thread as the frame is drawn:
		// the system's layers move them in the frame's transaction)
		var moves = [for (p in posts) {
			var n = p.node, x = p.x, y = p.y, w = p.w, h = p.h, on = p.on;
			() -> @:privateAccess n.placeNative(x, y, w, h, on);
		}];
		posts.resize(0);
		if (layers != null && !layers.single) {
			paced = false;
			layers.show(r, f, now, at, f.overlay ? barShown : null, false, moves);
		} else {
			// (the window's layer alone since the program's last frame: drawn onto it, taking its drawable)
			if (layers != null) layers.quiet(r, false);
			for (m in moves)
				helder.os.OsThread.post(m);
			draw(r, f, null, at);
			paced = r.impl.paces();
			if (layers != null) layers.windowShown();
		}
		var at = haxe.Timer.stamp(), d = at - drew;
		if (d > 0.002 && d < period * 1.5) period = period * 0.9 + d * 0.1;
		drew = at;
		drewSince = true;
		count++;
		if (onFrame != null) onFrame(drew);
	}

	// (the mirror's offsets of f's scrollers into now, at t: whether they
	// differ from those shown; an overlay bar moved shown again, and how far
	// each shows then, as Ui.barShown has it)
	function offsetsNow(f:CompositeFrame, t:Float):Bool {
		now.resize(0);
		barShown.resize(0);
		var changed = false;
		for (i in 0...f.nodes.length) {
			var o = mirror.offsets(f.nodes[i]);
			var x = o == null ? f.offsets[2 * i] : o.x, y = o == null ? f.offsets[2 * i + 1] : o.y;
			now.push(x);
			now.push(y);
			if (x != shownAt[2 * i] || y != shownAt[2 * i + 1]) {
				changed = true;
				if (f.overlay) barAt[i] = t;
			}
			var age = t - barAt[i];
			barShown.push(age >= SHOWN + FADE ? 0 : age <= SHOWN ? 1 : 1 - (age - SHOWN) / FADE);
		}
		return changed;
	}

	static inline var SHOWN = @:privateAccess Ui.BAR_SHOWN;
	static inline var FADE = @:privateAccess Ui.BAR_FADE;

	// (whether an overlay bar fades at t)
	function fading(t:Float):Bool {
		for (v in barAt)
			if (v > -1e9 && t - v < SHOWN + FADE) return true;
		return false;
	}

	// (the native views over the scrollers moved: where they fall at the
	// mirror's offsets, shown while inside their scroller's view; those that
	// moved since, into posts)
	function natives() {
		for (p in spots)
			if (p.at(mirror)) posts.push(p);
	}

	// a frame drawn at the mirror's offsets now, from the program's last,
	// its pixels read into capture before it is presented (a test's,
	// synchronously: the device's own thread)
	@:noCompletion public function drawNow(capture:haxe.io.Bytes) {
		device.inOrder(r -> {
			var f = shown;
			if (f == null) return;
			var t = Ui.now();
			offsetsNow(f, t);
			for (i in 0...now.length)
				shownAt[i] = now[i];
			animAt = t;
			draw(r, f, capture, t);
		});
		device.settle();
	}

	// (f's quads at the offsets now and time t, drawn whole and presented)
	function draw(r:Replay, f:CompositeFrame, capture:Null<haxe.io.Bytes>, t:Float) {
		if (f.buffers.length == 0 || r.impl.width != f.width || r.impl.height != f.height) return;
		var need = f.quads() * CompositeFrame.STRIDE;
		if (out.length < need) out = Bytes.alloc(need * 2);
		var n = f.compose(now, t, f.overlay ? barShown : null, out, runTextures, runs);
		if (n * CompositeFrame.STRIDE > f.capacity) return;
		var b = f.buffers[ring = (ring + 1) % f.buffers.length], c = commands, bg = f.background;
		c.clear();
		one(Replay.BEGIN_FRAME);
		r.run(c, false);
		c.clear();
		// (no drawable now: a hidden window)
		if (!r.began) return;
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(0);
		c.bytes(out, 0, n * CompositeFrame.STRIDE);
		c.end();
		// (the frame's pass: its background, multisampled as the window's)
		c.begin(Replay.BEGIN_PASS);
		c.int(1);
		c.int(cast LoadOp.Clear);
		CompositeFrame.clearTo(c, bg);
		c.int(0);
		c.int(0);
		c.int(Replay.NONE);
		c.int(0);
		c.end();
		if (n > 0) {
			three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
			three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
			three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
			three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
			for (k in 0...runTextures.length) {
				var t = runTextures[k];
				three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
				three(Replay.SET_VERTEX_BUFFER, 1, b.id(), runs[2 * k] * CompositeFrame.STRIDE, 3);
				c.begin(Replay.DRAW_INDEXED);
				c.int(6);
				c.int(runs[2 * k + 1]);
				c.int(0);
				c.int(0);
				c.end();
			}
		}
		one(Replay.END_PASS);
		if (capture != null) {
			r.run(c, false);
			c.clear();
			r.impl.readPixels(capture);
		}
		one(Replay.END_FRAME);
		r.run(c, false);
		c.clear();
	}

	inline function one(op:Int) {
		commands.begin(op);
		commands.end();
	}

	// (op and its first n of a, b, d)
	inline function three(op:Int, a:Int, b:Int, d:Int, n:Int) {
		var c = commands;
		c.begin(op);
		c.int(a);
		if (n > 1) c.int(b);
		if (n > 2) c.int(d);
		c.end();
	}
}

// (a native view over a scroller: its node, its scrollers (its own first)
// and their offsets as the program placed it, its scroller's view (x0, y0,
// x1, y1, in the coordinates of the content it is in), where it was placed;
// where it was last moved to)
private class Spot {
	public final node:Node;
	final chain:Array<Node> = [];
	final offsets:Array<Float> = [];
	final view:Array<Float> = [];
	final placed:Array<Float> = [];
	public var x = 0.0;
	public var y = 0.0;
	public var w = 0.0;
	public var h = 0.0;
	public var on = false;

	function new(n:Node) {
		node = n;
	}

	public static function of(shot:ScrollShot):Array<Spot> {
		var out = [];
		for (k in 0...shot.natives.length) {
			var s = new Spot(shot.natives[k]), i = shot.nativeAt[k], e = shot.entries[i];
			for (j in 0...5)
				s.placed.push(shot.placed[5 * k + j]);
			s.x = s.placed[0];
			s.y = s.placed[1];
			s.w = s.placed[2];
			s.h = s.placed[3];
			s.on = s.placed[4] == 1;
			for (v in [e.vx, e.vy, e.vx + e.vw, e.vy + e.vh])
				s.view.push(v);
			while (i >= 0) {
				var c = shot.entries[i];
				s.chain.push(c.node);
				s.offsets.push(c.scrollX);
				s.offsets.push(c.scrollY);
				i = c.up;
			}
			out.push(s);
		}
		return out;
	}

	// (where it falls at the mirror's offsets: whether it moved)
	public function at(m:ScrollMirror):Bool {
		var dx = 0.0, dy = 0.0, ox = 0.0, oy = 0.0;
		for (i in 0...chain.length) {
			var o = @:privateAccess m.offsets(chain[i]);
			if (o == null) continue;
			var ex = offsets[2 * i] - o.x, ey = offsets[2 * i + 1] - o.y;
			dx += ex;
			dy += ey;
			// (its scroller's view moves with those around it)
			if (i > 0) {
				ox += ex;
				oy += ey;
			}
		}
		var p = placed, nx = p[0] + dx, ny = p[1] + dy;
		// (the view in the window: its own scroller's offsets as placed taken off the coordinates of its content)
		var sx = 0.0, sy = 0.0;
		for (i in 1...chain.length) {
			sx += offsets[2 * i];
			sy += offsets[2 * i + 1];
		}
		var x0 = view[0] - sx + ox, y0 = view[1] - sy + oy, x1 = view[2] - sx + ox, y1 = view[3] - sy + oy;
		var inside = nx >= x0 - 0.5 && ny >= y0 - 0.5 && nx + p[2] <= x1 + 0.5 && ny + p[3] <= y1 + 0.5;
		var show = p[4] == 1 && inside;
		if (nx == x && ny == y && show == on) return false;
		x = nx;
		y = ny;
		w = p[2];
		h = p[3];
		on = show;
		return true;
	}
}
#end
