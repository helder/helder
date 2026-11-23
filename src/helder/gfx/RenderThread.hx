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
// of encoding between them.
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
	// (Apple: the autorelease pool around what runs outside a frame; a frame's own is the back end's)
	var pool = Ptr.nil();

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
		replay = r;
		work = c;
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

	function loop() {
		while (true) {
			ready.wait();
			if (stop) {
				drain();
				done.release();
				return;
			}
			var r = replay, c = work;
			#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			if (pool.isNull()) pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
			#end
			r.run(c, false);
			// (a pool popped outside a frame only: the frame's, the back end's, is inside it)
			if (!r.began) drain();
			done.release();
		}
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
#end
