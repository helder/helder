package helder.parallel;

// Where a body runs (each, map, the reductions and a kernel's run take it
// last; HELDER_PARALLEL=scalar|simd|jobs|gpu forces every call):
//
//   Auto    the default: Simd or Jobs, by the site's own timings (the same
//           bits either way); Gpu only where the data already is (the next
//           part)
//   Scalar  one item at a time, Haxe's Floats (doubles), rounded where
//           stored: the reference
//   Simd    4 items a turn on this thread (float32 lanes)
//   Jobs    Simd's chunks on helder.jobs' threads and this one; this
//           thread alone where there are none (a browser's wasm32)
//   Gpu     a compute dispatch, approximate (not yet: it throws)
enum abstract On(Int) {
	var Auto;
	var Scalar;
	var Simd;
	var Jobs;
	var Gpu;

	public function toString():String
		return switch (cast this : On) {
			case Auto: "auto";
			case Scalar: "scalar";
			case Simd: "simd";
			case Jobs: "jobs";
			case Gpu: "gpu";
		}
}
