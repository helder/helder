package viewer;

import haxe.io.Bytes;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

function tests() {
	describe("ThumbCache", () -> {
		var dir:String = null;
		var cache:ThumbCache = null;
		var jpeg = Bytes.ofHex("ffd8010203ffd9");
		var a = ThumbCache.key("a", 65, 70, 256), b = ThumbCache.key("b", 75, 80, 256), c = ThumbCache.key("c", 95, 100, 256);
		function reopen(budget = 192, segmentSize = 64) {
			cache.close();
			cache = new ThumbCache(budget, segmentSize, dir);
			assert(!cache.readOnly);
		}
		beforeEach(() -> {
			dir = helder.os.Paths.temp() + "/viewer-cache-" + Std.random(0x40000000);
			cache = new ThumbCache(192, 64, dir);
			assert(!cache.readOnly);
		});
		afterEach(() -> {
			cache.close();
			for (f in FileSystem.readDirectory(dir)) FileSystem.deleteFile(dir + "/" + f);
			FileSystem.deleteDirectory(dir);
		});
		test("key, round trip and negative hits", () -> {
			equals(a.high, 0x87343622);
			equals(a.low, 0xC7777729);
			cache.put(a, 3, 2, jpeg);
			cache.putNone(b);
			equals(cache.get(a), {width: 3, height: 2, bytes: jpeg});
			equals(cache.get(b), {width: 0, height: 0, bytes: null});
			equals(cache.get(c), null);
			equals(cache.get(ThumbCache.key("a", 65, 71, 256)), null);
		});
		test("reopen loads the saved index, including negative hits", () -> {
			cache.put(a, 3, 2, jpeg);
			cache.putNone(b);
			cache.flush();
			assert(FileSystem.exists(dir + "/index"));
			reopen();
			assert(!@:privateAccess cache.dirty, "loaded the saved index");
			equals(require(cache.get(a)).bytes, jpeg);
			equals(require(cache.get(b)).bytes, null);
		});
		test("missing, stale and corrupt indexes rebuilt from segments", () -> {
			cache.put(a, 3, 2, jpeg);
			cache.flush();
			cache.putNone(b);
			var readonly = new ThumbCache(192, 64, dir);
			equals(require(readonly.get(b)).bytes, null);
			readonly.close();
			cache.close();
			FileSystem.deleteFile(dir + "/index");
			reopen();
			equals(require(cache.get(a)).bytes, jpeg);
			cache.close();
			var index = File.getBytes(dir + "/index");
			index.set(index.length - 1, index.get(index.length - 1) ^ 1);
			File.saveBytes(dir + "/index", index);
			reopen();
			assert(@:privateAccess cache.dirty, "rebuilt after checksum failure");
			equals(require(cache.get(b)).bytes, null);
		});
		test("truncated and bad-CRC records end the scan, and new records go in a fresh segment", () -> {
			for (truncate in [true, false]) {
				cache.close();
				for (f in FileSystem.readDirectory(dir)) FileSystem.deleteFile(dir + "/" + f);
				reopen();
				cache.put(a, 3, 2, jpeg);
				cache.put(b, 3, 2, jpeg);
				cache.close();
				var path = dir + "/seg-0000000001", orig = File.getBytes(path);
				var damaged = truncate ? orig.sub(0, orig.length - 1) : orig;
				damaged.set(damaged.length - 1, 0);
				File.saveBytes(path, damaged);
				FileSystem.deleteFile(dir + "/index");
				reopen();
				equals(require(cache.get(a)).bytes, jpeg);
				equals(cache.get(b), null);
				cache.put(c, 3, 2, jpeg);
				assert(FileSystem.exists(dir + "/seg-0000000002"));
				reopen();
				equals(require(cache.get(c)).bytes, jpeg);
			}
		});
		test("FIFO eviction removes the segment and all its records", () -> {
			reopen(64, 32);
			cache.put(a, 3, 2, jpeg);
			cache.put(b, 3, 2, jpeg);
			cache.put(c, 3, 2, jpeg);
			assert(!FileSystem.exists(dir + "/seg-0000000001"));
			assert(FileSystem.exists(dir + "/seg-0000000002") && FileSystem.exists(dir + "/seg-0000000003"));
			equals(cache.get(a), null);
			equals(require(cache.get(c)).bytes, jpeg);
		});
		test("an old hit is promoted and survives the next FIFO eviction", () -> {
			reopen(96, 32);
			cache.put(a, 3, 2, jpeg);
			cache.put(b, 3, 2, jpeg);
			equals(require(cache.get(a)).bytes, jpeg);
			assert(FileSystem.exists(dir + "/seg-0000000003"));
			cache.put(c, 3, 2, jpeg);
			assert(!FileSystem.exists(dir + "/seg-0000000001"));
			reopen(96, 32);
			equals(require(cache.get(a)).bytes, jpeg);
		});
		test("second instance reads only, and an unlocked PID can be replaced", () -> {
			cache.put(a, 3, 2, jpeg);
			var second = new ThumbCache(192, 64, dir);
			assert(second.readOnly);
			equals(require(second.get(a)).bytes, jpeg);
			second.putNone(b);
			second.flush();
			equals(cache.get(b), null);
			second.close();
			cache.close();
			File.saveContent(dir + "/lock", "2147483647\n");
			reopen();
			assert(File.getContent(dir + "/lock") != "2147483647\n");
			cache.putNone(b);
			equals(require(cache.get(b)).bytes, null);
		});
	});
}
