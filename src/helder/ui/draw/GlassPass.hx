package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.ui.Color;
import helder.ui.draw.GlassShader;

// Liquid Glass drawn (helder.ui.Glass's, a GlassGroup's: GlassShader): its
// backdrop handed to the canvas where it paints (Backdrop), its passes
// recorded after it (GpuHost.beforePass: blurred along x, then y, then the
// glass), the glass's texture drawn in its place (TextureCanvas.gpuTexture),
// over its box and its shadow's margin. Its look in points, tuned against
// the system's (tests/ui/GlassTest.hx: macOS 26's NSGlassEffectView).
class GlassPass {
	// the look, regular and clear: the blur's sigma, the rim's displacement,
	// the bevel's width, the rim light's width and strength, the frost, the
	// saturation, the brightness, the clear glass's blur share, the shadow's
	// alpha, blur and offset, the light's dark-side share (points, shares)
	public static var regular = [12.7, 27.5, 39.4, 1.5, 0.35, 0.53, 2.06, 0.97, 1, 0.12, 6, 2, 0.6];
	public static var clear = [26.4, 30.9, 21, 1.5, 0.35, 0.21, 1.3, 1.06, 0.18, 0.08, 6, 2, 0.6];

	static final pipelines = new haxe.ds.ObjectMap<Device, Array<Pipeline>>();
	static final triangles = new haxe.ds.ObjectMap<Device, Buffer>();
	static var ids = 0;

	public final backdrop = new Backdrop();
	final id = -(++ids) - 5000000;
	final blurBytes = [Bytes.alloc(32), Bytes.alloc(32)];
	final bytes = Bytes.alloc(GLASS_BYTES);
	final retired:Array<Texture> = [];
	final retiredAt:Array<Int> = [];
	var device:Null<Device> = null;
	var out:Null<Texture> = null;
	var blurA:Null<Texture> = null;
	var blurB:Null<Texture> = null;
	var bw = 0;
	var bh = 0;
	var ow = 0;
	var oh = 0;
	var records = 0;
	var queued = -1;
	// (the shapes as painted, in the canvas's coordinates: x, y, w, h, radius each)
	var shapes:Array<Float> = [];
	var look:Array<Float> = regular;
	var spacing = 0.0;
	var dark = false;
	var tint:Color = 0;
	var press = 0.0;
	var pointerX = 0.0;
	var pointerY = 0.0;

	static inline var GLASS_BYTES = 9 * 16 + 16 * 16;
	static inline var MAX = 8;

	public function new() {}

	// the glass's shapes (x, y, w, h, radius each, in the canvas's coordinates;
	// at most 8) drawn on canvas: false where it has no GPU (drawn plainly)
	public function draw(canvas:helder.ui.Canvas, shapes:Array<Float>, clear:Bool, tint:Null<Color>, dark:Bool, spacing:Float, press:Float, pointerX:Float,
			pointerY:Float):Bool {
		var g = Std.downcast(canvas, TextureCanvas), r = GpuHost.of(canvas);
		if (g == null || r == null || shapes.length == 0) return false;
		if (device != r.device) ready(r.device);
		this.shapes = shapes;
		look = clear ? GlassPass.clear : regular;
		this.dark = dark;
		this.tint = tint ?? 0;
		this.spacing = spacing;
		this.press = press;
		this.pointerX = pointerX;
		this.pointerY = pointerY;
		var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, i = 0;
		while (i < shapes.length) {
			x0 = Math.min(x0, shapes[i]);
			y0 = Math.min(y0, shapes[i + 1]);
			x1 = Math.max(x1, shapes[i] + shapes[i + 2]);
			y1 = Math.max(y1, shapes[i + 1] + shapes[i + 3]);
			i += 5;
		}
		if (x1 <= x0 || y1 <= y0) return true;
		// (what it reads: its box and the lens's and the blur's reach; what it draws: its box and its shadow's)
		var reach = look[0] * 3 + look[1] + 2, m = look[10] * 2 + look[11] + 2, s = r.scale;
		backdrop.set(x0 - reach, y0 - reach, x1 - x0 + 2 * reach, y1 - y0 + 2 * reach);
		var pw = Std.int(Math.max(1, Math.ceil((x1 - x0 + 2 * m) * s))), ph = Std.int(Math.max(1, Math.ceil((y1 - y0 + 2 * m) * s)));
		if (pw != ow || ph != oh) {
			if (out != null) retire(out);
			out = device.createTexture({width: pw, height: ph, renderTarget: true});
			ow = pw;
			oh = ph;
		}
		while (retired.length > 0 && records >= retiredAt[0] + 2) {
			device.destroyTexture(retired.shift());
			retiredAt.shift();
		}
		g.pass(backdrop);
		var ox = x0 - m, oy = y0 - m;
		// (recorded where it was painted: a display list kept still runs it again)
		r.beforePass(enc -> record(enc, ox, oy));
		g.gpuTexture(out, id, ox, oy, pw / s, ph / s);
		return true;
	}

	function retire(t:Texture) {
		retired.push(t);
		retiredAt.push(records);
	}

	function ready(d:Device) {
		device = d;
		var p = pipelines.get(d);
		if (p == null) {
			var b = GlassBlur.pipeline({}), q = GlassShader.pipeline({});
			b.colorFormat = q.colorFormat = RGBA8;
			pipelines.set(d, p = [d.createPipeline(b), d.createPipeline(q)]);
		}
		if (!triangles.exists(d)) {
			var v = GlassShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
			triangles.set(d, d.createBuffer({size: v.length, usage: Vertex, data: v}));
			samplers.set(d, d.createSampler({filter: Linear, wrap: Clamp}));
		}
	}

	static final samplers = new haxe.ds.ObjectMap<Device, Sampler>();

	// (the passes, once the backdrop is captured: its blur, then the glass;
	// ox, oy: the target's top left in the canvas's coordinates)
	function record(enc:Encoder, ox:Float, oy:Float) {
		records++;
		var b = backdrop, t = b.texture, o = out, d = device;
		if (t == null || o == null || d == null) return;
		var p = pipelines.get(d), sampler = samplers.get(d), triangle = triangles.get(d), s = b.scale, k = look;
		// (frame pixels from the canvas's coordinates, where the backdrop was captured)
		inline function fx(x:Float)
			return b.fx + (x - b.x) * s;
		inline function fy(y:Float)
			return b.fy + (y - b.y) * s;
		// (blurred at a half or a quarter of its size: sigma in those texels, 8 at most)
		var sigma = k[0] * s, f = sigma > 16 ? 4 : 2;
		var w = Std.int(Math.max(1, Math.ceil(b.pw / f))), h = Std.int(Math.max(1, Math.ceil(b.ph / f)));
		if (blurA == null || w > bw || h > bh) {
			if (blurA != null) {
				retire(blurA);
				retire(blurB);
			}
			bw = Math.ceil(w / 32) * 32;
			bh = Math.ceil(h / 32) * 32;
			blurA = d.createTexture({width: bw, height: bh, renderTarget: true});
			blurB = d.createTexture({width: bw, height: bh, renderTarget: true});
		}
		var bs = Math.min(sigma / f, 8);
		GlassBlur.params.blur.write({map: new Vec4(0, 0, bw * f / b.tw, bh * f / b.th), step: new Vec4(f / b.tw, 0, bs, 0)}, blurBytes[0]);
		GlassBlur.params.blur.write({map: new Vec4(0, 0, 1, 1), step: new Vec4(0, 1 / bh, bs, 0)}, blurBytes[1]);
		for (j in 0...2) {
			enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0, 0), texture: j == 0 ? blurA : blurB}]});
			enc.setPipeline(p[0]);
			enc.setVertexBuffer(0, triangle);
			enc.setUniforms(GlassBlur.params.blur.block.binding, blurBytes[j]);
			enc.setTexture(GlassBlur.params.source.binding, j == 0 ? t : blurA, sampler);
			enc.draw(3);
			enc.endPass();
		}
		var rects = [], radii = [], i = 0, sh = shapes;
		while (i < sh.length && rects.length < MAX) {
			rects.push(new Vec4(fx(sh[i]), fy(sh[i + 1]), fx(sh[i] + sh[i + 2]), fy(sh[i + 1] + sh[i + 3])));
			radii.push(new Vec4(sh[i + 4] * s, 0, 0, 0));
			i += 5;
		}
		var c = tint;
		GlassShader.params.glass.write({
			out: new Vec4(fx(ox), fy(oy), ow, oh),
			capture: new Vec4(b.px, b.py, b.tw, b.th),
			blurred: new Vec4(f, f, bw, bh),
			shape: new Vec4(rects.length, Math.max(spacing * s, 0.001), look == GlassPass.clear ? 1 : 0, dark ? 1 : 0),
			tint: new Vec4(c.r / 255, c.g / 255, c.b / 255, c.a / 255),
			lens: new Vec4(k[1] * s, k[2] * s, k[3] * s, k[4]),
			tone: new Vec4(k[5], k[6], k[7], k[8]),
			shadow: new Vec4(k[9], k[10] * s, k[11] * s, k[12]),
			press: new Vec4(fx(pointerX), fy(pointerY), press, 40 * s),
			rects: rects,
			radii: radii
		}, bytes);
		enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0, 0), texture: o}]});
		enc.setPipeline(p[1]);
		enc.setVertexBuffer(0, triangle);
		enc.setUniforms(GlassShader.params.glass.block.binding, bytes);
		enc.setTexture(GlassShader.params.backdrop.binding, t, sampler);
		enc.setTexture(GlassShader.params.blurred.binding, blurB, sampler);
		enc.draw(3);
		enc.endPass();
	}
}
