package helder.compiler;

import helder.test.Test;

function tests() {
	test("each target's system", () -> {
		equals([for (t in ["linux-x86_64", "linux-arm64", "android-arm64", "android-x86_64", "macos-arm64", "macos-x86_64"]) Os.of(t)], ["linux", "linux", "android", "android", "macos", "macos"]);
		equals([for (t in ["ios-arm64", "ios-sim-arm64", "macos-catalyst-arm64", "windows-x86_64", "windows-arm64", "wasm32-wasi"]) Os.of(t)], ["ios", "ios", "ios", "windows", "windows", "web"]);
		equals(Os.define("wasm32-wasi"), ["-D", "helder.os=web"]);
	});
}
