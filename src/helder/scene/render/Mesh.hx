package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.gfx.Device;
import helder.gfx.IndexFormat;
import helder.scene.math.Aabb;

// What a node draws (node.mesh): primitives, each a vertex buffer in the
// renderer's layout (PbrVertex: position, normal, uv; 32 bytes a vertex),
// triangles' indices and a material, and the bounds of them all. Each
// primitive keeps its data on the CPU too (Primitive.data: the same bytes
// the GPU was given, for casting rays at its triangles: Raycaster), unless
// Mesh.keepCpu is off when it is made.
class Mesh {
	// whether the primitives made from now on keep their data on the CPU
	// (Primitive.data: raycasts against their triangles; off: only their
	// bounds are cast at, the bytes let go once uploaded)
	public static var keepCpu = true;

	public var primitives(default, null):Array<Primitive> = [];
	public var bounds(default, null):Aabb = Aabb.empty();

	public function new() {}

	// a primitive from positions, normals and uvs (x, y, z / u, v per
	// vertex; normals null: computed from the triangles, smooth where
	// vertices are shared) and triangles' indices (null: 0, 1, 2, ...)
	public function add(device:Device, positions:Array<Float>, normals:Null<Array<Float>>, uvs:Null<Array<Float>>, indices:Null<Array<Int>>,
			material:Material, ?joints:Array<Float>, ?weights:Array<Float>, ?tangents:Array<Float>):Primitive {
		return addData(device, VertexData.make(positions, normals, uvs, indices, joints, weights, tangents), material);
	}

	// a primitive from data in the renderer's layout (VertexData: made here, or packed at build time)
	public function addData(device:Device, d:VertexData, material:Material):Primitive {
		var prim = new Primitive(device.createBuffer({size: d.vertices.length, usage: Vertex, data: d.vertices}),
			device.createBuffer({size: d.indices.length, usage: Index, data: d.indices}), d.wide ? UInt32 : UInt16, d.count, material, d.bounds, d.skinned);
		if (d.tangents != null) prim.tangents = device.createBuffer({size: d.tangents.length, usage: Vertex, data: d.tangents});
		if (keepCpu) prim.data = d;
		primitives.push(prim);
		bounds = bounds.union(prim.bounds);
		return prim;
	}

	// a primitive of data on the CPU alone, no GPU buffers (not drawn): its
	// triangles cast at (Raycaster) and its bounds, without a device (tests,
	// a level's collision shapes)
	public function addCpu(d:VertexData, material:Material):Primitive {
		var prim = new Primitive(Buffer.NONE, Buffer.NONE, d.wide ? UInt32 : UInt16, d.count, material, d.bounds, d.skinned);
		prim.data = d;
		primitives.push(prim);
		bounds = bounds.union(prim.bounds);
		return prim;
	}

	// a primitive made elsewhere (a morph's copy, sharing the original's indices)
	public function addPrimitive(p:Primitive):Primitive {
		primitives.push(p);
		bounds = bounds.union(p.bounds);
		return p;
	}

	// other's primitives and bounds in this mesh, this one's in other (a
	// model's reload: what draws this mesh draws the new ones; other then
	// disposed with the old)
	public function take(other:Mesh) {
		var p = primitives, b = bounds;
		primitives = other.primitives;
		bounds = other.bounds;
		other.primitives = p;
		other.bounds = b;
	}

	public function dispose(device:Device) {
		for (p in primitives) {
			if (p.vertices == Buffer.NONE) continue;
			device.destroyBuffer(p.vertices);
			device.destroyBuffer(p.indices);
			if (p.tangents != null) device.destroyBuffer(p.tangents);
		}
		primitives = [];
	}

	public static inline function smoothNormals(positions:Array<Float>, indices:Array<Int>):Array<Float>
		return VertexData.smoothNormals(positions, indices);
}

class Primitive {
	static var made = 0;

	// (draws of one primitive are batched by it)
	public final id:Int = made++;

	public final vertices:Buffer;
	public final indices:Buffer;
	public final indexFormat:IndexFormat;
	public final count:Int;
	public var material:Material;
	public final bounds:Aabb;
	// its vertices carry joints and weights (drawn with a Skin)
	public final skinned:Bool;
	// its vertices' tangents (VertexData.tangents), for normal maps; null: none
	public var tangents:Null<Buffer>;
	// its data on the CPU (Mesh.keepCpu; null: let go), what rays are cast at
	public var data:Null<VertexData> = null;
	// the tree over its triangles rays are cast through: made from data when
	// first asked (null: no data), or the asset step's (Pack --bvh)
	public var bvh(get, set):Null<Bvh>;
	var tree:Null<Bvh> = null;

	function get_bvh():Null<Bvh> {
		if (tree == null && data != null) tree = Bvh.build(data);
		return tree;
	}

	inline function set_bvh(b:Null<Bvh>):Null<Bvh>
		return tree = b;

	// a primitive sharing this one's buffers, data and tree in another material
	public function withMaterial(material:Material):Primitive {
		var p = new Primitive(vertices, indices, indexFormat, count, material, bounds, skinned);
		p.tangents = tangents;
		p.data = data;
		p.tree = tree;
		return p;
	}

	public function new(vertices:Buffer, indices:Buffer, indexFormat:IndexFormat, count:Int, material:Material, bounds:Aabb, skinned = false) {
		this.skinned = skinned;
		this.vertices = vertices;
		this.indices = indices;
		this.indexFormat = indexFormat;
		this.count = count;
		this.material = material;
		this.bounds = bounds;
	}
}
