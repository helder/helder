package viewer;

import haxe.io.Bytes;
import helder.async.Async;
import helder.image.Image;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

function tests() {
	describe("Thumbnails", () -> {
		var dir:String = null;
		var queue:Thumbnails = null;
		beforeEach(() -> {
			dir = helder.os.Paths.temp() + "/viewer-thumbnails-" + Std.random(0x40000000);
			queue = new Thumbnails(new ThumbCache(1 << 20, 128 << 10, dir), 1);
		});
		afterEach(() -> {
			queue.close();
			for (name in FileSystem.readDirectory(dir)) FileSystem.deleteFile(dir + "/" + name);
			FileSystem.deleteDirectory(dir);
		});
		test("first images, small-file bypass, and warm hits for every format", async(() -> {
			var n = 0;
			for (f in [
				{name: "folder/photo 2.jpg", dims: [256, 216]},
				{name: "folder/photo 10.jpg", dims: [29, 37]},
				{name: "folder/alpha.png", dims: [13, 11]},
				{name: "folder/anim.gif", dims: [37, 29]},
				{name: "folder/lossy.webp", dims: [50, 40]},
				{name: "pdf/pages.pdf", dims: [192, 256]}
			]) {
				var path = "tests/fixtures/" + f.name, original = File.getBytes(path), st = FileSystem.stat(path);
				var first = require(ask(queue, path), f.name);
				equals([first.width, first.height], f.dims, f.name);
				equals(queue.sourceDecodes, ++n);
				if (st.size < 65536) {
					var small = require(ask(queue, path), f.name);
					equals([small.width, small.height], f.dims, f.name);
					equals(queue.sourceDecodes, ++n);
					// (trailing bytes keep the fixture's first image and exercise
					// the cacheable path, with the PDF's trailer still at the end)
					var padded = Bytes.alloc(65536);
					if (haxe.io.Path.extension(path) == "pdf") {
						var trailer = original.toString().lastIndexOf("startxref");
						padded.fill(0, padded.length, 32);
						padded.blit(0, original, 0, trailer);
						padded.blit(padded.length - (original.length - trailer), original, trailer, original.length - trailer);
					} else padded.blit(0, original, 0, original.length);
					path = dir + "/" + haxe.io.Path.withoutDirectory(path);
					File.saveBytes(path, padded);
					require(ask(queue, path), f.name + " padded");
					equals(queue.sourceDecodes, ++n);
				}
				var warm = require(ask(queue, path), f.name + " warm");
				equals([warm.width, warm.height], f.dims, f.name);
				equals(queue.sourceDecodes, n);
			}
		})).timeout(20);
		test("no thumbnail for a broken JPEG or a text file", async(() -> {
			equals(ask(queue, "tests/fixtures/folder/broken.jpg"), null);
			equals(ask(queue, "tests/fixtures/folder/notes.txt"), null);
		})).timeout(5);
		test("a TIFF through the system's decoder, turned as its EXIF says", async(() -> {
			var path = "../../tests/os/images/gradient-rot6.tif";
			if (!helder.os.SystemImages.supports(path)) return;
			var img = require(ask(queue, path));
			equals([img.width, img.height], [48, 64]);
		})).timeout(5);
		test("RAF preview outside the first read, fitted to 256", async(() -> {
			var jpeg = helder.image.JpegEncoder.encode(Bytes.alloc(200 * 100 * 4), 200, 100);
			var at = (512 << 10) + 12, b = Bytes.alloc(at + jpeg.length);
			b.blit(0, Bytes.ofString("FUJIFILMCCD-RAW"), 0, 15);
			for (i in 0...4) {
				b.set(84 + i, (at >>> (24 - i * 8)) & 255);
				b.set(88 + i, (jpeg.length >>> (24 - i * 8)) & 255);
			}
			b.blit(at, jpeg, 0, jpeg.length);
			var path = dir + "/preview.raf";
			File.saveBytes(path, b);
			var img = require(ask(queue, path));
			equals([img.width, img.height], [256, 128]);
		})).timeout(5);
		test("negative hit skips a second source decode; metadata changes miss", async(() -> {
			var path = dir + "/bad.jpg";
			File.saveBytes(path, Bytes.alloc(65536));
			equals(ask(queue, path), null);
			equals(ask(queue, path), null);
			equals(queue.sourceDecodes, 1);
			equals(ask(queue, path, 1), null);
			equals(queue.sourceDecodes, 2);
		})).timeout(5);
		test("priority, ties, reprioritization and cancellation on the main loop", async(() -> {
			var path = "tests/fixtures/folder/alpha.png", st = FileSystem.stat(path), order = [];
			var thread = hxmc.NativeThread.current();
			function add(name:String, priority:Int):Int {
				return queue.request(path, st.size, st.mtime.getTime(), 256, priority, result -> {
					equals(hxmc.NativeThread.current(), thread);
					assert(result != null);
					order.push(name);
				});
			}
			var active = add("running, then cancelled", -10);
			var moved = add("moved first", 50);
			var later = add("moved last", 1);
			add("earlier tie", 2);
			add("later tie", 2);
			queue.cancel(add("cancelled while queued", -100));
			queue.reprioritize(moved, 0);
			queue.reprioritize(later, 5);
			Async.launch(_ -> queue.cancel(active));
			while (order.length < 4) Async.delay(0.001);
			equals(order, ["moved first", "earlier tie", "later tie", "moved last"]);
			equals(queue.sourceDecodes, 5);
		})).timeout(5);
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || (!hxmc.target && helder.os == "macos"))
		test("a video keyframe through the platform decoder", async(() -> {
			var img = require(ask(queue, "../../tests/media/apple/quads.mp4"));
			assert(img.width > 0 && img.height > 0 && Math.max(img.width, img.height) <= 256);
		})).timeout(10);
		#end
	});
}

@:coroutine private function ask(queue:Thumbnails, path:String, mtimeOffset = 0):Null<Image> {
	var st = FileSystem.stat(path);
	return Async.suspend(cont -> {
		queue.request(path, st.size, st.mtime.getTime() + mtimeOffset, 256, 0, img -> Async.resumeLater(cont, img, null));
	});
}
