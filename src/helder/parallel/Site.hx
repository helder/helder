package helder.parallel;

#if !macro
// A call site's choice (each one a Site of its generated class): the form
// On asks for, or HELDER_PARALLEL's; Auto picks between Simd and Jobs by
// the site's own timings (which give the same bits, so the choice never
// changes a result): its first run on one thread, then, where it might
// win, one on the threads, and from then on the one predicted faster for
// the call's n (a nanoseconds-an-item estimate of each, kept up to date by
// a timed run now and then), changing only for a clear gain, so that a
// site does not flip from frame to frame. Gpu only from where the data is:
// an Items the body writes last written by a dispatch, or drawn by the GPU
// (Items.buffer), where Parallel.device has compute; never from timings.
@:noCompletion
class Site {
	// (a change of form needs this much predicted gain)
	static inline var MARGIN = 0.8;

	public final name:String;
	// whether the site has a Gpu form (each, map, a kernel: not a reduction yet)
	public final hasGpu:Bool;
	// whether the run picked is timed (took(...) after it)
	public var timing(default, null) = false;

	var simd = -1.0;
	var jobs = -1.0;
	var last = On.Auto;
	var runs = 0;

	public function new(name:String, hasGpu = false) {
		this.name = name;
		this.hasGpu = hasGpu;
	}

	// (resident: an Items the body writes is the GPU's alone, or drawn by it;
	// gpu: the site has a Gpu form and Parallel.device has compute)
	public function pick(on:On, n:Int, resident = false, gpu = false):On {
		var forced = Parallel.forced();
		var form = forced != On.Auto ? forced : on != On.Auto ? on : resident && gpu ? On.Gpu : auto(n);
		if (form == On.Gpu && !gpu)
			throw new haxe.Exception('helder.parallel: $name: On.Gpu: ' + (!hasGpu ? "no Gpu form (a reduction's comes with workgroup memory)" : "no Parallel.device with compute stages"));
		runs++;
		timing = form != On.Gpu && on == On.Auto && forced == On.Auto && (runs <= 16 || runs % 64 == 0);
		if (form != last) {
			if (Parallel.log) Sys.println('helder.parallel: $name: ${form.toString()} (n $n' + (simd < 0 ? "" : ', simd ${ns(simd)} ns an item') + (jobs < 0 ? "" : ', jobs ${ns(jobs)}') + ")");
			last = form;
		}
		return form;
	}

	static function ns(x:Float):Float
		return Math.round(x * 1000) / 1000;

	function auto(n:Int):On {
		var threads = helder.jobs.Spread.threads();
		if (threads == 0 || simd < 0) return On.Simd;
		var one = simd * n;
		// (one thread's work under the threads' fixed cost: never worth them)
		if (one < Parallel.jobsCost() * 2) return On.Simd;
		var many = Parallel.jobsCost() + (jobs >= 0 ? jobs : simd / (threads + 1) * 1.5) * n;
		if (jobs < 0) return many < one ? On.Jobs : On.Simd;
		return switch last {
			case On.Jobs: one < many * MARGIN ? On.Simd : On.Jobs;
			case _: many < one * MARGIN ? On.Jobs : On.Simd;
		}
	}

	// a timed run of form over n items: seconds
	public function took(form:On, n:Int, seconds:Float) {
		var each = seconds * 1e9 / n;
		switch form {
			case On.Simd: simd = simd < 0 ? each : Math.min(each, 0.7 * simd + 0.3 * each);
			case On.Jobs:
				var past = Math.max(0, seconds * 1e9 - Parallel.jobsCost()) / n;
				jobs = jobs < 0 ? past : Math.min(past, 0.7 * jobs + 0.3 * past);
			case _:
		}
	}
}
#end
