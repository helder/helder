package helder.gfx.soft;

import hxmc.simd.I32x4;

// A Bool in each of a call's 4 lanes (a 2x2 quad's pixels, or 4 vertices):
// all ones where true, the masks comparisons give
abstract LaneBool(I32x4) {
	inline function new(v:I32x4)
		this = v;

	@:to public inline function bits():I32x4
		return this;

	public static inline function of(v:I32x4):LaneBool
		return new LaneBool(v);

	public static inline function splat(b:Bool):LaneBool
		return new LaneBool(I32x4.splat(b ? -1 : 0));

	public static inline function none():LaneBool
		return new LaneBool(I32x4.zero());

	// the lanes of a mask's low 4 bits (lane i: bit i)
	public static inline function ofMask(m:Int):LaneBool
		return new LaneBool(I32x4.make(-(m & 1), -((m >> 1) & 1), -((m >> 2) & 1), -((m >> 3) & 1)));

	// the lanes set, as bits (lane i: bit i)
	public inline function mask():Int
		return this.bitmask();

	public inline function any():Bool
		return this.any();

	public inline function all():Bool
		return this.all();

	public inline function get(i:Int):Bool
		return this.get(i) != 0;

	@:op(A & B) inline function and(b:LaneBool):LaneBool
		return new LaneBool(this & b.bits());

	@:op(A | B) inline function or(b:LaneBool):LaneBool
		return new LaneBool(this | b.bits());

	@:op(A ^ B) inline function xor(b:LaneBool):LaneBool
		return new LaneBool(this ^ b.bits());

	@:op(!A) inline function not():LaneBool
		return new LaneBool(~this);

	// this's lanes but b's
	public inline function andNot(b:LaneBool):LaneBool
		return new LaneBool(this.andNot(b.bits()));

	public inline function eq(b:LaneBool):LaneBool
		return new LaneBool(~(this ^ b.bits()));

	public inline function ne(b:LaneBool):LaneBool
		return new LaneBool(this ^ b.bits());

	public static inline function select(m:LaneBool, a:LaneBool, b:LaneBool):LaneBool
		return new LaneBool(I32x4.select(m.bits(), a.bits(), b.bits()));
}
