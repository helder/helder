package helder.scene.render;

import haxe.ds.Vector;
import haxe.io.Bytes;
import helder.math.Vec3;

// A bounding volume hierarchy over one primitive's triangles (three-mesh-bvh's
// MeshBVH), for casting rays against them (Raycaster, world.raycast): a flat
// array of nodes, each a box and either two children (the next pair) or a
// leaf's run of triangles, built by the surface area heuristic over 12 bins
// a split (at most 8 triangles a leaf, more only where their centres
// coincide), the triangles' corners copied in the tree's order beside it.
// Built when first cast against (Primitive.bvh), or in the asset step
// (helder.scene.gltf.Pack --bvh) and read with the packed model, its bytes
// as they are (bytes(), read): a level loads with its trees made.
//
// A cast allocates nothing: the traversal's stack is the tree's own (one
// cast at a time: not shared between threads), the nearest hit's distance,
// triangle and barycentrics left in t, triangle, u and v.
//
//   var bvh = Bvh.build(Geometry.sphere());
//   if (bvh.intersect(origin, dir, 100, false)) trace(bvh.t, bvh.triangle);
class Bvh {
	// (a node: its box's 6 floats, then a (an inner node's first child, the
	// second after it; a leaf's first triangle) and n (0: inner; a leaf's
	// triangles), 32 bytes; a triangle: its corners' 9 floats and its index
	// in the primitive, 40 bytes)
	static inline var NODE = 32;
	static inline var TRI = 40;
	static inline var LEAF = 8;
	static inline var BINS = 12;

	public final nodes:Bytes;
	public final triangles:Bytes;
	public final nodeCount:Int;
	public final triangleCount:Int;
	// the tree's depth (its traversal's stack)
	public final depth:Int;

	// the last cast's nearest hit: its distance along the ray (in the ray
	// direction's lengths), its triangle (the primitive's: indices 3k to
	// 3k + 2), the barycentrics of its second and third corners (the first's
	// 1 - u - v), whether its front was hit (counter-clockwise towards the ray)
	public var t(default, null) = 0.0;
	public var triangle(default, null) = -1;
	public var u(default, null) = 0.0;
	public var v(default, null) = 0.0;
	public var front(default, null) = true;

	final stack:Vector<Int>;
	final stackT:Vector<Float>;

	function new(nodes:Bytes, triangles:Bytes, nodeCount:Int, triangleCount:Int, depth:Int) {
		this.nodes = nodes;
		this.triangles = triangles;
		this.nodeCount = nodeCount;
		this.triangleCount = triangleCount;
		this.depth = depth;
		stack = new Vector(depth + 2);
		stackT = new Vector(depth + 2);
	}

	// the tree of a primitive's data (its positions and triangles)
	public static function build(data:VertexData):Bvh {
		var n = Std.int(data.count / 3), stride = data.skinned ? 64 : 32;
		var corners = new Vector<Float>(n * 9);
		for (k in 0...n)
			for (c in 0...3) {
				var o = data.index(3 * k + c) * stride;
				corners[k * 9 + c * 3] = data.vertices.getFloat(o);
				corners[k * 9 + c * 3 + 1] = data.vertices.getFloat(o + 4);
				corners[k * 9 + c * 3 + 2] = data.vertices.getFloat(o + 8);
			}
		return make(corners, n);
	}

	// the tree of positions (x, y, z a vertex) and triangles' indices
	public static function fromArrays(positions:Array<Float>, indices:Array<Int>):Bvh {
		var n = Std.int(indices.length / 3);
		var corners = new Vector<Float>(n * 9);
		for (k in 0...n * 3) {
			var i = indices[k];
			corners[k * 3] = positions[i * 3];
			corners[k * 3 + 1] = positions[i * 3 + 1];
			corners[k * 3 + 2] = positions[i * 3 + 2];
		}
		return make(corners, n);
	}

	static function make(corners:Vector<Float>, n:Int):Bvh {
		// (each triangle's box and centre)
		var box = new Vector<Float>(n * 6), centre = new Vector<Float>(n * 3), order = new Vector<Int>(n);
		for (k in 0...n) {
			order[k] = k;
			for (a in 0...3) {
				var x = corners[k * 9 + a], y = corners[k * 9 + 3 + a], z = corners[k * 9 + 6 + a];
				var lo = Math.min(x, Math.min(y, z)), hi = Math.max(x, Math.max(y, z));
				box[k * 6 + a] = lo;
				box[k * 6 + 3 + a] = hi;
				centre[k * 3 + a] = (lo + hi) * 0.5;
			}
		}
		var bounds:Array<Float> = [], links:Array<Int> = [];
		function node():Int {
			var i = links.length >> 1;
			for (_ in 0...6)
				bounds.push(0);
			links.push(0);
			links.push(0);
			return i;
		}
		node();
		// (the work: a node, its run of order, its depth)
		var work:Array<Int> = [0, 0, n, 1];
		var deepest = 1;
		var binCount = new Vector<Int>(BINS), binBox = new Vector<Float>(BINS * 6);
		var leftArea = new Vector<Float>(BINS), leftCount = new Vector<Int>(BINS);
		while (work.length > 0) {
			var d = work.pop(), end = work.pop(), start = work.pop(), at = work.pop();
			if (d > deepest) deepest = d;
			// (its box, and its centres' box)
			var b0 = Math.POSITIVE_INFINITY, b1 = b0, b2 = b0, b3 = Math.NEGATIVE_INFINITY, b4 = b3, b5 = b3;
			var c0 = b0, c1 = b0, c2 = b0, c3 = b3, c4 = b3, c5 = b3;
			for (k in start...end) {
				var t = order[k];
				b0 = Math.min(b0, box[t * 6]);
				b1 = Math.min(b1, box[t * 6 + 1]);
				b2 = Math.min(b2, box[t * 6 + 2]);
				b3 = Math.max(b3, box[t * 6 + 3]);
				b4 = Math.max(b4, box[t * 6 + 4]);
				b5 = Math.max(b5, box[t * 6 + 5]);
				c0 = Math.min(c0, centre[t * 3]);
				c1 = Math.min(c1, centre[t * 3 + 1]);
				c2 = Math.min(c2, centre[t * 3 + 2]);
				c3 = Math.max(c3, centre[t * 3]);
				c4 = Math.max(c4, centre[t * 3 + 1]);
				c5 = Math.max(c5, centre[t * 3 + 2]);
			}
			var bo = at * 6;
			bounds[bo] = b0;
			bounds[bo + 1] = b1;
			bounds[bo + 2] = b2;
			bounds[bo + 3] = b3;
			bounds[bo + 4] = b4;
			bounds[bo + 5] = b5;
			var count = end - start;
			// (the best split: an axis and a bin, by the surface area heuristic)
			var bestAxis = -1, bestBin = 0, bestCost = Math.POSITIVE_INFINITY;
			if (count > 2)
				for (axis in 0...3) {
					var lo = axis == 0 ? c0 : axis == 1 ? c1 : c2, hi = axis == 0 ? c3 : axis == 1 ? c4 : c5;
					if (hi - lo <= 0) continue;
					var scale = BINS / (hi - lo);
					for (i in 0...BINS) {
						binCount[i] = 0;
						for (j in 0...3) {
							binBox[i * 6 + j] = Math.POSITIVE_INFINITY;
							binBox[i * 6 + 3 + j] = Math.NEGATIVE_INFINITY;
						}
					}
					for (k in start...end) {
						var t = order[k];
						var i = Std.int((centre[t * 3 + axis] - lo) * scale);
						if (i >= BINS) i = BINS - 1;
						binCount[i]++;
						for (j in 0...3) {
							binBox[i * 6 + j] = Math.min(binBox[i * 6 + j], box[t * 6 + j]);
							binBox[i * 6 + 3 + j] = Math.max(binBox[i * 6 + 3 + j], box[t * 6 + 3 + j]);
						}
					}
					// (sweeps from the left, then the right: each split's two areas)
					var x0 = Math.POSITIVE_INFINITY, y0 = x0, z0 = x0, x1 = Math.NEGATIVE_INFINITY, y1 = x1, z1 = x1, c = 0;
					for (i in 0...BINS - 1) {
						c += binCount[i];
						x0 = Math.min(x0, binBox[i * 6]);
						y0 = Math.min(y0, binBox[i * 6 + 1]);
						z0 = Math.min(z0, binBox[i * 6 + 2]);
						x1 = Math.max(x1, binBox[i * 6 + 3]);
						y1 = Math.max(y1, binBox[i * 6 + 4]);
						z1 = Math.max(z1, binBox[i * 6 + 5]);
						leftCount[i] = c;
						leftArea[i] = c > 0 ? area(x1 - x0, y1 - y0, z1 - z0) : 0;
					}
					x0 = y0 = z0 = Math.POSITIVE_INFINITY;
					x1 = y1 = z1 = Math.NEGATIVE_INFINITY;
					c = 0;
					var i = BINS - 1;
					while (i > 0) {
						c += binCount[i];
						x0 = Math.min(x0, binBox[i * 6]);
						y0 = Math.min(y0, binBox[i * 6 + 1]);
						z0 = Math.min(z0, binBox[i * 6 + 2]);
						x1 = Math.max(x1, binBox[i * 6 + 3]);
						y1 = Math.max(y1, binBox[i * 6 + 4]);
						z1 = Math.max(z1, binBox[i * 6 + 5]);
						var l = leftCount[i - 1];
						if (l > 0 && c > 0) {
							var cost = leftArea[i - 1] * l + area(x1 - x0, y1 - y0, z1 - z0) * c;
							if (cost < bestCost) {
								bestCost = cost;
								bestAxis = axis;
								bestBin = i;
							}
						}
						i--;
					}
				}
			// (a leaf: few enough, and no split cheaper than testing them all)
			var whole = area(b3 - b0, b4 - b1, b5 - b2);
			var split = bestAxis >= 0 && (count > LEAF || 1 + bestCost / Math.max(whole, 1e-30) < count);
			var mid = start;
			if (split) {
				var lo = bestAxis == 0 ? c0 : bestAxis == 1 ? c1 : c2, hi = bestAxis == 0 ? c3 : bestAxis == 1 ? c4 : c5;
				var scale = BINS / (hi - lo);
				var i = start, j = end - 1;
				while (i <= j) {
					var b = Std.int((centre[order[i] * 3 + bestAxis] - lo) * scale);
					if (b >= BINS) b = BINS - 1;
					if (b < bestBin) i++ else {
						var s = order[i];
						order[i] = order[j];
						order[j] = s;
						j--;
					}
				}
				mid = i;
			} else if (count > LEAF && (c3 > c0 || c4 > c1 || c5 > c2)) {
				// (no split found among the bins: halves of the run)
				mid = start + (count >> 1);
				split = true;
			}
			if (split && mid > start && mid < end) {
				var left = node();
				node();
				links[at * 2] = left;
				links[at * 2 + 1] = 0;
				work.push(left);
				work.push(start);
				work.push(mid);
				work.push(d + 1);
				work.push(left + 1);
				work.push(mid);
				work.push(end);
				work.push(d + 1);
			} else {
				links[at * 2] = start;
				links[at * 2 + 1] = count;
			}
		}
		var nodeCount = links.length >> 1;
		var nb = Bytes.alloc(nodeCount * NODE);
		for (i in 0...nodeCount) {
			for (j in 0...6)
				nb.setFloat(i * NODE + j * 4, bounds[i * 6 + j]);
			nb.setInt32(i * NODE + 24, links[i * 2]);
			nb.setInt32(i * NODE + 28, links[i * 2 + 1]);
		}
		var tb = Bytes.alloc(n * TRI);
		for (k in 0...n) {
			var t = order[k];
			for (j in 0...9)
				tb.setFloat(k * TRI + j * 4, corners[t * 9 + j]);
			tb.setInt32(k * TRI + 36, t);
		}
		return new Bvh(nb, tb, nodeCount, n, deepest);
	}

	static inline function area(x:Float, y:Float, z:Float):Float
		return x * y + y * z + z * x;

	// the nearest triangle the ray from origin along dir (any length: the
	// distances are in its lengths) crosses within maxT, its back too when
	// backfaces; false when none (t, triangle, u, v, front: the hit's)
	public function intersect(origin:Vec3, dir:Vec3, maxT:Float, backfaces:Bool):Bool {
		var found = false, best = maxT;
		if (nodeCount == 0) return false;
		var ox = origin.x, oy = origin.y, oz = origin.z, dx = dir.x, dy = dir.y, dz = dir.z;
		var ix = inv(dx), iy = inv(dy), iz = inv(dz);
		var t0 = slab(0, ox, oy, oz, ix, iy, iz, best);
		if (t0 < 0) return false;
		var sp = 0;
		stack[sp] = 0;
		stackT[sp++] = t0;
		while (sp > 0) {
			sp--;
			if (stackT[sp] > best) continue;
			var node = stack[sp], o = node * NODE;
			var a = nodes.getInt32(o + 24), n = nodes.getInt32(o + 28);
			if (n > 0) {
				for (k in a...a + n) {
					var h = hitTriangle(k, ox, oy, oz, dx, dy, dz, best, backfaces);
					if (h >= 0) {
						best = h;
						found = true;
						t = h;
						triangle = triangles.getInt32(k * TRI + 36);
						u = hu;
						v = hv;
						front = hfront;
					}
				}
				continue;
			}
			// (the nearer child popped first: pushed last)
			var tl = slab(a, ox, oy, oz, ix, iy, iz, best), tr = slab(a + 1, ox, oy, oz, ix, iy, iz, best);
			if (tl >= 0 && tr >= 0) {
				var nearL = tl <= tr;
				stack[sp] = nearL ? a + 1 : a;
				stackT[sp++] = nearL ? tr : tl;
				stack[sp] = nearL ? a : a + 1;
				stackT[sp++] = nearL ? tl : tr;
			} else if (tl >= 0) {
				stack[sp] = a;
				stackT[sp++] = tl;
			} else if (tr >= 0) {
				stack[sp] = a + 1;
				stackT[sp++] = tr;
			}
		}
		return found;
	}

	// every triangle the ray crosses within maxT, each given to sink (in no
	// order); their count
	public function intersectAll(origin:Vec3, dir:Vec3, maxT:Float, backfaces:Bool, sink:BvhSink):Int {
		if (nodeCount == 0) return 0;
		var ox = origin.x, oy = origin.y, oz = origin.z, dx = dir.x, dy = dir.y, dz = dir.z;
		var ix = inv(dx), iy = inv(dy), iz = inv(dz);
		if (slab(0, ox, oy, oz, ix, iy, iz, maxT) < 0) return 0;
		var sp = 0, hits = 0;
		stack[sp++] = 0;
		while (sp > 0) {
			var node = stack[--sp], o = node * NODE;
			var a = nodes.getInt32(o + 24), n = nodes.getInt32(o + 28);
			if (n > 0) {
				for (k in a...a + n) {
					var h = hitTriangle(k, ox, oy, oz, dx, dy, dz, maxT, backfaces);
					if (h >= 0) {
						hits++;
						sink.hit(h, triangles.getInt32(k * TRI + 36), hu, hv, hfront);
					}
				}
				continue;
			}
			if (slab(a, ox, oy, oz, ix, iy, iz, maxT) >= 0) stack[sp++] = a;
			if (slab(a + 1, ox, oy, oz, ix, iy, iz, maxT) >= 0) stack[sp++] = a + 1;
		}
		return hits;
	}

	// (the last triangle test's barycentrics and side)
	var hu = 0.0;
	var hv = 0.0;
	var hfront = true;

	static inline function inv(d:Float):Float
		return d == 0 ? 1e30 : 1 / d;

	// (the entry distance of the ray into node's box, -1 when it misses it
	// or enters past maxT)
	inline function slab(node:Int, ox:Float, oy:Float, oz:Float, ix:Float, iy:Float, iz:Float, maxT:Float):Float {
		var o = node * NODE;
		var ax = (nodes.getFloat(o) - ox) * ix, bx = (nodes.getFloat(o + 12) - ox) * ix;
		var ay = (nodes.getFloat(o + 4) - oy) * iy, by = (nodes.getFloat(o + 16) - oy) * iy;
		var az = (nodes.getFloat(o + 8) - oz) * iz, bz = (nodes.getFloat(o + 20) - oz) * iz;
		var lo = Math.max(Math.max(Math.min(ax, bx), Math.min(ay, by)), Math.max(Math.min(az, bz), 0.0));
		var hi = Math.min(Math.min(Math.max(ax, bx), Math.max(ay, by)), Math.min(Math.max(az, bz), maxT));
		return lo <= hi ? lo : -1;
	}

	// (Möller and Trumbore's: the distance to triangle k, -1 when missed;
	// hu, hv and hfront its barycentrics and side)
	function hitTriangle(k:Int, ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float, maxT:Float, backfaces:Bool):Float {
		var o = k * TRI, b = triangles;
		var ax = b.getFloat(o), ay = b.getFloat(o + 4), az = b.getFloat(o + 8);
		var e1x = b.getFloat(o + 12) - ax, e1y = b.getFloat(o + 16) - ay, e1z = b.getFloat(o + 20) - az;
		var e2x = b.getFloat(o + 24) - ax, e2y = b.getFloat(o + 28) - ay, e2z = b.getFloat(o + 32) - az;
		var px = dy * e2z - dz * e2y, py = dz * e2x - dx * e2z, pz = dx * e2y - dy * e2x;
		var det = e1x * px + e1y * py + e1z * pz;
		// (a front, counter-clockwise towards the ray: det above 0)
		if (det > -1e-12 && det < 1e-12) return -1;
		if (det < 0 && !backfaces) return -1;
		var id = 1 / det;
		var sx = ox - ax, sy = oy - ay, sz = oz - az;
		var uu = (sx * px + sy * py + sz * pz) * id;
		if (uu < 0 || uu > 1) return -1;
		var qx = sy * e1z - sz * e1y, qy = sz * e1x - sx * e1z, qz = sx * e1y - sy * e1x;
		var vv = (dx * qx + dy * qy + dz * qz) * id;
		if (vv < 0 || uu + vv > 1) return -1;
		var tt = (e2x * qx + e2y * qy + e2z * qz) * id;
		if (tt < 0 || tt > maxT) return -1;
		hu = uu;
		hv = vv;
		hfront = det > 0;
		return tt;
	}

	// its boxes fitted again to moved vertices (a morph's or a skin's
	// positions on the CPU: vertices of stride bytes, the primitive's own
	// triangles' indices), the tree's shape kept (three-mesh-bvh's refit)
	public function refit(vertices:Bytes, stride:Int, data:VertexData) {
		for (k in 0...triangleCount) {
			var t = triangles.getInt32(k * TRI + 36);
			for (c in 0...3) {
				var p = data.index(3 * t + c) * stride;
				for (j in 0...3)
					triangles.setFloat(k * TRI + (c * 3 + j) * 4, vertices.getFloat(p + j * 4));
			}
		}
		// (children after their parents: from the last node back)
		var i = nodeCount - 1;
		while (i >= 0) {
			var o = i * NODE, a = nodes.getInt32(o + 24), n = nodes.getInt32(o + 28);
			for (j in 0...3) {
				var lo = Math.POSITIVE_INFINITY, hi = Math.NEGATIVE_INFINITY;
				if (n > 0)
					for (k in a...a + n)
						for (c in 0...3) {
							var x = triangles.getFloat(k * TRI + (c * 3 + j) * 4);
							if (x < lo) lo = x;
							if (x > hi) hi = x;
						}
				else
					for (ch in a...a + 2) {
						lo = Math.min(lo, nodes.getFloat(ch * NODE + j * 4));
						hi = Math.max(hi, nodes.getFloat(ch * NODE + 12 + j * 4));
					}
				nodes.setFloat(o + j * 4, lo);
				nodes.setFloat(o + 12 + j * 4, hi);
			}
			i--;
		}
	}

	// the tree as bytes (the asset step's: read takes them back as they are)
	public function bytes():Bytes {
		var b = Bytes.alloc(12 + nodes.length + triangles.length);
		b.setInt32(0, nodeCount);
		b.setInt32(4, triangleCount);
		b.setInt32(8, depth);
		b.blit(12, nodes, 0, nodes.length);
		b.blit(12 + nodes.length, triangles, 0, triangles.length);
		return b;
	}

	public static function read(b:Bytes):Bvh {
		var nodeCount = b.getInt32(0), triangleCount = b.getInt32(4), depth = b.getInt32(8);
		return new Bvh(b.sub(12, nodeCount * NODE), b.sub(12 + nodeCount * NODE, triangleCount * TRI), nodeCount, triangleCount, depth);
	}
}

// what Bvh.intersectAll gives each triangle the ray crosses (its distance, its
// triangle, the barycentrics of its second and third corners, its side)
interface BvhSink {
	function hit(t:Float, triangle:Int, u:Float, v:Float, front:Bool):Void;
}
