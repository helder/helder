import helder.math.Mat4;
import helder.math.Vec2;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.math.Quat;

// helder's math types (helder.math's vectors, matrix and
// quaternion: struct values) crossing to TypeScript as helder/math's classes
// (tests/typescript/helder/math.ts): arguments, results, a field, a property.
class MathProbe {
	// where it is (a struct stored in the object)
	public var at:Vec3;
	// its turn (a property: through its accessors)
	public var turn(get, set):Quat;

	var q = Quat.identity();

	public function new(at:Vec3)
		this.at = at;

	function get_turn():Quat
		return q;

	function set_turn(v:Quat):Quat
		return q = v;

	// moved by d: where it is now
	public function moved(d:Vec3):Vec3 {
		at = at + d;
		return at;
	}

	public static function scaled(v:Vec3, s:Float):Vec3
		return v * s;

	public static function sum(a:Vec2, b:Vec4):Float
		return a.x + a.y + b.x + b.y + b.z + b.w;

	public static function translation(x:Float, y:Float, z:Float):Mat4
		return Mat4.translation(x, y, z);

	public static function apply(m:Mat4, v:Vec4):Vec4
		return m * v;

	public static function spin(a:Quat, b:Quat):Quat
		return a * b;

	// struct values a TypeScript function returns (math.ts): each called
	// from Haxe, its results read here (a Vec2, Vec3, Vec4, Quat, Mat4;
	// each function type's arguments its own: hxmc keys a closure's
	// signature by its result's being a struct, not by which, so that
	// () -> Vec3 and () -> Vec4 in one program do not compile)
	public static function made2(f:(x:Float, y:Float) -> Vec2):Float {
		var a = f(1, 2), b = f(3, 4);
		return a.x + a.y * 10 + b.x * 100 + b.y * 1000;
	}

	// (a struct given and one returned, n times: a grade's shape, Lut.strip's)
	public static function mapped3(v:Vec3, n:Int, f:(v:Vec3, i:Int) -> Vec3):Vec3 {
		var out = v;
		for (i in 0...n)
			out = f(out, i);
		return out;
	}

	public static function made4(f:(i:Int) -> Vec4):Vec4
		return f(1) + f(2);

	public static function turned(f:(angle:Float) -> Quat):Quat
		return f(0) * f(Math.PI / 2);

	public static function placed(f:(x:Float, y:Float, z:Float) -> Mat4, v:Vec4):Vec4
		return f(2, 0, 0) * (f(1, 2, 0) * v);

	// (a function kept, called later: its result read where it is called)
	static var kept:Null<() -> Vec3> = null;

	public static function keep(f:() -> Vec3)
		kept = f;

	public static function callKept():Vec3 {
		var f = kept;
		return f == null ? new Vec3(0, 0, 0) : f();
	}
}
