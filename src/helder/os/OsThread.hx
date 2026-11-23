package helder.os;

import hxmc.NativeThread;
import hxmc.Platform;
import sys.thread.Lock;
import sys.thread.Mutex;

// The main thread and the program's. App.run on macOS and Linux runs the
// program's loop on a thread of its own, as on Android, so that the main
// thread, where AppKit has to be called, can read the system's input while
// the program is busy (the compositor's scrolling, Layers' step 4b). The
// main thread runs what the program's thread hands it (run) and waits
// otherwise; what the system calls back from there into the program (an
// event, a live resize's frame) is handed back (back). Whichever side
// waits for the other runs what the other hands it meanwhile, so calls nest
// both ways without a deadlock and only one of the two runs at a time: the
// program's state and the system's objects are touched as on one thread.
// HELDER_THREAD=0 keeps the program on the main thread.
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
		return (Platform.os() == 1 && Platform.apple() < 1) || (Platform.os() == 0 && Platform.target() < 9);
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

	// f's value, on the main thread (as run)
	public static function get<T>(f:Void->T):T {
		if (program == 0 || NativeThread.current() != program) return f();
		var v:Null<T> = null;
		run(() -> v = f());
		return cast v;
	}

	// f on the program's thread, from the main thread (at once from any other)
	public static function back(f:Void->Void) {
		if (program == 0 || NativeThread.current() != 1) {
			f();
			return;
		}
		call(f, toProgram, programWake, toMain, mainWake);
	}

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
			mutex.release();
			mainWake.release();
		});
		started.wait();
		while (true) {
			drain(toMain);
			mutex.acquire();
			var done = ended;
			mutex.release();
			if (done) break;
			mainWake.wait();
		}
		program = 0;
		helder.async.Driven.MainLoop.program = 0;
		if (failure != null) throw failure;
	}

	static function call(f:Void->Void, to:Array<Call>, wake:Lock, mine:Array<Call>, myWake:Lock) {
		var c = new Call(f, myWake);
		mutex.acquire();
		to.push(c);
		mutex.release();
		wake.release();
		while (true) {
			drain(mine);
			mutex.acquire();
			var done = c.done;
			mutex.release();
			if (done) break;
			myWake.wait();
		}
		if (c.error != null) throw c.error;
	}

	static function drain(inbox:Array<Call>) {
		while (true) {
			mutex.acquire();
			var c = inbox.shift();
			mutex.release();
			if (c == null) return;
			try c.f() catch (e:haxe.Exception) c.error = e;
			mutex.acquire();
			c.done = true;
			mutex.release();
			c.wake.release();
		}
	}
}

private class Call {
	public final f:Void->Void;
	public final wake:Lock;
	public var done = false;
	public var error:Null<haxe.Exception> = null;

	public function new(f, wake) {
		this.f = f;
		this.wake = wake;
	}
}
