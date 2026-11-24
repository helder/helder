package helder.image;

import haxe.io.Bytes;

// EXIF's orientation (tag 0x112 of IFD0), and JPEG previews from JPEG,
// TIFF-based camera files and RAF. All offsets are relative to their
// container and checked against the bytes available.
class Exif {
	// a JPEG's or WebP's orientation (1 when it has none, or another file)
	public static function orientation(bytes:Bytes):Int {
		var file = new ByteReader(bytes), n = file.length;
		if (n >= 2 && file.u8(0) == 0xFF && file.u8(1) == 0xD8) return jpegOrientation(bytes, 0, n);
		if (n >= 8 && tiffMagic(file, 0) != 0) return tiff(bytes, 0, n);
		if (n >= 20 && file.string(0, 4) == "RIFF" && file.string(8, 4) == "WEBP") {
			var p = 12;
			while (p + 8 <= n) {
				var size = file.u8(p + 4) | (file.u8(p + 5) << 8) | (file.u8(p + 6) << 16) | (file.u8(p + 7) << 24), at = p + 8;
				if (size < 0 || size > n - at) return 1;
				if (file.string(p, 4) == "EXIF") {
					// (some writers keep JPEG's "Exif\0\0" before the TIFF header)
					var t = size >= 6 && file.string(at, 4) == "Exif" ? at + 6 : at;
					return tiff(bytes, t, at + size);
				}
				p = at + size + (size & 1);
			}
		}
		return 1;
	}

	@:allow(helder.image.Image) static function jpegOrientation(bytes:Bytes, offset:Int, length:Int):Int {
		var block = jpegExif(new ByteReader(bytes), offset, length);
		return block == null ? 1 : tiff(bytes, block.start, offset + length < block.end ? offset + length : block.end);
	}

	// (the first Exif APP1 before the first scan; its declared end can
	// lie beyond the prefix the caller has supplied)
	static function jpegExif(b:ByteReader, offset:Int, length:Int):Null<{start:Int, end:Int}> {
		var p = offset + 2, end = offset + length;
		while (end - p >= 4 && b.u8(p) == 0xFF) {
			var m = b.u8(p + 1);
			if (m == 0xFF) {
				p++;
				continue;
			}
			if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
				p += 2;
				continue;
			}
			if (m == 0xDA || m == 0xD9 || m == 0) break;
			var len = (b.u8(p + 2) << 8) | b.u8(p + 3);
			if (len < 2 || p > 0x7FFFFFFF - 2 - len) break;
			var next = p + 2 + len;
			if (m == 0xE1 && len >= 8 && end - p >= 10 && b.string(p + 4, 4) == "Exif" && b.u8(p + 8) == 0 && b.u8(p + 9) == 0)
				return {start: p + 10, end: next};
			p = next;
		}
		return null;
	}

	// JPEGs wholly within the supplied prefix, smallest by pixel area first.
	public static function previews(bytes:Bytes):Array<{offset:Int, length:Int, width:Int, height:Int}> {
		var found = [], b = new ByteReader(bytes);
		previewRanges(bytes, (at, n) -> {
			if (at > bytes.length - n || b.u8(at) != 0xFF || b.u8(at + 1) != 0xD8
				|| b.u8(at + n - 2) != 0xFF || b.u8(at + n - 1) != 0xD9) return;
			var size = JpegDecoder.size(bytes, at, n);
			if (size != null) found.push({offset: at, length: n, width: size.width, height: size.height});
		});
		found.sort((a, b) -> {
			var area = Reflect.compare(a.width * (a.height : Float), b.width * (b.height : Float));
			return area != 0 ? area : Reflect.compare(a.offset, b.offset);
		});
		return found;
	}

	// The end of the farthest preview declared by directories in the prefix.
	// A declaration beyond the prefix can only be checked once it is read.
	public static function previewsNeed(bytes:Bytes):Int {
		var need = 0;
		previewRanges(bytes, (at, n) -> if (at + n > need) need = at + n);
		return need;
	}

	static function previewRanges(bytes:Bytes, range:(Int, Int)->Void) {
		var b = new ByteReader(bytes), seen = new Map<String, Bool>();
		function add(at:Int, n:Int) {
			if (at < 0 || n < 4 || at > 0x7FFFFFFF - n) return;
			var key = at + ":" + n;
			if (seen.exists(key)) return;
			seen.set(key, true);
			range(at, n);
		}
		if (b.length >= 2 && b.u8(0) == 0xFF && b.u8(1) == 0xD8) {
			var block = jpegExif(b, 0, b.length);
			if (block != null) tiffRanges(b, block.start, block.end, true, add);
		} else if (b.length >= 92 && b.string(0, 15) == "FUJIFILMCCD-RAW") {
			var at = word(b, 84, false), n = word(b, 88, false);
			if (at >= 92) add(at, n);
		} else if (b.length >= 8) tiffRanges(b, 0, b.length, false, add);
	}

	static function tiffRanges(b:ByteReader, start:Int, end:Int, thumbnailOnly:Bool, add:(Int, Int)->Void) {
		var size = Std.int(Math.min(end, b.length)) - start;
		if (size < 8 || tiffMagic(b, start) == 0) return;
		var le = b.u8(start) == 0x49;
		inline function u16(at:Int):Int
			return halfword(b, start + at, le);
		inline function u32(at:Int):Int
			return word(b, start + at, le);
		var ifd0 = u32(4), pending = [], visited = new Map<Int, Bool>();
		function enqueue(ifd:Int) {
			if (ifd < 8 || ifd > size - 2 || visited.exists(ifd)) return;
			visited.set(ifd, true);
			pending.push(ifd);
		}
		enqueue(ifd0);
		// (a damaged TIFF can point many IFDs at overlapping tables)
		var remaining = size;
		while (pending.length > 0 && remaining > 0) {
			var ifd = pending.pop();
			var count = u16(ifd), first = ifd + 2, available = Std.int((size - first) / 12);
			if (count * 12 <= size - first - 4 && (!thumbnailOnly || ifd == ifd0)) enqueue(u32(first + count * 12));
			if (thumbnailOnly && ifd == ifd0) continue;
			var jpeg = -1, length = -1, strip = -1, stripLength = -1, compression = 0;
			for (i in 0...(count < available ? count : available)) {
				if (--remaining < 0) break;
				var e = first + i * 12;
				var tag = u16(e), type = u16(e + 2), n = u32(e + 4);
				if (tag == 0x014A && !thumbnailOnly && (type == 4 || type == 13) && n > 0) {
					var table = n == 1 ? e + 8 : u32(e + 8);
					if (table >= 8 && table <= size - 4) for (j in 0...Std.int(Math.min(n, (size - table) >> 2))) {
						if (--remaining < 0) break;
						enqueue(u32(table + 4 * j));
					}
				}
				if (n != 1 || (type != 3 && type != 4)) continue;
				var v = type == 3 ? u16(e + 8) : u32(e + 8);
				switch tag {
					case 0x0201: jpeg = v;
					case 0x0202: length = v;
					case 0x0111: strip = v;
					case 0x0117: stripLength = v;
					case 0x0103: compression = v;
					case _:
				}
			}
			inline function collect(at:Int, n:Int) {
				if (at >= 8 && at <= 0x7FFFFFFF - start && (!thumbnailOnly || (n >= 4 && at <= end - start - n))) {
					var p = start + at;
					if (p > b.length - 2 || (b.u8(p) == 0xFF && b.u8(p + 1) == 0xD8)) add(p, n);
				}
			}
			collect(jpeg, length);
			if (!thumbnailOnly && (compression == 6 || compression == 7)) collect(strip, stripLength);
		}
	}

	static inline function halfword(b:ByteReader, at:Int, le:Bool):Int
		return le ? b.u8(at) | (b.u8(at + 1) << 8) : (b.u8(at) << 8) | b.u8(at + 1);

	static inline function word(b:ByteReader, at:Int, le:Bool):Int
		return le ? halfword(b, at, le) | (halfword(b, at + 2, le) << 16) : (halfword(b, at, le) << 16) | halfword(b, at + 2, le);

	static function tiffMagic(b:ByteReader, start:Int):Int {
		var le = b.u8(start) == 0x49 && b.u8(start + 1) == 0x49;
		if (!le && !(b.u8(start) == 0x4D && b.u8(start + 1) == 0x4D)) return 0;
		var m = halfword(b, start + 2, le);
		return m == 42 || m == 0x4F52 || m == 0x5352 || (le && m == 0x55) ? m : 0;
	}

	// the orientation in a TIFF block at [start, end) of b (1 when none)
	public static function tiff(bytes:Bytes, start:Int, end:Int):Int {
		var b = new ByteReader(bytes);
		if (!b.has(start, 8) || end > b.length || end < start + 8) return 1;
		var le = b.u8(start) == 0x49 && b.u8(start + 1) == 0x49;
		if (!le && !(b.u8(start) == 0x4D && b.u8(start + 1) == 0x4D)) return 1;
		inline function r16(q:Int):Int
			return le ? b.u8(q) | (b.u8(q + 1) << 8) : (b.u8(q) << 8) | b.u8(q + 1);
		inline function r32(q:Int):Float
			return le ? r16(q) + r16(q + 2) * 65536.0 : r16(q) * 65536.0 + r16(q + 2);
		if (tiffMagic(b, start) == 0) return 1;
		// (IFD0's offset from the block's start, unsigned: within it)
		var off = r32(start + 4), size = end - start;
		if (off < 8 || off + 2 > size) return 1;
		var ifd = start + Std.int(off), count = r16(ifd), first = ifd + 2;
		for (i in 0...Std.int(Math.min(count, (end - first) / 12))) {
			var e = first + 12 * i;
			// (SHORT, one value: in the entry itself)
			if (r16(e) == 0x112) {
				var v = r16(e + 2) == 3 ? r16(e + 8) : 1;
				return v >= 1 && v <= 8 ? v : 1;
			}
		}
		return 1;
	}

	// whether orientation o swaps the width and the height
	public static inline function swaps(o:Int):Bool
		return o >= 5 && o <= 8;

	// w x h RGBA8 pixels in orientation o shown upright: new pixels (the
	// same when o is 1), the width and height swapped for 5 to 8
	public static function apply(rgba:Bytes, width:Int, height:Int, o:Int, ?mem:ImageMemory):{width:Int, height:Int, rgba:Bytes} {
		if (o < 2 || o > 8) return {width: width, height: height, rgba: rgba};
		var w = swaps(o) ? height : width, h = swaps(o) ? width : height;
		var out = (mem ?? ImageMemory.gc).bytes(w * h * 4);
		for (y in 0...height)
			if (GcPoint.yes()) for (x in 0...width) {
				var dx:Int, dy:Int;
				switch o {
					case 2: dx = width - 1 - x; dy = y;
					case 3: dx = width - 1 - x; dy = height - 1 - y;
					case 4: dx = x; dy = height - 1 - y;
					case 5: dx = y; dy = x;
					case 6: dx = height - 1 - y; dy = x;
					case 7: dx = height - 1 - y; dy = width - 1 - x;
					case _: dx = y; dy = width - 1 - x;
				}
				out.setInt32(4 * (dy * w + dx), rgba.getInt32(4 * (y * width + x)));
			}
		return {width: w, height: h, rgba: out};
	}
}
