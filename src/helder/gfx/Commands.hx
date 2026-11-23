package helder.gfx;

import haxe.io.Bytes;
import hxmc.unsafe.*;

// A device's GPU commands, recorded (Device, Encoder) and executed in
// order (Replay): flat words in memory outside the collector's heap, each
// command its op and its size in bytes, then its arguments; uploads'
// bytes copied in, so that the program may reuse its arrays at once. What
// has no flat form (a shader's or pipeline's descriptor, a call that
// answers: readPixels, createShader) is a closure in objects, by index.
@:noCompletion @:hxmc.unsafe(gc)
final class Commands {
	var base:Ptr<UInt8>;
	var cap:Int;
	// (where the command being written began; the reader's cursor)
	var start = 0;
	var at = 0;

	public var length(default, null) = 0;

	public final objects:Array<Replay->Void> = [];

	public function new() {
		cap = SMALL;
		base = LibC.malloc((cap : Int64));
		if (base.isNull()) throw "helder.gfx: out of memory";
	}

	public inline function begin(op:Int) {
		start = length;
		int(op);
		int(0);
	}

	public inline function end()
		(cast base.add(start + 4) : Ptr<Int32>).value = length - start;

	public inline function int(v:Int) {
		if (length + 4 > cap) grow(4);
		(cast base.add(length) : Ptr<Int32>).value = v;
		length += 4;
	}

	// (8-byte aligned)
	public inline function float(v:Float) {
		if (length & 7 != 0) int(0);
		if (length + 8 > cap) grow(8);
		(cast base.add(length) : Ptr<Float>).value = v;
		length += 8;
	}

	// n bytes of b from pos, after their count
	public function bytes(b:Bytes, pos:Int, n:Int) {
		int(n);
		var padded = (n + 3) & ~3;
		if (length + padded > cap) grow(padded);
		LibC.memcpy(base.add(length), BytesPtr.of(b, pos, n), (n : Int64));
		length += padded;
	}

	public inline function call(f:Replay->Void) {
		begin(Replay.CALL);
		int(objects.length);
		objects.push(f);
		end();
	}

	function grow(n:Int) {
		while (length + n > cap)
			cap *= 2;
		var p:Ptr<UInt8> = LibC.realloc(base, (cap : Int64));
		if (p.isNull()) throw "helder.gfx: out of memory for " + cap + " bytes of commands";
		base = p;
	}

	// ---- reading (Replay)

	public inline function more():Bool
		return at < length;

	public inline function cursor():Int
		return at;

	public inline function seek(p:Int)
		at = p;

	// (the command at p: its size in bytes)
	public inline function sizeAt(p:Int):Int
		return (cast base.add(p + 4) : Ptr<Int32>).value;

	public inline function next():Int {
		var v:Int = (cast base.add(at) : Ptr<Int32>).value;
		at += 4;
		return v;
	}

	public inline function nextFloat():Float {
		if (at & 7 != 0) at += 4;
		var v:Float = (cast base.add(at) : Ptr<Float>).value;
		at += 8;
		return v;
	}

	// the n bytes after their count (next()) into into, which holds them
	public function copy(into:Bytes, n:Int) {
		BytesPtr.copyIn(into, 0, base.add(at), n);
		at += (n + 3) & ~3;
	}

	// emptied for the next recording; a large one (an upload's) let go
	public function clear() {
		length = at = start = 0;
		objects.resize(0);
		if (cap > LARGE) {
			var p:Ptr<UInt8> = LibC.realloc(base, (SMALL : Int64));
			if (!p.isNull()) {
				base = p;
				cap = SMALL;
			}
		}
	}

	public function free() {
		LibC.free(base);
		base = Ptr.nil();
		cap = length = 0;
	}

	static inline var SMALL = 64 * 1024;
	static inline var LARGE = 4 * 1024 * 1024;
}
