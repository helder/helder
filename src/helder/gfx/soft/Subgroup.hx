package helder.gfx.soft;

// A compute stage's subgroup operations on the CPU (helder.gfx.shader.Soft's
// compute form): a call's 4 lanes are a subgroup, the lanes of m (those of
// the workgroup) taking part, in lane order; a vector's componentwise (Soft
// splits it). A lane past them reads lane 0's.
class Subgroup {
	public static inline function addFloat(m:LaneBool, x:Lane):Lane
		return Lane.splat((m.get(0) ? x.get(0) : 0.0) + (m.get(1) ? x.get(1) : 0.0) + (m.get(2) ? x.get(2) : 0.0) + (m.get(3) ? x.get(3) : 0.0));

	public static inline function addInt(m:LaneBool, x:LaneInt):LaneInt
		return LaneInt.splat((m.get(0) ? x.get(0) : 0) + (m.get(1) ? x.get(1) : 0) + (m.get(2) ? x.get(2) : 0) + (m.get(3) ? x.get(3) : 0));

	public static function minFloat(m:LaneBool, x:Lane):Lane {
		var r = x.get(0);
		if (m.get(1) && x.get(1) < r) r = x.get(1);
		if (m.get(2) && x.get(2) < r) r = x.get(2);
		if (m.get(3) && x.get(3) < r) r = x.get(3);
		return Lane.splat(r);
	}

	public static function maxFloat(m:LaneBool, x:Lane):Lane {
		var r = x.get(0);
		if (m.get(1) && x.get(1) > r) r = x.get(1);
		if (m.get(2) && x.get(2) > r) r = x.get(2);
		if (m.get(3) && x.get(3) > r) r = x.get(3);
		return Lane.splat(r);
	}

	public static function minInt(m:LaneBool, x:LaneInt):LaneInt {
		var r = x.get(0);
		if (m.get(1) && x.get(1) < r) r = x.get(1);
		if (m.get(2) && x.get(2) < r) r = x.get(2);
		if (m.get(3) && x.get(3) < r) r = x.get(3);
		return LaneInt.splat(r);
	}

	public static function maxInt(m:LaneBool, x:LaneInt):LaneInt {
		var r = x.get(0);
		if (m.get(1) && x.get(1) > r) r = x.get(1);
		if (m.get(2) && x.get(2) > r) r = x.get(2);
		if (m.get(3) && x.get(3) > r) r = x.get(3);
		return LaneInt.splat(r);
	}

	// (lane: a constant)
	public static inline function broadcastFloat(x:Lane, lane:Int):Lane
		return Lane.splat(x.get(lane));

	public static inline function broadcastInt(x:LaneInt, lane:Int):LaneInt
		return LaneInt.splat(x.get(lane));

	// (each lane its own: lane & 3)
	public static function shuffleFloat(x:Lane, lane:LaneInt):Lane
		return Lane.make(floatAt(x, lane.get(0)), floatAt(x, lane.get(1)), floatAt(x, lane.get(2)), floatAt(x, lane.get(3)));

	public static function shuffleInt(x:LaneInt, lane:LaneInt):LaneInt
		return LaneInt.make(intAt(x, lane.get(0)), intAt(x, lane.get(1)), intAt(x, lane.get(2)), intAt(x, lane.get(3)));

	public static inline function all(m:LaneBool, b:LaneBool):LaneBool
		return LaneBool.splat((b | !m).all());

	public static inline function any(m:LaneBool, b:LaneBool):LaneBool
		return LaneBool.splat((b & m).any());

	// (hxmc.simd's lanes read by constants)
	static inline function floatAt(x:Lane, k:Int):Float
		return switch k & 3 {
			case 0: x.get(0);
			case 1: x.get(1);
			case 2: x.get(2);
			case _: x.get(3);
		}

	static inline function intAt(x:LaneInt, k:Int):Int
		return switch k & 3 {
			case 0: x.get(0);
			case 1: x.get(1);
			case 2: x.get(2);
			case _: x.get(3);
		}
}
