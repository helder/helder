package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.test.Test;

// The frame's local lights (FrameLights, no device): those whose reach
// meets the view gathered, the most important to it first, at most its
// capacity (the rest counted as dropped); a draw's eight, the lights that
// reach its bounds most, listed by row; the frame's lights' texture's rows
// out (its arrays one after the other), a spot's cone as the smoothstep's
// scale and offset; gather and select allocating nothing. Each test's
// worlds are disposed after it.
function tests() {
	describe("FrameLights", () -> {
		final worlds:Array<World> = [];
		afterEach(() -> {
			for (w in worlds)
				w.dispose();
			worlds.resize(0);
		});
		test("gathered: in view, the most important first, at most the capacity", () -> {
			var w = new World();
			worlds.push(w);
			// (behind the camera, out of reach: left out)
			point(w, new Vec3(0, 0, 10), 1, 2);
			var near = point(w, new Vec3(0, 0, -5), 1, 2);
			var bright = point(w, new Vec3(0, 0, -20), 50, 2);
			var dim = point(w, new Vec3(3, 0, -30), 0.5, 2);
			var l = new FrameLights();
			l.gather(w, EYE, VP);
			equals(l.count, 3);
			equals(l.lights[0], bright);
			equals(l.lights[1], near);
			equals(l.lights[2], dim);
			// (seventy more: sixty-four kept, the least important dropped)
			for (k in 0...70)
				point(w, new Vec3(k % 10 - 5, 0, -40 - k), 0.1, 2);
			l.gather(w, EYE, VP);
			equals(l.count, FrameLights.MAX_LIGHTS);
			equals(l.dropped, 73 - FrameLights.MAX_LIGHTS);
			equals(l.lights[0], bright);
			assert(l.lights.indexOf(near) >= 0, "the near one kept");
		});
		test("a draw's eight: those that reach its bounds most, by row", () -> {
			var w = new World();
			worlds.push(w);
			for (k in 0...12)
				point(w, new Vec3(Math.cos(k) * 2, 0, -10 + Math.sin(k) * 2), 1 + k, 4);
			// (one far off the draw: never in its list)
			point(w, new Vec3(30, 0, -50), 100, 4);
			var l = new FrameLights();
			l.gather(w, EYE, VP);
			var out = [for (_ in 0...8) 0.0];
			l.select(0, 0, -10, 0.5, out, 0);
			for (i in 1...8)
				assert(out[i] > out[i - 1], 'by row: $out');
			var far = l.lights.indexOf(w.store(Light.KIND).valueAt(12));
			assert(out.indexOf(far) < 0, "the far light not listed");
			// (the brightest of the twelve listed: the last four made, 9 to 12)
			for (k in 8...12)
				assert(out.indexOf(l.lights.indexOf(w.store(Light.KIND).valueAt(k))) >= 0, 'light $k listed');
			// (out of every light's reach: none)
			l.select(0, 0, -60, 0.5, out, 0);
			for (i in 0...8)
				equals(out[i], -1.0);
		});
		test("the texture's rows: positions, colours, cones; a spot's cone", () -> {
			var w = new World();
			worlds.push(w);
			var n = w.node();
			n.position = new Vec3(1, 2, -3);
			Light.attach(n, Light.spot(new Vec3(1, 0.5, 0.25), 2, 6, 0.3, 0.5));
			var l = new FrameLights();
			l.gather(w, EYE, VP);
			var b = Bytes.alloc(FrameLights.MAX_LIGHTS * FrameLights.ROW);
			l.writeTexels(b);
			// (a row a light: its position, colour and cone, a texel each)
			var colors = 16, cones = 32;
			approx(b.getFloat(0), 1, 1e-6);
			approx(b.getFloat(4), 2, 1e-6);
			approx(b.getFloat(12), 6, 1e-6);
			// (its colour times its intensity, one array on)
			approx(b.getFloat(colors), 2, 1e-6);
			approx(b.getFloat(colors + 8), 0.5, 1e-6);
			// (its cone: down -z, the smoothstep from cos 0.5 to cos 0.3 from one dot)
			var scale = 1 / (Math.cos(0.3) - Math.cos(0.5));
			approx(b.getFloat(cones + 8), -scale, 1e-4);
			approx(b.getFloat(cones + 12), -Math.cos(0.5) * scale, 1e-4);
			// (a dot at the inner cone's cosine: 1; at the outer's: 0)
			approx(Math.cos(0.3) * scale + b.getFloat(cones + 12), 1, 1e-4);
			approx(Math.cos(0.5) * scale + b.getFloat(cones + 12), 0, 1e-4);
		});
		test("gather and select allocate nothing", () -> {
			var w = new World();
			worlds.push(w);
			for (k in 0...40)
				point(w, new Vec3(k % 8 - 4, 0, -5 - k), 1, 3);
			var l = new FrameLights(), out = [for (_ in 0...8) 0.0];
			l.gather(w, EYE, VP);
			#if (target.name == "hxmc")
			var before = hxmc.GcStats.bytesAllocated();
			l.gather(w, EYE, VP);
			l.select(0, 0, -10, 1, out, 0);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			#end
		});
	});
}

// (a camera at the origin looking down -z, 90 degrees: module-level, a
// closure cannot hold a struct local)
private final VP = Mat4.perspective(Math.PI / 2, 1, 0.1, 1000) * MathTools.lookAt(new Vec3(0, 0, 0), new Vec3(0, 0, -1), new Vec3(0, 1, 0));
private final EYE = new Vec3(0, 0, 0);

// (a point light at p)
private function point(w:World, p:Vec3, intensity:Float, range:Float):Light {
	var n = w.node();
	n.position = p;
	return Light.attach(n, Light.pointLight(new Vec3(1, 1, 1), intensity, range));
}
