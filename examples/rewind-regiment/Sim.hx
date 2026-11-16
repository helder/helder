import Levels.Level;
import Levels.PropDef;
import Levels.SquadDef;
import helder.gfx.shader.Vec3;
import helder.physics.*;
import helder.scene.math.Quat;

// The battle, and nothing drawn: a level's squads and props on helder.physics,
// stepped at 60 Hz, a function of the level and the player's orders alone
// (deterministic: the same steps give the same numbers on every target).
// What the physics does not keep (hit points, cooldowns, targets, orders,
// pellets, bombs, the helicopters' flight, the props' state) lives in the
// arrays below; a keyframe of both every KEY steps lets the timeline go back
// to any step (the keyframe before it, stepped on). An order given in the
// past drops the orders after it; the run before is kept as the ghost.
//
// Units: grunts (melee), riflemen (pellets at range, the only ones that hit
// helicopters), tin tanks (slow, heavy, ram), jeeps (fast, ram) and
// helicopters (fly, drop bombs). Props (each side's hurt only the other
// side, the jack-in-the-box everyone about it): a marble on books (rolled at a
// point), dominoes (tipped: fall in turn), a wind-up train (started: runs
// its rails), a jack-in-the-box (pops), a tower of blocks (pushed at a
// point) and a ruler catapult (an eraser flung at a point). What a prop
// sets moving fast knocks over the other side's soldiers it meets.
class Sim {
	public static inline var KEY = 10;
	public static inline var END = 60 * 36;
	public static inline var PROP = 100;
	public static inline var G = 9.81;

	// the kinds
	public static inline var GRUNT = 0;
	public static inline var RIFLE = 1;
	public static inline var TANK = 2;
	public static inline var JEEP = 3;
	public static inline var HELI = 4;
	public static inline var BAZOOKA = 5;
	public static inline var ROBOT = 6;
	public static inline var KINDS = 7;

	// the props
	public static inline var MARBLE = 0;
	public static inline var DOMINO = 1;
	public static inline var TRAIN = 2;
	public static inline var JACK = 3;
	public static inline var TOWER = 4;
	public static inline var CATAPULT = 5;
	public static inline var TOP = 6;

	// per kind: hit points, speed, melee reach (centre to centre), cooldown and its spread, damage, spacing
	public static final HP = [2, 1, 14, 3, 3, 1, 7];
	public static final SPEED = [1.1, 0.85, 0.5, 2.6, 1.25, 0.7, 0.6];
	public static final REACH = [0.46, 0.42, 0.66, 0.44, 0.0, 0.42, 0.62];
	public static final COOL = [34, 85, 40, 14, 150, 210, 55];
	public static final SPREAD = [28, 30, 12, 6, 30, 50, 20];
	public static final DAMAGE = [1, 1, 2, 2, 0, 1, 2];
	public static final GAP = [0.32, 0.36, 0.95, 0.62, 0.9, 0.42, 0.7];
	// (a bazooka's reach: its rockets arc over the lines)
	public static inline var LOB = 4.4;
	public static inline var RANGE = 3.4;
	public static inline var ALT = 1.45;
	public static inline var R = 0.11;
	public static inline var HALF = 0.1;

	public final level:Level;
	public final physics = new PhysicsWorld();

	// ---- squads
	public final sqTeam:Array<Int> = [];
	public final sqKind:Array<Int> = [];
	public final sqSize:Array<Int> = [];

	// ---- units
	public final bodies:Array<Body> = [];
	public final kind:Array<Int> = [];
	public final team:Array<Int> = [];
	public final squad:Array<Int> = [];
	// (the state: in keyframes)
	public final hp:Array<Int> = [];
	final cool:Array<Int> = [];
	public final alive:Array<Bool> = [];
	final target:Array<Int> = [];
	public final ordered:Array<Bool> = [];
	public final tx:Array<Float> = [];
	public final tz:Array<Float> = [];
	final until:Array<Int> = [];
	public final fell:Array<Int> = [];
	public final yaw:Array<Float> = [];
	// (a helicopter's place while it flies: it is in the physics only once shot down)
	public final hx:Array<Float> = [];
	public final hz:Array<Float> = [];
	// (looks only: a hit's flash, a shot's recoil)
	public final flash:Array<Int> = [];
	public final fired:Array<Int> = [];

	// ---- pellets and bombs (in keyframes)
	public static inline var PELLETS = 96;
	public final pAlive:Array<Bool> = [for (_ in 0...PELLETS) false];
	public final pTeam:Array<Int> = [for (_ in 0...PELLETS) 0];
	// (0 a pellet, 1 a rocket: arcs, bursts where it lands)
	public final pKind:Array<Int> = [for (_ in 0...PELLETS) 0];
	public final pX:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	public final pY:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	public final pZ:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	final pVX:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	final pVY:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	final pVZ:Array<Float> = [for (_ in 0...PELLETS) 0.0];
	final pLife:Array<Int> = [for (_ in 0...PELLETS) 0];
	public static inline var BOMBS = 16;
	public final bAlive:Array<Bool> = [for (_ in 0...BOMBS) false];
	final bTeam:Array<Int> = [for (_ in 0...BOMBS) 0];
	public final bX:Array<Float> = [for (_ in 0...BOMBS) 0.0];
	public final bY:Array<Float> = [for (_ in 0...BOMBS) 0.0];
	public final bZ:Array<Float> = [for (_ in 0...BOMBS) 0.0];
	final bVY:Array<Float> = [for (_ in 0...BOMBS) 0.0];
	// (looks only: where bombs and props went off lately, for the puffs)
	public final blasts:Array<Blast> = [];

	// ---- props
	public final props:Array<Prop> = [];

	var seed = 7;
	public var step = 0;
	public var ended = -1;
	// (the step the recorded run ends, -1: not yet; kept across seeks)
	public var runEnd = -1;

	// ---- orders and the timeline
	public final orders:Array<Order> = [];
	final keys:Array<Keyframe> = [];
	public final ahead:Array<Float> = [];
	public final ghost:Array<Float> = [];
	public var ghostEnd = -1;
	public var before:Null<Outcome> = null;
	public var recorded = 0;
	public var started = false;

	public function new(level:Level) {
		this.level = level;
		physics.iterations = 8;
		physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		for (w in [[5.35, 0, 0.12, 8], [-5.35, 0, 0.12, 8], [0, 7.75, 5.5, 0.12], [0, -7.75, 5.5, 0.12]])
			solid(new Vec3(w[0], 0.25, w[1]), new Vec3(w[2], 0.25, w[3]), Quat.identity());
		for (d in level.props)
			prop(d);
		for (s in level.blue)
			squadOf(0, s);
		for (s in level.red)
			squadOf(1, s);
		for (i in 0...bodies.length)
			if (kind[i] == HELI) {
				hx[i] = bodies[i].position.x;
				hz[i] = bodies[i].position.z;
			}
	}

	function solid(at:Vec3, half:Vec3, q:Quat):Body {
		var b = new Body(Box(half), at, 0);
		b.orientation = q;
		b.friction = 0.6;
		return physics.add(b);
	}

	inline function rand():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// ---- setting up

	function squadOf(t:Int, d:SquadDef) {
		var s = sqTeam.length, k = d.kind;
		sqTeam.push(t);
		sqKind.push(k);
		sqSize.push(d.rows * d.cols);
		var gap = GAP[k];
		for (r in 0...d.rows)
			for (c in 0...d.cols)
				unit(t, s, k, d.x + (c - (d.cols - 1) / 2) * gap, d.z + (r - (d.rows - 1) / 2) * gap);
	}

	function unit(t:Int, s:Int, k:Int, x:Float, z:Float) {
		var face = t == 0 ? Math.PI : 0.0;
		var b = switch k {
			case TANK: new Body(Box(new Vec3(0.27, 0.15, 0.36)), new Vec3(x, 0.15, z), 9);
			case JEEP: new Body(Box(new Vec3(0.16, 0.1, 0.27)), new Vec3(x, 0.1, z), 3);
			case ROBOT: new Body(Box(new Vec3(0.18, 0.3, 0.14)), new Vec3(x, 0.3, z), 5);
			case HELI: new Body(Box(new Vec3(0.16, 0.12, 0.38)), new Vec3(x, ALT, z), 2);
			case _: new Body(Capsule(R, HALF), new Vec3(x, R + HALF, z), 1);
		}
		b.rotates = false;
		b.friction = k == JEEP ? 0.2 : 0.5;
		b.restitution = 0.05;
		b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), face);
		// (a helicopter joins the physics when it falls)
		if (k != HELI) physics.add(b);
		bodies.push(b);
		kind.push(k);
		team.push(t);
		squad.push(s);
		hp.push(HP[k]);
		cool.push(Std.int(rand() * 30) + (k == HELI ? 60 : 0));
		alive.push(true);
		target.push(-1);
		ordered.push(false);
		tx.push(0);
		tz.push(0);
		until.push(0);
		fell.push(-1);
		yaw.push(face);
		hx.push(x);
		hz.push(z);
		flash.push(0);
		fired.push(-100);
	}

	function prop(d:PropDef) {
		var p = new Prop(props.length, d);
		props.push(p);
		var dx = Math.sin(d.angle), dz = Math.cos(d.angle);
		var face = Quat.axisAngle(new Vec3(0, 1, 0), d.angle);
		switch d.type {
			case MARBLE:
				// (a stack of books, a ramp down from it along the prop's direction, the marble on top)
				p.fixed.push(solid(new Vec3(d.x, 0.45, d.z), new Vec3(0.7, 0.45, 0.7), face));
				var tilt = Math.atan2(0.9, 2.2);
				var q = face * Quat.axisAngle(new Vec3(1, 0, 0), tilt);
				p.fixed.push(solid(new Vec3(d.x + dx * 1.75, 0.45, d.z + dz * 1.75), new Vec3(0.6, 0.04, 1.2), q));
				var m = new Body(Sphere(0.42), new Vec3(d.x, 0.9 + 0.42, d.z), 30);
				m.restitution = 0.2;
				m.friction = 0.5;
				p.live.push(physics.add(m));
			case DOMINO:
				// (standing pieces: kinematic, so they stand; each tips in turn, posed by the step)
				for (k in 0...d.count) {
					var a = p.along(k * 0.42);
					var b = Body.kinematic(Box(new Vec3(0.17, 0.32, 0.05)), new Vec3(a.x, 0.32, a.z));
					b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), a.h);
					p.live.push(physics.add(b));
				}
			case TRAIN:
				// (the engine and two cars on rails from x, z along the direction, length long)
				for (k in 0...3) {
					var a = p.along(-k * 0.7);
					var b = Body.kinematic(Box(new Vec3(0.2, 0.2, 0.3)), new Vec3(a.x, 0.2, a.z));
					b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), a.h);
					p.live.push(physics.add(b));
				}
			case JACK:
				p.fixed.push(solid(new Vec3(d.x, 0.3, d.z), new Vec3(0.3, 0.3, 0.3), face));
			case TOWER:
				// (blocks stacked: held still until pushed, then dynamic)
				for (k in 0...d.count) {
					var at = new Vec3(d.x + (k % 2 == 0 ? 0 : 0.03), 0.2 + k * 0.4, d.z);
					var rest = Body.kinematic(Box(new Vec3(0.2, 0.2, 0.2)), at);
					rest.orientation = Quat.axisAngle(new Vec3(0, 1, 0), d.angle + k * 0.35);
					p.rest.push(physics.add(rest));
					var b = new Body(Box(new Vec3(0.2, 0.2, 0.2)), at, 2.5);
					b.orientation = rest.orientation;
					b.restitution = 0.15;
					b.friction = 0.6;
					p.live.push(b);
					p.restPos.push(at);
					p.restRot.push(b.orientation);
				}
			case TOP:
				// (a spinning top: set going at a point, it wanders there, then topples)
				var b = Body.kinematic(Sphere(0.24), new Vec3(d.x, 0.26, d.z));
				p.live.push(physics.add(b));
			case CATAPULT:
				// (the ruler on its pencil; the eraser on the ruler's end, flung when fired)
				p.fixed.push(solid(new Vec3(d.x, 0.06, d.z), new Vec3(0.08, 0.06, 0.5), face));
				var at = new Vec3(d.x - dx * 0.55, 0.3, d.z - dz * 0.55);
				var rest = Body.kinematic(Box(new Vec3(0.16, 0.1, 0.1)), at);
				rest.orientation = face;
				p.rest.push(physics.add(rest));
				var e = new Body(Box(new Vec3(0.16, 0.1, 0.1)), at, 1.5);
				e.orientation = face;
				e.restitution = 0.3;
				p.live.push(e);
				p.restPos.push(at);
				p.restRot.push(face);
		}
	}

	// ---- deploying (before the battle): a blue squad moved, its middle to x, z on blue's side
	public function place(s:Int, x:Float, z:Float) {
		var gx = Math.max(-4.6, Math.min(4.6, x)), gz = Math.max(1.2, Math.min(6.9, z));
		var m = middle(s);
		for (i in 0...bodies.length)
			if (squad[i] == s) {
				var q = bodies[i].position;
				bodies[i].position = new Vec3(q.x + gx - m.x, q.y, q.z + gz - m.z);
				hx[i] = bodies[i].position.x;
				hz[i] = bodies[i].position.z;
			}
	}

	public function start() {
		started = true;
		step = 0;
		keys.resize(0);
		ahead.resize(0);
		keys.push(keyframe(new Keyframe()));
		ahead.push(lead());
		recorded = 0;
		ended = -1;
		runEnd = -1;
	}

	// ---- one step

	public function simulate() {
		for (o in orders)
			if (o.step == step) apply(o);
		for (p in props)
			if (p.def.team == 1 && p.def.at == step) fire(p, p.def.tx, p.def.tz);
		var n = bodies.length;
		for (i in 0...n)
			if (alive[i]) think(i);
		pellets();
		bombs();
		for (p in props)
			propStep(p);
		for (i in 0...n)
			if (fell[i] >= 0 && step - fell[i] == 90) physics.remove(bodies[i]);
		physics.step(1 / 60);
		// (helicopters in flight: placed by hand, out of the physics)
		for (i in 0...n)
			if (kind[i] == HELI && alive[i]) {
				var bob = Math.sin((step + i * 17) * 0.05) * 0.06;
				bodies[i].position = new Vec3(hx[i], ALT + bob, hz[i]);
				bodies[i].orientation = Quat.axisAngle(new Vec3(0, 1, 0), yaw[i]);
			}
		step++;
		// (a side gone: the battle's end three quarters of a second on, what falls left to settle)
		if (ended < 0 && (count(0) == 0 || count(1) == 0 || step >= END)) {
			ended = step >= END ? step : step + 45;
			runEnd = ended;
		}
		if (step % KEY == 0) {
			var k = Std.int(step / KEY);
			if (k < keys.length) keyframe(keys[k]) else keys.push(keyframe(new Keyframe()));
			if (k < ahead.length) ahead[k] = lead() else ahead.push(lead());
		}
		if (step > recorded) recorded = step;
	}

	// a unit's step: its target, where it goes, what it does there
	function think(i:Int) {
		var k = kind[i], b = bodies[i], p = b.position;
		var px = k == HELI ? hx[i] : p.x, pz = k == HELI ? hz[i] : p.z;
		if ((step + i) % 15 == 0 || target[i] < 0 || !alive[target[i]]) target[i] = nearest(i);
		var t = target[i];
		var dx = 0.0, dz = 0.0, speed = SPEED[k], d2 = 1e9;
		if (t >= 0) {
			var q = place3(t);
			d2 = (q.x - px) * (q.x - px) + (q.z - pz) * (q.z - pz);
		}
		var engaged = t >= 0 && d2 < 0.8 * 0.8;
		if (ordered[i] && !(engaged && k != HELI)) {
			dx = tx[i] - px;
			dz = tz[i] - pz;
			speed *= k == TANK ? 1.2 : 1.4;
			if (dx * dx + dz * dz < 0.45 * 0.45 || step >= until[i]) ordered[i] = false;
		} else if (t >= 0) {
			var q = place3(t);
			dx = q.x - px;
			dz = q.z - pz;
		}
		var l = Math.sqrt(dx * dx + dz * dz);
		var wx = l > 0.001 ? dx / l * speed : 0.0, wz = l > 0.001 ? dz / l * speed : 0.0;
		if (cool[i] > 0) cool[i]--;
		if (t >= 0 && !ordered[i]) switch k {
			case RIFLE:
				// (in range: stand and shoot; close: a jab)
				if (d2 < RANGE * RANGE) {
					wx = wz = 0;
					if (cool[i] <= 0) {
						if (d2 < REACH[k] * REACH[k]) hit(i, t, 1) else shoot(i, t);
						cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
					}
				}
			case BAZOOKA:
				// (in reach: kneel and fire a rocket over the lines; close: a jab)
				if (d2 < LOB * LOB) {
					wx = wz = 0;
					if (cool[i] <= 0) {
						if (d2 < REACH[k] * REACH[k]) hit(i, t, 1) else rocket(i, t);
						cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
					}
				}
			case HELI:
				// (over the target: hover and bomb)
				if (d2 < 0.35 * 0.35) wx = wz = 0;
				if (cool[i] <= 0 && d2 < 0.9 * 0.9) {
					bomb(i);
					cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
				}
			case JEEP:
				// (rams: whoever it touches, knocked, at its cooldown; it never stops)
				if (cool[i] <= 0) for (j in 0...bodies.length)
					if (alive[j] && team[j] != team[i] && kind[j] != HELI && dist2(i, j) < REACH[k] * REACH[k]) {
						hit(i, j, DAMAGE[k]);
						cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
						break;
					}
			case ROBOT:
				// (it swings both arms round: everyone of the other side in reach, at its cooldown)
				if (d2 < REACH[k] * REACH[k]) {
					wx *= 0.2;
					wz *= 0.2;
				}
				if (cool[i] <= 0 && d2 < REACH[k] * REACH[k]) {
					for (j in 0...bodies.length)
						if (alive[j] && team[j] != team[i] && kind[j] != HELI && dist2(i, j) < REACH[k] * REACH[k]) hit(i, j, DAMAGE[k]);
					cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
				}
			case TANK:
				if (d2 < (REACH[k] + 0.25) * (REACH[k] + 0.25)) {
					wx *= 0.3;
					wz *= 0.3;
				}
				if (cool[i] <= 0) for (j in 0...bodies.length)
					if (alive[j] && team[j] != team[i] && kind[j] != HELI && dist2(i, j) < REACH[k] * REACH[k]) {
						hit(i, j, DAMAGE[k]);
						cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
					}
			case _:
				if (d2 < REACH[k] * REACH[k]) {
					wx = wz = 0;
					if (cool[i] <= 0) {
						hit(i, t, DAMAGE[k]);
						cool[i] = COOL[k] + Std.int(rand() * SPREAD[k]);
					}
				}
		}
		// (turned towards where it goes, eased; tanks and jeeps steer)
		if (wx * wx + wz * wz > 0.01 || (t >= 0 && k != JEEP)) {
			var want = wx * wx + wz * wz > 0.01 ? Math.atan2(wx, wz) : Math.atan2(dx, dz);
			var dy = want - yaw[i];
			while (dy > Math.PI)
				dy -= 2 * Math.PI;
			while (dy < -Math.PI)
				dy += 2 * Math.PI;
			yaw[i] += dy * (k == TANK ? 0.05 : k == JEEP ? 0.12 : k == ROBOT ? 0.08 : 0.2);
		}
		if (k == HELI) {
			hx[i] += wx / 60;
			hz[i] += wz / 60;
			hx[i] = Math.max(-5, Math.min(5, hx[i]));
			hz[i] = Math.max(-7.4, Math.min(7.4, hz[i]));
			return;
		}
		if (k == JEEP || k == TANK) {
			// (drives along its heading)
			var s = Math.sqrt(wx * wx + wz * wz);
			wx = Math.sin(yaw[i]) * s;
			wz = Math.cos(yaw[i]) * s;
		}
		b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), yaw[i]);
		var v = b.velocity, ease = k == JEEP ? 0.1 : k == TANK ? 0.15 : 0.25;
		b.velocity = new Vec3(v.x + (wx - v.x) * ease, v.y, v.z + (wz - v.z) * ease);
		if (b.sleeping && l > 0.05) b.wake();
	}

	// where a unit is (a helicopter's flight)
	inline function place3(j:Int):Vec3
		return kind[j] == HELI && alive[j] ? new Vec3(hx[j], ALT, hz[j]) : bodies[j].position;

	function hit(i:Int, t:Int, damage:Int) {
		var p = place3(i), q = place3(t);
		var dx = q.x - p.x, dz = q.z - p.z, l = Math.sqrt(dx * dx + dz * dz) + 1e-6;
		hp[t] -= damage;
		flash[t] = 8;
		fired[i] = step;
		var push = kind[i] == TANK || kind[i] == JEEP || kind[i] == ROBOT ? 2.2 : 1.4;
		if (hp[t] <= 0) fall(t, new Vec3(dx / l * push, 0.9, dz / l * push)) else if (kind[t] != HELI)
			bodies[t].applyImpulse(new Vec3(dx / l * 0.5 * push, 0, dz / l * 0.5 * push));
	}

	// knocked over: no longer standing, given its push at its top; a helicopter falls into the physics
	public function fall(i:Int, j:Vec3) {
		if (!alive[i]) return;
		alive[i] = false;
		ordered[i] = false;
		fell[i] = step;
		flash[i] = 8;
		var b = bodies[i];
		b.rotates = true;
		if (kind[i] == HELI) {
			b.position = new Vec3(hx[i], ALT, hz[i]);
			b.velocity = new Vec3(j.x * 0.4, 0.5, j.z * 0.4);
			b.angular = new Vec3(0, 6, 1.5);
			physics.add(b);
			return;
		}
		var m = b.mass;
		b.applyImpulse(j * (0.6 * m));
		b.applyImpulse(j * (0.4 * m), b.position + new Vec3(0, kind[i] == TANK ? 0.2 : kind[i] == ROBOT ? 0.35 : HALF + R, 0));
	}

	function nearest(i:Int):Int {
		var best = -1, bd = 1e30, me = team[i], k = kind[i];
		var p = place3(i);
		// (only riflemen shoot at helicopters; helicopters hunt what is on the ground)
		var air = k == RIFLE;
		for (j in 0...bodies.length) {
			if (!alive[j] || team[j] == me) continue;
			if (kind[j] == HELI && !air) continue;
			var q = place3(j), d = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z);
			// (riflemen favour helicopters a little)
			if (kind[j] == HELI) d *= 0.6;
			if (d < bd) {
				bd = d;
				best = j;
			}
		}
		return best;
	}

	inline function dist2(i:Int, j:Int):Float {
		var p = place3(i), q = place3(j);
		return (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z);
	}

	public inline function pVelocity(k:Int):Vec3
		return new Vec3(pVX[k], pVY[k], pVZ[k]);

	// ---- pellets: straight, fast, the first of the other side they pass hit
	function shoot(i:Int, t:Int) {
		var slot = -1;
		for (k in 0...PELLETS)
			if (!pAlive[k]) {
				slot = k;
				break;
			}
		if (slot < 0) return;
		fired[i] = step;
		var p = bodies[i].position, q = place3(t);
		var y0 = 0.3, y1 = kind[t] == HELI ? ALT : 0.22;
		var dx = q.x - p.x, dy = y1 - y0, dz = q.z - p.z, l = Math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6;
		// (a little wide now and then)
		var spread = (rand() - 0.5) * 0.2;
		pAlive[slot] = true;
		pTeam[slot] = team[i];
		pX[slot] = p.x + dx / l * 0.2;
		pY[slot] = y0;
		pZ[slot] = p.z + dz / l * 0.2;
		var v = 7.5;
		pVX[slot] = (dx / l + spread * dz / l) * v;
		pVY[slot] = dy / l * v;
		pVZ[slot] = (dz / l - spread * dx / l) * v;
		pLife[slot] = 50;
		pKind[slot] = 0;
	}

	// a rocket from a bazooka: an arc to land where the target stands, a little off
	function rocket(i:Int, t:Int) {
		var slot = -1;
		for (k in 0...PELLETS)
			if (!pAlive[k]) {
				slot = k;
				break;
			}
		if (slot < 0) return;
		fired[i] = step;
		var p = bodies[i].position, q = place3(t);
		var ox = (rand() - 0.5) * 0.5, oz = (rand() - 0.5) * 0.5;
		var dx = q.x + ox - p.x, dz = q.z + oz - p.z;
		var d = Math.sqrt(dx * dx + dz * dz), time = 0.45 + d / 6;
		pAlive[slot] = true;
		pKind[slot] = 1;
		pTeam[slot] = team[i];
		pX[slot] = p.x;
		pY[slot] = 0.35;
		pZ[slot] = p.z;
		pVX[slot] = dx / time;
		pVY[slot] = (-0.35 + 0.5 * G * time * time) / time;
		pVZ[slot] = dz / time;
		pLife[slot] = 400;
	}

	function pellets() {
		for (k in 0...PELLETS) {
			if (!pAlive[k]) continue;
			if (pKind[k] == 1) pVY[k] -= G / 60;
			pX[k] += pVX[k] / 60;
			pY[k] += pVY[k] / 60;
			pZ[k] += pVZ[k] / 60;
			if (pKind[k] == 1) {
				if (pY[k] <= 0.05 || --pLife[k] <= 0) {
					pAlive[k] = false;
					blast(pX[k], pZ[k], 0.5, pTeam[k], 4);
				}
				continue;
			}
			if (--pLife[k] <= 0 || pY[k] < 0) {
				pAlive[k] = false;
				continue;
			}
			for (j in 0...bodies.length) {
				if (!alive[j] || team[j] == pTeam[k]) continue;
				var q = place3(j), dx = q.x - pX[k], dz = q.z - pZ[k];
				var flying = kind[j] == HELI, r = flying ? 0.32 : kind[j] == TANK ? 0.34 : kind[j] == JEEP || kind[j] == ROBOT ? 0.24 : 0.15;
				var dy = flying ? pY[k] - ALT : pY[k] - 0.25;
				if (dx * dx + dz * dz < r * r && Math.abs(dy) < (flying ? 0.3 : 0.3)) {
					hp[j]--;
					flash[j] = 8;
					var l = Math.sqrt(pVX[k] * pVX[k] + pVZ[k] * pVZ[k]) + 1e-6;
					if (hp[j] <= 0) fall(j, new Vec3(pVX[k] / l * 1.1, 0.7, pVZ[k] / l * 1.1)) else if (!flying)
						bodies[j].applyImpulse(new Vec3(pVX[k] / l * 0.3, 0, pVZ[k] / l * 0.3));
					pAlive[k] = false;
					break;
				}
			}
		}
	}

	// ---- bombs: dropped, falling, knocking over the other side's soldiers about where they land
	function bomb(i:Int) {
		for (k in 0...BOMBS)
			if (!bAlive[k]) {
				bAlive[k] = true;
				bTeam[k] = team[i];
				bX[k] = hx[i];
				bY[k] = ALT - 0.2;
				bZ[k] = hz[i];
				bVY[k] = 0;
				fired[i] = step;
				return;
			}
	}

	function bombs() {
		for (k in 0...BOMBS) {
			if (!bAlive[k]) continue;
			bVY[k] -= G / 60;
			bY[k] += bVY[k] / 60;
			if (bY[k] > 0.08) continue;
			bAlive[k] = false;
			blast(bX[k], bZ[k], 0.8, bTeam[k], 1);
		}
	}

	// everyone of the other side (team -1: of both) within radius of x, z knocked over, outwards
	function blast(x:Float, z:Float, radius:Float, of:Int, kindOf:Int) {
		blasts.push({x: x, z: z, radius: radius, step: step, kind: kindOf});
		for (j in 0...bodies.length) {
			if (!alive[j] || team[j] == of || kind[j] == HELI) continue;
			var q = bodies[j].position, dx = q.x - x, dz = q.z - z, d = Math.sqrt(dx * dx + dz * dz);
			if (d > radius) continue;
			var l = d + 1e-6;
			if (kind[j] == TANK) {
				hp[j] -= 4;
				flash[j] = 8;
				if (hp[j] > 0) continue;
			}
			fall(j, new Vec3(dx / l * 2.2, 2.0, dz / l * 2.2));
		}
	}

	// ---- props

	public function fire(p:Prop, x:Float, z:Float) {
		if (p.firedAt >= 0) return;
		p.firedAt = step;
		p.tx = x;
		p.tz = z;
		var d = p.def, dx = Math.sin(d.angle), dz = Math.cos(d.angle);
		switch d.type {
			case MARBLE:
				var m = p.live[0], ax = x - m.position.x, az = z - m.position.z, l = Math.sqrt(ax * ax + az * az) + 1e-6;
				var v = d.team == 1 ? 3.4 : 6.0;
				if (d.team == 1) {
					ax = dx;
					az = dz;
					l = 1;
				}
				m.velocity = new Vec3(ax / l * v, 0, az / l * v);
				m.wake();
			case JACK:
				blast(d.x, d.z, 1.7, -1, 2);
			case TOP:
				var b = p.live[0], ax = x - b.position.x, az = z - b.position.z, l = Math.sqrt(ax * ax + az * az) + 1e-6;
				b.velocity = new Vec3(ax / l * 2.4, 0, az / l * 2.4);
			case TOWER, CATAPULT:
				for (b in p.rest)
					physics.remove(b);
				var k = 0;
				for (b in p.live) {
					// (from where it rested: a rewind may have left it where it flew)
					b.position = p.restPos[k];
					b.orientation = p.restRot[k];
					b.angular = new Vec3(0, 0, 0);
					b.rotates = true;
					b.wake();
					physics.add(b);
					var ax = x - b.position.x, az = z - b.position.z, l = Math.sqrt(ax * ax + az * az) + 1e-6;
					if (d.type == CATAPULT) {
						// (flung to land at x, z in 0.9 s)
						var t = 0.9;
						b.velocity = new Vec3(ax / t, (0 - b.position.y + 0.5 * G * t * t) / t, az / t);
						b.angular = new Vec3(8, 3, 0);
					} else {
						var v = 3.0 + k * 0.35;
						b.velocity = new Vec3(ax / l * v, 1.0 + k * 0.2, az / l * v);
						b.angular = new Vec3(az / l * 4, 0, -ax / l * 4);
					}
					k++;
				}
			case _:
		}
	}

	function propStep(p:Prop) {
		var d = p.def;
		if (p.firedAt < 0) return;
		var since = step - p.firedAt;
		switch d.type {
			case MARBLE:
				hazard(p.live[0], 0.42 + 0.26, 0.8, d.team);
			case DOMINO:
				// (each tips 7 steps after the one before, down over 14 steps, about its front foot)
				for (k in 0...p.live.length) {
					var t = (since - k * 7) / 14;
					if (t <= 0) continue;
					var at = p.along(k * 0.42), h = at.h, dx = Math.sin(h), dz = Math.cos(h);
					var a = Math.min(1, t * t) * (Math.PI / 2 - 0.12);
					var b = p.live[k];
					var foot = new Vec3(at.x + dx * 0.05, 0, at.z + dz * 0.05);
					var up = new Vec3(dx * Math.sin(a), Math.cos(a), dz * Math.sin(a));
					b.position = new Vec3(foot.x + up.x * 0.32 - dx * 0.05 * Math.cos(a), up.y * 0.32 + 0.05 * Math.sin(a), foot.z + up.z * 0.32 - dz * 0.05 * Math.cos(a));
					b.orientation = Quat.axisAngle(new Vec3(dz, 0, -dx), a) * Quat.axisAngle(new Vec3(0, 1, 0), h);
					// (landing: whoever is where it lands)
					if (t >= 0.75 && t - 1 / 14 < 0.75) {
						var lx = foot.x + dx * 0.5, lz = foot.z + dz * 0.5;
						knockAt(lx, lz, 0.6, dx * 1.6, dz * 1.6, d.team);
					}
				}
			case TRAIN:
				// (along its track: the engine since * 2.6 / 60 on, the cars behind it)
				var run = Math.min(d.length, (since + 1) * 2.6 / 60), moving = (since + 1) * 2.6 / 60 < d.length;
				for (k in 0...p.live.length) {
					var a = p.along(run - k * 0.7), b = p.live[k], dx = Math.sin(a.h), dz = Math.cos(a.h);
					b.position = new Vec3(a.x, 0.2, a.z);
					b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), a.h);
					b.velocity = moving ? new Vec3(dx * 2.6, 0, dz * 2.6) : new Vec3(0, 0, 0);
					if (moving) knockAt(a.x, a.z, 0.55, dx * 2.4, dz * 2.4, d.team);
				}
			case TOP:
				var b = p.live[0];
				if (since >= 60 * 4) {
					b.velocity = new Vec3(0, 0, 0);
				} else {
					// (its path curls as it wobbles, its knocks all round it)
					var v = b.velocity, a = Math.sin(since * 0.09) * 0.035;
					b.velocity = new Vec3(v.x * Math.cos(a) - v.z * Math.sin(a), 0, v.x * Math.sin(a) + v.z * Math.cos(a));
					var w = b.position;
					if (Math.abs(w.x) > 4.9 && w.x * b.velocity.x > 0) b.velocity = new Vec3(-b.velocity.x, 0, b.velocity.z);
					if (Math.abs(w.z) > 7.3 && w.z * b.velocity.z > 0) b.velocity = new Vec3(b.velocity.x, 0, -b.velocity.z);
					var vv = b.velocity, l = Math.sqrt(vv.x * vv.x + vv.z * vv.z) + 1e-6;
					knockAt(w.x, w.z, 0.5, vv.x / l * 2.2, vv.z / l * 2.2, d.team);
				}
			case TOWER:
				for (b in p.live)
					hazard(b, 0.5, 1.2, d.team);
			case CATAPULT:
				var e = p.live[0];
				if (!p.landed && since > 10 && e.position.y < 0.25) {
					p.landed = true;
					blast(e.position.x, e.position.z, 1.1, d.team, 3);
				}
				if (!p.landed) hazard(e, 0.3, 2.0, d.team);
			case _:
		}
	}

	// a prop's body moving faster than speed knocks over who it meets
	function hazard(b:Body, reach:Float, speed:Float, of:Int) {
		var v = b.velocity;
		if (v.x * v.x + v.z * v.z + v.y * v.y < speed * speed) return;
		var p = b.position;
		for (j in 0...bodies.length) {
			if (!alive[j] || kind[j] == HELI || team[j] == of) continue;
			var q = bodies[j].position, dx = q.x - p.x, dz = q.z - p.z;
			var r = reach + (kind[j] == TANK ? 0.3 : kind[j] == JEEP ? 0.15 : 0.0);
			if (dx * dx + dz * dz < r * r && q.y < p.y + 0.6) {
				var l = Math.sqrt(dx * dx + dz * dz) + 1e-6;
				if (kind[j] == TANK) {
					hp[j] -= 5;
					flash[j] = 8;
					if (hp[j] > 0) continue;
				}
				fall(j, new Vec3(dx / l * 1.2 + v.x * 0.5, 1.2, dz / l * 1.2 + v.z * 0.5));
			}
		}
	}

	function knockAt(x:Float, z:Float, r:Float, px:Float, pz:Float, of:Int) {
		for (j in 0...bodies.length) {
			if (!alive[j] || kind[j] == HELI || team[j] == of) continue;
			var q = bodies[j].position, dx = q.x - x, dz = q.z - z;
			if (dx * dx + dz * dz < r * r) {
				if (kind[j] == TANK) {
					hp[j] -= 6;
					flash[j] = 8;
					if (hp[j] > 0) continue;
				}
				fall(j, new Vec3(px, 1.0, pz));
			}
		}
	}

	// ---- reading the battle

	public function count(t:Int):Int {
		var n = 0;
		for (i in 0...bodies.length)
			if (alive[i] && team[i] == t) n++;
		return n;
	}

	public function standing(s:Int):Int {
		var n = 0;
		for (i in 0...bodies.length)
			if (alive[i] && squad[i] == s) n++;
		return n;
	}

	public function army(t:Int):Int {
		var n = 0;
		for (s in 0...sqTeam.length)
			if (sqTeam[s] == t) n += sqSize[s];
		return n;
	}

	// (each side's share of its army standing, blue's less red's: level at the start)
	function lead():Float
		return count(0) / army(0) - count(1) / army(1);

	// the middle of a squad's standing soldiers (all of them before the battle)
	public function middle(s:Int):Vec3 {
		var x = 0.0, z = 0.0, k = 0;
		for (i in 0...bodies.length)
			if (squad[i] == s && (alive[i] || !started)) {
				var p = place3(i);
				x += p.x;
				z += p.z;
				k++;
			}
		return k == 0 ? new Vec3(0, 0, 0) : new Vec3(x / k, 0, z / k);
	}

	// where a squad is marching (null: it is not)
	public function heading(s:Int):Null<Vec3> {
		var x = 0.0, z = 0.0, k = 0;
		for (i in 0...bodies.length)
			if (alive[i] && squad[i] == s && ordered[i]) {
				x += tx[i];
				z += tz[i];
				k++;
			}
		return k == 0 ? null : new Vec3(x / k, 0, z / k);
	}

	public function over():Bool
		return ended >= 0 && step >= ended;

	public function won():Bool
		return over() && count(1) == 0 && count(0) > 0;

	public function outcome():Outcome
		return {won: count(1) == 0 && count(0) > 0, blue: count(0), red: count(1), orders: orders.length};

	// ---- keyframes and the timeline

	function keyframe(k:Keyframe):Keyframe {
		k.physics = physics.snapshot(k.physics);
		k.ints = hp.concat(cool).concat(target).concat(until).concat(fell).concat(pTeam).concat(pLife).concat(bTeam).concat(pKind);
		k.floats = tx.concat(tz).concat(yaw).concat(hx).concat(hz).concat(pX).concat(pY).concat(pZ).concat(pVX).concat(pVY).concat(pVZ).concat(bX).concat(bY)
			.concat(bZ).concat(bVY);
		k.bools = alive.concat(ordered).concat(pAlive).concat(bAlive);
		k.props = [for (p in props) p.firedAt];
		k.landed = [for (p in props) p.landed];
		k.ptx = [for (p in props) p.tx];
		k.ptz = [for (p in props) p.tz];
		// (the live bodies not yet in the physics: their state, as the snapshot keeps only those in it)
		k.seed = seed;
		k.ended = ended;
		return k;
	}

	static function back<T>(to:Array<T>, from:Array<T>, at:Int):Int {
		for (i in 0...to.length)
			to[i] = from[at + i];
		return at + to.length;
	}

	function restore(k:Keyframe, at:Int) {
		physics.restore(k.physics);
		var o = 0;
		for (a in [hp, cool, target, until, fell, pTeam, pLife, bTeam, pKind])
			o = back(a, k.ints, o);
		o = 0;
		for (a in [tx, tz, yaw, hx, hz, pX, pY, pZ, pVX, pVY, pVZ, bX, bY, bZ, bVY])
			o = back(a, k.floats, o);
		o = 0;
		for (a in [alive, ordered, pAlive, bAlive])
			o = back(a, k.bools, o);
		for (i in 0...props.length) {
			props[i].firedAt = k.props[i];
			props[i].landed = k.landed[i];
			props[i].tx = k.ptx[i];
			props[i].tz = k.ptz[i];
		}
		for (i in 0...flash.length)
			flash[i] = 0;
		// (a helicopter in flight, put back where it flew)
		for (i in 0...bodies.length)
			if (kind[i] == HELI && alive[i]) {
				bodies[i].position = new Vec3(hx[i], ALT, hz[i]);
				bodies[i].rotates = false;
			}
		blasts.resize(0);
		seed = k.seed;
		ended = k.ended;
		step = at;
	}

	// the battle as it was at step s (at most what is recorded): the keyframe before it, stepped on
	public function seek(s:Int) {
		s = Std.int(Math.max(0, Math.min(s, recorded)));
		if (s == step) return;
		var k = Std.int(s / KEY);
		if (s < step || Std.int(step / KEY) != k) restore(keys[k], k * KEY);
		while (step < s)
			simulate();
	}

	// an order now: the run after this step kept as the ghost and dropped; the battle goes on from here
	public function order(who:Int, x:Float, z:Float) {
		branch();
		orders.push({step: step, who: who, x: x, z: z});
	}

	// a squad put somewhere else at the very start, as before the battle
	// (not an order: the deployment's): the run after kept as the ghost and
	// dropped, the orders with it; the start's keyframe taken again
	public function replace(s:Int, x:Float, z:Float) {
		if (step != 0 || !started) return;
		branch();
		place(s, x, z);
		keyframe(keys[0]);
		ahead[0] = lead();
	}

	// played on from a moment rewound to: the orders from it on undone (the
	// toys they set off ready again, to use later or not), what came after
	// kept as the ghost
	public function resume() {
		for (o in orders)
			if (o.step >= step) {
				branch();
				return;
			}
	}

	// the battle goes on differently from this step: what came after kept as the ghost, dropped
	function branch() {
		if (recorded > step) {
			ghost.resize(0);
			for (a in ahead)
				ghost.push(a);
			ghostEnd = runEnd >= 0 ? runEnd : recorded;
			before = null;
			if (runEnd >= 0) {
				var keep = step;
				seek(runEnd);
				before = outcome();
				seek(keep);
			}
		}
		var i = orders.length;
		while (i-- > 0)
			if (orders[i].step >= step) orders.splice(i, 1);
		recorded = step;
		keys.resize(Std.int(step / KEY) + 1);
		ahead.resize(Std.int(step / KEY) + 1);
		ended = -1;
		runEnd = -1;
	}

	// whether the order can be given now: a squad standing, a prop of blue's not fired yet
	public function canOrder(who:Int):Bool {
		if (who >= PROP) {
			var p = props[who - PROP];
			return p.def.team == 0 && p.firedAt < 0;
		}
		return who >= 0 && who < sqTeam.length && sqTeam[who] == 0 && standing(who) > 0;
	}

	function apply(o:Order) {
		if (o.who >= PROP) {
			fire(props[o.who - PROP], o.x, o.z);
			return;
		}
		var c = middle(o.who);
		for (i in 0...bodies.length)
			if (alive[i] && squad[i] == o.who) {
				var p = place3(i);
				tx[i] = Math.max(-4.9, Math.min(4.9, o.x + (p.x - c.x) * 0.8));
				tz[i] = Math.max(-7.3, Math.min(7.3, o.z + (p.z - c.z) * 0.8));
				ordered[i] = true;
				until[i] = step + 60 * 8;
			}
	}

	// the steps the timeline shows: the battle so far and the ghost's, with room after, at least 15 s
	public function span():Int
		return Std.int(Math.max(60 * 15, Math.max(recorded, ghostEnd) * 1.12));

	// ---- checks

	public function hash():Float {
		var h = 0.0;
		for (i in 0...bodies.length) {
			var p = place3(i);
			h += (p.x * 3 + p.y * 5 + p.z * 7) * (i + 1) + hp[i] * 11 + (alive[i] ? 13 : 0);
		}
		return h;
	}

	// played from the start to the end, with these orders: the outcome
	public function play(list:Array<Order>):Outcome {
		orders.resize(0);
		for (o in list)
			orders.push(o);
		restore(keys[0], 0);
		while (!over())
			simulate();
		return outcome();
	}

	// the orders the solver and the hints try: who (blue's squads and props), when, where
	public function candidates(moments:Array<Int>):Array<Order> {
		var list:Array<Order> = [];
		var spots = [for (gx in [-3.6, -1.2, 1.2, 3.6]) for (gz in [-6.0, -3.5, -1.0, 1.5]) new Vec3(gx, 0, gz)];
		for (s in 0...sqTeam.length)
			if (sqTeam[s] == 0)
				for (m in moments)
					for (p in spots)
						list.push({step: m, who: s, x: p.x, z: p.z});
		for (p in props)
			if (p.def.team == 0) {
				var aims = p.def.type == MARBLE || p.def.type == TOWER || p.def.type == CATAPULT || p.def.type == TOP;
				for (m in moments)
					if (aims) for (q in spots)
						list.push({step: m, who: PROP + p.index, x: q.x, z: q.z}) else list.push({step: m, who: PROP + p.index, x: 0, z: 0});
			}
		return list;
	}
}

class Prop {
	public final index:Int;
	public final def:PropDef;
	// (bodies always in the physics: the books, the box, the ruler)
	public final fixed:Array<Body> = [];
	// (the moving pieces: the marble, the dominoes, the train, the blocks, the eraser)
	public final live:Array<Body> = [];
	// (kinematic stand-ins held still until fired: the tower's blocks, the eraser)
	public final rest:Array<Body> = [];
	public final restPos:Array<Vec3> = [];
	public final restRot:Array<Quat> = [];
	public var firedAt = -1;
	public var landed = false;
	public var tx = 0.0;
	public var tz = 0.0;

	public function new(index:Int, def:PropDef) {
		this.index = index;
		this.def = def;
		// (the path, for dominoes and trains: sampled every STEP from 3 behind its start, straight back there)
		var len = span();
		var x = def.x, z = def.z;
		var back = Std.int(3 / STEP);
		for (k in 0...back + 1) {
			var s = -(back - k) * STEP;
			pathX.push(def.x + Math.sin(def.angle) * s);
			pathZ.push(def.z + Math.cos(def.angle) * s);
			pathH.push(def.angle);
		}
		first = back;
		var n = Std.int(len / STEP) + 2;
		for (k in 1...n) {
			var s = (k - 0.5) * STEP, h = heading(s, len);
			x += Math.sin(h) * STEP;
			z += Math.cos(h) * STEP;
			pathX.push(x);
			pathZ.push(z);
			pathH.push(heading(k * STEP, len));
		}
	}

	static inline var STEP = 0.05;
	final pathX:Array<Float> = [];
	final pathZ:Array<Float> = [];
	final pathH:Array<Float> = [];
	var first = 0;

	// the path's length (dominoes: their row; a train: its run)
	public function span():Float
		return def.type == Sim.DOMINO ? def.count * 0.42 + 0.5 : def.length + 0.5;

	function heading(s:Float, len:Float):Float {
		var f = Math.max(0, Math.min(1, s / Math.max(1e-6, len)));
		return def.angle + def.bend * f + def.wave * Math.sin(f * 2 * Math.PI);
	}

	// the point s along the path, and the heading there
	public function along(s:Float):{x:Float, z:Float, h:Float} {
		var f = s / STEP + first, i = Std.int(Math.floor(f));
		if (i < 0) i = 0;
		if (i >= pathX.length - 1) i = pathX.length - 2;
		var t = Math.max(0, Math.min(1, f - i));
		return {x: pathX[i] + (pathX[i + 1] - pathX[i]) * t, z: pathZ[i] + (pathZ[i + 1] - pathZ[i]) * t, h: pathH[i] + (pathH[i + 1] - pathH[i]) * t};
	}
}

typedef Order = {
	step:Int,
	// a squad, or Sim.PROP + a prop's index
	who:Int,
	x:Float,
	z:Float
}

typedef Outcome = {
	won:Bool,
	blue:Int,
	red:Int,
	orders:Int
}

typedef Blast = {
	x:Float,
	z:Float,
	radius:Float,
	step:Int,
	kind:Int
}

class Keyframe {
	public var physics:Null<Snapshot> = null;
	public var ints:Array<Int> = [];
	public var floats:Array<Float> = [];
	public var bools:Array<Bool> = [];
	public var props:Array<Int> = [];
	public var landed:Array<Bool> = [];
	public var ptx:Array<Float> = [];
	public var ptz:Array<Float> = [];
	public var seed = 0;
	public var ended = -1;

	public function new() {}
}
