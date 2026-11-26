package image;

import haxe.io.Bytes;
import helder.image.*;
import helder.test.Gen;
import helder.test.Test;

// helder.image's decoders against the test images mutated (Gen.mutated),
// natively and on wasm32-wasi: each decoded by Image.decode and
// AnimatedImage.decode (a JPEG also at 1/8) under a small ImageLimits
// budget ends in a decode or an ImageError, no read past the end
// swallowed; natively within 10 s a case (else hung) and 256 MB more
// memory. The fuzz lane soaks it (HELDER_PROPERTY_SOAK).
function tests() {
	var seeds = new Map<String, Bytes>();
	for (dir in ["png", "jpeg", "gif", "webp", "apng"])
		for (f in sys.FileSystem.readDirectory('tests/image/$dir')) {
			if (StringTools.endsWith(f, ".rgba") || StringTools.endsWith(f, ".json")) continue;
			var b = sys.io.File.getBytes('tests/image/$dir/$f');
			if (b.length <= 16384) seeds.set('$dir/$f', b);
		}

	test("a mutated image: decoded, or an ImageError", () -> {
		var limits = [ImageLimits.maxPixels, ImageLimits.maxSide, ImageLimits.maxMemory];
		ImageLimits.maxPixels = 4194304;
		ImageLimits.maxSide = 8192;
		ImageLimits.maxMemory = 96 * 1048576.0;
		property(mutated(seeds), b -> {
			var jpeg = b.length > 2 && b.get(0) == 0xFF && b.get(1) == 0xD8;
			for (pass in 0...(jpeg ? 3 : 2)) {
				var before = ByteReader.refused, decoded = true;
				try {
					if (pass == 2) JpegDecoder.decode(b, null, 8) else if (pass == 1) AnimatedImage.decode(b) else Image.decode(b);
				} catch (e:ImageError) {
					decoded = false;
				}
				assert(!decoded || ByteReader.refused == before, 'pass $pass: a read past the end refused, and still decoded');
			}
		}, {cases: 150, seconds: 3, limit: 10, memory: 256});
		ImageLimits.maxPixels = Std.int(limits[0]);
		ImageLimits.maxSide = Std.int(limits[1]);
		ImageLimits.maxMemory = limits[2];
	});
}
