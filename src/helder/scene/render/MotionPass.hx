package helder.scene.render;

import helder.gfx.shader.Vec4;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.scene.Node;
import helder.scene.math.MathTools;
import helder.scene.render.VelocityShaders;

// The view buffers' motion (ViewBuffers.velocity, VelocityShaders' notes):
// after their prepass, the frame's opaque draws again into an RGBA16F
// target of their size with a depth of its own (Depth32F), each point by
// its node's world matrix now and the frame before (MotionStore: kept by
// node, nothing allocated) and the camera's view-projections then and now.
// Instanced runs read the last frame's matrices from a buffer of their own
// beside the renderer's instances; an instanced set (InstancedMesh) moves
// with the camera alone, a skinned mesh is not drawn (0 there: the
// camera's motion from depth, what reads it falls back to). A module of
// its own, made by ViewBuffers when velocity is first asked for.
class MotionPass implements RenderFeature.MotionSource {
	final views:ViewBuffers;
	final device:Device;
	final pipelines:Array<Pipeline> = [];
	final store = new MotionStore();
	final frameBytes = Bytes.alloc(VelocityShader.uniforms[slot(VelocityShader.uniforms, "VelocityFrame")].size);
	final objectBytes = Bytes.alloc(VelocityShader.uniforms[slot(VelocityShader.uniforms, "VelocityObject")].size);
	// (the blocks as written, kept: nothing allocated per draw)
	final frameBlock:VelocityFrame = {viewProj: Mat4.identity(), current: Mat4.identity(), previous: Mat4.identity()};
	final objectBlock:VelocityObject = {model: Mat4.identity(), previous: Mat4.identity()};
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0)}], depth: {load: Clear}};
	final plainFrame:Int;
	final plainObject:Int;
	final instancedFrame:Int;
	// (the instanced runs' last matrices, at the renderer's instances' offsets)
	var lastBytes = Bytes.alloc(64 * 64);
	var lastBuffer:Buffer = Buffer.NONE;
	var lastCapacity = 0;
	var width = 0;
	var height = 0;
	var target:Texture = cast 0;
	var depth:Texture = cast 0;
	var draws = 0;

	public function texture():Texture
		return target;

	public function drawn():Int
		return draws;

	static final INSTANCED:Array<VertexBufferLayout> = [
		{
			stride: 32,
			attributes: [{location: 0, format: Float3, offset: 0}, {location: 1, format: Float3, offset: 12}, {location: 2, format: Float2, offset: 24}]
		},
		{
			stride: 64,
			step: Instance,
			attributes: [
				{location: 3, format: Float4, offset: 0}, {location: 4, format: Float4, offset: 16}, {location: 5, format: Float4, offset: 32},
				{location: 6, format: Float4, offset: 48}
			]
		},
		{
			stride: 64,
			step: Instance,
			attributes: [
				{location: 7, format: Float4, offset: 0}, {location: 8, format: Float4, offset: 16}, {location: 9, format: Float4, offset: 32},
				{location: 10, format: Float4, offset: 48}
			]
		}
	];

	public function new(views:ViewBuffers) {
		this.views = views;
		device = views.device;
		for (k in 0...4) {
			var instanced = k >= 2;
			var d = instanced ? VelocityInstancedShader.pipeline({cull: k % 2 == 0 ? Back : None, depthCompare: Less, depthWrite: true}) : VelocityShader.pipeline({
				cull: k % 2 == 0 ? Back : None,
				depthCompare: Less,
				depthWrite: true
			});
			if (instanced) d.layout = INSTANCED;
			d.colorFormat = RGBA16F;
			d.depthFormat = Depth32F;
			d.samples = 1;
			pipelines.push(device.createPipeline(d));
		}
		plainFrame = VelocityShader.uniforms[slot(VelocityShader.uniforms, "VelocityFrame")].binding;
		plainObject = VelocityShader.uniforms[slot(VelocityShader.uniforms, "VelocityObject")].binding;
		instancedFrame = VelocityInstancedShader.uniforms[slot(VelocityInstancedShader.uniforms, "VelocityFrame")].binding;
	}

	public static function make(views:ViewBuffers):RenderFeature.MotionSource
		return new MotionPass(views);

	static function slot(uniforms:Array<helder.gfx.shader.Shader.UniformBlock>, name:String):Int {
		for (k in 0...uniforms.length)
			if (uniforms[k].name == name) return k;
		return 0;
	}

	function size(w:Int, h:Int) {
		if (w == width && h == height) return;
		release();
		width = w;
		height = h;
		target = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		depth = device.createTexture({width: w, height: h, format: Depth32F});
		pass.colors[0].texture = target;
		pass.depth.texture = depth;
	}

	public function render(enc:Encoder, renderer:Renderer, frame:Renderer.FrameInfo) {
		draws = 0;
		size(views.width, views.height);
		var now = frame.index;
		frameBlock.viewProj = frame.viewProj;
		frameBlock.current = frame.stillViewProj;
		frameBlock.previous = frame.previousViewProj;
		VelocityShader.params.frame.write(frameBlock, frameBytes);
		@:privateAccess {
			var r = renderer;
			// (the instanced runs' last matrices, before the pass)
			var bytes = 0;
			for (b in 0...r.batchCount) {
				var n = r.batchSize[b];
				var d = r.list[r.batchStart[b]];
				if (d.primitive.material.blended) break;
				if (n < 2 || d.primitive.skinned) continue;
				var o = r.batchOffset[b];
				if (o + 64 * n > lastBytes.length) {
					var grown = Bytes.alloc(Std.int(Math.max(lastBytes.length * 2, o + 64 * n)));
					grown.blit(0, lastBytes, 0, bytes);
					lastBytes = grown;
				}
				for (k in 0...n) {
					var node = r.list[r.batchStart[b] + k].node;
					var m = store.previous(node, now, node.worldMatrix());
					for (c in 0...4) {
						var col = MathTools.col(m, c), at = o + 64 * k + 16 * c;
						lastBytes.setFloat(at, col.x);
						lastBytes.setFloat(at + 4, col.y);
						lastBytes.setFloat(at + 8, col.z);
						lastBytes.setFloat(at + 12, col.w);
					}
				}
				bytes = o + 64 * n;
			}
			if (bytes > 0) {
				if (bytes > lastCapacity) {
					if (lastCapacity > 0) device.destroyBuffer(lastBuffer);
					lastCapacity = lastBytes.length;
					lastBuffer = device.createBuffer({size: lastCapacity, usage: Vertex});
				}
				device.writeBuffer(lastBuffer, 0, lastBytes, 0, bytes);
			}
			enc.beginPass(pass);
			// (the instanced sets: moved with the camera alone)
			for (k in 0...r.setCount) {
				var set = r.sets[k];
				for (p in set.mesh.primitives) {
					var m = p.material;
					if (p.skinned || m.blended) continue;
					enc.setPipeline(pipelines[2 + (m.doubleSided ? 1 : 0)]);
					enc.setUniforms(instancedFrame, frameBytes);
					enc.setVertexBuffer(0, p.vertices);
					enc.setVertexBuffer(1, set.buffer);
					enc.setVertexBuffer(2, set.buffer);
					enc.setIndexBuffer(p.indices, p.indexFormat);
					enc.drawIndexed(p.count, set.count);
					draws++;
				}
			}
			var current:Null<Pipeline> = null, node = Node.NONE;
			for (b in 0...r.batchCount) {
				var start = r.batchStart[b], n = r.batchSize[b];
				var d = r.list[start], p = d.primitive, m = p.material;
				if (m.blended) break;
				if (p.skinned) continue;
				var many = n > 1;
				var want = pipelines[(many ? 2 : 0) + (m.doubleSided ? 1 : 0)];
				if (want != current) {
					enc.setPipeline(want);
					enc.setUniforms(many ? instancedFrame : plainFrame, frameBytes);
					current = want;
					node = Node.NONE;
				}
				if (!many && d.node != node) {
					var model = d.node.worldMatrix();
					objectBlock.model = model;
					objectBlock.previous = store.previous(d.node, now, model);
					VelocityShader.params.object.write(objectBlock, objectBytes);
					enc.setUniforms(plainObject, objectBytes);
					node = d.node;
				}
				enc.setVertexBuffer(0, p.vertices);
				if (many) {
					enc.setVertexBuffer(1, r.instanceBuffer, r.batchOffset[b]);
					enc.setVertexBuffer(2, lastBuffer, r.batchOffset[b]);
				}
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count, n);
				draws++;
			}
			enc.endPass();
			// (each node drawn: its matrix now, the next frame's last)
			for (k in 0...r.count) {
				var d = r.list[k];
				if (d.primitive.material.blended || d.primitive.skinned) continue;
				store.record(d.node, now, d.node.worldMatrix());
			}
		}
	}

	function release() {
		if (width == 0) return;
		device.destroyTexture(target);
		device.destroyTexture(depth);
		width = height = 0;
	}

	public function dispose() {
		release();
		if (lastCapacity > 0) device.destroyBuffer(lastBuffer);
		lastCapacity = 0;
	}
}

// each node's world matrix as last drawn (by its slot: 16 floats, the
// node's id and the frame), so a frame finds where a node was the frame
// before; nothing allocated once its arrays are as long as the world's slots
class MotionStore {
	final mats:Array<Float> = [];
	final ids:Array<Int> = [];
	final frames:Array<Int> = [];

	public function new() {}

	// the node's matrix the frame before frame (now when it was not drawn then)
	public function previous(node:Node, frame:Int, now:Mat4):Mat4 {
		var s = @:privateAccess node.slot;
		if (s >= ids.length || ids[s] != node.id() || frames[s] != frame - 1) return now;
		var o = s * 16;
		return new Mat4(new helder.gfx.shader.Vec4(mats[o], mats[o + 1], mats[o + 2], mats[o + 3]),
			new helder.gfx.shader.Vec4(mats[o + 4], mats[o + 5], mats[o + 6], mats[o + 7]),
			new helder.gfx.shader.Vec4(mats[o + 8], mats[o + 9], mats[o + 10], mats[o + 11]),
			new helder.gfx.shader.Vec4(mats[o + 12], mats[o + 13], mats[o + 14], mats[o + 15]));
	}

	public function record(node:Node, frame:Int, m:Mat4) {
		var s = @:privateAccess node.slot;
		while (ids.length <= s) {
			ids.push(0);
			frames.push(-2);
			for (_ in 0...16)
				mats.push(0);
		}
		ids[s] = node.id();
		frames[s] = frame;
		var o = s * 16;
		for (c in 0...4) {
			var col = MathTools.col(m, c);
			mats[o + c * 4] = col.x;
			mats[o + c * 4 + 1] = col.y;
			mats[o + c * 4 + 2] = col.z;
			mats[o + c * 4 + 3] = col.w;
		}
	}
}
