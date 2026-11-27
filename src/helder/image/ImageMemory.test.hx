package helder.image;

import helder.test.Test;

// ImageMemory: a decode's planes and pixels off the heap give the same
// pixels as on it (JPEG, its EXIF turn too; lossy WebP; PNG), the result
// taken, the rest freed; a JPEG in strips over threads allocates on its own
// thread (another thread's bytes() throws: their arrays fell apart, #224)
function tests() {
	describe("ImageMemory", () -> {
		for (f in ["jpeg/large-420.jpg", "jpeg/orient6.jpg", "jpeg/progressive-420.jpg", "webp/lossy-alpha.webp", "png/rgb8.png"])
			test('off the heap: $f as on it', () -> {
				var file = sys.io.File.getBytes("tests/image/" + f);
				var on = Image.decode(file).pixels;
				var mem = ImageMemory.offHeapMemory();
				var d = StringTools.endsWith(f, ".jpg") ? JpegDecoder.decode(file, mem) : StringTools.endsWith(f, ".webp") ? WebpDecoder.decode(file, mem) : PngDecoder.decode(file, mem);
				equals(d.rgba.toHex(), on.toHex());
				#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
				var b = mem.take(d.rgba);
				mem.dispose();
				equals(b.getBytes(0, b.length).toHex(), on.toHex());
				b.close();
				#end
			});
		test("off the heap in strips over three threads: as on one", () -> {
			var file = sys.io.File.getBytes("tests/image/jpeg/large-420.jpg");
			var on = Image.decode(file).pixels.toHex();
			var mem = ImageMemory.offHeapMemory();
			JpegDecoder.threads = 3;
			var d = try JpegDecoder.decode(file, mem) catch (e:Dynamic) {
				JpegDecoder.threads = 1;
				mem.dispose();
				throw e;
			}
			JpegDecoder.threads = 1;
			equals(d.rgba.toHex(), on);
			#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
			var b = mem.take(d.rgba);
			mem.dispose();
			equals(b.getBytes(0, b.length).toHex(), on);
			b.close();
			#end
		});
	});
}
