package helder.scene.render;

import helder.canvas.Path;
import helder.gfx.shader.Vec3;
import helder.test.Test;

// Geometry.extrude and Geometry.text on the CPU: a square's solid (its two
// caps and four sides, closed: every edge shared by two triangles), a ring
// (a square with a square hole: the hole's sides facing in), a circle's
// curves flattened, a bevel's rings, the caps' area the shape's, normals
// unit and facing out; Triangulate on a polygon with two holes; a text's
// glyphs (their holes too: "aBo8") flat and solid, aligned.
function tests() {
	describe("Extrude", () -> {
		test("a square: two caps, four sides, closed, facing out", () -> {
			var p = new Path();
			p.rect(0, 0, 2, 1);
			var g = Geometry.extrude(p, {depth: 0.5});
			equals(Std.int(g.count / 3), 2 + 2 + 4 * 2);
			closed(g);
			facingOut(g, new Vec3(1, 0.5, 0.25));
			approx(capArea(g, 0.5), 2, 1e-6);
			approx(g.bounds.max.z, 0.5);
		});
		test("a ring: a square with a hole, its sides facing in", () -> {
			var p = new Path();
			p.rect(0, 0, 4, 4);
			p.rect(1, 1, 2, 2);
			var g = Geometry.extrude(p, {depth: 1, evenOdd: true});
			closed(g);
			approx(capArea(g, 1), 12, 1e-6);
			// (the hole's walls: their normals towards its middle)
			var inward = 0;
			for (k in 0...Std.int(g.count / 3)) {
				var c = centroid(g, k), n = g.normal(g.index(3 * k));
				if (c.x > 0.99 && c.x < 3.01 && c.y > 0.99 && c.y < 3.01 && Math.abs(n.z) < 0.5) {
					var toMiddle = new Vec3(2 - c.x, 2 - c.y, 0);
					assert(n.x * toMiddle.x + n.y * toMiddle.y > 0, "a hole's side faces into it");
					inward++;
				}
			}
			equals(inward, 8);
		});
		test("a circle: its curve flattened, the cap's area near pi", () -> {
			var p = new Path();
			p.arc(0, 0, 1, 0, Math.PI * 2);
			p.close();
			var g = Geometry.extrude(p, {depth: 0.2, tolerance: 0.001});
			closed(g);
			approx(capArea(g, 0.2), Math.PI, 0.01);
			for (i in 0...g.vertexCount) {
				var n = g.normal(i);
				approx(Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z), 1, 1e-5);
			}
		});
		test("a bevel: the caps inset, rounded rings up to them", () -> {
			var p = new Path();
			p.rect(0, 0, 2, 2);
			var g = Geometry.extrude(p, {depth: 1, bevelSize: 0.2, bevelSegments: 3});
			closed(g);
			// (the front cap 1.6 square)
			approx(capArea(g, 1), 1.6 * 1.6, 1e-6);
			approx(g.bounds.min.x, 0);
			approx(g.bounds.max.x, 2);
		});
		test("depth 0: the front alone", () -> {
			var p = new Path();
			p.rect(0, 0, 1, 1);
			var g = Geometry.extrude(p, {depth: 0});
			equals(g.count, 6);
			approx(g.normal(0).z, 1);
		});
		test("Triangulate: two holes, every triangle counter-clockwise, the area kept", () -> {
			var pts = [0.0, 0, 10, 0, 10, 10, 0, 10, 2, 2, 2, 4, 4, 4, 4, 2, 6, 6, 6, 8, 8, 8, 8, 6];
			var t = Triangulate.polygon(pts, [4, 8]);
			var total = 0.0;
			var k = 0;
			while (k < t.length) {
				var a = t[k], b = t[k + 1], c = t[k + 2];
				var area = (pts[b * 2] - pts[a * 2]) * (pts[c * 2 + 1] - pts[a * 2 + 1]) - (pts[c * 2] - pts[a * 2]) * (pts[b * 2 + 1] - pts[a * 2 + 1]);
				assert(area > 0, "counter-clockwise");
				total += area / 2;
				k += 3;
			}
			approx(total, 100 - 8, 1e-9);
		});
		test("text: glyphs with holes, flat and solid, aligned", () -> {
			var font = helder.text.FontFile.parse(sys.io.File.getBytes("tests/canvas/fonts/DejaVuSans-canvas.ttf"));
			var flat = Geometry.text(font, "aBo8", {size: 1});
			assert(flat.count > 100, 'its triangles: ${flat.count / 3}');
			approx(flat.bounds.min.z, 0);
			approx(flat.bounds.max.z, 0);
			// (an em of 1: the capital's height about 0.73, the baseline at 0)
			assert(flat.bounds.max.y > 0.6 && flat.bounds.max.y < 0.85, 'its top ${flat.bounds.max.y}');
			assert(flat.bounds.min.y > -0.05, 'its bottom ${flat.bounds.min.y}');
			var solid = Geometry.text(font, "aBo8", {size: 1, depth: 0.2});
			closed(solid);
			approx(solid.bounds.max.z, 0.2);
			var centred = Geometry.text(font, "aBo8", {size: 1, align: 0.5});
			approx(centred.bounds.min.x + centred.bounds.max.x, 0, 0.12);
			var two = Geometry.text(font, "a\nb", {size: 1});
			assert(two.bounds.min.y < -0.9, "the second line below");
		});
	});
}

// (every edge of the triangles shared by exactly two: by its ends' positions)
private function closed(g:VertexData) {
	var edges = new Map<String, Int>();
	function key(i:Int):String {
		var p = g.position(i);
		return Math.round(p.x * 1e5) + "," + Math.round(p.y * 1e5) + "," + Math.round(p.z * 1e5);
	}
	for (k in 0...Std.int(g.count / 3))
		for (e in 0...3) {
			var a = key(g.index(3 * k + e)), b = key(g.index(3 * k + (e + 1) % 3));
			if (a == b) continue;
			var id = a < b ? a + "|" + b : b + "|" + a;
			edges.set(id, (edges.get(id) ?? 0) + 1);
		}
	var open = 0;
	for (n in edges)
		if (n != 2) open++;
	equals(open, 0, "edges not shared by two triangles");
}

// (each triangle's normal away from inside, a point inside a convex solid)
private function facingOut(g:VertexData, inside:Vec3) {
	for (k in 0...Std.int(g.count / 3)) {
		var a = g.position(g.index(3 * k)), b = g.position(g.index(3 * k + 1)), c = g.position(g.index(3 * k + 2));
		var u = b - a, v = c - a;
		var n = new Vec3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x);
		var out = (a + b + c) / 3 - inside;
		assert(n.x * out.x + n.y * out.y + n.z * out.z > 0, 'triangle $k faces in');
	}
}

private function centroid(g:VertexData, k:Int):Vec3
	return (g.position(g.index(3 * k)) + g.position(g.index(3 * k + 1)) + g.position(g.index(3 * k + 2))) / 3;

// (the area of the triangles facing +z at z)
private function capArea(g:VertexData, z:Float):Float {
	var total = 0.0;
	for (k in 0...Std.int(g.count / 3)) {
		var a = g.position(g.index(3 * k)), b = g.position(g.index(3 * k + 1)), c = g.position(g.index(3 * k + 2));
		if (Math.abs(a.z - z) > 1e-6 || Math.abs(b.z - z) > 1e-6 || Math.abs(c.z - z) > 1e-6) continue;
		var cz = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
		if (cz > 0) total += cz / 2;
	}
	return total;
}
