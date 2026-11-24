package helder.jobs;

import hxmc.unsafe.Atomic;
import hxmc.unsafe.Blocking;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// GC-free work split over threads and waited for, the synchronous tier
// beside jobs: count calls of f(ctx, i), a GC-free callback
//
//   @:hxmc.callback @:hxmc.unsafe static function tile(ctx:Ptr, i:Int):Int
//
// on threads of their own (as many as the pool has: Jobs.workers) and the
// caller's, each taking the next i until none is left, all in safe regions
// (hxmc.unsafe.Blocking): they read and write memory outside the collector's
// heap only, shared between them without copies (the CPU back end's tiles:
// helder.gfx.soft), so other threads' collections never wait for them.
// Without threads (WebAssembly, Jobs.workers = 0), or while another run is
// on its way, the caller makes every call itself.
@:hxmc.unsafe(gc)
class Parallel {
	// (the run: f, ctx, count, the next i)
	static inline var F = 0;
	static inline var CTX = 8;
	static inline var COUNT = 16;
	static inline var NEXT = 20;
	static inline var BUSY = 24;

	static var run_ = Ptr.nil();
	#if (hxmc.target != "wasm32-wasi")
	static final wakes:Array<sys.thread.Lock> = [];
	static final done = new sys.thread.Lock();
	#end

	// the threads beside the caller's (at most most, when >= 0)
	public static function threads(most = -1):Int {
		#if (hxmc.target == "wasm32-wasi")
		return 0;
		#else
		var n = Jobs.workers == 0 ? 0 : Jobs.size();
		return most >= 0 && most < n ? most : n;
		#end
	}

	// f(ctx, i) for each i of 0...count, on up to most threads beside this one
	public static function run(f:Ptr, ctx:Ptr, count:Int, most = -1) {
		if (count <= 0) return;
		if (run_.isNull()) {
			run_ = LibC.malloc(32);
			Mem.zero(run_, 32);
		}
		var r = run_;
		var helpers = count - 1 < threads(most) ? count - 1 : threads(most);
		if (helpers <= 0 || Atomic.cas32(r.add(BUSY), 0, 1) != 0) {
			for (i in 0...count)
				Call.call(f, ctx, i);
			return;
		}
		Mem.setPtr(r, F, f);
		Mem.setPtr(r, CTX, ctx);
		Mem.setI32(r, COUNT, count);
		Atomic.store32(r.add(NEXT), 0);
		#if (hxmc.target != "wasm32-wasi")
		while (wakes.length < helpers) {
			var wake = new sys.thread.Lock();
			wakes.push(wake);
			sys.thread.Thread.create(() -> serve(wake));
		}
		for (k in 0...helpers)
			wakes[k].release();
		var region = Blocking.enter();
		work(r);
		Blocking.leave(region);
		for (_ in 0...helpers)
			done.wait();
		#end
		Atomic.store32(r.add(BUSY), 0);
	}

	// (the calls left, one after another)
	static function work(r:Ptr) {
		var f = Mem.getPtr(r, F), ctx = Mem.getPtr(r, CTX), count = Mem.getI32(r, COUNT);
		while (true) {
			var i = Atomic.add32(r.add(NEXT), 1);
			if (i >= count) break;
			Call.call(f, ctx, i);
		}
	}

	#if (hxmc.target != "wasm32-wasi")
	static function serve(wake:sys.thread.Lock)
		while (true) {
			wake.wait();
			var r = run_, region = Blocking.enter();
			work(r);
			Blocking.leave(region);
			done.release();
		}
	#end
}

// (a GC-free callback by its address, in the caller's safe region)
@:hxmc.c @:hxmc.fast private extern class Call {
	@:hxmc.indirect static function call(f:Ptr, ctx:Ptr, i:Int):Int;
}
