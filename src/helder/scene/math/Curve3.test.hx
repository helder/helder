package helder.scene.math;

import helder.gfx.shader.Vec3;
import helder.test.Test;

// Curve3 on the CPU: lengths (a line's, a straight Bezier's, a circle's
// through a closed Catmull-Rom, a path's), points by distance, frames
// that are orthonormal and do not flip (a helix, a curve that bends back),
// a closed one's ends meeting.
function tests() {
	describe("Curve3", () -> {
		test("a line's and a straight Bezier's length, points by distance", () -> {
			var l = Curve3.line(new Vec3(0, 0, 0), new Vec3(3, 4, 0));
			approx(l.length, 5, 1e-9);
			approx(l.pointAt(2.5).x, 1.5, 1e-9);
			var b = Curve3.bezier(new Vec3(0, 0, 0), new Vec3(1, 0, 0), new Vec3(2, 0, 0), new Vec3(3, 0, 0));
			approx(b.length, 3, 1e-6);
			approx(b.pointAt(1).x, 1, 1e-3);
			approx(b.tangent(0.5).x, 1, 1e-6);
		});
		test("a closed Catmull-Rom through a circle's points: its length 2 pi", () -> {
			var c = Curve3.catmullRom([for (k in 0...32) new Vec3(Math.cos(k / 32 * Math.PI * 2), 0, Math.sin(k / 32 * Math.PI * 2))], true);
			approx(c.length, Math.PI * 2, 0.01);
			// (through its points, back to the first)
			approx(c.point(0).x, 1, 1e-9);
			approx(c.point(1).x, 1, 1e-9);
			approx(curveLen(c.pointAt(c.length * 0.37)), 1, 2e-3);
		});
		test("a path: its curves end to end, by length", () -> {
			var p = Curve3.path([Curve3.line(new Vec3(0, 0, 0), new Vec3(1, 0, 0)), Curve3.line(new Vec3(1, 0, 0), new Vec3(1, 3, 0))]);
			approx(p.length, 4, 1e-6);
			approx(p.pointAt(2).y, 1, 1e-3);
			approx(p.point(0.125).x, 0.5, 1e-3);
		});
		test("frames: orthonormal, without flips, a closed curve's ends meeting", () -> {
			var helix = Curve3.catmullRom([for (k in 0...24) new Vec3(Math.cos(k * 0.6), k * 0.15, Math.sin(k * 0.6))]);
			// (an S: Frenet's normal flips at its inflection, parallel transport's does not)
			var s = Curve3.bezier(new Vec3(0, 0, 0), new Vec3(2, 2, 0), new Vec3(-1, 2, 0), new Vec3(1, 4, 0));
			for (c in [helix, s]) {
				var f = c.frames(64);
				equals(f.normals.length, 65);
				for (i in 0...65) {
					var t = f.tangents[i], n = f.normals[i], b = f.binormals[i];
					approx(curveLen(n), 1, 1e-6);
					approx(curveLen(b), 1, 1e-6);
					approx(curveDot(t, n), 0, 1e-6);
					approx(curveDot(n, b), 0, 1e-6);
					if (i > 0) assert(curveDot(n, f.normals[i - 1]) > 0.8, 'frame $i turns by little');
				}
			}
			var ring = Curve3.catmullRom([for (k in 0...12) new Vec3(Math.cos(k / 12 * Math.PI * 2), Math.sin(k * 1.3) * 0.2, Math.sin(k / 12 * Math.PI * 2))], true);
			var f = ring.frames(48, true);
			approx(curveDot(f.normals[0], f.normals[48]), 1, 1e-4);
		});
	});
}

// (module-level, not local functions: hxmc mixes up a local closure of
// Vec3s with another test file's of Vec4s for now)
private function curveLen(v:Vec3):Float
	return Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);

private function curveDot(a:Vec3, b:Vec3):Float
	return a.x * b.x + a.y * b.y + a.z * b.z;
