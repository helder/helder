package helder.gfx;

#if (hxmc.target != "wasm32-wasi")
import hxmc.unsafe.*;
import sys.thread.Lock;
import sys.thread.Thread;

// The thread that owns the GPU's context and executes the devices'
// command buffers (Replay), one at a time, in order, presenting their
// frames; one per process, started by the first device that asks for it,
// ended by the last one's dispose once it drained. The program hands it a
// buffer and goes on recording the next (Device: two of them); it waits
// only to hand over another while the last is still running, and at its
// sync points. A GC thread that waits in a safe region (Lock.wait) and
// whose back ends wait for vsync and the GPU in theirs (present,
// nextDrawable, swap), so that collections wait only for its stretches
// of encoding between them. Between the buffers it runs the devices' idle
// work (RenderIdle: helder.ui's compositor) when it is due or woken.
@:noCompletion @:hxmc.unsafe(gc)
final class RenderThread {
	static var shared:Null<RenderThread> = null;
	static var users = 0;

	final ready = new Lock();
	final done = new Lock();
	var replay:Null<Replay> = null;
	var work:Null<Commands> = null;
	var busy = false;
	var stop = false;
	// (buffers handed over, run: a wake without one runs only the idle work)
	var submitted = 0;
	var taken = 0;
	final idles:Array<RenderIdle> = [];
	final idleReplays:Array<Replay> = [];
	final idleLock = new sys.thread.Mutex();
	// (Apple: the autorelease pool around what runs outside a frame; a frame's own is the back end's)
	var pool = Ptr.nil();
	// (Windows: the system's timer at 1 ms while idle work is due)
	var fine = false;

	function new() {}

	public static function acquire():RenderThread {
		var t = shared;
		if (t == null) {
			var made = new RenderThread();
			Thread.create(() -> made.loop());
			shared = t = made;
		}
		users++;
		return t;
	}

	// (a device let go of it: the last one ends it, after what it was given)
	public function release() {
		wait();
		if (--users > 0) return;
		shared = null;
		var threads = hxmc.NativeThread.count();
		stop = true;
		ready.release();
		done.wait();
		// (its last instructions, before a build swapped out under hxmc dev is unloaded)
		var waited = 0;
		while (hxmc.NativeThread.count() >= threads && waited++ < 200)
			Sys.sleep(0.001);
	}

	// c handed over to be run by r after what it was given before; c's
	// owner records into another meanwhile, and clears c once wait returned
	public function submit(r:Replay, c:Commands) {
		wait();
		idleLock.acquire();
		replay = r;
		work = c;
		submitted++;
		idleLock.release();
		busy = true;
		ready.release();
	}

	// until what it was given has run
	public function wait() {
		if (!busy) return;
		done.wait();
		busy = false;
		replay = null;
		work = null;
	}

	// whether what it was given has run (not waiting)
	public function poll():Bool {
		if (!busy) return true;
		if (!done.wait(0)) return false;
		busy = false;
		replay = null;
		work = null;
		return true;
	}

	public function addIdle(i:RenderIdle, r:Replay) {
		idleLock.acquire();
		idles.push(i);
		idleReplays.push(r);
		idleLock.release();
		ready.release();
	}

	public function removeIdle(i:RenderIdle) {
		idleLock.acquire();
		var k = idles.indexOf(i);
		if (k >= 0) {
			idles.splice(k, 1);
			idleReplays.splice(k, 1);
		}
		idleLock.release();
	}

	// (from any thread)
	public function wake()
		ready.release();

	function loop() {
		while (true) {
			var due = nextDue();
			tick(due >= 0);
			if (due < 0) ready.wait() else ready.wait(Math.max(0, due - haxe.Timer.stamp()));
			if (stop) {
				tick(false);
				drain();
				done.release();
				return;
			}
			idleLock.acquire();
			var r = taken != submitted ? replay : null, c = work;
			taken = submitted;
			idleLock.release();
			if (r != null) runWork(r, c);
			runIdles();
		}
	}

	// (the idle work's earliest due time, -1: none)
	function nextDue():Float {
		var at = -1.0;
		idleLock.acquire();
		for (i in idles) {
			var d = i.due();
			if (d >= 0 && (at < 0 || d < at)) at = d;
		}
		idleLock.release();
		return at;
	}

	function runIdles() {
		idleLock.acquire();
		var list = idles.copy(), replays = idleReplays.copy();
		idleLock.release();
		var now = haxe.Timer.stamp(), ran = false;
		for (k in 0...list.length) {
			var d = list[k].due();
			if (d < 0 || d > now) continue;
			pooled();
			list[k].idle(replays[k]);
			ran = true;
		}
		// (what it left in the pool let go, outside a frame)
		if (!ran) return;
		for (r in replays)
			if (r.began) return;
		drain();
	}

	// (the program's buffer run)
	function runWork(r:Replay, c:Commands) {
		pooled();
		r.run(c, false);
		// (a pool popped outside a frame only: the frame's, the back end's, is inside it)
		if (!r.began) drain();
		done.release();
	}

	// (Windows: a timed wait ends on the system's tick, 15.6 ms; the
	// compositor's waits of part of a period (the program's turn after
	// input, the layers' next composition) then end a vblank late, its
	// frames locked at half the display's rate. 1 ms while something moves
	// only, for the power it costs)
	function tick(on:Bool) {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (on == fine) return;
		fine = on;
		if (on) Winmm.timeBeginPeriod(1) else Winmm.timeEndPeriod(1);
		#end
	}

	// (Apple: the autorelease pool around what runs outside a frame)
	inline function pooled() {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		if (pool.isNull()) pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		#end
	}

	function drain() {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		if (!pool.isNull()) {
			helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
			pool = Ptr.nil();
		}
		#end
	}
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("winmm") extern class Winmm {
	static function timeBeginPeriod(ms:Int):Int;
	static function timeEndPeriod(ms:Int):Int;
}
#end
#end
