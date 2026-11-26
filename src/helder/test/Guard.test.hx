package helder.test;

import helder.test.Gen;
import helder.test.Test;

// The watchdog's memory budget, natively: the program run again on a
// fixture (HELDER_GUARD_FIXTURE, its own store). Cases that allocate and
// drop 8 MB each, thousands of them, pass a 32 MB budget (the collector's
// garbage of the cases before is not theirs); a case that keeps 300 MB
// ends the process, saying what it measured.
function tests() {
	switch Sys.getEnv("HELDER_GUARD_FIXTURE") {
		case "churn":
			test("churn", () -> property(int(0, 100), n -> {
				var kept = [for (_ in 0...8) haxe.io.Bytes.alloc(1 << 20)];
				kept[n % 8].set(0, n);
			}, {cases: 3000, seconds: 20, limit: 30, memory: 32}));
		case "grow":
			test("grow", () -> property(int(0, 100), n -> {
				if (n > 50) for (_ in 0...300) held.push(haxe.io.Bytes.alloc(1 << 20));
			}, {limit: 30, memory: 32}));
		case _:
			#if (helder.os == "macos" || helder.os == "linux")
			test("cases that allocate and drop pass a small budget", () -> {
				var r = rerun("churn");
				equals(r.code, 0, r.out);
			}).timeout(60);
			test("a case that keeps memory ends the process, saying so", () -> {
				var r = rerun("grow");
				equals(r.code, 3, r.out);
				assert(~/(kept|rose) \d+ MB/.match(r.out), r.out);
			}).timeout(60);
			#end
	}
}

private final held:Array<haxe.io.Bytes> = [];

// (the program again on a fixture, its store its own: its exit code and output)
private function rerun(fixture:String):{code:Int, out:String} {
	var store = 'bin/test/guard-$fixture';
	try for (f in sys.FileSystem.readDirectory(store)) sys.FileSystem.deleteFile('$store/$f') catch (_:Dynamic) {}
	Sys.putEnv("HELDER_GUARD_FIXTURE", fixture);
	Sys.putEnv("HELDER_PROPERTY_STORE", store);
	var p = new sys.io.Process(Sys.programPath(), ["-t", fixture]);
	var out = p.stdout.readAll().toString();
	var code = p.exitCode();
	p.close();
	Sys.putEnv("HELDER_GUARD_FIXTURE", "");
	Sys.putEnv("HELDER_PROPERTY_STORE", "");
	return {code: code, out: out};
}
