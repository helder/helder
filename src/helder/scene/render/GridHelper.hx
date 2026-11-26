package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Mat4;
import helder.math.Vec4;
import helder.scene.Node;
import helder.scene.math.MathTools;
import helder.scene.render.GridShader;

// An infinite grid on its node's xz plane (a studio's viewport, an editor's
// floor: GridShader, not lines): cells of size / divisions (the node's
// units), a major line every tenth, the x axis red and the z axis blue,
// each line a pixel wide however far, fading out at fade (size * 3 by
// default) from the eye. Drawn by DebugDraw (its pipeline made on its
// renderer when first drawn), blended over the scene, depth tested.
//
//   GridHelper.attach(world.node("grid"), {size: 10, divisions: 10});
class GridHelper extends Helper {
	public var size:Float;
	public var divisions:Int;
	public var fade:Float;
	// the cells' lines' colour and the major ones' (linear, alpha their opacity)
	public var color:Vec4;
	public var majorColor:Vec4;

	final viewBytes = Bytes.alloc(GridShader.uniforms[0].size);
	final viewBlock:GridView = {
		viewProj: Mat4.identity(), model: Mat4.identity(), eye: new Vec4(0, 0, 0, 0), grid: new Vec4(0, 0, 0, 0), centre: new Vec4(0, 0, 0, 0),
		minor: new Vec4(0, 0, 0, 0), major: new Vec4(0, 0, 0, 0)
	};
	// (made on the renderer it is first drawn by, with the quad)
	var pipeline:Null<Pipeline> = null;
	var on:Null<Renderer> = null;
	var quad:Buffer = Buffer.NONE;
	var indices:Buffer = Buffer.NONE;

	public function new(?options:GridOptions) {
		super();
		size = options?.size ?? 10.0;
		divisions = options?.divisions ?? 10;
		fade = options?.fade ?? size * 3;
		color = options?.color ?? new Vec4(0.5, 0.5, 0.5, 0.55);
		majorColor = options?.majorColor ?? new Vec4(0.75, 0.75, 0.75, 0.8);
	}

	public static function attach(node:Node, ?options:GridOptions):GridHelper
		return Helper.add(node, new GridHelper(options));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		if (on != renderer) make(renderer);
		var m = node.worldMatrix(), inv = MathTools.inverse(m);
		var e = MathTools.transformPoint(inv, frame.eye);
		// (the node's scale along its plane: its units into the world's)
		var sx = Math.sqrt(m.c0.x * m.c0.x + m.c0.y * m.c0.y + m.c0.z * m.c0.z);
		var b = viewBlock;
		b.viewProj = frame.viewProj;
		b.model = m;
		b.eye = new Vec4(frame.eye.x, frame.eye.y, frame.eye.z, frame.hdr ? 1 : 0);
		b.grid = new Vec4(size / Math.max(1, divisions), 10, fade, 2 / Math.max(1e-6, frame.projection.c1.y * frame.height));
		b.centre = new Vec4(e.x, e.z, sx, 0);
		b.minor = color;
		b.major = majorColor;
		GridShader.params.view.write(b, viewBytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(GridShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, quad);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(6, 1);
	}

	function make(renderer:Renderer) {
		on = renderer;
		var device = renderer.device;
		var d = GridShader.pipeline({cull: None, depthCompare: Less, depthWrite: false, blend: Alpha});
		d.layout = [{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]}];
		pipeline = renderer.createPipeline(d);
		if (quad == Buffer.NONE) {
			var q = Bytes.alloc(32);
			var c = [-1.0, -1, 1, -1, 1, 1, -1, 1];
			for (k in 0...8)
				q.setFloat(4 * k, c[k]);
			quad = device.createBuffer({size: 32, usage: Vertex, data: q});
			var ib = Bytes.alloc(12);
			var idx = [0, 1, 2, 0, 2, 3];
			for (k in 0...6)
				ib.setUInt16(2 * k, idx[k]);
			indices = device.createBuffer({size: 12, usage: Index, data: ib});
		}
	}
}

// a GridHelper's (each optional): 10 wide in 10 cells, fading at 30
typedef GridOptions = {
	?size:Float,
	?divisions:Int,
	?fade:Float,
	?color:Vec4,
	?majorColor:Vec4
}
