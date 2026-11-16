import helder.gfx.Device;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.math.Quat;
import helder.scene.render.Material;
import helder.scene.render.Mesh;

// The toys, modelled in code: each a mesh of a few materials built from
// shapes (boxes with rounded edges, cylinders, spheres, cones, tori) placed,
// scaled and turned, smooth where they are round. The soldiers are moulded
// plastic of one colour, tinted per side by their instances (InstancedMesh's
// colour: white plastic here), standing on the classic oval base; the tin
// toys painted tin; the props wood, glass, paper and painted metal. Sizes in
// metres of the field (a soldier 0.42 tall), each origin where the
// simulation's body is: the soldiers' at their middle, 0.21 above their feet.
class Toys {
	public final device:Device;

	// (the soldiers' moulded plastic: white, so an instance's colour is its colour)
	public final plastic = new Material("plastic", new Vec4(1, 1, 1, 1), 0, 0.42);
	public final tin = new Material("tin", new Vec4(1, 1, 1, 1), 0.55, 0.32);
	public final rubber = new Material("rubber", new Vec4(0.07, 0.07, 0.075, 1), 0, 0.85);
	public final steel = new Material("steel", new Vec4(0.62, 0.62, 0.64, 1), 1, 0.3);
	public final brass = new Material("brass", new Vec4(0.85, 0.66, 0.32, 1), 1, 0.28);
	public final glass = new Material("glass", new Vec4(0.08, 0.1, 0.12, 1), 0, 0.05);

	public function new(device:Device) {
		this.device = device;
		plastic.clearcoat = 0.25;
		plastic.clearcoatRoughness = 0.35;
		tin.clearcoat = 0.6;
		tin.clearcoatRoughness = 0.15;
		glass.clearcoat = 1;
		glass.clearcoatRoughness = 0.02;
	}

	public static function mat(name:String, rgb:Int, roughness = 0.5, metallic = 0.0):Material
		return new Material(name, new Vec4(lin((rgb >> 16) & 255), lin((rgb >> 8) & 255), lin(rgb & 255), 1), metallic, roughness);

	// an sRGB channel in linear light
	public static inline function lin(c:Float):Float
		return Math.pow(c / 255, 2.2);

	// ---- the soldiers

	// a plastic army man charging, bayonet forward (+z his front)
	public function grunt():Mesh {
		var b = new Builder();
		var foot = -0.21;
		armyBase(b, foot);
		// (legs mid-stride)
		b.capsule(new Vec3(-0.035, foot + 0.1, 0.045), 0.026, 0.07, Quat.fromEuler(0.45, 0, 0.05));
		b.capsule(new Vec3(0.035, foot + 0.1, -0.04), 0.026, 0.07, Quat.fromEuler(-0.35, 0, -0.05));
		b.ellipsoid(new Vec3(-0.035, foot + 0.02, 0.09), new Vec3(0.026, 0.02, 0.045));
		b.ellipsoid(new Vec3(0.035, foot + 0.02, -0.075), new Vec3(0.026, 0.02, 0.045));
		// (the torso leaning in, the belt, the pack)
		b.roundBox(new Vec3(0, foot + 0.255, 0.02), new Vec3(0.07, 0.085, 0.045), 0.03, Quat.fromEuler(0.25, 0, 0));
		b.roundBox(new Vec3(0, foot + 0.18, 0.005), new Vec3(0.068, 0.014, 0.046), 0.01, Quat.fromEuler(0.2, 0, 0));
		b.roundBox(new Vec3(0, foot + 0.27, -0.055), new Vec3(0.05, 0.055, 0.025), 0.015, Quat.fromEuler(0.25, 0, 0));
		// (the head, the helmet and its brim)
		b.sphere(new Vec3(0, foot + 0.375, 0.06), 0.04);
		b.ellipsoid(new Vec3(0, foot + 0.39, 0.055), new Vec3(0.05, 0.034, 0.052));
		b.cylinder(new Vec3(0, foot + 0.378, 0.055), 0.058, 0.006, Quat.fromEuler(0.12, 0, 0));
		// (the arms and the rifle, bayonet forward)
		b.capsule(new Vec3(-0.07, foot + 0.27, 0.07), 0.02, 0.05, Quat.fromEuler(1.1, 0, -0.3));
		b.capsule(new Vec3(0.065, foot + 0.24, 0.07), 0.02, 0.05, Quat.fromEuler(1.25, 0, 0.35));
		rifle(b, new Vec3(0, foot + 0.24, 0.15), Quat.fromEuler(-0.15, 0, 0));
		var m = new Mesh();
		b.into(m, device, plastic);
		return m;
	}

	// a plastic rifleman down on one knee, aiming
	public function rifleman():Mesh {
		var b = new Builder();
		var foot = -0.21;
		armyBase(b, foot);
		// (the knee down, the other leg up, the boots)
		b.capsule(new Vec3(0.04, foot + 0.045, -0.02), 0.027, 0.06, Quat.fromEuler(1.5, 0, 0));
		b.capsule(new Vec3(0.04, foot + 0.07, -0.085), 0.025, 0.045, Quat.fromEuler(0.2, 0, 0));
		b.capsule(new Vec3(-0.04, foot + 0.1, 0.06), 0.027, 0.055, Quat.fromEuler(-1.2, 0, 0));
		b.capsule(new Vec3(-0.04, foot + 0.055, 0.105), 0.025, 0.045, Quat.fromEuler(0.1, 0, 0));
		b.ellipsoid(new Vec3(-0.04, foot + 0.02, 0.12), new Vec3(0.026, 0.02, 0.045));
		// (the torso upright over the knee, a pack)
		b.roundBox(new Vec3(0, foot + 0.205, 0), new Vec3(0.07, 0.085, 0.045), 0.03, Quat.fromEuler(0.05, 0, 0));
		b.roundBox(new Vec3(0, foot + 0.215, -0.065), new Vec3(0.052, 0.06, 0.026), 0.015);
		b.sphere(new Vec3(0, foot + 0.33, 0.015), 0.04);
		b.ellipsoid(new Vec3(0, foot + 0.345, 0.01), new Vec3(0.05, 0.034, 0.052));
		b.cylinder(new Vec3(0, foot + 0.333, 0.01), 0.058, 0.006);
		// (the arms up to the rifle at his cheek, levelled)
		b.capsule(new Vec3(-0.06, foot + 0.27, 0.07), 0.02, 0.05, Quat.fromEuler(1.45, 0, -0.5));
		b.capsule(new Vec3(0.055, foot + 0.27, 0.035), 0.02, 0.045, Quat.fromEuler(1.3, 0, 0.6));
		rifle(b, new Vec3(-0.025, foot + 0.3, 0.13), Quat.identity(), false);
		var m = new Mesh();
		b.into(m, device, plastic);
		return m;
	}

	// a plastic bazooka man down on one knee, the tube on his shoulder
	public function bazooka():Mesh {
		var b = new Builder();
		var foot = -0.21;
		armyBase(b, foot);
		b.capsule(new Vec3(0.04, foot + 0.045, -0.02), 0.027, 0.06, Quat.fromEuler(1.5, 0, 0));
		b.capsule(new Vec3(0.04, foot + 0.07, -0.085), 0.025, 0.045, Quat.fromEuler(0.2, 0, 0));
		b.capsule(new Vec3(-0.04, foot + 0.1, 0.06), 0.027, 0.055, Quat.fromEuler(-1.2, 0, 0));
		b.capsule(new Vec3(-0.04, foot + 0.055, 0.105), 0.025, 0.045, Quat.fromEuler(0.1, 0, 0));
		b.ellipsoid(new Vec3(-0.04, foot + 0.02, 0.12), new Vec3(0.026, 0.02, 0.045));
		b.roundBox(new Vec3(0, foot + 0.205, 0), new Vec3(0.07, 0.085, 0.045), 0.03, Quat.fromEuler(0.05, 0, 0));
		b.sphere(new Vec3(0, foot + 0.33, 0.015), 0.04);
		b.ellipsoid(new Vec3(0, foot + 0.345, 0.01), new Vec3(0.05, 0.034, 0.052));
		b.cylinder(new Vec3(0, foot + 0.333, 0.01), 0.058, 0.006);
		// (the tube on his right shoulder, aimed up a little; his hands on its grips)
		var q = Quat.fromEuler(Math.PI / 2 - 0.25, 0, 0);
		b.cylinder(new Vec3(0.07, foot + 0.31, 0.02), 0.032, 0.17, q, 14);
		b.cylinder(new Vec3(0.07, foot + 0.355, 0.19), 0.04, 0.025, q, 14);
		b.roundBox(new Vec3(0.07, foot + 0.27, 0.05), new Vec3(0.01, 0.03, 0.012), 0.006);
		b.capsule(new Vec3(0.05, foot + 0.255, 0.04), 0.02, 0.04, Quat.fromEuler(1.2, 0, 0.3));
		b.capsule(new Vec3(-0.04, foot + 0.27, 0.06), 0.02, 0.05, Quat.fromEuler(1.3, 0, -0.9));
		var m = new Mesh();
		b.into(m, device, plastic);
		return m;
	}

	// a rocket: a body, a nose, fins (+z its front)
	public function rocket():Mesh {
		var b = new Builder(), n = new Builder();
		b.cylinder(new Vec3(0, 0, 0), 0.028, 0.07, Quat.fromEuler(Math.PI / 2, 0, 0), 12);
		n.cone(new Vec3(0, 0, 0.1), 0.028, 0.06, Quat.fromEuler(Math.PI / 2, 0, 0), 12);
		for (k in 0...4)
			b.roundBox(Quat.axisAngle(new Vec3(0, 0, 1), k * Math.PI / 2).rotate(new Vec3(0.035, 0, -0.06)), new Vec3(0.02, 0.003, 0.02), 0.002,
				Quat.axisAngle(new Vec3(0, 0, 1), k * Math.PI / 2));
		var m = new Mesh();
		b.into(m, device, mat("rocket", 0x4A5D23, 0.5, 0.3));
		n.into(m, device, mat("warhead", 0xD62828, 0.35, 0.3));
		return m;
	}

	// a wooden spinning top, painted in rings: its body a cone over a disc, its stem above
	public function top():Mesh {
		var m = new Mesh();
		var rings = [0xE63946, 0xF1FAEE, 0x457B9D, 0xFFB703];
		for (k in 0...4) {
			var b = new Builder();
			var y0 = -0.12 + k * 0.06;
			var r0 = 0.06 + k * 0.06, r1 = 0.06 + (k + 1) * 0.06;
			b.cylinder(new Vec3(0, y0 + 0.03, 0), (r0 + r1) / 2, 0.03, Quat.identity(), 28);
			b.into(m, device, mat("top paint", rings[k], 0.3));
		}
		var w = new Builder();
		w.cone(new Vec3(0, -0.2, 0), 0.08, 0.1, Quat.fromEuler(Math.PI, 0, 0), 20);
		w.ellipsoid(new Vec3(0, 0.12, 0), new Vec3(0.25, 0.05, 0.25), null, 28, 8);
		w.cylinder(new Vec3(0, 0.22, 0), 0.025, 0.08, Quat.identity(), 12);
		w.sphere(new Vec3(0, 0.3, 0), 0.035);
		w.into(m, device, mat("top wood", 0xC89B6D, 0.45));
		return m;
	}

	// a wind-up tin robot: a boxy body with rivets and a dial, a head with an antenna, arms out, the key in its back
	public function robot():Mesh {
		var b = new Builder(), d = new Builder(), k = new Builder(), e = new Builder();
		b.roundBox(new Vec3(0, -0.02, 0), new Vec3(0.15, 0.13, 0.11), 0.025);
		b.roundBox(new Vec3(0, 0.19, 0), new Vec3(0.1, 0.075, 0.09), 0.025);
		for (side in [-1, 1]) {
			b.roundBox(new Vec3(side * 0.07, -0.22, 0.01), new Vec3(0.045, 0.075, 0.06), 0.015);
			b.capsule(new Vec3(side * 0.19, 0.0, 0.05), 0.03, 0.06, Quat.fromEuler(1.2, 0, side * 0.3));
			d.cylinder(new Vec3(side * 0.2, -0.04, 0.13), 0.035, 0.012, Quat.fromEuler(Math.PI / 2, 0, 0), 10);
		}
		d.roundBox(new Vec3(0, -0.29, 0.02), new Vec3(0.13, 0.012, 0.08), 0.008);
		e.sphere(new Vec3(-0.04, 0.2, 0.09), 0.022);
		e.sphere(new Vec3(0.04, 0.2, 0.09), 0.022);
		d.roundBox(new Vec3(0, 0.15, 0.09), new Vec3(0.05, 0.008, 0.004), 0.003);
		k.cylinder(new Vec3(0, 0.3, 0), 0.006, 0.05, Quat.identity(), 6);
		k.sphere(new Vec3(0, 0.35, 0), 0.018);
		k.cylinder(new Vec3(0, -0.02, 0.112), 0.04, 0.006, Quat.fromEuler(Math.PI / 2, 0, 0), 16);
		k.cylinder(new Vec3(0, 0.0, -0.14), 0.01, 0.04, Quat.fromEuler(Math.PI / 2, 0, 0), 8);
		k.ellipsoid(new Vec3(-0.035, 0.0, -0.18), new Vec3(0.035, 0.028, 0.007));
		k.ellipsoid(new Vec3(0.035, 0.0, -0.18), new Vec3(0.035, 0.028, 0.007));
		var m = new Mesh();
		b.into(m, device, tin);
		d.into(m, device, rubber);
		k.into(m, device, brass);
		var glow = mat("eyes", 0xFFE08A, 0.2);
		glow.emissive = new Vec3(2.4, 1.8, 0.6);
		e.into(m, device, glow);
		return m;
	}

	// a blast's flash: a hot ball, its light bloomed
	public function flash():Mesh {
		var b = new Builder();
		b.sphere(new Vec3(0, 0, 0), 1, 16, 10);
		var m = new Mesh();
		var hot = mat("flash", 0xFFD27A, 1.0);
		hot.emissive = new Vec3(9, 5.5, 2.0);
		hot.castShadows = false;
		b.into(m, device, hot);
		return m;
	}

	// the oval base army men stand on
	function armyBase(b:Builder, foot:Float) {
		b.cylinder(new Vec3(0, foot + 0.008, 0.01), 1, 0.008, Quat.identity(), 28, new Vec3(0.085, 1, 0.12));
	}

	function rifle(b:Builder, at:Vec3, q:Quat, bayonet = true) {
		var f = q.rotate(new Vec3(0, 0, 1));
		b.roundBox(at, new Vec3(0.013, 0.02, 0.07), 0.006, q);
		b.cylinder(at + f * 0.11 + q.rotate(new Vec3(0, 0.01, 0)), 0.007, 0.06, q * Quat.fromEuler(Math.PI / 2, 0, 0), 10);
		b.roundBox(at - f * 0.075 + q.rotate(new Vec3(0, -0.012, 0)), new Vec3(0.012, 0.026, 0.028), 0.006, q * Quat.fromEuler(-0.4, 0, 0));
		if (bayonet) b.cone(at + f * 0.2 + q.rotate(new Vec3(0, 0.01, 0)), 0.006, 0.05, q * Quat.fromEuler(Math.PI / 2, 0, 0), 8);
	}

	// a wind-up tin tank: hull, turret, gun, tracks and wheels, the key behind
	public function tank():Mesh {
		var b = new Builder(), d = new Builder(), k = new Builder();
		var y0 = -0.15;
		b.roundBox(new Vec3(0, y0 + 0.13, 0), new Vec3(0.2, 0.06, 0.34), 0.03);
		b.roundBox(new Vec3(0, y0 + 0.19, 0.2), new Vec3(0.17, 0.02, 0.1), 0.02, Quat.fromEuler(-0.35, 0, 0));
		b.cylinder(new Vec3(0, y0 + 0.235, -0.03), 0.13, 0.05, Quat.identity(), 28);
		b.ellipsoid(new Vec3(0, y0 + 0.28, -0.03), new Vec3(0.11, 0.035, 0.11));
		b.cylinder(new Vec3(0, y0 + 0.24, 0.2), 0.022, 0.17, Quat.fromEuler(Math.PI / 2 - 0.06, 0, 0), 14);
		b.cylinder(new Vec3(0, y0 + 0.25, 0.37), 0.03, 0.025, Quat.fromEuler(Math.PI / 2 - 0.06, 0, 0), 14);
		b.cylinder(new Vec3(0.05, y0 + 0.315, -0.07), 0.03, 0.02, Quat.identity(), 14);
		for (side in [-1, 1]) {
			d.roundBox(new Vec3(side * 0.225, y0 + 0.07, 0), new Vec3(0.055, 0.07, 0.36), 0.055);
			for (w in 0...5)
				k.cylinder(new Vec3(side * 0.282, y0 + 0.065, -0.26 + w * 0.13), 0.045, 0.008, Quat.fromEuler(0, 0, Math.PI / 2), 18);
		}
		// (the wind-up key behind)
		k.cylinder(new Vec3(0, y0 + 0.14, -0.38), 0.012, 0.05, Quat.fromEuler(Math.PI / 2, 0, 0), 10);
		k.ellipsoid(new Vec3(-0.04, y0 + 0.14, -0.43), new Vec3(0.04, 0.03, 0.008));
		k.ellipsoid(new Vec3(0.04, y0 + 0.14, -0.43), new Vec3(0.04, 0.03, 0.008));
		var m = new Mesh();
		b.into(m, device, tin);
		d.into(m, device, rubber);
		k.into(m, device, brass);
		return m;
	}

	// a little toy jeep: body, bonnet, seats, windscreen frame, wheels, a spare
	public function jeep():Mesh {
		var b = new Builder(), w = new Builder(), s = new Builder();
		var y0 = -0.1;
		b.roundBox(new Vec3(0, y0 + 0.1, 0), new Vec3(0.13, 0.045, 0.25), 0.03);
		b.roundBox(new Vec3(0, y0 + 0.135, 0.15), new Vec3(0.12, 0.025, 0.1), 0.025);
		b.roundBox(new Vec3(0, y0 + 0.15, -0.06), new Vec3(0.1, 0.035, 0.03), 0.015);
		b.roundBox(new Vec3(0, y0 + 0.15, -0.16), new Vec3(0.1, 0.035, 0.03), 0.015);
		for (side in [-1, 1]) {
			b.roundBox(new Vec3(side * 0.135, y0 + 0.1, 0.17), new Vec3(0.03, 0.012, 0.07), 0.012);
			b.roundBox(new Vec3(side * 0.135, y0 + 0.1, -0.17), new Vec3(0.03, 0.012, 0.07), 0.012);
		}
		s.roundBox(new Vec3(0, y0 + 0.2, 0.045), new Vec3(0.12, 0.05, 0.006), 0.006, Quat.fromEuler(-0.3, 0, 0));
		s.cylinder(new Vec3(0, y0 + 0.17, 0.0), 0.004, 0.04, Quat.identity(), 6);
		for (x in [-1, 1])
			for (z in [-1, 1])
				w.cylinder(new Vec3(x * 0.13, y0 + 0.055, z * 0.17), 0.055, 0.025, Quat.fromEuler(0, 0, Math.PI / 2), 20);
		w.cylinder(new Vec3(0, y0 + 0.12, -0.27), 0.05, 0.02, Quat.fromEuler(Math.PI / 2, 0, 0), 20);
		var m = new Mesh();
		b.into(m, device, plastic);
		w.into(m, device, rubber);
		s.into(m, device, steel);
		return m;
	}

	// a toy helicopter's body: the cabin's bubble, the tail, the fin, the skids (the rotor apart)
	public function heli():Mesh {
		var b = new Builder(), g = new Builder(), s = new Builder();
		b.ellipsoid(new Vec3(0, 0, 0.05), new Vec3(0.13, 0.12, 0.2));
		b.cylinder(new Vec3(0, 0.03, -0.22), 0.035, 0.17, Quat.fromEuler(Math.PI / 2 + 0.08, 0, 0), 12);
		b.roundBox(new Vec3(0, 0.1, -0.4), new Vec3(0.008, 0.07, 0.05), 0.006, Quat.fromEuler(-0.3, 0, 0));
		b.roundBox(new Vec3(0, 0.03, -0.38), new Vec3(0.08, 0.006, 0.03), 0.005);
		b.cylinder(new Vec3(0, 0.13, 0.02), 0.03, 0.03, Quat.identity(), 12);
		g.ellipsoid(new Vec3(0, 0.03, 0.13), new Vec3(0.105, 0.085, 0.11));
		for (side in [-1, 1]) {
			s.cylinder(new Vec3(side * 0.1, -0.15, 0.05), 0.008, 0.2, Quat.fromEuler(Math.PI / 2, 0, 0), 8);
			s.cylinder(new Vec3(side * 0.085, -0.11, 0.12), 0.006, 0.045, Quat.fromEuler(0, 0, side * 0.35), 6);
			s.cylinder(new Vec3(side * 0.085, -0.11, -0.03), 0.006, 0.045, Quat.fromEuler(0, 0, side * 0.35), 6);
		}
		var m = new Mesh();
		b.into(m, device, plastic);
		g.into(m, device, glass);
		s.into(m, device, steel);
		return m;
	}

	// the main rotor: two blades and the hub (turned by the frame)
	public function rotor():Mesh {
		var b = new Builder();
		b.roundBox(new Vec3(0, 0, 0), new Vec3(0.4, 0.005, 0.025), 0.004);
		b.roundBox(new Vec3(0, 0, 0), new Vec3(0.025, 0.005, 0.4), 0.004);
		b.cylinder(new Vec3(0, 0.01, 0), 0.025, 0.015, Quat.identity(), 12);
		var m = new Mesh();
		b.into(m, device, plastic);
		return m;
	}

	// a foam pellet, a bomb
	public function pellet():Mesh {
		var b = new Builder();
		b.capsule(new Vec3(0, 0, 0), 0.022, 0.025, Quat.fromEuler(Math.PI / 2, 0, 0));
		var m = new Mesh();
		b.into(m, device, mat("foam", 0xFF9F1C, 0.7));
		return m;
	}

	public function bomb():Mesh {
		var b = new Builder(), f = new Builder();
		b.sphere(new Vec3(0, 0, 0), 0.06);
		f.cylinder(new Vec3(0, 0.065, 0), 0.012, 0.015, Quat.identity(), 8);
		var m = new Mesh();
		b.into(m, device, mat("bomb", 0x2A2D34, 0.35, 0.4));
		f.into(m, device, brass);
		return m;
	}

	// ---- the props

	// a glossy swirl marble: a pale glass body, ribbons of colour twisting through its surface
	public function marble(rgb:Int, tint:Int):Mesh {
		var b = new Builder(), c = new Builder();
		b.sphere(new Vec3(0, 0, 0), 0.42, 40, 20);
		for (k in 0...4)
			c.ellipsoid(new Vec3(0, 0, 0), new Vec3(0.428, 0.07, 0.31), Quat.fromEuler(k * 0.8, k * 1.3, 0.5 + k * 0.4), 32, 12);
		var m = new Mesh();
		var g = mat("marble glass", tint, 0.04);
		g.clearcoat = 1;
		g.clearcoatRoughness = 0.02;
		var core = mat("marble swirl", rgb, 0.12);
		core.clearcoat = 1;
		core.clearcoatRoughness = 0.02;
		b.into(m, device, g);
		c.into(m, device, core);
		return m;
	}

	// a hardback book lying flat: covers, the page block, the spine (w across, h thick, d deep), its origin its middle
	public function book(w:Float, h:Float, d:Float, rgb:Int):Mesh {
		var c = new Builder(), p = new Builder();
		var t = 0.025;
		c.roundBox(new Vec3(0, h / 2 - t / 2, 0), new Vec3(w / 2, t / 2, d / 2), 0.008);
		c.roundBox(new Vec3(0, -h / 2 + t / 2, 0), new Vec3(w / 2, t / 2, d / 2), 0.008);
		c.roundBox(new Vec3(-w / 2 + 0.015, 0, 0), new Vec3(0.02, h / 2, d / 2), 0.015);
		p.roundBox(new Vec3(0.01, 0, 0), new Vec3(w / 2 - 0.03, h / 2 - t, d / 2 - 0.02), 0.004);
		var m = new Mesh();
		c.into(m, device, mat("cover", rgb, 0.55));
		p.into(m, device, mat("pages", 0xEFE6D2, 0.8));
		return m;
	}

	// an ivory domino standing (0.34 wide, 0.64 tall, 0.1 thick), its pips on both faces
	public function domino(a:Int, b:Int):Mesh {
		var body = new Builder(), pips = new Builder();
		body.roundBox(new Vec3(0, 0, 0), new Vec3(0.17, 0.32, 0.05), 0.025);
		pips.roundBox(new Vec3(0, 0, 0.05), new Vec3(0.13, 0.006, 0.004), 0.003);
		pips.roundBox(new Vec3(0, 0, -0.05), new Vec3(0.13, 0.006, 0.004), 0.003);
		for (face in [-1, 1])
			for (half in 0...2) {
				var n = half == 0 ? a : b, cy = half == 0 ? 0.16 : -0.16;
				for (q in PIPS[n])
					pips.cylinder(new Vec3(q[0] * 0.075, cy + q[1] * 0.075, face * 0.049), 0.022, 0.003, Quat.fromEuler(Math.PI / 2, 0, 0), 12);
			}
		var m = new Mesh();
		body.into(m, device, mat("ivory", 0xF4EEDF, 0.3));
		pips.into(m, device, mat("pip", 0x1B1B1E, 0.4));
		return m;
	}

	static final PIPS:Array<Array<Array<Float>>> = [
		[], [[0, 0]], [[-1, 1], [1, -1]], [[-1, 1], [0, 0], [1, -1]], [[-1, 1], [1, 1], [-1, -1], [1, -1]],
		[[-1, 1], [1, 1], [0, 0], [-1, -1], [1, -1]], [[-1, 1], [1, 1], [-1, 0], [1, 0], [-1, -1], [1, -1]]
	];

	// a wind-up tin locomotive (front +z): boiler, cab, chimney, cow-catcher, red wheels
	public function engine(rgb:Int):Mesh {
		var b = new Builder(), w = new Builder(), k = new Builder(), d = new Builder();
		b.cylinder(new Vec3(0, 0.0, 0.08), 0.12, 0.17, Quat.fromEuler(Math.PI / 2, 0, 0), 24);
		b.roundBox(new Vec3(0, 0.03, -0.18), new Vec3(0.16, 0.15, 0.1), 0.02);
		b.roundBox(new Vec3(0, 0.2, -0.18), new Vec3(0.19, 0.02, 0.13), 0.015);
		b.roundBox(new Vec3(0, -0.13, 0), new Vec3(0.17, 0.03, 0.3), 0.015);
		d.cylinder(new Vec3(0, 0.16, 0.18), 0.04, 0.06, Quat.identity(), 14);
		d.cylinder(new Vec3(0, 0.23, 0.18), 0.06, 0.015, Quat.identity(), 14);
		d.cone(new Vec3(0, -0.11, 0.31), 0.1, 0.07, Quat.fromEuler(1.2, 0, 0), 4);
		k.cylinder(new Vec3(0, 0.0, 0.26), 0.11, 0.012, Quat.fromEuler(Math.PI / 2, 0, 0), 24);
		k.sphere(new Vec3(0, 0.03, 0.275), 0.03);
		for (side in [-1, 1])
			for (z in [-0.18, 0.0, 0.18])
				w.cylinder(new Vec3(side * 0.16, -0.12, z), 0.075, 0.015, Quat.fromEuler(0, 0, Math.PI / 2), 18);
		var m = new Mesh();
		var paint = mat("engine", rgb, 0.3, 0.4);
		paint.clearcoat = 0.7;
		b.into(m, device, paint);
		w.into(m, device, mat("wheels", 0xC1272D, 0.35, 0.4));
		k.into(m, device, brass);
		d.into(m, device, mat("iron", 0x232326, 0.45, 0.6));
		return m;
	}

	// a tin goods wagon
	public function wagon(rgb:Int):Mesh {
		var b = new Builder(), w = new Builder();
		b.roundBox(new Vec3(0, 0.0, 0), new Vec3(0.16, 0.12, 0.26), 0.02);
		b.roundBox(new Vec3(0, 0.13, 0), new Vec3(0.18, 0.015, 0.28), 0.01);
		b.roundBox(new Vec3(0, -0.13, 0), new Vec3(0.17, 0.03, 0.28), 0.012);
		for (side in [-1, 1])
			for (z in [-0.16, 0.16])
				w.cylinder(new Vec3(side * 0.16, -0.12, z), 0.075, 0.015, Quat.fromEuler(0, 0, Math.PI / 2), 18);
		var m = new Mesh();
		var paint = mat("wagon", rgb, 0.3, 0.4);
		paint.clearcoat = 0.7;
		b.into(m, device, paint);
		w.into(m, device, mat("wheels", 0x2B2B2E, 0.4, 0.5));
		return m;
	}

	// a straight track along z of length: two rails on sleepers
	// a track along a path (world points along it, their headings)
	public function trackAlong(points:Array<{x:Float, z:Float, h:Float}>):Mesh {
		var r = new Builder(), s = new Builder();
		for (k in 0...points.length - 1) {
			var a = points[k], b = points[k + 1];
			var mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2, h = Math.atan2(b.x - a.x, b.z - a.z);
			var len = Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
			var q = Quat.axisAngle(new Vec3(0, 1, 0), h);
			for (side in [-1, 1])
				r.roundBox(new Vec3(mx, 0.025, mz) + q.rotate(new Vec3(side * 0.16, 0, 0)), new Vec3(0.012, 0.012, len / 2 + 0.006), 0.006, q);
			s.roundBox(new Vec3(a.x, 0.008, a.z), new Vec3(0.24, 0.008, 0.03), 0.005, Quat.axisAngle(new Vec3(0, 1, 0), a.h));
		}
		var m = new Mesh();
		r.into(m, device, steel);
		s.into(m, device, mat("sleeper", 0x6E4B33, 0.7));
		return m;
	}

	public function track(length:Float):Mesh {
		var r = new Builder(), s = new Builder();
		for (side in [-1, 1])
			r.roundBox(new Vec3(side * 0.16, 0.025, 0), new Vec3(0.012, 0.012, length / 2), 0.006);
		var n = Std.int(length / 0.22);
		for (k in 0...n + 1)
			s.roundBox(new Vec3(0, 0.008, -length / 2 + k * length / n), new Vec3(0.24, 0.008, 0.03), 0.005);
		var m = new Mesh();
		r.into(m, device, steel);
		s.into(m, device, mat("sleeper", 0x6E4B33, 0.7));
		return m;
	}

	// a jack-in-the-box's box: four painted sides, a crank (the lid and the clown apart)
	public function jackBox():Mesh {
		var m = new Mesh();
		var colors = [0xE63946, 0xF4A261, 0x2A9D8F, 0x457B9D];
		for (k in 0...4) {
			var b = new Builder(), a = k * Math.PI / 2;
			var q = Quat.axisAngle(new Vec3(0, 1, 0), a);
			b.roundBox(q.rotate(new Vec3(0, 0, 0.27)), new Vec3(0.3, 0.3, 0.03), 0.02, q);
			b.into(m, device, mat("side", colors[k], 0.45, 0.2));
		}
		var t = new Builder();
		t.roundBox(new Vec3(0, -0.28, 0), new Vec3(0.3, 0.02, 0.3), 0.01);
		t.cylinder(new Vec3(0.33, 0, 0), 0.015, 0.05, Quat.fromEuler(0, 0, Math.PI / 2), 8);
		t.roundBox(new Vec3(0.38, -0.06, 0), new Vec3(0.01, 0.07, 0.015), 0.008);
		t.sphere(new Vec3(0.39, -0.13, 0), 0.025);
		t.into(m, device, brass);
		return m;
	}

	public function jackLid():Mesh {
		var b = new Builder();
		b.roundBox(new Vec3(0, 0.015, -0.3), new Vec3(0.31, 0.02, 0.31), 0.015);
		var m = new Mesh();
		b.into(m, device, mat("lid", 0xF1FAEE, 0.4, 0.2));
		return m;
	}

	// the clown on his spring (the spring along y from 0 to 1, scaled by the pop)
	public function clown():Mesh {
		var h = new Builder(), n = new Builder(), c = new Builder();
		h.sphere(new Vec3(0, 0.12, 0), 0.12);
		n.sphere(new Vec3(0, 0.12, 0.12), 0.035);
		c.cone(new Vec3(0, 0.3, 0), 0.08, 0.16, Quat.identity(), 16);
		c.sphere(new Vec3(0, 0.39, 0), 0.03);
		c.cylinder(new Vec3(0, 0.01, 0), 0.13, 0.02, Quat.identity(), 18);
		var m = new Mesh();
		h.into(m, device, mat("face", 0xF8E1C8, 0.55));
		n.into(m, device, mat("nose", 0xE5383B, 0.3));
		c.into(m, device, mat("hat", 0x7B2CBF, 0.45));
		return m;
	}

	public function spring():Mesh {
		var b = new Builder();
		for (k in 0...8)
			b.torus(new Vec3(0, k / 8 + 0.06, 0), 0.07, 0.012, 16, 6);
		var m = new Mesh();
		b.into(m, device, steel);
		return m;
	}

	// a wooden letter block (0.4 a side), its letters raised on two faces
	public function block(rgb:Int):Mesh {
		var b = new Builder(), l = new Builder();
		b.roundBox(new Vec3(0, 0, 0), new Vec3(0.2, 0.2, 0.2), 0.03);
		for (face in [new Vec3(0, 0, 1), new Vec3(1, 0, 0), new Vec3(0, 0, -1), new Vec3(-1, 0, 0)]) {
			var q = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(face.x, face.z));
			l.roundBox(face * 0.2, new Vec3(0.13, 0.13, 0.006), 0.006, q);
		}
		var m = new Mesh();
		b.into(m, device, mat("wood", 0xE9C893, 0.55));
		l.into(m, device, mat("paint", rgb, 0.4));
		return m;
	}

	// the catapult: a wooden ruler on a pencil (the ruler's middle at the origin, along z)
	public function ruler():Mesh {
		var b = new Builder(), k = new Builder();
		b.roundBox(new Vec3(0, 0, 0), new Vec3(0.09, 0.012, 0.75), 0.006);
		for (i in 0...30)
			k.roundBox(new Vec3(0.065, 0.013, -0.72 + i * 0.05), new Vec3(i % 2 == 0 ? 0.02 : 0.012, 0.0015, 0.002), 0.001);
		var m = new Mesh();
		b.into(m, device, mat("ruler", 0xD9B26F, 0.55));
		k.into(m, device, mat("ink", 0x222222, 0.6));
		return m;
	}

	public function pencil():Mesh {
		var b = new Builder(), t = new Builder(), e = new Builder();
		b.cylinder(new Vec3(0, 0, 0), 0.05, 0.35, Quat.fromEuler(0, 0, Math.PI / 2), 6);
		t.cone(new Vec3(-0.4, 0, 0), 0.05, 0.1, Quat.fromEuler(0, 0, Math.PI / 2), 6);
		e.cylinder(new Vec3(0.38, 0, 0), 0.05, 0.035, Quat.fromEuler(0, 0, Math.PI / 2), 12);
		var m = new Mesh();
		b.into(m, device, mat("pencil", 0xF6BD18, 0.45));
		t.into(m, device, mat("cedar", 0xD8B07A, 0.7));
		e.into(m, device, mat("ferrule", 0xC7C9CC, 0.3, 1));
		return m;
	}

	public function eraser():Mesh {
		var b = new Builder();
		b.roundBox(new Vec3(0, 0, 0), new Vec3(0.16, 0.1, 0.1), 0.04);
		var m = new Mesh();
		b.into(m, device, mat("eraser", 0xF28AA8, 0.75));
		return m;
	}
}

// A mesh's triangles gathered from shapes, each placed (at), sized and turned (q)
class Builder {
	final p:Array<Float> = [];
	final n:Array<Float> = [];
	final uv:Array<Float> = [];
	final idx:Array<Int> = [];

	public function new() {}

	public function into(m:Mesh, device:Device, material:Material) {
		if (idx.length > 0) m.add(device, p, n, uv, idx, material);
	}

	inline function vert(at:Vec3, q:Quat, local:Vec3, normal:Vec3, u:Float, v:Float) {
		var w = at + q.rotate(local), nn = q.rotate(normal);
		p.push(w.x);
		p.push(w.y);
		p.push(w.z);
		n.push(nn.x);
		n.push(nn.y);
		n.push(nn.z);
		uv.push(u);
		uv.push(v);
	}

	// a box of half extents h, its edges rounded by r: each face a grid whose
	// rows bunch at its rims, each point pushed onto the rounded box (the
	// inner box's nearest point, plus r along the way out); detail: the rows
	// round each edge (2: three, 588 triangles; 1: one, 300; 0: none, a bevel, 108)
	public function roundBox(at:Vec3, h:Vec3, r:Float, ?q:Quat, detail = 2) {
		var qq = q ?? Quat.identity();
		r = Math.max(1e-4, Math.min(r, Math.min(h.x, Math.min(h.y, h.z)) * 0.999));
		var inner = [h.x - r, h.y - r, h.z - r], half = [h.x, h.y, h.z];
		inline function samples(axis:Int):Array<Float> {
			var i = inner[axis];
			return switch detail {
				case 0: [-half[axis], -i, i, half[axis]];
				case 1: [-half[axis], -(i + r * 0.707), -i, i, i + r * 0.707, half[axis]];
				case _: [-half[axis], -(i + r * 0.866), -(i + r * 0.5), -i, i, i + r * 0.5, i + r * 0.866, half[axis]];
			}
		}
		// (each face: its axis, its sign, the two axes across it)
		for (f in [[2, 1, 0, 1], [2, -1, 0, 1], [0, 1, 2, 1], [0, -1, 2, 1], [1, 1, 0, 2], [1, -1, 0, 2]]) {
			var ax = f[0], sign = f[1], ua = f[2], va = f[3];
			var us = samples(ua), vs = samples(va);
			var base = Std.int(p.length / 3);
			for (i in 0...us.length)
				for (j in 0...vs.length) {
					var c = [0.0, 0.0, 0.0];
					c[ax] = sign * half[ax];
					c[ua] = us[i];
					c[va] = vs[j];
					var k = [for (a in 0...3) Math.max(-inner[a], Math.min(inner[a], c[a]))];
					var d = new Vec3(c[0] - k[0], c[1] - k[1], c[2] - k[2]);
					var l = Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
					var nn = l > 1e-9 ? d / l : new Vec3(ax == 0 ? sign : 0, ax == 1 ? sign : 0, ax == 2 ? sign : 0);
					vert(at, qq, new Vec3(k[0], k[1], k[2]) + nn * r, nn, i / (us.length - 1), j / (vs.length - 1));
				}
			var nu = us.length, nv = vs.length;
			// (wound outwards: the face's normal is u x v times the sign, flipped as needed)
			var flip = (ax == 0 && sign > 0) || (ax == 1 && sign > 0) || (ax == 2 && sign < 0);
			for (i in 0...nu - 1)
				for (j in 0...nv - 1) {
					var a = base + i * nv + j, b = a + nv;
					if (flip) {
						idx.push(a);
						idx.push(a + 1);
						idx.push(b);
						idx.push(b);
						idx.push(a + 1);
						idx.push(b + 1);
					} else {
						idx.push(a);
						idx.push(b);
						idx.push(a + 1);
						idx.push(a + 1);
						idx.push(b);
						idx.push(b + 1);
					}
				}
		}
	}

	public function sphere(at:Vec3, r:Float, seg = 20, rings = 12)
		ellipsoid(at, new Vec3(r, r, r), null, seg, rings);

	public function ellipsoid(at:Vec3, s:Vec3, ?q:Quat, seg = 20, rings = 12) {
		var qq = q ?? Quat.identity();
		var base = Std.int(p.length / 3);
		for (r in 0...rings + 1) {
			var th = Math.PI * r / rings;
			for (k in 0...seg + 1) {
				var ph = 2 * Math.PI * k / seg;
				var x = Math.sin(th) * Math.cos(ph), y = Math.cos(th), z = -Math.sin(th) * Math.sin(ph);
				var nn = new Vec3(x / s.x, y / s.y, z / s.z);
				var l = Math.sqrt(nn.x * nn.x + nn.y * nn.y + nn.z * nn.z);
				vert(at, qq, new Vec3(x * s.x, y * s.y, z * s.z), nn / l, k / seg, r / rings);
			}
		}
		for (r in 0...rings)
			for (k in 0...seg) {
				var a = base + r * (seg + 1) + k, b = a + seg + 1;
				idx.push(a);
				idx.push(b);
				idx.push(a + 1);
				idx.push(a + 1);
				idx.push(b);
				idx.push(b + 1);
			}
	}

	// a capsule along its y (radius r, half the straight part h)
	public function capsule(at:Vec3, r:Float, h:Float, ?q:Quat) {
		var qq = q ?? Quat.identity();
		var seg = 14, rings = 5;
		var base = Std.int(p.length / 3);
		var rows = 2 * rings + 2;
		for (row in 0...rows) {
			var upper = row <= rings;
			var th = Math.PI / 2 * (upper ? row : row - 1) / rings;
			var y = Math.cos(th), ring = Math.sin(th), shift = upper ? h : -h;
			for (k in 0...seg + 1) {
				var ph = 2 * Math.PI * k / seg;
				var x = ring * Math.cos(ph), z = -ring * Math.sin(ph);
				vert(at, qq, new Vec3(x * r, y * r + shift, z * r), new Vec3(x, y, z), k / seg, row / (rows - 1));
			}
		}
		for (row in 0...rows - 1)
			for (k in 0...seg) {
				var a = base + row * (seg + 1) + k, b = a + seg + 1;
				idx.push(a);
				idx.push(b);
				idx.push(a + 1);
				idx.push(a + 1);
				idx.push(b);
				idx.push(b + 1);
			}
	}

	// a cylinder along its y (radius r, half its height h), capped; scale: its section stretched (an oval)
	public function cylinder(at:Vec3, r:Float, h:Float, ?q:Quat, seg = 16, ?scale:Vec3) {
		var qq = q ?? Quat.identity(), s = scale ?? new Vec3(1, 1, 1);
		var base = Std.int(p.length / 3);
		for (k in 0...seg + 1) {
			var a = 2 * Math.PI * k / seg, x = Math.cos(a), z = -Math.sin(a);
			var nx = x / s.x, nz = z / s.z, l = Math.sqrt(nx * nx + nz * nz);
			vert(at, qq, new Vec3(x * r * s.x, h, z * r * s.z), new Vec3(nx / l, 0, nz / l), k / seg, 0);
			vert(at, qq, new Vec3(x * r * s.x, -h, z * r * s.z), new Vec3(nx / l, 0, nz / l), k / seg, 1);
		}
		for (k in 0...seg) {
			var a = base + k * 2;
			idx.push(a);
			idx.push(a + 1);
			idx.push(a + 2);
			idx.push(a + 2);
			idx.push(a + 1);
			idx.push(a + 3);
		}
		for (cap in [-1, 1]) {
			var c = Std.int(p.length / 3);
			vert(at, qq, new Vec3(0, cap * h, 0), new Vec3(0, cap, 0), 0.5, 0.5);
			for (k in 0...seg + 1) {
				var a = 2 * Math.PI * k / seg, x = Math.cos(a), z = -Math.sin(a);
				vert(at, qq, new Vec3(x * r * s.x, cap * h, z * r * s.z), new Vec3(0, cap, 0), 0.5 + x / 2, 0.5 + z / 2);
			}
			for (k in 0...seg) {
				idx.push(c);
				if (cap > 0) {
					idx.push(c + 1 + k);
					idx.push(c + 2 + k);
				} else {
					idx.push(c + 2 + k);
					idx.push(c + 1 + k);
				}
			}
		}
	}

	// a flat rectangle facing up (half extents hx, hz), its texture across it once
	public function plane(at:Vec3, hx:Float, hz:Float, ?q:Quat) {
		var qq = q ?? Quat.identity();
		var base = Std.int(p.length / 3), up = new Vec3(0, 1, 0);
		vert(at, qq, new Vec3(-hx, 0, -hz), up, 0, 0);
		vert(at, qq, new Vec3(hx, 0, -hz), up, 1, 0);
		vert(at, qq, new Vec3(-hx, 0, hz), up, 0, 1);
		vert(at, qq, new Vec3(hx, 0, hz), up, 1, 1);
		for (i in [0, 2, 1, 1, 2, 3])
			idx.push(base + i);
	}

	// a tapered cylinder along its y: radius r0 at -h, r1 at +h (h half its height), capped
	public function frustum(at:Vec3, r0:Float, r1:Float, h:Float, ?q:Quat, seg = 24) {
		var qq = q ?? Quat.identity();
		var base = Std.int(p.length / 3);
		var slope = (r0 - r1) / (2 * h), nl = Math.sqrt(1 + slope * slope);
		for (k in 0...seg + 1) {
			var a = 2 * Math.PI * k / seg, x = Math.cos(a), z = -Math.sin(a);
			var nn = new Vec3(x / nl, slope / nl, z / nl);
			vert(at, qq, new Vec3(x * r1, h, z * r1), nn, k / seg, 0);
			vert(at, qq, new Vec3(x * r0, -h, z * r0), nn, k / seg, 1);
		}
		for (k in 0...seg) {
			var a = base + k * 2;
			idx.push(a);
			idx.push(a + 1);
			idx.push(a + 2);
			idx.push(a + 2);
			idx.push(a + 1);
			idx.push(a + 3);
		}
		for (cap in [-1, 1]) {
			var c = Std.int(p.length / 3), r = cap > 0 ? r1 : r0;
			vert(at, qq, new Vec3(0, cap * h, 0), new Vec3(0, cap, 0), 0.5, 0.5);
			for (k in 0...seg + 1) {
				var a = 2 * Math.PI * k / seg, x = Math.cos(a), z = -Math.sin(a);
				vert(at, qq, new Vec3(x * r, cap * h, z * r), new Vec3(0, cap, 0), 0.5 + x / 2, 0.5 + z / 2);
			}
			for (k in 0...seg) {
				idx.push(c);
				if (cap > 0) {
					idx.push(c + 1 + k);
					idx.push(c + 2 + k);
				} else {
					idx.push(c + 2 + k);
					idx.push(c + 1 + k);
				}
			}
		}
	}

	// a cone along its y: its base (radius r) at -h/2, its tip at +h/2
	public function cone(at:Vec3, r:Float, h:Float, ?q:Quat, seg = 16) {
		var qq = q ?? Quat.identity();
		var base = Std.int(p.length / 3);
		var slope = r / h, nl = Math.sqrt(1 + slope * slope);
		for (k in 0...seg + 1) {
			var a = 2 * Math.PI * k / seg, x = Math.cos(a), z = -Math.sin(a);
			var nn = new Vec3(x / nl, slope / nl, z / nl);
			vert(at, qq, new Vec3(x * r, -h / 2, z * r), nn, k / seg, 1);
			vert(at, qq, new Vec3(0, h / 2, 0), nn, k / seg, 0);
		}
		for (k in 0...seg) {
			var a = base + k * 2;
			idx.push(a);
			idx.push(a + 2);
			idx.push(a + 1);
		}
		var c = Std.int(p.length / 3);
		vert(at, qq, new Vec3(0, -h / 2, 0), new Vec3(0, -1, 0), 0.5, 0.5);
		for (k in 0...seg + 1) {
			var a = 2 * Math.PI * k / seg;
			vert(at, qq, new Vec3(Math.cos(a) * r, -h / 2, -Math.sin(a) * r), new Vec3(0, -1, 0), 0, 0);
		}
		for (k in 0...seg) {
			idx.push(c);
			idx.push(c + 2 + k);
			idx.push(c + 1 + k);
		}
	}

	// a torus about y (ring radius R, tube radius r)
	public function torus(at:Vec3, big:Float, r:Float, seg = 20, sides = 8, ?q:Quat) {
		var qq = q ?? Quat.identity();
		var base = Std.int(p.length / 3);
		for (i in 0...seg + 1) {
			var a = 2 * Math.PI * i / seg, ca = Math.cos(a), sa = -Math.sin(a);
			for (j in 0...sides + 1) {
				var b = 2 * Math.PI * j / sides, cb = Math.cos(b), sb = Math.sin(b);
				var nn = new Vec3(ca * cb, sb, sa * cb);
				vert(at, qq, new Vec3(ca * (big + r * cb), r * sb, sa * (big + r * cb)), nn, i / seg, j / sides);
			}
		}
		for (i in 0...seg)
			for (j in 0...sides) {
				var a = base + i * (sides + 1) + j, b = a + sides + 1;
				idx.push(a);
				idx.push(a + 1);
				idx.push(b);
				idx.push(b);
				idx.push(a + 1);
				idx.push(b + 1);
			}
	}
}
