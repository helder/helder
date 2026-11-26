package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.parallel.Items;
import helder.parallel.On;
import helder.parallel.Parallel;
import helder.scene.math.MathTools;
import helder.scene.render.GpuParticleShader;
import helder.scene.render.ParticleShader;

// Simulated particles (renderer.use(new Particles(capacity))), beside the
// closed-form GpuParticles: a ring of capacity particles (an Items, the
// oldest written over when it is full), each step moved by one
// helder.parallel each over the ring: gravity, drag, a floor to bounce on
// (floor, bounce), spheres to collide with (spheres: xyz the centre, w the
// radius), ages and deaths. emit puts a particle among the step's births (a
// small Items of their own: the ring itself is never written on the CPU, so
// where the GPU draws it the GPU moves it, and only the births are
// uploaded). Drawn from the ring's buffer as instances at AfterOpaque
// (ParticleShader, GpuParticles' quads, streaks and fades), without a copy
// where a dispatch moved them. On a device without compute (WebGL2) the
// same step runs on the CPU's lanes and the ring is uploaded each frame;
// on the CPU's forms the same steps give the same numbers everywhere. On
// Metal the births are the buffer's own memory (shared): the first emit
// after a step waits for that step's dispatch, which reads them.
//
//   var sparks = new Particles(65536);
//   renderer.use(sparks);
//   sparks.spheres[0] = new Vec4(0, 1, 0, 0.5);
//   sparks.emit(x, y, z, vx, vy, vz, 2, 1.2, 0.5, 1, 0.03, 0.01, 1.5, 0.02, 1);
//   sparks.step(dt);                // each fixed step
@:structInit @:publicFields class SimParticle {
	// xyz: where it is, w: its birth (seconds)
	var start:Vec4;
	// xyz: its velocity, w: its life (seconds)
	var velocity:Vec4;
	// linear colour, w: opacity
	var color:Vec4;
	// x: the first size, y: the last, z: stretch (seconds of its path), w: heat
	var shape:Vec4;
}

class Particles implements RenderFeature {
	public static inline var STRIDE = 64;

	public final capacity:Int;
	// the particles: the ring, each moved by step
	public final items:Items<SimParticle>;
	// the clock, in seconds (step moves it)
	public var time = 0.0;
	// how fast the particles slow (per second: their speed times e^(-drag t))
	public var drag = 0.0;
	public var gravity = new Vec3(0, -9.81, 0);
	// a floor at y = floor (none: -Infinity), what share of its fall a particle keeps bouncing off it
	public var floor = Math.NEGATIVE_INFINITY;
	public var bounce = 0.4;
	// the spheres the particles collide with (xyz: the centre, w: the radius; a radius of 0: none)
	public final spheres:Items<Vec4>;
	public var visible = true;
	// where the step runs (helder.parallel's On: Auto, on the GPU where it draws them)
	public var on:On = Auto;
	// the births a step takes at most (emit drops the rest: dropped)
	public final burst:Int;
	public var dropped(default, null) = 0;

	final births:Items<SimParticle>;
	var born = 0;
	var next = 0;
	var device:Null<Device> = null;
	var pipeline:Pipeline = cast 0;
	var quad:Null<Buffer> = null;
	var indices:Null<Buffer> = null;
	final viewBytes = Bytes.alloc(ParticleShader.uniforms[0].size);
	final viewBlock:GpuParticleView = {viewProj: helder.math.Mat4.identity(), right: new Vec4(0, 0, 0, 0), up: new Vec4(0, 0, 0, 0), forward: new Vec4(0, 0, 0, 0), gravity: new Vec4(0, 0, 0, 0), fog: new Vec4(0, 0, 0, 0), fogShape: new Vec4(0, 0, 0, 0), eye: new Vec4(0, 0, 0, 0)};

	static final LAYOUT:Array<VertexBufferLayout> = [
		{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
		{
			stride: STRIDE,
			step: Instance,
			attributes: [
				{location: 1, format: Float4, offset: 0}, {location: 2, format: Float4, offset: 16}, {location: 3, format: Float4, offset: 32},
				{location: 4, format: Float4, offset: 48}
			]
		}
	];

	public function new(capacity = 4096, burst = 1024, sphereCount = 8) {
		this.capacity = capacity;
		this.burst = burst;
		items = new Items<SimParticle>(capacity);
		// (every slot born never: a birth far in the future draws and moves nothing)
		for (k in 0...capacity)
			items[k] = {start: vec4(0, 0, 0, 1e9), velocity: vec4(0, 0, 0, 0), color: vec4(0), shape: vec4(0)};
		births = new Items<SimParticle>(burst);
		spheres = new Items<Vec4>(sphereCount);
	}

	public function attach(renderer:Renderer) {
		device = renderer.device;
		if (Parallel.device == null) Parallel.device = renderer.device;
		var d = ParticleShader.pipeline({blend: Premultiplied, depthCompare: Less, depthWrite: false});
		d.layout = LAYOUT;
		pipeline = renderer.createPipeline(d);
		var q = Bytes.alloc(32);
		var c = [-1.0, -1, 1, -1, 1, 1, -1, 1];
		for (k in 0...8)
			q.setFloat(4 * k, c[k]);
		quad = renderer.device.createBuffer({size: 32, usage: Vertex, data: q});
		var ib = Bytes.alloc(12);
		var idx = [0, 1, 2, 0, 2, 3];
		for (k in 0...6)
			ib.setUInt16(2 * k, idx[k]);
		indices = renderer.device.createBuffer({size: 12, usage: Index, data: ib});
		// (drawn from: from the first step on, the step runs where the ring is)
		items.buffer(renderer.device);
		renderer.inject(AfterOpaque, (enc, frame) -> draw(enc, frame));
	}

	// a particle at x, y, z moving at vx, vy, vz (units a second), of a
	// linear colour r, g, b and opacity a, its size (half its side) from
	// size0 to size1 over life seconds; stretch: drawn as a streak of that
	// many seconds of its path; heat: whiter and brighter while young (0 to
	// 1); born at the next step (delay seconds after it)
	public function emit(x:Float, y:Float, z:Float, vx:Float, vy:Float, vz:Float, r:Float, g:Float, b:Float, a:Float, size0:Float, size1:Float,
			life:Float, stretch = 0.0, heat = 0.0, delay = 0.0) {
		if (born >= burst || born >= capacity) {
			dropped++;
			return;
		}
		births[born++] = {
			start: vec4(x, y, z, time + delay),
			velocity: vec4(vx, vy, vz, life),
			color: vec4(r, g, b, a),
			shape: vec4(size0, size1, stretch, heat)
		};
	}

	// the births since the last step
	public var pending(get, never):Int;

	inline function get_pending()
		return born;

	// dt seconds: the births taken into the ring, every particle alive moved
	public function step(dt:Float) {
		time += dt;
		var ps = items, bs = births, sp = spheres;
		var cap = capacity, from = next, n = born, count = spheres.length;
		var now = time, damp = Math.exp(-drag * dt), g = gravity, ground = floor, keep = bounce;
		each(cap, i -> {
			var k = i - from;
			if (k < 0) k += cap;
			var q = ps[i];
			if (k < n) q = bs[k];
			var start = q.start, vel = q.velocity;
			var age = now - start.w;
			if (age >= 0 && age < vel.w) {
				var v = vel.xyz * damp + g * dt;
				var p = start.xyz + v * dt;
				if (p.y < ground) {
					p = vec3(p.x, ground + (ground - p.y) * keep, p.z);
					v = vec3(v.x, -v.y * keep, v.z);
				}
				var s = 0;
				while (s < count) {
					var c = sp[s];
					var d = p - c.xyz;
					var l = length(d);
					if (l < c.w && l > 0.00001) {
						var normal = d / l;
						p = c.xyz + normal * c.w;
						var into = dot(v, normal);
						if (into < 0) v = v - normal * (into * (1 + keep));
					}
					s++;
				}
				q = {start: vec4(p, start.w), velocity: vec4(v, vel.w), color: q.color, shape: q.shape};
			}
			ps[i] = q;
		}, on);
		next = (next + born) % capacity;
		born = 0;
	}

	function draw(enc:Encoder, frame:Renderer.FrameInfo) {
		if (!visible || frame.camera == null || device == null) return;
		var m = frame.camera.node.worldMatrix();
		var right = MathTools.transformDir(m, new Vec3(1, 0, 0)), up = MathTools.transformDir(m, new Vec3(0, 1, 0)),
			forward = MathTools.transformDir(m, new Vec3(0, 0, -1));
		var b = viewBlock;
		b.viewProj = frame.viewProj;
		b.right = new Vec4(right.x, right.y, right.z, frame.hdr ? 1 : 0);
		b.up = new Vec4(up.x, up.y, up.z, time);
		b.forward = new Vec4(forward.x, forward.y, forward.z, drag);
		b.fog = Fog.colorOf(frame.fog);
		b.fogShape = Fog.shapeOf(frame.fog);
		b.eye = new Vec4(frame.eye.x, frame.eye.y, frame.eye.z, 1);
		ParticleShader.params.view.write(b, viewBytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(ParticleShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, quad);
		enc.setIndexBuffer(indices, UInt16);
		enc.setVertexBuffer(1, items.buffer(device));
		enc.drawIndexed(6, capacity);
	}

	public function dispose() {
		items.dispose();
		births.dispose();
		spheres.dispose();
		if (device != null) {
			device.destroyBuffer(quad);
			device.destroyBuffer(indices);
		}
	}
}
