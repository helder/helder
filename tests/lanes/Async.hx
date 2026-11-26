package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Async {
	public static final LANES:Array<Lane> = [
		{name: "tls", about: "helder.async's https, wss and http natively", run: () -> {
			exe("bin/async/TlsCheck", cps(["src", "tests/async"]).concat(["-main", "TlsCheck"]));
			run(exePath("bin/async/TlsCheck", HOST), []);
		}},
		{name: "async", about: "helder.async on Eval, natively and as wasm32-wasi", run: async},
		{name: "header-check", about: "typed C bindings against each POSIX target's headers", run: headerCheck},
		{name: "jobs", about: "helder.jobs' sendable check's rejections", run: jobsLane},
		{name: "parallel", about: "helder.parallel's body rules' rejections and HELDER_PARALLEL", run: parallelLane},
		{name: "jobs-web", about: "helder.jobs on Web Workers in headless Chromium", run: jobsWeb},
		{name: "async-web", about: "helder.async's browser loop in headless Chromium", run: asyncWeb}
	];

	// (ASYNC_TARGETS: the example also built for those, comma-separated, e.g.
	// macos-arm64,windows-x86_64: their runtime objects installed)
	static function async() {
		var cp = cps(["src", "tests/async"]);
		interp(cp, "AsyncCheck");
		exe("bin/async/AsyncCheck", cp.concat(["-main", "AsyncCheck"]));
		run(exePath("bin/async/AsyncCheck", HOST), []);
		// (TLS by mbedtls: a server and a client in one process, https and wss over it)
		exe("bin/async/TlsCheck", cp.concat(["-main", "TlsCheck"]));
		run(exePath("bin/async/TlsCheck", HOST), []);
		wasm("bin/async/WebCheck.wasm", cp.concat(["-main", "WebCheck"]));
		run(NODE, ["tests/async/web.mjs", "bin/async/WebCheck.wasm"]);
		var dev = cps(["src", "examples/async-dev"]).concat(["-main", "AsyncDev"]);
		exe("bin/async/AsyncDev", dev);
		Sys.println('AsyncDev: ${Math.round(FileSystem.stat(exePath("bin/async/AsyncDev", HOST)).size / 1024)} KB');
		run(NODE, ["tests/async/dev.mjs", exePath("bin/async/AsyncDev", HOST), "bin/async"]);
		for (t in (Sys.getEnv("ASYNC_TARGETS") ?? "").split(","))
			if (t != "") native('bin/async/$t/AsyncDev', dev, t);
	}

	static function headerCheck() {
		var zig = Sys.getEnv("ZIG") ?? "zig";
		if ((try output(zig, ["version"], true) catch (_:Dynamic) null) == null) {
			Sys.println("header-check: skipped (no zig)");
			return;
		}
		var cp = cps(["src", "tests/async"]);
		for (t => triple in ["linux-x86_64" => "x86_64-linux-musl", "linux-arm64" => "aarch64-linux-musl", "macos-x86_64" => "x86_64-macos", "macos-arm64" => "aarch64-macos"]) {
			var out = 'bin/header-check/$t', cpp = '$out.cpp';
			var b = build(cp.concat(["-main", "HeaderCheck", "-D", 'hxmc.target=$t', "-D", "hxmc.lower-only", "-D", 'hxmc.header-check=$cpp', "--custom-target", 'hxmc=$out']), '$out.log');
			if (b.code != 0) throw new Failed('header-check $t: the build failed:\n' + b.log);
			var asserts = File.getContent(cpp).split("\n").filter(l -> l.indexOf("src/helder/") >= 0).length;
			run(zig, ["c++", "-target", triple, "-std=c++17", "-nostdinc++", "-c", "-o", '$out.o', "-x", "c++", cpp]);
			Sys.println('header-check $t: $asserts assertions of helder\'s, ok');
		}
	}

	// (the sendable check: a program it rejects, with the message expected)
	static function jobsLane() {
		var cp = cps(["src", "tests/jobs/reject"]);
		for (r in [
			{main: "NotSendable", want: "helder.jobs: count's input cannot be sent: .items[]: Item is a class"},
			{main: "NotSendableChannel", want: "helder.jobs: a Channel's value cannot be sent: Int -> Void is a function"},
			{main: "NotKernel", want: "a GC-free job is an @:hxmc.kernel @:hxmc.callback static function (job:helder.jobs.Job):Int (raw)"},
			{main: "ReadsRaw", want: "Mem, Atomic and C functions need @:hxmc.unsafe"}
		]) {
			var b = build(cp.concat(["-main", r.main, "--custom-target", 'hxmc=bin/jobs/reject/${r.main}']), 'bin/jobs/reject/${r.main}.log');
			if (b.code == 0 || !b.log.contains(r.want)) throw new Failed('${r.main}: expected the error "${r.want}":\n' + b.log);
			Sys.println('${r.main}: rejected');
		}
	}

	// (a body's rules, helder.parallel.ParallelScan's: a program each rejects,
	// its message and line expected; then HELDER_PARALLEL's forms, each
	// site's choice printed. The forms' tests are src/helder/parallel's, the test lane's)
	static function parallelLane() {
		var cp = cps(["src", "tests/parallel/reject"]);
		for (r in [
			{main: "CaptureAssigned", line: 7, want: "each: total is captured: a body reads what it captures, and assigns its own locals and Items' elements only"},
			{main: "WritesElsewhere", line: 7, want: "each: a[...] = ...: a body writes at the item's own index only (a[i] = ...)"},
			{main: "ReadsWritten", line: 8, want: "each: a is written by the body (a[i] = ...), and so read at the item's own index only (a[i])"},
			{main: "IndexAssigned", line: 8, want: "each: i is the item's index: a body does not assign it"},
			{main: "Allocates", line: 8, want: "each: arrays are not supported in a shader"},
			{main: "CapturesString", line: 7, want: "each: names's type is Array<String>: a body captures Int, Float, Bool, vectors, Mat4 and Items"},
			{main: "PassesItems", line: 7, want: "each: a: an Items in a body is indexed (a[i]) or its length read, not passed on"},
			{main: "KernelLocal", line: 8, want: "kernel: scale is a local: a kernel reads its parameters (p.x) and statics"},
			{main: "ElementVec3", line: 6, want: "Items<Vec3>: a Vec3 has no storage layout"},
			{main: "ReduceString", line: 7, want: "min: a body's value is an Int or a Float, not Bool"}
		]) {
			var b = build(cp.concat(["-main", r.main, "--no-output", "--custom-target", 'hxmc=bin/parallel/reject/${r.main}']), 'bin/parallel/reject/${r.main}.log');
			var at = '${r.main}.hx:${r.line}:';
			if (b.code == 0 || !b.log.contains(r.want) || !b.log.contains(at)) throw new Failed('${r.main}: expected the error "${r.want}" at $at\n' + b.log);
			Sys.println('${r.main}: rejected');
		}
		exe("bin/parallel/ForcedCheck", cps(["src", "tests/parallel"]).concat(["-main", "ForcedCheck"]));
		var check = exePath("bin/parallel/ForcedCheck", HOST);
		for (form in ["scalar", "simd", "jobs"]) {
			expect(check, [], ["HELDER_PARALLEL" => form], 'ForcedCheck.hx:9 each: $form');
			expect(check, [], ["HELDER_PARALLEL" => form], 'ForcedCheck.hx:11 sum: $form');
		}
		expect(check, [], ["HELDER_PARALLEL" => "gpu"], "On.Gpu: no Parallel.device with compute stages", 1);
	}

	static function jobsWeb() {
		wasm("bin/jobs/JobsWebCheck.wasm", cps(["src", "tests/jobs"]).concat(["-main", "JobsWebCheck"]));
		run(NODE, ["tests/jobs/browser.mjs", "bin/jobs/JobsWebCheck.wasm"]);
	}

	static function asyncWeb() {
		wasm("bin/async/WebCheck.wasm", cps(["src", "tests/async"]).concat(["-main", "WebCheck"]));
		run(NODE, ["tests/async/browser.mjs", "bin/async/WebCheck.wasm"]);
	}
}
