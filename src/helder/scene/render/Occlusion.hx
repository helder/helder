package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Node;
import helder.scene.StoreKind;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.render.OcclusionShader;

// Occlusion culling by queries, a RenderFeature (renderer.use(new
// Occlusion(device))), as Babylon's occlusion queries: each node marked
// (Occlusion.test(node): large ones, what a wall may hide) has its bounds
// drawn as a box after the frame's opaque surfaces, depth tested and not
// written, inside a query of gfx's (Device.createQueries); a node whose
// last answered query passed no sample is culled at the next frames'
// extraction (Renderer.occluded counts it, --stats' occluded), its box
// still drawn each frame so that it comes back when it is seen again (a
// frame or more late: the queries are never waited for). A node outside
// the view, or whose bounds hold the eye, is not tested and never culled;
// its last answer is let go (Device.resetQuery). The boxes are one draw
// each (a query each): test what is worth it, not every pebble. Nothing is
// allocated per frame. GPU-driven culling against a depth pyramid is the
// compute tier's (DESIGN-3D.md, section 8).
//
//   renderer.use(new Occlusion(device));
//   Occlusion.test(building);           // its node's meshes culled while hidden
class Occlusion implements RenderFeature implements RenderFeature.OcclusionSource {
	// the nodes tested: their query and last answer (Occlusion.test)
	@:noCompletion public static final KIND = new StoreKind<OcclusionTest>("occlusion");

	public final device:Device;
	// the queries (one a node tested, at most capacity: those past it untested)
	public final capacity:Int;
	// off: nothing culled, no boxes drawn (the answers let go)
	public var enabled = true;
	// the last frame's boxes drawn (each a query)
	public var draws(default, null) = 0;
	// how much larger than its bounds a box is drawn (a share of its size,
	// and metres: its own surfaces not taken for what hides it)
	public var margin = 0.02;

	final queries:QuerySet;
	final cube:Buffer;
	final cubeIndices:Buffer;
	var boxes:Buffer = Buffer.NONE;
	var boxCapacity = 0;
	var boxBytes = Bytes.alloc(64 * 16);
	final viewBytes = Bytes.alloc(OcclusionShader.uniforms[0].size);
	final viewBlock:OcclusionView = {viewProj: Mat4.identity()};
	// (this frame's tested entries, in box order)
	final drawn:Array<OcclusionTest> = [];
	var count = 0;
	var renderer:Null<Renderer> = null;
	// (the queries given out: a node's entry keeps its index)
	static var given = 0;

	static final LAYOUT:Array<VertexBufferLayout> = [
		{stride: 12, attributes: [{location: 0, format: Float3, offset: 0}]},
		{
			stride: 64,
			step: Instance,
			attributes: [
				{location: 1, format: Float4, offset: 0}, {location: 2, format: Float4, offset: 16}, {location: 3, format: Float4, offset: 32},
				{location: 4, format: Float4, offset: 48}
			]
		}
	];

	public function new(device:Device, capacity = 1024) {
		this.device = device;
		this.capacity = capacity;
		queries = device.createQueries(capacity);
		var corners = Bytes.alloc(8 * 12);
		for (k in 0...8) {
			corners.setFloat(k * 12, k & 1);
			corners.setFloat(k * 12 + 4, (k >> 1) & 1);
			corners.setFloat(k * 12 + 8, (k >> 2) & 1);
		}
		cube = device.createBuffer({size: corners.length, usage: Vertex, data: corners});
		// (each face's two triangles, turning anticlockwise seen from outside)
		var faces = [0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3, 0, 4, 5, 0, 5, 1, 2, 3, 7, 2, 7, 6, 0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5];
		var idx = Bytes.alloc(faces.length * 2);
		for (k in 0...faces.length)
			idx.setUInt16(k * 2, faces[k]);
		cubeIndices = device.createBuffer({size: idx.length, usage: Index, data: idx});
	}

	// a node's meshes culled while what is drawn before them hides their bounds
	public static function test(node:Node) {
		var store = node.world.store(KIND);
		if (store.get(node) != null) return;
		store.set(node, new OcclusionTest(node, given++));
	}

	// a node no longer tested (drawn whenever in view)
	public static function untest(node:Node)
		node.world.store(KIND).remove(node);

	// whether a node is tested (Occlusion.test)
	public static function tested(node:Node):Bool
		return node.world.store(KIND).get(node) != null;

	@:noCompletion public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.occluder = this;
		made = renderer.createPipeline(desc());
	}

	var made:Null<Pipeline> = null;

	function desc():PipelineDesc {
		var d = OcclusionShader.pipeline({cull: Back, depthCompare: LessEqual, depthWrite: false, blend: Multiply});
		d.layout = LAYOUT;
		return d;
	}

	@:noCompletion public function prepare(renderer:Renderer, world:World, viewProj:Mat4, eye:Vec3) {
		count = 0;
		draws = 0;
		@:privateAccess renderer.pass.queries = enabled ? queries : null;
		var store = world.store(KIND), meshes = world.store(MeshRenderer.KIND);
		for (k in 0...store.length) {
			var node = store.nodeAt(k), e = store.valueAt(k);
			var mesh = meshes.get(node);
			var bounds = mesh != null ? mesh.bounds : null;
			var testing = enabled && e.query < capacity && bounds != null && !bounds.isEmpty() && node.shown() && world.inTree(node);
			var m = testing ? node.worldMatrix() : Mat4.identity();
			if (testing) {
				// (its bounds as a box in the world, a little larger)
				var size = bounds.max - bounds.min;
				var grow = new Vec3(size.x * margin + 0.01, size.y * margin + 0.01, size.z * margin + 0.01);
				var lo = bounds.min - grow, hi = bounds.max + grow;
				var box = m * new Mat4(new Vec4(hi.x - lo.x, 0, 0, 0), new Vec4(0, hi.y - lo.y, 0, 0), new Vec4(0, 0, hi.z - lo.z, 0), new Vec4(lo.x, lo.y, lo.z, 1));
				// (in view, and not holding the eye)
				var local = MathTools.inverse(box) * new Vec4(eye.x, eye.y, eye.z, 1);
				var inside = local.x >= 0 && local.x <= 1 && local.y >= 0 && local.y <= 1 && local.z >= 0 && local.z <= 1;
				testing = !inside && @:privateAccess Renderer.visibleBox(viewProj * m, bounds);
				if (testing) {
					if (count * 64 + 64 > boxBytes.length) {
						var grown = Bytes.alloc(boxBytes.length * 2);
						grown.blit(0, boxBytes, 0, count * 64);
						boxBytes = grown;
					}
					for (c in 0...4) {
						var col = MathTools.col(box, c);
						boxBytes.setFloat(count * 64 + c * 16, col.x);
						boxBytes.setFloat(count * 64 + c * 16 + 4, col.y);
						boxBytes.setFloat(count * 64 + c * 16 + 8, col.z);
						boxBytes.setFloat(count * 64 + c * 16 + 12, col.w);
					}
					if (count == drawn.length) drawn.push(e) else drawn[count] = e;
					count++;
				}
			}
			if (testing) {
				e.hidden = device.queryResult(queries, e.query) == 0;
				e.tested = true;
			} else {
				e.hidden = false;
				if (e.tested && e.query < capacity) device.resetQuery(queries, e.query);
				e.tested = false;
			}
		}
		if (count > 0) {
			if (count * 64 > boxCapacity) {
				if (boxCapacity > 0) device.destroyBuffer(boxes);
				boxCapacity = boxBytes.length;
				boxes = device.createBuffer({size: boxCapacity, usage: Vertex});
			}
			device.writeBuffer(boxes, 0, boxBytes, 0, count * 64);
		}
		viewBlock.viewProj = viewProj;
		OcclusionShader.params.view.write(viewBlock, viewBytes);
	}

	@:noCompletion public function hidden(node:Node):Bool {
		if (!enabled) return false;
		var e = node.world.store(KIND).get(node);
		return e != null && e.hidden;
	}

	@:noCompletion public function draw(enc:Encoder, renderer:Renderer) {
		if (!enabled || count == 0 || made == null) return;
		enc.setPipeline(made);
		enc.setUniforms(OcclusionShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, cube);
		enc.setIndexBuffer(cubeIndices, UInt16);
		for (k in 0...count) {
			enc.setVertexBuffer(1, boxes, k * 64);
			enc.beginQuery(drawn[k].query);
			enc.drawIndexed(36, 1);
			enc.endQuery();
		}
		draws = count;
	}

	public function dispose() {
		device.destroyQueries(queries);
		device.destroyBuffer(cube);
		device.destroyBuffer(cubeIndices);
		if (boxCapacity > 0) device.destroyBuffer(boxes);
		boxCapacity = 0;
		var r = renderer;
		if (r != null && @:privateAccess r.occluder == this) {
			@:privateAccess r.occluder = null;
			@:privateAccess r.pass.queries = null;
		}
	}
}

// a tested node's: its query, whether its last answer was hidden, whether
// it was tested last frame
class OcclusionTest {
	public final node:Node;
	public final query:Int;
	public var hidden = false;
	public var tested = false;

	public function new(node:Node, query:Int) {
		this.node = node;
		this.query = query;
	}
}
