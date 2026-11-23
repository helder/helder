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
// changed). Off with HELDER_ASYNC_SCROLL=0, and where the program has no
// thread of its own (helder.os.OsThread), headless and for screenshots.
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
	}

	// whether the compositor runs here: a window's GPU on the render thread, the program on its own thread
	public static function wanted(device:Device):Bool {
		#if (helder.headless || hxmc.target == "wasm32-wasi")
		return false;
		#else
		return device.threaded && helder.os.OsThread.wanted() && Sys.getEnv("HELDER_ASYNC_SCROLL") != "0";
		#end
	}

	// whether its mirror moves anything still (a glide, a spring, a fling)
	public function moving():Bool {
		lock.acquire();
		var m = mirror.moving;
		lock.release();
		return m;
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
		lock.acquire();
		mirror.adopt(shot);
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
		f.buffers = buffers.copy();
		f.capacity = capacity;
		filling = 1 - filling;
		device.inOrder(_ -> adopt(f));
	}

	public function dispose() {
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
		lock.release();
	}

	public function due():Float {
		lock.acquire();
		var f = shown, d = -1.0;
		if (f != null && (mirror.moving || moved(f))) {
			// (the program's to draw while it keeps the pace: it drained this vsync)
			// (asleep: it wakes for the input and draws it, unless it has not drained since)
			d = Math.max(drew + period * 0.5, turn ? drained + period * 0.6 : drained > routedAt ? drained + period * 0.6 : routedAt + period * 0.6);
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
		var f = shown;
		if (f == null || t - drained < period * 0.6 || !turn && drained > routedAt && t - routedAt < period * 0.6) {
			lock.release();
			return;
		}
		if (t - stepped > period / 2) {
			mirror.step(Ui.now());
			stepped = t;
		}
		var changed = offsetsNow(f);
		if (!changed) {
			drew = t;
			lock.release();
			return;
		}
		for (i in 0...now.length)
			shownAt[i] = now[i];
		lock.release();
		draw(r, f, null);
		var at = haxe.Timer.stamp(), d = at - drew;
		if (d > 0.002 && d < period * 1.5) period = period * 0.9 + d * 0.1;
		drew = at;
		drewSince = true;
		count++;
		if (onFrame != null) onFrame(drew);
	}

	// (the mirror's offsets of f's scrollers into now: whether they differ from those shown)
	function offsetsNow(f:CompositeFrame):Bool {
		now.resize(0);
		var changed = false;
		for (i in 0...f.nodes.length) {
			var o = mirror.offsets(f.nodes[i]);
			var x = o == null ? f.offsets[2 * i] : o.x, y = o == null ? f.offsets[2 * i + 1] : o.y;
			now.push(x);
			now.push(y);
			if (x != shownAt[2 * i] || y != shownAt[2 * i + 1]) changed = true;
		}
		return changed;
	}

	// a frame drawn at the mirror's offsets now, from the program's last,
	// its pixels read into capture before it is presented (a test's,
	// synchronously: the device's own thread)
	@:noCompletion public function drawNow(capture:haxe.io.Bytes) {
		device.inOrder(r -> {
			var f = shown;
			if (f == null) return;
			offsetsNow(f);
			draw(r, f, capture);
		});
		device.settle();
	}

	// (f's quads at the offsets now, drawn whole and presented)
	function draw(r:Replay, f:CompositeFrame, capture:Null<haxe.io.Bytes>) {
		if (f.buffers.length == 0 || r.impl.width != f.width || r.impl.height != f.height) return;
		var need = f.quads() * CompositeFrame.STRIDE;
		if (out.length < need) out = Bytes.alloc(need * 2);
		var n = f.compose(now, out, runTextures, runs);
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
		c.float((bg >> 16 & 0xFF) / 255);
		c.float((bg >> 8 & 0xFF) / 255);
		c.float((bg & 0xFF) / 255);
		c.float(1);
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
#end
