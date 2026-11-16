package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.test.Test;

// Spherical harmonics (Sh) against known functions: a uniform sky's
// irradiance is its radiance along every normal; a sky lit from above,
// max(y, 0), reflects 2/3 of it upward (Lambert's integral) within L2's
// error; a directional light's band-limited lobe; an equirectangular image
// of one colour the same as the function; the seven packed vectors (the
// shaders' polynomial) evaluate to irradiance; blending; half floats read.
function tests() {
	describe("Sh", () -> {
		final normals = [new Vec3(0, 1, 0), new Vec3(0, -1, 0), new Vec3(1, 0, 0), new Vec3(0, 0, -1), new Vec3(0.6, 0.48, -0.64)];
		test("a uniform sky: its radiance along every normal", () -> {
			var sh = Sh.ofFunction(d -> new Vec3(0.5, 1, 2));
			for (n in normals) {
				var e = sh.irradiance(n);
				approx(e.x, 0.5, 1e-3);
				approx(e.y, 1, 1e-3);
				approx(e.z, 2, 1e-3);
			}
		});
		test("a sky lit from above: Lambert's 2/3 upward, within L2's error", () -> {
			var sh = Sh.ofFunction(d -> {
				var y = Math.max(d.y, 0);
				return new Vec3(y, y, y);
			});
			// (the exact irradiance over pi: 2/3 facing up, 1/6 sideways (L2's
			// 0.211: its error is largest there), 0 facing down)
			approx(sh.irradiance(new Vec3(0, 1, 0)).x, 2 / 3, 0.03);
			approx(sh.irradiance(new Vec3(1, 0, 0)).x, 1 / 6, 0.05);
			approx(sh.irradiance(new Vec3(0, -1, 0)).x, 0, 0.03);
		});
		test("a directional light: its band-limited cosine lobe", () -> {
			var sh = new Sh().addDirectional(new Vec3(0, 1, 0), new Vec3(1, 1, 1));
			// (along the light: (1 + 2 + 1.25) / 4pi; the exact clamped cosine's 1 / pi)
			approx(sh.irradiance(new Vec3(0, 1, 0)).x, 4.25 / (4 * Math.PI), 1e-4);
			assert(Math.abs(sh.irradiance(new Vec3(0, 1, 0)).x - 1 / Math.PI) < 0.025);
			approx(sh.irradiance(new Vec3(0, -1, 0)).x, 0, 0.02);
		});
		test("an equirectangular image of one colour: the function's", () -> {
			var w = 32, h = 16;
			var rgba = Bytes.alloc(w * h * 4);
			for (p in 0...w * h) {
				rgba.set(4 * p, 255);
				rgba.set(4 * p + 1, 128);
				rgba.set(4 * p + 2, 0);
				rgba.set(4 * p + 3, 255);
			}
			var sh = Sh.ofEquirect(w, h, rgba);
			var g = Math.pow(128 / 255, 2.2);
			for (n in normals) {
				var e = sh.irradiance(n);
				// (a 32 x 16 grid's quadrature: within half a percent)
				approx(e.x, 1, 5e-3);
				approx(e.y, g, 5e-3);
				approx(e.z, 0, 1e-6);
			}
			// (an image brighter above: its north half white, its south black)
			for (p in 0...w * h)
				for (c in 0...3)
					rgba.set(4 * p + c, p < w * h / 2 ? 255 : 0);
			var sky = Sh.ofEquirect(w, h, rgba);
			assert(sky.irradiance(new Vec3(0, 1, 0)).x > 0.9);
			assert(sky.irradiance(new Vec3(0, -1, 0)).x < 0.1);
			approx(sky.irradiance(new Vec3(1, 0, 0)).x, 0.5, 0.02);
		});
		test("the packed vectors: the shaders' polynomial is irradiance", () -> {
			var sh = Sh.ofFunction(d -> new Vec3(Math.max(d.x, 0) + 0.2, d.y * d.y, Math.max(-d.z, 0) * d.x * d.x + 0.1));
			var v:Array<Vec4> = [for (_ in 0...7) new Vec4(0, 0, 0, 0)];
			sh.pack(v);
			for (n in normals) {
				var n4 = new Vec4(n.x, n.y, n.z, 1), b = new Vec4(n.x * n.y, n.y * n.z, n.z * n.z, n.z * n.x), c = n.x * n.x - n.y * n.y;
				inline function dot(a:Vec4, b:Vec4)
					return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
				var e = sh.irradiance(n);
				approx(dot(v[0], n4) + dot(v[3], b) + v[6].x * c, e.x, 1e-9);
				approx(dot(v[1], n4) + dot(v[4], b) + v[6].y * c, e.y, 1e-9);
				approx(dot(v[2], n4) + dot(v[5], b) + v[6].z * c, e.z, 1e-9);
			}
		});
		test("blended, scaled, a hemisphere's", () -> {
			var a = Sh.ofFunction(d -> new Vec3(1, 1, 1)), b = Sh.ofFunction(d -> new Vec3(3, 3, 3));
			var m = new Sh().setLerp(a, b, 0.25);
			approx(m.irradiance(new Vec3(0, 1, 0)).x, 1.5, 1e-3);
			approx(m.copy().scale(2).irradiance(new Vec3(0, 1, 0)).x, 3, 2e-3);
			var hemi = Sh.ofHemisphere(new Vec3(1, 1, 1), new Vec3(0, 0, 0));
			// (the standard material's ambient: the normal's height blends them, half way at the horizon)
			approx(hemi.irradiance(new Vec3(1, 0, 0)).x, 0.5, 0.01);
			assert(hemi.irradiance(new Vec3(0, 1, 0)).x > 0.8);
		});
		test("half floats", () -> {
			approx(Sh.half(0x3C00), 1, 0);
			approx(Sh.half(0xC000), -2, 0);
			approx(Sh.half(0x3555), 0.333251953125, 0);
			approx(Sh.half(0x0001), Math.pow(2, -24), 0);
		});
	});
}
