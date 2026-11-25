package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.render.LineShader;

// Draws a world's Lines (renderer.use(new LineRenderer(device)), or
// LineRenderer.of(renderer)): each shown node's lines one instanced draw
// (LineShader: a segment an instance), the depth-tested opaque ones after
// the opaque surfaces (AfterOpaque), the see-through ones (transparent)
// after the see-through surfaces, those drawn over everything (onTop) last
// (AfterTransparent). Their points are uploaded once changed; nothing is
// allocated a frame. DebugDraw draws through it.
class LineRenderer implements RenderFeature {
	public final device:Device;
	// the last frame's draws (statistics)
	public var draws(default, null) = 0;

	final corners:Buffer;
	final indices:Buffer;
	static inline var INDICES = 6 + 6 * Lines.FAN;
	final viewBytes = Bytes.alloc(LineShader.uniforms[0].size);
	final viewBlock:LineView = {
		viewProj: Mat4.identity(), model: Mat4.identity(), viewport: new Vec4(0, 0, 0, 0), style: new Vec4(0, 0, 0, 0), dash: new Vec4(0, 0, 0, 0),
		fog: new Vec4(0, 0, 0, 0), fogShape: new Vec4(0, 0, 0, 0), eye: new Vec4(0, 0, 0, 0)
	};
	// (by segments, then onTop, then transparent: made when first drawn)
	final pipelines:Array<Null<Pipeline>> = [for (_ in 0...8) null];
	var renderer:Null<Renderer> = null;
	// what runs before the frame's lines (DebugDraw's: the helpers, its rings into its lines)
	@:allow(helder.scene.render) var before:Null<(Encoder, Renderer.FrameInfo, Renderer) -> Void> = null;
	// lines of no node, drawn in the world's frame (DebugDraw's)
	@:allow(helder.scene.render) final extras:Array<Lines> = [];

	public function new(device:Device) {
		this.device = device;
		// (the quad's four corners, then each fan's centre and arc)
		var c = Bytes.alloc((4 + 2 * (Lines.FAN + 2)) * 16), at = 0;
		function corner(piece:Float, k:Float, side:Float) {
			c.setFloat(at, piece);
			c.setFloat(at + 4, k);
			c.setFloat(at + 8, side);
			c.setFloat(at + 12, 0);
			at += 16;
		}
		corner(0, 0, -1);
		corner(0, 0, 1);
		corner(0, 1, -1);
		corner(0, 1, 1);
		for (piece in 1...3) {
			corner(piece, -1, 0);
			for (k in 0...Lines.FAN + 1)
				corner(piece, k, 0);
		}
		corners = device.createBuffer({size: c.length, usage: Vertex, data: c});
		var ib = Bytes.alloc(INDICES * 2), i = 0;
		function index(v:Int) {
			ib.setUInt16(i, v);
			i += 2;
		}
		for (v in [0, 1, 2, 2, 1, 3])
			index(v);
		for (piece in 0...2) {
			var base = 4 + piece * (Lines.FAN + 2);
			for (k in 0...Lines.FAN) {
				index(base);
				index(base + 1 + k);
				index(base + 2 + k);
			}
		}
		indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
	}

	// the renderer's line renderer, made and turned on when it has none
	public static function of(renderer:Renderer):LineRenderer {
		var l = Std.downcast(@:privateAccess renderer.lines, LineRenderer);
		if (l != null) return l;
		var made = new LineRenderer(renderer.device);
		renderer.use(made);
		return made;
	}

	public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.lines = this;
		renderer.inject(AfterOpaque, (enc, frame) -> {
			draws = 0;
			if (before != null) before(enc, frame, renderer);
			drawAll(enc, frame, 0);
		});
		renderer.inject(AfterTransparent, (enc, frame) -> {
			drawAll(enc, frame, 1);
			drawAll(enc, frame, 2);
			FrameCounts.sceneDraws += draws;
		});
	}

	// (stage 0: depth tested and opaque; 1: depth tested, see-through; 2: on top)
	function drawAll(enc:Encoder, frame:Renderer.FrameInfo, stage:Int) {
		var world = frame.world;
		if (world == null) return;
		var store = world.store(Lines.KIND);
		for (k in 0...store.length) {
			var node = store.nodeAt(k), l = store.valueAt(k);
			var s = l.onTop ? 2 : l.transparent ? 1 : 0;
			if (s != stage || !l.visible || !node.shown() || !world.inTree(node)) continue;
			draw(enc, frame, l, node.worldMatrix());
		}
		for (l in extras)
			if ((l.onTop ? 2 : l.transparent ? 1 : 0) == stage && l.visible) draw(enc, frame, l, Mat4.identity());
	}


	// lines drawn with model as their frame (inside the frame's pass: a
	// feature's own lines, not a node's)
	@:allow(helder.scene.render) function draw(enc:Encoder, frame:Renderer.FrameInfo, l:Lines, model:Mat4) {
		l.prepare();
		var n = l.drawn;
		if (n == 0) return;
		l.upload(device);
		var b = viewBlock;
		b.viewProj = frame.viewProj;
		b.model = model;
		b.viewport = new Vec4(frame.width, frame.height, frame.projection.c1.y, frame.hdr ? 1 : 0);
		b.style = new Vec4(l.width * 0.5, l.widthUnits == World ? 1 : 0, l.join == Miter ? 0 : l.join == Round ? 1 : 2, l.cap == Butt ? 0 : l.cap == Round ? 1 : 2);
		b.dash = new Vec4(l.dash > 0 ? l.dash : 0, l.gap, l.dashOffset, l.toneMapped ? 1 : 0);
		b.fog = Fog.colorOf(frame.fog);
		b.fogShape = Fog.shapeOf(frame.fog);
		b.eye = new Vec4(frame.eye.x, frame.eye.y, frame.eye.z, l.transparent || l.onTop ? 1 : 0);
		LineShader.params.view.write(b, viewBytes);
		enc.setPipeline(pipeline(l));
		enc.setUniforms(LineShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, corners);
		var r = Lines.RECORD;
		if (l.segments) {
			enc.setVertexBuffer(1, l.buffer, 0);
			enc.setVertexBuffer(2, l.buffer, 0);
			enc.setVertexBuffer(3, l.buffer, r);
			enc.setVertexBuffer(4, l.buffer, r);
		} else
			for (s in 0...4)
				enc.setVertexBuffer(1 + s, l.buffer, s * r);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(INDICES, n);
		draws++;
	}

	function pipeline(l:Lines):Pipeline {
		var k = (l.segments ? 4 : 0) + (l.onTop ? 2 : 0) + (l.transparent ? 1 : 0);
		var p = pipelines[k];
		if (p != null) return p;
		var d = LineShader.pipeline({
			cull: None,
			depthCompare: l.onTop ? Always : Less,
			depthWrite: !l.onTop && !l.transparent,
			blend: l.transparent || l.onTop ? Premultiplied : Opaque
		});
		// (the corners, then four views of the points: the one before, the
		// segment's two, the one after; segments' a pair an instance)
		var stride = l.segments ? 2 * Lines.RECORD : Lines.RECORD;
		d.layout = [
			{stride: 16, attributes: [{location: 0, format: Float4, offset: 0}]},
			{stride: stride, step: Instance, attributes: [{location: 1, format: Float4, offset: 0}]},
			{stride: stride, step: Instance, attributes: [{location: 2, format: Float4, offset: 0}, {location: 3, format: Float4, offset: 16}]},
			{stride: stride, step: Instance, attributes: [{location: 4, format: Float4, offset: 0}, {location: 5, format: Float4, offset: 16}]},
			{stride: stride, step: Instance, attributes: [{location: 6, format: Float4, offset: 0}]}
		];
		p = pipelines[k] = renderer.createPipeline(d);
		return p;
	}

	public function dispose() {
		device.destroyBuffer(corners);
		device.destroyBuffer(indices);
	}
}
