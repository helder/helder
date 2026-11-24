package helder.jobs;

import hxmc.I64;
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
// Between runs the threads spin a while (in their safe regions) before they
// sleep, so that a frame's many short runs (a pass's tiles each) find them
// awake. Without threads (WebAssembly, Jobs.workers = 0), or while another
// run is on its way, the caller makes every call itself.
@:hxmc.unsafe(gc)
class Parallel {
	// (the run: its generation and next i in one word, so that a thread late
	// for a run takes nothing of the next; f, ctx, count, the calls done)
	static inline var NEXT = 0;
	static inline var F = 8;
	static inline var CTX = 16;
	static inline var COUNT = 24;
	static inline var DONE = 28;
	static inline var BUSY = 32;
	// (each thread's word: 1 while it sleeps)
	static inline var SLEEPS = 64;
	static inline var MAX = 256;
	// (how long a thread spins for the next run before it sleeps)
	static inline var SPIN = 200000;

	static var run_ = Ptr.nil();
	static var generation = 0;
	#if (hxmc.target != "wasm32-wasi")
	static final wakes:Array<sys.thread.Lock> = [];
	#end

	// the threads beside the caller's (at most most, when >= 0)
	public static function threads(most = -1):Int {
		#if (hxmc.target == "wasm32-wasi")
		return 0;
		#else
		var n = Jobs.workers == 0 ? 0 : Jobs.size();
		if (n > MAX) n = MAX;
		return most >= 0 && most < n ? most : n;
		#end
	}

	// f(ctx, i) for each i of 0...count, on up to most threads beside this one
	public static function run(f:Ptr, ctx:Ptr, count:Int, most = -1) {
		if (count <= 0) return;
		if (run_.isNull()) {
			run_ = LibC.malloc(SLEEPS + 4 * MAX);
			Mem.zero(run_, SLEEPS + 4 * MAX);
		}
		var r = run_;
		var helpers = threads(most);
		if (helpers <= 0 || count == 1 || Atomic.cas32(r.add(BUSY), 0, 1) != 0) {
			for (i in 0...count)
				Call.call(f, ctx, i);
			return;
		}
		#if (hxmc.target != "wasm32-wasi")
		while (wakes.length < helpers) {
			var k = wakes.length, wake = new sys.thread.Lock();
			wakes.push(wake);
			sys.thread.Thread.create(() -> serve(k, wake));
		}
		Mem.setPtr(r, F, f);
		Mem.setPtr(r, CTX, ctx);
		Mem.setI32(r, COUNT, count);
		Atomic.store32(r.add(DONE), 0);
		var g = ++generation;
		Atomic.store64(r.add(NEXT), word(g, 0));
		for (k in 0...wakes.length)
			if (Atomic.load32(r.add(SLEEPS + 4 * k)) != 0) wakes[k].release();
		var region = Blocking.enter();
		work(r, g);
		while (Atomic.load32(r.add(DONE)) < count) {}
		Blocking.leave(region);
		#end
		Atomic.store32(r.add(BUSY), 0);
	}

	static inline function word(g:Int, i:Int):I64
		return ((g : I64) << 32) | (i : I64);

	// (the run's calls left, while its generation stands: each claimed, made, counted)
	static function work(r:Ptr, g:Int) {
		var f = Mem.getPtr(r, F), ctx = Mem.getPtr(r, CTX), count = Mem.getI32(r, COUNT);
		while (true) {
			var v = Atomic.load64(r.add(NEXT));
			var i = (v & 0x7FFFFFFF).toInt();
			if ((v >> 32).toInt() != g || i >= count) return;
			if (Atomic.cas64(r.add(NEXT), v, word(g, i + 1)) != v) continue;
			Call.call(f, ctx, i);
			Atomic.add32(r.add(DONE), 1);
		}
	}

	#if (hxmc.target != "wasm32-wasi")
	static function serve(k:Int, wake:sys.thread.Lock) {
		var r = run_, seen = 0;
		while (true) {
			var region = Blocking.enter(), g = seen, spins = 0;
			while (g == seen && spins < SPIN) {
				g = (Atomic.load64(r.add(NEXT)) >> 32).toInt();
				spins++;
			}
			if (g != seen) {
				seen = g;
				work(r, g);
				Blocking.leave(region);
				continue;
			}
			// (asleep: said first, then looked again, so that a run begun meanwhile is not missed)
			Atomic.store32(r.add(SLEEPS + 4 * k), 1);
			g = (Atomic.load64(r.add(NEXT)) >> 32).toInt();
			Blocking.leave(region);
			if (g == seen) wake.wait();
			Atomic.store32(r.add(SLEEPS + 4 * k), 0);
		}
	}
	#end
}

// (a GC-free callback by its address, in the caller's safe region)
@:hxmc.c @:hxmc.fast private extern class Call {
	@:hxmc.indirect static function call(f:Ptr, ctx:Ptr, i:Int):Int;
}
