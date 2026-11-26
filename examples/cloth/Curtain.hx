// title: Cloth
// summary: A sheet of cloth hanging from pins, blown by the wind: Verlet steps and a Jacobi constraint solve written once with helder.parallel, on the GPU where the device has compute stages (the points drawn straight from their buffer), else on the CPU's SIMD lanes and threads
// tags: gfx, compute, parallel, physics
// demo: canvas 640x480
import Cloth;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.math.*;
import helder.os.*;

// A cloth in a window (close it, or press Escape):
//
//   helder run examples/cloth/Curtain.hx
//
// Cloth.hx is the simulation: two kernels (Integrate, Solve) at a fixed
// step. Where the device has compute, the points' Items are drawn as the
// mesh's vertex buffer (cloth.buffer(device)), and Auto runs every step
// on the GPU, as it does what the GPU draws; elsewhere (WebGL2) the steps
// run on the CPU and the points are uploaded each frame.
@:structInit @:publicFields class CurtainVertex {
	var pos:Vec4; // xyz, w: the inverse mass
	var uv:Vec2;
}

@:structInit @:publicFields class CurtainVaryings {
	var pos:Vec4;
	var uv:Vec2;
	var depth:Float;
}

@:structInit @:publicFields class CurtainCamera {
	var mvp:Mat4;
}

// the sheet: a checker of two cloths' colours, darker away from the camera, the pins red
final CurtainShader = shader({
	vertex: function(v:CurtainVertex, p:{cam:CurtainCamera}):CurtainVaryings {
		var clip = p.cam.mvp * vec4(v.pos.xyz, 1);
		return {pos: position(clip), uv: v.uv, depth: v.pos.w == 0 ? -1 : clip.w};
	},
	fragment: function(i:CurtainVaryings):Vec4 {
		if (i.depth < 0) return vec4(0.9, 0.2, 0.15, 1);
		var c = (Std.int(floor(i.uv.x * 12)) + Std.int(floor(i.uv.y * 9))) % 2 == 0 ? vec3(0.93, 0.85, 0.7) : vec3(0.3, 0.45, 0.62);
		return vec4(c * clamp(1.6 - i.depth * 0.25, 0.35, 1), 1);
	}
});

class Curtain {
	static inline var W = 64;
	static inline var H = 48;

	final device:Device;
	final cloth = new Cloth(W, H, 0.04, 1, 7);
	final points:Buffer;
	final uvs:Buffer;
	final indices:Buffer;
	final count:Int;
	final pipeline:Pipeline;
	final camera = Bytes.alloc(64);
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0.06, 0.07, 0.09, 1)}], depth: {load: Clear}};
	// (no compute: the points' bytes, uploaded each frame)
	final upload:Null<Bytes>;
	var time = 0.0;
	var last = -1.0;

	public function new(device:Device) {
		this.device = device;
		var uv = Bytes.alloc(W * H * 8);
		for (r in 0...H)
			for (c in 0...W) {
				uv.setFloat(8 * (r * W + c), c / (W - 1));
				uv.setFloat(8 * (r * W + c) + 4, r / (H - 1));
			}
		uvs = device.createBuffer({size: uv.length, usage: Vertex, data: uv});
		var quads = (W - 1) * (H - 1), is = Bytes.alloc(quads * 6 * 4), k = 0;
		for (r in 0...H - 1)
			for (c in 0...W - 1) {
				var a = r * W + c;
				for (v in [a, a + 1, a + W + 1, a, a + W + 1, a + W]) {
					is.setInt32(k, v);
					k += 4;
				}
			}
		count = quads * 6;
		indices = device.createBuffer({size: is.length, usage: Index, data: is});
		if (device.has(Compute)) {
			points = cloth.buffer(device);
			upload = null;
		} else {
			upload = Bytes.alloc(W * H * 32);
			points = device.createBuffer({size: upload.length, usage: Vertex});
		}
		var d = CurtainShader.pipeline({depthCompare: Less, depthWrite: true});
		d.layout = [
			{stride: 32, attributes: [{location: 0, format: Float4, offset: 0}]},
			{stride: 8, attributes: [{location: 1, format: Float2, offset: 0}]}
		];
		pipeline = device.createPipeline(d);
	}

	// the cloth dt seconds on, and the frame's pass recorded; the caller ends the frame
	public function draw(enc:Encoder, dt:Float) {
		time += dt;
		cloth.wind = vec4(1.2 * Math.sin(time * 0.7), 0, 2.5 + 1.5 * Math.sin(time * 1.3), 0);
		cloth.advance(dt);
		if (upload != null) {
			for (i in 0...W * H) {
				var p = cloth.points[i].pos;
				upload.setFloat(32 * i, p.x);
				upload.setFloat(32 * i + 4, p.y);
				upload.setFloat(32 * i + 8, p.z);
				upload.setFloat(32 * i + 12, p.w);
			}
			device.writeBuffer(points, 0, upload);
		}
		var view = Mat4.perspective(Math.PI / 3, device.width / Math.max(1, device.height), 0.1, 50) * Mat4.translation(0, -0.2, -3.2)
			* Mat4.rotationX(0.35) * Mat4.rotationY(0.5);
		CurtainShader.params.cam.write({mvp: view}, camera);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, camera);
		enc.setVertexBuffer(0, points);
		enc.setVertexBuffer(1, uvs);
		enc.setIndexBuffer(indices, UInt32);
		enc.drawIndexed(count);
		enc.endPass();
	}

	public function frame() {
		var now = haxe.Timer.stamp();
		var dt = last < 0 ? Cloth.DT : now - last;
		last = now;
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc, dt);
		device.endFrame();
	}

	static function main() {
		var window = new Window({title: "Cloth", width: 640, height: 480});
		var curtain = new Curtain(Device.create(window.surface));
		Sys.println('Cloth: ${W * H} points, ' + (curtain.upload == null ? "stepped on the GPU" : "stepped on the CPU (no compute here)"));
		App.run(curtain.frame, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
