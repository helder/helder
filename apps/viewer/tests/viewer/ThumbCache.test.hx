package viewer;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// ThumbCache: its keys, round trips and negative hits, indexes saved,
// stale or damaged and rebuilt, eviction by segment, promotion, a second
// instance reading only; and against a model of its segments (a stateful
// property: puts, hits, flushes and reopens, in a temporary directory)
function tests() {
	test("ThumbCache against its segments: the same hits, promotions and evictions", () -> stateful({
		setup: () -> new Model(),
		steps: [
			{name: "put", run: (m, c) -> m.put(c.draw(int(0, 5)), c.draw(int(1, 3)), c.draw(int(1, 3)), c.draw(int(1, 40)))},
			{name: "put none", run: (m, c) -> m.put(c.draw(int(0, 5)), 0, 0, 0)},
			{name: "get", run: (m, c) -> m.get(c.draw(int(0, 5)))},
			{name: "flush", run: (m, c) -> m.flush()},
			{name: "reopen", run: (m, c) -> m.reopen()}
		],
		check: m -> m.check(),
		teardown: m -> m.dispose()
	}, {cases: 40, steps: 30}));
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

// (a record: its header and bytes)
private inline var HEADER = 25;

private typedef Kept = {segment:Int, width:Int, height:Int, bytes:Null<Bytes>};

// (the cache in a directory of its own and its model: segments as ids and
// sizes, the oldest first, and where each key's newest record is)
private class Model {
	final dir = helder.os.Paths.temp() + "/viewer-cache-" + Std.random(0x40000000);
	final keys = [for (k in 0...6) ThumbCache.key("f" + k, k, k, 256)];
	var cache:ThumbCache;
	var segments:Array<{id:Int, size:Int}> = [];
	final index = new Map<Int, Kept>();
	var next = 1;

	public function new()
		cache = new ThumbCache(192, 64, dir);

	public function put(k:Int, width:Int, height:Int, n:Int) {
		var bytes = n == 0 ? null : Bytes.alloc(n);
		if (bytes != null) bytes.fill(0, n, k * 16 + n);
		if (bytes == null) cache.putNone(keys[k]) else cache.put(keys[k], width, height, bytes);
		// (a record larger than a segment: not kept)
		if (HEADER + n <= 64) append(k, {segment: 0, width: width, height: height, bytes: bytes});
	}

	public function get(k:Int) {
		var e = index.get(k), hit = cache.get(keys[k]);
		equals(hit, e == null ? null : {width: e.width, height: e.height, bytes: e.bytes}, 'get($k)');
		if (e == null) return;
		// (an entry in the oldest quarter of the segments, not the newest: written again)
		var oldest = (segments.length + 3) >> 2;
		if (e.segment != segments[segments.length - 1].id && e.segment <= segments[oldest - 1].id) append(k, e);
	}

	public function flush()
		cache.flush();

	public function reopen() {
		cache.close();
		cache = new ThumbCache(192, 64, dir);
		assert(!cache.readOnly, "the owner");
		evict(0);
	}

	public function check() {
		var real:Array<{id:Int, size:Int}> = [for (s in @:privateAccess cache.segments) {id: s.id, size: s.size}];
		equals(real, segments, "segments");
		equals(@:privateAccess cache.used, 1.0 * used(), "used");
		var at = @:privateAccess cache.index;
		for (k in 0...6) {
			var e = at.get(@:privateAccess ThumbCache.name(keys[k])), m = index.get(k);
			equals(e == null ? null : e.segment.id, m == null ? null : m.segment, 'key $k\'s segment');
		}
	}

	public function dispose() {
		cache.close();
		for (f in FileSystem.readDirectory(dir))
			FileSystem.deleteFile(dir + "/" + f);
		FileSystem.deleteDirectory(dir);
	}

	function append(k:Int, e:Kept) {
		var n = HEADER + (e.bytes == null ? 0 : e.bytes.length);
		evict(n);
		if (used() + n > 192) return;
		var s = segments[segments.length - 1];
		if (s == null || n > 64 - s.size) segments.push(s = {id: next++, size: 0});
		s.size += n;
		index.set(k, {segment: s.id, width: e.width, height: e.height, bytes: e.bytes});
	}

	// (the oldest segments let go, with their records, until there is room)
	function evict(reserve:Int)
		while (used() + reserve > 192 && segments.length > 0) {
			var s = segments.shift();
			for (k => e in index)
				if (e.segment == s.id) index.remove(k);
		}

	function used():Int
		return Lambda.fold(segments, (s, n) -> n + s.size, 0);
}

