package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.test.Test;

// Bvh against brute force: random rays at a generated mesh's triangles (a
// torus knot, 2,560 of them), at a soup of random ones (long, thin and
// crossing) and at a flat grid where many triangles' centres share a plane,
// each ray's nearest hit the same triangle at the same distance as testing
// every triangle; every hit by castAll; its tree packed (bytes) and read
// back casting alike; a cast allocating nothing (natively and as
// wasm32-wasi). The world's casts: Raycaster.test.hx.
function tests() {
	describe("Bvh", () -> {
		test("a torus knot: the nearest hits as brute force's", () -> sameAsBrute(Geometry.torusKnot({tubularSegments: 160, radialSegments: 8}), 400, 3));
		test("a soup of random triangles: the nearest hits as brute force's", () -> sameAsBrute(soup(600), 400, 6));
		test("a flat grid (centres on one plane): as brute force's", () -> sameAsBrute(Geometry.plane({width: 4, height: 4, widthSegments: 40, heightSegments: 40}), 300, 3));
		test("its leaves hold at most 8 triangles, the tree every triangle once", () -> {
			var bvh = Bvh.build(Geometry.torusKnot({tubularSegments: 160, radialSegments: 8}));
			var seen = [for (_ in 0...bvh.triangleCount) 0];
			for (i in 0...bvh.nodeCount) {
				var n = bvh.nodes.getInt32(i * 32 + 28), a = bvh.nodes.getInt32(i * 32 + 24);
				if (n == 0) continue;
				assert(n <= 8, 'a leaf of $n');
				for (k in a...a + n)
					seen[bvh.triangles.getInt32(k * 40 + 36)]++;
			}
			for (s in seen)
				equals(s, 1);
		});
		test("castAll: every triangle crossed, as brute force's", () -> {
			var g = Geometry.torusKnot({tubularSegments: 80, radialSegments: 8});
			var bvh = Bvh.build(g);
			var sink = new CountSink();
			var rng = new Rng(7);
			for (_ in 0...100) {
				var o = rng.onSphere(4), d = (rng.inBall(0.6) - o);
				sink.count = 0;
				var n = bvh.intersectAll(o, d, Math.POSITIVE_INFINITY, true, sink);
				equals(n, sink.count);
				equals(n, bruteAll(g, o, d));
			}
		});
		test("packed: read from its bytes, the same tree and the same hits", () -> {
			var g = Geometry.torusKnot();
			var built = Bvh.build(g);
			var read = Bvh.read(built.bytes());
			equals(read.nodeCount, built.nodeCount);
			equals(read.triangleCount, built.triangleCount);
			equals(read.depth, built.depth);
			assert(read.nodes.compare(built.nodes) == 0, "the nodes' bytes");
			assert(read.triangles.compare(built.triangles) == 0, "the triangles' bytes");
			var rng = new Rng(3);
			for (_ in 0...100) {
				var o = rng.onSphere(4), d = rng.inBall(0.5) - o;
				var a = built.intersect(o, d, 100, false), b = read.intersect(o, d, 100, false);
				equals(a, b);
				if (a) {
					equals(read.triangle, built.triangle);
					approx(read.t, built.t, 1e-9);
				}
			}
		});
		test("backfaces: a back hit only when asked, its side said", () -> {
			// (a plane facing +z, the ray from behind it)
			var bvh = Bvh.build(Geometry.plane());
			assert(!bvh.intersect(new Vec3(0.1, 0.1, -1), new Vec3(0, 0, 1), 10, false), "its back culled");
			assert(bvh.intersect(new Vec3(0.1, 0.1, -1), new Vec3(0, 0, 1), 10, true), "its back hit");
			assert(!bvh.front, "the back");
			approx(bvh.t, 1);
			assert(bvh.intersect(new Vec3(0.1, 0.1, 1), new Vec3(0, 0, -2), 10, false), "its front");
			assert(bvh.front, "the front");
			approx(bvh.t, 0.5, 1e-9, "in the direction's lengths");
			assert(!bvh.intersect(new Vec3(0.1, 0.1, 1), new Vec3(0, 0, -1), 0.5, false), "beyond maxT");
		});
		test("refit: its boxes moved with its vertices", () -> {
			var g = Geometry.box();
			var bvh = Bvh.build(g);
			var moved = g.transformed(helder.gfx.shader.Mat4.translation(5, 0, 0));
			assert(!bvh.intersect(new Vec3(5, 0, 3), new Vec3(0, 0, -1), 10, false), "not there yet");
			bvh.refit(moved.vertices, 32, moved);
			assert(bvh.intersect(new Vec3(5, 0, 3), new Vec3(0, 0, -1), 10, false), "moved");
			approx(bvh.t, 2.5, 1e-6);
		});
		test("a cast allocates nothing", () -> {
			var bvh = Bvh.build(Geometry.torusKnot());
			var sink = new CountSink();
			function casts(seed:Int) {
				for (k in 0...200) {
					var a = (seed * 200 + k) * 0.37;
					var o = new Vec3(Math.cos(a) * 4, Math.sin(a * 1.3), Math.sin(a) * 4);
					bvh.intersect(o, o * -1, 100, false);
					bvh.intersectAll(o, o * -1, 100, true, sink);
				}
			}
			casts(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (s in 1...10)
				casts(s);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}

// (rays from a sphere about the mesh towards random points near its middle:
// the tree's nearest hit against every triangle's)
private function sameAsBrute(g:VertexData, rays:Int, seed:Int) {
	var bvh = Bvh.build(g);
	var rng = new Rng(seed);
	var hits = 0;
	for (_ in 0...rays) {
		var o = rng.onSphere(5), d = rng.inBall(0.8) - o;
		var backfaces = rng.next() < 0.5;
		var b = brute(g, o, d, backfaces);
		var hit = bvh.intersect(o, d, Math.POSITIVE_INFINITY, backfaces);
		equals(hit, b.triangle >= 0);
		if (hit) {
			hits++;
			approx(bvh.t, b.t, 1e-6);
			// (the same triangle, or one at the same distance: a shared edge)
			if (bvh.triangle != b.triangle) approx(bvh.t, b.t, 1e-9);
		}
	}
	assert(hits > rays / 5, 'only $hits of $rays rays hit');
}

private function brute(g:VertexData, o:Vec3, d:Vec3, backfaces:Bool):{t:Float, triangle:Int} {
	var best = Math.POSITIVE_INFINITY, tri = -1;
	for (k in 0...Std.int(g.count / 3)) {
		var t = triangleHit(g, k, o, d, backfaces);
		if (t >= 0 && t < best) {
			best = t;
			tri = k;
		}
	}
	return {t: best, triangle: tri};
}

private function bruteAll(g:VertexData, o:Vec3, d:Vec3):Int {
	var n = 0;
	for (k in 0...Std.int(g.count / 3))
		if (triangleHit(g, k, o, d, true) >= 0) n++;
	return n;
}

// (in float32, as the tree keeps its corners)
private function triangleHit(g:VertexData, k:Int, o:Vec3, d:Vec3, backfaces:Bool):Float {
	var a = f32(g.position(g.index(3 * k))), b = f32(g.position(g.index(3 * k + 1))), c = f32(g.position(g.index(3 * k + 2)));
	var e1 = b - a, e2 = c - a;
	var p = cross(d, e2);
	var det = dot(e1, p);
	if (det > -1e-12 && det < 1e-12) return -1;
	if (det < 0 && !backfaces) return -1;
	var s = o - a, u = dot(s, p) / det;
	if (u < 0 || u > 1) return -1;
	var q = cross(s, e1), v = dot(d, q) / det;
	if (v < 0 || u + v > 1) return -1;
	var t = dot(e2, q) / det;
	return t < 0 ? -1 : t;
}

private function f32(v:Vec3):Vec3 {
	var b = haxe.io.Bytes.alloc(12);
	b.setFloat(0, v.x);
	b.setFloat(4, v.y);
	b.setFloat(8, v.z);
	return new Vec3(b.getFloat(0), b.getFloat(4), b.getFloat(8));
}

private inline function cross(a:Vec3, b:Vec3):Vec3
	return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

private inline function dot(a:Vec3, b:Vec3):Float
	return a.x * b.x + a.y * b.y + a.z * b.z;

// (random triangles in a box: some long and thin, crossing each other)
private function soup(n:Int):VertexData {
	var rng = new Rng(11), p = [], idx = [];
	for (k in 0...n) {
		var c = rng.inBall(2), s = rng.next() < 0.2 ? 1.5 : 0.25;
		for (_ in 0...3) {
			var q = c + rng.inBall(s);
			p.push(q.x);
			p.push(q.y);
			p.push(q.z);
		}
		idx.push(3 * k);
		idx.push(3 * k + 1);
		idx.push(3 * k + 2);
	}
	return VertexData.make(p, null, null, idx);
}

private class CountSink implements Bvh.BvhSink {
	public var count = 0;

	public function new() {}

	public function hit(t:Float, triangle:Int, u:Float, v:Float, front:Bool)
		count++;
}

// (a small LCG: the same rays everywhere)
private class Rng {
	var s:Int;

	public function new(seed:Int)
		s = seed * 7919 + 1;

	public function next():Float {
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
		return s / 0x7FFFFFFF;
	}

	public function inBall(r:Float):Vec3
		return new Vec3((next() * 2 - 1) * r, (next() * 2 - 1) * r, (next() * 2 - 1) * r);

	public function onSphere(r:Float):Vec3 {
		var z = next() * 2 - 1, a = next() * Math.PI * 2, q = Math.sqrt(1 - z * z);
		return new Vec3(Math.cos(a) * q * r, z * r, Math.sin(a) * q * r);
	}
}
