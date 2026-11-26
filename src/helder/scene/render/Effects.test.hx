package helder.scene.render;

import helder.gfx.Device;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.World;
import helder.scene.render.EffectShaders.octDecode;
import helder.scene.render.EffectShaders.viewPointAt;
import helder.scene.render.PbrShader.octEncode;
import helder.scene.render.PostShader.cocOf;
import helder.scene.render.PostShader.viewDepthAt;
import helder.test.Test;

// Post's effects on the CPU (their shaders' functions run as they are,
// natively and as wasm32-wasi): the view buffers' normals (octahedral)
// back as they went in, a point's depth from the view buffers' depth
// (Camera's projection inverted), depth of field's circle of confusion for
// both lenses, the selection as data (a node's group, its descendants'
// through the nearest selected, nothing allocated looking it up), a LUT's
// strip. The frames: tests/3d/EffectScenes.hx.
function tests() {
	describe("post effects", () -> {
		test("a normal through octEncode and octDecode is itself", () -> {
			for (n in [new Vec3(0, 0, 1), new Vec3(0, 0, -1), new Vec3(0.6, -0.8, 0), new Vec3(-0.3, 0.4, -0.866)]) {
				var e = octEncode(n);
				// (8 bits a channel, as the view buffers keep them)
				var q = new Vec2(Math.round(e.x * 255) / 255, Math.round(e.y * 255) / 255);
				var d = octDecode(q);
				approx(d.x, n.x, 0.02);
				approx(d.y, n.y, 0.02);
				approx(d.z, n.z, 0.02);
			}
		});
		test("a point's depth from the projected depth", () -> {
			var p = Mat4.perspective(0.9, 1.5, 0.1, 60);
			var inv = helder.scene.math.MathTools.inverse(p);
			for (z in [0.5, 3.0, 20.0, 55.0]) {
				var c = p * new Vec4(0.4, -0.2, -z, 1);
				var d = c.z / c.w, uv = new Vec2(c.x / c.w * 0.5 + 0.5, 0.5 - c.y / c.w * 0.5);
				approx(viewDepthAt(inv, uv, d), z, z * 1e-4);
				var v = viewPointAt(inv, uv, d);
				approx(v.x, 0.4, 1e-3);
				approx(v.y, -0.2, 1e-3);
			}
		});
		test("the circle of confusion: none in focus, growing away from it", () -> {
			var focus = Dof.focus({distance: 6, aperture: 0.04, radius: 0.03});
			var f = @:privateAccess focus.params();
			approx(cocOf(f, 6, 6), 0);
			approx(cocOf(f, 6, 12), 0.02, 1e-6);
			// (at most the radius: near the lens)
			approx(cocOf(f, 6, 0.5), 0.03, 1e-6);
			var tilt = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1, radius: 0.02});
			var t = @:privateAccess tilt.params();
			approx(cocOf(t, 10, 11.5), 0);
			approx(cocOf(t, 10, 25), 0.02, 1e-6);
			equals(cocOf(t, 10, 13) > 0 && cocOf(t, 10, 13) < 0.02, true);
			tilt.strength = 0.5;
			approx(cocOf(@:privateAccess tilt.params(), 10, 25), 0.01, 1e-6);
		});
		test("a node's selection group, its descendants' the nearest's, nothing allocated", () -> {
			var world = new World();
			var model = world.node("model"), arm = world.node("arm", model), hand = world.node("hand", arm), other = world.node("other");
			equals(ViewBuffers.groupOf(hand), 0);
			Outline.select(model, 3);
			Outline.select(hand, 5);
			equals(ViewBuffers.groupOf(model), 3);
			equals(ViewBuffers.groupOf(arm), 3);
			equals(ViewBuffers.groupOf(hand), 5);
			equals(ViewBuffers.groupOf(other), 0);
			equals(Outline.selected(arm), 0);
			#if (target.name == "hxmc")
			var before = hxmc.GcStats.bytesAllocated();
			var sum = 0;
			for (_ in 0...100)
				sum += ViewBuffers.groupOf(hand) + ViewBuffers.groupOf(arm) + ViewBuffers.groupOf(other);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			equals(sum, 800);
			#end
			Outline.select(model, 0);
			equals(ViewBuffers.groupOf(arm), 0);
			// (its slot of 16 freed for the next files' worlds)
			world.dispose();
		});
		test("a LUT's strip: size slices of size by size, red across, green down, blue by slice", () -> {
			var s = Lut.strip(4, (r, g, b) -> new Vec3(r, g, b));
			equals(s.length, 16 * 4 * 4);
			equals(s.get(0), 0);
			equals(s.get(3 * 4), 255);
			var last = (3 * 16 + 15) * 4;
			equals(s.get(last), 255);
			equals(s.get(last + 1), 255);
			equals(s.get(last + 2), 255);
			// (x 5: the second slice's second texel; blue a third)
			equals(s.get(5 * 4), 85);
			equals(s.get(5 * 4 + 2), 85);
		});
	});
}
