package helder.scene.render.shading;

import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.Material;
import helder.scene.render.PbrShader;
import helder.scene.render.shading.Lambert;
import helder.scene.render.shading.Phong;
import helder.scene.render.shading.Toon;
import helder.scene.render.shading.Unlit;
import helder.test.Test;

// The shading models' slots on the CPU (their functions as the GPU runs
// them): toon's ramp in steps bands, its shadow banded; Lambert's light the
// standard material's diffuse with no highlight; Blinn-Phong's shininess
// and Material.phong's roughness one lobe; the camera's axes unlit's view
// space reads (matcap, normals, depth) from a view-projection. The
// renderer drawing them: the 3d lane's "shading" and "toon" frames.
function tests() {
	describe("shading models", () -> {
		test("toon: steps bands, each edge soft, its shadow a band", () -> {
			for (steps in [1, 2, 3, 5]) {
				var seen = new Map<Int, Bool>();
				for (k in 0...200)
					seen.set(Math.round(ramp(k / 199, steps) * steps * 1000), true);
				// (the bands' values, and the soft edges' few between)
				var whole = [for (b in 0...steps + 1) seen.exists(b * 1000)];
				assert(!whole.contains(false), 'every band of $steps');
			}
			approx(ramp(0, 3), 0);
			approx(ramp(0.5, 3), 2 / 3);
			approx(ramp(1, 3), 1);
			// (in shadow: the ramp of n.l times the shadow, the band below)
			var m = materialOf(Material.toon({steps: 2}));
			var lit = toonDirect(surface(), light(1), {material: m}), dark = toonDirect(surface(), light(0), {material: m});
			assert(lit.x > 0 && dark.x == 0);
		});
		test("lambert: the standard diffuse, no highlight", () -> {
			// (the eye along the light's reflection: pbr's highlight peaks, Lambert's has none)
			var s = surface(new Vec3(-0.6, 0.8, 0));
			var l = light(1, new Vec3(0.6, 0.8, 0));
			var a = lambertDirect(s, l, {}), b = pbrDirect(s, l, {material: materialOf(new Material())});
			approx(a.x, 0.8 / Math.PI * 2, 1e-6);
			assert(b.x > a.x, "pbr's has its highlight");
		});
		test("phong: three's shininess kept as the roughness of the same lobe", () -> {
			for (shininess in [10.0, 30.0, 100.0]) {
				var m = Material.phong({shininess: shininess});
				approx(phongShininess(m.roughness), shininess, 1e-6);
			}
		});
		test("unlit's view space: the camera's axes from its view-projection", () -> {
			var eye = new Vec3(3, 2, 5);
			var view = MathTools.lookAt(eye, new Vec3(0, 0, 0), new Vec3(0, 1, 0));
			var f = frameOf(Mat4.perspective(0.9, 1.5, 0.1, 50) * view);
			for (d in [new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(0.3, -0.2, 0.9)]) {
				var want = MathTools.transformDir(view, d), got = toView(f, d);
				approx(got.x, want.x, 1e-6);
				approx(got.y, want.y, 1e-6);
				approx(got.z, want.z, 1e-6);
			}
		});
	});
}

// (module-level, not local functions: hxmc mixes up local closures of
// struct values of different types for now)

// (a white surface facing up, the eye straight above, or along view)
private function surface(?view:Vec3):LitSurface
	return {
		world: new Vec3(0, 0, 0),
		normal: new Vec3(0, 1, 0),
		view: view ?? new Vec3(0, 1, 0),
		uv: new Vec2(0, 0),
		up: new Vec3(0, 1, 0),
		albedo: new Vec3(1, 1, 1),
		alpha: 1,
		metalness: 0,
		roughness: 0.3
	};

// (a light of colour 2 along d, n.l 0.8 by default, shadowed by 1 - lit)
private function light(lit:Float, ?d:Vec3):LightSample {
	var dir = d ?? new Vec3(0.6, 0.8, 0);
	var c = new Vec3(2, 2, 2);
	return {
		color: c,
		shadow: lit,
		radiance: c * lit,
		direction: dir,
		ndotl: dir.y
	};
}

private function frameOf(viewProj:Mat4):PbrFrame {
	var zero = new Vec4(0, 0, 0, 0);
	return {
		viewProj: viewProj, eye: zero, lightDir: zero, lightColor: zero, sky: zero, ground: zero, exposure: zero, lightViewProj: Mat4.identity(), shadow: zero,
		lightViewProjFar: Mat4.identity(), shadowFar: zero, shadowRect: zero, shadowRectFar: zero, shadowAtlas: zero, environment: zero, rim: zero, fog: zero,
		fogShape: zero, shadowSoft: zero, clusters: zero, clusterDepth: zero, clusterAxis: zero
	};
}
