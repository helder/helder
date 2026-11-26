import haxe.Timer;
import helder.parallel.Items;
import helder.parallel.ItemsData;
import helder.parallel.On;
import helder.parallel.Parallel;

// helder.parallel's reductions on the GPU (`bun run test bench reduce`):
// the sum of squares of N floats a dispatch wrote (the GPU's values), as
//
//   gpu        sum(n, ..., Gpu): the tree on the GPU, one value read back
//   read+simd  the values read back (an Items' read after a dispatch), then
//              sum(n, ..., Simd): what a reduction of them costs without
//              the Gpu form
//   read+jobs  the same, summed by Jobs
//   simd, jobs the values the CPU's already: the sum alone
//
// Each the least of its runs (a run: enough sums for 2 ms), in µs a sum.
// Metal and the CPU back end share an Items' memory: there a read back is
// the wait alone. PARALLEL_N="1000 5000" narrows a run.
class ReduceBench {
	static final SIZES = [1000, 10000, 100000, 1000000, 10000000];
	static final FORMS = ["gpu", "read+simd", "read+jobs", "simd", "jobs"];

	static function main() {
		var device = try helder.gfx.Device.create(helder.os.Surface.headless(64, 64)) catch (_:Dynamic) null;
		if (device == null || !device.has(Compute)) {
			Sys.println("reduce: no device with compute stages");
			Sys.exit(3);
		}
		Parallel.device = device;
		Sys.println('reduce: ${helder.jobs.Spread.threads() + 1} threads, gpu ${Std.string(device.backend)}');
		var given = Sys.getEnv("PARALLEL_N");
		var sizes = given == null ? SIZES : [for (x in given.split(" ")) if (x != "") Std.parseInt(x)];
		var rows = [];
		for (n in sizes) {
			var a = new Items<Float>(n);
			each(n, i -> a[i] = (i % 1000) * 0.001, Gpu);
			var g = sum(n, i -> a[i] * a[i], Gpu), c = sum(n, i -> a[i] * a[i], Simd);
			Sys.println('reduce $n: gpu $g, simd $c (${Math.abs(g - c) / Math.max(1, Math.abs(c))} apart)');
			var row = [Std.string(n)];
			for (f in FORMS) {
				var us = measure(f, a);
				Sys.println('reduce $n $f ${round(us)}');
				row.push(round(us));
			}
			rows.push(row);
			a.dispose();
		}
		Sys.println("");
		Sys.println("| N | " + FORMS.join(" | ") + " |");
		Sys.println("|" + [for (_ in 0...FORMS.length + 1) "---:"].join("|") + "|");
		for (r in rows)
			Sys.println("| " + r.join(" | ") + " |");
		device.dispose();
	}

	static var sink = 0.0;

	static function once(form:String, a:Items<Float>) {
		var n = a.length;
		switch form {
			case "gpu": sink += sum(n, i -> a[i] * a[i], Gpu);
			case "read+simd" | "read+jobs":
				// (the values the GPU's alone again, as after a dispatch)
				a.data().state = ItemsData.GPU;
				sink += sum(n, i -> a[i] * a[i], form == "read+simd" ? Simd : Jobs);
			case "simd": sink += sum(n, i -> a[i] * a[i], Simd);
			case _: sink += sum(n, i -> a[i] * a[i], Jobs);
		}
	}

	static function measure(form:String, a:Items<Float>):Float {
		var t0 = Timer.stamp();
		once(form, a);
		var one = Timer.stamp() - t0;
		var k = Std.int(Math.max(1, Math.min(10000, 0.002 / Math.max(one, 1e-7))));
		var best = 1e30;
		for (_ in 0...(one > 0.05 ? 3 : 10)) {
			var t = Timer.stamp();
			for (_ in 0...k)
				once(form, a);
			best = Math.min(best, (Timer.stamp() - t) / k * 1e6);
		}
		return best;
	}

	static function round(us:Float):String
		return us >= 100 ? Std.string(Math.round(us)) : Std.string(Math.round(us * 10) / 10);
}
