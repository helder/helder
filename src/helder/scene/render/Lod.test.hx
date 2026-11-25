package helder.scene.render;

import helder.math.Mat4;
import helder.math.Vec3;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.render.Lod.LodLevel;
import helder.test.Test;

// Levels of detail and visible ranges on the CPU (Lod, meshes of data
// alone): a share of the view's height (Lod.coverageOf) for perspective and
// orthographic cameras; each level held within its band of hysteresis, the
// first frame by the plain thresholds; past the last level's threshold,
// nothing; a node picked by its distance and scale; a visible range on an
// ancestor hiding what is under it. Each test's worlds are disposed after it.
function tests() {
	describe("Lod", () -> {
		final worlds:Array<World> = [];
		afterEach(() -> {
			for (w in worlds)
				w.dispose();
			worlds.resize(0);
		});
		test("coverage: a sphere's share of the view's height", () -> {
			// (fovY 90 degrees: the view's half height at a depth d is d)
			var vp = Mat4.perspective(Math.PI / 2, 1, 0.1, 100) * MathTools.lookAt(new Vec3(0, 0, 0), new Vec3(0, 0, -1), new Vec3(0, 1, 0));
			approx(Lod.coverageOf(vp, 0, 0, -10, 1), 0.1, 1e-9);
			approx(Lod.coverageOf(vp, 3, 0, -20, 2), 0.1, 1e-9);
			// (orthographic, 10 m high: a 1 m sphere covers a tenth, however far)
			var ortho = Mat4.orthographic(-5, 5, -5, 5, 0.1, 100);
			approx(Lod.coverageOf(ortho, 0, 0, -50, 0.5), 0.1, 1e-9);
		});
		test("levels held within their band of hysteresis", () -> {
			var lod = new Lod([level(0.2), level(0.05), level(0)], 0.1);
			// (the first frame: the plain thresholds)
			equals(lod.choose(0.21), 0);
			// (inside the band below 0.2: held; past it: the next)
			equals(lod.choose(0.195), 0);
			equals(lod.choose(0.189), 1);
			// (back up: only past the band above)
			equals(lod.choose(0.205), 1);
			equals(lod.choose(0.211), 0);
			// (far, straight to the coarsest; near again, straight to the finest)
			equals(lod.choose(0.01), 2);
			equals(lod.choose(0.5), 0);
			var fresh = new Lod([level(0.2), level(0.05), level(0)]);
			equals(fresh.choose(0.1), 1);
		});
		test("past the last level's threshold, none", () -> {
			var lod = new Lod([level(0.2), level(0.02)], 0);
			equals(lod.choose(0.3), 0);
			equals(lod.choose(0.03), 1);
			equals(lod.choose(0.01), 2);
		});
		test("a node's level by its distance and its scale; a visible range on its parent", () -> {
			var w = new World();
			worlds.push(w);
			var hi = mesh(), mid = mesh(), lo = mesh();
			var parent = w.node("parent");
			var n = w.node("tree");
			parent.add(n);
			var lod = Lod.attach(n, [{mesh: hi, until: 0.15}, {mesh: mid, until: 0.04}, {mesh: lo}]);
			equals(MeshRenderer.of(n), hi);
			var vp = Mat4.perspective(Math.PI / 2, 1, 0.1, 500) * MathTools.lookAt(new Vec3(0, 0, 0), new Vec3(0, 0, -1), new Vec3(0, 1, 0));
			var eye = new Vec3(0, 0, 0);
			// (a unit box's sphere: half its diagonal, 0.866)
			n.position = new Vec3(0, 0, -2);
			equals(Lod.meshOf(n, hi, vp, eye), hi);
			n.position = new Vec3(0, 0, -10);
			equals(Lod.meshOf(n, hi, vp, eye), mid);
			n.position = new Vec3(0, 0, -100);
			equals(Lod.meshOf(n, hi, vp, eye), lo);
			// (scaled up ten times: as near as ten times nearer)
			n.scale = new Vec3(10, 10, 10);
			equals(Lod.meshOf(n, hi, vp, eye), mid);
			equals(lod.level, 1);
			// (its parent's range: drawn from 5 to 50 metres off it)
			Lod.range(parent, 5, 50);
			equals(Lod.meshOf(n, hi, vp, eye), null);
			parent.position = new Vec3(0, 0, -20);
			n.position = new Vec3(0, 0, 0);
			n.scale = new Vec3(1, 1, 1);
			equals(Lod.meshOf(n, hi, vp, eye), mid);
			parent.position = new Vec3(0, 0, -2);
			equals(Lod.meshOf(n, hi, vp, eye), null);
		});
	});
}

// (a level of an empty mesh at a threshold)
private function level(until:Float):LodLevel
	return {mesh: new Mesh(), until: until};

// (a unit box's mesh of data alone)
private function mesh():Mesh {
	var m = new Mesh();
	m.addCpu(Geometry.box(), new Material());
	return m;
}
