package helder.scene.render;

import helder.math.Vec2;
import helder.math.Vec3;
import helder.scene.Node;

// Where a ray met the world (world.raycast, Raycaster): filled by the cast,
// owned by the program (one kept and refilled: nothing allocated a cast).
// The node hit, how far along the ray (the world's units), the point,
// the surface's normal there (its vertices' normals blended, in the world,
// turned towards the ray: the back's when the back was hit), which side,
// the primitive and its triangle (indices 3 * triangle on), the
// barycentrics of the triangle's corners and the uvs there; an instanced
// set's instance (-1: a node's mesh). A cast at bounds alone (triangles
// off, or a primitive with no data on the CPU) gives the box's point, no
// triangle (-1), the ray's opposite for a normal.
class Hit {
	public var node:Node = Node.NONE;
	public var distance = 0.0;
	public var point:Vec3 = new Vec3(0, 0, 0);
	public var normal:Vec3 = new Vec3(0, 0, 1);
	// whether the triangle's front was hit (counter-clockwise towards the ray)
	public var front = true;
	public var primitive:Null<Mesh.Primitive> = null;
	public var triangle = -1;
	// the weights of the triangle's three corners (x the first's)
	public var barycentric:Vec3 = new Vec3(1, 0, 0);
	public var uv:Vec2 = new Vec2(0, 0);
	public var instance = -1;

	public function new() {}

	// another hit's values in this one
	public function copyFrom(h:Hit):Hit {
		node = h.node;
		distance = h.distance;
		point = h.point;
		normal = h.normal;
		front = h.front;
		primitive = h.primitive;
		triangle = h.triangle;
		barycentric = h.barycentric;
		uv = h.uv;
		instance = h.instance;
		return this;
	}
}

// The hits of world.raycastAll, nearest first, refilled by each cast: its
// hits kept between casts (more made only when a cast has more hits than
// any before it).
class HitList {
	// the last cast's hits
	public var count(default, null) = 0;
	final hits:Array<Hit> = [];

	public function new() {}

	public inline function get(i:Int):Hit
		return hits[i];

	@:allow(helder.scene.render) function clear()
		count = 0;

	// (the next hit to fill)
	@:allow(helder.scene.render) function next():Hit {
		if (count == hits.length) hits.push(new Hit());
		return hits[count++];
	}

	// (the last one taken given back: a candidate that was not a hit)
	@:allow(helder.scene.render) function drop()
		count--;

	// (nearest first: insertion, the hits few)
	@:allow(helder.scene.render) function sort()
		for (i in 1...count) {
			var h = hits[i], j = i - 1;
			while (j >= 0 && hits[j].distance > h.distance) {
				hits[j + 1] = hits[j];
				j--;
			}
			hits[j + 1] = h;
		}
}

// What a cast looks at (world.raycast's options; kept by the program, not
// made a cast): as far as maxDistance, the nodes of layers (a mask of
// Raycaster.setLayers' bits: a node's 1 unless set), at the triangles
// (false: the primitives' bounds alone, Pick.ray's way), their backs too
// with backfaces, instanced sets (InstancedMesh, Sprites, Text3D) with
// instances.
class RaycastOptions {
	public var maxDistance = Math.POSITIVE_INFINITY;
	public var layers = -1;
	public var triangles = true;
	public var backfaces = false;
	public var instances = true;

	public function new(?o:{?maxDistance:Float, ?layers:Int, ?triangles:Bool, ?backfaces:Bool, ?instances:Bool}) {
		if (o == null) return;
		if (o.maxDistance != null) maxDistance = o.maxDistance;
		if (o.layers != null) layers = o.layers;
		if (o.triangles != null) triangles = o.triangles;
		if (o.backfaces != null) backfaces = o.backfaces;
		if (o.instances != null) instances = o.instances;
	}
}
