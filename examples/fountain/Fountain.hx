// title: Fountain
// summary: Drops of a fountain moved by a compute stage written in Haxe (helder.gfx's compute tier: WebGPU, Metal, D3D11, GL ES 3.1), drawn as instances straight from its storage buffer; on WebGL2 the same function runs on the CPU
// tags: gfx, shaders, compute, particles
// demo: canvas 640x480
import helder.math.*;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.os.*;
import FountainShaders;

// A fountain of drops in a window (close it, or press Escape):
//
//   helder run examples/fountain/Fountain.hx            (natively)
//   helder build examples/fountain/Fountain.hx --target web
//
// Spray (FountainShaders.hx) is a compute stage: each frame one dispatch
// moves every drop in a storage buffer (BufferUsage.Storage), then one
// instanced draw reads that buffer as the drops' instance vertex buffer: the
// CPU writes nothing a frame but the step's uniform block. Where the device
// has no compute (WebGL2: Device.has(Compute) false) the same function,
// Spray.main, moves fewer drops on the CPU, and their bytes are uploaded
// with writeBuffer: the fallback path of the same program.
class Fountain {
	// (the CPU's share where there is no compute)
	static inline var GPU_DROPS = 65536;
	static inline var CPU_DROPS = 4096;

	final device:Device;
	final compute:Bool;
	final count:Int;
	final drops:Buffer;
	final quad:Buffer;
	final pipeline:Pipeline;
	final spray:Null<ComputePipeline>;
	final step = Bytes.alloc(Spray.params.step.block.size);
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0.02, 0.03, 0.06, 1)}]};
	// the step (the uniform block's value, written each frame); the CPU's
	// fallback: the drops, their bytes and the ids it calls Spray.main with
	final cpu:Array<Drop> = [];
	final cpuBytes:Null<Bytes>;
	final cpuStep:SprayStep = {dt: 0, time: 0, count: 0, aspect: 1};
	final cpuParams:{step:SprayStep, drops:RWStorage<Drop>};
	final id:ComputeInput = ComputeInput.at(0, 0, 0, 64, 1, 1);
	var time = 0.0;
	var last = -1.0;

	public function new(device:Device) {
		this.device = device;
		compute = device.has(Compute);
		count = compute ? GPU_DROPS : CPU_DROPS;
		// (every drop old and below the floor: born at the first step, spread over the first frames)
		for (i in 0...count)
			cpu.push({pos: new Vec4(0, -2, 0, LIFE + i / count), vel: new Vec4(0, 0, 0, 0)});
		var initial = Spray.params.drops.bytesOf(cpu);
		drops = device.createBuffer({size: initial.length, usage: compute ? Storage : Vertex, data: initial});
		cpuBytes = compute ? null : initial;
		cpuParams = {step: cpuStep, drops: cpu};
		if (compute) cpu.resize(0);
		var s = 0.006;
		quad = device.createBuffer({size: 48, usage: Vertex, data: floats([-s, -s, s, -s, s, s, -s, -s, s, s, -s, s])});
		var d = DropShader.pipeline({blend: Additive});
		d.layout = [
			{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
			{stride: Spray.params.drops.stride, step: Instance, attributes: [{location: 1, format: Float4, offset: 0}]}
		];
		pipeline = device.createPipeline(d);
		spray = compute ? device.createComputePipeline(Spray.pipeline()) : null;
	}

	public function frame() {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc);
		device.endFrame();
	}

	// the frame's step (the drops moved: a dispatch, or the CPU's) and its pass; the caller ends the frame
	public function draw(enc:Encoder) {
		var now = haxe.Timer.stamp();
		var dt = last < 0 ? 1 / 60 : Math.min(now - last, 1 / 20);
		last = now;
		time += dt;
		var aspect = device.width / Math.max(1, device.height);
		cpuStep.dt = dt;
		cpuStep.time = time;
		cpuStep.count = count;
		cpuStep.aspect = aspect;
		if (!compute) {
			// (Spray.main on the CPU, the drops uploaded)
			for (i in 0...count) {
				id.x = i;
				Spray.main(id, cpuParams);
			}
			Spray.params.drops.store(cpu, cpuBytes);
			device.writeBuffer(drops, 0, cpuBytes);
		}
		if (compute) {
			Spray.params.step.write(cpuStep, step);
			enc.beginCompute();
			enc.setComputePipeline(spray);
			enc.setUniforms(Spray.params.step.block.binding, step);
			enc.setStorage(Spray.params.drops.binding, drops);
			enc.dispatch(Spray.groups(count));
			enc.endCompute();
		}
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, quad);
		enc.setVertexBuffer(1, drops);
		enc.draw(6, count);
		enc.endPass();
	}

	static function floats(xs:Array<Float>):Bytes {
		var b = Bytes.alloc(4 * xs.length);
		for (i in 0...xs.length)
			b.setFloat(4 * i, xs[i]);
		return b;
	}

	static function main() {
		var window = new Window({title: "Fountain", width: 640, height: 480});
		var fountain = new Fountain(Device.create(window.surface));
		Sys.println("Fountain: " + fountain.count + " drops, " + (fountain.compute ? "moved by a compute stage" : "moved on the CPU (no compute here)"));
		App.run(fountain.frame, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
