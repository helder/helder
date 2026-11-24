package viewer;

import haxe.Int64;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import helder.os.Paths;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;
import sys.thread.Mutex;

typedef ThumbHit = {
	width:Int,
	height:Int,
	// (null: a negative hit; no entry at all is a miss)
	bytes:Null<Bytes>
}

private typedef Segment = {
	id:Int,
	path:String,
	size:Int,
	// (a damaged suffix is never appended to)
	end:Int,
	stamp:Float,
	keys:Array<String>
}

private typedef ThumbEntry = {
	key:Int64,
	segment:Segment,
	offset:Int,
	length:Int,
	width:Int,
	height:Int,
	flags:Int
}

// The viewer's own thumbnails, in append-only segments. One owner writes;
// another process can read the entries it found on open. The index is a
// snapshot of the log, replaced whole after the segments have been flushed.
class ThumbCache {
	static inline var MAGIC = 0x314D4854; // THM1
	static inline var HEADER = 25;
	static inline var VERSION = 1;
	static inline var NEGATIVE = 1;
	static inline var KEEP = 4;

	public final directory:Null<String>;
	public var readOnly(get, never):Bool;

	final budget:Int;
	final segmentSize:Int;
	final mutex = new Mutex();
	final segments:Array<Segment> = [];
	final byId = new Map<Int, Segment>();
	final index = new Map<String, ThumbEntry>();
	final readers:Array<{id:Int, file:FileInput}> = [];
	var owner:Null<ThumbCacheLock>;
	var writer:Null<FileOutput>;
	var nextId = 1;
	var used = 0.0;
	var dirty = false;
	var closed = false;

	public function new(budget = 512 << 20, segmentSize = 16 << 20, ?directory:String) {
		this.budget = budget;
		this.segmentSize = segmentSize;
		var base = directory == null ? Paths.cache() : null;
		this.directory = directory ?? (base == null ? null : base + "/thumbs");
		if (this.directory == null || segmentSize < HEADER || budget < HEADER) return;
		try {
			FileSystem.createDirectory(this.directory);
			owner = ThumbCacheLock.take(this.directory + "/lock");
			listSegments();
			if (!loadIndex()) rebuild();
			if (owner != null) evict();
		} catch (_:Dynamic) {
			if (owner != null) owner.close();
			owner = null;
		}
	}

	function get_readOnly():Bool {
		mutex.acquire();
		var readOnly = owner == null;
		mutex.release();
		return readOnly;
	}

	// FNV-1a over the UTF-8 file identity and requested side.
	public static function key(path:String, size:Float, mtime:Float, side:Int):Int64 {
		var b = Bytes.ofString(path + "\x00" + size + "\x00" + mtime + "\x00" + side);
		var hash = Int64.make(0xCBF29CE4, 0x84222325), prime = Int64.make(0x100, 0x1B3);
		for (i in 0...b.length)
			hash = (hash ^ Int64.ofInt(b.get(i))) * prime;
		return hash;
	}

	static inline function name(key:Int64):String
		return StringTools.hex(key.high, 8) + StringTools.hex(key.low, 8);

	public function get(key:Int64):Null<ThumbHit> {
		mutex.acquire();
		var hit = try read(key) catch (_:Dynamic) null;
		mutex.release();
		return hit;
	}

	function read(key:Int64):Null<ThumbHit> {
		if (closed) return null;
		var k = name(key), entry = index.get(k);
		if (entry == null) return null;
		var record = try readRecord(entry) catch (_:Dynamic) null;
		if (record == null) {
			var s = entry.segment;
			if (entry.offset < s.end) s.end = entry.offset;
			for (key in s.keys) {
				var e = index.get(key);
				if (e != null && e.segment == s && e.offset >= s.end) index.remove(key);
			}
			dirty = true;
			return null;
		}
		// (round the quarter up on a small cache; appending to the same
		// segment would not move the entry ahead of an eviction)
		var oldest = (segments.length + 3) >> 2;
		if (owner != null && entry.segment != segments[segments.length - 1] && entry.segment.id <= segments[oldest - 1].id)
			try append(k, entry, record) catch (_:Dynamic) {}
		return {width: entry.width, height: entry.height, bytes: entry.flags == NEGATIVE ? null : record.sub(HEADER, entry.length)};
	}

	function readRecord(entry:ThumbEntry):Null<Bytes> {
		var file = reader(entry.segment), record = Bytes.alloc(HEADER + entry.length);
		file.seek(entry.offset, SeekBegin);
		file.readFullBytes(record, 0, record.length);
		return record.getInt32(0) == MAGIC && record.getInt64(4) == entry.key && record.get(12) == entry.flags
			&& record.getUInt16(13) == entry.width && record.getUInt16(15) == entry.height && record.getInt32(17) == entry.length
			&& record.getInt32(21) == checksum(record, record, HEADER, entry.length) ? record : null;
	}

	public function put(key:Int64, width:Int, height:Int, jpeg:Bytes) {
		if (width > 0 && width <= 0xFFFF && height > 0 && height <= 0xFFFF && jpeg.length > 0)
			store(key, width, height, jpeg);
	}

	public function putNone(key:Int64)
		store(key, 0, 0, null);

	function store(key:Int64, width:Int, height:Int, jpeg:Null<Bytes>) {
		var n = jpeg == null ? 0 : jpeg.length;
		if (n > segmentSize - HEADER || n > budget - HEADER) return;
		mutex.acquire();
		try {
			if (owner != null) {
				var flags = jpeg == null ? NEGATIVE : 0, record = Bytes.alloc(HEADER + n);
				record.setInt32(0, MAGIC);
				record.setInt64(4, key);
				record.set(12, flags);
				record.setUInt16(13, width);
				record.setUInt16(15, height);
				record.setInt32(17, n);
				if (jpeg != null) record.blit(HEADER, jpeg, 0, n);
				record.setInt32(21, checksum(record, record, HEADER, n));
				append(name(key), {key: key, segment: null, offset: 0, length: n, width: width, height: height, flags: flags}, record);
			}
		} catch (_:Dynamic) {}
		mutex.release();
	}

	function append(k:String, entry:ThumbEntry, record:Bytes) {
		evict(record.length);
		if (used + record.length > budget) return;
		var s = segments[segments.length - 1];
		if (s == null || s.end != s.size || record.length > segmentSize - s.size) {
			finishWriting();
			s = addSegment(nextId++, 0, 0);
		}
		var at = s.size;
		dirty = true;
		try {
			if (writer == null) writer = File.append(s.path, true);
			writer.writeFullBytes(record, 0, record.length);
		} catch (e:Dynamic) {
			// (a partial write is still on disk, but seals this segment)
			finishWriting();
			s.size = FileSystem.exists(s.path) ? FileSystem.stat(s.path).size : 0;
			used += s.size - at;
			throw e;
		}
		s.size += record.length;
		s.end = s.size;
		used += record.length;
		remember(k, {key: entry.key, segment: s, offset: at, length: entry.length, width: entry.width, height: entry.height, flags: entry.flags});
	}

	function remember(k:String, entry:ThumbEntry) {
		var prior = index.get(k);
		if (prior == null || prior.segment != entry.segment) entry.segment.keys.push(k);
		index.set(k, entry);
	}

	function reader(s:Segment):FileInput {
		for (i in 0...readers.length) {
			var r = readers[i];
			if (r.id != s.id) continue;
			readers.splice(i, 1);
			readers.push(r);
			return r.file;
		}
		var file = ThumbCacheLock.openReader(s.path);
		readers.push({id: s.id, file: file});
		if (readers.length > KEEP) readers.shift().file.close();
		return file;
	}

	function evict(reserve = 0) {
		while (used + reserve > budget && segments.length > 0) {
			var s = segments[0];
			if (segments.length == 1) finishWriting();
			for (r in readers.copy())
				if (r.id == s.id) {
					r.file.close();
					readers.remove(r);
				}
			// (e.g. a reader in another process on Windows can hold it
			// open; keep its bytes in the budget and retry on the next write)
			try FileSystem.deleteFile(s.path) catch (_:Dynamic) {
				if (FileSystem.exists(s.path)) return;
			}
			segments.shift();
			byId.remove(s.id);
			used -= s.size;
			for (k in s.keys) {
				var entry = index.get(k);
				if (entry != null && entry.segment == s) index.remove(k);
			}
			dirty = true;
		}
	}

	function addSegment(id:Int, size:Int, stamp:Float):Segment {
		var s = {id: id, path: directory + "/seg-" + StringTools.lpad(Std.string(id), "0", 10), size: size, end: size, stamp: stamp, keys: []};
		segments.push(s);
		byId.set(id, s);
		used += size;
		return s;
	}

	function listSegments() {
		var ids = [];
		for (file in FileSystem.readDirectory(directory)) {
			if (file.length != 14 || !StringTools.startsWith(file, "seg-")) continue;
			var id = Std.parseInt(file.substr(4));
			if (id != null && id > 0 && file == "seg-" + StringTools.lpad(Std.string(id), "0", 10)) ids.push(id);
		}
		ids.sort(Reflect.compare);
		for (id in ids) {
			var path = directory + "/seg-" + StringTools.lpad(Std.string(id), "0", 10);
			var stat = try FileSystem.stat(path) catch (_:Dynamic) null;
			if (stat != null && !FileSystem.isDirectory(path) && stat.size >= 0) addSegment(id, stat.size, stat.mtime.getTime());
			nextId = id + 1;
		}
	}

	function rebuild() {
		index.clear();
		for (s in segments) {
			s.keys.resize(0);
			s.end = 0;
			try {
				var f = reader(s), header = Bytes.alloc(HEADER);
				f.seek(0, SeekBegin);
				while (s.end <= s.size - HEADER) {
					f.readFullBytes(header, 0, HEADER);
					if (header.getInt32(0) != MAGIC) break;
					var e = unpack(header, 4, s, s.end);
					if (!valid(e) || e.length > s.size - s.end - HEADER) break;
					var bytes = f.read(e.length);
					if (header.getInt32(21) != checksum(header, bytes, 0, e.length)) break;
					remember(name(e.key), e);
					s.end += HEADER + e.length;
				}
			} catch (_:Dynamic) {}
		}
		dirty = true;
	}

	// (key, flags, width, height and length have the same layout in both files)
	static function unpack(b:Bytes, p:Int, s:Segment, offset:Int):ThumbEntry
		return {key: b.getInt64(p), segment: s, offset: offset, flags: b.get(p + 8), width: b.getUInt16(p + 9),
			height: b.getUInt16(p + 11), length: b.getInt32(p + 13)};

	static inline function valid(e:ThumbEntry):Bool
		return e.flags == NEGATIVE ? e.width == 0 && e.height == 0 && e.length == 0
			: e.flags == 0 && e.width > 0 && e.height > 0 && e.length > 0;

	static function checksum(header:Bytes, bytes:Bytes, at:Int, n:Int):Int {
		var crc = new Crc32();
		crc.update(header, 0, 21);
		crc.update(bytes, at, n);
		return crc.get();
	}

	function loadIndex():Bool {
		var path = directory + "/index";
		var b = try {
			var newest = segments[segments.length - 1];
			if (newest != null && newest.stamp > FileSystem.stat(path).mtime.getTime()) return false;
			File.getBytes(path);
		} catch (_:Dynamic) return false;
		if (b.length < 20 || b.getInt32(0) != VERSION || b.getInt32(4) != segments.length) return false;
		var end = b.length - 4, p = 16, count = b.getInt32(8), next = b.getInt32(12);
		if (segments.length > Std.int((end - p) / 20) || next < nextId) return false;
		var crc = new Crc32();
		crc.update(b, 0, end);
		if (crc.get() != b.getInt32(end)) return false;
		for (s in segments) {
			var n = b.getInt32(p + 8);
			if (b.getInt32(p) != s.id || b.getInt32(p + 4) != s.size || b.getDouble(p + 12) != s.stamp || n < 0 || n > s.size) return false;
			s.end = n;
			p += 20;
		}
		if (count < 0 || count != (end - p) / 25) return false;
		for (_ in 0...count) {
			var s = byId.get(b.getInt32(p)), offset = b.getInt32(p + 4);
			if (s == null || offset < 0) return false;
			var e = unpack(b, p + 8, s, offset);
			if (!valid(e) || offset > s.end - HEADER || e.length > s.end - HEADER - offset) return false;
			remember(name(e.key), e);
			p += 25;
		}
		nextId = next;
		return true;
	}

	public function flush() {
		mutex.acquire();
		try saveIndex() catch (_:Dynamic) {}
		mutex.release();
	}

	function saveIndex() {
		if (owner == null || !dirty) return;
		finishWriting();
		evict();
		var count = 0;
		for (_ in index) count++;
		var b = Bytes.alloc(20 + segments.length * 20 + count * 25);
		b.setInt32(0, VERSION);
		b.setInt32(4, segments.length);
		b.setInt32(8, count);
		b.setInt32(12, nextId);
		var p = 16;
		for (s in segments) {
			var stamp = FileSystem.stat(s.path).mtime.getTime();
			b.setInt32(p, s.id);
			b.setInt32(p + 4, s.size);
			b.setInt32(p + 8, s.end);
			b.setDouble(p + 12, stamp);
			p += 20;
		}
		for (e in index) {
			b.setInt32(p, e.segment.id);
			b.setInt32(p + 4, e.offset);
			b.setInt64(p + 8, e.key);
			b.set(p + 16, e.flags);
			b.setUInt16(p + 17, e.width);
			b.setUInt16(p + 19, e.height);
			b.setInt32(p + 21, e.length);
			p += 25;
		}
		var crc = new Crc32();
		crc.update(b, 0, p);
		b.setInt32(p, crc.get());
		var path = directory + "/index";
		File.saveBytes(path + ".tmp", b);
		FileSystem.rename(path + ".tmp", path);
		dirty = false;
	}

	function finishWriting() {
		if (writer == null) return;
		var file = writer;
		writer = null;
		try file.flush() catch (e:Dynamic) {
			file.close();
			throw e;
		}
		file.close();
	}

	public function close() {
		mutex.acquire();
		if (!closed) {
			closed = true;
			try saveIndex() catch (_:Dynamic) {}
			if (writer != null) writer.close();
			writer = null;
			for (r in readers) r.file.close();
			readers.resize(0);
			if (owner != null) owner.close();
			owner = null;
		}
		mutex.release();
	}
}
