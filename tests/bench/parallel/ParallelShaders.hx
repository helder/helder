import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The prototype's one kernel (docs/design/parallel.md): a particle's step,
// written once as a compute stage. The GPU runs it through compute(); the
// CPU forms in ParallelKernels.hx are written by hand as the kernel
// compiler would emit them from this same body (scalar, 4 lanes, chunks on
// helder.jobs.Spread), over the same std430 bytes.
@:structInit @:publicFields class Particle {
	// xyz: where it is, w: carried (its age, its kind)
	var pos:Vec4;
	// xyz: its velocity, w: carried
	var vel:Vec4;
}

@:structInit @:publicFields class ParticleStep {
	var dt:Float;
	var gravity:Float;
	// the velocity kept a step (1: no drag)
	var drag:Float;
	// the share of the speed kept when it bounces off the floor (y = 0)
	var bounce:Float;
	var count:Int;
}

// v' = v * drag - (0, g dt, 0); p' = p + v' dt; below the floor: mirrored, its fall bounced
final Integrate = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:ParticleStep, particles:RWStorage<Particle>}) {
		if (id.x >= p.step.count) return;
		var q = p.particles[id.x];
		var vel = q.vel.xyz * p.step.drag - vec3(0, p.step.gravity * p.step.dt, 0);
		var pos = q.pos.xyz + vel * p.step.dt;
		if (pos.y < 0) {
			pos = vec3(pos.x, -pos.y, pos.z);
			vel = vec3(vel.x, -vel.y * p.step.bounce, vel.z);
		}
		var next:Particle = {pos: vec4(pos, q.pos.w), vel: vec4(vel, q.vel.w)};
		p.particles[id.x] = next;
	}
});
