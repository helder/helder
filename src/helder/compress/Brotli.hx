package helder.compress;

import haxe.ds.Vector;
import haxe.io.Bytes;

// Brotli (RFC 7932) decoded, in one go: WOFF2's tables, a web response's
// body. Its input is untrusted: every count, length and distance is checked,
// a code that is not a complete prefix code refused, and the output never
// grows past its bound, so a damaged stream throws "Brotli: ..." and never
// loops or allocates without limit. The whole output is the window: a
// distance reaches back into it, or past it (or past the window) into the
// static dictionary (dictionary.bin, built in).
class Brotli {
	// a stream (data's len bytes from pos) of exactly size bytes
	public static function exact(data:Bytes, pos:Int, len:Int, size:Int):Bytes {
		var d = new Brotli(data, pos, len, Bytes.alloc(size), size);
		d.run();
		if (d.at != size) throw 'Brotli: ${d.at} bytes, not $size';
		return d.out;
	}

	// a stream of any size up to budget bytes
	public static function all(data:Bytes, budget:Int):Bytes {
		var d = new Brotli(data, 0, data.length, Bytes.alloc(Std.int(Math.min(budget, Math.max(1024, data.length * 4)))), budget);
		d.run();
		return d.out.sub(0, d.at);
	}

	// (prefix codes' tables: ROOT bits looked up at once, longer codes in a second table)
	static inline var ROOT = 8;

	final data:Bytes;
	final end:Int;
	var next:Int;
	var bits = 0;
	var count = 0;
	var past = 0;
	var out:Bytes;
	final budget:Int;
	var at = 0;

	function new(data:Bytes, pos:Int, len:Int, out:Bytes, budget:Int) {
		if (pos < 0 || len < 0 || pos + len > data.length) throw "Brotli: no such range";
		this.data = data;
		next = pos;
		end = pos + len;
		this.out = out;
		this.budget = budget;
	}

	// --- bits, least significant first

	inline function fill(n:Int)
		while (count < n) {
			bits |= byte() << count;
			count += 8;
		}

	// (past the end: zeros, a few bytes' worth, then the stream is cut)
	function byte():Int {
		if (next < end) return data.get(next++);
		if (++past > 8) throw "Brotli: the stream is cut";
		return 0;
	}

	inline function read(n:Int):Int {
		fill(n);
		var v = bits & ((1 << n) - 1);
		bits >>>= n;
		count -= n;
		return v;
	}

	// (to the next byte: its bits must be zero)
	function align()
		if (read(count & 7) != 0) throw "Brotli: padding is not zero";

	// n bytes after align(): the buffered ones first
	function bytes(n:Int, keep:Bool) {
		if (keep) room(n);
		while (n > 0 && count >= 8) {
			var b = read(8);
			if (keep) out.set(at++, b);
			n--;
		}
		if (next + n > end) throw "Brotli: the stream is cut";
		if (keep) {
			out.blit(at, data, next, n);
			at += n;
		}
		next += n;
	}

	// --- the stream

	function run() {
		var window = (1 << windowBits()) - 16;
		// (the last four distances, the last at last - 1; the last two bytes)
		var dist = Vector.fromArrayCopy([16, 15, 11, 4]), last = 4;
		while (true) {
			var isLast = read(1) == 1;
			if (isLast && read(1) == 1) break;
			var nibbles = read(2);
			if (nibbles == 3) {
				// (metadata, skipped)
				if (read(1) != 0) throw "Brotli: a reserved bit is set";
				var n = read(2), skip = 0;
				for (i in 0...n) {
					var b = read(8);
					if (i == n - 1 && n > 1 && b == 0) throw "Brotli: a metadata length's last byte is zero";
					skip |= b << (8 * i);
				}
				align();
				bytes(n > 0 ? skip + 1 : 0, false);
				if (isLast) break;
				continue;
			}
			nibbles += 4;
			var length = 0;
			for (i in 0...nibbles) {
				var v = read(4);
				if (i == nibbles - 1 && nibbles > 4 && v == 0) throw "Brotli: a length's last nibble is zero";
				length |= v << (4 * i);
			}
			length++;
			if (!isLast && read(1) == 1) {
				align();
				bytes(length, true);
				continue;
			}
			last = block(length, window, dist, last);
			if (isLast) break;
		}
		// (the input whole, as the reference has it: nothing after the stream)
		align();
		var left = end - next + (count >> 3) - past;
		if (left < 0) throw "Brotli: the stream is cut";
		if (left > 0) throw "Brotli: data after the stream";
	}

	function windowBits():Int {
		if (read(1) == 0) return 16;
		var n = read(3);
		if (n != 0) return 17 + n;
		n = read(3);
		if (n == 1) throw "Brotli: a large window is not RFC 7932's";
		return n == 0 ? 17 : 8 + n;
	}

	// a compressed meta-block of length bytes; the distances' ring's next slot
	function block(length:Int, window:Int, dist:Vector<Int>, slot:Int):Int {
		// (each category's block types and counts: literals, commands, distances)
		var types = new Vector<Int>(3), current = new Vector<Int>(3), left = new Vector<Int>(3);
		var lastType = new Vector<Int>(3), before = new Vector<Int>(3);
		var typeCodes = new Vector<Null<Vector<Int>>>(3), countCodes = new Vector<Null<Vector<Int>>>(3);
		for (c in 0...3) {
			var n = small() + 1;
			types[c] = n;
			current[c] = 0;
			lastType[c] = 0;
			before[c] = 1;
			if (n >= 2) {
				typeCodes[c] = code(n + 2);
				countCodes[c] = code(26);
				left[c] = blockLength(countCodes[c]);
			} else left[c] = 1 << 28;
		}
		var postfix = read(2), direct = read(4) << postfix;
		var modes = new Vector<Int>(types[0]);
		for (i in 0...types[0]) modes[i] = read(2) * 512;
		var literalMap = contextMap(64 * types[0], small() + 1);
		var distanceMap = contextMap(4 * types[2], small() + 1);
		var literals = [for (_ in 0...max(literalMap)) code(256)];
		var commands = [for (_ in 0...types[1]) code(704)];
		var distances = [for (_ in 0...max(distanceMap)) code(16 + direct + (48 << postfix))];

		var lut = modes[0], mapAt = 0, ctx = BrotliTables.CONTEXT;
		var p1 = at > 0 ? out.get(at - 1) : 0, p2 = at > 1 ? out.get(at - 2) : 0;
		var remaining = length;
		room(Std.int(Math.min(length, budget - at)));
		while (remaining > 0) {
			if (left[1] == 0) switchBlock(1, types, current, left, lastType, before, typeCodes, countCodes);
			left[1]--;
			var cmd = symbol(commands[current[1]]), cell = cmd >> 6;
			var insertCode = INSERT_CELL[cell] + ((cmd >> 3) & 7), copyCode = COPY_CELL[cell] + (cmd & 7);
			var insert = INSERT_BASE[insertCode] + read(INSERT_EXTRA[insertCode]);
			var copy = COPY_BASE[copyCode] + read(COPY_EXTRA[copyCode]);
			if (insert > remaining) throw "Brotli: literals past the meta-block";
			room(insert);
			for (_ in 0...insert) {
				if (left[0] == 0) {
					switchBlock(0, types, current, left, lastType, before, typeCodes, countCodes);
					lut = modes[current[0]];
					mapAt = current[0] * 64;
				}
				left[0]--;
				var b = symbol(literals[literalMap[mapAt + (ctx[lut + p1] | ctx[lut + 256 + p2])]]);
				out.set(at++, b);
				p2 = p1;
				p1 = b;
			}
			remaining -= insert;
			if (remaining == 0) break;
			// (the distance: the last one, implied by the command's cell, else read)
			var d:Int, push = true;
			if (cell < 2) {
				d = dist[(slot - 1) & 3];
				push = false;
			} else {
				if (left[2] == 0) switchBlock(2, types, current, left, lastType, before, typeCodes, countCodes);
				left[2]--;
				var c = symbol(distances[distanceMap[current[2] * 4 + (copy > 4 ? 3 : copy - 2)]]);
				if (c < 16) {
					push = c != 0;
					d = c < 4 ? dist[(slot - 1 - c) & 3] : dist[(slot - 1 - (c < 10 ? 0 : 1)) & 3] + SHORT_DELTA[c];
					if (d <= 0) throw "Brotli: a distance is not positive";
				} else if (c < 16 + direct) d = c - 15 else {
					var x = c - direct - 16, n = 1 + (x >> (postfix + 1));
					var offset = ((2 + ((x >> postfix) & 1)) << n) - 4;
					d = ((offset + read(n)) << postfix) + (x & ((1 << postfix) - 1)) + direct + 1;
				}
			}
			var reach = at < window ? at : window;
			if (d > reach) {
				var n = word(d - reach - 1, copy);
				if (n > remaining) throw "Brotli: a word past the meta-block";
				remaining -= n;
			} else {
				if (copy > remaining) throw "Brotli: a copy past the meta-block";
				if (push) {
					dist[slot & 3] = d;
					slot++;
				}
				room(copy);
				if (d >= copy) out.blit(at, out, at - d, copy) else for (k in 0...copy) out.set(at + k, out.get(at + k - d));
				at += copy;
				remaining -= copy;
			}
			p1 = out.get(at - 1);
			p2 = at > 1 ? out.get(at - 2) : 0;
		}
		return slot;
	}

	// (the largest tree index a context map names, plus one)
	static function max(map:Vector<Int>):Int {
		var m = 0;
		for (v in map) if (v > m) m = v;
		return m + 1;
	}

	function switchBlock(c:Int, types:Vector<Int>, current:Vector<Int>, left:Vector<Int>, lastType:Vector<Int>, before:Vector<Int>,
			typeCodes:Vector<Null<Vector<Int>>>, countCodes:Vector<Null<Vector<Int>>>) {
		var s = symbol(typeCodes[c]);
		var t = s == 0 ? before[c] : s == 1 ? lastType[c] + 1 : s - 2;
		if (t >= types[c]) t -= types[c];
		before[c] = lastType[c];
		lastType[c] = t;
		current[c] = t;
		left[c] = blockLength(countCodes[c]);
	}

	function blockLength(code:Vector<Int>):Int {
		var s = symbol(code);
		return BLOCK_BASE[s] + read(BLOCK_EXTRA[s]);
	}

	// (0-255 in 1 to 11 bits)
	function small():Int {
		if (read(1) == 0) return 0;
		var n = read(3);
		return n == 0 ? 1 : (1 << n) + read(n);
	}

	function contextMap(size:Int, trees:Int):Vector<Int> {
		var map = new Vector<Int>(size, 0);
		if (trees == 1) return map;
		var rle = read(1) == 1 ? read(4) + 1 : 0;
		var c = code(trees + rle), i = 0;
		while (i < size) {
			var s = symbol(c);
			if (s == 0) i++ else if (s <= rle) {
				i += (1 << s) + read(s);
				if (i > size) throw "Brotli: a context map's run is too long";
			} else map[i++] = s - rle;
		}
		// (move-to-front, inverted)
		if (read(1) == 1) {
			var mtf = [for (k in 0...256) k];
			for (k in 0...size) {
				var j = map[k], v = mtf[j];
				map[k] = v;
				while (j > 0) mtf[j] = mtf[--j];
				mtf[0] = v;
			}
		}
		return map;
	}

	// --- prefix codes

	// a prefix code over alphabet symbols, read: its table
	function code(alphabet:Int):Vector<Int> {
		var lengths = new Vector<Int>(alphabet, 0);
		var skip = read(2);
		if (skip == 1) {
			var n = read(2) + 1, width = 0;
			while (1 << width < alphabet) width++;
			var syms = [];
			for (_ in 0...n) {
				var s = read(width);
				if (s >= alphabet || syms.contains(s)) throw "Brotli: a simple code's symbol is not one";
				syms.push(s);
			}
			if (n == 1) return single(syms[0]);
			var lens = switch n {
				case 2: [1, 1];
				case 3: [1, 2, 2];
				case _: read(1) == 0 ? [2, 2, 2, 2] : [1, 2, 3, 3];
			}
			for (i in 0...n) lengths[syms[i]] = lens[i];
			return table(lengths);
		}
		// (the code lengths' own code, its lengths in a fixed code of their own)
		var cl = new Vector<Int>(18, 0), space = 32, used = 0, only = 0;
		for (i in skip...18) {
			fill(4);
			var p = bits & 15, v = CL_VALUE[p];
			bits >>>= CL_LENGTH[p];
			count -= CL_LENGTH[p];
			cl[CL_ORDER[i]] = v;
			if (v != 0) {
				space -= 32 >> v;
				used++;
				only = CL_ORDER[i];
				if (space <= 0) break;
			}
		}
		if (used != 1 && space != 0) throw "Brotli: the code lengths' code is not complete";
		var clCode = used == 1 ? single(only) : table(cl);
		var s = 0, previous = 8, repeat = 0, repeatLength = 0, room = 32768;
		while (s < alphabet && room > 0) {
			var p = symbol(clCode);
			if (p < 16) {
				repeat = 0;
				lengths[s++] = p;
				if (p != 0) {
					previous = p;
					room -= 32768 >> p;
				}
				continue;
			}
			var extra = p == 16 ? 2 : 3, length = p == 16 ? previous : 0;
			if (repeatLength != length) {
				repeat = 0;
				repeatLength = length;
			}
			var old = repeat;
			if (repeat > 0) repeat = (repeat - 2) << extra;
			repeat += read(extra) + 3;
			var delta = repeat - old;
			if (s + delta > alphabet) throw "Brotli: code lengths past the alphabet";
			for (_ in 0...delta) lengths[s++] = length;
			if (length != 0) room -= delta << (15 - length);
		}
		if (room != 0) throw "Brotli: a prefix code is not complete";
		return table(lengths);
	}

	// (one symbol, no bits)
	static function single(s:Int):Vector<Int>
		return new Vector<Int>(1 << ROOT, s);

	// a complete prefix code's table from its lengths (canonical codes, read
	// from their first bit: reversed): an entry is length << 16 | symbol, or
	// for a longer code's first ROOT bits (16 + its table's bits) << 16 | where
	static function table(lengths:Vector<Int>):Vector<Int> {
		var counts = new Vector<Int>(16, 0);
		for (l in lengths) counts[l]++;
		counts[0] = 0;
		var left = 1;
		for (l in 1...16) {
			left = (left << 1) - counts[l];
			if (left < 0) throw "Brotli: a prefix code is over-subscribed";
		}
		if (left != 0) throw "Brotli: a prefix code is not complete";
		var firsts = new Vector<Int>(16, 0), c = 0;
		for (l in 1...16) {
			c = (c + counts[l - 1]) << 1;
			firsts[l] = c;
		}
		// (each long code's first ROOT bits' table: as deep as its deepest code)
		var n = lengths.length, codes = new Vector<Int>(n, 0), deep = new Vector<Int>(1 << ROOT, 0);
		for (s in 0...n) {
			var l = lengths[s];
			if (l == 0) continue;
			var r = reverse(firsts[l]++, l);
			codes[s] = r;
			if (l > ROOT && l - ROOT > deep[r & 255]) deep[r & 255] = l - ROOT;
		}
		var size = 1 << ROOT, at = new Vector<Int>(1 << ROOT, 0);
		for (p in 0...1 << ROOT) if (deep[p] > 0) {
			at[p] = size;
			size += 1 << deep[p];
		}
		var t = new Vector<Int>(size, 0);
		for (p in 0...1 << ROOT) if (deep[p] > 0) t[p] = (16 + deep[p]) << 16 | at[p];
		for (s in 0...n) {
			var l = lengths[s], r = codes[s];
			if (l == 0) continue;
			if (l <= ROOT) {
				var i = r;
				while (i < 1 << ROOT) {
					t[i] = l << 16 | s;
					i += 1 << l;
				}
			} else {
				var p = r & 255, i = r >>> ROOT, base = at[p], span = 1 << deep[p];
				while (i < span) {
					t[base + i] = (l - ROOT) << 16 | s;
					i += 1 << (l - ROOT);
				}
			}
		}
		return t;
	}

	static function reverse(c:Int, l:Int):Int {
		var r = 0;
		for (_ in 0...l) {
			r = r << 1 | (c & 1);
			c >>= 1;
		}
		return r;
	}

	inline function symbol(t:Vector<Int>):Int {
		fill(15);
		var e = t[bits & 255], n = e >>> 16;
		if (n > 15) {
			bits >>>= ROOT;
			count -= ROOT;
			e = t[(e & 0xffff) + (bits & ((1 << (n - 16)) - 1))];
			n = e >>> 16;
		}
		bits >>>= n;
		count -= n;
		return e & 0xffff;
	}

	// --- output

	// (n bytes more, within the bound)
	function room(n:Int) {
		if (at + n <= out.length) return;
		if (at + n > budget) throw 'Brotli: more than $budget bytes';
		var b = Bytes.alloc(Std.int(Math.min(budget, Math.max(out.length * 2, at + n))));
		b.blit(0, out, 0, at);
		out = b;
	}

	// a static dictionary word, transformed: its bytes' count
	function word(id:Int, length:Int):Int {
		if (length < 4 || length > 24) throw "Brotli: no dictionary word of that length";
		var bits = WORD_BITS[length], index = id & ((1 << bits) - 1), transform = id >>> bits;
		if (transform >= 121) throw "Brotli: no such transform";
		var words = dictionary(), from = WORD_OFFSETS[length] + index * length;
		var prefix = BrotliTables.PREFIXES[transform], kind = BrotliTables.KINDS[transform], suffix = BrotliTables.SUFFIXES[transform];
		room(prefix.length + length + suffix.length);
		var start = at;
		for (b in prefix) out.set(at++, b);
		var n = length;
		if (kind >= 1 && kind <= 9) n = kind > n ? 0 : n - kind else if (kind >= 12) {
			var s = kind - 11 > n ? n : kind - 11;
			from += s;
			n -= s;
		}
		out.blit(at, words, from, n);
		if (kind == 10) upper(at, n) else if (kind == 11) {
			var i = 0;
			while (i < n) i += upper(at + i, n - i);
		}
		at += n;
		for (b in suffix) out.set(at++, b);
		return at - start;
	}

	// (RFC 7932's uppercasing of a UTF-8 character: its bytes' count)
	function upper(p:Int, n:Int):Int {
		var b = out.get(p);
		if (b < 0xc0) {
			if (b >= 97 && b <= 122) out.set(p, b ^ 32);
			return 1;
		}
		if (b < 0xe0) {
			if (n > 1) out.set(p + 1, out.get(p + 1) ^ 32);
			return 2;
		}
		if (n > 2) out.set(p + 2, out.get(p + 2) ^ 5);
		return 3;
	}

	static var words:Null<Bytes> = null;

	static function dictionary():Bytes {
		if (words == null) words = embedded();
		return words;
	}

	// (its bytes built in by Asset.embed's macro, not by a call of Asset.embed:
	// that would link Asset, whose loads are helder.async's, into every program
	// that reads a font, a page's too: tests/web/links.mjs)
	static macro function embedded():haxe.macro.Expr
		return helder.asset.AssetMacro.embed("helder/compress/dictionary.bin");

	// (RFC 7932's tables)
	static final CL_ORDER = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15];
	// (the code lengths' lengths' fixed code, by its next four bits)
	static final CL_LENGTH = [2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4];
	static final CL_VALUE = [0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5];
	static final BLOCK_BASE = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625];
	static final BLOCK_EXTRA = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24];
	static final INSERT_CELL = [0, 0, 0, 0, 8, 8, 0, 16, 8, 16, 16];
	static final COPY_CELL = [0, 8, 0, 8, 0, 8, 16, 0, 16, 8, 16];
	static final INSERT_BASE = [0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594];
	static final INSERT_EXTRA = [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24];
	static final COPY_BASE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118];
	static final COPY_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24];
	// (short distance codes 4-15: the last distance's, then the one before's, plus these)
	static final SHORT_DELTA = [0, 0, 0, 0, -1, 1, -2, 2, -3, 3, -1, 1, -2, 2, -3, 3];
	static final WORD_BITS = [0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5, 5];
	static final WORD_OFFSETS = {
		var o = [0, 0, 0, 0, 0], at = 0;
		for (l in 4...24) o.push(at += l << WORD_BITS[l]);
		o;
	}
}
