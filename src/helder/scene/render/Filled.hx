package helder.scene.render;

import helder.math.Mat4;
import helder.math.Vec4;

// Arrays of n copies of a value, made by a loop: an array comprehension
// over a constant range ([for (_ in 0...24) 0.0]) is unrolled by the
// compiler into code a copy, 90 KB of a constructor for Shadows' tiles.
class Filled {
	public static function floats(n:Int, v:Float):Array<Float> {
		var a:Array<Float> = [];
		var i = 0;
		while (i < n) {
			a.push(v);
			i++;
		}
		return a;
	}

	public static function ints(n:Int, v:Int):Array<Int> {
		var a:Array<Int> = [];
		var i = 0;
		while (i < n) {
			a.push(v);
			i++;
		}
		return a;
	}

	public static function bools(n:Int):Array<Bool> {
		var a:Array<Bool> = [];
		var i = 0;
		while (i < n) {
			a.push(false);
			i++;
		}
		return a;
	}

	public static function vec4s(n:Int):Array<Vec4> {
		var a:Array<Vec4> = [];
		var i = 0;
		while (i < n) {
			a.push(new Vec4(0, 0, 0, 0));
			i++;
		}
		return a;
	}

	public static function mat4s(n:Int):Array<Mat4> {
		var a:Array<Mat4> = [];
		var i = 0;
		while (i < n) {
			a.push(Mat4.identity());
			i++;
		}
		return a;
	}

	public static function lights(n:Int):Array<Null<Light>> {
		var a:Array<Null<Light>> = [];
		var i = 0;
		while (i < n) {
			a.push(null);
			i++;
		}
		return a;
	}
}
