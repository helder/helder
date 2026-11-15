package helder.scene.render;

import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.scene.math.Curve3;

// Shapes made in code, on the CPU (three's geometries, Bevy's meshable
// primitives): each generator returns a VertexData (positions, normals,
// uvs and triangles in the renderer's layout; tangents with tangents:
// true), free of the GPU, so it is tested on Eval, read by physics for its
// colliders and packed by the asset step. Shapes.of(device, geometry,
// material) uploads one as a Mesh.
//
// The parameters, their names and defaults, their vertex counts and their
// triangles are three.js's, as option structures (each field optional):
//
//   Geometry.box({width, height, depth, widthSegments, heightSegments, depthSegments})
//   Geometry.sphere({radius, widthSegments, heightSegments, phiStart, phiLength, thetaStart, thetaLength})
//   Geometry.cylinder({radiusTop, radiusBottom, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength})
//   Geometry.cone({radius, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength})
//   Geometry.capsule({radius, height, capSegments, radialSegments, heightSegments})
//   Geometry.torus({radius, tube, radialSegments, tubularSegments, arc})
//   Geometry.torusKnot({radius, tube, tubularSegments, radialSegments, p, q})
//   Geometry.ring({innerRadius, outerRadius, thetaSegments, phiSegments, thetaStart, thetaLength})
//   Geometry.circle({radius, segments, thetaStart, thetaLength})
//   Geometry.plane({width, height, widthSegments, heightSegments})
//   Geometry.lathe(points, {segments, phiStart, phiLength})
//   Geometry.tube(curve, {tubularSegments, radius, radialSegments, closed})
//   Geometry.extrude(path, {depth, bevelSize, bevelSegments, tolerance, evenOdd})
//   Geometry.text(font, text, {size, depth, bevelSize, bevelSegments, lineHeight, letterSpacing, align})
//
// extrude and text make solids of helder.canvas' paths and helder.text's
// outlines (Extrude: canvas' boolean ops, then the caps triangulated):
// linked only by a program that calls them.
// Like three's: y up, the plane, circle and ring in xy facing +z, the
// torus about z, a cylinder's seam at +z. Unlike three's, uvs run down the
// image as glTF's (three's v flipped: 1 - v), as every helder material
// reads them. Each also takes flat: true (its vertices unshared, each
// triangle's three with its face's normal: flat shading, a low-poly
// look) and tangents: true (VertexData.computeTangents', for normal maps).
class Geometry {
	public static function box(?o:BoxOptions):VertexData {
		var w = o?.width ?? 1.0, h = o?.height ?? 1.0, d = o?.depth ?? 1.0;
		var ws = Std.int(o?.widthSegments ?? 1), hs = Std.int(o?.heightSegments ?? 1), ds = Std.int(o?.depthSegments ?? 1);
		var b = new Builder();
		// (three's buildPlane: the axes u, v, w as 0, 1, 2)
		function face(u:Int, v:Int, w:Int, udir:Float, vdir:Float, width:Float, height:Float, depth:Float, gx:Int, gy:Int) {
			var start = b.vertices();
			for (iy in 0...gy + 1) {
				var y = iy * height / gy - height / 2;
				for (ix in 0...gx + 1) {
					var x = ix * width / gx - width / 2;
					var p = [0.0, 0.0, 0.0], n = [0.0, 0.0, 0.0];
					p[u] = x * udir;
					p[v] = y * vdir;
					p[w] = depth / 2;
					n[w] = depth > 0 ? 1 : -1;
					b.vertex(p[0], p[1], p[2], n[0], n[1], n[2], ix / gx, iy / gy);
				}
			}
			for (iy in 0...gy)
				for (ix in 0...gx) {
					var a = start + ix + (gx + 1) * iy, bb = start + ix + (gx + 1) * (iy + 1);
					b.quad(a, bb, bb + 1, a + 1);
				}
		}
		// (three's faces, +z and -z first: a see-through box's own triangles
		// blended in the order helder's boxes always had)
		face(0, 1, 2, 1, -1, w, h, d, ws, hs);
		face(0, 1, 2, -1, -1, w, h, -d, ws, hs);
		face(2, 1, 0, -1, -1, d, h, w, ds, hs);
		face(2, 1, 0, 1, -1, d, h, -w, ds, hs);
		face(0, 2, 1, 1, 1, w, d, h, ws, ds);
		face(0, 2, 1, 1, -1, w, d, -h, ws, ds);
		return b.done(o);
	}

	public static function sphere(?o:SphereOptions):VertexData {
		var radius = o?.radius ?? 1.0;
		var ws = Std.int(Math.max(3, o?.widthSegments ?? 32)), hs = Std.int(Math.max(2, o?.heightSegments ?? 16));
		var phiStart = o?.phiStart ?? 0.0, phiLength = o?.phiLength ?? Math.PI * 2;
		var thetaStart = o?.thetaStart ?? 0.0, thetaLength = o?.thetaLength ?? Math.PI;
		var thetaEnd = Math.min(thetaStart + thetaLength, Math.PI);
		var b = new Builder();
		for (iy in 0...hs + 1) {
			var v = iy / hs;
			// (the poles' uvs half a segment in, as three's)
			var uOffset = iy == 0 && thetaStart == 0 ? 0.5 / ws : iy == hs && thetaEnd == Math.PI ? -0.5 / ws : 0.0;
			for (ix in 0...ws + 1) {
				var u = ix / ws;
				var x = -Math.cos(phiStart + u * phiLength) * Math.sin(thetaStart + v * thetaLength);
				var y = Math.cos(thetaStart + v * thetaLength);
				var z = Math.sin(phiStart + u * phiLength) * Math.sin(thetaStart + v * thetaLength);
				b.vertex(x * radius, y * radius, z * radius, x, y, z, u + uOffset, v);
			}
		}
		for (iy in 0...hs)
			for (ix in 0...ws) {
				// (three's quads, cut along their other diagonal: helder's spheres'
				// as they were, their frames the same)
				var a = iy * (ws + 1) + ix, c = (iy + 1) * (ws + 1) + ix;
				// (no triangles of no area at the poles)
				if (iy != 0 || thetaStart > 0) b.triangle(a, c, a + 1);
				if (iy != hs - 1 || thetaEnd < Math.PI) b.triangle(a + 1, c, c + 1);
			}
		return b.done(o);
	}

	public static function cylinder(?o:CylinderOptions):VertexData {
		var b = new Builder();
		frustum(b, o?.radiusTop ?? 1.0, o?.radiusBottom ?? 1.0, o?.height ?? 1.0, Std.int(o?.radialSegments ?? 32), Std.int(o?.heightSegments ?? 1),
			o?.openEnded ?? false, o?.thetaStart ?? 0.0, o?.thetaLength ?? Math.PI * 2);
		return b.done(o);
	}

	// a cylinder whose top is a point (three's ConeGeometry)
	public static function cone(?o:ConeOptions):VertexData {
		var b = new Builder();
		frustum(b, 0, o?.radius ?? 1.0, o?.height ?? 1.0, Std.int(o?.radialSegments ?? 32), Std.int(o?.heightSegments ?? 1), o?.openEnded ?? false,
			o?.thetaStart ?? 0.0, o?.thetaLength ?? Math.PI * 2);
		return b.done(o);
	}

	// (three's CylinderGeometry: its side, then its caps)
	static function frustum(b:Builder, top:Float, bottom:Float, height:Float, rs:Int, hs:Int, open:Bool, thetaStart:Float, thetaLength:Float) {
		var half = height / 2, slope = (bottom - top) / height;
		for (y in 0...hs + 1) {
			var v = y / hs, r = v * (bottom - top) + top;
			for (x in 0...rs + 1) {
				var u = x / rs, th = u * thetaLength + thetaStart, s = Math.sin(th), c = Math.cos(th);
				var l = Math.sqrt(s * s + slope * slope + c * c);
				b.vertex(r * s, -v * height + half, r * c, s / l, slope / l, c / l, u, v);
			}
		}
		for (x in 0...rs)
			for (y in 0...hs) {
				var a = y * (rs + 1) + x, bb = (y + 1) * (rs + 1) + x, c = bb + 1, d = a + 1;
				if (top > 0 || y != 0) b.triangle(a, bb, d);
				if (bottom > 0 || y != hs - 1) b.triangle(bb, c, d);
			}
		if (open) return;
		for (top_ in [true, false]) {
			var r = top_ ? top : bottom, sign = top_ ? 1.0 : -1.0;
			if (r <= 0) continue;
			var center = b.vertices();
			for (x in 0...rs)
				b.vertex(0, half * sign, 0, 0, sign, 0, 0.5, 0.5);
			var ring = b.vertices();
			for (x in 0...rs + 1) {
				var u = x / rs, th = u * thetaLength + thetaStart, s = Math.sin(th), c = Math.cos(th);
				b.vertex(r * s, half * sign, r * c, 0, sign, 0, c * 0.5 + 0.5, 1 - (s * 0.5 * sign + 0.5));
			}
			for (x in 0...rs) {
				var c = center + x, i = ring + x;
				if (top_) b.triangle(i, i + 1, c) else b.triangle(i + 1, i, c);
			}
		}
	}

	// a cylinder of height with half spheres of radius at its ends, along y
	// (physics' Capsule(radius, height / 2)): rows from the top pole down,
	// capSegments in each half sphere, heightSegments along the side
	public static function capsule(?o:CapsuleOptions):VertexData {
		var radius = o?.radius ?? 1.0, height = o?.height ?? 1.0;
		var cs = Std.int(Math.max(1, o?.capSegments ?? 4)), rs = Std.int(Math.max(3, o?.radialSegments ?? 8)), hs = Std.int(Math.max(1, o?.heightSegments ?? 1));
		var b = new Builder();
		var arc = Math.PI / 2 * radius, total = 2 * arc + height;
		// (each row: its angle from the top, its centre's height, its share of the length)
		var rows:Array<{th:Float, y:Float, s:Float}> = [];
		for (r in 0...cs + 1)
			rows.push({th: Math.PI / 2 * r / cs, y: height / 2, s: arc * r / cs});
		for (r in 1...hs)
			rows.push({th: Math.PI / 2, y: height / 2 - height * r / hs, s: arc + height * r / hs});
		for (r in 0...cs + 1)
			rows.push({th: Math.PI / 2 + Math.PI / 2 * r / cs, y: -height / 2, s: arc + height + arc * r / cs});
		for (row in rows) {
			var ny = Math.cos(row.th), ring = Math.sin(row.th);
			for (x in 0...rs + 1) {
				var u = x / rs, ph = u * Math.PI * 2, s = Math.sin(ph), c = Math.cos(ph);
				b.vertex(ring * s * radius, ny * radius + row.y, ring * c * radius, ring * s, ny, ring * c, u, row.s / total);
			}
		}
		var n = rows.length;
		for (r in 0...n - 1)
			for (x in 0...rs) {
				var a = r * (rs + 1) + x, bb = a + rs + 1;
				if (r > 0) b.triangle(a, bb, a + 1);
				if (r < n - 2) b.triangle(a + 1, bb, bb + 1);
			}
		return b.done(o);
	}

	public static function torus(?o:TorusOptions):VertexData {
		var radius = o?.radius ?? 1.0, tube = o?.tube ?? 0.4, arc = o?.arc ?? Math.PI * 2;
		var rs = Std.int(o?.radialSegments ?? 12), ts = Std.int(o?.tubularSegments ?? 48);
		var b = new Builder();
		for (j in 0...rs + 1)
			for (i in 0...ts + 1) {
				var u = i / ts * arc, v = j / rs * Math.PI * 2;
				var x = (radius + tube * Math.cos(v)) * Math.cos(u), y = (radius + tube * Math.cos(v)) * Math.sin(u), z = tube * Math.sin(v);
				var nx = x - radius * Math.cos(u), ny = y - radius * Math.sin(u), l = Math.sqrt(nx * nx + ny * ny + z * z);
				b.vertex(x, y, z, nx / l, ny / l, z / l, i / ts, 1 - j / rs);
			}
		for (j in 1...rs + 1)
			for (i in 1...ts + 1) {
				var a = (ts + 1) * j + i - 1, bb = (ts + 1) * (j - 1) + i - 1, c = (ts + 1) * (j - 1) + i, d = (ts + 1) * j + i;
				b.quad(a, bb, c, d);
			}
		return b.done(o);
	}

	// a tube wound p times about the torus' axis and q times through its
	// hole (three's TorusKnotGeometry)
	public static function torusKnot(?o:TorusKnotOptions):VertexData {
		var radius = o?.radius ?? 1.0, tube = o?.tube ?? 0.4;
		var ts = Std.int(o?.tubularSegments ?? 64), rs = Std.int(o?.radialSegments ?? 8), p = o?.p ?? 2.0, q = o?.q ?? 3.0;
		function on(u:Float):Vec3 {
			var cs = Math.cos(q / p * u);
			return new Vec3(radius * (2 + cs) * 0.5 * Math.cos(u), radius * (2 + cs) * Math.sin(u) * 0.5, radius * Math.sin(q / p * u) * 0.5);
		}
		var b = new Builder();
		for (i in 0...ts + 1) {
			var u = i / ts * p * Math.PI * 2;
			var p1 = on(u), p2 = on(u + 0.01);
			var t = p2 - p1, n = p2 + p1;
			var bn = unit(cross(t, n));
			n = unit(cross(bn, t));
			for (j in 0...rs + 1) {
				var v = j / rs * Math.PI * 2, cx = -tube * Math.cos(v), cy = tube * Math.sin(v);
				var at = p1 + n * cx + bn * cy, d = unit(at - p1);
				b.vertex(at.x, at.y, at.z, d.x, d.y, d.z, i / ts, 1 - j / rs);
			}
		}
		for (j in 1...ts + 1)
			for (i in 1...rs + 1) {
				var a = (rs + 1) * (j - 1) + (i - 1), bb = (rs + 1) * j + (i - 1), c = (rs + 1) * j + i, d = (rs + 1) * (j - 1) + i;
				b.quad(a, bb, c, d);
			}
		return b.done(o);
	}

	public static function ring(?o:RingOptions):VertexData {
		var inner = o?.innerRadius ?? 0.5, outer = o?.outerRadius ?? 1.0;
		var ts = Std.int(Math.max(3, o?.thetaSegments ?? 32)), ps = Std.int(Math.max(1, o?.phiSegments ?? 1));
		var thetaStart = o?.thetaStart ?? 0.0, thetaLength = o?.thetaLength ?? Math.PI * 2;
		var b = new Builder();
		for (j in 0...ps + 1) {
			var r = inner + (outer - inner) * j / ps;
			for (i in 0...ts + 1) {
				var a = thetaStart + i / ts * thetaLength, x = r * Math.cos(a), y = r * Math.sin(a);
				b.vertex(x, y, 0, 0, 0, 1, (x / outer + 1) / 2, 1 - (y / outer + 1) / 2);
			}
		}
		for (j in 0...ps)
			for (i in 0...ts) {
				var a = i + j * (ts + 1);
				b.quad(a, a + ts + 1, a + ts + 2, a + 1);
			}
		return b.done(o);
	}

	public static function circle(?o:CircleOptions):VertexData {
		var radius = o?.radius ?? 1.0, segments = Std.int(Math.max(3, o?.segments ?? 32));
		var thetaStart = o?.thetaStart ?? 0.0, thetaLength = o?.thetaLength ?? Math.PI * 2;
		var b = new Builder();
		b.vertex(0, 0, 0, 0, 0, 1, 0.5, 0.5);
		for (s in 0...segments + 1) {
			var a = thetaStart + s / segments * thetaLength, x = radius * Math.cos(a), y = radius * Math.sin(a);
			b.vertex(x, y, 0, 0, 0, 1, (x / radius + 1) / 2, 1 - (y / radius + 1) / 2);
		}
		for (i in 1...segments + 1)
			b.triangle(i, i + 1, 0);
		return b.done(o);
	}

	public static function plane(?o:PlaneOptions):VertexData {
		var w = o?.width ?? 1.0, h = o?.height ?? 1.0;
		var gx = Std.int(Math.max(1, o?.widthSegments ?? 1)), gy = Std.int(Math.max(1, o?.heightSegments ?? 1));
		var b = new Builder();
		for (iy in 0...gy + 1) {
			var y = iy * h / gy - h / 2;
			for (ix in 0...gx + 1)
				b.vertex(ix * w / gx - w / 2, -y, 0, 0, 0, 1, ix / gx, iy / gy);
		}
		for (iy in 0...gy)
			for (ix in 0...gx) {
				var a = ix + (gx + 1) * iy, bb = ix + (gx + 1) * (iy + 1);
				b.quad(a, bb, bb + 1, a + 1);
			}
		return b.done(o);
	}

	// points (x the distance from the y axis, y the height) turned about y
	// (three's LatheGeometry: its normals from the profile's, averaged
	// between its segments)
	public static function lathe(points:Array<Vec2>, ?o:LatheOptions):VertexData {
		if (points.length < 2) throw "helder.scene: Geometry.lathe: two points at least";
		var segments = Std.int(Math.max(1, o?.segments ?? 12)), phiStart = o?.phiStart ?? 0.0;
		var phiLength = Math.min(Math.max(o?.phiLength ?? Math.PI * 2, 0), Math.PI * 2);
		var n = points.length;
		// (the profile's normals: each segment's (dy, -dx), averaged at the points between)
		var normals:Array<Vec2> = [];
		var prev = new Vec2(0, 0);
		for (j in 0...n) {
			if (j == 0) {
				var dx = points[1].x - points[0].x, dy = points[1].y - points[0].y;
				prev = unit2(new Vec2(dy, -dx));
				normals.push(prev);
			} else if (j == n - 1) normals.push(prev);
			else {
				var dx = points[j + 1].x - points[j].x, dy = points[j + 1].y - points[j].y;
				var cur = unit2(new Vec2(dy, -dx));
				normals.push(unit2(cur + prev));
				prev = cur;
			}
		}
		var b = new Builder();
		for (i in 0...segments + 1) {
			var phi = phiStart + i / segments * phiLength, s = Math.sin(phi), c = Math.cos(phi);
			for (j in 0...n)
				b.vertex(points[j].x * s, points[j].y, points[j].x * c, normals[j].x * s, normals[j].y, normals[j].x * c, i / segments, 1 - j / (n - 1));
		}
		for (i in 0...segments)
			for (j in 0...n - 1) {
				var a = j + i * n, bb = a + n, c = a + n + 1, d = a + 1;
				b.triangle(a, bb, d);
				b.triangle(c, d, bb);
			}
		return b.done(o);
	}

	// a tube of radius along a curve, its rings on the curve's frames
	// (Curve3.frames: no twist where the curve bends back), at equal lengths
	// along it (three's TubeGeometry)
	// a 2D path (helder.canvas.Path: lines, curves, holes, unions) made
	// solid, from z 0 to depth (Extrude.shape)
	public static function extrude(shape:helder.canvas.Path, ?o:Extrude.ExtrudeOptions):VertexData
		return Extrude.shape(shape, o);

	// a text's outlines in font made solid (or flat: depth 0), size the em's
	// height, its first baseline at y 0 (Extrude.text)
	public static function text(font:helder.text.FontFile, text:String, ?o:Extrude.TextGeometryOptions):VertexData
		return Extrude.text(font, text, o);

	public static function tube(curve:Curve3, ?o:TubeOptions):VertexData {
		var ts = Std.int(Math.max(1, o?.tubularSegments ?? 64)), radius = o?.radius ?? 1.0, rs = Std.int(Math.max(3, o?.radialSegments ?? 8));
		var closed = o?.closed ?? false;
		var f = curve.frames(ts, closed);
		var b = new Builder();
		for (i in 0...ts + 1) {
			// (closed: the last ring the first's, its vertices again for the uvs' seam)
			var k = closed && i == ts ? 0 : i;
			var p = curve.pointAt(curve.length * k / ts), nr = f.normals[k], bn = f.binormals[k];
			for (j in 0...rs + 1) {
				var v = j / rs * Math.PI * 2, s = Math.sin(v), c = -Math.cos(v);
				var d = unit(nr * c + bn * s), at = p + d * radius;
				b.vertex(at.x, at.y, at.z, d.x, d.y, d.z, i / ts, 1 - j / rs);
			}
		}
		for (j in 1...ts + 1)
			for (i in 1...rs + 1) {
				var a = (rs + 1) * (j - 1) + (i - 1), bb = (rs + 1) * j + (i - 1), c = (rs + 1) * j + i, d = (rs + 1) * (j - 1) + i;
				b.quad(a, bb, c, d);
			}
		return b.done(o);
	}

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	static inline function unit(a:Vec3):Vec3 {
		var l = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
		return l > 0 ? a / l : a;
	}

	static inline function unit2(a:Vec2):Vec2 {
		var l = Math.sqrt(a.x * a.x + a.y * a.y);
		return l > 0 ? a / l : a;
	}
}

// (a generator's arrays, then its VertexData: flat and tangents applied; Extrude's too)
@:allow(helder.scene.render) class Builder {
	final p:Array<Float> = [];
	final n:Array<Float> = [];
	final uv:Array<Float> = [];
	final idx:Array<Int> = [];

	public function new() {}

	public inline function vertices():Int
		return Std.int(p.length / 3);

	public function vertex(x:Float, y:Float, z:Float, nx:Float, ny:Float, nz:Float, u:Float, v:Float) {
		p.push(x);
		p.push(y);
		p.push(z);
		n.push(nx);
		n.push(ny);
		n.push(nz);
		uv.push(u);
		uv.push(v);
	}

	public function triangle(a:Int, b:Int, c:Int) {
		idx.push(a);
		idx.push(b);
		idx.push(c);
	}

	// (three's a, b, d and b, c, d)
	public inline function quad(a:Int, b:Int, c:Int, d:Int) {
		triangle(a, b, d);
		triangle(b, c, d);
	}

	public function done(o:Null<GeometryOptions>):VertexData {
		var positions = p, normals = n, uvs = uv, indices = idx;
		if (o?.flat == true) {
			// (each triangle its own three vertices, its face's normal)
			positions = [];
			normals = [];
			uvs = [];
			var t = 0;
			while (t + 2 < idx.length) {
				var a = idx[t], b = idx[t + 1], c = idx[t + 2];
				var ux = p[3 * b] - p[3 * a], uy = p[3 * b + 1] - p[3 * a + 1], uz = p[3 * b + 2] - p[3 * a + 2];
				var vx = p[3 * c] - p[3 * a], vy = p[3 * c + 1] - p[3 * a + 1], vz = p[3 * c + 2] - p[3 * a + 2];
				var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
				var l = Math.sqrt(nx * nx + ny * ny + nz * nz);
				if (l > 0) {
					nx /= l;
					ny /= l;
					nz /= l;
				}
				for (k in [a, b, c]) {
					positions.push(p[3 * k]);
					positions.push(p[3 * k + 1]);
					positions.push(p[3 * k + 2]);
					normals.push(nx);
					normals.push(ny);
					normals.push(nz);
					uvs.push(uv[2 * k]);
					uvs.push(uv[2 * k + 1]);
				}
				t += 3;
			}
			indices = [for (i in 0...idx.length) i];
		}
		var tangents = o?.tangents == true ? VertexData.computeTangents(positions, normals, uvs, indices) : null;
		return VertexData.make(positions, normals, uvs, indices, null, null, tangents);
	}
}

// what every generator takes: flat (its vertices unshared, each triangle
// its face's normal) and tangents (made for normal maps)
typedef GeometryOptions = {
	?flat:Bool,
	?tangents:Bool
}

typedef BoxOptions = {
	> GeometryOptions,
	?width:Float,
	?height:Float,
	?depth:Float,
	?widthSegments:Int,
	?heightSegments:Int,
	?depthSegments:Int
}

typedef SphereOptions = {
	> GeometryOptions,
	?radius:Float,
	?widthSegments:Int,
	?heightSegments:Int,
	?phiStart:Float,
	?phiLength:Float,
	?thetaStart:Float,
	?thetaLength:Float
}

typedef CylinderOptions = {
	> GeometryOptions,
	?radiusTop:Float,
	?radiusBottom:Float,
	?height:Float,
	?radialSegments:Int,
	?heightSegments:Int,
	?openEnded:Bool,
	?thetaStart:Float,
	?thetaLength:Float
}

typedef ConeOptions = {
	> GeometryOptions,
	?radius:Float,
	?height:Float,
	?radialSegments:Int,
	?heightSegments:Int,
	?openEnded:Bool,
	?thetaStart:Float,
	?thetaLength:Float
}

typedef CapsuleOptions = {
	> GeometryOptions,
	?radius:Float,
	?height:Float,
	?capSegments:Int,
	?radialSegments:Int,
	?heightSegments:Int
}

typedef TorusOptions = {
	> GeometryOptions,
	?radius:Float,
	?tube:Float,
	?radialSegments:Int,
	?tubularSegments:Int,
	?arc:Float
}

typedef TorusKnotOptions = {
	> GeometryOptions,
	?radius:Float,
	?tube:Float,
	?tubularSegments:Int,
	?radialSegments:Int,
	?p:Float,
	?q:Float
}

typedef RingOptions = {
	> GeometryOptions,
	?innerRadius:Float,
	?outerRadius:Float,
	?thetaSegments:Int,
	?phiSegments:Int,
	?thetaStart:Float,
	?thetaLength:Float
}

typedef CircleOptions = {
	> GeometryOptions,
	?radius:Float,
	?segments:Int,
	?thetaStart:Float,
	?thetaLength:Float
}

typedef PlaneOptions = {
	> GeometryOptions,
	?width:Float,
	?height:Float,
	?widthSegments:Int,
	?heightSegments:Int
}

typedef LatheOptions = {
	> GeometryOptions,
	?segments:Int,
	?phiStart:Float,
	?phiLength:Float
}

typedef TubeOptions = {
	> GeometryOptions,
	?tubularSegments:Int,
	?radius:Float,
	?radialSegments:Int,
	?closed:Bool
}
