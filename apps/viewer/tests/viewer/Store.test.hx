package viewer;

import helder.test.Test;

// Where the viewer keeps what it keeps: --store over HELDER_VIEWER_STORE
// over the platform's place (a test's run never the user's own)
function tests() {
	describe("Store", () -> {
		test("--store, else the environment's, else the user's own", () -> {
			equals(Shell.storeDir(["a.png", "--store", "/tmp/s"], "/tmp/env"), "/tmp/s");
			equals(Shell.storeDir(["a.png"], "/tmp/env"), "/tmp/env");
			equals(Shell.storeDir(["a.png"], ""), null);
			equals(Shell.storeDir(["--store"], null), null);
			equals(Shell.storeDir([], null), null);
		});
	});
}
