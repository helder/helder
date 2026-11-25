package helder.image;

import haxe.io.Bytes;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.UInt8;

// Deflate's streams (RFC 1951) inflated, raw or in zlib's wrapper (RFC
// 1950): helder's one inflater, what PNG, zip and PDF read. A kernel (@:hxmc.kernel,
// as PngCore's decoding: no GC object touched, memory through checked
// spans), so a job inflates off the heap as PngCore does: a 32-bit bit
// buffer, codes up to 10 bits by table, longer ones from their canonical
// counts. Its frame is a scratch of SCRATCH bytes, so inflates on several
// threads are independent and none allocates; Bytes in and out:
// exact (zip's entries, their size known) and all (PDF's
// streams: grown as they go, what decodes of a damaged one). Deflate
// writes them.
class Inflate {
	public static inline var ERR_SHORT = -9;
	public static inline var ERR_DATA = -12;
	public static inline var ERR_FULL = -15;

	// a deflate stream (zlib: in zlib's wrapper) of exactly size bytes
	public static function exact(data:Bytes, size:Int, zlib:Bool):Bytes {
		var out = Bytes.alloc(size), scratch = Bytes.alloc(SCRATCH);
		var n = inflate(Span.ofBytes(scratch), ReadOnlySpan.ofBytes(data), 0, data.length, false, zlib, Span.ofBytes(out));
		if (n != size) throw n == ERR_FULL ? "a deflated stream longer than its size" : n < 0 ? "a deflated stream that does not decode" : "a deflated stream shorter than its size";
		return out;
	}

	// a deflate stream of any size, zlib's or raw (its first two bytes
	// tell): null past budget bytes; a damaged or cut stream gives what
	// decoded of it
	public static function all(data:Bytes, budget:Int):Null<Bytes> {
		var zlib = data.length >= 2 && data.get(0) & 15 == 8 && ((data.get(0) << 8) | data.get(1)) % 31 == 0;
		var scratch = Bytes.alloc(SCRATCH), size = data.length * 4 < 65536 ? 65536 : data.length * 4;
		while (true) {
			if (size > budget) size = budget;
			var out = Bytes.alloc(size);
			var n = inflate(Span.ofBytes(scratch), ReadOnlySpan.ofBytes(data), 0, data.length, false, zlib, Span.ofBytes(out));
			if (n >= 0) return out.sub(0, n);
			if (n != ERR_FULL) return out.sub(0, produced(Span.ofBytes(scratch)));
			if (size >= budget) return null;
			size = size > budget >> 1 ? budget : size * 2;
		}
	}

	// the scratch (SCRATCH bytes) holds the state
	// (a Bits) in its first STATE bytes, then Ints: each code's table (1024
	// entries), counts (16) and symbols (288), the code lengths (320), and
	// the fixed codes, built at the first block that uses them (fixed)

	static inline var FAST = 10;
	static inline var TABLE = 1 << FAST;
	static inline var COUNTS = TABLE;
	static inline var SYMBOLS = COUNTS + 16;
	static inline var CODE = SYMBOLS + 288;
	static inline var STATE = 64;
	static inline var LIT = STATE >> 2;
	static inline var DIST = LIT + CODE;
	static inline var CL = DIST + CODE;
	static inline var LENS = CL + CODE;
	static inline var FIXED_LIT = LENS + 320;
	static inline var FIXED_DIST = FIXED_LIT + CODE;
	public static inline var SCRATCH = 4 * (FIXED_DIST + CODE);

	// (the fixed codes, into the scratch: once an inflate)
	@:hxmc.kernel static function fixed(scratch:Span<UInt8>) {
		var words:Span<Int> = scratch.reinterpret();
		var l = words.sub(LENS, 320);
		for (i in 0...288)
			l[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
		build(words.sub(FIXED_LIT, CODE), l, 288);
		for (i in 0...30)
			l[i] = 5;
		build(words.sub(FIXED_DIST, CODE), l, 30);
	}

	// (an inflate's failure: the data ended early, the output is full, or it does not decode)
	static inline function failed(st:Span<Bits>):Int
		return st[0].bad == 2 ? ERR_SHORT : st[0].bad == 3 ? ERR_FULL : ERR_DATA;

	// a deflate stream at src's [at, end) (zlib: in zlib's wrapper, its
	// Adler-32 checked; chunked: continued by a PNG's IDAT chunks after it)
	// inflated into out: the bytes produced, or an error (what was produced
	// until then: produced)
	@:hxmc.kernel public static function inflate(scratch:Span<UInt8>, src:ReadOnlySpan<UInt8>, at:Int, end:Int, chunked:Bool, zlib:Bool, out:Span<UInt8>):Int {
		var words:Span<Int> = scratch.reinterpret();
		var st:Span<Bits> = scratch.sub(0, STATE).reinterpret();
		var lit = words.sub(LIT, CODE), dist = words.sub(DIST, CODE), cl = words.sub(CL, CODE), l = words.sub(LENS, 320);
		var flit = words.sub(FIXED_LIT, CODE), fdist = words.sub(FIXED_DIST, CODE);
		st[0].buf = 0;
		st[0].cnt = 0;
		st[0].p = at;
		st[0].end = end;
		st[0].pos = 0;
		st[0].bad = 0;
		st[0].chunked = chunked ? 1 : 0;
		if (zlib) {
			var cmf = bits(st, src, 8), flg = bits(st, src, 8);
			if (st[0].bad != 0 || st[0].p > st[0].end || cmf & 15 != 8 || ((cmf << 8) + flg) % 31 != 0 || flg & 32 != 0) return ERR_DATA;
		}
		var last = false, fixedBuilt = false;
		while (!last) {
			last = bits(st, src, 1) == 1;
			var type = bits(st, src, 2);
			if (type == 0) {
				// (stored: from the next byte, the bit buffer's whole bytes first)
				var skip = st[0].cnt & 7;
				st[0].buf = st[0].buf >>> skip;
				st[0].cnt -= skip;
				var len = bits(st, src, 16), nlen = bits(st, src, 16), pos = st[0].pos;
				if (st[0].bad != 0 || nlen != 0xFFFF - len) return ERR_DATA;
				if (pos + len > out.length) return ERR_FULL;
				while (len > 0 && st[0].cnt >= 8) {
					out[pos++] = bits(st, src, 8);
					len--;
				}
				while (len > 0) {
					var p = st[0].p, e = st[0].end;
					if (p >= e) {
						if (st[0].chunked == 0) return ERR_DATA;
						hop(st, src);
						continue;
					}
					var k = e - p < len ? e - p : len;
					out.blit(pos, src, p, k);
					pos += k;
					len -= k;
					st[0].p = p + k;
				}
				st[0].pos = pos;
			} else if (type == 1) {
				if (!fixedBuilt) {
					fixed(scratch);
					fixedBuilt = true;
				}
				if (!block(st, src, out, flit, fdist)) return failed(st);
			} else if (type == 2) {
				var hlit = bits(st, src, 5) + 257, hdist = bits(st, src, 5) + 1, hclen = bits(st, src, 4) + 4;
				l.fill(0, 19, 0);
				for (i in 0...hclen)
					l[order(i)] = bits(st, src, 3);
				build(cl, l, 19);
				var i = 0, total = hlit + hdist;
				while (i < total) {
					var sym = symbol(st, src, cl);
					if (sym < 16) l[i++] = sym else {
						var v = 0, r = 0;
						if (sym == 16) {
							if (i == 0) return ERR_DATA;
							v = l[i - 1];
							r = 3 + bits(st, src, 2);
						} else r = sym == 17 ? 3 + bits(st, src, 3) : 11 + bits(st, src, 7);
						if (i + r > total) return ERR_DATA;
						l.fill(i, r, v);
						i += r;
					}
					if (st[0].bad != 0) return failed(st);
				}
				build(lit, l, hlit);
				build(dist, l.sub(hlit, hdist), hdist);
				if (!block(st, src, out, lit, dist)) return failed(st);
			} else
				return ERR_DATA;
			if (st[0].bad != 0) return failed(st);
		}
		if (!zlib) return st[0].pos;
		// (zlib's Adler-32 of the output, big-endian, after the stream, from the next byte)
		var skip = st[0].cnt & 7;
		st[0].buf = st[0].buf >>> skip;
		st[0].cnt -= skip;
		var want = bits(st, src, 8) << 24;
		want |= bits(st, src, 8) << 16;
		want |= bits(st, src, 8) << 8;
		want |= bits(st, src, 8);
		// (no byte of it past the input's end)
		if (st[0].bad != 0 || st[0].p - (st[0].cnt >> 3) > st[0].end) return ERR_DATA;
		var pos = st[0].pos;
		if (adler(out.sub(0, pos)) != want) return ERR_DATA;
		return pos;
	}

	// one block's symbols with the codes lit and dist: false when it does
	// not decode. The hot loop: the bit buffer in locals (st's on the way
	// out, and around slow), refilled to 25 bits or more before a literal or
	// length (15 bits at most, its extra bits 5) and before a distance (15,
	// then 13); the tables' length tested, so that their masked lookups
	// are unchecked.
	@:hxmc.kernel static function block(st:Span<Bits>, src:ReadOnlySpan<UInt8>, out:Span<UInt8>, lit:ReadOnlySpan<Int>, dist:ReadOnlySpan<Int>):Bool {
		if (lit.length < TABLE || dist.length < TABLE) return false;
		var pos = st[0].pos, cap = out.length;
		var buf = st[0].buf, cnt = st[0].cnt, p = st[0].p, end = st[0].end, ok = false;
		while (true) {
			while (cnt <= 24) {
				if (p < end) {
					buf |= src[p] << cnt;
					p++;
					cnt += 8;
				} else if (st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				} else {
					// (past the input's end: zeros, a few)
					if (p >= end + 4) break;
					p++;
					cnt += 8;
				}
			}
			var e = lit[buf & (TABLE - 1)], sym = 0;
			if (e != 0) {
				var len = e >> 9;
				buf >>>= len;
				cnt -= len;
				sym = e & 511;
			} else {
				st[0].buf = buf;
				st[0].cnt = cnt;
				st[0].p = p;
				sym = slow(st, src, lit);
				buf = st[0].buf;
				cnt = st[0].cnt;
				p = st[0].p;
				end = st[0].end;
			}
			if (sym < 256) {
				if (pos >= cap) {
					st[0].bad = 3;
					break;
				}
				out[pos++] = sym;
				continue;
			}
			if (sym == 256) {
				ok = true;
				break;
			}
			var k = sym - 257;
			if (k >= 29 || cnt < 5) break;
			var x = lengthExtra(k), len = lengthBase(k) + (buf & ((1 << x) - 1));
			buf >>>= x;
			cnt -= x;
			while (cnt <= 24) {
				if (p < end) {
					buf |= src[p] << cnt;
					p++;
					cnt += 8;
				} else if (st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				} else {
					// (past the input's end: zeros, a few)
					if (p >= end + 4) break;
					p++;
					cnt += 8;
				}
			}
			var e = dist[buf & (TABLE - 1)], d = 0;
			if (e != 0) {
				var n = e >> 9;
				buf >>>= n;
				cnt -= n;
				d = e & 511;
			} else {
				st[0].buf = buf;
				st[0].cnt = cnt;
				st[0].p = p;
				d = slow(st, src, dist);
				buf = st[0].buf;
				cnt = st[0].cnt;
				p = st[0].p;
				end = st[0].end;
			}
			if (d >= 30) break;
			var y = distExtra(d);
			if (cnt < y) {
				while (cnt <= 24) {
					if (p < end) {
						buf |= src[p] << cnt;
						p++;
						cnt += 8;
					} else if (st[0].chunked != 0) {
						st[0].p = p;
						hop(st, src);
						p = st[0].p;
						end = st[0].end;
					} else {
						// (past the input's end: zeros, a few)
						if (p >= end + 4) break;
						p++;
						cnt += 8;
					}
				}
				if (cnt < y) break;
			}
			var back = distBase(d) + (buf & ((1 << y) - 1));
			buf >>>= y;
			cnt -= y;
			if (back > pos || st[0].bad != 0) break;
			if (pos + len > cap) {
				st[0].bad = 3;
				break;
			}
			// (a copy from back bytes before: whole periods at a time, each copy's source before its target)
			var from = pos - back;
			while (len > 0) {
				var n = pos - from < len ? pos - from : len;
				out.blit(pos, out, from, n);
				pos += n;
				len -= n;
			}
		}
		st[0].buf = buf;
		st[0].cnt = cnt;
		st[0].p = p;
		st[0].pos = pos;
		// (bits taken from past the input's end: it ended early)
		if (st[0].chunked == 0 && p - (cnt >> 3) > end && st[0].bad == 0) st[0].bad = 2;
		return ok && st[0].bad == 0;
	}

	// (n bits in the buffer: the input's next bytes, the next IDAT chunk's
	// when one ends; past the input's end, zeros: no more than its reading
	// ahead, else bad)
	static inline function need(st:Span<Bits>, src:ReadOnlySpan<UInt8>, n:Int) {
		var cnt = st[0].cnt;
		if (cnt < n) {
			var buf = st[0].buf, p = st[0].p, end = st[0].end;
			while (cnt < n) {
				if (p >= end && st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				}
				if (p < end) buf |= src[p] << cnt else if (p >= end + 4) st[0].bad = 2;
				p++;
				cnt += 8;
			}
			st[0].buf = buf;
			st[0].p = p;
			st[0].cnt = cnt;
		}
	}

	// (the chunk ended: the next IDAT chunk with data, else the stream's end)
	@:hxmc.kernel static function hop(st:Span<Bits>, src:ReadOnlySpan<UInt8>) {
		var q = st[0].end + 4;
		while (q + 8 <= src.length) {
			var len = u32(src, q);
			if (name(src, q + 4) != 0x54414449 || len < 0 || len > src.length - q - 12) break;
			if (len > 0) {
				st[0].p = q + 8;
				st[0].end = q + 8 + len;
				return;
			}
			q += 12;
		}
		st[0].chunked = 0;
	}

	static inline function bits(st:Span<Bits>, src:ReadOnlySpan<UInt8>, n:Int):Int {
		need(st, src, n);
		var buf = st[0].buf;
		st[0].buf = buf >>> n;
		st[0].cnt -= n;
		return buf & ((1 << n) - 1);
	}

	// a symbol: the table for codes up to FAST bits, else bit by bit from the
	// canonical counts (a code's first bit its most significant)
	static inline function symbol(st:Span<Bits>, src:ReadOnlySpan<UInt8>, h:ReadOnlySpan<Int>):Int {
		need(st, src, 15);
		var buf = st[0].buf;
		var e = h[buf & (TABLE - 1)];
		return if (e != 0) {
			var len = e >> 9;
			st[0].buf = buf >>> len;
			st[0].cnt -= len;
			e & 511;
		} else slow(st, src, h);
	}

	@:hxmc.kernel static function slow(st:Span<Bits>, src:ReadOnlySpan<UInt8>, h:ReadOnlySpan<Int>):Int {
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(st, src, 1);
			var count = h[COUNTS + len];
			if (code - count < first) return h[SYMBOLS + index + (code - first)];
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		st[0].bad = 1;
		return 999;
	}

	// a canonical code from n lengths: the table of the codes up to FAST
	// bits (by their bits as read: reversed), each (length << 9) | symbol,
	// the counts, the symbols
	@:hxmc.kernel static function build(h:Span<Int>, l:ReadOnlySpan<Int>, n:Int) {
		h.fill(0, CODE, 0);
		for (i in 0...n) {
			var len = l[i];
			if (len > 0) h[COUNTS + len] += 1;
		}
		// (the symbols by length, then by value; the next one's place by length in the table's room until it is filled)
		var total = 0;
		for (len in 1...16) {
			h[len] = total;
			total += h[COUNTS + len];
		}
		for (sym in 0...n) {
			var len = l[sym];
			if (len > 0) {
				var k = h[len];
				h[SYMBOLS + k] = sym;
				h[len] = k + 1;
			}
		}
		h.fill(0, 16, 0);
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...h[COUNTS + len]) {
				if (len <= FAST) {
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | h[SYMBOLS + k];
					var j = r;
					while (j < TABLE) {
						h[j] = e;
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}

	@:hxmc.kernel static function adler(b:ReadOnlySpan<UInt8>):Int {
		var a = 1, c = 0, i = 0, n = b.length;
		while (i < n) {
			// (3800 bytes at most between the reductions: the sums stay under 2^31, signed)
			var m = b.sub(i, n - i < 3800 ? n - i : 3800);
			for (j in 0...m.length) {
				a += m[j];
				c += a;
			}
			i += m.length;
			a %= 65521;
			c %= 65521;
		}
		return (c << 16) | a;
	}

	// (deflate's tables as arithmetic)
	static inline function lengthBase(k:Int):Int
		return k < 8 ? 3 + k : k == 28 ? 258 : ((4 + (k & 3)) << ((k >> 2) - 1)) + 3;

	static inline function lengthExtra(k:Int):Int
		return k < 8 || k == 28 ? 0 : (k >> 2) - 1;

	static inline function distBase(d:Int):Int
		return d < 4 ? 1 + d : ((2 + (d & 1)) << ((d >> 1) - 1)) + 1;

	static inline function distExtra(d:Int):Int
		return d < 4 ? 0 : (d >> 1) - 1;

	static inline function order(i:Int):Int
		return switch i {
			case 0: 16;
			case 1: 17;
			case 2: 18;
			case 3: 0;
			case _: (i & 1) == 0 ? 8 + ((i - 4) >> 1) : 7 - ((i - 5) >> 1);
		}

	// (the bytes an inflate produced: until its failure, after one)
	@:hxmc.kernel public static function produced(scratch:Span<UInt8>):Int {
		var st:Span<Bits> = scratch.sub(0, STATE).reinterpret();
		return st[0].pos;
	}

	// (big-endian, as PNG's numbers are; a chunk's name as its bytes in memory, little-endian)
	static inline function u32(b:ReadOnlySpan<UInt8>, p:Int):Int
		return (b[p] : Int) << 24 | (b[p + 1] : Int) << 16 | (b[p + 2] : Int) << 8 | (b[p + 3] : Int);

	static inline function name(b:ReadOnlySpan<UInt8>, p:Int):Int
		return (b[p] : Int) | (b[p + 1] : Int) << 8 | (b[p + 2] : Int) << 16 | (b[p + 3] : Int) << 24;
}

// (the inflater's state: the bit buffer, its count, the input's position
// and its chunk's end, the output's position, a failure (3: the output is
// full; 2: the input ran out; 1: a bad code), whether IDAT chunks continue
// the input)
@:hxmc.struct @:publicFields private class Bits {
	var buf:Int;
	var cnt:Int;
	var p:Int;
	var end:Int;
	var pos:Int;
	var bad:Int;
	var chunked:Int;

	function new() {}
}
