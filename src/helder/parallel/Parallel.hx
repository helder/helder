package helder.parallel;

#if macro
import haxe.macro.Expr;
#end

// One body over a range of items, run as SIMD lanes, across helder.jobs'
// threads, or one item at a time (README.md): import helder.parallel.Parallel.
//
//   each(n, i -> heights[i] = Math.sin(i * k));          // for each i of 0...n
//   map(speed, i -> length(vel[i]));                     // speed[i] = ..., each i of its length
//   var e = sum(n, i -> 0.5 * mass[i] * dot(vel[i], vel[i]));
//   var low = min(n, i -> pos[i].y), high = max(n, i -> pos[i].y);
//   var box = reduce(n, vec2(1e9, -1e9), i -> vec2(pos[i].y, pos[i].y), (a, b) -> vec2(Math.min(a.x, b.x), Math.max(a.y, b.y)));
//   final Relax = kernel(function(i:Int, p:{from:Items<Vec4>, to:Items<Vec4>, omega:Float}) ...);
//   Relax.run(n, {from: a, to: b, omega: 1.5});
//
// The last argument, an On, says where (Auto when none). A body is
// compiled at build time, as a compute shader is (its rules: README.md).

// the body for each i of 0...n
@:definition macro function each(n:Expr, body:Expr, ?on:Expr):Expr
	return ParallelMacro.each(n, body, on);

// out[i] = the body's value, for each i of 0...out.length
@:definition macro function map(out:Expr, body:Expr, ?on:Expr):Expr
	return ParallelMacro.map(out, body, on);

// the sum of the body's values over 0...n (Int, Float or a vector)
@:definition macro function sum(n:Expr, body:Expr, ?on:Expr):Expr
	return ParallelMacro.reduction("sum", n, body, on);

// the least of the body's values over 0...n (Int or Float); min(a, b): ShaderMath's
@:definition macro function min(n:Expr, body:Expr, ?on:Expr):Expr
	return ParallelMacro.minMax("min", n, body, on);

// the greatest of the body's values over 0...n; max(a, b): ShaderMath's
@:definition macro function max(n:Expr, body:Expr, ?on:Expr):Expr
	return ParallelMacro.minMax("max", n, body, on);

// the body's values over 0...n combined (combine associative, empty its identity)
@:definition macro function reduce(n:Expr, empty:Expr, body:Expr, combine:Expr, ?on:Expr):Expr
	return ParallelMacro.reduction("reduce", n, body, on, empty, combine);

// a named body of its own parameters: K.run(n, {...}, ?on)
@:definition macro function kernel(f:Expr):Expr
	return ParallelMacro.kernel(f);

#if !macro
class Parallel {
	// each site's choice printed when it changes
	public static var log = false;

	static var forcedForm:Null<On> = null;
	static var jobsFixed = -1.0;

	// HELDER_PARALLEL's form (scalar, simd, jobs, gpu), else Auto
	@:noCompletion public static function forced():On {
		if (forcedForm == null) forcedForm = switch Sys.getEnv("HELDER_PARALLEL") {
			case null | "" | "auto": On.Auto;
			case "scalar": On.Scalar;
			case "simd": On.Simd;
			case "jobs": On.Jobs;
			case "gpu": On.Gpu;
			case v: throw new haxe.Exception('HELDER_PARALLEL=$v: scalar, simd, jobs, gpu or auto');
		}
		return forcedForm;
	}

	// (a run on the threads that does nothing: its round trip in ns, the least of a few)
	@:noCompletion public static function jobsCost():Float {
		if (jobsFixed < 0) {
			var best = 1e30;
			for (_ in 0...8) {
				var t0 = haxe.Timer.stamp();
				Nothing.run();
				best = Math.min(best, (haxe.Timer.stamp() - t0) * 1e9);
			}
			jobsFixed = best;
		}
		return jobsFixed;
	}
}

@:hxmc.unsafe(gc) private class Nothing {
	static var at = hxmc.unsafe.Ptr.nil();

	@:hxmc.callback @:hxmc.unsafe static function none(ctx:hxmc.unsafe.Ptr, k:Int):Int
		return 0;

	public static function run() {
		if (at.isNull()) at = hxmc.unsafe.Callback.addr(none);
		helder.jobs.Spread.run(at, hxmc.unsafe.Ptr.nil(), (helder.jobs.Spread.threads() + 1) * 4);
	}
}
#end
