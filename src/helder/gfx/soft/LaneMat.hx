package helder.gfx.soft;

// a Mat4 in each of a call's 4 lanes: four columns of Lane4s
@:forward(c0, c1, c2, c3)
abstract LaneMat(LaneMatData) {
	public inline function new(c0:Lane4, c1:Lane4, c2:Lane4, c3:Lane4)
		this = new LaneMatData(c0, c1, c2, c3);

	public static inline function splat(m:helder.gfx.shader.Mat4):LaneMat
		return new LaneMat(Lane4.splat(m.c0), Lane4.splat(m.c1), Lane4.splat(m.c2), Lane4.splat(m.c3));

	public static inline function zero():LaneMat
		return new LaneMat(Lane4.zero(), Lane4.zero(), Lane4.zero(), Lane4.zero());

	public static inline function select(m:LaneBool, a:LaneMat, b:LaneMat):LaneMat
		return new LaneMat(Lane4.select(m, a.c0, b.c0), Lane4.select(m, a.c1, b.c1), Lane4.select(m, a.c2, b.c2), Lane4.select(m, a.c3, b.c3));

	@:op(A + B) static inline function add(a:LaneMat, b:LaneMat):LaneMat
		return new LaneMat(a.c0 + b.c0, a.c1 + b.c1, a.c2 + b.c2, a.c3 + b.c3);

	@:op(A - B) static inline function sub(a:LaneMat, b:LaneMat):LaneMat
		return new LaneMat(a.c0 - b.c0, a.c1 - b.c1, a.c2 - b.c2, a.c3 - b.c3);
}

@:hxmc.struct @:noCompletion final class LaneMatData {
	public final c0:Lane4;
	public final c1:Lane4;
	public final c2:Lane4;
	public final c3:Lane4;

	public inline function new(c0:Lane4, c1:Lane4, c2:Lane4, c3:Lane4) {
		this.c0 = c0;
		this.c1 = c1;
		this.c2 = c2;
		this.c3 = c3;
	}
}
