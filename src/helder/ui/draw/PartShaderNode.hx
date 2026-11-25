package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.gfx.Device;
import helder.gfx.Encoder;
import helder.gfx.Pipeline;
import helder.gfx.Texture;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.gfx.Color;
import helder.ui.Node;
import helder.ui.controls.Eased;
import helder.ui.controls.Look;

// A part's shader (PartShader) drawn under its children: a node over the whole
// part, its texture the part's size in pixels, rendered in a pass before
// the window's (Renderer.beforePass) whenever it is painted, as an
// effect's box is (examples/fx's FxBox). A shader's parts share its
// pipeline.
@:noCompletion class PartShaderNode extends Node {
	static final pipelines = new Map<String, Pipeline>();
	static var triangle:Null<Buffer> = null;
	static var ids = 0;

	final shader:PartShader.DrawShader;
	final eased:Eased;
	final look:Look<Dynamic>;
	final bytes = Bytes.alloc(96);
	final id = -(++ids) - 3000000;
	final retired:Array<Texture> = [];
	final retiredAt:Array<Int> = [];
	var device:Null<Device> = null;
	var pipeline:Null<Pipeline> = null;
	var color:Null<Texture> = null;
	var records = 0;
	var tw = 0;
	var th = 0;
	var queued = -1;
	// (the frames it painted: what the test reads)
	public var painted(default, null) = 0;

	public function new(shader:PartShader.DrawShader, eased:Eased, look:Look<Dynamic>) {
		super("draw");
		this.shader = shader;
		this.eased = eased;
		this.look = look;
		style.position = Absolute;
		style.left = 0;
		style.top = 0;
		style.right = 0;
		style.bottom = 0;
		style.pointerEvents = None;
		var before = eased.onChange;
		eased.onChange = () -> {
			if (before != null) before();
			if (ui != null) ui.requestFrame();
		};
	}

	@:noCompletion override public function hasContent():Bool
		return true;

	function ready(d:Device) {
		device = d;
		if (triangle == null) {
			var v = shader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
			triangle = d.createBuffer({size: v.length, usage: Vertex, data: v});
		}
		var key = Type.getClassName(Type.getClass(shader));
		pipeline = pipelines.get(key);
		if (pipeline == null) {
			var desc = shader.pipeline({});
			desc.colorFormat = RGBA8;
			pipelines.set(key, pipeline = d.createPipeline(desc));
		}
	}

	@:noCompletion override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var g = Std.downcast(canvas, helder.ui.draw.TextureCanvas), r = helder.ui.draw.GpuHost.of(canvas);
		if (g == null || r == null) return helder.ui.draw.GpuPlaceholder.draw(canvas, x, y, width, height);
		if (pipeline == null) ready(r.device);
		var pw = Std.int(Math.max(1, Math.round(width * r.scale))), ph = Std.int(Math.max(1, Math.round(height * r.scale)));
		if (pw != tw || ph != th) {
			if (color != null) {
				retired.push(color);
				retiredAt.push(records);
			}
			color = device.createTexture({width: pw, height: ph, renderTarget: true});
			tw = pw;
			th = ph;
		}
		while (retired.length > 0 && records >= retiredAt[0] + 2) {
			device.destroyTexture(retired.shift());
			retiredAt.shift();
		}
		var dark = ui != null && ui.dark, t = look.tokens;
		var off = parent != null && parent.parent != null && parent.parent.attr("data-disabled") != null ? 1.0 : 0.0;
		shader.params.part.write({
			size: new Vec4(pw, ph, r.scale, helder.ui.Clock.now),
			states: new Vec4(eased.hover, eased.pressed, eased.checked, eased.focus),
			more: new Vec4(eased.open, off, 0, 0),
			accent: rgba(dark ? t.accent.dark : t.accent.light),
			fg: rgba(dark ? t.fg.dark : t.fg.light),
			surface: rgba(dark ? t.surface.dark : t.surface.light)
		}, bytes);
		if (queued != r.passKey) {
			queued = r.passKey;
			r.beforePass(record);
		}
		painted++;
		g.gpuTexture(color, id, x, y, width, height, parent == null ? 0 : parent.style.radius);
	}

	static function rgba(c:Color):Vec4
		return new Vec4(c.r / 255, c.g / 255, c.b / 255, c.a / 255);

	function record(enc:Encoder) {
		records++;
		var c = color;
		if (c == null || pipeline == null) return;
		enc.beginPass({colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0), texture: c}]});
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, triangle);
		enc.setUniforms(shader.uniforms[0].binding, bytes);
		enc.draw(3);
		enc.endPass();
	}
}
