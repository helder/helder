// title: Fountain
// summary: Drops of a fountain moved by one body written in Haxe (helder.parallel's each): a compute dispatch where the GPU has compute (WebGPU, Metal, D3D11, GL ES 3.1), drawn as instances straight from its buffer; on WebGL2 the same body runs as SIMD lanes on the CPU
// tags: gfx, shaders, compute, particles, parallel
// demo: canvas 640x480
import helder.math.*;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.os.*;
import helder.parallel.Items;
import helder.parallel.Parallel;
import FountainShaders;

// A fountain of drops in a window (close it, or press Escape):
//
//   helder run examples/fountain/Fountain.hx            (natively)
//   helder build examples/fountain/Fountain.hx --target web
//
// The drops are an Items<Drop> (helder.parallel), moved each frame by one
// each(...): its body is compiled at build time into a compute stage and
// SIMD lanes alike. The drops are drawn as instances from their Items'
// buffer (drops.buffer(device)), so Auto runs the body on the GPU where the
// device has compute: the drops stay there, the CPU writes nothing a frame
// but the body's captured values. Without compute (WebGL2) it runs on the
// CPU's lanes over fewer drops, and the draw uploads them: the fallback
// path of the same program, the same body.
class Fountain {
	// (the CPU's share where there is no compute)
	static inline var GPU_DROPS = 65536;
	static inline var CPU_DROPS = 4096;

	final device:Device;
	final compute:Bool;
	final count:Int;
	final drops:Items<Drop>;
	final quad:Buffer;
	final pipeline:Pipeline;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0.02, 0.03, 0.06, 1)}]};
	var time = 0.0;
	var last = -1.0;

	public function new(device:Device) {
		this.device = device;
		compute = device.has(Compute);
		count = compute ? GPU_DROPS : CPU_DROPS;
		Parallel.device = device;
		// (every drop old and below the floor: born at the first step, spread over the first frames)
		drops = new Items<Drop>(count);
		for (i in 0...count)
			drops[i] = {pos: new Vec4(0, -2, 0, LIFE + i / count), vel: new Vec4(0, 0, 0, 0)};
		// (drawn from its buffer: from the first step on, the body runs where they are)
		drops.buffer(device);
		var s = 0.006;
		quad = device.createBuffer({size: 48, usage: Vertex, data: floats([-s, -s, s, -s, s, s, -s, -s, s, s, -s, s])});
		var d = DropShader.pipeline({blend: Additive});
		d.layout = [
			{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
			{stride: 32, step: Instance, attributes: [{location: 1, format: Float4, offset: 0}]}
		];
		pipeline = device.createPipeline(d);
	}

	public function frame() {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc);
		device.endFrame();
	}

	// the frame's step (the drops moved: on the GPU, or the CPU's lanes) and its pass; the caller ends the frame
	public function draw(enc:Encoder) {
		var now = haxe.Timer.stamp();
		var dt = last < 0 ? 1 / 60 : Math.min(now - last, 1 / 20);
		last = now;
		time += dt;
		var t = time, aspect = device.width / Math.max(1, device.height);
		var drops = this.drops;
		each(count, i -> {
			var d = drops[i];
			var age = d.pos.w + dt;
			var vel = d.vel.xyz - vec3(0, GRAVITY * dt, 0);
			var pos = d.pos.xyz + vel * dt;
			if (pos.y < -1 || age > LIFE) {
				// (born again at the nozzle, sprayed up and out; its age spread so that they do not all land at once)
				var n:Float = i;
				var a = (hash(n, t) - 0.5) * 0.9, s = 1.5 + 0.5 * hash(n + 0.5, t);
				pos = vec3(0, -0.85, 0);
				vel = vec3(sin(a) * s / aspect, cos(a) * s, 0);
				age = hash(n + 0.25, t) * 0.3;
			}
			drops[i] = {pos: vec4(pos, age), vel: vec4(vel, 0)};
		});
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, quad);
		enc.setVertexBuffer(1, drops.buffer(device));
		enc.draw(6, count);
		enc.endPass();
	}

	static function floats(xs:Array<Float>):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(4 * xs.length);
		for (i in 0...xs.length)
			b.setFloat(4 * i, xs[i]);
		return b;
	}

	static function main() {
		var window = new Window({title: "Fountain", width: 640, height: 480});
		var fountain = new Fountain(Device.create(window.surface));
		Sys.println("Fountain: " + fountain.count + " drops, " + (fountain.compute ? "moved on the GPU" : "moved on the CPU's lanes (no compute here)"));
		App.run(fountain.frame, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
