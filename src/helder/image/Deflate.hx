package helder.image;

import haxe.io.Bytes;

// Deflate (RFC 1951) and zlib's wrapper (RFC 1950), helder's one encoder:
// what PNG, zip, gzip and PDF write. One block of the fixed codes, LZ77 by
// a hash of three bytes and a short chain: pure Haxe, no zlib; written once
// by a build, so a smaller ratio than zlib -9's is the price. Inflate reads
// them.
class Deflate {
	// a zlib stream of data: one deflate block of the fixed codes, its Adler-32
	public static function zlib(data:Bytes):Bytes
		return encode(data, true);

	// the raw deflate stream (RFC 1951), no wrapper
	public static function raw(data:Bytes):Bytes
		return encode(data, false);

	static function encode(data:Bytes, zlib:Bool):Bytes {
		var w = new BitWriter(data.length >> 2);
		if (zlib) {
			w.bits(0x78, 8);
			w.bits(0x01, 8);
		}
		w.bits(1, 1); // the last block
		w.bits(1, 2); // fixed Huffman codes
		var n = data.length, HASH = 1 << 15, WINDOW = 32768;
		var head = new haxe.ds.Vector<Int>(HASH), prev = new haxe.ds.Vector<Int>(WINDOW);
		for (i in 0...HASH)
			head[i] = -1;
		inline function hash(i:Int):Int
			return ((data.get(i) << 10) ^ (data.get(i + 1) << 5) ^ data.get(i + 2)) & (HASH - 1);
		inline function insert(i:Int) {
			var h = hash(i);
			prev[i & (WINDOW - 1)] = head[h];
			head[h] = i;
		}
		var i = 0;
		while (i < n) {
			var bestLen = 0, bestDist = 0;
			if (i + 2 < n) {
				var cand = head[hash(i)], chain = 16, max = n - i < 258 ? n - i : 258;
				while (cand >= 0 && i - cand <= WINDOW && chain-- > 0) {
					var l = 0;
					while (l < max && data.get(cand + l) == data.get(i + l))
						l++;
					if (l > bestLen) {
						bestLen = l;
						bestDist = i - cand;
						if (l == max) break;
					}
					var p = prev[cand & (WINDOW - 1)];
					if (p >= cand) break;
					cand = p;
				}
			}
			if (bestLen >= 3) {
				w.length(bestLen);
				w.distance(bestDist);
				var end = i + bestLen;
				while (i < end) {
					if (i + 2 < n) insert(i);
					i++;
				}
			} else {
				w.literal(data.get(i));
				if (i + 2 < n) insert(i);
				i++;
			}
		}
		w.literal(256);
		w.flush();
		if (!zlib) return w.bytes();
		var a = haxe.crypto.Adler32.make(data);
		w.byte(a >>> 24);
		w.byte(a >> 16);
		w.byte(a >> 8);
		w.byte(a);
		return w.bytes();
	}
}

private class BitWriter {
	var out:haxe.io.BytesBuffer;
	var acc = 0;
	var count = 0;

	static final LENGTH_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
	static final LENGTH_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
	static final DIST_BASE = [
		1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
	];
	static final DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

	public function new(_:Int)
		out = new haxe.io.BytesBuffer();

	// n bits of v, least significant first
	public inline function bits(v:Int, n:Int) {
		acc |= (v & ((1 << n) - 1)) << count;
		count += n;
		while (count >= 8) {
			out.addByte(acc & 0xFF);
			acc >>>= 8;
			count -= 8;
		}
	}

	// a Huffman code: its bits most significant first
	inline function code(c:Int, n:Int) {
		var r = 0;
		for (k in 0...n)
			r |= ((c >> k) & 1) << (n - 1 - k);
		bits(r, n);
	}

	// a literal or the end (256) or a length's symbol, in the fixed codes
	public function literal(v:Int) {
		if (v < 144) code(0x30 + v, 8) else if (v < 256) code(0x190 + v - 144, 9) else if (v < 280) code(v - 256, 7) else code(0xC0 + v - 280, 8);
	}

	public function length(l:Int) {
		var k = 28;
		while (LENGTH_BASE[k] > l)
			k--;
		literal(257 + k);
		if (LENGTH_EXTRA[k] > 0) bits(l - LENGTH_BASE[k], LENGTH_EXTRA[k]);
	}

	public function distance(d:Int) {
		var k = 29;
		while (DIST_BASE[k] > d)
			k--;
		code(k, 5);
		if (DIST_EXTRA[k] > 0) bits(d - DIST_BASE[k], DIST_EXTRA[k]);
	}

	public function flush() {
		if (count > 0) out.addByte(acc & 0xFF);
		acc = 0;
		count = 0;
	}

	public inline function byte(b:Int)
		out.addByte(b & 0xFF);

	public function bytes():Bytes
		return out.getBytes();
}
