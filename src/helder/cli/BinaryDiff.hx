package helder.cli;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// A binary diff of one version of a file against the one before (a live
// share's web build: its module, which a small edit shifts throughout, so
// a copy-and-insert diff does poorly), as bsdiff 4.3 makes it (Colin
// Percival's: Larsson and Sadakane's suffix sort of the old file, each
// stretch of the new one matched approximately, its bytes then the
// difference from the old ones, mostly zeros). Its own container, which
// helder's page (page.html) applies with the browser's deflate-raw:
//
//   "HDF1", u32 old size, u32 new size, u32 payload size (little-endian),
//   then the payload deflated (raw):
//     varint triples, then per triple: varint add, varint extra, zigzag varint seek
//     the diff bytes (sum of adds) as runs: varint zeros, varint literal count, the literals,
//       until they are all given
//     the extra bytes (sum of extras)
//
// apply(old, diff) is null for a diff not of old (its size) or damaged.
class BinaryDiff {
	public static function diff(old:Bytes, now:Bytes):Bytes {
		var oldSize = old.length, newSize = now.length;
		var I = new Vector<Int>(oldSize + 1), V = new Vector<Int>(oldSize + 1);
		qsufsort(I, V, old, oldSize);
		var ctrl = new BytesBuffer(), db = Bytes.alloc(newSize), eb = new BytesBuffer();
		var triples = 0, dblen = 0;
		var scan = 0, len = 0, pos = 0, lastscan = 0, lastpos = 0, lastoffset = 0;
		while (scan < newSize) {
			var oldscore = 0;
			var scsc = scan += len;
			while (scan < newSize) {
				var found = search(I, old, oldSize, now, scan, 0, oldSize);
				len = found.len;
				pos = found.pos;
				while (scsc < scan + len) {
					if (scsc + lastoffset < oldSize && old.get(scsc + lastoffset) == now.get(scsc)) oldscore++;
					scsc++;
				}
				if ((len == oldscore && len != 0) || len > oldscore + 8) break;
				if (scan + lastoffset < oldSize && old.get(scan + lastoffset) == now.get(scan)) oldscore--;
				scan++;
			}
			if (len != oldscore || scan == newSize) {
				var s = 0, sf = 0, lenf = 0, i = 0;
				while (lastscan + i < scan && lastpos + i < oldSize) {
					if (old.get(lastpos + i) == now.get(lastscan + i)) s++;
					i++;
					if (s * 2 - i > sf * 2 - lenf) {
						sf = s;
						lenf = i;
					}
				}
				var lenb = 0;
				if (scan < newSize) {
					var sb = 0;
					s = 0;
					i = 1;
					while (scan >= lastscan + i && pos >= i) {
						if (old.get(pos - i) == now.get(scan - i)) s++;
						if (s * 2 - i > sb * 2 - lenb) {
							sb = s;
							lenb = i;
						}
						i++;
					}
				}
				if (lastscan + lenf > scan - lenb) {
					var overlap = (lastscan + lenf) - (scan - lenb), ss = 0, lens = 0;
					s = 0;
					for (k in 0...overlap) {
						if (now.get(lastscan + lenf - overlap + k) == old.get(lastpos + lenf - overlap + k)) s++;
						if (now.get(scan - lenb + k) == old.get(pos - lenb + k)) s--;
						if (s > ss) {
							ss = s;
							lens = k + 1;
						}
					}
					lenf += lens - overlap;
					lenb -= lens;
				}
				for (k in 0...lenf)
					db.set(dblen + k, (now.get(lastscan + k) - old.get(lastpos + k)) & 0xFF);
				var extra = (scan - lenb) - (lastscan + lenf);
				for (k in 0...extra)
					eb.addByte(now.get(lastscan + lenf + k));
				dblen += lenf;
				varint(ctrl, lenf);
				varint(ctrl, extra);
				varint(ctrl, zigzag((pos - lenb) - (lastpos + lenf)));
				triples++;
				lastscan = scan - lenb;
				lastpos = pos - lenb;
				lastoffset = pos - scan;
			}
		}
		var payload = new BytesBuffer();
		varint(payload, triples);
		payload.add(ctrl.getBytes());
		// (the difference bytes: runs of zeros, then literals)
		var k = 0;
		while (k < dblen) {
			var z = k;
			while (z < dblen && db.get(z) == 0) z++;
			var l = z;
			while (l < dblen && db.get(l) != 0) l++;
			varint(payload, z - k);
			varint(payload, l - z);
			payload.addBytes(db, z, l - z);
			k = l;
		}
		payload.add(eb.getBytes());
		var raw = payload.getBytes(), out = new BytesBuffer();
		out.addString("HDF1");
		out.addInt32(oldSize);
		out.addInt32(newSize);
		out.addInt32(raw.length);
		out.add(helder.image.Deflate.raw(raw));
		return out.getBytes();
	}

	public static function apply(old:Bytes, diff:Bytes):Null<Bytes> {
		if (diff.length < 16 || diff.getString(0, 4) != "HDF1" || diff.getInt32(4) != old.length) return null;
		var newSize = diff.getInt32(8), size = diff.getInt32(12);
		if (newSize < 0 || size < 0) return null;
		var p = try helder.image.Inflate.exact(diff.sub(16, diff.length - 16), size, false) catch (_:Dynamic) return null;
		var at = 0;
		function read():Int {
			var v = 0, shift = 0;
			while (true) {
				if (at >= p.length || shift > 28) throw "binary diff: cut";
				var b = p.get(at++);
				v |= (b & 127) << shift;
				if (b < 128) return v;
				shift += 7;
			}
		}
		return try {
			var n = read(), ctrl = [for (_ in 0...n * 3) read()];
			var add = 0, extra = 0;
			for (t in 0...n) {
				add += ctrl[t * 3];
				extra += ctrl[t * 3 + 1];
			}
			if (add + extra != newSize) throw "binary diff: sizes";
			// (the difference bytes, decoded from their runs)
			var d = Bytes.alloc(add), k = 0;
			while (k < add) {
				var z = read(), l = read();
				if (k + z + l > add || at + l > p.length) throw "binary diff: runs";
				k += z;
				d.blit(k, p, at, l);
				at += l;
				k += l;
			}
			var out = Bytes.alloc(newSize), o = 0, n2 = 0, dk = 0;
			for (t in 0...n) {
				var a = ctrl[t * 3], e = ctrl[t * 3 + 1], seek = unzigzag(ctrl[t * 3 + 2]);
				if (n2 < 0 || n2 + a > old.length) throw "binary diff: reads past the old file";
				for (i in 0...a)
					out.set(o + i, (old.get(n2 + i) + d.get(dk + i)) & 0xFF);
				o += a;
				n2 += a;
				dk += a;
				if (at + e > p.length) throw "binary diff: extra";
				out.blit(o, p, at, e);
				o += e;
				at += e;
				n2 += seek;
			}
			out;
		} catch (_:Dynamic) null;
	}

	// ---- bsdiff's suffix sort (Larsson and Sadakane, qsufsort) and search

	static function qsufsort(I:Vector<Int>, V:Vector<Int>, old:Bytes, size:Int) {
		var buckets = new Vector<Int>(256);
		for (i in 0...256)
			buckets[i] = 0;
		for (i in 0...size)
			buckets[old.get(i)]++;
		for (i in 1...256)
			buckets[i] += buckets[i - 1];
		var i = 255;
		while (i > 0) {
			buckets[i] = buckets[i - 1];
			i--;
		}
		buckets[0] = 0;
		for (k in 0...size)
			I[++buckets[old.get(k)]] = k;
		I[0] = size;
		for (k in 0...size)
			V[k] = buckets[old.get(k)];
		V[size] = 0;
		for (k in 1...256)
			if (buckets[k] == buckets[k - 1] + 1) I[buckets[k]] = -1;
		I[0] = -1;
		var h = 1;
		while (I[0] != -(size + 1)) {
			var len = 0, k = 0;
			while (k < size + 1) {
				if (I[k] < 0) {
					len -= I[k];
					k -= I[k];
				} else {
					if (len != 0) I[k - len] = -len;
					len = V[I[k]] + 1 - k;
					split(I, V, k, len, h);
					k += len;
					len = 0;
				}
			}
			if (len != 0) I[k - len] = -len;
			h += h;
		}
		for (k in 0...size + 1)
			I[V[k]] = k;
	}

	static function split(I:Vector<Int>, V:Vector<Int>, start:Int, len:Int, h:Int) {
		if (len < 16) {
			var k = start;
			while (k < start + len) {
				var j = 1, x = V[I[k] + h], i = 1;
				while (k + i < start + len) {
					if (V[I[k + i] + h] < x) {
						x = V[I[k + i] + h];
						j = 0;
					}
					if (V[I[k + i] + h] == x) {
						var tmp = I[k + j];
						I[k + j] = I[k + i];
						I[k + i] = tmp;
						j++;
					}
					i++;
				}
				for (i in 0...j)
					V[I[k + i]] = k + j - 1;
				if (j == 1) I[k] = -1;
				k += j;
			}
			return;
		}
		var x = V[I[start + (len >> 1)] + h], jj = 0, kk = 0;
		for (i in start...start + len) {
			if (V[I[i] + h] < x) jj++;
			if (V[I[i] + h] == x) kk++;
		}
		jj += start;
		kk += jj;
		var i = start, j = 0, k = 0;
		while (i < jj) {
			if (V[I[i] + h] < x) i++;
			else if (V[I[i] + h] == x) {
				var tmp = I[i];
				I[i] = I[jj + j];
				I[jj + j] = tmp;
				j++;
			} else {
				var tmp = I[i];
				I[i] = I[kk + k];
				I[kk + k] = tmp;
				k++;
			}
		}
		while (jj + j < kk) {
			if (V[I[jj + j] + h] == x) j++;
			else {
				var tmp = I[jj + j];
				I[jj + j] = I[kk + k];
				I[kk + k] = tmp;
				k++;
			}
		}
		if (jj > start) split(I, V, start, jj - start, h);
		for (i in 0...kk - jj)
			V[I[jj + i]] = kk - 1;
		if (jj == kk - 1) I[jj] = -1;
		if (start + len > kk) split(I, V, kk, start + len - kk, h);
	}

	static function matchlen(old:Bytes, oldAt:Int, now:Bytes, nowAt:Int):Int {
		var n = 0, max = old.length - oldAt < now.length - nowAt ? old.length - oldAt : now.length - nowAt;
		while (n < max && old.get(oldAt + n) == now.get(nowAt + n)) n++;
		return n;
	}

	// (the old file's suffix that matches now from at the longest: a binary search of the sorted suffixes)
	static function search(I:Vector<Int>, old:Bytes, oldSize:Int, now:Bytes, at:Int, st:Int, en:Int):{len:Int, pos:Int} {
		while (en - st >= 2) {
			var x = st + ((en - st) >> 1);
			if (less(old, I[x], now, at)) st = x else en = x;
		}
		var a = matchlen(old, I[st], now, at), b = matchlen(old, I[en], now, at);
		return a > b ? {len: a, pos: I[st]} : {len: b, pos: I[en]};
	}

	// (memcmp(old + o, now + n, min(...)) < 0)
	static function less(old:Bytes, o:Int, now:Bytes, n:Int):Bool {
		var max = old.length - o < now.length - n ? old.length - o : now.length - n;
		for (i in 0...max) {
			var a = old.get(o + i), b = now.get(n + i);
			if (a != b) return a < b;
		}
		return false;
	}

	static function varint(b:BytesBuffer, v:Int) {
		while (v >= 128 || v < 0) {
			b.addByte((v & 127) | 128);
			v >>>= 7;
		}
		b.addByte(v);
	}

	static inline function zigzag(v:Int):Int
		return (v << 1) ^ (v >> 31);

	static inline function unzigzag(v:Int):Int
		return (v >>> 1) ^ -(v & 1);
}
