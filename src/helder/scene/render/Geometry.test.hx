package helder.scene.render;

import helder.math.Vec2;
import helder.math.Vec3;
import helder.scene.math.Curve3;
import helder.test.Test;

// Geometry's generators on the CPU: three.js's vertex and index counts for
// the same parameters; closed shapes closed (their positions welded, each
// edge two triangles', once each way: no hole, wound one way round);
// every triangle wound counter-clockwise from the side its normals face;
// normals of unit length; uvs within 0 to 1; flat: a vertex a corner, each
// triangle's normal its face's; VertexData.transformed. The renderer
// drawing them: the 3d lane's "primitives" frame (tests/3d/Scenes.hx).
function tests() {
	describe("Geometry", () -> {
		final helix = Curve3.catmullRom([for (k in 0...9) new Vec3(Math.cos(k * 1.4), k * 0.3, Math.sin(k * 1.4))]);
		final vase = [new Vec2(0.01, -1), new Vec2(0.6, -0.9), new Vec2(0.8, 0), new Vec2(0.4, 0.7)];
		// (each generator at three's defaults: its counts, three's for the same)
		final all:Array<{name:String, g:VertexData, vertices:Int, indices:Int, closed:Bool}> = [
			{name: "box", g: Geometry.box(), vertices: 24, indices: 36, closed: true},
			{name: "box 2x3x4", g: Geometry.box({widthSegments: 2, heightSegments: 3, depthSegments: 4}), vertices: 2 * (12 + 15 + 20), indices: 6 * 2 * (6 + 8 + 12), closed: true},
			{name: "sphere", g: Geometry.sphere(), vertices: 33 * 17, indices: 32 * 30 * 3, closed: true},
			{name: "cylinder", g: Geometry.cylinder(), vertices: 66 + 2 * 65, indices: 192 + 2 * 96, closed: true},
			{name: "cylinder open", g: Geometry.cylinder({openEnded: true, heightSegments: 3}), vertices: 33 * 4, indices: 32 * 3 * 6, closed: false},
			{name: "cone", g: Geometry.cone(), vertices: 66 + 65, indices: 96 + 96, closed: true},
			{name: "capsule", g: Geometry.capsule(), vertices: 9 * 10, indices: 8 * (2 * 9 - 2) * 3, closed: true},
			{name: "capsule 3 along", g: Geometry.capsule({heightSegments: 3}), vertices: 9 * 12, indices: 8 * (2 * 11 - 2) * 3, closed: true},
			{name: "torus", g: Geometry.torus(), vertices: 13 * 49, indices: 12 * 48 * 6, closed: true},
			{name: "torusKnot", g: Geometry.torusKnot(), vertices: 65 * 9, indices: 64 * 8 * 6, closed: true},
			{name: "ring", g: Geometry.ring(), vertices: 2 * 33, indices: 32 * 6, closed: false},
			{name: "circle", g: Geometry.circle(), vertices: 34, indices: 96, closed: false},
			{name: "plane", g: Geometry.plane(), vertices: 4, indices: 6, closed: false},
			{name: "plane 3x2", g: Geometry.plane({widthSegments: 3, heightSegments: 2}), vertices: 12, indices: 36, closed: false},
			{name: "lathe", g: Geometry.lathe(vase), vertices: 13 * 4, indices: 12 * 3 * 6, closed: false},
			{name: "tube", g: Geometry.tube(helix, {radius: 0.2}), vertices: 65 * 9, indices: 64 * 8 * 6, closed: false}
		];

		test("three.js's vertex and index counts", () -> {
			for (s in all) {
				equals(s.g.vertexCount, s.vertices, s.name + "'s vertices");
				equals(s.g.count, s.indices, s.name + "'s indices");
			}
		});
		test("closed shapes are closed, each edge two triangles', wound one way round", () -> {
			for (s in all)
				if (s.closed) equals(closed(s.g), null, s.name);
			// (the flat ones too: the same surface, its vertices unshared)
			equals(closed(Geometry.torusKnot({flat: true})), null, "torusKnot flat");
			equals(closed(Geometry.cylinder({flat: true, radialSegments: 6})), null, "cylinder flat");
		});
		test("triangles wound counter-clockwise from their normals' side, normals unit, uvs 0 to 1", () -> {
			for (s in all) {
				equals(wound(s.g), null, s.name);
				assert(unitNormals(s.g), s.name + "'s normals of unit length");
				// (the sphere's poles' uvs half a segment over, as three's)
				assert(uvsIn(s.g, s.name == "sphere" ? 0.5 / 32 : 0), s.name + "'s uvs within 0 to 1");
			}
		});
		test("a sphere's normals point out from its centre; its uvs down the image", () -> {
			var g = Geometry.sphere({radius: 2});
			for (i in 0...g.vertexCount) {
				var p = g.position(i), n = g.normal(i);
				approx(p.x / 2, n.x, 1e-5);
				approx(p.y / 2, n.y, 1e-5);
			}
			// (the top pole at v 0: glTF's uvs, three's flipped)
			approx(g.position(0).y, 2, 1e-6);
			approx(g.uv(0).y, 0);
		});
		test("flat: a vertex a corner, each triangle its face's normal", () -> {
			var g = Geometry.sphere({widthSegments: 8, heightSegments: 4, flat: true});
			equals(g.vertexCount, g.count);
			equals(wound(g), null);
			var k = 0;
			while (k < g.count) {
				var a = g.normal(k), b = g.normal(k + 1), c = g.normal(k + 2);
				approx(a.x, b.x, 1e-6);
				approx(a.y, c.y, 1e-6);
				k += 3;
			}
		});
		test("a cylinder's sizes: radii and height, its seam at +z as three's", () -> {
			var g = Geometry.cylinder({radiusTop: 0.5, radiusBottom: 1, height: 3});
			approx(g.bounds.min.y, -1.5, 1e-6);
			approx(g.bounds.max.y, 1.5, 1e-6);
			approx(g.bounds.max.x, 1, 1e-6);
			// (the first vertex: the top ring at angle 0, on +z)
			approx(g.position(0).z, 0.5, 1e-6);
			approx(g.position(0).y, 1.5, 1e-6);
		});
		test("tangents when asked", () -> {
			var g = Geometry.box({tangents: true});
			assert(g.tangents != null);
			assert(Geometry.box().tangents == null);
		});
		test("transformed: positions moved, normals turned, a mirror's winding kept", () -> {
			var g = Geometry.plane().rotated(-Math.PI / 2, 0, 0);
			approx(g.normal(0).y, 1, 1e-6);
			approx(g.bounds.max.z, 0.5, 1e-6);
			equals(wound(g), null);
			var mirrored = Geometry.box().transformed(helder.math.Mat4.scaling(-1, 1, 1));
			equals(wound(mirrored), null);
			equals(closed(mirrored), null);
			var moved = Geometry.box().translated(0, 2, 0);
			approx(moved.bounds.min.y, 1.5, 1e-6);
		});
	});
}

// (module-level, not local functions: hxmc mixes up local closures of
// struct values of different types for now)
// (a weld of positions to 1e-4: its edges' counts, each way)
private function closed(g:VertexData):Null<String> {
	var ids = new Map<String, Int>(), weld = [];
	for (i in 0...g.vertexCount) {
		var p = g.position(i);
		var key = Math.round(p.x * 1e4) + "," + Math.round(p.y * 1e4) + "," + Math.round(p.z * 1e4);
		if (!ids.exists(key)) ids.set(key, Lambda.count(ids));
		weld.push(ids.get(key));
	}
	var edges = new Map<String, Int>();
	var k = 0;
	while (k < g.count) {
		var t = [weld[g.index(k)], weld[g.index(k + 1)], weld[g.index(k + 2)]];
		for (e in 0...3) {
			var a = t[e], b = t[(e + 1) % 3];
			if (a == b) continue;
			var key = a + ">" + b;
			edges.set(key, (edges.get(key) ?? 0) + 1);
		}
		k += 3;
	}
	for (key => n in edges) {
		var ab = key.split(">");
		var back = edges.get(ab[1] + ">" + ab[0]) ?? 0;
		if (n != 1 || back != 1) return 'edge $key: $n one way, $back the other';
	}
	return null;
}
// (each triangle's winding against its vertices' normals: counter-clockwise from their side)
private function wound(g:VertexData):Null<String> {
	var k = 0;
	while (k < g.count) {
		var a = g.position(g.index(k)), b = g.position(g.index(k + 1)), c = g.position(g.index(k + 2));
		var u = b - a, v = c - a;
		var f = new Vec3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x);
		var area = Math.sqrt(f.x * f.x + f.y * f.y + f.z * f.z);
		if (area > 1e-9) {
			var n = g.normal(g.index(k)) + g.normal(g.index(k + 1)) + g.normal(g.index(k + 2));
			if (f.x * n.x + f.y * n.y + f.z * n.z <= 0) return 'triangle ${Std.int(k / 3)} wound against its normals';
		}
		k += 3;
	}
	return null;
}
private function unitNormals(g:VertexData):Bool {
	for (i in 0...g.vertexCount) {
		var n = g.normal(i);
		if (Math.abs(Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z) - 1) > 1e-4) return false;
	}
	return true;
}
private function uvsIn(g:VertexData, slack = 0.0):Bool {
	for (i in 0...g.vertexCount) {
		var t = g.uv(i);
		if (t.x < -slack - 1e-6 || t.x > 1 + slack + 1e-6 || t.y < -1e-6 || t.y > 1 + 1e-6) return false;
	}
	return true;
}
