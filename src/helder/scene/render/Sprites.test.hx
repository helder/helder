package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.scene.math.MathTools;
import helder.test.Test;

// Sprites on the CPU (no device: their quad's mesh made by hand): the
// instance matrices prepare writes facing a camera (Spherical: the quad's
// normal to the camera, turned on the screen; Axis: upright along its
// axis), the atlas' cell in the matrix's last w, see-through ones sorted
// far to near, and a frame's writes and turn allocating nothing (natively
// and as wasm32-wasi). The renderer drawing them: the 3d lane's "sprites"
// frame (tests/3d/Scenes.hx).
function tests() {
	describe("Sprites", () -> {
		test("Spherical: facing the camera, sized, turned on the screen", () -> {
			var s = spritesMade(new Material(), 4);
			s.set(0, 1, 2, 0, 2, 3, Math.PI / 2, 0);
			s.prepare(spritesCamera());
			var r = spriteColumn(s, 0, 0), u = spriteColumn(s, 0, 1), n = spriteColumn(s, 0, 2), p = spriteColumn(s, 0, 3);
			// (a quarter turn: its width along the screen's up, its height along its left)
			approx(r.y, 2, 1e-6);
			approx(u.x, -3, 1e-6);
			approx(n.z, 1, 1e-6);
			approx(p.y, 2, 1e-6);
			approx(s.data.getFloat(60), 1, 1e-6, "the first cell: 1");
		});
		test("Axis: upright along its axis, its face as near the camera's as it can turn", () -> {
			var s = spritesMade(new Material(), 1, {mode: Axis});
			s.set(0, 0, 0, 0, 1, 2);
			// (the camera above and in front: the card stays upright)
			s.prepare(Mat4.perspective(1, 1, 0.1, 100) * MathTools.lookAt(new Vec3(0, 4, 5), new Vec3(0, 0, 0), new Vec3(0, 1, 0)));
			var u = spriteColumn(s, 0, 1), n = spriteColumn(s, 0, 2);
			approx(u.y, 2, 1e-6);
			approx(n.y, 0, 1e-6);
			approx(n.z, 1, 1e-6);
		});
		test("an atlas' cell in the matrix's last w, the material's uvs a cell's share", () -> {
			var m = new Material();
			var s = spritesMade(m, 2, {columns: 4, rows: 2});
			approx(m.uvScale.x, 0.25);
			approx(m.uvScale.y, 0.5);
			s.set(1, 0, 0, 0, 1, 1, 0, 6);
			s.prepare(spritesCamera());
			// (cell 6: column 2, row 1: 1 + 2 + 256)
			approx(s.data.getFloat(64 + 60), 259);
		});
		test("see-through by alpha: drawn far to near", () -> {
			var m = new Material();
			m.blend = Alpha;
			var s = spritesMade(m, 3);
			s.set(0, 0, 0, 2, 1, 1);
			s.set(1, 0, 0, -8, 1, 1);
			s.set(2, 0, 0, -2, 1, 1);
			s.prepare(spritesCamera());
			approx(spriteColumn(s, 0, 3).z, -8);
			approx(spriteColumn(s, 1, 3).z, -2);
			approx(spriteColumn(s, 2, 3).z, 2);
		});
		test("a frame's writes and turn allocate nothing", () -> {
			var m = new Material();
			m.blend = Alpha;
			var s = spritesMade(m, 1000, {mode: Spherical, columns: 4, rows: 4});
			function frame(t:Float) {
				for (i in 0...s.count) {
					var a = t + i * 0.01;
					s.set(i, Math.cos(a) * i * 0.01, Math.sin(a), -i * 0.02, 1, 1, a, i % 16);
					s.setColor(i, new Vec3(1, Math.sin(a) * 0.5 + 0.5, 1));
				}
				s.prepare(Mat4.perspective(1, 1, 0.1, 100) * MathTools.lookAt(new Vec3(Math.sin(t) * 5, 1, 5), new Vec3(0, 0, 0), new Vec3(0, 1, 0)));
			}
			frame(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 1...20)
				frame(k * 0.1);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}

// (module-level, not local functions: hxmc mixes up local closures that
// return structs of different types for now)

// (a camera at z 5 looking down -z: its view-projection)
private function spritesCamera():Mat4
	return Mat4.perspective(1, 1, 0.1, 100) * MathTools.lookAt(new Vec3(0, 0, 5), new Vec3(0, 0, 0), new Vec3(0, 1, 0));

private function spriteColumn(s:Sprites, i:Int, c:Int):Vec3
	return new Vec3(s.data.getFloat(i * 64 + c * 16), s.data.getFloat(i * 64 + c * 16 + 4), s.data.getFloat(i * 64 + c * 16 + 8));

private function spritesMade(material:Material, capacity:Int, ?o:Sprites.SpritesOptions):Sprites
	return new Sprites(null, material, capacity, o);
