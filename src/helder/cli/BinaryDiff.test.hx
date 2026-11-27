package helder.cli;

import haxe.io.Bytes;
import helder.test.Test;

// A version made from the one before and its diff: an edit that shifts
// what follows (an insertion, a deletion), bytes changed in place, the
// empty files; a diff of another file, or damaged, is refused
function tests() {
	// (random bytes, as a module's code is to a diff)
	function bytes(n:Int, seed:Int):Bytes {
		var b = Bytes.alloc(n), s = seed;
		for (i in 0...n) {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			b.set(i, s >> 16);
		}
		return b;
	}
	function edit(b:Bytes, at:Int, cut:Int, insert:Bytes):Bytes {
		var out = Bytes.alloc(b.length - cut + insert.length);
		out.blit(0, b, 0, at);
		out.blit(at, insert, 0, insert.length);
		out.blit(at + insert.length, b, at + cut, b.length - at - cut);
		return out;
	}
	test("an insertion, a deletion, bytes changed: the new version back, the diff small", () -> {
		var old = bytes(60000, 7);
		var now = edit(edit(old, 20000, 0, bytes(300, 9)), 45000, 120, Bytes.alloc(0));
		for (i in 0...40)
			now.set(1000 + i * 997, (now.get(1000 + i * 997) + 3) & 0xFF);
		var d = BinaryDiff.diff(old, now);
		equals(BinaryDiff.apply(old, d).compare(now), 0);
		assert(d.length < now.length / 20, '${d.length} bytes');
	});
	test("the empty files, and the same file", () -> {
		var b = bytes(5000, 3), empty = Bytes.alloc(0);
		equals(BinaryDiff.apply(empty, BinaryDiff.diff(empty, b)).compare(b), 0);
		equals(BinaryDiff.apply(b, BinaryDiff.diff(b, empty)).length, 0);
		var same = BinaryDiff.diff(b, b);
		equals(BinaryDiff.apply(b, same).compare(b), 0);
		assert(same.length < 100, '${same.length} bytes');
	});
	test("a diff of another file, cut or damaged: null", () -> {
		var old = bytes(8000, 1), now = edit(old, 4000, 10, bytes(50, 2));
		var d = BinaryDiff.diff(old, now);
		equals(BinaryDiff.apply(bytes(8001, 1), d), null);
		equals(BinaryDiff.apply(old, d.sub(0, d.length >> 1)), null);
		var bad = d.sub(0, d.length);
		bad.set(12, bad.get(12) ^ 0x40);
		equals(BinaryDiff.apply(old, bad), null);
	});
}
