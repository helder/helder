package helder.scene.render;

import helder.canvas.Path;
import helder.canvas.PathOps;
import helder.scene.render.Geometry;

// Shapes of helder.canvas' 2D paths made solid (Geometry.extrude, three's
// ExtrudeGeometry and TextGeometry): the path first made polygonal and
// simple by canvas' boolean ops (PathOps.simplify: its curves flattened
// within tolerance, overlaps merged, holes found by the fill rule), so an
// SVG icon, a union of shapes or a glyph run with its holes (helder.text's
// outlines, Geometry.text) is one shape; then its caps cut into triangles
// (Triangulate) and its sides walled, from z 0 (the back cap, facing -z) to
// depth (the front, facing +z), y up as the path's numbers are. A bevel
// rounds the caps' edges inwards over bevelSegments steps of a quarter
// circle bevelSize wide (the caps that much smaller); the sides are smooth
// along a curve, sharp where the outline turns by more than 30 degrees.
// depth 0: the front cap alone (a flat shape: a double-sided material for
// its back). Uvs: the caps' the outline's bounds, the sides' along the
// outline and the depth, in the shape's units over its largest side.
class Extrude {
	public static function shape(path:Path, ?o:ExtrudeOptions):VertexData {
		var depth = Math.max(0, o?.depth ?? 1.0), segments = Std.int(Math.max(1, o?.bevelSegments ?? 3));
		var bevel = Math.max(0, Math.min(o?.bevelSize ?? 0.0, depth / 2));
		var simple = PathOps.simplify(path, o?.evenOdd ?? false, o?.tolerance ?? 0.01);
		var contours = contoursOf(simple);
		var b = new Builder();
		if (contours.length == 0) return b.done(o);
		// (the bounds: the uvs' frame)
		var minX = Math.POSITIVE_INFINITY, minY = minX, maxX = Math.NEGATIVE_INFINITY, maxY = maxX;
		for (c in contours) {
			var i = 0;
			while (i < c.length) {
				minX = Math.min(minX, c[i]);
				maxX = Math.max(maxX, c[i]);
				minY = Math.min(minY, c[i + 1]);
				maxY = Math.max(maxY, c[i + 1]);
				i += 2;
			}
		}
		var span = Math.max(1e-9, Math.max(maxX - minX, maxY - minY));
		// (outlines and their holes: a hole in the smallest outline holding it)
		var outers = [], holesOf:Array<Array<Int>> = [];
		for (k in 0...contours.length)
			if (area(contours[k]) > 0) {
				outers.push(k);
				holesOf.push([]);
			}
		for (k in 0...contours.length) {
			if (area(contours[k]) > 0) continue;
			var c = contours[k], best = -1, bestArea = Math.POSITIVE_INFINITY;
			for (j in 0...outers.length) {
				var oc = contours[outers[j]], a = area(oc);
				if (a < bestArea && inside(oc, c[0], c[1])) {
					best = j;
					bestArea = a;
				}
			}
			if (best >= 0) holesOf[best].push(k);
		}
		// (each contour's inset by the bevel: along its corners' bisectors, into its material)
		var insets = [for (c in contours) bevel > 0 ? inset(c, bevel) : c];
		for (j in 0...outers.length) {
			var group = [outers[j]].concat(holesOf[j]);
			var flat:Array<Float> = [], holes:Array<Int> = [];
			for (k in group) {
				if (k != outers[j]) holes.push(Std.int(flat.length / 2));
				for (x in insets[k])
					flat.push(x);
			}
			var tris = Triangulate.polygon(flat, holes);
			// (the front cap at depth, facing +z; the back at 0, facing -z, its triangles turned)
			var front = b.vertices();
			var i = 0;
			while (i < flat.length) {
				b.vertex(flat[i], flat[i + 1], depth, 0, 0, 1, (flat[i] - minX) / span, (maxY - flat[i + 1]) / span);
				i += 2;
			}
			var t = 0;
			while (t < tris.length) {
				b.triangle(front + tris[t], front + tris[t + 1], front + tris[t + 2]);
				t += 3;
			}
			if (depth > 0) {
				var back = b.vertices();
				i = 0;
				while (i < flat.length) {
					b.vertex(flat[i], flat[i + 1], 0, 0, 0, -1, (maxX - flat[i]) / span, (maxY - flat[i + 1]) / span);
					i += 2;
				}
				t = 0;
				while (t < tris.length) {
					b.triangle(back + tris[t], back + tris[t + 2], back + tris[t + 1]);
					t += 3;
				}
			}
		}
		if (depth > 0)
			for (k in 0...contours.length)
				wall(b, contours[k], depth, bevel, bevel > 0 ? segments : 0, span);
		return b.done(o);
	}

	// the sides of a contour (counter-clockwise: an outline; clockwise: a
	// hole, its sides facing in) from the back cap's ring to the front's
	static function wall(b:Builder, c:Array<Float>, depth:Float, bevel:Float, segments:Int, span:Float) {
		var n = c.length >> 1;
		// (the rings, back to front: each its inset, its z, and its normal's
		// share outwards and along z)
		var rings:Array<Array<Float>> = [];
		if (segments == 0) {
			rings.push([0, 0, 1, 0]);
			rings.push([0, depth, 1, 0]);
		} else {
			for (j in 0...segments + 1) {
				var a = Math.PI / 2 * j / segments;
				rings.push([bevel * (1 - Math.sin(a)), bevel * (1 - Math.cos(a)), Math.sin(a), -Math.cos(a)]);
			}
			for (j in 0...segments + 1) {
				var a = Math.PI / 2 * (segments - j) / segments;
				rings.push([bevel * (1 - Math.sin(a)), depth - bevel * (1 - Math.cos(a)), Math.sin(a), Math.cos(a)]);
			}
		}
		// (each edge's outward normal: the right of its direction)
		var ex = [], ey = [];
		for (i in 0...n) {
			var j = (i + 1) % n;
			var dx = c[j * 2] - c[i * 2], dy = c[j * 2 + 1] - c[i * 2 + 1], l = Math.sqrt(dx * dx + dy * dy);
			ex.push(l > 0 ? dy / l : 0);
			ey.push(l > 0 ? -dx / l : 0);
		}
		// (a corner's bisector, for the insets: into the material, the edges' left)
		var cos30 = Math.cos(Math.PI / 6);
		var along = 0.0;
		for (i in 0...n) {
			var j = (i + 1) % n, p = (i + n - 1) % n, q = (j + 1) % n;
			// (the edge's two ends' normals: shared with the neighbour where the outline is smooth there)
			var ax = ex[i], ay = ey[i], bx = ex[i], by = ey[i];
			if (ex[p] * ex[i] + ey[p] * ey[i] > cos30) {
				var sx = ex[p] + ex[i], sy = ey[p] + ey[i], l = Math.sqrt(sx * sx + sy * sy);
				ax = sx / l;
				ay = sy / l;
			}
			if (ex[j] * ex[i] + ey[j] * ey[i] > cos30) {
				var sx = ex[j] + ex[i], sy = ey[j] + ey[i], l = Math.sqrt(sx * sx + sy * sy);
				bx = sx / l;
				by = sy / l;
			}
			var dx = c[j * 2] - c[i * 2], dy = c[j * 2 + 1] - c[i * 2 + 1], len = Math.sqrt(dx * dx + dy * dy);
			var ia = miter(c, p, i, j), ib = miter(c, i, j, q);
			var first = b.vertices();
			for (r in rings) {
				var inset = r[0], z = r[1], out = r[2], nz = r[3];
				b.vertex(c[i * 2] + ia[0] * inset, c[i * 2 + 1] + ia[1] * inset, z, ax * out, ay * out, nz, along / span, z / span);
				b.vertex(c[j * 2] + ib[0] * inset, c[j * 2 + 1] + ib[1] * inset, z, bx * out, by * out, nz, (along + len) / span, z / span);
			}
			for (k in 0...rings.length - 1) {
				var a0 = first + k * 2, a1 = a0 + 1, b0 = a0 + 2, b1 = a0 + 3;
				// (outward: i to j along the back ring, then up to the front's)
				b.triangle(a0, a1, b1);
				b.triangle(a0, b1, b0);
			}
			along += len;
		}
	}

	// (a corner's move inwards a unit: its edges' left normals' bisector, as
	// far as keeps both edges a unit away, at most 4)
	static function miter(c:Array<Float>, p:Int, i:Int, j:Int):Array<Float> {
		var ax = c[i * 2] - c[p * 2], ay = c[i * 2 + 1] - c[p * 2 + 1], la = Math.sqrt(ax * ax + ay * ay);
		var bx = c[j * 2] - c[i * 2], by = c[j * 2 + 1] - c[i * 2 + 1], lb = Math.sqrt(bx * bx + by * by);
		var n1x = la > 0 ? -ay / la : 0, n1y = la > 0 ? ax / la : 0, n2x = lb > 0 ? -by / lb : 0, n2y = lb > 0 ? bx / lb : 0;
		var mx = n1x + n2x, my = n1y + n2y, ml = Math.sqrt(mx * mx + my * my);
		if (ml < 1e-9) return [n1x, n1y];
		mx /= ml;
		my /= ml;
		var d = Math.max(mx * n1x + my * n1y, 0.25);
		return [mx / d, my / d];
	}

	static function inset(c:Array<Float>, by:Float):Array<Float> {
		var n = c.length >> 1, out = [];
		for (i in 0...n) {
			var m = miter(c, (i + n - 1) % n, i, (i + 1) % n);
			out.push(c[i * 2] + m[0] * by);
			out.push(c[i * 2 + 1] + m[1] * by);
		}
		return out;
	}

	// (twice the signed area: positive counter-clockwise, y up)
	static function area(c:Array<Float>):Float {
		var s = 0.0, n = c.length >> 1;
		for (i in 0...n) {
			var j = (i + 1) % n;
			s += c[i * 2] * c[j * 2 + 1] - c[j * 2] * c[i * 2 + 1];
		}
		return s;
	}

	static function inside(c:Array<Float>, x:Float, y:Float):Bool {
		var n = c.length >> 1, odd = false, j = n - 1;
		for (i in 0...n) {
			var yi = c[i * 2 + 1], yj = c[j * 2 + 1];
			if ((yi > y) != (yj > y) && x < (c[j * 2] - c[i * 2]) * (y - yi) / (yj - yi) + c[i * 2]) odd = !odd;
			j = i;
		}
		return odd;
	}

	// (a polygonal path's closed contours, x, y pairs, repeated and collinear points dropped)
	static function contoursOf(p:Path):Array<Array<Float>> {
		var out:Array<Array<Float>> = [], cur:Array<Float> = [], pi = 0;
		function flush() {
			// (the closing point, repeats)
			var c:Array<Float> = [];
			var i = 0;
			while (i < cur.length) {
				var x = cur[i], y = cur[i + 1];
				if (c.length == 0 || Math.abs(c[c.length - 2] - x) > 1e-9 || Math.abs(c[c.length - 1] - y) > 1e-9) {
					c.push(x);
					c.push(y);
				}
				i += 2;
			}
			if (c.length >= 4 && Math.abs(c[0] - c[c.length - 2]) <= 1e-9 && Math.abs(c[1] - c[c.length - 1]) <= 1e-9) {
				c.pop();
				c.pop();
			}
			if (c.length >= 6 && Math.abs(area(c)) > 1e-12) out.push(c);
			cur = [];
		}
		for (k in 0...p.verbCount)
			switch p.verbs[k] {
				case Path.MOVE:
					flush();
					cur.push(p.points[pi]);
					cur.push(p.points[pi + 1]);
					pi += 2;
				case Path.LINE:
					cur.push(p.points[pi]);
					cur.push(p.points[pi + 1]);
					pi += 2;
				case Path.QUAD:
					pi += 4;
				case Path.CUBIC:
					pi += 6;
				case _:
					flush();
			}
		flush();
		return out;
	}

	// a text's outlines (helder.text's layout of it in font, its glyphs'
	// curves through helder.canvas: Glyphs) made solid: size the em's
	// height in the scene's units, the first line's baseline at y 0, its
	// lines aligned by align (0 left at x 0, 0.5 centred on it, 1 right)
	public static function text(font:helder.text.FontFile, text:String, ?o:TextGeometryOptions):VertexData {
		var size = o?.size ?? 1.0;
		// (laid out at 100 units an em, scaled: the shaping's own rounding kept small)
		var em = 100.0, s = size / em;
		var layout = new helder.text.TextLayout(text, new helder.text.FontSet(font, em), o?.lineHeight ?? 1.2, Math.POSITIVE_INFINITY, null, 0,
			(o?.letterSpacing ?? 0.0) * em);
		var align = o?.align ?? 0.0;
		var glyphs = new helder.canvas.Glyphs();
		var lines = layout.lines;
		if (lines.length == 0) return new Builder().done(o);
		var first = lines[0];
		// (each line on its own: aligned by its width; y down in the layout, up in the shape)
		var path = new Path();
		for (k in 0...lines.length) {
			var line = lines[k];
			var x = -line.width * align, y = line.top + line.baseline - (first.top + first.baseline);
			glyphs.path.clear();
			addLine(glyphs, layout, k, x, y);
			path.addPath(glyphs.path, new helder.canvas.Matrix(s, 0, 0, -s, 0, 0));
		}
		return shape(path, {
			depth: o?.depth ?? 0.0,
			bevelSize: o?.bevelSize,
			bevelSegments: o?.bevelSegments,
			tolerance: o?.tolerance ?? 0.005 * size,
			flat: o?.flat,
			tangents: o?.tangents
		});
	}

	// (line k's glyphs into glyphs' path, its pen at x and its baseline at y)
	static function addLine(glyphs:helder.canvas.Glyphs, layout:helder.text.TextLayout, k:Int, x:Float, y:Float) {
		var line = layout.lines[k];
		for (i in line.glyphStart...line.glyphEnd) {
			if (layout.glyphHidden(i)) continue;
			var face = layout.glyphFont(i), set = layout.glyphFontSet(i), sc = set.scale(face);
			var gx = x + layout.glyphX(i) + layout.glyphOffsetX(i), gy = y + layout.glyphOffsetY(i);
			face.outline(layout.glyphId(i), glyphs, [sc, 0, set.oblique ? 0.25 * sc : 0, -sc, gx, gy]);
		}
	}
}

// what Geometry.extrude takes (each optional): its depth (1), a bevel's
// size (0: none) and steps (3), the curves' flattening tolerance (0.01, the
// path's units), the fill rule that finds its holes (non-zero; evenOdd),
// and every generator's flat and tangents
typedef ExtrudeOptions = {
	> GeometryOptions,
	?depth:Float,
	?bevelSize:Float,
	?bevelSegments:Int,
	?tolerance:Float,
	?evenOdd:Bool
}

// what Geometry.text takes (each optional): the em's size (1), its depth
// (0: flat), a bevel (as extrude's), the lines' height (1.2 ems), the
// letters' spacing (ems), the lines' alignment (0 left, 0.5 centred, 1
// right), the curves' tolerance (the scene's units: size / 200)
typedef TextGeometryOptions = {
	> GeometryOptions,
	?size:Float,
	?depth:Float,
	?bevelSize:Float,
	?bevelSegments:Int,
	?lineHeight:Float,
	?letterSpacing:Float,
	?align:Float,
	?tolerance:Float
}
