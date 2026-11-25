package helder.os;

import hxmc.NativeThread;
import hxmc.Platform;
import sys.thread.Lock;
import sys.thread.Mutex;

// The main thread and the program's. App.run on macOS, iOS, Windows and Linux runs the
// program's loop on a thread of its own, as on Android, so that the main
// thread, where AppKit has to be called, can read the system's input while
// the program is busy (the compositor's scrolling, Layers' step 4b). The
// main thread runs what the program's thread hands it (run) and waits
// otherwise; what the system calls back from there into the program (an
// event, a live resize's frame) is handed back (back). Whichever side
// waits for the other runs what the other hands it meanwhile, so calls nest
// both ways without a deadlock and only one of the two runs at a time: the
// program's state and the system's objects are touched as on one thread.
// The calls are handed over inside the macOS classes (CocoaWindow, MacViews,
// ...), not around their run-time Platform branches: a closure there is
// compiled on every target, and would link AppKit into Linux's and
// Windows' builds. While the program runs on, the main thread may read the
// system's input (waitMain: the compositor's, helder.ui.draw.Compositor),
// woken by a call handed to it (wakeMain); the events are the program's
// at its next poll, as before. A system's callback that comes meanwhile
// and needs no answer (iOS's touches, a UIScrollView's offset) waits for
// the program's next call (soon), so that the main thread never waits for
// a busy program. HELDER_THREAD=0 keeps the program on the main thread.
@:hxmc.unsafe(gc)
class OsThread {
	// the program's thread's Haxe id; 0 while the program runs on the main thread
	public static var program(default, null) = 0;

	static final mutex = new Mutex();
	static final toMain:Array<Call> = [];
	static final toProgram:Array<Call> = [];
	static final mainWake = new Lock();
	static final programWake = new Lock();
	static var ended = false;
	// (the main thread in waitMain: a call handed to it wakes it with wakeMain)
	static var waiting = false;

	// the main thread's wait while the program runs on (the platform's:
	// CocoaWindow reads the input meanwhile, for the compositor; false: not
	// now, it waits on its lock), and what wakes it from the program's
	// thread when a call is handed over
	@:noCompletion public static var waitMain:Null<Void->Bool> = null;
	@:noCompletion public static var wakeMain:Null<Void->Void> = null;

	// what a thread lets go of as the program leaves it (the main thread's
	// before the program's starts, the program's at its end): what is bound
	// to a thread, as a GL context current on it (helder.gfx's GL back end)
	public static final leaving:Array<Void->Void> = [];

	// whether App.run gives the program a thread of its own
	public static function wanted():Bool {
		#if (helder.headless || hxmc.target == "wasm32-wasi")
		return false;
		#else
		if (Sys.getEnv("HELDER_THREAD") == "0") return false;
		return Platform.os() == 1 || Platform.os() == 2 || (Platform.os() == 0 && Platform.target() < 9);
		#end
	}

	// f on the main thread, from the program's (at once from any other)
	public static function run(f:Void->Void) {
		if (program == 0 || NativeThread.current() != program) {
			f();
			return;
		}
		call(f, toMain, mainWake, toProgram, programWake);
	}

	// f on the main thread soon, from any thread, nothing waited for (the
	// compositor's, from the render thread: a native view moved with its
	// frame); at once without a program's thread
	public static function post(f:Void->Void) {
		if (program == 0) {
			f();
			return;
		}
		mutex.acquire();
		toMain.push(new Call(f, null));
		var w = waiting;
		mutex.release();
		mainWake.release();
		if (w && wakeMain != null) wakeMain();
	}

	// f's value, on the main thread (as run)
	public static function get<T>(f:Void->T):T {
		if (program == 0 || NativeThread.current() != program) return f();
		var v:Null<T> = null;
		run(() -> v = f());
		return cast v;
	}

	// f where the program's state may be touched, from the main thread: at
	// once while the program waits for it (a call of its own, as on one
	// thread), on the program's thread while the main thread reads input on
	// its own (waitMain): a system's callback (accessibility, a native
	// view's delegate) reading or changing what the program has
	public static function hold<T>(f:Void->T):T {
		if (!reading()) return f();
		var v:Null<T> = null;
		back(() -> v = f());
		return cast v;
	}

	public static function holdVoid(f:Void->Void)
		if (reading()) back(f) else f();

	// f where the program's state may be touched, from the main thread,
	// nothing waited for: at once while the program waits for it, else on
	// the main thread before the program's next call to it runs, in order
	public static function soon(f:Void->Void) {
		if (!reading()) {
			f();
			return;
		}
		mutex.acquire();
		later.push(f);
		mutex.release();
	}

	static final later:Array<Void->Void> = [];

	// (the main thread reading input on its own, the program running on)
	static function reading():Bool {
		if (program == 0 || NativeThread.current() != 1) return false;
		mutex.acquire();
		var w = waiting;
		mutex.release();
		return w;
	}

	// f on the program's thread, from the main thread (at once from any other)
	public static function back(f:Void->Void) {
		if (program == 0 || NativeThread.current() != 1) {
			f();
			return;
		}
		nest++;
		try
			call(f, toProgram, programWake, toMain, mainWake)
		catch (e:haxe.Exception) {
			nest--;
			throw e;
		}
		nest--;
	}

	// f on the program's thread, from the main thread, as back, waited for
	// seconds at most (what the program hands the main thread meanwhile run):
	// whether it ran by then. Else it runs when the program comes to it, an
	// error of it thrown there, and the next call waits for it in place of
	// its own (a live resize's frame: AppKit waits for no busy program, and
	// one frame at a time is asked of it, not one each time it is slow)
	public static function within(f:Void->Void, seconds:Float):Bool {
		if (program == 0 || NativeThread.current() != 1) {
			f();
			return true;
		}
		var until = haxe.Timer.stamp() + seconds;
		mutex.acquire();
		var c = behind != null && !behind.done ? behind : null;
		if (c != null) c.left = false;
		behind = null;
		mutex.release();
		if (c == null) {
			c = new Call(f, mainWake);
			mutex.acquire();
			toProgram.push(c);
			mutex.release();
			programWake.release();
		}
		nest++;
		while (true) {
			try drain(toMain) catch (e:haxe.Exception) {
				nest--;
				throw e;
			}
			mutex.acquire();
			var done = c.done, left = until - haxe.Timer.stamp();
			if (!done && left <= 0) {
				c.left = true;
				behind = c;
			}
			mutex.release();
			if (done) break;
			if (left <= 0) {
				nest--;
				return false;
			}
			// (in short waits: one timed wait of 0.1 s woke up to 0.1 s late on
			// CI's macOS VMs, 2 ms ones a few ms at most)
			mainWake.wait(Math.min(left, 0.002));
		}
		nest--;
		if (c.error != null) throw c.error;
		return true;
	}

	// (within's call given up on, not run yet)
	static var behind:Null<Call> = null;

	// whether the main thread serves the program from inside a call of its
	// own to it (back: a system's callout, a run loop source's, under it):
	// an autorelease pool pushed outside that callout is not popped there
	@:noCompletion public static function nested():Bool
		return nest > 0;

	static var nest = 0;

	// loop on a thread of its own while the main thread serves it, until it returns
	public static function start(loop:Void->Void) {
		var failure:Null<haxe.Exception> = null;
		var started = new Lock();
		ended = false;
		for (f in leaving)
			f();
		sys.thread.Thread.create(() -> {
			program = NativeThread.current();
			helder.async.Driven.MainLoop.program = program;
			started.release();
			try loop() catch (e:haxe.Exception) failure = e;
			for (f in leaving)
				f();
			mutex.acquire();
			ended = true;
			var w = waiting;
			mutex.release();
			mainWake.release();
			if (w && wakeMain != null) wakeMain();
		});
		started.wait();
		while (true) {
			drain(toMain);
			mutex.acquire();
			var done = ended, calls = toMain.length > 0, pump = !done && !calls && waitMain != null;
			waiting = pump;
			mutex.release();
			if (done) break;
			if (calls) continue;
			if (pump) {
				var read = waitMain();
				mutex.acquire();
				waiting = false;
				mutex.release();
				if (read) continue;
			}
			mainWake.wait();
		}
		program = 0;
		helder.async.Driven.MainLoop.program = 0;
		if (failure != null) throw failure;
	}

	// (a frame's handoffs allocate nothing: their Calls are reused)
	static final spare:Array<Call> = [];

	static function call(f:Void->Void, to:Array<Call>, wake:Lock, mine:Array<Call>, myWake:Lock) {
		mutex.acquire();
		var c = spare.pop();
		if (c == null) c = new Call(f, myWake) else c.reuse(f, myWake);
		to.push(c);
		var w = to == toMain && waiting;
		mutex.release();
		wake.release();
		if (w && wakeMain != null) wakeMain();
		while (true) {
			drain(mine);
			mutex.acquire();
			var done = c.done;
			mutex.release();
			if (done) break;
			myWake.wait();
		}
		var error = c.error;
		c.reuse(null, null);
		mutex.acquire();
		spare.push(c);
		mutex.release();
		if (error != null) throw error;
	}

	static function drain(inbox:Array<Call>) {
		while (true) {
			mutex.acquire();
			var c = inbox.shift();
			// (the program waits for this call: what came for it meanwhile first)
			var soon = c != null && c.wake != null && inbox == toMain && later.length > 0 ? later.splice(0, later.length) : null;
			mutex.release();
			if (c == null) return;
			// (an error of one of those: the program's call's to throw)
			var failed:Null<haxe.Exception> = null;
			if (soon != null)
				for (f in soon)
					try f() catch (e:haxe.Exception) if (failed == null) failed = e;
			try c.f() catch (e:haxe.Exception) c.error = e;
			if (failed != null && c.error == null) c.error = failed;
			mutex.acquire();
			c.done = true;
			// (read before the waiter, seeing it done, reuses it)
			var left = c.left, wake = c.wake, error = c.error;
			mutex.release();
			if (wake != null) wake.release();
			// (no one waits for it any more: its error is this thread's)
			if (left && error != null) throw error;
		}
	}
}

private class Call {
	public var f:Null<Void->Void>;
	public var wake:Null<Lock>;
	public var done = false;
	// (within's, given up on: no one waits for it)
	public var left = false;
	public var error:Null<haxe.Exception> = null;

	public function new(f, wake) {
		this.f = f;
		this.wake = wake;
	}

	public function reuse(f, wake) {
		this.f = f;
		this.wake = wake;
		done = left = false;
		error = null;
	}
}
