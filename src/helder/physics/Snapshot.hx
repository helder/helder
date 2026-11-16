package helder.physics;

import helder.gfx.shader.Vec3;
import helder.scene.math.Quat;

// A world's state at a step (PhysicsWorld.snapshot), put back by
// PhysicsWorld.restore: its bodies (the list, so bodies added after are
// taken out and those removed after come back, and the joints') and each
// one's position, orientation, velocities, sleep and the settings a
// program changes as it plays (rotates, friction, restitution). A step
// keeps nothing else between steps (contacts and the broad phase are made
// anew each step), so the steps after a restore give the same numbers as
// they gave the first time: a rewind, a replay, a branch. One snapshot is
// written again and again without allocating once its arrays are the
// world's size.
//   var at = physics.snapshot();
//   for (_ in 0...120) physics.step(dt);
//   physics.restore(at);    // as it was 120 steps ago
class Snapshot {
	// (per body: position 3, orientation 4, velocity 3, angular 3, friction, restitution)
	static inline var STRIDE = 15;

	public var length(default, null) = 0;

	final bodies:Array<Body> = [];
	final joints:Array<Joint> = [];
	final values:Array<Float> = [];
	// (per body: sleeping, rotates and still, packed)
	final flags:Array<Int> = [];

	public function new() {}

	@:allow(helder.physics) function write(world:PhysicsWorld) {
		var bs = world.bodies, n = bs.length;
		bodies.resize(n);
		if (values.length < n * STRIDE) values.resize(n * STRIDE);
		flags.resize(n);
		for (i in 0...n) {
			var b = bs[i], k = i * STRIDE;
			bodies[i] = b;
			var p = b.position, q = b.orientation, v = b.velocity, w = b.angular;
			values[k] = p.x;
			values[k + 1] = p.y;
			values[k + 2] = p.z;
			values[k + 3] = q.x;
			values[k + 4] = q.y;
			values[k + 5] = q.z;
			values[k + 6] = q.w;
			values[k + 7] = v.x;
			values[k + 8] = v.y;
			values[k + 9] = v.z;
			values[k + 10] = w.x;
			values[k + 11] = w.y;
			values[k + 12] = w.z;
			values[k + 13] = b.friction;
			values[k + 14] = b.restitution;
			flags[i] = (b.sleeping ? 1 : 0) | (b.rotates ? 2 : 0) | (b.still << 2);
		}
		joints.resize(world.joints.length);
		for (i in 0...world.joints.length)
			joints[i] = world.joints[i];
		length = n;
	}

	@:allow(helder.physics) function read(world:PhysicsWorld) {
		var bs = world.bodies;
		bs.resize(length);
		for (i in 0...length) {
			var b = bodies[i], k = i * STRIDE;
			bs[i] = b;
			b.position = new Vec3(values[k], values[k + 1], values[k + 2]);
			b.orientation = new Quat(values[k + 3], values[k + 4], values[k + 5], values[k + 6]);
			b.velocity = new Vec3(values[k + 7], values[k + 8], values[k + 9]);
			b.angular = new Vec3(values[k + 10], values[k + 11], values[k + 12]);
			b.friction = values[k + 13];
			b.restitution = values[k + 14];
			var f = flags[i];
			b.sleeping = f & 1 != 0;
			b.rotates = f & 2 != 0;
			b.still = f >>> 2;
			if (!b.node.isNone && b.node.valid && (!b.isStatic() || b.isKinematic)) {
				b.node.position = b.position;
				b.node.rotation = b.orientation;
			}
		}
		world.joints.resize(joints.length);
		for (i in 0...joints.length)
			world.joints[i] = joints[i];
	}
}
