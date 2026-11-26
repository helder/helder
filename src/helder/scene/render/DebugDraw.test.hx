package helder.scene.render;

import helder.math.Mat4;
import helder.math.Vec3;
import helder.scene.World;
import helder.scene.math.Aabb;
import helder.scene.math.Curve3;
import helder.math.Quat;
import helder.test.Test;

// DebugDraw's calls without a GPU: the segments each writes into the ring
// (the depth-tested one, or overlay's), a colour as written (0xRRGGBB into
// linear light), the ring's capacity (calls past it dropped and counted),
// Lines' records as the renderer uploads them (a polyline's neighbours
// padded, distances along it), and none of it allocating (natively and as
// wasm32-wasi). Drawn: the 3d lane's debugdraw and helpers frames.
function tests() {
	describe("DebugDraw", () -> {
		test("each call's segments", () -> {
			clearRings();
			DebugDraw.line(new Vec3(0, 0, 0), new Vec3(1, 0, 0));
			equals(ringCount(0), 1);
			DebugDraw.aabb(new Aabb(new Vec3(0, 0, 0), new Vec3(1, 1, 1)));
			equals(ringCount(0), 13);
			DebugDraw.sphere(new Vec3(0, 0, 0), 1, 0xFFFFFF, 16);
			equals(ringCount(0), 13 + 48);
			DebugDraw.axes(Mat4.identity());
			equals(ringCount(0), 64);
			DebugDraw.grid(new Vec3(0, 0, 0), 4, 4);
			equals(ringCount(0), 74);
			DebugDraw.overlay = true;
			DebugDraw.ray(new Vec3(0, 0, 0), new Vec3(0, 1, 0));
			DebugDraw.overlay = false;
			equals(ringCount(1), 5, "a ray and its head's four, over everything");
		});
		test("a colour as written: 0xRRGGBB into linear light", () -> {
			clearRings();
			DebugDraw.line(new Vec3(0, 0, 0), new Vec3(1, 0, 0), 0xFF8000);
			var r = @:privateAccess DebugDraw.rings[0];
			approx(r[6], 1);
			approx(r[7], Math.pow(128 / 255, 2.2), 1e-9);
			approx(r[8], 0);
		});
		test("past its capacity: dropped, counted", () -> {
			clearRings();
			var before = DebugDraw.dropped, cap = DebugDraw.capacity;
			for (_ in 0...cap + 10)
				DebugDraw.line(new Vec3(0, 0, 0), new Vec3(1, 0, 0));
			equals(ringCount(0), cap);
			equals(DebugDraw.dropped - before, 10);
			clearRings();
		});
		test("Lines' records: a polyline padded with its ends, its distances along", () -> {
			var l = new Lines(4);
			l.count = 3;
			l.setPoint(0, 0, 0, 0);
			l.setPoint(1, 3, 0, 0);
			l.setPoint(2, 3, 4, 0);
			l.prepare();
			equals(l.drawn, 2);
			// (the first again, the three, the last again)
			approx(l.data.getFloat(0), 0);
			approx(l.data.getFloat(32 + 12), 0);
			approx(l.data.getFloat(64), 3);
			approx(l.data.getFloat(64 + 12), 3);
			approx(l.data.getFloat(96 + 12), 7);
			approx(l.data.getFloat(128 + 4), 4);
			l.closed = true;
			l.count = 3;
			l.prepare();
			equals(l.drawn, 3);
			// (the last before the first; the first and second after the last, 12 round)
			approx(l.data.getFloat(4), 4);
			approx(l.data.getFloat(128 + 12), 12);
		});
		test("calls and a frame's records allocate nothing", () -> {
			var w = new World();
			var lamp = w.node("lamp");
			Light.attach(lamp, Light.spot(new Vec3(1, 0.5, 0.2), 2, 3, 0.2, 0.4));
			var eye = w.node("eye");
			var cam = helder.scene.Camera.attach(eye, helder.scene.Camera.perspective(1, 0.1, 10));
			var chain = [w.node("a")];
			chain.push(w.node("b", chain[0]));
			chain.push(w.node("c", chain[1]));
			var curve = Curve3.catmullRom([new Vec3(0, 0, 0), new Vec3(1, 1, 0), new Vec3(2, 0, 1)]);
			var box = new Aabb(new Vec3(0, 0, 0), new Vec3(1, 1, 1));
			var lines = new Lines(64, {closed: true});
			function frame(k:Int) {
				clearRings();
				var t = Quat.fromEuler(k * 0.1, 0, 0).toMat4();
				DebugDraw.line(new Vec3(0, 0, 0), new Vec3(1, k, 0), 0xFF0000);
				DebugDraw.ray(new Vec3(0, 0, 0), new Vec3(0, 1, 0), 2);
				DebugDraw.arrow(new Vec3(0, 0, 0), new Vec3(1, 1, 1));
				DebugDraw.aabb(box);
				DebugDraw.boxOf(t, new Vec3(-1, -1, -1), new Vec3(1, 1, 1));
				DebugDraw.sphere(new Vec3(0, k, 0), 1);
				DebugDraw.circle(new Vec3(0, 0, 0), new Vec3(0, 1, 0), 2);
				DebugDraw.cross3(new Vec3(1, 1, 1));
				DebugDraw.axes(t);
				DebugDraw.grid(new Vec3(0, 0, 0));
				DebugDraw.frustum(cam, 1.5);
				DebugDraw.light(lamp);
				DebugDraw.bones(chain);
				DebugDraw.path(curve, 16);
				lines.count = 64;
				for (i in 0...64)
					lines.setPoint(i, Math.cos(i + k), Math.sin(i), 0);
				lines.prepare();
			}
			frame(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 1...10)
				frame(k);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			clearRings();
			w.dispose();
		});
	});
}

private function ringCount(ring:Int):Int
	return @:privateAccess DebugDraw.counts[ring];

private function clearRings() {
	@:privateAccess DebugDraw.counts[0] = 0;
	@:privateAccess DebugDraw.counts[1] = 0;
}
