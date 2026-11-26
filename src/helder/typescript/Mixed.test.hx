package helder.typescript;

import helder.test.Test;

function tests() {
	// (WASI has no /tmp: the folder these need is the host's alone)
	#if !(hxmc.target == "wasm32-wasi")
	// (the compiler's helder: a folder with helder/math in it)
	var src = haxe.io.Path.normalize((Sys.getEnv("TMPDIR") ?? "/tmp") + "/helder-mixed-" + Std.random(1000000));
	sys.FileSystem.createDirectory('$src/helder/math');
	describe("Mixed", () -> {
		test("another checkout's helder/math: named", () -> {
			equals(Mixed.of(["/p/app.tsx", "/old/src/helder/math/index.ts"], src), "/old/src");
			equals(Mixed.explain("TSHX004: helder/math's Vec3 is not in the program", ["/old/src/helder/math/index.ts"], src).indexOf("two helder sources mixed") > 0, true);
		});
		test("the compiler's own, or no helder: none", () -> {
			equals(Mixed.of(['$src/helder/math/index.ts', "/p/helder/app.tsx"], src), null);
			equals(Mixed.explain("TSHX001: x", ["/old/src/helder/math/index.ts"], src), "TSHX001: x");
		});
	});
	afterAll(() -> {
		sys.FileSystem.deleteDirectory('$src/helder/math');
		sys.FileSystem.deleteDirectory('$src/helder');
		sys.FileSystem.deleteDirectory(src);
	});
	#end
}
