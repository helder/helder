package helder.test;

// A robustness property's watchdog (natively): a thread that ends the
// process when a case runs past its limit or grows the process past its
// budget, neither of which the case's own thread can stop or catch. The
// case is already on disk (Property keeps it before it runs): the next
// run replays it first. Eval and wasm32-wasi have no watchdog.
//
// Memory is each case's: its footprint against its own start, the
// collector's garbage of the cases before taken out by a full collection
// when it has drifted half the budget (a soak's 940,000 cases tripped a
// budget against the property's start, a collection giving back all but
// 40 KB). The watchdog's reading during a case is its peak (a blow-up:
// 1.7 GB in one glyph); after it, what it kept once collected (a leak).
class Guard {
	static var since = -1.0;
	static var limit = 0.0;
	static var budget = 0.0;
	// (the case's start, and the footprint when last collected)
	static var base = -1.0;
	static var floor = 0.0;
	static var over:Null<String->Void>;
	static var running = false;

	// (watched from now: each case between enter and leave)
	public static function watch(seconds:Float, mb:Float, report:String->Void) {
		limit = seconds;
		budget = mb;
		base = -1;
		if (budget > 0) floor = collected();
		over = report;
		#if (helder.os && helder.os != "web" && !eval)
		if (!running) {
			running = true;
			sys.thread.Thread.create(loop);
		}
		#end
	}

	public static function stop() {
		since = -1;
		base = -1;
		over = null;
	}

	public static function enter() {
		if (budget > 0) {
			var m = resident();
			if (m >= 0 && m - floor > budget / 2) m = floor = collected();
			base = m;
		}
		since = haxe.Timer.stamp();
	}

	// (the case's end: what it kept, once collected, within the budget)
	public static function leave() {
		since = -1;
		var b = base, f = over;
		base = -1;
		if (b < 0 || f == null || resident() - b <= budget) return;
		var m = collected();
		floor = m;
		if (m - b > budget) f('a case kept ${Math.round(m - b)} MB after a full collection (the footprint against its start), over $budget MB');
	}

	static function loop()
		while (true) {
			Sys.sleep(0.05);
			var f = over, s = since, b = base;
			if (f == null || s < 0) continue;
			if (haxe.Timer.stamp() - s > limit) f('a case ran over $limit s: hung');
			var m = b >= 0 ? resident() : -1;
			if (m >= 0 && m - b > budget) f('the footprint rose ${Math.round(m - b)} MB during a case (against its start, its garbage included), over $budget MB');
		}

	// (resident memory after a full collection)
	static function collected():Float {
		#if (target.name == "hxmc")
		hxmc.NativeGc.collect(true);
		#end
		return resident();
	}

	// the process's resident memory in MB, -1 where unknown
	public static function resident():Float {
		#if ((helder.os == "macos" || helder.os == "ios") && !eval)
		return Footprint.now() / 1048576;
		#elseif (helder.os == "linux" || helder.os == "android")
		try {
			for (line in sys.io.File.getContent("/proc/self/status").split("\n"))
				if (StringTools.startsWith(line, "VmRSS:")) return Std.parseFloat(StringTools.trim(line.substr(6)).split(" ")[0]) / 1024;
		} catch (e:Dynamic) {}
		return -1;
		#else
		return -1;
		#end
	}
}

#if ((helder.os == "macos" || helder.os == "ios") && !eval)
// (Apple's phys_footprint: rusage_info_v2's, after its uuid and seven counters;
// fast as every other getpid's declaration: one declared both ways fails a build)
@:hxmc.c @:hxmc.fast private extern class Rusage {
	static function getpid():Int;
	static function proc_pid_rusage(pid:Int, flavor:Int, buffer:hxmc.unsafe.Ptr):Int;
}

private class Footprint {
	@:hxmc.unsafe(gc) public static function now():Float {
		var buf = hxmc.unsafe.IoBuffer.alloc(256);
		Rusage.proc_pid_rusage(Rusage.getpid(), 2, buf.ptr);
		var f:Float = cast hxmc.unsafe.Mem.getI64(buf.ptr, 72);
		buf.free();
		return f;
	}
}
#end
