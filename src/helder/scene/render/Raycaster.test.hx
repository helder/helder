package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.Hit;
import helder.test.Test;

// world.raycast on the CPU (meshes of data alone: Mesh.addCpu, no device):
// a turned, unevenly scaled node's triangles hit where they are (its
// distance the world's, its normal turned to the ray, its uv the vertices'
// blend), the nearest of several, a node's children, an instanced set's
// instances, hidden nodes and other layers skipped, maxDistance, bounds
// alone, backs only when asked, raycastAll's hits nearest first, and a cast
// allocating nothing (natively and as wasm32-wasi). Each test's worlds are
// disposed after it.
function tests() {
	describe("Raycaster", () -> {
		// (each test's worlds let go after it: a program holds 16 at once)
		afterEach(() -> {
			for (w in worlds)
				w.dispose();
			worlds.resize(0);
		});
		test("a plane's triangle: its point, distance, normal and uv", () -> {
			var w = world();
			var n = meshNode(w, Geometry.plane({width: 2, height: 2}));
			// (the plane turned to face +y, 1 up)
			n.position = new Vec3(0, 1, 0);
			n.rotation = Quat.fromEuler(-Math.PI / 2, 0, 0);
			var hit = new Hit();
			assert(w.raycast(new Vec3(0.5, 5, -0.5), new Vec3(0, -2, 0), hit), "hit");
			equals(hit.node, n);
			approx(hit.distance, 4, 1e-6);
			approx(hit.point.x, 0.5, 1e-6);
			approx(hit.point.y, 1, 1e-6);
			approx(hit.normal.y, 1, 1e-6);
			assert(hit.front, "its front");
			// (the plane's u along x, v down from its top as an image's rows: its
			// local y, -z once turned)
			approx(hit.uv.x, 0.75, 1e-6);
			approx(hit.uv.y, 0.25, 1e-6);
			assert(hit.triangle >= 0, "a triangle");
			approx(hit.barycentric.x + hit.barycentric.y + hit.barycentric.z, 1, 1e-9);
			equals(hit.instance, -1);
		});
		test("an unevenly scaled sphere: hit at its surface, not its bounds", () -> {
			var w = world();
			var n = meshNode(w, Geometry.sphere({radius: 1, widthSegments: 64, heightSegments: 32}));
			n.scale = new Vec3(2, 1, 1);
			var hit = new Hit();
			// (along the diagonal of its bounds' corner: the box would be hit at 45 degrees' corner, the ellipsoid inside it)
			var o = new Vec3(5, 5, 0), d = new Vec3(-1, -1, 0);
			assert(w.raycast(o, d, hit), "hit");
			// (x^2/4 + y^2 = 1 along x = y: x = 2/sqrt(5))
			var x = 2 / Math.sqrt(5);
			approx(hit.point.x, x, 1e-2);
			approx(hit.point.y, x, 1e-2);
			approx(hit.distance, (5 - x) * Math.sqrt(2), 1e-2);
			// (the ellipsoid's normal there: (x/4, y) normalized)
			var nx = x / 4, ny = x, l = Math.sqrt(nx * nx + ny * ny);
			approx(hit.normal.x, nx / l, 2e-2);
			approx(hit.normal.y, ny / l, 2e-2);
		});
		test("the nearest of several, children too; hidden ones and other layers skipped", () -> {
			var w = world();
			var far = meshNode(w, Geometry.box());
			far.position = new Vec3(0, 0, -6);
			var near = meshNode(w, Geometry.box());
			near.position = new Vec3(0, 0, -3);
			var parent = w.node("parent");
			var child = meshNode(w, Geometry.box(), parent);
			parent.position = new Vec3(0, 0, -1.5);
			child.scale = new Vec3(0.5, 0.5, 0.5);
			var hit = new Hit(), o = new Vec3(0, 0, 2), d = new Vec3(0, 0, -1);
			assert(w.raycast(o, d, hit), "hit");
			equals(hit.node, child);
			approx(hit.distance, 3.25, 1e-6);
			child.visible = false;
			w.raycast(o, d, hit);
			equals(hit.node, near);
			Raycaster.setLayers(near, 2);
			w.raycast(o, d, hit, new RaycastOptions({layers: 1}));
			equals(hit.node, far);
			w.raycast(o, d, hit, new RaycastOptions({layers: 2}));
			equals(hit.node, near);
			assert(!w.raycast(o, d, new Hit(), new RaycastOptions({maxDistance: 1})), "within 1: none");
		});
		test("bounds alone: the box's point, no triangle", () -> {
			var w = world();
			meshNode(w, Geometry.sphere({radius: 1}));
			var hit = new Hit();
			assert(w.raycast(new Vec3(3, 3, 0), new Vec3(-1, -1, 0), hit, new RaycastOptions({triangles: false})), "hit");
			equals(hit.triangle, -1);
			approx(hit.point.x, 1, 1e-6);
			approx(hit.point.y, 1, 1e-6);
		});
		test("backs: a box from inside only with backfaces", () -> {
			var w = world();
			meshNode(w, Geometry.box({width: 2, height: 2, depth: 2}));
			var hit = new Hit();
			assert(!w.raycast(new Vec3(0, 0, 0), new Vec3(1, 0, 0), hit), "from inside: the backs culled");
			assert(w.raycast(new Vec3(0, 0, 0), new Vec3(1, 0, 0), hit, new RaycastOptions({backfaces: true})), "with backfaces");
			assert(!hit.front, "a back");
			approx(hit.distance, 1, 1e-6);
			// (turned to the ray)
			approx(hit.normal.x, -1, 1e-6);
		});
		test("an instanced set's instances, each where its matrix puts it", () -> {
			var w = world();
			var mesh = new Mesh();
			mesh.addCpu(Geometry.box(), new Material());
			var set = new InstancedMesh(mesh, 3);
			InstancedMesh.attach(w.node("set"), set);
			set.setTransform(0, -3, 0, 0, 0, 0, 0, 1);
			set.setTransform(1, 0, 0, 0, 0, 0, 0, 1, 0.5);
			set.setTransform(2, 3, 0, 0, 0, 0, 0, 1);
			var hit = new Hit();
			assert(w.raycast(new Vec3(3, 0, 5), new Vec3(0, 0, -1), hit), "the third");
			equals(hit.instance, 2);
			approx(hit.distance, 4.5, 1e-6);
			assert(w.raycast(new Vec3(0, 0, 5), new Vec3(0, 0, -1), hit), "the second, half as big");
			equals(hit.instance, 1);
			approx(hit.distance, 4.75, 1e-6);
			assert(!w.raycast(new Vec3(1.5, 0, 5), new Vec3(0, 0, -1), hit), "between them");
			assert(!w.raycast(new Vec3(3, 0, 5), new Vec3(0, 0, -1), hit, new RaycastOptions({instances: false})), "instances off");
		});
		test("raycastAll: every triangle crossed, nearest first", () -> {
			var w = world();
			for (k in 0...3) {
				var n = meshNode(w, Geometry.box());
				n.position = new Vec3(0, 0, -2.0 * k);
			}
			var hits = new HitList();
			equals(w.raycastAll(new Vec3(0.1, 0.2, 3), new Vec3(0, 0, -1), hits, new RaycastOptions({backfaces: true})), 6);
			for (i in 1...hits.count)
				assert(hits.get(i - 1).distance <= hits.get(i).distance, "nearest first");
			approx(hits.get(0).distance, 2.5, 1e-6);
			approx(hits.get(5).distance, 7.5, 1e-6);
			equals(w.raycastAll(new Vec3(0.1, 0.2, 3), new Vec3(0, 0, -1), hits), 3);
		});
		test("a cast allocates nothing (its trees made)", () -> {
			var w = world();
			// (one mesh for them all: its tree made by the first cast at it, an allocation once)
			var knot = new Mesh();
			knot.addCpu(Geometry.torusKnot({tubularSegments: 48, radialSegments: 6}), new Material());
			for (k in 0...20) {
				var n = w.node("knot");
				MeshRenderer.attach(n, knot);
				n.position = new Vec3((k % 5) * 3 - 6, Std.int(k / 5) * 3 - 4.5, -4);
				n.rotation = Quat.fromEuler(k * 0.3, k * 0.7, 0);
			}
			var mesh = new Mesh();
			mesh.addCpu(Geometry.box(), new Material());
			var set = new InstancedMesh(mesh, 50);
			InstancedMesh.attach(w.node("set"), set);
			for (i in 0...50)
				set.setTransform(i, i * 0.4 - 10, 4, -2, 0, 0, 0, 1, 0.3);
			var hit = new Hit(), hits = new HitList(), opts = new RaycastOptions({backfaces: true});
			function casts(seed:Int) {
				for (k in 0...40) {
					var a = (seed * 40 + k) * 0.21;
					var o = new Vec3(Math.cos(a) * 2, Math.sin(a * 1.7) * 2, 6);
					w.raycast(o, new Vec3(Math.sin(a) * 0.3, Math.cos(a) * 0.3, -1), hit);
					w.raycastAll(o, new Vec3(Math.sin(a) * 0.3, Math.cos(a) * 0.3, -1), hits, opts);
				}
			}
			// (once: the tree made, the list grown to the most hits a cast has)
			for (s in 0...8)
				casts(s);
			var before = hxmc.GcStats.bytesAllocated();
			for (s in 0...8)
				casts(s);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}

private final worlds:Array<World> = [];

private function world():World {
	var w = new World();
	worlds.push(w);
	return w;
}

private function meshNode(w:World, g:VertexData, ?parent:helder.scene.Node):helder.scene.Node {
	var m = new Mesh();
	m.addCpu(g, new Material());
	var n = w.node("mesh", parent);
	MeshRenderer.attach(n, m);
	return n;
}
