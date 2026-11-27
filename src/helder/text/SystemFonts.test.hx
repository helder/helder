package helder.text;

import helder.test.Test;
import helder.text.SystemFonts.FaceInfo;

// what discovery reads of a font file, its headers alone (FaceInfo.read)
function tests() {
	describe("FaceInfo", () -> {
		// (a directory of the checkout: wasm32-wasi reaches no /tmp)
		var dir = "bin/test/faceinfo";
		sys.FileSystem.createDirectory(dir);
		test("a font's family, weight and axis", () -> {
			var p = dir + "/helder-faceinfo-" + Std.random(1 << 30) + ".ttf";
			sys.io.File.saveBytes(p, helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"));
			var f = FaceInfo.read(p);
			sys.FileSystem.deleteFile(p);
			equals(f.length, 1);
			equals(f[0].family, "Inter");
			equals(f[0].italic, false);
			equals([f[0].minWeight, f[0].maxWeight], [100, 900]);
		});
		test("not a font: no faces", () -> {
			var p = dir + "/helder-faceinfo-" + Std.random(1 << 30) + ".ttf";
			sys.io.File.saveContent(p, "not a font");
			equals(FaceInfo.read(p).length, 0);
			sys.FileSystem.deleteFile(p);
		});
	});
}
