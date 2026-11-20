// title: Murmuration
// summary: Half a million starlings wheeling over a marsh at dusk, steered on the GPU by compute stages (separation, alignment and cohesion over a hashed grid), a hawk splitting them, drawn as instances with beating wings into an HDR frame with bloom
// tags: 3d, compute, instancing, shaders, post
// demo: canvas 960x540
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;
import helder.scene.math.MathTools;
import helder.scene.render.PostProcess;
import BirdShader;
import FlockShaders;
import SkyShader;

// A murmuration at dusk (close it, or press Escape; drag to turn the
// camera, scroll to come closer):
//
//   helder run examples/murmuration
//   helder run examples/murmuration -- --birds 65536
//   helder build examples/murmuration --target web
//
// The flock takes fixed steps on the GPU (Flock: a hashed grid built
// by two dispatches, each bird steered by its neighbours in a third), then
// one pass draws the sky over the frame and every bird as an instance read
// straight from the flock's buffer, in linear light into a multisampled
// half-float target, which helder.scene's PostProcess blooms, tone maps
// and grades into the frame. Without compute (WebGL2) fewer birds are
// steered on the CPU by the same functions.
class Murmuration {
	static inline var FOV = 0.95;
	static inline var STEP = 1 / 60;

	final device:Device;
	final flock:Flock;
	final flight = new Flight();
	final post:PostProcess;
	final sky:Pipeline;
	final birds:Pipeline;
	final triangle:Buffer;
	final shape:Buffer;
	final corners:Buffer;
	final shapeIndices:Int;
	final hawk:Buffer;
	final hawkShape:Buffer;
	final hawkBytes = Bytes.alloc(48);
	final skyBytes = Bytes.alloc(SkyShader.params.view.block.size);
	final birdBytes = Bytes.alloc(BirdShader.params.view.block.size);
	final hawkView = Bytes.alloc(BirdShader.params.view.block.size);
	final mirrorView = Bytes.alloc(BirdShader.params.view.block.size);
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0)}]};
	final sun:Vec3;
	final hills:Texture;
	final weather:Texture;
	final repeatingMips:Sampler;
	final around:Sampler;
	var color:Null<Texture>;
	var resolved:Null<Texture>;
	var width = 0;
	var height = 0;
	var time = 0.0;
	var accumulated = 0.0;
	final late:Array<Float> = [];
	var paced = 0.0;
	var slow = 0;
	var settled = false;

	public function new(device:Device, all = false) {
		this.device = device;
		flight.update(0);
		flock = new Flock(device, flight.roost, flight.heading, all);
		flight.scale = sizeOf(flock.live);
		flight.update(0);
		flight.camera(0, 0);
		post = new PostProcess(device, RGBA8, true);
		post.bloom = 0.05;
		post.radius = 1.2;
		post.toneMap = Aces;
		post.saturation = 1.06;
		post.contrast = 1.04;
		post.vignette = 0.28;
		post.grain = 0.012;
		post.transparent = false;
		var el = 0.022, az = Flight.SUN;
		sun = new Vec3(Math.cos(az) * Math.cos(el), Math.sin(el), Math.sin(az) * Math.cos(el));
		hills = SkyTextures.hills(device);
		weather = SkyTextures.weather(device);
		repeatingMips = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		around = device.createSampler({filter: Linear, wrap: Repeat});
		triangle = device.createBuffer({size: 24, usage: Vertex, data: floats([-1, -1, 3, -1, -1, 3])});
		var s = shapeOf(false);
		shape = device.createBuffer({size: 4 * s.length, usage: Vertex, data: floats(s)});
		s = shapeOf(true);
		hawkShape = device.createBuffer({size: 4 * s.length, usage: Vertex, data: floats(s)});
		var is = [0, 1, 3, 0, 2, 3, 4, 6, 7, 4, 7, 5, 8, 10, 11, 8, 11, 9];
		shapeIndices = is.length;
		var ib = Bytes.alloc(2 * is.length);
		for (k in 0...is.length)
			ib.setUInt16(2 * k, is[k]);
		corners = device.createBuffer({size: ib.length, usage: Index, data: ib});
		hawk = device.createBuffer({size: 48, usage: Vertex, data: hawkBytes});
		var d = SkyShader.pipeline();
		d.colorFormat = RGBA16F;
		d.samples = 4;
		sky = device.createPipeline(d);
		var d = BirdShader.pipeline({blend: Premultiplied, cull: None});
		d.colorFormat = RGBA16F;
		d.samples = 4;
		d.layout = [
			{stride: 16, attributes: [{location: 0, format: Float4, offset: 0}]},
			{
				stride: 48,
				step: Instance,
				attributes: [
					{location: 1, format: Float4, offset: 0},
					{location: 2, format: Float4, offset: 16},
					{location: 3, format: Float4, offset: 32}
				]
			}
		];
		birds = device.createPipeline(d);
	}

	// a starling seen from above, a wingspan of 1: x, y, z, how much of the
	// beat each corner takes; the body (nose, sides, tail), then each wing
	// (its root's front and back, its elbow, its tip)
	static function shapeOf(hawk:Bool):Array<Float> {
		var out = hawk ? [0, 0, 0.24, 0, -0.068, 0, 0.04, 0, 0.068, 0, 0.04, 0, 0, 0, -0.31, 0]
			: [0, 0, 0.26, 0, -0.055, 0, 0.04, 0, 0.055, 0, 0.04, 0, 0, 0, -0.27, 0];
		var wing = hawk ? [[0.045, 0, 0.115, 0], [0.045, 0, -0.11, 0], [0.28, 0, 0.09, 0.5], [0.5, 0, -0.035, 1]]
			: [[0.04, 0, 0.1, 0], [0.04, 0, -0.07, 0], [0.25, 0, 0.06, 0.55], [0.5, 0, -0.11, 1]];
		for (side in [-1.0, 1.0])
			for (c in wing) {
				out.push(c[0] * side);
				for (k in 1...4)
					out.push(c[k]);
			}
		return out;
	}

	function resize(w:Int, h:Int) {
		if (w == width && h == height) return;
		if (color != null) device.destroyTexture(color);
		if (resolved != null) device.destroyTexture(resolved);
		width = w;
		height = h;
		color = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true, samples: 4});
		resolved = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		post.base = h >= 1300 ? 2 : 1;
	}

	// (the birds' number by how the frames keep up: each half second doubled
	// while they come on time, halved for good when twice they did not; a
	// display faster than 60 Hz judged as one of 60)
	public function pace(delta:Float, period:Float) {
		late.push(delta / Math.max(period, 1 / 60));
		paced += delta;
		if (paced < 0.5) return;
		late.sort(Reflect.compare);
		var median = late[late.length >> 1];
		late.resize(0);
		paced = 0;
		slow = median > 1.6 ? slow + 1 : 0;
		if (slow >= 2 && flock.shrink()) {
			settled = true;
			slow = 0;
		} else if (!settled && median < 1.25) flock.grow();
	}

	static function sizeOf(live:Int):Float
		return Math.pow(live / Flock.GPU_BIRDS, 1 / 3);

	public function frame(dt:Float) {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc, dt);
		device.endFrame();
	}

	function advance(enc:Encoder) {
		time += STEP;
		flight.scale += (sizeOf(flock.live) - flight.scale) * STEP * 0.5;
		flight.update(time);
		var st = flock.step;
		st.roost = new Vec4(flight.roost.x, flight.roost.y, flight.roost.z, flight.radius);
		st.heading = new Vec4(flight.heading.x, flight.heading.y, flight.heading.z, flight.flat);
		st.armA = new Vec4(flight.armA.x, flight.armA.y, flight.armA.z, 0);
		st.armB = new Vec4(flight.armB.x, flight.armB.y, flight.armB.z, 0);
		st.hawk = new Vec4(flight.hawk.x, flight.hawk.y, flight.hawk.z, flight.reach);
		st.hawkVel = new Vec4(flight.hawkVel.x, flight.hawkVel.y, flight.hawkVel.z, 0);
		flock.advance(enc, STEP, time);
	}

	public function draw(enc:Encoder, dt:Float) {
		accumulated += Math.min(dt, 3 * STEP);
		var steps = 0;
		while (steps < 3 && accumulated + 1e-9 >= STEP) {
			accumulated = Math.max(0, accumulated - STEP);
			advance(enc);
			steps++;
		}
		if (steps > 0 && !flock.compute) flock.upload();
		flight.camera(time, Math.min(dt, 3 * STEP));
		resize(device.width, device.height);
		// (out of the dark at the start: while a fast GPU's flock grows to its whole)
		post.exposure = 0.8 * smoothstep(0.0, 2.0, time);
		var aspect = width / Math.max(1, height);
		var view = MathTools.lookAt(flight.eye, flight.target, new Vec3(0, 1, 0));
		var proj = Mat4.perspective(FOV, aspect, 0.5, 8000);
		var f = normalize(flight.target - flight.eye);
		var r = normalize(cross(f, new Vec3(0, 1, 0)));
		var u = cross(r, f);
		var ty = Math.tan(FOV / 2), tx = ty * aspect;
		SkyShader.params.view.write({
			right: new Vec4(r.x * tx, r.y * tx, r.z * tx, 0),
			up: new Vec4(u.x * ty, u.y * ty, u.z * ty, 2 * ty / height),
			forward: new Vec4(f.x, f.y, f.z, 0),
			eye: new Vec4(flight.eye.x, flight.eye.y, flight.eye.z, time),
			sun: new Vec4(sun.x, sun.y, sun.z, 0)
		}, skyBytes);
		var focal = height / 2 / ty;
		var bv:BirdView = {
			viewProj: proj * view,
			eye: new Vec4(flight.eye.x, flight.eye.y, flight.eye.z, focal),
			sun: new Vec4(sun.x, sun.y, sun.z, 0),
			size: new Vec4(0.55, 1.2, 1, 1)
		};
		BirdShader.params.view.write(bv, birdBytes);
		// (a quarter of them in the water, twice the size: as dark, blurred by the ripples anyway)
		bv.size = new Vec4(1.1, 2.4, -1, 0.55);
		BirdShader.params.view.write(bv, mirrorView);
		bv.size = new Vec4(2.2, 1.2, 1, 1);
		BirdShader.params.view.write(bv, hawkView);
		// (the hawk an instance of its own: where, its wings' phase, its way, beating hard)
		var at = flight.hawk, hv = flight.hawkVel;
		hawkBytes.setFloat(0, at.x);
		hawkBytes.setFloat(4, at.y);
		hawkBytes.setFloat(8, at.z);
		hawkBytes.setFloat(12, time * 11 % (Math.PI * 2));
		hawkBytes.setFloat(16, hv.x);
		hawkBytes.setFloat(20, hv.y);
		hawkBytes.setFloat(24, hv.z);
		hawkBytes.setFloat(36, 1.35);
		device.writeBuffer(hawk, 0, hawkBytes);

		pass.colors[0].texture = color;
		pass.colors[0].resolve = resolved;
		enc.beginPass(pass);
		enc.setPipeline(sky);
		enc.setUniforms(SkyShader.params.view.block.binding, skyBytes);
		enc.setTexture(SkyShader.params.hills.binding, hills, around);
		enc.setTexture(SkyShader.params.weather.binding, weather, repeatingMips);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.setPipeline(birds);
		enc.setUniforms(BirdShader.params.view.block.binding, birdBytes);
		enc.setVertexBuffer(0, shape);
		enc.setIndexBuffer(corners, UInt16);
		enc.setVertexBuffer(1, flock.current());
		enc.drawIndexed(shapeIndices, flock.live);
		enc.setUniforms(BirdShader.params.view.block.binding, mirrorView);
		enc.drawIndexed(shapeIndices, flock.live >> 2);
		if (flight.reach > 0) {
			enc.setUniforms(BirdShader.params.view.block.binding, hawkView);
			enc.setVertexBuffer(0, hawkShape);
			enc.setVertexBuffer(1, hawk);
			enc.drawIndexed(shapeIndices, 1);
		}
		enc.endPass();
		post.run(enc, resolved, null, width, height, time);
	}

	static function floats(xs:Array<Float>):Bytes {
		var b = Bytes.alloc(4 * xs.length);
		for (i in 0...xs.length)
			b.setFloat(4 * i, xs[i]);
		return b;
	}

	// --bench [w h]: frames drawn offscreen as fast as the GPU goes, timed
	static function bench(w:Int, h:Int) {
		var device = Device.create(Surface.headless(w, h));
		var m = new Murmuration(device, true), pixels = Bytes.alloc(w * h * 4);
		function run(n:Int) {
			for (_ in 0...n - 1)
				m.frame(1 / 60);
			// (the last frame read back: every frame before it done)
			var enc = device.beginFrame();
			m.draw(enc, 1 / 60);
			device.readPixels(pixels);
			device.endFrame();
		}
		run(120);
		var start = Sys.time(), n = 600;
		run(n);
		Sys.println('Murmuration: ${m.flock.count} birds at ${w}x${h}: ${Math.round((Sys.time() - start) / n * 100000) / 100} ms a frame');
	}

	static function main() {
		var args = Sys.args(), b = args.indexOf("--bench");
		if (b >= 0) return bench(Std.parseInt(args[b + 1] ?? "1920") ?? 1920, Std.parseInt(args[b + 2] ?? "1080") ?? 1080);
		var window = new Window("Murmuration", 1280, 720);
		var m = new Murmuration(Device.create(window.surface));
		// (--birds n: at most n fly, as helder.build's landing asks)
		var cap = args.indexOf("--birds");
		if (cap >= 0) m.flock.limit = Std.parseInt(args[cap + 1] ?? "") ?? m.flock.limit;
		while (m.flock.live > m.flock.limit && m.flock.shrink()) {}
		Sys.println('Murmuration: up to ${m.flock.count} birds, ' + (m.flock.compute ? "steered by a compute stage" : "steered on the CPU (no compute here)"));
		var pressed = false, lastX = 0.0, lastY = 0.0, told = 0;
		App.run(() -> {
			m.pace(App.frame.delta, App.frame.period);
			m.frame(App.frame.delta);
			if (m.flock.live != told) Sys.println('Murmuration: ${told = m.flock.live} birds');
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case PointerDown:
				pressed = true;
				lastX = e.x;
				lastY = e.y;
			case PointerMove if (pressed):
				m.flight.turnBy((e.x - lastX) / window.scale, (e.y - lastY) / window.scale);
				lastX = e.x;
				lastY = e.y;
			case PointerUp | PointerCancel: pressed = false;
			case Scroll: m.flight.zoomBy(e.deltaY);
			case _:
		});
	}
}
