package helder.gfx.soft;

import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Ptr;

// A pass's memory outside the collector's heap: chunks a bump pointer cuts,
// never moved (the tiles read what was recorded by address), kept for the
// next pass when emptied
@:hxmc.unsafe(gc)
class Chunks {
	static inline var CHUNK = 1 << 20;

	final chunks:Array<Ptr> = [];
	var current = 0;
	var at:Ptr = Ptr.nil();
	var end:Ptr = Ptr.nil();

	// the bytes cut since the last reset
	public var used(default, null) = 0.0;

	public function new() {}

	// n bytes, 16-byte aligned (not zeroed)
	public function alloc(n:Int):Ptr {
		n = (n + 15) & ~15;
		used += n;
		if (at.isNull() || at.add(n).toI64() > end.toI64()) {
			if (n > CHUNK) {
				// (a large one of its own, let go at the reset)
				var big:Ptr = LibC.malloc((n : I64));
				if (big.isNull()) throw "helder.gfx: out of memory";
				large.push(big);
				return big;
			}
			if (current >= chunks.length) {
				var c:Ptr = LibC.malloc((CHUNK : I64));
				if (c.isNull()) throw "helder.gfx: out of memory";
				chunks.push(c);
			}
			at = chunks[current++];
			end = at.add(CHUNK);
		}
		var p = at;
		at = at.add(n);
		return p;
	}

	final large:Array<Ptr> = [];

	// everything cut let go (the chunks kept, but the large ones)
	public function reset() {
		for (b in large)
			LibC.free(b);
		large.resize(0);
		current = 0;
		at = end = Ptr.nil();
		used = 0;
	}

	public function free() {
		for (c in chunks)
			LibC.free(c);
		for (b in large)
			LibC.free(b);
		chunks.resize(0);
		large.resize(0);
		current = 0;
		at = end = Ptr.nil();
	}
}
