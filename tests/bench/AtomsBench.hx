import helder.view.graph.Graph.*;

// A signal's read and write, timed (helder.view.graph.Atoms: a value per
// store): in the default store as every program has it, and in a screen's
// store, a signal made there (its home) and a top-level one (another
// store's node, from the store's map). The least of RUNS (5), ns an op.
//   helder build tests/bench/AtomsBench.hx -o bin/bench/atoms && bin/bench/atoms
class AtomsBench {
	static final count = signal(0);
	static final double = memo(() -> count() * 2);

	static inline var READS = 10000000;
	static inline var WRITES = 200000;
	static inline var RUNS = 5;

	static function time(name:String, n:Int, f:Void->Void) {
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...RUNS) {
			var t = haxe.Timer.stamp();
			f();
			best = Math.min(best, haxe.Timer.stamp() - t);
		}
		Sys.println('$name: ${Math.round(best * 1e9 / n * 100) / 100} ns');
	}

	static function reads(s:helder.view.graph.Signal<Int>) {
		var sum = 0;
		for (_ in 0...READS)
			sum += s();
		if (sum < 0) Sys.println(sum);
	}

	static function writes(s:helder.view.graph.Signal<Int>) {
		for (i in 0...WRITES) {
			s(i + 1);
			flush();
		}
		s(0);
		flush();
	}

	static function main() {
		time("read, default store", READS, () -> reads(count));
		time("memo read, default store", READS, () -> {
			var sum = 0;
			for (_ in 0...READS)
				sum += double();
			if (sum < 0) Sys.println(sum);
		});
		time("write + flush, default store", WRITES, () -> writes(count));
		#if atoms
		var store = new helder.view.graph.Atoms("screen");
		var home = store.run(() -> signal(0));
		store.run(() -> {
			time("read, a screen's own signal", READS, () -> reads(home));
			time("read, a top-level signal in a screen", READS, () -> reads(count));
			time("write + flush, a top-level signal in a screen", WRITES, () -> writes(count));
		});
		#end
	}
}
