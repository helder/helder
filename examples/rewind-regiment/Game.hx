import Levels.Level;
import Sim.Prop;
import Toys.Builder;
import haxe.io.Bytes;
import helder.gfx.Color;
import helder.gfx.Device;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.Store;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World as SceneWorld;
import helder.scene.math.Aabb;
import helder.scene.math.MathTools;
import helder.scene.math.Quat;
import helder.scene.render.Environment;
import helder.scene.render.Images;
import helder.scene.render.InstancedMesh;
import helder.scene.render.Light;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.MeshRenderer;
import helder.scene.render.Renderer;
import helder.scene.render.Shadows;
import helder.scene.view.SceneBox;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// The game's side of the screen: the scene (the level's toys on the play
// tray, lit by a window, through a tilt-shift lens), the battle stepped on
// the frame's clock, the player's touches (squads dragged before the fight;
// a squad or a prop tapped, then where; the timeline dragged), and what the
// HUD reads (signals, and a tick that changes every frame for what follows
// the battle: the badges, the bar, the timeline).
class Game {
	public static final BLUE = new Vec3(0.045, 0.2, 0.78);
	public static final RED = new Vec3(0.78, 0.07, 0.045);
	static final FALLEN = new Vec3(0.3, 0.29, 0.27);
	static final CHOSEN = new Vec3(1.0, 0.72, 0.08);

	public final world = new SceneWorld("rewind-regiment");
	public final camera:Camera;
	final eye:Node;
	final sun:Node;
	var sunLight:Light;
	var stage:Node;
	public var renderer:Null<Renderer>;
	var tilt:Null<TiltShift>;
	var toys:Null<Toys>;
	var box:Null<SceneBox>;
	var device:Null<Device>;

	// ---- the HUD's
	public final screen = signal("title");
	public final levelIndex = signal(0);
	public final playing = signal(false);
	public final selected = signal(-1);
	public final tick = signal(0);
	public final width = signal(390.0);
	public final height = signal(844.0);
	public final ready = signal(false);
	public final card = signal(false);
	public final best:Signal<Array<Int>>;
	public final toast = signal("");
	// (a won battle's best moments shown again, slowly, before the card)
	public final replaying = signal(false);

	public var sim:Sim;
	var level:Level;
	final store:Null<Store>;

	public function new() {
		store = try Store.open("rewind-regiment") catch (_:Dynamic) null;
		best = signal([for (l in Levels.levels) stored(l.name)]);
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.62, 0.1, 120));
		sun = world.node("sun");
		sunLight = Light.attach(sun, Light.directional(new Vec3(1, 0.9, 0.78), 3.4));
		stage = world.node("level");
		level = Levels.levels[0];
		sim = new Sim(level);
	}

	function stored(name:String):Int {
		var s = store == null ? null : store.get("stars:" + name);
		return s == null ? 0 : Std.parseInt(s) ?? 0;
	}

	// ---- set up by the <Scene>

	public function attach(b:SceneBox) {
		box = b;
		// (a phone's 3x screen drawn at 1.5 pixels a point, stretched: a ninth of
		// the fill was most of the frame; the HUD over it stays sharp)
		b.density = 1.5;
	}

	public function setup(r:Renderer) {
		renderer = r;
		device = r.device;
		r.clearColor = new Color(0.9, 0.86, 0.8, 1);
		var s = new Shadows(r.device, 2048).soft(0.06, 8, 0.05);
		s.strength = 0.82;
		s.bias = 0.0015;
		r.use(s);
		r.rimPower = 4.0;
		var post = r.post;
		if (post != null) {
			post.bloom = 0.04;
			post.levels = 4;
			post.base = 2;
			post.saturation = 1.08;
			post.contrast = 1.06;
			post.vignette = 0.28;
			post.grain = 0.012;
			// (the contact shadows of everything strewn: GTAO, at half size)
			post.ao = new helder.scene.render.Ssao({radius: 0.45, intensity: 1.1, samples: 8, halfRes: true});
		}
		tilt = post != null ? new TiltShift(post) : null;
		toys = new Toys(r.device);
		Sounds.start();
		// (for checking: RR_LEVEL=n opens level n, RR_FIGHT starts it)
		var only = Sys.getEnv("RR_LEVEL");
		load(only != null ? (Std.parseInt(only) ?? 1) - 1 : levelIndex.peek());
		if (only != null) {
			screen("deploy");
			if (Sys.getEnv("RR_FIGHT") != null) begin();
		}
	}

	// ---- a level: its scene made anew

	public function load(n:Int) {
		clearEvents();
		levelIndex(n);
		level = Levels.levels[n];
		sim = new Sim(level);
		selected(-1);
		playing(false);
		card(false);
		var t = toys, d = device;
		if (t == null || d == null) return;
		stage.dispose();
		stage = world.node("level");
		var set = Levels.settings[level.setting];
		// (the room's light: its window's colour, warm or cool)
		var l = set.light;
		sunLight.color = new Vec3(Toys.lin((l >> 16) & 255), Toys.lin((l >> 8) & 255), Toys.lin(l & 255));
		room(t, d, set);
		var r = renderer;
		var e = environment == null ? envFor(d, Levels.settings[0]) : null;
		if (r != null && e != null) {
			environment = e;
			e.background = false;
			e.intensity = 0.9;
			r.use(e);
		}
		units(t);
		propsOf(t);
		fx(t);
		framed = -1;
		introTime = Sys.getEnv("RR_CLOSE") == null ? 1.2 : 0.0;
	}

	var environment:Null<Environment>;

	// ---- the room: Rooms' (the field's surface, the floor, what is about)
	function room(t:Toys, d:Device, set:Levels.Setting)
		Rooms.build(d, world, stage, level.setting, levelIndex.peek(), sim.props);

	// ---- the units: one instanced draw a kind
	var sets:Array<Null<InstancedMesh>> = [];
	var slot:Array<Int> = [];
	var rotors:Null<InstancedMesh>;
	var pellets:Null<InstancedMesh>;
	var bombs:Null<InstancedMesh>;
	var rockets:Null<InstancedMesh>;

	function units(t:Toys) {
		var meshes = [t.grunt(), t.rifleman(), t.tank(), t.jeep(), t.heli(), t.bazooka(), t.robot()];
		var counts = [for (_ in 0...Sim.KINDS) 0];
		slot = [];
		for (i in 0...sim.bodies.length)
			slot.push(counts[sim.kind[i]]++);
		sets = [];
		for (k in 0...Sim.KINDS) {
			if (counts[k] == 0) {
				sets.push(null);
				continue;
			}
			var im = new InstancedMesh(meshes[k], counts[k], counts[k]);
			im.bounds = new Aabb(new Vec3(-7, -1, -9), new Vec3(7, 3, 9));
			InstancedMesh.attach(world.node("units", stage), im);
			sets.push(im);
		}
		rotors = counts[Sim.HELI] > 0 ? new InstancedMesh(t.rotor(), counts[Sim.HELI], counts[Sim.HELI]) : null;
		if (rotors != null) {
			rotors.bounds = new Aabb(new Vec3(-7, -1, -9), new Vec3(7, 3, 9));
			InstancedMesh.attach(world.node("rotors", stage), rotors);
		}
		pellets = new InstancedMesh(t.pellet(), Sim.PELLETS, 0);
		pellets.bounds = new Aabb(new Vec3(-7, -1, -9), new Vec3(7, 3, 9));
		pellets.castShadows = false;
		InstancedMesh.attach(world.node("pellets", stage), pellets);
		rockets = new InstancedMesh(t.rocket(), 32, 0);
		rockets.bounds = new Aabb(new Vec3(-7, -1, -9), new Vec3(7, 6, 9));
		InstancedMesh.attach(world.node("rockets", stage), rockets);
		bombs = new InstancedMesh(t.bomb(), Sim.BOMBS, 0);
		bombs.bounds = new Aabb(new Vec3(-7, -1, -9), new Vec3(7, 3, 9));
		InstancedMesh.attach(world.node("bombs", stage), bombs);
	}

	// ---- the props' nodes
	var propNodes:Array<Array<Node>> = [];

	function propsOf(t:Toys) {
		propNodes = [];
		for (p in sim.props) {
			var d = p.def, list:Array<Node> = [];
			var face = Quat.axisAngle(new Vec3(0, 1, 0), d.angle);
			var dx = Math.sin(d.angle), dz = Math.cos(d.angle);
			inline function node(m:Mesh, ?at:Vec3, ?q:Quat):Node {
				var n = world.node("prop", stage);
				MeshRenderer.attach(n, m);
				if (at != null) n.position = at;
				if (q != null) n.rotation = q;
				return n;
			}
			var team = d.team == 0 ? 0x2F5FD0 : 0xC8372D;
			switch d.type {
				case Sim.MARBLE:
					// (three books stacked, the ramp book, the marble)
					var cols = d.team == 0 ? [0x2B4C7E, 0x567EBB, 0x1D3557] : [0x9B2226, 0xBB3E03, 0x7F1D1D];
					for (k in 0...3)
						node(t.book(1.4, 0.3, 1.4, cols[k]), new Vec3(d.x, 0.15 + k * 0.3, d.z), face * Quat.axisAngle(new Vec3(0, 1, 0), (k - 1) * 0.08));
					var tilt = Math.atan2(0.9, 2.2);
					node(t.book(1.2, 0.08, 2.4, cols[1]), new Vec3(d.x + dx * 1.75, 0.45, d.z + dz * 1.75), face * Quat.axisAngle(new Vec3(1, 0, 0), tilt));
					list.push(node(t.marble(0xFFFFFF, d.team == 0 ? 0x4C8DFF : 0xFF5A45)));
				case Sim.DOMINO:
					for (k in 0...d.count)
						list.push(node(t.domino((k * 3 + 1) % 7, (k * 5 + 2) % 7)));
				case Sim.TRAIN:
					var len = d.length + 1.4;
					var n = Std.int((d.length + 1.6) / 0.22);
					node(t.trackAlong([for (k in 0...n + 1) p.along(-1.5 + k * 0.22)]));
					list.push(node(t.engine(team)));
					list.push(node(t.wagon(0xE9C46A)));
					list.push(node(t.wagon(0x2A9D8F)));
				case Sim.JACK:
					list.push(node(t.jackBox(), new Vec3(d.x, 0.3, d.z), face));
					list.push(node(t.jackLid()));
					list.push(node(t.spring()));
					list.push(node(t.clown()));
				case Sim.TOWER:
					var cols = [0xE63946, 0xF4A261, 0x2A9D8F, 0x457B9D, 0x8338EC, 0xFFBE0B];
					for (k in 0...d.count)
						list.push(node(t.block(cols[k % cols.length])));
				case Sim.TOP:
					list.push(node(t.top()));
				case Sim.CATAPULT:
					node(t.pencil(), new Vec3(d.x, 0.05, d.z), face * Quat.axisAngle(new Vec3(0, 1, 0), Math.PI / 2));
					list.push(node(t.ruler()));
					list.push(node(t.eraser()));
			}
			propNodes.push(list);
		}
	}

	// ---- puffs: dust where soldiers fall and props land (looks only)
	static inline var PUFFS = 220;
	var puffs:Null<InstancedMesh>;
	final puffX = [for (_ in 0...PUFFS) 0.0];
	final puffY = [for (_ in 0...PUFFS) 0.0];
	final puffZ = [for (_ in 0...PUFFS) 0.0];
	final puffVX = [for (_ in 0...PUFFS) 0.0];
	final puffVY = [for (_ in 0...PUFFS) 0.0];
	final puffVZ = [for (_ in 0...PUFFS) 0.0];
	final puffLife = [for (_ in 0...PUFFS) 0.0];
	final puffSize = [for (_ in 0...PUFFS) 0.0];
	final puffColor = [for (_ in 0...PUFFS) 0];
	final puffFall = [for (_ in 0...PUFFS) false];
	var puffNext = 0;
	var wasAlive:Array<Bool> = [];
	// (blasts' flashes: a few hot balls, swelling and gone in a fifth of a second)
	static inline var FLASHES = 8;
	var flashes:Null<InstancedMesh>;
	final flashX = [for (_ in 0...FLASHES) 0.0];
	final flashZ = [for (_ in 0...FLASHES) 0.0];
	final flashR = [for (_ in 0...FLASHES) 0.0];
	final flashLife = [for (_ in 0...FLASHES) 0.0];
	var flashNext = 0;

	function flashAt(x:Float, z:Float, r:Float) {
		var k = flashNext;
		flashNext = (flashNext + 1) % FLASHES;
		flashX[k] = x;
		flashZ[k] = z;
		flashR[k] = r;
		flashLife[k] = 0.0001;
	}

	function fx(t:Toys) {
		var b = new Builder();
		b.ellipsoid(new Vec3(0, 0, 0), new Vec3(1, 0.55, 1), null, 10, 6);
		var m = new Mesh();
		b.into(m, t.device, Toys.mat("dust", 0xFFFFFF, 0.9));
		flashes = new InstancedMesh(t.flash(), FLASHES, FLASHES);
		flashes.bounds = new Aabb(new Vec3(-8, -1, -9), new Vec3(8, 3, 9));
		flashes.castShadows = false;
		InstancedMesh.attach(world.node("flashes", stage), flashes);
		for (k in 0...FLASHES)
			flashLife[k] = 0;
		puffs = new InstancedMesh(m, PUFFS, PUFFS);
		puffs.bounds = new Aabb(new Vec3(-8, -1, -9), new Vec3(8, 3, 9));
		puffs.castShadows = false;
		InstancedMesh.attach(world.node("puffs", stage), puffs);
		for (k in 0...PUFFS)
			puffLife[k] = 0;
		wasAlive = sim.alive.copy();
	}

	var seedFx = 11;

	// ---- the guides the HUD draws over the field (in points): a path of
	// dots and a flag where each squad was sent, gold from what is chosen to
	// the finger; x, y and 1 for gold, 0 for blue, three numbers a dot or flag
	public final guides:Array<Float> = [];
	public final flagsAt:Array<Float> = [];
	public static inline var GUIDES = 60;

	function markers() {
		guides.resize(0);
		flagsAt.resize(0);
		if (slot.length != sim.bodies.length || screen.peek() != "battle" || replaying.peek()) return;
		var chosen = downOn >= 0 ? downOn : selected.peek();
		inline function path(a:Vec3, b:Vec3, gold:Bool) {
			var dx = b.x - a.x, dz = b.z - a.z, len = Math.sqrt(dx * dx + dz * dz);
			var gap = 0.42, k = (time * 0.7) % gap + 0.3;
			while (k < len - 0.25 && guides.length < GUIDES * 3) {
				var f = k / len, p = project(new Vec3(a.x + dx * f, 0.02, a.z + dz * f));
				guides.push(p.x);
				guides.push(p.y);
				guides.push(gold ? 1 : 0);
				k += gap;
			}
			var e = project(new Vec3(b.x, 0.02, b.z));
			flagsAt.push(e.x);
			flagsAt.push(e.y);
			flagsAt.push(gold ? 1 : 0);
		}
		// (where blue's squads were sent, while they march)
		for (q in 0...sim.sqTeam.length) {
			if (sim.sqTeam[q] != 0 || (q == chosen && dragTo != null)) continue;
			var h = sim.heading(q);
			if (h != null) path(sim.middle(q), h, false);
		}
		// (what the chosen one will do: a path to the finger)
		var to = dragTo;
		if (chosen >= 0 && to != null && (chosen < Sim.PROP || aims(chosen))) {
			var from = chosen >= Sim.PROP ? {
				var d = sim.props[chosen - Sim.PROP].def;
				new Vec3(d.x, 0, d.z);
			} : sim.middle(chosen);
			path(from, to, true);
		}
	}

	inline function rnd():Float {
		seedFx = (seedFx * 1103515245 + 12345) & 0x7fffffff;
		return seedFx / 0x7fffffff;
	}

	function puff(x:Float, y:Float, z:Float, n:Int, speed:Float, size:Float) {
		for (_ in 0...n) {
			var k = puffNext;
			puffNext = (puffNext + 1) % PUFFS;
			var a = rnd() * Math.PI * 2;
			puffX[k] = x;
			puffY[k] = y;
			puffZ[k] = z;
			puffVX[k] = Math.cos(a) * speed * (0.4 + rnd());
			puffVY[k] = speed * (0.3 + rnd() * 0.7);
			puffVZ[k] = Math.sin(a) * speed * (0.4 + rnd());
			puffLife[k] = 0.0001;
			puffSize[k] = size * (0.6 + rnd() * 0.6);
			puffColor[k] = 0xEDE6D8;
			puffFall[k] = false;
		}
	}

	// confetti over the tray: coloured bits drifting down, turning
	function confetti() {
		var colors = [0xE63946, 0xFFB703, 0x2A9D8F, 0x457B9D, 0xF4A261, 0x8338EC, 0xFFFFFF];
		for (n in 0...120) {
			var k = puffNext;
			puffNext = (puffNext + 1) % PUFFS;
			puffX[k] = (rnd() - 0.5) * 10;
			puffY[k] = 3 + rnd() * 3;
			puffZ[k] = (rnd() - 0.5) * 14;
			puffVX[k] = (rnd() - 0.5) * 0.6;
			puffVY[k] = -0.6 - rnd() * 0.6;
			puffVZ[k] = (rnd() - 0.5) * 0.6;
			puffLife[k] = 0.0001 + n * 0.004;
			puffSize[k] = 0.05 + rnd() * 0.03;
			puffColor[k] = colors[n % colors.length];
			puffFall[k] = true;
		}
	}

	// ---- the frame

	var last = -1.0;
	var acc = 0.0;
	var time = 0.0;
	var smooth = 0;
	var slowFor = 0.0;

	public function frame(t:Float) {
		var dt = last < 0 ? 0 : Math.min(0.1, t - last);
		last = t;
		time += dt;
		var b = box;
		if (b != null) {
			if (Math.abs(b.width - width.peek()) > 0.5) width(b.width);
			if (Math.abs(b.height - height.peek()) > 0.5) height(b.height);
		}
		if (!ready.peek()) {
			smooth = dt > 0 && dt < 0.034 ? smooth + 1 : 0;
			if ((renderer != null && smooth >= 6) || time > 4) ready(true);
		}
		// (too slow for a few seconds on end, once ready: the world drawn at fewer
		// pixels, a step at a time, down to half; never back up)
		if (ready.peek() && b != null && dt > 0) {
			slowFor = dt > 1 / 40 ? slowFor + dt : Math.max(0, slowFor - dt * 2);
			if (slowFor > 2.5 && b.scale > 0.55) {
				b.scale = Math.max(0.5, b.scale * 0.85);
				slowFor = 0;
			}
		}
		// (behind the title: the first level's battle playing by itself, again and again)
		if (screen.peek() == "title" && renderer != null && slot.length == sim.bodies.length) {
			if (!sim.started) {
				sim.start();
				wasAlive = sim.alive.copy();
				playing(true);
			} else if (sim.over() || !playing.peek()) {
				sim.seek(0);
				wasAlive = sim.alive.copy();
				playing(true);
			}
		}
		Sounds.muted = screen.peek() != "battle";
		if (replaying.peek()) replayStep(dt);
		if (playing.peek() && sim.started) {
			// (the last moments, once a side is gone: slow)
			// (and while a squad or a toy is chosen, or dragged: a quarter speed, to steer by)
			var steer = screen.peek() == "battle" && (selected.peek() >= 0 || downOn >= 0) ? 0.25 : 1.0;
			acc += (sim.ended >= 0 && sim.step < sim.ended ? dt * 0.35 : dt) * steer;
			var n = 0;
			while (acc >= 1 / 60 && n < 3) {
				acc -= 1 / 60;
				n++;
				if (sim.over()) {
					playing(false);
					if (screen.peek() == "battle") finished();
					break;
				}
				if (sim.step < sim.recorded) sim.seek(sim.step + 1) else sim.simulate();
				falls();
			}
			if (acc > 1 / 60) acc = 0;
		}
		sync(dt);
		markers();
		frameCamera();
		shake(dt);
		layoutLabels(dt);
		focus();
		tick(tick.peek() + 1);
	}

	// (new falls and blasts: dust)
	function falls() {
		// (what happened, for the replay: a step seen again drops what was kept from it on)
		if (!replaying.peek()) {
			if (sim.step <= eventsTo) {
				var k = evStep.length;
				while (k-- > 0)
					if (evStep[k] >= sim.step) {
						evStep.splice(k, 1);
						evX.splice(k, 1);
						evZ.splice(k, 1);
						evW.splice(k, 1);
					}
			}
			eventsTo = sim.step;
		}
		for (i in 0...sim.bodies.length) {
			if (sim.alive[i] && sim.fired[i] == sim.step - 1) {
				var k = sim.kind[i], p = sim.bodies[i].position, y = sim.yaw[i];
				if (k == Sim.RIFLE) {
					puff(p.x + Math.sin(y) * 0.32, p.y + 0.1, p.z + Math.cos(y) * 0.32, 2, 0.15, 0.035);
					Sounds.play("pop", 0.18);
				} else if (k == Sim.BAZOOKA) {
					puff(p.x - Math.sin(y) * 0.15, p.y + 0.14, p.z - Math.cos(y) * 0.15, 5, 0.35, 0.06);
					Sounds.play("whoosh", 0.3);
				} else if (k != Sim.HELI) Sounds.play("clack", 0.22);
			}
			if (sim.alive[i] && wasAlive[i] && sim.flash[i] == 8) Sounds.play("clack", 0.14, 1.2);
			if (wasAlive[i] && !sim.alive[i]) {
				Sounds.play("topple", sim.kind[i] == Sim.TANK ? 0.6 : 0.3, sim.kind[i] == Sim.TANK ? 0.6 : null);
				var p = sim.bodies[i].position;
				event(p.x, p.z, sim.team[i] == 1 ? (sim.kind[i] == Sim.TANK || sim.kind[i] == Sim.HELI ? 4 : 1) : 0.5);
				var big = sim.kind[i] == Sim.TANK ? 2.5 : 1.0;
				puff(p.x, 0.05, p.z, Std.int(4 * big), 0.5 * big, 0.06 * big);
			}
			wasAlive[i] = sim.alive[i];
		}
		for (bl in sim.blasts) {
			puff(bl.x, 0.08, bl.z, bl.kind == 2 ? 26 : bl.kind == 4 ? 12 : 18, 1.6 * bl.radius, 0.1);
			trauma = Math.min(1, trauma + (bl.kind == 4 ? 0.2 : 0.45));
			event(bl.x, bl.z, 3);
			if (bl.kind != 2) flashAt(bl.x, bl.z, bl.radius * (bl.kind == 4 ? 0.5 : 0.6));
			if (bl.kind == 2) {
				Sounds.play("boing", 0.8);
				Sounds.play("boom", 0.35, 1.3);
			} else Sounds.play("boom", bl.kind == 4 ? 0.35 : 0.55);
		}
		// (the dominoes: a tock as each lands)
		for (p in sim.props)
			if (p.def.type == Sim.DOMINO && p.firedAt >= 0) {
				var since = sim.step - 1 - p.firedAt;
				if (since >= 11 && (since - 11) % 7 == 0 && (since - 11) / 7 < p.def.count) Sounds.play("tock", 0.45);
			}
		for (p in sim.props)
			if (p.firedAt == sim.step - 1) {
				var d = p.def;
				event(d.x, d.z, d.team == 0 ? 5 : 2);
				switch d.type {
					case Sim.MARBLE: Sounds.play("roll", 0.9);
					case Sim.TRAIN: Sounds.play("whistle", 0.6);
					case Sim.TOWER: Sounds.play("topple", 0.7, 0.7);
					case Sim.CATAPULT: Sounds.play("whoosh", 0.6, 0.8);
					case Sim.TOP: Sounds.play("whir", 0.5, 0.7);
					case _:
				}
			}
		sim.blasts.resize(0);
	}

	public var wonNow = false;

	function finished() {
		var o = sim.outcome();
		wonNow = o.won;
		if (o.won && !replaying.peek() && startReplay()) {
			save(o);
			return;
		}
		if (o.won) confetti();
		Sounds.play(o.won ? "fanfare" : "sag", 0.7, 1.0);
		save(o);
		card(true);
	}

	function save(o:Sim.Outcome) {
		if (o.won) {
			var stars = starsFor(o.orders, o.blue, sim.army(0));
			var list = best.peek().copy();
			if (stars > list[levelIndex.peek()]) {
				list[levelIndex.peek()] = stars;
				best(list);
				if (store != null) store.set("stars:" + level.name, "" + stars);
			}
		}
	}

	// ---- the replay: the battle's busiest moments again, slowly, close
	// (events: where something fell, burst or was set off, weighted)
	final evStep:Array<Int> = [];
	final evX:Array<Float> = [];
	final evZ:Array<Float> = [];
	final evW:Array<Float> = [];
	var eventsTo = -1;
	var moments:Array<{from:Int, x:Float, z:Float, turn:Float}> = [];
	var moment = 0;
	var momentT = 0.0;
	static inline var MOMENT = 66;
	static inline var SLOW = 0.32;

	function clearEvents() {
		for (a in [evX, evZ, evW])
			a.resize(0);
		evStep.resize(0);
		eventsTo = -1;
		replaying(false);
	}

	function event(x:Float, z:Float, w:Float) {
		if (replaying.peek()) return;
		evStep.push(sim.step);
		evX.push(x);
		evZ.push(z);
		evW.push(w);
	}

	// the moments: the busiest stretches of 45 steps, up to three, apart, in order
	function startReplay():Bool {
		var bucket = 45, scores = new Map<Int, Float>();
		for (k in 0...evStep.length) {
			var b = Std.int(evStep[k] / bucket);
			scores.set(b, (scores.get(b) ?? 0) + evW[k]);
		}
		var keys = [for (b in scores.keys()) b];
		keys.sort((a, b) -> (scores.get(b) ?? 0) > (scores.get(a) ?? 0) ? 1 : -1);
		var chosen:Array<Int> = [];
		for (b in keys) {
			if (chosen.length >= 3 || (scores.get(b) ?? 0) < 3) break;
			var near = false;
			for (c in chosen)
				if (Math.abs(c - b) < 3) near = true;
			if (!near) chosen.push(b);
		}
		if (chosen.length == 0) return false;
		chosen.sort((a, b) -> a - b);
		moments = [];
		for (b in chosen) {
			var x = 0.0, z = 0.0, w = 0.0;
			for (k in 0...evStep.length)
				if (Std.int(evStep[k] / bucket) == b) {
					x += evX[k] * evW[k];
					z += evZ[k] * evW[k];
					w += evW[k];
				}
			moments.push({from: Std.int(Math.max(0, b * bucket - 24)), x: Math.max(-4.5, Math.min(4.5, x / w)), z: Math.max(-6.5, Math.min(6.5, z / w)),
				turn: moments.length % 2 == 0 ? 1.0 : -1.0});
		}
		replaying(true);
		selected(-1);
		moment = -1;
		nextMoment();
		return true;
	}

	function nextMoment() {
		moment++;
		if (moment >= moments.length) {
			endReplay();
			return;
		}
		sim.seek(moments[moment].from);
		wasAlive = sim.alive.copy();
		momentT = 0;
		acc = 0;
	}

	public function endReplay() {
		if (!replaying.peek()) return;
		replaying(false);
		sim.seek(sim.recorded);
		wasAlive = sim.alive.copy();
		confetti();
		Sounds.play("fanfare", 0.7, 1.0);
		card(true);
	}

	function replayStep(dt:Float) {
		var m = moments[moment];
		if (m == null) return;
		momentT += dt;
		acc += dt * SLOW;
		while (acc >= 1 / 60) {
			acc -= 1 / 60;
			if (sim.step < sim.recorded && sim.step < m.from + MOMENT) {
				sim.seek(sim.step + 1);
				falls();
			}
		}
		if (sim.step >= m.from + MOMENT || sim.step >= sim.recorded) nextMoment();
	}

	// the replay's camera: low, close, turning slowly about the moment
	function replayCamera() {
		var m = moments[moment];
		if (m == null) return;
		var u = momentT * SLOW * 60 / MOMENT;
		var side = width.peek() / Math.max(1, height.peek()) > 1.15;
		var a = (side ? Math.PI / 2 : 0) + m.turn * (-0.55 + u * 0.9), r = 4.3 - u * 0.8, h = 1.6 + u * 0.3;
		eye.position = new Vec3(m.x + Math.sin(a) * r, h, m.z + Math.cos(a) * r);
		eye.lookAt(new Vec3(m.x, 0.22, m.z));
	}

	// medals: one for a win; two with at most two orders; three with one order (or none)
	public static function starsFor(orders:Int, left:Int, army:Int):Int
		return orders <= 1 ? 3 : orders <= 2 ? 2 : 1;

	// ---- placing what the battle moved

	function sync(dt:Float) {
		var n = sim.bodies.length;
		if (slot.length != n) return;
		var spin = time * 40;
		var sel = moving >= 0 ? moving : downOn >= 0 && downOn < Sim.PROP ? downOn : selected.peek();
		for (i in 0...n) {
			var im = sets[sim.kind[i]];
			if (im == null) continue;
			var b = sim.bodies[i], p = b.position, q = b.orientation;
			var k = sim.kind[i], j = slot[i];
			// (a shot's kick: the rifleman rocks back a little)
			var kick = sim.alive[i] && sim.step - sim.fired[i] < 6 ? (6 - (sim.step - sim.fired[i])) / 6 : 0.0;
			if (kick > 0 && (k == Sim.RIFLE || k == Sim.GRUNT)) q = q * Quat.axisAngle(new Vec3(1, 0, 0), -kick * 0.18);
			// (a soldier's march: a bob)
			var y = p.y;
			if (sim.alive[i] && k != Sim.HELI && playing.peek()) {
				var v = b.velocity;
				var sp = Math.sqrt(v.x * v.x + v.z * v.z);
				if (sp > 0.2 && k <= Sim.RIFLE) y += Math.abs(Math.sin(time * 14 + i)) * 0.018;
				if (sp > 0.1 && k == Sim.ROBOT) q = q * Quat.axisAngle(new Vec3(0, 0, 1), Math.sin(time * 9 + i) * 0.12);
			}
			im.setTransform(j, p.x, y, p.z, q.x, q.y, q.z, q.w);
			var c = sim.flash[i] > 0 ? new Vec3(1.6, 1.5, 1.4) : !sim.alive[i] ? FALLEN : sim.team[i] == 0 ? (sim.squad[i] == sel ? CHOSEN : BLUE) : RED;
			if (sim.flash[i] > 0 && dt > 0) sim.flash[i]--;
			// (each soldier's plastic a shade of its own, as from different batches)
			var shade = sim.flash[i] > 0 ? 1.0 : 0.9 + (((i * 40503 + 977) * 2971) & 255) / 255 * 0.2;
			im.setColor(j, c.x * shade, c.y * shade, c.z * shade);
			if (k == Sim.HELI) {
				var r = rotors;
				if (r != null) {
					var top = q.rotate(new Vec3(0, 0.17, 0.02));
					var rq = q * Quat.axisAngle(new Vec3(0, 1, 0), sim.alive[i] ? spin + i : 0.3 * i);
					r.setTransform(j, p.x + top.x, p.y + top.y, p.z + top.z, rq.x, rq.y, rq.z, rq.w);
					r.setColor(j, c.x * 0.7 + 0.1, c.y * 0.7 + 0.1, c.z * 0.7 + 0.1);
				}
			}
		}
		// (pellets: along their flight; bombs: falling, turning)
		var pl = pellets;
		if (pl != null) {
			var c = 0, rc = 0;
			var rk = rockets;
			for (k in 0...Sim.PELLETS)
				if (sim.pAlive[k] && sim.pKind[k] == 1) {
					// (a rocket along its flight, trailing smoke)
					var v = sim.pVelocity(k);
					var yaw = Math.atan2(v.x, v.z), pitch = -Math.atan2(v.y, Math.sqrt(v.x * v.x + v.z * v.z));
					var q = Quat.axisAngle(new Vec3(0, 1, 0), yaw) * Quat.axisAngle(new Vec3(1, 0, 0), pitch);
					if (rk != null && rc < 32) {
						rk.setTransform(rc, sim.pX[k], sim.pY[k], sim.pZ[k], q.x, q.y, q.z, q.w);
						rc++;
					}
					if (playing.peek() && rnd() < 0.6) puff(sim.pX[k], sim.pY[k], sim.pZ[k], 1, 0.05, 0.045);
				} else if (sim.pAlive[k]) {
					var team = sim.pTeam[k];
					var v = sim.pVelocity(k);
					var q = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(v.x, v.z));
					pl.setTransform(c, sim.pX[k], sim.pY[k], sim.pZ[k], q.x, q.y, q.z, q.w);
					pl.setColor(c, team == 0 ? 1.0 : 1.0, team == 0 ? 0.75 : 0.45, team == 0 ? 0.25 : 0.2);
					c++;
				}
			pl.count = c;
			if (rk != null) rk.count = rc;
		}
		var bm = bombs;
		if (bm != null) {
			var c = 0;
			for (k in 0...Sim.BOMBS)
				if (sim.bAlive[k]) {
					var q = Quat.axisAngle(new Vec3(1, 0, 0), sim.bY[k] * 3);
					bm.setTransform(c, sim.bX[k], sim.bY[k], sim.bZ[k], q.x, q.y, q.z, q.w);
					c++;
				}
			bm.count = c;
		}
		props();
		var fl = flashes;
		if (fl != null)
			for (k in 0...FLASHES) {
				var life = flashLife[k];
				if (life > 0) {
					life += dt;
					flashLife[k] = life > 0.22 ? 0 : life;
				}
				var t = flashLife[k] / 0.22;
				var s = flashLife[k] <= 0 ? 0.0 : flashR[k] * Math.sin(Math.min(1, t) * Math.PI) * (0.6 + t * 0.6);
				fl.setTransform(k, flashX[k], 0.08 + s * 0.4, flashZ[k], 0, 0, 0, 1, s);
			}
		var pf = puffs;
		if (pf != null)
			for (k in 0...PUFFS) {
				var life = puffLife[k];
				if (life > 0) {
					life += dt;
					puffLife[k] = life >= (puffFall[k] ? 6.0 : 0.9) || puffY[k] < -0.1 ? 0 : life;
					puffX[k] += puffVX[k] * dt;
					puffY[k] += puffVY[k] * dt;
					puffZ[k] += puffVZ[k] * dt;
					puffVX[k] *= 1 - dt * 3;
					puffVY[k] = puffFall[k] ? Math.max(-0.9, puffVY[k] - dt * 0.2) : puffVY[k] * (1 - dt * 3) - dt * 0.4;
					puffVZ[k] *= 1 - dt * 3;
				}
				var s = puffLife[k] <= 0 ? 0.0 : puffFall[k] ? puffSize[k] * Math.min(1, puffLife[k] * 4) : puffSize[k] * Math.sin(Math.min(1, puffLife[k] / 0.9) * Math.PI);
				var spin = puffFall[k] ? Quat.axisAngle(new Vec3(0.6, 0.5, 0.3), puffLife[k] * 6 + k) : Quat.identity();
				pf.setTransform(k, puffX[k], Math.max(puffFall[k] ? 0.01 : 0.02, puffY[k]), puffZ[k], spin.x, spin.y, spin.z, spin.w, s);
				var c = puffColor[k];
				pf.setColor(k, Toys.lin((c >> 16) & 255), Toys.lin((c >> 8) & 255), Toys.lin(c & 255));
			}
	}

	function props() {
		if (propNodes.length != sim.props.length) return;
		for (pi in 0...sim.props.length) {
			var p = sim.props[pi], d = p.def, list = propNodes[pi];
			var fired = p.firedAt >= 0 && sim.step >= p.firedAt;
			var since = fired ? sim.step - p.firedAt : -1;
			switch d.type {
				case Sim.MARBLE:
					pose(list[0], p.live[0]);
				case Sim.TOP:
					// (spinning while it runs, slowing, then lying on its side)
					var b = p.live[0], n = list[0];
					var t = since < 0 ? 0.0 : since / 60;
					var spinning = since >= 0 && since < 240;
					var lean = since < 0 ? 0.0 : since < 240 ? Math.sin(t * 5) * 0.08 : Math.min(1.25, (since - 240) / 20 * 1.25);
					spinAngle += since < 0 ? 0.0 : spinning ? 0.9 : Math.max(0, 0.9 - (since - 240) * 0.05);
					var down = since >= 240 ? Math.min(1, (since - 240) / 20) : 0.0;
					n.position = new Vec3(b.position.x, 0.26 - down * 0.08, b.position.z);
					n.rotation = Quat.axisAngle(new Vec3(1, 0, 0.3), lean) * Quat.axisAngle(new Vec3(0, 1, 0), spinAngle);
				case Sim.DOMINO, Sim.TRAIN:
					for (k in 0...list.length)
						pose(list[k], p.live[k]);
				case Sim.JACK:
					var face = Quat.axisAngle(new Vec3(0, 1, 0), d.angle);
					// (the lid flung open, the clown up on his spring, bobbing as it settles)
					var t = since < 0 ? 0.0 : since / 60;
					var open = since < 0 ? 0.0 : Math.min(1, t * 6);
					var lid = list[1];
					var hinge = new Vec3(d.x, 0.6, d.z) + face.rotate(new Vec3(0, 0, 0.3));
					lid.position = hinge;
					lid.rotation = face * Quat.axisAngle(new Vec3(1, 0, 0), -open * 2.2);
					var up = since < 0 ? 0.0 : (1 - Math.exp(-t * 7) * Math.cos(t * 22)) * 0.75;
					var spring = list[2];
					spring.position = new Vec3(d.x, 0.45, d.z);
					spring.scale = new Vec3(1, Math.max(0.02, up), 1);
					var clown = list[3];
					clown.position = new Vec3(d.x, 0.45 + Math.max(0.02, up), d.z);
					clown.rotation = face * Quat.axisAngle(new Vec3(0, 0, 1), since < 0 ? 0 : Math.sin(t * 9) * Math.exp(-t * 2) * 0.4);
					clown.visible = since >= 0;
					spring.visible = since >= 0;
				case Sim.TOWER, Sim.CATAPULT:
					var from = fired ? p.live : p.rest;
					var nodes = d.type == Sim.CATAPULT ? [list[1]] : list;
					for (k in 0...nodes.length)
						pose(nodes[k], from[k]);
					if (d.type == Sim.CATAPULT) {
						// (the ruler: its far end down until fired, then flipped)
						var face = Quat.axisAngle(new Vec3(0, 1, 0), d.angle);
						var t = since < 0 ? 0.0 : Math.min(1, since / 6);
						var a = 0.2 - t * 0.4;
						list[0].position = new Vec3(d.x, 0.12, d.z);
						list[0].rotation = face * Quat.axisAngle(new Vec3(1, 0, 0), a);
					}
			}
		}
	}

	var spinAngle = 0.0;

	inline function pose(n:Node, b:helder.physics.Body) {
		n.position = b.position;
		n.rotation = b.orientation;
	}

	// ---- the camera: the whole tray between the HUD's bars, from blue's side
	var framed = -1.0;

	function frameCamera() {
		var b = box;
		var w = b != null ? b.width : 390.0, h = b != null ? b.height : 844.0;
		var aspect = w / Math.max(1, h);
		if (Math.abs(aspect - framed) < 1e-4) return;
		framed = aspect;
		var top = 96 / h, bottom = 120 / h;
		// (tall: from behind blue; wide: from the side, blue on the left)
		var side = aspect > 1.15;
		var tilt = aspect < 1 ? 1.12 : side ? 0.98 : 0.92, d = 6.0, at = side ? new Vec3(0.4, 0, 0) : new Vec3(0, 0, 0.5);
		while (d < 90) {
			eye.position = side ? new Vec3(at.x + Math.cos(tilt) * d, Math.sin(tilt) * d, at.z) : new Vec3(at.x, Math.sin(tilt) * d, at.z + Math.cos(tilt) * d);
			eye.lookAt(at);
			var vp = camera.viewProjection(aspect), fits = true;
			for (c in [new Vec3(-5.5, 0.5, -7.9), new Vec3(5.5, 0.5, -7.9), new Vec3(-5.5, 0, 7.9), new Vec3(5.5, 0, 7.9)]) {
				var v = MathTools.transformPoint(vp, c);
				if (Math.abs(v.x) > 0.97 || v.y > 1 - 2 * top || v.y < -1 + 2 * bottom) fits = false;
			}
			if (fits) break;
			d *= 1.02;
		}
		restAt = at;
		// (the window's sun from behind red, low and warm, across the view)
		sun.rotation = side ? Quat.fromEuler(-0.82, -0.55 - Math.PI / 2, 0) : Quat.fromEuler(-0.82, -0.55, 0);
		// (a close look, for checking the models: RR_CLOSE=x,y,z,tx,ty,tz)
		var close = Sys.getEnv("RR_CLOSE");
		if (close != null) {
			var v = [for (s in close.split(",")) Std.parseFloat(s)];
			eye.position = new Vec3(v[0], v[1], v[2]);
			eye.lookAt(new Vec3(v[3], v[4], v[5]));
		}
	}

	// (a jolt when something big goes off: the camera nudged about where it was framed, easing)
	var trauma = 0.0;
	var rest:Null<Vec3> = null;

	function shake(dt:Float) {
		if (framed != lastFramed || rest == null) {
			rest = eye.position;
			lastFramed = framed;
		}
		var r = rest;
		if (r == null) return;
		trauma = Math.max(0, trauma - dt * 1.6);
		// (a small jolt: the whole tray stays in view, nothing missed)
		var k = trauma * trauma * 0.05;
		// (a level opening: from low over the tray, drawn back up to the whole of it)
		introTime = Math.max(0, introTime - dt);
		var i = introTime / 1.2, z = i * i * (3 - 2 * i) * 0.6;
		var a = restAt, t = a;
		var p = new Vec3(t.x + (r.x - a.x) * (1 - z), r.y * (1 - z) * (1 - z * 0.7), t.z + (r.z - a.z) * (1 - z));
		eye.position = new Vec3(p.x + Math.sin(time * 43) * k, p.y + Math.sin(time * 37 + 1) * k, p.z + Math.sin(time * 31 + 2) * k);
		if (Sys.getEnv("RR_CLOSE") == null) eye.lookAt(t);
		if (replaying.peek()) replayCamera();
	}

	var lastFramed = -2.0;
	var restAt = new Vec3(0, 0, 0);
	var introTime = 0.0;

	// (the lens: sharp across the tray's middle band, soft at the frame's top and bottom)
	function focus() {
		var t = tilt;
		if (t == null) return;
		if (replaying.peek()) {
			t.top = 0.34;
			t.bottom = 0.6;
			t.amount = 0.6;
			return;
		}
		var side = width.peek() / Math.max(1, height.peek()) > 1.15;
		var near = project(side ? new Vec3(5, 0, 0) : new Vec3(0, 0, 6.5)), far = project(side ? new Vec3(-5, 0, 0) : new Vec3(0, 0, -6.5));
		var h = height.peek();
		t.top = Math.max(0, far.y / h - 0.06);
		t.bottom = Math.min(1, near.y / h + 0.04);
		t.amount = 0.8;
	}

	// a point of the field on the box, in points
	public function project(p:Vec3):{x:Float, y:Float} {
		var w = width.peek(), h = height.peek();
		var v = MathTools.transformPoint(camera.viewProjection(w / Math.max(1, h)), p);
		return {x: (v.x + 1) / 2 * w, y: (1 - v.y) / 2 * h};
	}

	// a point of the box (points) to the floor
	final ray = new helder.scene.Camera.CameraRay();

	public function floor(x:Float, y:Float):Null<Vec3> {
		var w = width.peek(), h = height.peek();
		camera.rayInto(x / w * 2 - 1, 1 - y / h * 2, w / Math.max(1, h), ray);
		if (ray.dir.y > -1e-4) return null;
		var t = -ray.origin.y / ray.dir.y;
		return ray.origin + ray.dir * t;
	}

	// ---- touches on the field

	var downX = 0.0;
	var downY = 0.0;
	public var downOn(default, null) = -1;
	public var moving(default, null) = -1;
	public var dragTo:Null<Vec3> = null;

	public function down(x:Float, y:Float) {
		// (a touch ends the opening's fly-in: what is under the finger is where it shows)
		if (introTime > 0) {
			introTime = 0;
			shake(0);
		}
		downX = x;
		downY = y;
		dragTo = null;
		if (replaying.peek()) {
			endReplay();
			return;
		}
		var s = screen.peek();
		if (s == "deploy") {
			moving = pick(x, y, false);
		} else if (s == "battle" && sim.started && sim.step == 0 && pick(x, y, false) >= 0) {
			// (rewound to the very start: squads put where they stand, as before the battle)
			moving = pick(x, y, false);
			playing(false);
			card(false);
			selected(-1);
		} else if (s == "battle") {
			downOn = pick(x, y, true);
			if (downOn >= 0 && !sim.canOrder(downOn)) downOn = -1;
		}
	}

	public function move(x:Float, y:Float) {
		var s = screen.peek();
		if (s == "deploy" && moving >= 0) {
			var p = floor(x, y);
			if (p != null) sim.place(moving, p.x, p.z);
		} else if (s == "battle" && moving >= 0) {
			var p = floor(x, y);
			if (p != null) {
				sim.replace(moving, p.x, p.z);
				wasAlive = sim.alive.copy();
			}
		} else if (s == "battle" && downOn >= 0) {
			var moved = (x - downX) * (x - downX) + (y - downY) * (y - downY) > 20 * 20;
			if (moved) dragTo = floor(x, y);
		}
	}

	public function up(x:Float, y:Float) {
		var s = screen.peek();
		var moved = (x - downX) * (x - downX) + (y - downY) * (y - downY) > 20 * 20;
		if (s == "battle" && moving >= 0) {} else if (s == "battle" && !sim.over() || s == "battle" && card.peek() == false) {
			var p = floor(x, y);
			if (downOn >= 0 && moved && p != null)
				give(downOn, p)
			else if (downOn >= 0 && !moved) {
				if (downOn >= Sim.PROP && !aims(downOn)) give(downOn, new Vec3(0, 0, 0)) else selected(selected.peek() == downOn ? -1 : downOn);
			} else if (downOn < 0 && !moved && selected.peek() >= 0 && p != null)
				give(selected.peek(), p);
		}
		moving = -1;
		downOn = -1;
		dragTo = null;
	}

	// a touch the system took back: nothing given, nothing chosen by it
	public function cancel() {
		moving = -1;
		downOn = -1;
		dragTo = null;
	}

	// whether a prop needs a place (a marble, a tower, a catapult)
	public function aims(who:Int):Bool {
		if (who < Sim.PROP) return true;
		var t = sim.props[who - Sim.PROP].def.type;
		return t == Sim.MARBLE || t == Sim.TOWER || t == Sim.CATAPULT || t == Sim.TOP;
	}

	function give(who:Int, p:Vec3) {
		if (!sim.canOrder(who)) return;
		if (sim.over()) card(false);
		sim.order(who, p.x, p.z);
		Sounds.play("tick", 0.5, 1.0);
		selected(-1);
		playing(true);
	}

	// what is under a point: a blue squad (its badge, or near its middle), a blue prop; -1 nothing
	function pick(x:Float, y:Float, withProps:Bool):Int {
		// (a label under the finger: exactly that one, the props' tags over the badges)
		var ns = sim.sqTeam.length;
		if (labelOn.length == ns + sim.props.length) {
			var k = labelOn.length;
			while (k-- > 0) {
				if (!labelOn[k] || Math.abs(x - labelX[k]) > labelW[k] + 5 || Math.abs(y - labelY[k]) > labelH[k] + 5) continue;
				if (k < ns) {
					if (sim.sqTeam[k] == 0) return k;
				} else if (withProps) {
					var p = sim.props[k - ns];
					if (p.def.team == 0 && p.firedAt < 0) return Sim.PROP + p.index;
				}
			}
		}
		var best = -1, bd = 56.0 * 56.0;
		for (s in 0...sim.sqTeam.length) {
			if (sim.sqTeam[s] != 0 || (sim.started && sim.standing(s) == 0)) continue;
			var c = project(sim.middle(s)), b = label(s);
			var d = Math.min((c.x - x) * (c.x - x) + (c.y - y) * (c.y - y), (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y));
			if (d < bd) {
				bd = d;
				best = s;
			}
		}
		if (withProps)
			for (p in sim.props) {
				if (p.def.team != 0 || p.firedAt >= 0) continue;
				var c = propSpot(p);
				var d = (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y);
				if (d < bd * 1.4) {
					bd = d;
					best = Sim.PROP + p.index;
				}
			}
		return best;
	}

	// ---- what the HUD reads

	// ---- the labels: each squad's badge and each prop's tag (squads first,
	// then the props), pushed apart so none covers another; each tied by a
	// line to what it names (its anchor). In points, their middles
	public final labelX:Array<Float> = [];
	public final labelY:Array<Float> = [];
	public final labelW:Array<Float> = [];
	public final labelH:Array<Float> = [];
	public final labelOn:Array<Bool> = [];
	public final anchorX:Array<Float> = [];
	public final anchorY:Array<Float> = [];
	final wantX:Array<Float> = [];
	final wantY:Array<Float> = [];

	function layoutLabels(dt:Float) {
		var ns = sim.sqTeam.length, n = ns + sim.props.length;
		var fresh = labelOn.length != n;
		if (fresh)
			for (a in [labelX, labelY, labelW, labelH, anchorX, anchorY, wantX, wantY]) {
				a.resize(0);
				for (_ in 0...n)
					a.push(0.0);
			}
		labelOn.resize(n);
		var s = screen.peek();
		for (k in 0...n) {
			if (k < ns) {
				var m = sim.middle(k), air = sim.sqKind[k] == Sim.HELI;
				var a = project(new Vec3(m.x, air ? Sim.ALT : 0, m.z)), b = badge(k);
				anchorX[k] = a.x;
				anchorY[k] = a.y;
				wantX[k] = b.x;
				wantY[k] = b.y;
				labelW[k] = sim.sqTeam[k] == 0 ? 40 : 30;
				labelH[k] = 13;
				labelOn[k] = !sim.started || sim.standing(k) > 0;
			} else {
				var p = sim.props[k - ns], a = propSpot(p);
				anchorX[k] = a.x;
				anchorY[k] = a.y;
				wantX[k] = a.x;
				wantY[k] = a.y - 26;
				labelW[k] = 38;
				labelH[k] = 14;
				labelOn[k] = s == "battle" && p.firedAt < 0 && (p.def.team == 0 || p.def.at - sim.step < 60 * 4);
			}
		}
		// (overlaps undone, a few rounds: up or down rather than sideways, as labels are wide)
		for (_ in 0...10) {
			var moved = false;
			for (i in 0...n) {
				if (!labelOn[i]) continue;
				for (j in i + 1...n) {
					if (!labelOn[j]) continue;
					var dx = wantX[j] - wantX[i], dy = wantY[j] - wantY[i];
					var ox = labelW[i] + labelW[j] + 4 - Math.abs(dx), oy = labelH[i] + labelH[j] + 4 - Math.abs(dy);
					if (ox <= 0 || oy <= 0) continue;
					moved = true;
					if (oy * 1.5 < ox) {
						var d = (dy > 0 || (dy == 0 && anchorY[j] >= anchorY[i]) ? 1 : -1) * (oy / 2 + 0.5);
						wantY[i] -= d;
						wantY[j] += d;
					} else {
						var d = (dx > 0 || (dx == 0 && j > i) ? 1 : -1) * (ox / 2 + 0.5);
						wantX[i] -= d;
						wantX[j] += d;
					}
				}
			}
			if (!moved) break;
		}
		var w = width.peek();
		for (k in 0...n) {
			var tx = Math.max(labelW[k] + 4, Math.min(w - labelW[k] - 4, wantX[k])), ty = wantY[k];
			if (!Math.isFinite(tx + ty)) continue;
			if (!Math.isFinite(labelX[k] + labelY[k])) fresh = true;
			// (eased there, so they glide aside rather than jump)
			if (fresh || Math.abs(tx - labelX[k]) + Math.abs(ty - labelY[k]) > 120) {
				labelX[k] = tx;
				labelY[k] = ty;
			} else {
				var e = Math.min(1, dt * 14);
				labelX[k] += (tx - labelX[k]) * e;
				labelY[k] += (ty - labelY[k]) * e;
			}
		}
	}

	// label k's middle and what it is tied to (its anchor), in points
	public function label(k:Int):{x:Float, y:Float, ax:Float, ay:Float, on:Bool} {
		if (k >= labelOn.length) return {x: -200, y: -200, ax: -200, ay: -200, on: false};
		var x = labelX[k], y = labelY[k], ax = anchorX[k], ay = anchorY[k];
		// (before the camera has a size: nowhere)
		if (!Math.isFinite(x + y + ax + ay)) return {x: -200, y: -200, ax: -200, ay: -200, on: false};
		return {x: x, y: y, ax: ax, ay: ay, on: labelOn[k]};
	}

	// a squad's badge, in points: blue's below their squad, red's above
	public function badge(s:Int):{x:Float, y:Float} {
		var m = sim.middle(s);
		var air = sim.sqKind[s] == Sim.HELI;
		var c = project(new Vec3(m.x, air ? Sim.ALT : 0, m.z));
		return sim.sqTeam[s] == 0 ? {x: c.x, y: c.y + 30} : {x: c.x, y: c.y - (air ? 40 : 26)};
	}

	// where a prop's marker shows (over its moving part)
	public function propSpot(p:Prop):{x:Float, y:Float} {
		var d = p.def;
		var at = switch d.type {
			case Sim.MARBLE: new Vec3(d.x, 1.6, d.z);
			case Sim.DOMINO:
				var a = p.along(d.count * 0.21);
				new Vec3(a.x, 0.9, a.z);
			case Sim.TRAIN: new Vec3(d.x, 0.7, d.z);
			case Sim.JACK: new Vec3(d.x, 0.9, d.z);
			case Sim.TOWER: new Vec3(d.x, 0.4 * d.count + 0.3, d.z);
			case Sim.TOP: new Vec3(d.x, 0.7, d.z);
			case _: new Vec3(d.x, 0.6, d.z);
		}
		return project(at);
	}

	public static function verb(type:Int):String
		return ["Roll", "Tip", "Start", "Pop", "Push", "Fling", "Spin"][type];

	public static function propName(type:Int):String
		return ["Marble", "Dominoes", "Train", "Jack-in-the-box", "Block tower", "Catapult", "Spinning top"][type];

	public static function kindName(k:Int):String
		return ["Grunts", "Riflemen", "Tin tank", "Jeeps", "Helicopters", "Bazookas", "Robots"][k];

	// ---- the flow

	public function begin() {
		sim.start();
		clearEvents();
		// (for checking: RR_ORDER=who,x,z,seconds given at the start)
		var o = Sys.getEnv("RR_ORDER");
		if (o != null) {
			var v = [for (s in o.split(",")) Std.parseFloat(s)];
			sim.orders.push({who: Std.int(v[0]), x: v[1], z: v[2], step: Std.int(v[3] * 60 / Sim.KEY) * Sim.KEY});
		}
		wasAlive = sim.alive.copy();
		screen("battle");
		playing(true);
		acc = 0;
	}

	public function openLevel(n:Int) {
		load(n);
		screen("deploy");
	}

	public function retry() {
		load(levelIndex.peek());
		screen("deploy");
	}

	public function next() {
		var n = levelIndex.peek() + 1;
		if (n < Levels.levels.length) openLevel(n) else screen("levels");
	}

	public function togglePlay() {
		if (screen.peek() != "battle") return;
		if (sim.over()) {
			card(true);
			return;
		}
		selected(-1);
		if (!playing.peek()) sim.resume();
		playing(!playing.peek());
	}

	// the timeline dragged to share f of its span
	public function scrub(f:Float) {
		if (!sim.started) return;
		playing(false);
		card(false);
		selected(-1);
		var before = sim.step;
		// (near the left end: the very start, where squads can be put elsewhere)
		sim.seek(f < 0.015 ? 0 : Std.int(Math.max(0, Math.min(1, f)) * sim.span()));
		if (sim.step != before) Sounds.play("whir", 0.35, sim.step < before ? 0.8 : 1.1);
		wasAlive = sim.alive.copy();
	}

	// back to just before it went wrong: a second before blue first fell behind (the start, if it always was)
	public function rewindToTrouble() {
		card(false);
		var at = 0;
		for (k in 0...sim.ahead.length)
			if (sim.ahead[k] < -0.04) {
				at = Std.int(Math.max(0, k * Sim.KEY - 60));
				break;
			}
		scrub(at / sim.span());
	}

	// a room's levels open once any level of the room before is won (the first room's: always)
	public function unlocked(n:Int):Bool {
		var room = Std.int(Math.min(Levels.settings.length - 1, n / 3));
		if (room == 0) return true;
		var b = best.peek();
		for (i in (room - 1) * 3...room * 3)
			if (i < b.length && b[i] > 0) return true;
		return false;
	}

	// ---- textures, made in code

	static function mix(a:Int, b:Int, t:Float):Int {
		var r = Std.int(((a >> 16) & 255) * (1 - t) + ((b >> 16) & 255) * t);
		var g = Std.int(((a >> 8) & 255) * (1 - t) + ((b >> 8) & 255) * t);
		var bl = Std.int((a & 255) * (1 - t) + (b & 255) * t);
		return (r << 16) | (g << 8) | bl;
	}

	static function hash(x:Int, y:Int):Float {
		var h = x * 374761393 + y * 668265263;
		h = (h ^ (h >>> 13)) * 1274126177;
		h = h ^ (h >>> 16);
		return (h & 0xffff) / 65535;
	}

	static function noise(x:Float, y:Float):Float {
		var ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
		var a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1);
		var ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
		return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
	}

	// the room around, for the light it gives and the reflections: walls in
	// the setting's colour, a bright window behind red's left, the ceiling
	// lighter, the floor below
	static function envFor(d:Device, set:Levels.Setting):Null<Environment> {
		var w = 256, h = 128;
		var px = Bytes.alloc(w * h * 4);
		var wall = set.sky, flo = set.floor, lit = set.light;
		for (y in 0...h)
			for (x in 0...w) {
				var u = x / w, v = y / h;
				var c = v < 0.5 ? mix(wall, 0xFFFFFF, Math.max(0, 0.35 - v) * 1.4) : mix(flo, 0x000000, (v - 0.5) * 0.6);
				// (the window: a bright pane, its bars)
				var wu = (u - 0.62) / 0.09, wv = (v - 0.33) / 0.13;
				if (Math.abs(wu) < 1 && Math.abs(wv) < 1) {
					c = Math.abs(wu) < 0.06 || Math.abs(wv) < 0.06 ? mix(wall, 0xFFFFFF, 0.4) : lit;
				}
				var o = (y * w + x) * 4;
				px.set(o, (c >> 16) & 255);
				px.set(o + 1, (c >> 8) & 255);
				px.set(o + 2, c & 255);
				px.set(o + 3, 255);
			}
		return new Environment(d, Images.mipmapped(d, w, h, px), w);
	}
}
