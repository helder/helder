package viewer;

import helder.test.Test;

// Where the viewer keeps what it keeps: --store's home (set as helder.os's
// HELDER_HOME), else the environment's, else the platform's place (a test's
// run never the user's own)
function tests() {
	describe("Store", () -> {
		test("--store's home, else none (HELDER_HOME's, else the user's own)", () -> {
			equals(Shell.storeDir(["a.png", "--store", "/tmp/s"]), "/tmp/s");
			equals(Shell.storeDir(["a.png"]), null);
			equals(Shell.storeDir(["--store", ""]), null);
			equals(Shell.storeDir(["--store"]), null);
		});
	});
}
