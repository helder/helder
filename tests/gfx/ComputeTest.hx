import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.os.*;
import ComputeShaders;

// The compute tier (gfx's lanes: GL on Mesa, D3D11 on WARP, Metal; in
// Chromium on WebGPU, and on WebGL2 that it has none: compute-web.mjs),
// headless, one frame of 256x192 drawn twice:
//
//   scan       an inclusive prefix sum of 1000 Ints, Hillis and Steele's:
//              ten dispatches of Scan, each reading the last one's buffer
//              (a uniform block a dispatch), read back (readBuffer)
//   particles  128 particles moved by Move, dispatched indirectly (its
//              workgroups from a buffer), each kept one appended to a
//              storage buffer and counted (atomicAdd) into an indirect
//              draw's instances; the draw reads the kept positions as an
//              instance vertex buffer: their squares' pixels white, the
//              others' black; the count read back
//   image      a storage texture of 32x32 written by Gradient, then
//              sampled into the frame's top left: its texels' pixels
//
// The second frame allocates nothing in the GC heap from beginFrame to
// endFrame (hxmc.GcStats, the drawing thread's). Natively the results are read back here; in a
// browser WebGPU reads back asynchronously only: the program prints what
// it expects (a buffer's handle, size and FNV-1a; pixels) and the harness
// checks it. Without compute (WebGL2): Device.has says so,
// createComputePipeline and a storage buffer throw.
//
//   ComputeTest [--optional]   (exit 0: ok, 1: failed, 3: no Metal device;
//                              --optional: no compute is no failure)
class ComputeTest {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;
	static inline var N = 1000;
	static inline var COLS = 16;
	static inline var ROWS = 8;
	static inline var IMAGE = 32;

	static var failures = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failures++;
		Sys.println('ComputeTest: $what: ' + (ok ? "ok" : "FAIL" + (detail == null ? "" : ": " + detail)));
	}

	static function main() {
		var web = hxmc.Platform.os() == 3;
		var device = try Device.create(Surface.headless(WIDTH, HEIGHT)) catch (e:String) {
			if (e != "helder.gfx: no Metal device") throw e;
			Sys.println("ComputeTest: skipped: no Metal device");
			Sys.exit(3);
			null;
		}
		var name = backendName(device.backend);
		if (!device.has(Compute)) {
			var threw = try {
				device.createComputePipeline(Scan.pipeline());
				false;
			} catch (e:Dynamic) true;
			var storageThrew = try {
				device.createBuffer({size: 16, usage: Storage});
				false;
			} catch (e:Dynamic) true;
			check('no compute ($name): has(Compute), has(StorageTextures), has(Indirect) false', !device.has(StorageTextures) && !device.has(Indirect));
			check('no compute ($name): createComputePipeline throws', threw);
			check('no compute ($name): a storage buffer throws', storageThrew);
			Sys.println('ComputeTest: no compute ($name)');
			device.dispose();
			if (!Sys.args().contains("--optional") && device.backend != WebGL2) failures++;
			Sys.exit(failures == 0 ? 0 : 1);
		}
		Sys.println('ComputeTest: compute on $name');
		// ---- resources (made once)
		var scanA = device.createBuffer({size: N * 4, usage: Storage}), scanB = device.createBuffer({size: N * 4, usage: Storage});
		var input = Bytes.alloc(N * 4), expected = Bytes.alloc(N * 4), sum = 0;
		for (i in 0...N) {
			input.setInt32(4 * i, i % 7 + 1);
			sum += i % 7 + 1;
			expected.setInt32(4 * i, sum);
		}
		var count = COLS * ROWS;
		var particles:Array<Particle> = [];
		var keptCount = 0;
		for (r in 0...ROWS)
			for (c in 0...COLS) {
				var keep = (c + r) % 3 != 0;
				if (keep) keptCount++;
				var px = 8 + 16 * c, py = 72 + 16 * r;
				particles.push({pos: new Vec4(px * 2 / WIDTH - 1, 1 - py * 2 / HEIGHT, 0, keep ? 1 : 0), vel: new Vec4(4 * 2 / WIDTH, 0, 0, 0)});
			}
		var particleBytes = Move.params.particles.bytesOf(particles);
		var particleBuffer = device.createBuffer({size: particleBytes.length, usage: Storage});
		var kept = device.createBuffer({size: count * 16, usage: Storage});
		var dispatchArgs = ints([Move.groups(count), 1, 1]), drawArgs = ints([6, 0, 0, 0]);
		var groups = device.createBuffer({size: 12, usage: Indirect, data: dispatchArgs});
		var draws = device.createBuffer({size: 16, usage: Indirect});
		var image = device.createTexture({width: IMAGE, height: IMAGE, storage: true});
		var nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		var scan = device.createComputePipeline(Scan.pipeline()), move = device.createComputePipeline(Move.pipeline()),
			gradient = device.createComputePipeline(Gradient.pipeline());
		// (the dots: the quad's corners, then the kept positions as instances)
		var dx = 3 * 2 / WIDTH, dy = 3 * 2 / HEIGHT;
		var corners = floats([-dx, -dy, dx, -dy, dx, dy, -dx, -dy, dx, dy, -dx, dy]);
		var quad = device.createBuffer({size: corners.length, usage: Vertex, data: corners});
		var d = DotShader.pipeline();
		d.layout = [
			{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
			{stride: 16, step: Instance, attributes: [{location: 1, format: Float4, offset: 0}]}
		];
		var dots = device.createPipeline(d);
		var x1 = IMAGE * 2 / WIDTH - 1, y1 = 1 - IMAGE * 2 / HEIGHT;
		var imageQuad = device.createBuffer({
			size: 96,
			usage: Vertex,
			data: ImageShader.vertexBytes([
				{pos: new Vec2(-1, 1), uv: new Vec2(0, 0)}, {pos: new Vec2(x1, 1), uv: new Vec2(1, 0)}, {pos: new Vec2(x1, y1), uv: new Vec2(1, 1)},
				{pos: new Vec2(-1, 1), uv: new Vec2(0, 0)}, {pos: new Vec2(x1, y1), uv: new Vec2(1, 1)}, {pos: new Vec2(-1, y1), uv: new Vec2(0, 1)}
			])
		});
		var imagePipeline = device.createPipeline(ImageShader.pipeline());
		// (the uniform blocks' bytes, written each dispatch into the frame's ring)
		var scanSteps = [], offset = 1;
		while (offset < N) {
			var b = Bytes.alloc(Scan.params.step.block.size);
			Scan.params.step.write({offset: offset, count: N}, b);
			scanSteps.push(b);
			offset <<= 1;
		}
		var moveStep = Bytes.alloc(Move.params.step.block.size), sizeBlock = Bytes.alloc(Gradient.params.size.block.size);
		Move.params.step.write({dt: 1, count: count}, moveStep);
		Gradient.params.size.write({width: IMAGE, height: IMAGE}, sizeBlock);
		var black = new Color(0, 0, 0, 1);
		var pass:PassDesc = {colors: [{load: Clear, clear: black}]};

		function frame(enc:Encoder) {
			enc.beginCompute();
			// scan: A -> B -> A ... (ten steps: the sums in A)
			enc.setComputePipeline(scan);
			var from = scanA, to = scanB;
			for (step in scanSteps) {
				enc.setUniforms(Scan.params.step.block.binding, step);
				enc.setStorage(Scan.params.src.binding, from);
				enc.setStorage(Scan.params.dst.binding, to);
				enc.dispatch(Scan.groups(N));
				var t = from;
				from = to;
				to = t;
			}
			// the particles, their workgroups from a buffer
			enc.setComputePipeline(move);
			enc.setUniforms(Move.params.step.block.binding, moveStep);
			enc.setStorage(Move.params.particles.binding, particleBuffer);
			enc.setStorage(Move.params.kept.binding, kept);
			enc.setStorage(Move.params.args.binding, draws);
			enc.dispatchIndirect(groups);
			enc.setComputePipeline(gradient);
			enc.setUniforms(Gradient.params.size.block.binding, sizeBlock);
			enc.setStorageTexture(Gradient.params.image.binding, image);
			enc.dispatch(Gradient.groups(IMAGE), Gradient.groups(IMAGE, 1));
			enc.endCompute();
			enc.beginPass(pass);
			enc.setPipeline(imagePipeline);
			enc.setTexture(ImageShader.params.image.binding, image, nearest);
			enc.setVertexBuffer(0, imageQuad);
			enc.draw(6);
			enc.setPipeline(dots);
			enc.setVertexBuffer(0, quad);
			enc.setVertexBuffer(1, kept);
			enc.drawIndirect(draws);
			enc.endPass();
		}

		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4), allocated = 0.0;
		for (n in 0...2) {
			// (the inputs as they were: each frame the same work)
			device.writeBuffer(scanA, 0, input);
			device.writeBuffer(particleBuffer, 0, particleBytes);
			device.writeBuffer(draws, 0, drawArgs);
			// (this thread's: the CPU back end's helper threads, in their safe
			// regions, move the count of every thread's by their buffers' sizes)
			var before = hxmc.GcStats.threadBytesAllocated();
			var enc = device.beginFrame();
			frame(enc);
			allocated = hxmc.GcStats.threadBytesAllocated() - before;
			if (n == 1 && !web) device.readPixels(pixels);
			device.endFrame();
		}
		check("the second frame allocates nothing", allocated == 0, allocated + " bytes");
		// ---- the results
		var argsWant = ints([6, keptCount, 0, 0]);
		var points:Array<{x:Int, y:Int, rgb:Array<Int>}> = [];
		for (r in 0...ROWS)
			for (c in 0...COLS) {
				var v = (c + r) % 3 != 0 ? 255 : 0;
				points.push({x: 8 + 16 * c + 4, y: 72 + 16 * r, rgb: [v, v, v]});
			}
		for (p in [[0, 0], [5, 9], [31, 31], [17, 3], [30, 12]])
			points.push({x: p[0], y: p[1], rgb: [p[0] * 8, p[1] * 8, 128]});
		if (web) {
			// (the harness reads them: host.gfx.readBuffer, readPixels)
			Sys.println('ComputeTest: read scan ${scanA.id()} ${N * 4} ${fnv(expected)}');
			Sys.println('ComputeTest: read args ${draws.id()} 16 ${fnv(argsWant)}');
			for (p in points)
				Sys.println('ComputeTest: pixel ${p.x} ${p.y} ${p.rgb.join(" ")}');
		} else {
			var got = Bytes.alloc(N * 4);
			device.readBuffer(scanA, 0, got);
			var wrong = -1;
			for (i in 0...N)
				if (got.getInt32(4 * i) != expected.getInt32(4 * i) && wrong < 0) wrong = i;
			check("scan: 1000 prefix sums, ten dispatches", wrong < 0, wrong < 0 ? null : 'sum $wrong is ${got.getInt32(4 * wrong)}, not ${expected.getInt32(4 * wrong)}');
			var args = Bytes.alloc(16);
			device.readBuffer(draws, 0, args);
			check('particles: $keptCount kept, counted into the draw\'s instances', args.compare(argsWant) == 0, '[' + [for (i in 0...4) args.getInt32(4 * i)].join(", ") + "]");
			var moved = Bytes.alloc(particleBytes.length);
			device.readBuffer(particleBuffer, 0, moved);
			var p0 = Move.params.particles.load(moved, 1);
			check("particles: moved in place", Math.abs(p0.pos.x - (particles[1].pos.x + 4 * 2 / WIDTH)) < 1e-6, Std.string(p0.pos.x));
			var bad = [];
			for (p in points) {
				var o = 4 * (p.y * WIDTH + p.x);
				for (k in 0...3)
					if (Math.abs(pixels.get(o + k) - p.rgb[k]) > 2) {
						bad.push('(${p.x}, ${p.y}): ${pixels.get(o)} ${pixels.get(o + 1)} ${pixels.get(o + 2)}, not ${p.rgb.join(" ")}');
						break;
					}
			}
			check("pixels: the kept particles drawn indirectly, the storage texture sampled", bad.length == 0, bad.slice(0, 4).join("; "));
		}
		// (in a browser the harness reads the buffers and the frame after main: kept)
		if (!web) device.dispose();
		Sys.println("ComputeTest: " + (failures == 0 ? "ok" : '$failures FAILED'));
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function backendName(b:Backend):String
		return switch b {
			case GL: "GL";
			case Metal: "Metal";
			case D3D11: "D3D11";
			case WebGPU: "WebGPU";
			case WebGL2: "WebGL2";
			case Soft: "Soft";
		}

	static function ints(xs:Array<Int>):Bytes {
		var b = Bytes.alloc(4 * xs.length);
		for (i in 0...xs.length)
			b.setInt32(4 * i, xs[i]);
		return b;
	}

	static function floats(xs:Array<Float>):Bytes {
		var b = Bytes.alloc(4 * xs.length);
		for (i in 0...xs.length)
			b.setFloat(4 * i, xs[i]);
		return b;
	}

	// FNV-1a, as compute-web.mjs computes it
	static function fnv(b:Bytes):String {
		var h = 0x811c9dc5;
		for (i in 0...b.length)
			h = (h ^ b.get(i)) * 0x01000193;
		return StringTools.hex(h, 8);
	}
}
