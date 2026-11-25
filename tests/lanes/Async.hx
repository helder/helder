package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Async {
	public static final LANES:Array<Lane> = [
		{name: "tls", about: "helder.async's https, wss and http natively", run: () -> {
			exe("bin/async/TlsTest", cps(["src", "tests/async"]).concat(["-main", "TlsTest"]));
			run(exePath("bin/async/TlsTest", HOST), []);
		}},
		{name: "async", about: "helder.async on Eval, natively and as wasm32-wasi", run: async},
		{name: "header-check", about: "typed C bindings against each POSIX target's headers", run: headerCheck},
		{name: "jobs", about: "helder.jobs' sendable check's rejections", run: jobsLane},
		{name: "jobs-web", about: "helder.jobs on Web Workers in headless Chromium", run: jobsWeb},
		{name: "async-web", about: "helder.async's browser loop in headless Chromium", run: asyncWeb}
	];

	// (ASYNC_TARGETS: the example also built for those, comma-separated, e.g.
	// macos-arm64,windows-x86_64: their runtime objects installed)
	static function async() {
		var cp = cps(["src", "tests/async"]);
		interp(cp, "AsyncTest");
		exe("bin/async/AsyncTest", cp.concat(["-main", "AsyncTest"]));
		run(exePath("bin/async/AsyncTest", HOST), []);
		// (TLS by mbedtls: a server and a client in one process, https and wss over it)
		exe("bin/async/TlsTest", cp.concat(["-main", "TlsTest"]));
		run(exePath("bin/async/TlsTest", HOST), []);
		wasm("bin/async/WebTest.wasm", cp.concat(["-main", "WebTest"]));
		run(NODE, ["tests/async/web.mjs", "bin/async/WebTest.wasm"]);
		var dev = cps(["src", "examples/async-dev"]).concat(["-main", "AsyncDev"]);
		exe("bin/async/AsyncDev", dev);
		Sys.println('AsyncDev: ${Math.round(FileSystem.stat(exePath("bin/async/AsyncDev", HOST)).size / 1024)} KB');
		run(NODE, ["tests/async/dev.mjs", exePath("bin/async/AsyncDev", HOST), "bin/async"]);
		for (t in (Sys.getEnv("ASYNC_TARGETS") ?? "").split(","))
			if (t != "") native('bin/async/$t/AsyncDev', dev, t);
		exe("bin/async/AsyncBench", cp.concat(["-main", "AsyncBench"]));
		run(exePath("bin/async/AsyncBench", HOST), []);
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

	static function jobsWeb() {
		wasm("bin/jobs/JobsWeb.wasm", cps(["src", "tests/jobs"]).concat(["-main", "JobsWeb"]));
		run(NODE, ["tests/jobs/browser.mjs", "bin/jobs/JobsWeb.wasm"]);
	}

	static function asyncWeb() {
		wasm("bin/async/WebTest.wasm", cps(["src", "tests/async"]).concat(["-main", "WebTest"]));
		run(NODE, ["tests/async/browser.mjs", "bin/async/WebTest.wasm"]);
	}
}
