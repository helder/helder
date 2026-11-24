package helder.gfx.soft;

import hxmc.simd.F32x4;
import hxmc.simd.F64x2;
import hxmc.simd.I32x4;
import hxmc.unsafe.Ptr;

// A Float in each of a call's 4 lanes: a 2x2 quad's pixels (lanes 0, 1 the
// top row, 2, 3 the bottom one: dFdx is lane 1 - lane 0, dFdy lane 2 -
// lane 0, as GPUs take them) or 4 vertices. float32, as GPUs compute; with
// -D helder.soft.exact two F64x2s, Haxe's own doubles, so that a shader's
// lanes equal its scalar code bit for bit (tests/gfx/SoftShaderTest). The
// one place the lane width is known with LaneBool and LaneInt: wider lanes
// are another implementation of these three.
#if helder.soft.exact
abstract Lane(LaneData) {
	inline function new(d:LaneData)
		this = d;

	inline function lo():F64x2
		return this.lo;

	inline function hi():F64x2
		return this.hi;

	static inline function of(lo:F64x2, hi:F64x2):Lane
		return new Lane(new LaneData(lo, hi));

	public static inline function splat(x:Float):Lane
		return of(F64x2.splat(x), F64x2.splat(x));

	public static inline function make(a:Float, b:Float, c:Float, d:Float):Lane
		return of(F64x2.make(a, b), F64x2.make(c, d));

	public static inline function zero():Lane
		return splat(0);

	public inline function get(i:Int):Float
		return i < 2 ? this.lo.get(i & 1) : this.hi.get(i & 1);

	// 4 float32s at p + off
	@:hxmc.unsafe(gc) public static inline function load(p:Ptr, off:Int):Lane {
		var f = F32x4.loadPtr(p, off);
		return of(F64x2.promoteLow(f), F64x2.promoteLow(f.swizzle(2, 3, 0, 1)));
	}

	@:hxmc.unsafe(gc) public inline function store(p:Ptr, off:Int)
		F32x4.demote(this.lo).shuffle(F32x4.demote(this.hi), 0, 1, 4, 5).storePtr(p, off);

	public inline function f32():F32x4
		return F32x4.demote(this.lo).shuffle(F32x4.demote(this.hi), 0, 1, 4, 5);

	public static inline function ofF32(f:F32x4):Lane
		return of(F64x2.promoteLow(f), F64x2.promoteLow(f.swizzle(2, 3, 0, 1)));

	@:op(A + B) inline function add(b:Lane):Lane
		return of(this.lo + b.lo(), this.hi + b.hi());

	@:op(A - B) inline function sub(b:Lane):Lane
		return of(this.lo - b.lo(), this.hi - b.hi());

	@:op(A * B) inline function mul(b:Lane):Lane
		return of(this.lo * b.lo(), this.hi * b.hi());

	@:op(A / B) inline function div(b:Lane):Lane
		return of(this.lo / b.lo(), this.hi / b.hi());

	@:op(-A) inline function neg():Lane
		return of(-this.lo, -this.hi);

	// (Math.min and max: x < y ? x : y, y < x ? x : y on hxmc)
	public inline function min(b:Lane):Lane
		return of(b.lo().pmin(this.lo), b.hi().pmin(this.hi));

	public inline function max(b:Lane):Lane
		return of(b.lo().pmax(this.lo), b.hi().pmax(this.hi));

	public inline function abs():Lane
		return of(this.lo.abs(), this.hi.abs());

	public inline function sqrt():Lane
		return of(this.lo.sqrt(), this.hi.sqrt());

	public inline function floor():Lane
		return of(this.lo.floor(), this.hi.floor());

	public inline function ceil():Lane
		return of(this.lo.ceil(), this.hi.ceil());

	static inline function narrow(lo:hxmc.simd.I64x2, hi:hxmc.simd.I64x2):LaneBool
		return LaneBool.of(lo.asI32x4().shuffle(hi.asI32x4(), 0, 2, 4, 6));

	public inline function eq(b:Lane):LaneBool
		return narrow(this.lo.eq(b.lo()), this.hi.eq(b.hi()));

	public inline function ne(b:Lane):LaneBool
		return narrow(this.lo.ne(b.lo()), this.hi.ne(b.hi()));

	public inline function lt(b:Lane):LaneBool
		return narrow(this.lo.lt(b.lo()), this.hi.lt(b.hi()));

	public inline function le(b:Lane):LaneBool
		return narrow(this.lo.le(b.lo()), this.hi.le(b.hi()));

	public inline function gt(b:Lane):LaneBool
		return narrow(this.lo.gt(b.lo()), this.hi.gt(b.hi()));

	public inline function ge(b:Lane):LaneBool
		return narrow(this.lo.ge(b.lo()), this.hi.ge(b.hi()));

	public static inline function select(m:LaneBool, a:Lane, b:Lane):Lane {
		var k = m.bits();
		return of(F64x2.select(cast k.swizzle(0, 0, 1, 1), a.lo(), b.lo()), F64x2.select(cast k.swizzle(2, 2, 3, 3), a.hi(), b.hi()));
	}

	public static inline function ofInt(v:LaneInt):Lane
		return of(F64x2.fromI32x4Low(v.bits()), F64x2.fromI32x4Low(v.bits().swizzle(2, 3, 0, 1)));

	// truncated, as Std.int
	public inline function toInt():LaneInt
		return LaneInt.make(Std.int(get(0)), Std.int(get(1)), Std.int(get(2)), Std.int(get(3)));
}

@:hxmc.struct @:noCompletion final class LaneData {
	public final lo:F64x2;
	public final hi:F64x2;

	public inline function new(lo:F64x2, hi:F64x2) {
		this.lo = lo;
		this.hi = hi;
	}
}
#else
abstract Lane(F32x4) {
	inline function new(v:F32x4)
		this = v;

	public inline function f32():F32x4
		return this;

	public static inline function ofF32(f:F32x4):Lane
		return new Lane(f);

	public static inline function splat(x:Float):Lane
		return new Lane(F32x4.splat(x));

	public static inline function make(a:Float, b:Float, c:Float, d:Float):Lane
		return new Lane(F32x4.make(a, b, c, d));

	public static inline function zero():Lane
		return new Lane(F32x4.zero());

	public inline function get(i:Int):Float
		return this.get(i);

	@:hxmc.unsafe(gc) public static inline function load(p:Ptr, off:Int):Lane
		return new Lane(F32x4.loadPtr(p, off));

	@:hxmc.unsafe(gc) public inline function store(p:Ptr, off:Int)
		this.storePtr(p, off);

	@:op(A + B) inline function add(b:Lane):Lane
		return new Lane(this + b.f32());

	@:op(A - B) inline function sub(b:Lane):Lane
		return new Lane(this - b.f32());

	@:op(A * B) inline function mul(b:Lane):Lane
		return new Lane(this * b.f32());

	@:op(A / B) inline function div(b:Lane):Lane
		return new Lane(this / b.f32());

	@:op(-A) inline function neg():Lane
		return new Lane(-this);

	// (Math.min and max: x < y ? x : y, y < x ? x : y on hxmc)
	public inline function min(b:Lane):Lane
		return new Lane(b.f32().pmin(this));

	public inline function max(b:Lane):Lane
		return new Lane(b.f32().pmax(this));

	public inline function abs():Lane
		return new Lane(this.abs());

	public inline function sqrt():Lane
		return new Lane(this.sqrt());

	public inline function floor():Lane
		return new Lane(this.floor());

	public inline function ceil():Lane
		return new Lane(this.ceil());

	public inline function eq(b:Lane):LaneBool
		return LaneBool.of(this.eq(b.f32()));

	public inline function ne(b:Lane):LaneBool
		return LaneBool.of(this.ne(b.f32()));

	public inline function lt(b:Lane):LaneBool
		return LaneBool.of(this.lt(b.f32()));

	public inline function le(b:Lane):LaneBool
		return LaneBool.of(this.le(b.f32()));

	public inline function gt(b:Lane):LaneBool
		return LaneBool.of(this.gt(b.f32()));

	public inline function ge(b:Lane):LaneBool
		return LaneBool.of(this.ge(b.f32()));

	public static inline function select(m:LaneBool, a:Lane, b:Lane):Lane
		return new Lane(F32x4.select(m.bits(), a.f32(), b.f32()));

	public static inline function ofInt(v:LaneInt):Lane
		return new Lane(F32x4.fromI32x4(v.bits()));

	// truncated, as Std.int
	public inline function toInt():LaneInt
		return LaneInt.of(this.toI32x4());
}
#end
