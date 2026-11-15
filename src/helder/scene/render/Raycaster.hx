package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.render.Hit;

// Rays cast at a world's triangles (world.raycast, world.raycastAll: three's
// Raycaster, Bevy's MeshRayCast): each shown node drawing a mesh
// (MeshRenderer) and each instance of an instanced set (InstancedMesh,
// Sprites, Text3D), the ray brought into its frame (turned, moved and
// scaled, unevenly too), its bounds first, then each primitive's bounds and
// its triangles through the primitive's Bvh (made when first cast at, from
// the data it keeps on the CPU: Mesh.keepCpu; or the asset step's). The
// nearest hit fills a Hit the program owns, every hit a HitList: nothing is
// allocated a cast, the trees once made.
//
//   final hit = new Hit();
//   if (world.raycast(ray.origin, ray.dir, hit)) paint(hit.node, hit.uv);
//
// Skinned and morphed meshes are cast at in their rest pose (Bvh.refit to
// fit a tree to moved vertices). Pick.ray stays the bounds-only fast path.
class Raycaster implements Bvh.BvhSink {
	// a node's layers (a mask; 1 unless set), which a cast's options.layers picks
	public static final LAYERS = new StoreKind<Int>("raycastLayers");

	public static function setLayers(node:Node, mask:Int)
		node.world.store(LAYERS).set(node, mask);

	public static function layersOf(node:Node):Int {
		var m:Null<Int> = node.world.store(LAYERS).get(node);
		return m == null ? 1 : m;
	}

	static final defaults = new RaycastOptions();
	static var shared:Null<Raycaster> = null;

	// (the cast's state: castAll's sink)
	var list:Null<HitList> = null;
	var node = Node.NONE;
	var model:Mat4 = Mat4.identity();
	var prim:Null<Mesh.Primitive> = null;
	var instance = -1;
	var origin:Vec3 = new Vec3(0, 0, 0);
	var dir:Vec3 = new Vec3(0, 0, 1);

	function new() {}

	static function get():Raycaster {
		if (shared == null) shared = new Raycaster();
		return shared;
	}

	// the nearest hit of the ray from origin along dir (normalized here)
	// into hit; false when it hits nothing (hit as it was)
	public static function raycast(world:World, origin:Vec3, dir:Vec3, hit:Hit, ?options:RaycastOptions):Bool {
		var r = get();
		r.list = null;
		return r.run(world, origin, dir, hit, options ?? defaults);
	}

	// every hit of the ray into hits, nearest first (the list refilled);
	// their count
	public static function raycastAll(world:World, origin:Vec3, dir:Vec3, hits:HitList, ?options:RaycastOptions):Int {
		var r = get();
		hits.clear();
		r.list = hits;
		r.run(world, origin, dir, null, options ?? defaults);
		r.list = null;
		hits.sort();
		return hits.count;
	}

	var best = 0.0;
	var found = false;
	var into:Null<Hit> = null;
	var options:RaycastOptions = defaults;

	function run(world:World, o:Vec3, d:Vec3, hit:Null<Hit>, opts:RaycastOptions):Bool {
		var l = Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
		if (l == 0) return false;
		origin = o;
		dir = d / l;
		best = opts.maxDistance;
		found = false;
		into = hit;
		options = opts;
		var meshes = world.store(MeshRenderer.KIND);
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k), mesh = meshes.valueAt(k);
			if (mesh.bounds.isEmpty() || !n.shown() || !world.inTree(n)) continue;
			if (opts.layers != -1 && (layersOf(n) & opts.layers) == 0) continue;
			castMesh(n, mesh, n.worldMatrix(), -1);
		}
		if (opts.instances) {
			var sets = world.store(InstancedMesh.KIND);
			for (k in 0...sets.length) {
				var n = sets.nodeAt(k), s = sets.valueAt(k);
				if (s.count == 0 || s.mesh.bounds.isEmpty() || !n.shown() || !world.inTree(n)) continue;
				if (opts.layers != -1 && (layersOf(n) & opts.layers) == 0) continue;
				if (!s.bounds.isEmpty() && s.bounds.ray(origin, dir) < 0) continue;
				var b = s.mesh.bounds, data = s.data;
				for (i in 0...s.count) {
					var m = instanceMatrix(data, i);
					// (the instance's box in the world first: Arvo's, from the mesh's)
					if (!boxHit(m, b.min, b.max)) continue;
					castMesh(n, s.mesh, m, i);
				}
			}
		}
		return found;
	}

	// (instance i's matrix: its columns, their w's the colour's and the cell's, an affine matrix's 0, 0, 0, 1)
	static inline function instanceMatrix(d:Bytes, i:Int):Mat4 {
		var o = i * InstancedMesh.STRIDE;
		return new Mat4(new Vec4(d.getFloat(o), d.getFloat(o + 4), d.getFloat(o + 8), 0), new Vec4(d.getFloat(o + 16), d.getFloat(o + 20), d.getFloat(o + 24), 0),
			new Vec4(d.getFloat(o + 32), d.getFloat(o + 36), d.getFloat(o + 40), 0), new Vec4(d.getFloat(o + 48), d.getFloat(o + 52), d.getFloat(o + 56), 1));
	}

	// (whether the ray meets the box min to max moved by m within best)
	function boxHit(m:Mat4, min:Vec3, max:Vec3):Bool {
		var cx = (min.x + max.x) * 0.5, cy = (min.y + max.y) * 0.5, cz = (min.z + max.z) * 0.5;
		var ex = (max.x - min.x) * 0.5, ey = (max.y - min.y) * 0.5, ez = (max.z - min.z) * 0.5;
		var tc = MathTools.transformPoint(m, new Vec3(cx, cy, cz));
		var wx = Math.abs(m.c0.x) * ex + Math.abs(m.c1.x) * ey + Math.abs(m.c2.x) * ez;
		var wy = Math.abs(m.c0.y) * ex + Math.abs(m.c1.y) * ey + Math.abs(m.c2.y) * ez;
		var wz = Math.abs(m.c0.z) * ex + Math.abs(m.c1.z) * ey + Math.abs(m.c2.z) * ez;
		var lo = 0.0, hi = best;
		for (a in 0...3) {
			var o = a == 0 ? origin.x : a == 1 ? origin.y : origin.z, d = a == 0 ? dir.x : a == 1 ? dir.y : dir.z;
			var c = a == 0 ? tc.x : a == 1 ? tc.y : tc.z, e = a == 0 ? wx : a == 1 ? wy : wz;
			if (d == 0) {
				if (o < c - e || o > c + e) return false;
				continue;
			}
			var t0 = (c - e - o) / d, t1 = (c + e - o) / d;
			if (t0 > t1) {
				var s = t0;
				t0 = t1;
				t1 = s;
			}
			if (t0 > lo) lo = t0;
			if (t1 < hi) hi = t1;
			if (lo > hi) return false;
		}
		return true;
	}

	function castMesh(n:Node, mesh:Mesh, m:Mat4, inst:Int) {
		var inv = MathTools.inverse(m);
		var lo = MathTools.transformPoint(inv, origin), ld = MathTools.transformDir(inv, dir);
		// (lo + t ld in its frame is origin + t dir in the world: t the world's distance)
		var tb = mesh.bounds.ray(lo, ld);
		if (tb < 0 || (list == null && tb > best)) return;
		node = n;
		model = m;
		instance = inst;
		for (p in mesh.primitives) {
			var pb = p.bounds.ray(lo, ld);
			var limit = list == null ? best : options.maxDistance;
			if (pb < 0 || pb > limit) continue;
			var tree = options.triangles ? p.bvh : null;
			if (tree == null) {
				// (its bounds alone: the box's point)
				prim = p;
				record(pb, -1, 0, 0, true);
				continue;
			}
			prim = p;
			if (list != null) tree.intersectAll(lo, ld, limit, options.backfaces, this);
			else if (tree.intersect(lo, ld, limit, options.backfaces)) record(tree.t, tree.triangle, tree.u, tree.v, tree.front);
		}
	}

	// (castAll's: each triangle hit)
	public function hit(t:Float, triangle:Int, u:Float, v:Float, front:Bool)
		record(t, triangle, u, v, front);

	function record(t:Float, triangle:Int, u:Float, v:Float, front:Bool) {
		var h:Hit;
		if (list != null) h = list.next() else {
			if (t > best) return;
			best = t;
			h = into;
		}
		found = true;
		h.node = node;
		h.distance = t;
		h.point = origin + dir * t;
		h.primitive = prim;
		h.triangle = triangle;
		h.instance = instance;
		h.front = front;
		var w = 1 - u - v;
		h.barycentric = new Vec3(w, u, v);
		var data = prim.data;
		if (triangle < 0 || data == null) {
			h.normal = dir * -1;
			h.uv = new Vec2(0, 0);
			return;
		}
		var a = data.index(3 * triangle), b = data.index(3 * triangle + 1), c = data.index(3 * triangle + 2);
		var na = data.normal(a), nb = data.normal(b), nc = data.normal(c);
		var nl = MathTools.transformDir(MathTools.normalMatrix(model), na * w + nb * u + nc * v);
		var len = Math.sqrt(nl.x * nl.x + nl.y * nl.y + nl.z * nl.z);
		var nw = len > 0 ? nl / len : dir * -1;
		// (towards the ray: the back's normal when the back was hit)
		if (nw.x * dir.x + nw.y * dir.y + nw.z * dir.z > 0) nw = nw * -1;
		h.normal = nw;
		h.uv = data.uv(a) * w + data.uv(b) * u + data.uv(c) * v;
	}
}
