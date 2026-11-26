package helder.test;

// A robustness property's watchdog (natively): a thread that ends the
// process when a case runs past its limit or the process grows past its
// budget, neither of which the case's own thread can stop or catch. The
// case is already on disk (Property keeps it before it runs): the next
// run replays it first. Eval and wasm32-wasi have no watchdog.
class Guard {
	static var since = -1.0;
	static var limit = 0.0;
	static var budget = 0.0;
	static var base = 0.0;
	static var over:Null<String->Void>;
	static var running = false;

	// (watched from now: each case between enter and leave)
	public static function watch(seconds:Float, mb:Float, report:String->Void) {
		limit = seconds;
		budget = mb;
		base = resident();
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
		over = null;
	}

	public static function enter()
		since = haxe.Timer.stamp();

	public static function leave()
		since = -1;

	static function loop()
		while (true) {
			Sys.sleep(0.05);
			var f = over, s = since;
			if (f == null || s < 0) continue;
			if (haxe.Timer.stamp() - s > limit) f('a case ran over $limit s: hung');
			var m = budget > 0 && base >= 0 ? resident() : -1;
			if (m >= 0 && m - base > budget) f('the process grew by ${Math.round(m - base)} MB in a case, over $budget MB');
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
// (Apple's phys_footprint: rusage_info_v2's, after its uuid and seven counters)
@:hxmc.c private extern class Rusage {
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
