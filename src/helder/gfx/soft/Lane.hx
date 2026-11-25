package helder.gfx.soft;

import hxmc.simd.F32x4;
import hxmc.simd.F64x2;
import hxmc.simd.I32x4;
import hxmc.unsafe.Ptr;

// A Float in each of a call's 4 lanes: a 2x2 quad's pixels (lanes 0, 1 the
// top row, 2, 3 the bottom one: dFdx is lane 1 - lane 0, dFdy lane 2 -
// lane 0, as GPUs take them) or 4 vertices. float32, as GPUs compute; with
// -D helder.soft.exact two F64x2s, Haxe's own doubles, so that a shader's
// lanes equal its scalar code bit for bit (tests/gfx/SoftShaderCheck). The
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

	public static inline function constant(bits:Int, x:Float):Lane
		return splat(x);

	@:hxmc.unsafe(gc) public static inline function loadSplat(p:Ptr, off:Int):Lane
		return splat(hxmc.unsafe.Mem.getF32(p, off));

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

	// (Math.min and max: WebAssembly's on hxmc, NaN where either is, -0 below +0)
	public inline function min(b:Lane):Lane
		return of(this.lo.min(b.lo()), this.hi.min(b.hi()));

	public inline function max(b:Lane):Lane
		return of(this.lo.max(b.lo()), this.hi.max(b.hi()));

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

	// (lane by lane, Math's: the scalar code's own)
	public inline function exp():Lane
		return make(Math.exp(get(0)), Math.exp(get(1)), Math.exp(get(2)), Math.exp(get(3)));

	public inline function log():Lane
		return make(Math.log(get(0)), Math.log(get(1)), Math.log(get(2)), Math.log(get(3)));

	public inline function sin():Lane
		return make(Math.sin(get(0)), Math.sin(get(1)), Math.sin(get(2)), Math.sin(get(3)));

	public inline function cos():Lane
		return make(Math.cos(get(0)), Math.cos(get(1)), Math.cos(get(2)), Math.cos(get(3)));

	public inline function pow(y:Lane):Lane
		return make(Math.pow(get(0), y.get(0)), Math.pow(get(1), y.get(1)), Math.pow(get(2), y.get(2)), Math.pow(get(3), y.get(3)));
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

	// (a constant by its float32 bits)
	public static inline function constant(bits:Int, x:Float):Lane
		return new Lane(I32x4.splat(bits).asF32x4());

	// (the float32 at p + off in every lane, moved as its bits)
	@:hxmc.unsafe(gc) public static inline function loadSplat(p:Ptr, off:Int):Lane
		return new Lane(I32x4.splat(hxmc.unsafe.Mem.getI32(p, off)).asF32x4());

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

	// (Math.min and max: WebAssembly's on hxmc, NaN where either is, -0 below +0)
	public inline function min(b:Lane):Lane
		return new Lane(this.min(b.f32()));

	public inline function max(b:Lane):Lane
		return new Lane(this.max(b.f32()));

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

	// exp, log, pow, sin and cos over the lanes: Cephes' single-precision
	// polynomials (within 2 ulps of the true value over the range shading
	// takes them in, as GPUs' are approximations too), SIMD and without
	// fused multiply-adds, so that every machine computes the same bits
	public inline function exp():Lane {
		var x = this.clamp(F32x4.splat(-87.3), F32x4.splat(88.3));
		var n = (x * F32x4.splat(1.44269504088896341) + F32x4.splat(0.5)).floor();
		x = x - n * F32x4.splat(0.693359375) - n * F32x4.splat(-2.12194440e-4);
		var z = x * x;
		var y = F32x4.splat(1.9875691500E-4) * x + F32x4.splat(1.3981999507E-3);
		y = y * x + F32x4.splat(8.3334519073E-3);
		y = y * x + F32x4.splat(4.1665795894E-2);
		y = y * x + F32x4.splat(1.6666665459E-1);
		y = y * x + F32x4.splat(5.0000001201E-1);
		y = y * z + x + F32x4.splat(1);
		var scale = ((n.toI32x4() + I32x4.splat(127)) << 23).asF32x4();
		return new Lane(y * scale);
	}

	public inline function log():Lane {
		var bits = this.asI32x4();
		var e = F32x4.fromI32x4((bits >>> 23) - I32x4.splat(126));
		var m = ((bits & I32x4.splat(0x007FFFFF)) | I32x4.splat(0x3F000000)).asF32x4();
		var small = m.lt(F32x4.splat(0.707106781186547524));
		e = F32x4.select(small, e - F32x4.splat(1), e);
		m = F32x4.select(small, m + m, m) - F32x4.splat(1);
		var z = m * m;
		var y = F32x4.splat(7.0376836292E-2) * m - F32x4.splat(1.1514610310E-1);
		y = y * m + F32x4.splat(1.1676998740E-1);
		y = y * m - F32x4.splat(1.2420140846E-1);
		y = y * m + F32x4.splat(1.4249322787E-1);
		y = y * m - F32x4.splat(1.6668057665E-1);
		y = y * m + F32x4.splat(2.0000714765E-1);
		y = y * m - F32x4.splat(2.4999993993E-1);
		y = y * m + F32x4.splat(3.3333331174E-1);
		y = y * m * z;
		y = y + e * F32x4.splat(-2.12194440e-4);
		y = y - z * F32x4.splat(0.5);
		var r = m + y + e * F32x4.splat(0.693359375);
		// (0: -infinity; below it, or NaN: NaN; infinity itself)
		var zero = F32x4.zero();
		r = F32x4.select(this.eq(zero), F32x4.splat(Math.NEGATIVE_INFINITY), r);
		r = F32x4.select(this.ge(zero), r, F32x4.splat(Math.NaN));
		return new Lane(F32x4.select(this.eq(F32x4.splat(Math.POSITIVE_INFINITY)), this, r));
	}

	// (x^y as e^(y log x); 0^y 0, x^0 1, as Math.pow)
	public inline function pow(y:Lane):Lane {
		var r = (y * log()).exp().f32(), zero = F32x4.zero();
		r = F32x4.select(this.eq(zero), F32x4.select(y.f32().lt(zero), F32x4.splat(Math.POSITIVE_INFINITY), zero), r);
		return new Lane(F32x4.select(y.f32().eq(zero), F32x4.splat(1), r));
	}

	// (x's even octant: x over pi/4, rounded up to even; x less it times pi/4, in three parts)
	static inline function octant(x:F32x4):I32x4
		return ((x * F32x4.splat(1.27323954473516)).toI32x4() + I32x4.splat(1)) & I32x4.splat(~1);

	static inline function reduced(x:F32x4, j:I32x4):F32x4 {
		var y = F32x4.fromI32x4(j);
		return ((x - y * F32x4.splat(0.78515625)) - y * F32x4.splat(2.4187564849853515625e-4)) - y * F32x4.splat(3.77489497744594108e-8);
	}

	static inline function sinPoly(x:F32x4, z:F32x4):F32x4 {
		var y = F32x4.splat(-1.9515295891E-4) * z + F32x4.splat(8.3321608736E-3);
		y = y * z - F32x4.splat(1.6666654611E-1);
		return y * z * x + x;
	}

	static inline function cosPoly(z:F32x4):F32x4 {
		var y = F32x4.splat(2.443315711809948E-005) * z - F32x4.splat(1.388731625493765E-003);
		y = y * z + F32x4.splat(4.166664568298827E-002);
		return y * z * z - z * F32x4.splat(0.5) + F32x4.splat(1);
	}

	public inline function sin():Lane {
		var a = this.abs(), j = octant(a), r = reduced(a, j), z = r * r;
		var poly = F32x4.select((j & I32x4.splat(2)).ne(I32x4.zero()), cosPoly(z), sinPoly(r, z));
		var negative = this.lt(F32x4.zero()) ^ (j & I32x4.splat(4)).ne(I32x4.zero());
		return new Lane(F32x4.select(negative, -poly, poly));
	}

	public inline function cos():Lane {
		var a = this.abs(), k = octant(a), r = reduced(a, k), z = r * r;
		var j = k - I32x4.splat(2);
		var poly = F32x4.select((j & I32x4.splat(2)).ne(I32x4.zero()), cosPoly(z), sinPoly(r, z));
		var negative = (j & I32x4.splat(4)).eq(I32x4.zero());
		return new Lane(F32x4.select(negative, -poly, poly));
	}
}
#end
