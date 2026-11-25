import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import lanes.*;
import lanes.Tools.*;

using StringTools;

// The checks, from the repository's root, with @hxmc/cli's compiler (`haxe`,
// node_modules/.bin on the PATH):
//
//   bun run test                   the headless lanes (no GPU, display or browser)
//   bun run test <lane> ...        those lanes (-k: the next one after a failure,
//                                  headless's too; every failure listed at the end;
//                                  -x <lane>: not that one, as headless -x typescript;
//                                  -j <n>: n lanes at once, each its own process)
//   bun run test help              the lanes
//
// The lanes are in tests/lanes, a file per group; tests/README.md says what
// each one checks.
// Outputs go to bin/<lane>. GFX_TARGET and AUDIO_TARGET (the host's by
// default) cross-compile the native programs (windows-x86_64: run under
// Wine). BLESS=1 rewrites the golden files of the lanes that have them. The
// browser lanes need Playwright with Chromium (bun add --no-save playwright;
// bunx playwright install chromium); the gfx, ui-draw and 3d lanes Mesa and
// Xvfb on Linux.
class Run {
	static final HEADLESS = ["view", "text", "image", "ui", "layout-conformance", "gfx-shader", "async", "header-check", "jobs", "test", "os", "cli", "asset", "pack", "devtools", "typescript", "examples", "viewer", "canvas", "pdf", "syntax", "text-quality", "ui-soft", "gfx-soft"];

	static final LANES:Array<Lane> = [{name: "headless", about: "the lanes that need no GPU, display or browser", run: () -> for (l in HEADLESS) lane(l)}]
		.concat(View.LANES).concat(Text.LANES).concat(Image.LANES).concat(Canvas.LANES).concat(Async.LANES).concat(Os.LANES).concat(Viewer.LANES).concat(Pack.LANES).concat(Cli.LANES).concat(Gfx.LANES).concat(Scene.LANES).concat(Studio.LANES).concat(Bench.LANES);

	static function main() {
		// (helder.text's own engine for every lane's program: goldens the same on every OS; system-text's the platform's)
		if (Sys.getEnv("HELDER_TEXT_ENGINE") == null) Sys.putEnv("HELDER_TEXT_ENGINE", "helder");
		// (no helder build server kept warm: the lanes' builds, many at once, each its own compiler; BuildServer)
		if (Sys.getEnv("HELDER_BUILD_SERVER") == null) Sys.putEnv("HELDER_BUILD_SERVER", "0");
		if (Sys.getEnv("HELDER_BACKGROUND") == null) Sys.putEnv("HELDER_BACKGROUND", "1");
		// (hxmc's module cache off: no faster for helder's builds, and seen building stale code; HXMC_MODULE_CACHE=1 turns it on)
		if (Sys.getEnv("HXMC_MODULE_CACHE") == null) Sys.putEnv("HXMC_MODULE_CACHE", "0");
		var args = Sys.args();
		buildOnly = args.remove("--build-only");
		usePrebuilt = args.remove("--prebuilt");
		var ix = args.indexOf("--shard");
		if (ix >= 0) {
			var spec = args[ix + 1] ?? "";
			var m = ~/^(\d+)\/([1-9]\d*)$/;
			if (m.match(spec)) {
				shardIndex = Std.parseInt(m.matched(1)) ?? -1;
				shardTotal = Std.parseInt(m.matched(2)) ?? -1;
			} else shardTotal = 0;
			args.splice(ix, 2);
			if (shardIndex < 0 || shardIndex >= shardTotal || args.contains("--shard")) {
				Sys.stderr().writeString("--shard expects a zero-based index and total, for example --shard 0/2\n");
				Sys.exit(2);
			}
		}
		var keepGoing = args.remove("-k");
		var skipped = [];
		while (args.indexOf("-x") >= 0) {
			var i = args.indexOf("-x");
			if (i + 1 < args.length) skipped.push(args[i + 1]);
			args.splice(i, 2);
		}
		var jobs = 1;
		var i = args.indexOf("--jobs");
		if (i < 0) i = args.indexOf("-j");
		if (i >= 0) {
			workerCount = jobs = Std.parseInt(args[i + 1] ?? "") ?? cpus();
			if (jobs < 1) {
				Sys.stderr().writeString("--jobs must be positive\n");
				Sys.exit(2);
			}
			args.splice(i, 2);
		}
		if (args.length == 0) args = ["headless"];
		args = benches(args);
		if (args.contains("help")) {
			Sys.println("bun run test [-k] [--jobs n] [--shard i/n] <lane> ...\n");
			for (l in LANES) Sys.println("  " + l.name.rpad(" ", 19) + " " + l.about);
			return;
		}
		if (buildOnly && usePrebuilt || (buildOnly || usePrebuilt) && Lambda.exists(args, a -> a != "android-device" && a != "ios-device")) {
			Sys.stderr().writeString("--build-only and --prebuilt are mutually exclusive device lane options\n");
			Sys.exit(2);
		}
		if (shardTotal > 1 && Lambda.exists(args, a -> a != "typescript" && a != "3d-web" && a != "ios-device")) {
			Sys.stderr().writeString("--shard is supported by typescript, 3d-web and ios-device\n");
			Sys.exit(2);
		}
		// (headless as its lanes, each run on its own: with -k every one runs
		// and each failure is reported, not the first alone)
		args = [for (a in args) for (l in (a == "headless" ? HEADLESS : [a])) if (!skipped.contains(l)) l];
		if (jobs > 1 && args.length > 1) {
			lanesAtOnce(args, jobs, keepGoing);
			return;
		}
		var failed = [], times = [];
		for (a in args) {
			var t0 = Sys.time();
			try {
				lane(a);
			} catch (e:Failed) {
				Sys.println('\n$a: FAILED: ${e.message}');
				failed.push(a);
			}
			// (each lane's time, and all of them at the end: where a job's minutes go)
			var t = Math.round(Sys.time() - t0);
			times.push(a.rpad(" ", 16) + " " + Std.string(t).lpad(" ", 5) + " s" + (failed.contains(a) ? "  FAILED" : ""));
			Sys.println('--- $a: $t s');
			if (failed.length > 0 && !keepGoing) break;
		}
		if (times.length > 1) Sys.println("\nlanes:\n  " + times.join("\n  "));
		if (failed.length > 0) {
			Sys.println("failed: " + failed.join(", "));
			Sys.exit(1);
		}
	}

	// -j <n>: the lanes n at once, each in a process of its own (bun run test
	// <lane>), the long ones first (CI's), then in the order given, each
	// one's output printed whole when it ends; the CLI built once before
	// (RUN_CLI_BUILT: the lanes run it, none builds it again). Without -k,
	// none is started after a failure.
	static function lanesAtOnce(lanes:Array<String>, jobs:Int, keepGoing:Bool) {
		for (l in lanes) if (!Lambda.exists(LANES, x -> x.name == l)) throw new Failed('no lane $l (bun run test help)');
		helderCli();
		Sys.putEnv("RUN_CLI_BUILT", "1");
		// (the long ones first, CI's minutes: the short ones fill in after;
		// the dev loops' lanes alone at the end, as a serial run has them: a
		// watcher's and a build's times under the others' load timed out)
		var long = ["pack", "test", "ui", "canvas", "syntax"], alone = ["cli", "devtools"];
		var queue = [for (l in long) if (lanes.contains(l)) l].concat([for (l in lanes) if (!long.contains(l) && !alone.contains(l)) l]);
		var last = [for (l in alone) if (lanes.contains(l)) l];
		var failed = [], times = new Map<String, Int>();
		var mutex = new sys.thread.Mutex(), done = new sys.thread.Lock();
		var t0 = Sys.time();
		var workers = Std.int(Math.max(1, Math.min(jobs, queue.length)));
		Sys.println('--- ${lanes.length} lanes, $workers at once: ${queue.join(" ")}' + (last.length > 0 ? '; then alone: ${last.join(" ")}' : ""));
		function pool(queue:Array<String>, workers:Int) {
			for (_ in 0...workers)
				sys.thread.Thread.create(() -> {
					while (true) {
						mutex.acquire();
						var l = failed.length > 0 && !keepGoing ? null : queue.shift();
						mutex.release();
						if (l == null) break;
						var s = Sys.time();
						var opts = buildOnly ? ["--build-only"] : usePrebuilt ? ["--prebuilt"] : [];
						var p = new Process(TOOL, ["-cp", "tests", "--run", "Run", l].concat(shardArgs()).concat(opts));
						var r = drain(p);
						var code = p.exitCode();
						p.close();
						var t = Math.round(Sys.time() - s);
						mutex.acquire();
						Sys.print(r.out + r.err);
						if (code != 0) {
							Sys.println('\n$l: FAILED (exit code $code)');
							failed.push(l);
						}
						Sys.println('--- $l: $t s (at ${Math.round(Sys.time() - t0)} s)');
						times.set(l, t);
						mutex.release();
					}
					done.release();
				});
			for (_ in 0...workers) done.wait();
		}
		pool(queue, workers);
		pool(last, 1);
		Sys.println('\nlanes ($workers at once, ${Math.round(Sys.time() - t0)} s):\n  '
			+ [for (l in lanes) if (times.exists(l)) l.rpad(" ", 16) + " " + Std.string(times.get(l)).lpad(" ", 5) + " s" + (failed.contains(l) ? "  FAILED" : "")].join("\n  "));
		if (failed.length > 0) {
			Sys.println("failed: " + failed.join(", "));
			Sys.exit(1);
		}
	}

	// bench <name> ...: each its lane, "bench <name>"
	static function benches(args:Array<String>):Array<String> {
		var out = [], named = false;
		for (a in args) {
			if (named && Lambda.exists(LANES, l -> l.name == 'bench $a')) {
				if (out[out.length - 1] == "bench") out.pop();
				out.push('bench $a');
				continue;
			}
			named = a == "bench";
			out.push(a);
		}
		return out;
	}

	static function lane(name:String) {
		var l = Lambda.find(LANES, l -> l.name == name);
		if (l == null) throw new Failed('no lane $name (bun run test help)');
		Sys.println('--- $name');
		l.run();
	}
}
