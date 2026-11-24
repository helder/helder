package helder.gfx.soft;

import hxmc.simd.I32x4;

// An Int in each of a call's 4 lanes (32 bits, wrapping as Haxe's do)
abstract LaneInt(I32x4) {
	inline function new(v:I32x4)
		this = v;

	@:to public inline function bits():I32x4
		return this;

	public static inline function of(v:I32x4):LaneInt
		return new LaneInt(v);

	public static inline function splat(x:Int):LaneInt
		return new LaneInt(I32x4.splat(x));

	public static inline function make(a:Int, b:Int, c:Int, d:Int):LaneInt
		return new LaneInt(I32x4.make(a, b, c, d));

	public inline function get(i:Int):Int
		return this.get(i);

	@:op(A + B) inline function add(b:LaneInt):LaneInt
		return new LaneInt(this + b.bits());

	@:op(A - B) inline function sub(b:LaneInt):LaneInt
		return new LaneInt(this - b.bits());

	@:op(A * B) inline function mul(b:LaneInt):LaneInt
		return new LaneInt(this * b.bits());

	@:op(-A) inline function neg():LaneInt
		return new LaneInt(-this);

	@:op(A & B) inline function and(b:LaneInt):LaneInt
		return new LaneInt(this & b.bits());

	@:op(A | B) inline function or(b:LaneInt):LaneInt
		return new LaneInt(this | b.bits());

	@:op(A ^ B) inline function xor(b:LaneInt):LaneInt
		return new LaneInt(this ^ b.bits());

	@:op(~A) inline function not():LaneInt
		return new LaneInt(~this);

	// (no SIMD division or shift by lanes: lane by lane, as Haxe's Ints)
	public inline function div(b:LaneInt):LaneInt
		return make(Std.int(get(0) / b.get(0)), Std.int(get(1) / b.get(1)), Std.int(get(2) / b.get(2)), Std.int(get(3) / b.get(3)));

	public inline function mod(b:LaneInt):LaneInt
		return make(get(0) % b.get(0), get(1) % b.get(1), get(2) % b.get(2), get(3) % b.get(3));

	public inline function shl(b:LaneInt):LaneInt
		return make(get(0) << b.get(0), get(1) << b.get(1), get(2) << b.get(2), get(3) << b.get(3));

	public inline function shr(b:LaneInt):LaneInt
		return make(get(0) >> b.get(0), get(1) >> b.get(1), get(2) >> b.get(2), get(3) >> b.get(3));

	public inline function eq(b:LaneInt):LaneBool
		return LaneBool.of(this.eq(b.bits()));

	public inline function ne(b:LaneInt):LaneBool
		return LaneBool.of(this.ne(b.bits()));

	public inline function lt(b:LaneInt):LaneBool
		return LaneBool.of(this.lt(b.bits()));

	public inline function le(b:LaneInt):LaneBool
		return LaneBool.of(this.le(b.bits()));

	public inline function gt(b:LaneInt):LaneBool
		return LaneBool.of(this.gt(b.bits()));

	public inline function ge(b:LaneInt):LaneBool
		return LaneBool.of(this.ge(b.bits()));

	public inline function min(b:LaneInt):LaneInt
		return new LaneInt(this.min(b.bits()));

	public inline function max(b:LaneInt):LaneInt
		return new LaneInt(this.max(b.bits()));

	public inline function abs():LaneInt
		return new LaneInt(this.abs());

	public static inline function select(m:LaneBool, a:LaneInt, b:LaneInt):LaneInt
		return new LaneInt(I32x4.select(m.bits(), a.bits(), b.bits()));
}
