import Sim.Prop;
import Toys.Builder;
import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.Texture;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Node;
import helder.scene.World as SceneWorld;
import helder.scene.math.Quat;
import helder.scene.render.Images;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.MeshRenderer;
import helder.scene.render.Shapes;

// The rooms the battles are fought in, only looks: what the field is (a
// rug, a baking tray on a tablecloth, a desk's blotter, a foam puzzle mat,
// a sandbox in the grass, an old card table under the roof), what is
// around it (each room its own things, strewn anew for each level from its
// own seed), and things like the props beside the props, so the toys you
// can use are among others of their kind, not the only things there. All
// of it built in code, merged into one mesh a material (a few draws a
// room, whatever is strewn).
class Rooms {
	// the field's inner half extents (Sim's walls just outside)
	public static inline var FX = 5.23;
	public static inline var FZ = 7.63;

	final d:Device;
	final world:SceneWorld;
	final parent:Node;
	final parts:Map<String, {b:Builder, m:Material}> = [];
	final order:Array<String> = [];
	// (where things are put: their frame; the spots taken, as circles)
	var pos = new Vec3(0, 0, 0);
	var rot = Quat.identity();
	var sc = 1.0;
	final taken:Array<Vec3> = [];
	var seed = 1;

	function new(d:Device, world:SceneWorld, parent:Node) {
		this.d = d;
		this.world = world;
		this.parent = parent;
	}

	// the level's room: its floor, its field, its things
	public static function build(d:Device, world:SceneWorld, parent:Node, room:Int, level:Int, props:Array<Prop>) {
		var r = new Rooms(d, world, parent);
		r.seed = 7919 * (level + 3) + room * 131;
		for (p in props)
			r.taken.push(new Vec3(p.def.x, 0, p.def.z));
		switch room {
			case 0: r.bedroom();
			case 1: r.kitchen();
			case 2: r.study();
			case 3: r.playroom();
			case 4: r.garden();
			case _: r.attic();
		}
		for (p in props)
			r.companions(p, room);
		r.tape();
		r.finish();
	}

	// ---- the rooms

	function bedroom() {
		floor(planks(0xB98A5E, 0.62, 0.5, 8), 10);
		// (a woollen rug, its border bands, tassels at its ends)
		edge = 0x25344F;
		surface(rug(), 0.012, 0xFFFFFF, 0.95, 0, 5.75, 8.15);
		for (side in [-1, 1])
			for (k in 0...34) {
				var x = -5.6 + k * (11.2 / 33);
				at(x, 0.006, side * 8.28, 0);
				cyl("fabric", 0xEFE3C8, new Vec3(0, 0, 0), 0.025, 0.006, Quat.fromEuler(Math.PI / 2, 0, 0.1 * Math.sin(k * 7.1)), 6, null, 0.14);
			}
		// (the bed's corner, a toy chest, a teddy, books and blocks about)
		at(-8.8, 0, -6.5, 0.2);
		box("fabric", 0xF1E9DA, new Vec3(0, 1.1, 0), new Vec3(2.6, 1.1, 4.5), 0.35);
		box("fabric", 0x8FB3D9, new Vec3(0.2, 2.25, 0.8), new Vec3(2.7, 0.18, 3.6), 0.16);
		box("fabric", 0xFFFFFF, new Vec3(0, 2.4, -3.4), new Vec3(1.8, 0.25, 0.8), 0.22);
		at(8.4, 0, -4.2, -0.35);
		chest(0xD8574A);
		teddy(7.6, 4.6, -2.3, 1.15);
		scatter(["books", "blocks", "crayons", "marbles", "car", "die", "ball"], 46);
	}

	function kitchen() {
		floor(gingham(0xC94C4C), 9);
		// (the baking tray: a metal sheet, its rolled rim)
		var steel = 0xC9CCD1;
		edge = 0xB9BDC2;
		surface(brushed(), 0.008, 0xFFFFFF, 0.38, 0.9, 5.45, 7.85);
		// (baking paper over it, creased)
		edge = 0xE6D9BC;
		surface(parchment(), 0.014, 0xFFFFFF, 0.8, 0, 5.2, 7.6);
		for (w in [[5.38, 0, 0.09, 7.95], [-5.38, 0, 0.09, 7.95], [0, 7.88, 5.47, 0.09], [0, -7.88, 5.47, 0.09]]) {
			at(w[0], 0, w[1], 0);
			box("metal", steel, new Vec3(0, 0.22, 0), new Vec3(w[2], 0.22, w[3]), 0.08);
		}
		at(-8.6, 0, -2.2, 0.3);
		cerealBox(0xF2B134);
		at(8.6, 0, 3.2, 0);
		jar(0xE9E1D0, 0xC0392B);
		scatter(["mug", "plate", "apple", "orange", "spoon", "mug", "apple"], 30);
	}

	function study() {
		floor(planks(0x6B4A33, 0.48, 0.7, 5), 8);
		// (a green leather blotter, its darker corners)
		edge = 0x2E4A36;
		surface(leather(0x3E6B4A), 0.01, 0xFFFFFF, 0.6, 0, 5.6, 8.0);
		for (cx in [-1, 1])
			for (cz in [-1, 1]) {
				at(cx * 5.0, 0, cz * 7.4, cx * cz > 0 ? 0 : Math.PI / 2);
				box("leather", 0x2E241B, new Vec3(0, 0.02, 0), new Vec3(0.75, 0.02, 0.75), 0.02, Quat.axisAngle(new Vec3(0, 1, 0), Math.PI / 4));
			}
		at(-8.3, 0, -3.0, 0.4);
		lamp();
		at(8.0, 0, -5.4, 0);
		pencilCup();
		scatter(["notebook", "paper", "pencil", "books", "paper", "eraser", "pencil", "coin"], 40);
	}

	function playroom() {
		floor(carpet(0xD8C7A1), 6);
		edge = 0xE9C46A;
		surface(foam(), 0.03, 0xFFFFFF, 0.85, 0, 5.6, 8.0);
		at(8.3, 0, -3.6, 0);
		rings();
		at(-8.6, 0, 4.4, 0.4);
		box("plastic", 0x3D8BD9, new Vec3(0, 1.0, 0), new Vec3(1.6, 1.0, 1.2), 0.2);
		box("plastic", 0xF2C14E, new Vec3(0, 2.05, 0), new Vec3(1.7, 0.08, 1.3), 0.06);
		scatter(["brick", "brick", "car", "ball", "blocks", "brick", "crayons", "die"], 52);
	}

	function garden() {
		floor(grass(), 7);
		// (a sandbox: sand inside planks)
		edge = 0xD2BC8E;
		surface(sand(), 0.02, 0xFFFFFF, 0.97, 0, 5.4, 7.8);
		for (w in [[5.5, 0, 0.18, 8.05], [-5.5, 0, 0.18, 8.05], [0, 7.95, 5.68, 0.18], [0, -7.95, 5.68, 0.18]]) {
			at(w[0], 0, w[1], 0);
			box("wood", 0xA9845E, new Vec3(0, 0.3, 0), new Vec3(w[2], 0.3, w[3]), 0.05);
		}
		for (cx in [-1, 1])
			for (cz in [-1, 1]) {
				at(cx * 5.5, 0, cz * 7.95, 0);
				box("wood", 0x8E6C4A, new Vec3(0, 0.32, 0), new Vec3(0.24, 0.32, 0.24), 0.04);
			}
		// (leaves and pebbles in the sand: flat, walked over)
		for (_ in 0...26) {
			at((rnd() - 0.5) * 10, 0.025, (rnd() - 0.5) * 15, rnd() * 6.3);
			leaf([0x7FA34A, 0xC58A2E, 0xA9502B][Std.int(rnd() * 3)], 0.7 + rnd() * 0.5);
		}
		at(-8.4, 0, 3.4, 0.6);
		bucket(0xE04F3F);
		at(8.2, 0, -5.0, 0);
		pot(0xE9C46A);
		scatter(["pot", "pebble", "pebble", "flowers", "leaves", "pot"], 36);
	}

	function attic() {
		floor(planks(0x8C6E52, 0.9, 0.85, 7), 9);
		// (an old card table: worn felt, a dark wooden rim)
		surface(feltTex(), 0.012, 0x4F6A44, 0.95, 0, 5.3, 7.7);
		for (w in [[5.35, 0, 0.14, 7.9], [-5.35, 0, 0.14, 7.9], [0, 7.76, 5.49, 0.14], [0, -7.76, 5.49, 0.14]]) {
			at(w[0], 0, w[1], 0);
			box("varnish", 0x4A2E1E, new Vec3(0, 0.22, 0), new Vec3(w[2], 0.22, w[3]), 0.07);
		}
		at(-8.8, 0, -4.0, 0.15);
		carton(2.0, 1.5, 1.6);
		at(-8.6, 0, 1.2, -0.2);
		carton(1.5, 1.1, 1.3);
		at(8.7, 0, -1.0, 0.1);
		trunk();
		scatter(["books", "carton", "candle", "books", "die", "marbles", "blocks"], 34);
	}

	// ---- what lies beside a prop: its kind's spares, at the field's edge nearest it

	function companions(p:Prop, room:Int) {
		var d = p.def;
		// (the nearest edge, just outside it)
		var ex = FX - Math.abs(d.x), ez = FZ - Math.abs(d.z);
		var x = d.x, z = d.z;
		if (ex < ez) x = (d.x < 0 ? -1 : 1) * (FX + 1.3) else z = (d.z < 0 ? -1 : 1) * (FZ + 1.3);
		switch d.type {
			case Sim.MARBLE:
				for (k in 0...4) {
					at(x + (rnd() - 0.5) * 2.2, 0, z + (rnd() - 0.5) * 2.2, 0);
					marble([0x4C8DFF, 0xFF5A45, 0x5FD38A, 0xFFC93C][k]);
				}
				at(x + (rnd() - 0.5), 0, z + (rnd() - 0.5), rnd() * 3);
				bookStack(2);
			case Sim.DOMINO:
				at(x, 0, z, rnd() * 3);
				dominoBox();
				for (k in 0...3) {
					at(x + (rnd() - 0.5) * 2.4, 0, z + (rnd() - 0.5) * 2.4, rnd() * 6);
					domino(true);
				}
			case Sim.TOWER:
				for (k in 0...5) {
					at(x + (rnd() - 0.5) * 2.6, 0, z + (rnd() - 0.5) * 2.6, rnd() * 6);
					block(BLOCKS[k % BLOCKS.length], k == 2 ? 0.6 : 0.2);
				}
			case Sim.CATAPULT:
				for (k in 0...3) {
					at(x + (rnd() - 0.5) * 2.4, 0, z + (rnd() - 0.5) * 2.4, rnd() * 6);
					if (k == 0) eraser() else pencil();
				}
			case Sim.JACK:
				at(x, 0, z, rnd() * 3);
				box("plastic", 0x4FA3D9, new Vec3(0, 0.32, 0), new Vec3(0.32, 0.32, 0.32), 0.04);
				box("plastic", 0xF2C14E, new Vec3(0, 0.66, 0), new Vec3(0.34, 0.03, 0.34), 0.02);
			case Sim.TOP:
				at(x, 0, z, rnd() * 6);
				top(true);
			case Sim.TRAIN:
				at(x, 0, z, d.angle);
				box("wood", 0xC9A36B, new Vec3(0, 0.08, 0), new Vec3(0.5, 0.08, 0.5), 0.02);
				box("paint", 0xC0392B, new Vec3(0, 0.45, 0), new Vec3(0.04, 0.3, 0.04), 0.02);
				box("paint", 0xFFFFFF, new Vec3(0, 0.75, 0), new Vec3(0.25, 0.12, 0.02), 0.02);
		}
		taken.push(new Vec3(x, 0, z));
	}

	// (the halfway line: strips of masking tape, laid by hand)
	function tape() {
		var x = -5.0;
		while (x < 5.0) {
			var len = 1.2 + rnd() * 0.9;
			if (x + len > 5.0) len = 5.0 - x;
			at(x + len / 2, 0.02, (rnd() - 0.5) * 0.04, (rnd() - 0.5) * 0.04);
			box("paper", 0xEDE2C4, new Vec3(0, 0, 0), new Vec3(len / 2 + 0.03, 0.004, 0.07), 0.003);
			if (x + len >= 5.0) break;
			x += len - 0.06;
		}
	}

	// ---- strewn about the field: things of the room's kinds, not on top of each other

	static final BLOCKS = [0xE63946, 0xF4A261, 0x2A9D8F, 0x457B9D, 0x8338EC, 0xFFBE0B];
	static final CRAYONS = [0xE63946, 0x2A9D8F, 0xFFBE0B, 0x457B9D, 0x8AC926, 0xFF7F1F, 0x8338EC];

	function scatter(kinds:Array<String>, n:Int) {
		var placed = 0, tries = 0;
		while (placed < n && tries < n * 30) {
			tries++;
			// (a ring about the field, nearer more often)
			var side = rnd(), out = 0.5 + Math.pow(rnd(), 1.6) * 3.6;
			var x, z;
			if (side < 0.5) {
				x = (rnd() < 0.5 ? -1 : 1) * (FX + out);
				z = (rnd() - 0.5) * 2 * (FZ + 3);
			} else {
				x = (rnd() - 0.5) * 2 * (FX + 3);
				z = (rnd() < 0.5 ? -1 : 1) * (FZ + out);
			}
			var r = 0.8;
			var free = true;
			for (t in taken)
				if ((t.x - x) * (t.x - x) + (t.z - z) * (t.z - z) < (r + 0.7) * (r + 0.7)) free = false;
			if (!free) continue;
			taken.push(new Vec3(x, 0, z));
			placed++;
			var kind = kinds[Std.int(rnd() * kinds.length)];
			at(x, 0, z, rnd() * 6.3);
			switch kind {
				case "books": bookStack(1 + Std.int(rnd() * 3));
				case "blocks":
					block(BLOCKS[Std.int(rnd() * 6)], 0.2);
					if (rnd() < 0.5) {
						at(x + 0.5, 0, z + 0.1, rnd() * 6.3);
						block(BLOCKS[Std.int(rnd() * 6)], 0.2);
					}
					if (rnd() < 0.3) {
						at(x + 0.2, 0, z + 0.05, rnd() * 6.3);
						block(BLOCKS[Std.int(rnd() * 6)], 0.6);
					}
				case "crayons":
					for (k in 0...2 + Std.int(rnd() * 3)) {
						at(x + (rnd() - 0.5) * 0.8, 0, z + (rnd() - 0.5) * 0.8, rnd() * 6.3);
						crayon(CRAYONS[Std.int(rnd() * CRAYONS.length)]);
					}
				case "marbles":
					for (k in 0...2 + Std.int(rnd() * 2)) {
						at(x + (rnd() - 0.5) * 0.9, 0, z + (rnd() - 0.5) * 0.9, 0);
						marble(CRAYONS[Std.int(rnd() * CRAYONS.length)]);
					}
				case "car": car(BLOCKS[Std.int(rnd() * 6)]);
				case "die": die();
				case "ball": ball(BLOCKS[Std.int(rnd() * 6)]);
				case "mug": mug([0xF1EDE4, 0x2F6BD8, 0xE07A5F, 0x81B29A][Std.int(rnd() * 4)]);
				case "plate": plate();
				case "apple": apple(rnd() < 0.6 ? 0xC0392B : 0x8DB33A);
				case "orange": orange();
				case "spoon": spoon();
				case "notebook": notebook(BLOCKS[Std.int(rnd() * 6)]);
				case "paper": paper();
				case "pencil":
					pencil();
					if (rnd() < 0.5) {
						at(x + 0.3, 0, z + 0.2, rnd() * 6.3);
						pencil();
					}
				case "eraser": eraser();
				case "coin":
					for (k in 0...3) {
						at(x + (rnd() - 0.5) * 0.6, 0, z + (rnd() - 0.5) * 0.6, 0);
						cyl("metal", 0xC9A64B, new Vec3(0, 0.012, 0), 0.11, 0.012, null, 20);
					}
				case "brick":
					for (k in 0...1 + Std.int(rnd() * 3)) {
						at(x + (rnd() - 0.5) * 0.9, 0, z + (rnd() - 0.5) * 0.9, rnd() * 6.3);
						brick(BLOCKS[Std.int(rnd() * 6)], k == 1 && rnd() < 0.4 ? 0.23 : 0);
					}
				case "pot": pot([0xC8694B, 0xD98E5F, 0xB55A3C][Std.int(rnd() * 3)]);
				case "pebble":
					for (k in 0...3 + Std.int(rnd() * 3)) {
						at(x + (rnd() - 0.5) * 1.2, 0, z + (rnd() - 0.5) * 1.2, rnd() * 6.3);
						var g = 0x8A8580 + Std.int(rnd() * 3) * 0x101010;
						ell("stone", g, new Vec3(0, 0.05, 0), new Vec3(0.12 + rnd() * 0.12, 0.07, 0.1 + rnd() * 0.08));
					}
				case "flowers": flowers();
				case "leaves":
					for (k in 0...4) {
						at(x + (rnd() - 0.5) * 1.4, 0.01, z + (rnd() - 0.5) * 1.4, rnd() * 6.3);
						leaf([0x7FA34A, 0xC58A2E, 0xA9502B][Std.int(rnd() * 3)], 1);
					}
				case "carton": carton(0.9 + rnd() * 0.6, 0.6 + rnd() * 0.5, 0.8 + rnd() * 0.5);
				case "candle": candle();
				case _:
			}
		}
	}

	// ---- things (each in its frame: at() first)

	function bookStack(n:Int) {
		var y = 0.0;
		var cols = [0x284B63, 0xB5452B, 0xD9A441, 0x3E6B4A, 0x6D3B6E, 0x2F2F2F];
		for (k in 0...n) {
			var h = 0.16 + rnd() * 0.12, w = 1.2 + rnd() * 0.5, dd = 1.6 + rnd() * 0.6;
			var q = Quat.axisAngle(new Vec3(0, 1, 0), (rnd() - 0.5) * 0.5);
			book(new Vec3(0, y + h / 2, 0), w, h, dd, cols[Std.int(rnd() * cols.length)], q);
			y += h;
		}
	}

	function book(c:Vec3, w:Float, h:Float, dd:Float, rgb:Int, q:Quat) {
		var t = 0.022;
		box("cover", rgb, c + q.rotate(new Vec3(0, h / 2 - t / 2, 0)), new Vec3(w / 2, t / 2, dd / 2), 0.008, q);
		box("cover", rgb, c + q.rotate(new Vec3(0, -h / 2 + t / 2, 0)), new Vec3(w / 2, t / 2, dd / 2), 0.008, q);
		box("cover", rgb, c + q.rotate(new Vec3(-w / 2 + 0.014, 0, 0)), new Vec3(0.018, h / 2, dd / 2), 0.014, q);
		box("paper", 0xEFE6D2, c + q.rotate(new Vec3(0.01, 0, 0)), new Vec3(w / 2 - 0.03, h / 2 - t, dd / 2 - 0.02), 0.004, q);
		// (the spine's gilt bands)
		for (b in [-0.6, 0.6])
			box("gilt", 0xD4AF37, c + q.rotate(new Vec3(-w / 2 - 0.002, 0, b * dd / 2)), new Vec3(0.004, h / 2 - 0.01, 0.02), 0.002, q);
	}

	function block(rgb:Int, y:Float) {
		var q = Quat.axisAngle(new Vec3(0, 1, 0), 0);
		box("wood", 0xE9C893, new Vec3(0, y, 0), new Vec3(0.2, 0.2, 0.2), 0.03);
		for (face in [new Vec3(0, 0, 1), new Vec3(1, 0, 0), new Vec3(0, 0, -1), new Vec3(-1, 0, 0)]) {
			var fq = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(face.x, face.z));
			box("paint", rgb, new Vec3(face.x * 0.2, y, face.z * 0.2), new Vec3(0.12, 0.12, 0.006), 0.006, fq);
		}
		box("paint", rgb, new Vec3(0, y + 0.2, 0), new Vec3(0.12, 0.006, 0.12), 0.006, q);
	}

	function crayon(rgb:Int) {
		var lie = Quat.fromEuler(0, 0, Math.PI / 2);
		cyl("wax", rgb, new Vec3(0, 0.05, 0), 0.05, 0.3, lie, 12);
		cyl("paper", mix(rgb, 0xFFFFFF, 0.25), new Vec3(-0.04, 0.05, 0), 0.053, 0.2, lie, 12);
		cone("wax", rgb, new Vec3(0.36, 0.05, 0), 0.05, 0.12, Quat.fromEuler(0, 0, -Math.PI / 2), 12);
	}

	function pencil() {
		var lie = Quat.fromEuler(0, 0, Math.PI / 2);
		cyl("paint", 0xF2B705, new Vec3(0, 0.045, 0), 0.045, 0.42, lie, 6);
		cone("wood", 0xE8C9A0, new Vec3(0.47, 0.045, 0), 0.042, 0.1, Quat.fromEuler(0, 0, -Math.PI / 2), 6);
		cone("graphite", 0x333333, new Vec3(0.51, 0.045, 0), 0.016, 0.03, Quat.fromEuler(0, 0, -Math.PI / 2), 6);
		cyl("metal", 0xC0C0C0, new Vec3(-0.45, 0.045, 0), 0.047, 0.035, lie, 12);
		cyl("rubber", 0xF28C9E, new Vec3(-0.52, 0.045, 0), 0.044, 0.04, lie, 12);
	}

	function eraser() {
		box("rubber", 0xF28C9E, new Vec3(0, 0.07, 0), new Vec3(0.24, 0.07, 0.12), 0.03);
		box("paper", 0x3D6FB6, new Vec3(-0.06, 0.07, 0), new Vec3(0.13, 0.073, 0.123), 0.02);
	}

	function marble(rgb:Int) {
		sph("glass", 0xFFFFFF, new Vec3(0, 0.13, 0), 0.13);
		ell("glassTint", rgb, new Vec3(0, 0.13, 0), new Vec3(0.1, 0.03, 0.1), Quat.fromEuler(rnd() * 3, rnd() * 3, 0));
	}

	function domino(lying:Bool) {
		var q = lying ? Quat.fromEuler(Math.PI / 2, 0, 0) : Quat.identity();
		var y = lying ? 0.05 : 0.3;
		box("bone", 0xF4EFE4, new Vec3(0, y, 0), new Vec3(0.15, 0.3, 0.05), 0.03, q);
		for (k in 0...4)
			sph("ink", 0x1A1A1A, new Vec3((k % 2 - 0.5) * 0.12, y + 0.1, 0.0) + q.rotate(new Vec3(0, (k < 2 ? 0.12 : -0.12), 0.046)) - new Vec3(0, 0.1, 0), 0.02, 8, 4);
	}

	function dominoBox() {
		box("wood", 0x7A4A2A, new Vec3(0, 0.12, 0), new Vec3(0.45, 0.12, 0.8), 0.03);
		box("wood", 0x5C3820, new Vec3(0.55, 0.05, 0.1), new Vec3(0.45, 0.04, 0.82), 0.03, Quat.fromEuler(0, 0.3, 0));
		for (k in 0...4)
			box("bone", 0xF4EFE4, new Vec3(0, 0.26, -0.55 + k * 0.32), new Vec3(0.16, 0.05, 0.14), 0.02);
	}

	function top(lying:Bool) {
		var q = lying ? Quat.fromEuler(0, 0, 1.1) : Quat.identity();
		var c = new Vec3(0, lying ? 0.2 : 0.26, 0);
		ell("plastic", 0xE63946, c, new Vec3(0.26, 0.14, 0.26), q);
		cyl("plastic", 0xFFBE0B, c + q.rotate(new Vec3(0, 0.12, 0)), 0.04, 0.12, q, 12);
		cone("plastic", 0x457B9D, c + q.rotate(new Vec3(0, -0.17, 0)), 0.1, 0.16, q * Quat.fromEuler(Math.PI, 0, 0), 12);
	}

	function car(rgb:Int) {
		box("plastic", rgb, new Vec3(0, 0.16, 0), new Vec3(0.22, 0.08, 0.42), 0.06);
		box("plastic", rgb, new Vec3(0, 0.29, -0.04), new Vec3(0.18, 0.07, 0.2), 0.06);
		box("glass", 0x223344, new Vec3(0, 0.29, -0.04), new Vec3(0.185, 0.05, 0.18), 0.04);
		for (wx in [-1, 1])
			for (wz in [-1, 1]) {
				cyl("rubber", 0x1E1E1E, new Vec3(wx * 0.2, 0.08, wz * 0.27), 0.08, 0.04, Quat.fromEuler(0, 0, Math.PI / 2), 14);
				cyl("metal", 0xD0D0D0, new Vec3(wx * 0.24, 0.08, wz * 0.27), 0.04, 0.005, Quat.fromEuler(0, 0, Math.PI / 2), 10);
			}
	}

	function die() {
		box("plastic", 0xF8F5EE, new Vec3(0, 0.15, 0), new Vec3(0.15, 0.15, 0.15), 0.04);
		var spots = [[0.0, 0.0], [-0.07, -0.07], [0.07, 0.07], [-0.07, 0.07], [0.07, -0.07]];
		for (k in 0...5)
			sph("ink", 0xC0392B, new Vec3(spots[k][0], 0.3, spots[k][1]), 0.025, 8, 4);
		for (k in [1, 2])
			sph("ink", 0x1A1A1A, new Vec3(spots[k][0], 0.15 + spots[k][1], 0.15), 0.025, 8, 4);
	}

	function ball(rgb:Int) {
		sph("plastic", rgb, new Vec3(0, 0.55, 0), 0.55, 28, 16);
		torus("plastic", 0xFFFFFF, new Vec3(0, 0.55, 0), 0.55, 0.06, 32, 8, Quat.fromEuler(0.4, 0, 0.3));
	}

	function teddy(x:Float, z:Float, yaw:Float, s:Float) {
		at(x, 0, z, yaw, s);
		var fur = 0xA9774A, light = 0xD9B48A;
		ell("fur", fur, new Vec3(0, 0.62, 0), new Vec3(0.5, 0.6, 0.42));
		ell("fur", light, new Vec3(0, 0.6, 0.3), new Vec3(0.3, 0.38, 0.15));
		sph("fur", fur, new Vec3(0, 1.38, 0.04), 0.38);
		for (e in [-1, 1]) {
			sph("fur", fur, new Vec3(e * 0.28, 1.68, 0), 0.13);
			sph("fur", light, new Vec3(e * 0.28, 1.68, 0.06), 0.07);
			ell("fur", fur, new Vec3(e * 0.5, 0.75, 0.1), new Vec3(0.15, 0.32, 0.15), Quat.fromEuler(0.3, 0, e * 0.6));
			ell("fur", fur, new Vec3(e * 0.28, 0.14, 0.42), new Vec3(0.18, 0.16, 0.32));
			ell("fur", light, new Vec3(e * 0.28, 0.14, 0.72), new Vec3(0.13, 0.12, 0.03));
			sph("glass", 0x111111, new Vec3(e * 0.13, 1.47, 0.36), 0.05, 12, 8);
		}
		ell("fur", light, new Vec3(0, 1.3, 0.34), new Vec3(0.16, 0.12, 0.12));
		ell("glass", 0x2A1A12, new Vec3(0, 1.36, 0.45), new Vec3(0.06, 0.04, 0.04));
		torus("fabric", 0xC0392B, new Vec3(0, 1.06, 0.04), 0.3, 0.05, 24, 8);
	}

	function chest(rgb:Int) {
		box("paint", rgb, new Vec3(0, 0.75, 0), new Vec3(1.6, 0.75, 1.0), 0.08);
		box("paint", mix(rgb, 0x000000, 0.2), new Vec3(0, 1.58, 0), new Vec3(1.68, 0.1, 1.08), 0.08);
		for (bx in [-1.1, 1.1])
			box("metal", 0xD4AF37, new Vec3(bx, 0.75, 1.0), new Vec3(0.08, 0.7, 0.03), 0.02);
		box("paint", 0xF2C14E, new Vec3(0, 0.85, 1.01), new Vec3(0.5, 0.3, 0.02), 0.02);
	}

	function mug(rgb:Int) {
		cyl("ceramic", rgb, new Vec3(0, 0.55, 0), 0.5, 0.55, null, 36);
		cyl("coffee", 0x3B2414, new Vec3(0, 1.08, 0), 0.44, 0.02, null, 36);
		torus("ceramic", rgb, new Vec3(0.55, 0.6, 0), 0.24, 0.06, 24, 10, Quat.fromEuler(Math.PI / 2, 0, 0));
	}

	function plate() {
		cyl("ceramic", 0xF7F4EE, new Vec3(0, 0.03, 0), 0.9, 0.03, null, 40);
		torus("ceramic", 0xF7F4EE, new Vec3(0, 0.07, 0), 0.82, 0.07, 40, 8);
		torus("ceramic", 0x2F6BD8, new Vec3(0, 0.1, 0), 0.82, 0.025, 40, 6);
		if (rnd() < 0.6) {
			at(pos.x + 0.2, 0.1, pos.z, rnd() * 6);
			apple(0xC0392B);
		}
	}

	function apple(rgb:Int) {
		ell("fruit", rgb, new Vec3(0, 0.3, 0), new Vec3(0.32, 0.29, 0.32));
		cyl("wood", 0x5A3A1A, new Vec3(0, 0.62, 0), 0.02, 0.06, Quat.fromEuler(0.2, 0, 0.1), 6);
		ell("leaf", 0x6A9A3A, new Vec3(0.08, 0.64, 0), new Vec3(0.1, 0.015, 0.05), Quat.fromEuler(0, 0.4, 0.3));
	}

	function orange() {
		sph("peel", 0xF28C28, new Vec3(0, 0.34, 0), 0.34, 24, 14);
		sph("leaf", 0x5A7A2A, new Vec3(0, 0.67, 0), 0.04, 8, 4);
	}

	function spoon() {
		ell("wood", 0xC9A06A, new Vec3(0, 0.05, 0.75), new Vec3(0.22, 0.05, 0.3));
		box("wood", 0xC9A06A, new Vec3(0, 0.04, -0.25), new Vec3(0.06, 0.035, 0.8), 0.03);
	}

	function cerealBox(rgb:Int) {
		box("card", rgb, new Vec3(0, 1.5, 0), new Vec3(1.0, 1.5, 0.35), 0.03);
		box("card", 0xFFFFFF, new Vec3(0, 2.1, 0.36), new Vec3(0.75, 0.3, 0.005), 0.01);
		ell("card", 0xC0392B, new Vec3(0, 1.2, 0.36), new Vec3(0.5, 0.5, 0.01));
	}

	function jar(glass:Int, lid:Int) {
		cyl("glass", glass, new Vec3(0, 0.7, 0), 0.55, 0.7, null, 32);
		cyl("cookie", 0xB07A3B, new Vec3(0, 0.45, 0), 0.5, 0.42, null, 32);
		cyl("paint", lid, new Vec3(0, 1.46, 0), 0.58, 0.07, null, 32);
	}

	function notebook(rgb:Int) {
		box("cover", rgb, new Vec3(0, 0.05, 0), new Vec3(0.75, 0.05, 1.0), 0.02);
		for (k in 0...9)
			torus("metal", 0xBFBFBF, new Vec3(-0.75, 0.05, -0.85 + k * 0.21), 0.06, 0.012, 12, 6, Quat.fromEuler(0, 0, Math.PI / 2));
	}

	function paper() {
		box("paper", 0xFAF7EF, new Vec3(0, 0.006, 0), new Vec3(0.8, 0.004, 1.1), 0.002);
		for (k in 0...5)
			box("ink", 0x6C8EBF, new Vec3(0, 0.011, -0.7 + k * 0.3), new Vec3(0.65, 0.001, 0.008), 0.001);
	}

	function lamp() {
		cyl("metal", 0x2F2F2F, new Vec3(0, 0.08, 0), 0.7, 0.08, null, 32);
		capsule("metal", 0x2F2F2F, new Vec3(0, 1.2, 0), 0.06, 1.1, Quat.fromEuler(0, 0, 0.15));
		cone("paint", 0x3E6B4A, new Vec3(0.5, 2.3, 0), 0.6, 0.7, Quat.fromEuler(0, 0, 2.2), 28);
	}

	function pencilCup() {
		cyl("ceramic", 0x81B29A, new Vec3(0, 0.6, 0), 0.4, 0.6, null, 28);
		for (k in 0...5) {
			var a = k * 1.3;
			var q = Quat.fromEuler(Math.cos(a) * 0.25, 0, Math.sin(a) * 0.25);
			cyl("paint", [0xF2B705, 0xE63946, 0x2A9D8F][k % 3], new Vec3(Math.sin(a) * 0.18, 1.3, Math.cos(a) * 0.18), 0.045, 0.6, q, 6);
		}
	}

	function rings() {
		cyl("wood", 0xE9C893, new Vec3(0, 0.06, 0), 0.6, 0.06, null, 28);
		cyl("wood", 0xE9C893, new Vec3(0, 0.9, 0), 0.07, 0.85, null, 12);
		var cols = [0xE63946, 0xF4A261, 0xFFBE0B, 0x2A9D8F, 0x457B9D];
		for (k in 0...5)
			torus("plastic", cols[k], new Vec3(0, 0.24 + k * 0.27, 0), 0.5 - k * 0.07, 0.13 - k * 0.012, 28, 10);
		sph("plastic", 0x8338EC, new Vec3(0, 1.75, 0), 0.16);
	}

	function brick(rgb:Int, y:Float) {
		box("plastic", rgb, new Vec3(0, y + 0.115, 0), new Vec3(0.32, 0.115, 0.16), 0.012);
		for (i in 0...4)
			for (j in 0...2)
				cyl("plastic", rgb, new Vec3(-0.24 + i * 0.16, y + 0.25, -0.08 + j * 0.16), 0.05, 0.02, null, 12);
	}

	function pot(rgb:Int) {
		frustum("clay", rgb, new Vec3(0, 0.45, 0), 0.38, 0.55, 0.45);
		torus("clay", rgb, new Vec3(0, 0.9, 0), 0.55, 0.07, 28, 8);
		cyl("soil", 0x3B2A1E, new Vec3(0, 0.86, 0), 0.52, 0.02, null, 24);
		for (k in 0...7) {
			var a = k * 0.9, l = 0.3 + rnd() * 0.25;
			ell("leaf", 0x4E8A3A, new Vec3(Math.sin(a) * 0.25, 1.1 + rnd() * 0.3, Math.cos(a) * 0.25), new Vec3(0.14, 0.04, l),
				Quat.fromEuler(-0.6, a, 0));
		}
		if (rnd() < 0.6)
			for (k in 0...3)
				sph("petal", [0xF28C9E, 0xFFBE0B, 0xFFFFFF][Std.int(rnd() * 3)], new Vec3((rnd() - 0.5) * 0.4, 1.45 + rnd() * 0.2, (rnd() - 0.5) * 0.4), 0.09, 10, 6);
	}

	function flowers() {
		for (k in 0...5) {
			var x = (rnd() - 0.5) * 1.2, z = (rnd() - 0.5) * 1.2, h = 0.3 + rnd() * 0.3;
			cyl("leaf", 0x4E8A3A, new Vec3(x, h, z), 0.02, h, null, 6);
			var c = [0xF28C9E, 0xFFBE0B, 0xFFFFFF, 0xE63946][Std.int(rnd() * 4)];
			for (p in 0...5) {
				var a = p * 1.2566;
				ell("petal", c, new Vec3(x + Math.sin(a) * 0.07, h * 2, z + Math.cos(a) * 0.07), new Vec3(0.06, 0.02, 0.06));
			}
			sph("petal", 0xF2B705, new Vec3(x, h * 2 + 0.02, z), 0.035, 8, 5);
		}
	}

	function leaf(rgb:Int, s:Float) {
		ell("leaf", rgb, new Vec3(0, 0.01, 0), new Vec3(0.12 * s, 0.008, 0.24 * s));
	}

	function bucket(rgb:Int) {
		frustum("plastic", rgb, new Vec3(0, 0.5, 0), 0.45, 0.6, 0.5);
		torus("plastic", rgb, new Vec3(0, 1.0, 0), 0.6, 0.04, 28, 6);
		torus("plastic", 0xFFBE0B, new Vec3(0, 1.0, 0), 0.62, 0.03, 28, 6, Quat.fromEuler(0, 0, 1.2));
		at(pos.x + 1.0, 0, pos.z + 0.4, 1.0);
		box("plastic", 0x2F6BD8, new Vec3(0, 0.04, 0.35), new Vec3(0.22, 0.03, 0.3), 0.03);
		capsule("plastic", 0x2F6BD8, new Vec3(0, 0.06, -0.3), 0.04, 0.35, Quat.fromEuler(Math.PI / 2, 0, 0));
	}

	function carton(w:Float, h:Float, dd:Float) {
		box("card", 0xC49A63, new Vec3(0, h / 2, 0), new Vec3(w / 2, h / 2, dd / 2), 0.02);
		box("tape", 0xD9C7A0, new Vec3(0, h + 0.002, 0), new Vec3(0.15, 0.004, dd / 2 + 0.01), 0.002);
		box("tape", 0xD9C7A0, new Vec3(0, h * 0.75, dd / 2 + 0.002), new Vec3(0.15, h * 0.25, 0.004), 0.002);
		box("ink", 0x3A3A3A, new Vec3(w * 0.2, h * 0.55, dd / 2 + 0.004), new Vec3(w * 0.15, 0.04, 0.002), 0.002);
	}

	function trunk() {
		box("varnish", 0x6B4226, new Vec3(0, 0.7, 0), new Vec3(1.5, 0.7, 0.9), 0.06);
		box("varnish", 0x5A3820, new Vec3(0, 1.48, 0), new Vec3(1.55, 0.12, 0.95), 0.06);
		for (bx in [-1.0, 0, 1.0])
			box("metal", 0x8C7A5B, new Vec3(bx, 0.8, 0), new Vec3(0.06, 0.82, 0.93), 0.02);
		box("metal", 0xC9A64B, new Vec3(0, 1.2, 0.93), new Vec3(0.12, 0.14, 0.03), 0.02);
	}

	function candle() {
		cyl("ceramic", 0xE9E1D0, new Vec3(0, 0.05, 0), 0.32, 0.05, null, 24);
		cyl("wax", 0xF4EAD5, new Vec3(0, 0.5, 0), 0.12, 0.42, null, 16);
		cyl("ink", 0x222222, new Vec3(0, 0.95, 0), 0.01, 0.04, null, 6);
	}

	// ---- the field's surface and the floor

	// the field's cloth (a thin slab of half extents w, h, its top at y), textured
	function surface(tex:Texture, y:Float, tint:Int, rough:Float, metal:Float, w:Float, h:Float) {
		var n = world.node("surface", parent);
		var m = Toys.mat("surface", tint, rough, metal);
		m.baseColorTexture = tex;
		var b = new Builder(), top = new Builder();
		b.roundBox(new Vec3(0, y / 2 - 0.0008, 0), new Vec3(w, y / 2, h), Math.min(0.04, y / 2 * 0.99));
		top.plane(new Vec3(0, y, 0), w - Math.min(0.04, y / 2), h - Math.min(0.04, y / 2));
		var mesh = new Mesh();
		b.into(mesh, d, Toys.mat("edge", edgeOf(tint), rough, metal));
		top.into(mesh, d, m);
		MeshRenderer.attach(n, mesh);
	}

	// (the slab's sides: the texture's average, near enough)
	var edge = 0x888888;

	function edgeOf(tint:Int):Int
		return tint == 0xFFFFFF ? edge : tint;

	function floor(tex:Texture, repeat:Float) {
		var n = world.node("floor", parent);
		var m = new Material("floor", new Vec4(1, 1, 1, 1), 0, 0.6);
		m.baseColorTexture = tex;
		m.uvScale = new Vec2(repeat, repeat);
		MeshRenderer.attach(n, Shapes.plane(d, m, 48));
		n.position = new Vec3(0, -0.002, 0);
	}

	// ---- the merged meshes: one a material (a kind of stuff and a colour)

	function at(x:Float, y:Float, z:Float, yaw:Float, s = 1.0) {
		pos = new Vec3(x, y, z);
		rot = Quat.axisAngle(new Vec3(0, 1, 0), yaw);
		sc = s;
	}

	function part(kind:String, rgb:Int):Builder {
		var key = kind + "/" + rgb;
		var p = parts.get(key);
		if (p == null) {
			var m = switch kind {
				case "plastic": glossy(Toys.mat(kind, rgb, 0.32), 0.5);
				case "paint": glossy(Toys.mat(kind, rgb, 0.4), 0.3);
				case "glass" | "glassTint": glossy(Toys.mat(kind, rgb, 0.05), 1.0);
				case "metal": Toys.mat(kind, rgb, 0.3, 1.0);
				case "gilt": Toys.mat(kind, rgb, 0.25, 1.0);
				case "ceramic": glossy(Toys.mat(kind, rgb, 0.2), 0.8);
				case "varnish": glossy(Toys.mat(kind, rgb, 0.45), 0.5);
				case "wax": Toys.mat(kind, rgb, 0.55);
				case "fruit" | "peel": glossy(Toys.mat(kind, rgb, 0.4), 0.3);
				case "fur" | "fabric": Toys.mat(kind, rgb, 0.97);
				case "rubber": Toys.mat(kind, rgb, 0.8);
				case "cover": Toys.mat(kind, rgb, 0.6);
				case "wood": Toys.mat(kind, rgb, 0.6);
				case _: Toys.mat(kind, rgb, 0.85);
			}
			p = {b: new Builder(), m: m};
			parts.set(key, p);
			order.push(key);
		}
		return p.b;
	}

	static function glossy(m:Material, coat:Float):Material {
		m.clearcoat = coat;
		m.clearcoatRoughness = 0.15;
		return m;
	}

	inline function P(v:Vec3):Vec3
		return pos + rot.rotate(v * sc);

	inline function Q(?q:Quat):Quat
		return q == null ? rot : rot * q;

	// (the decor's boxes coarser than the toys': a bevel where the rounding is
	// too small to see, one row round the edge where it isn't)
	function box(k:String, rgb:Int, c:Vec3, h:Vec3, r:Float, ?q:Quat)
		part(k, rgb).roundBox(P(c), h * sc, r * sc, Q(q), r * sc < 0.025 ? 0 : 1);

	function cyl(k:String, rgb:Int, c:Vec3, r:Float, h:Float, ?q:Quat, seg = 16, ?scale:Vec3, ?s:Float) {
		part(k, rgb).cylinder(P(c), r * sc, h * sc * (s ?? 1.0), Q(q), seg, scale);
	}

	function frustum(k:String, rgb:Int, c:Vec3, r0:Float, r1:Float, h:Float, ?q:Quat)
		part(k, rgb).frustum(P(c), r0 * sc, r1 * sc, h * sc, Q(q));

	function cone(k:String, rgb:Int, c:Vec3, r:Float, h:Float, ?q:Quat, seg = 16)
		part(k, rgb).cone(P(c), r * sc, h * sc, Q(q), seg);

	function sph(k:String, rgb:Int, c:Vec3, r:Float, seg = 16, rings = 10)
		part(k, rgb).ellipsoid(P(c), new Vec3(r, r, r) * sc, rot, r * sc < 0.05 ? Std.int(Math.min(seg, 8)) : seg, r * sc < 0.05 ? Std.int(Math.min(rings, 5)) : rings);

	// (flat ones, leaves and petals, coarser)
	function ell(k:String, rgb:Int, c:Vec3, s:Vec3, ?q:Quat) {
		var flat = Math.min(s.x, Math.min(s.y, s.z)) * sc < 0.03;
		part(k, rgb).ellipsoid(P(c), s * sc, Q(q), flat ? 10 : 16, flat ? 4 : 10);
	}

	function torus(k:String, rgb:Int, c:Vec3, big:Float, r:Float, seg = 20, sides = 8, ?q:Quat)
		part(k, rgb).torus(P(c), big * sc, r * sc, seg, sides, Q(q));

	function capsule(k:String, rgb:Int, c:Vec3, r:Float, h:Float, ?q:Quat)
		part(k, rgb).capsule(P(c), r * sc, h * sc, Q(q));

	function finish() {
		for (key in order) {
			var p = parts.get(key);
			if (p == null) continue;
			var mesh = new Mesh();
			p.b.into(mesh, d, p.m);
			MeshRenderer.attach(world.node("decor", parent), mesh);
		}
	}

	inline function rnd():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	static function mix(a:Int, b:Int, t:Float):Int {
		var r = Std.int(((a >> 16) & 255) * (1 - t) + ((b >> 16) & 255) * t);
		var g = Std.int(((a >> 8) & 255) * (1 - t) + ((b >> 8) & 255) * t);
		var bl = Std.int((a & 255) * (1 - t) + (b & 255) * t);
		return (r << 16) | (g << 8) | bl;
	}

	// ---- textures, drawn in code

	static function hash(x:Int, y:Int):Float {
		var h = x * 374761393 + y * 668265263;
		h = (h ^ (h >>> 13)) * 1274126177;
		h = h ^ (h >>> 16);
		return (h & 0xffff) / 65535;
	}

	static function noise(x:Float, y:Float):Float {
		var ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
		var a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), e = hash(ix + 1, iy + 1);
		var ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
		return a + (b - a) * ux + (c - a) * uy + (a - b - c + e) * ux * uy;
	}

	static function fbm(x:Float, y:Float):Float
		return noise(x, y) * 0.5 + noise(x * 2.1, y * 2.1) * 0.27 + noise(x * 4.3, y * 4.3) * 0.15 + noise(x * 8.7, y * 8.7) * 0.08;

	function image(w:Int, h:Int, f:(u:Float, v:Float, x:Int, y:Int) -> Int):Texture {
		var px = Bytes.alloc(w * h * 4);
		for (y in 0...h)
			for (x in 0...w) {
				var c = f(x / w, y / h, x, y), o = (y * w + x) * 4;
				px.set(o, (c >> 16) & 255);
				px.set(o + 1, (c >> 8) & 255);
				px.set(o + 2, c & 255);
				px.set(o + 3, 255);
			}
		return Images.mipmapped(d, w, h, px);
	}

	static inline function shade(c:Int, k:Float):Int {
		var r = Std.int(Math.max(0, Math.min(255, ((c >> 16) & 255) * k)));
		var g = Std.int(Math.max(0, Math.min(255, ((c >> 8) & 255) * k)));
		var b = Std.int(Math.max(0, Math.min(255, (c & 255) * k)));
		return (r << 16) | (g << 8) | b;
	}

	// floorboards: boards across, each its own shade, staggered ends, grain and seams
	function planks(base:Int, light:Float, grain:Float, boards:Int):Texture
		return image(512, 512, (u, v, _, _) -> {
			var bi = Std.int(u * boards);
			var k = 0.82 + hash(bi, 7) * 0.3;
			var lv = (v + hash(bi, 3)) * 2, seg = Math.floor(lv);
			k *= 0.9 + hash(bi, seg) * 0.16;
			var g = noise(u * 40 + bi * 13, v * 3 + seg * 7) * 0.6 + noise(u * 180, v * 10 + bi) * 0.4;
			var ring = Math.sin((u * boards - bi) * 22 + g * 7 * grain) * 0.5 + 0.5;
			k *= 0.84 + ring * 0.16 * grain + g * 0.1;
			var edge = Math.min(u * boards - bi, 1 - (u * boards - bi));
			if (edge < 0.014) k *= 0.5;
			if (lv - seg < 0.004) k *= 0.55;
			shade(base, k);
		});

	// a woollen rug: a border of bands, a field of lozenges, wool's mottle
	function rug():Texture {
		var red = 0x9E3B32, cream = 0xEADBC0, navy = 0x25344F, gold = 0xC9963F;
		return image(512, 512, (u, v, x, y) -> {
			var bu = Math.min(u, 1 - u), bv = Math.min(v, 1 - v), b = Math.min(bu * 1.42, bv);
			var c = b < 0.03 ? navy : b < 0.045 ? cream : b < 0.09 ? red : b < 0.1 ? gold : b < 0.115 ? navy : -1;
			if (c < 0) {
				// (a lattice of lozenges, a medallion in the middle)
				var la = ((u * 9 + v * 6.4) % 1 + 1) % 1, lb = ((u * 9 - v * 6.4) % 1 + 1) % 1;
				var m = Math.abs(u - 0.5) * 1.42 + Math.abs(v - 0.5);
				c = m < 0.05 ? gold : m < 0.075 ? red : m < 0.15 ? navy : m < 0.165 ? cream : la < 0.07 || lb < 0.07 ? cream
					: Math.abs(la - 0.5) + Math.abs(lb - 0.5) < 0.16 ? navy : Math.abs(la - 0.5) + Math.abs(lb - 0.5) < 0.22 ? gold : red;
			}
			shade(c, 0.86 + fbm(x * 0.25, y * 0.25) * 0.22 + hash(x, y) * 0.06);
		});
	}

	function gingham(rgb:Int):Texture
		return image(512, 512, (u, v, x, y) -> {
			var a = Std.int(u * 16) % 2 == 0, b = Std.int(v * 16) % 2 == 0;
			var c = a && b ? rgb : a || b ? mix(rgb, 0xFFFFFF, 0.55) : 0xF7F2EA;
			var weave = ((x + y) % 3 == 0 ? 0.94 : 1.0) * (0.95 + noise(x * 0.5, y * 0.5) * 0.08);
			shade(c, weave);
		});

	function brushed():Texture
		return image(256, 256, (u, v, x, y) -> {
			var k = 0.8 + noise(x * 0.05, y * 3.0) * 0.12 + hash(x, y) * 0.04 + fbm(x * 0.02, y * 0.02) * 0.1;
			shade(0xD3D6DA, k);
		});

	function leather(rgb:Int):Texture
		return image(512, 512, (u, v, x, y) -> {
			var cell = noise(x * 0.12, y * 0.12), fine = noise(x * 0.6, y * 0.6);
			var wear = fbm(u * 4, v * 4);
			shade(rgb, 0.78 + cell * 0.18 + fine * 0.08 + wear * 0.18);
		});

	function foam():Texture {
		var cols = [0xE76F51, 0xF4A261, 0xE9C46A, 0x2A9D8F, 0x7CB5E2, 0xB388EB];
		return image(512, 512, (u, v, x, y) -> {
			var tu = u * 6, tv = v * 9, iu = Math.floor(tu), iv = Math.floor(tv), fu = tu - iu, fv = tv - iv;
			// (the jigsaw's tabs: a bump on the tile's edges, given to the neighbour)
			var tab = 0.1;
			if (fu < tab && Math.abs(fv - 0.5) < 0.12 && (iu + iv) % 2 == 0) iu -= 1;
			if (fv < tab && Math.abs(fu - 0.5) < 0.12 && (iu + iv) % 2 == 1) iv -= 1;
			var c = cols[Std.int(Math.abs(iu * 3 + iv * 5)) % cols.length];
			var seam = fu < 0.008 || fv < 0.008 ? 0.7 : 1.0;
			shade(c, seam * (0.92 + hash(x, y) * 0.05 + noise(x * 0.3, y * 0.3) * 0.06));
		});
	}

	function parchment():Texture
		return image(512, 512, (u, v, x, y) -> {
			var crease = Math.abs(noise(u * 5, v * 7) - 0.5) < 0.012 || Math.abs(noise(u * 3 + 9, v * 4) - 0.5) < 0.01 ? 0.9 : 1.0;
			shade(0xEFE3C6, crease * (0.9 + fbm(u * 8, v * 8) * 0.12 + hash(x, y) * 0.03));
		});

	function sand():Texture
		return image(512, 512, (u, v, x, y) -> {
			var k = 0.82 + fbm(x * 0.04, y * 0.04) * 0.2 + hash(x, y) * 0.12 - (hash(x * 7, y) > 0.985 ? 0.25 : 0);
			// (raked lines, faint)
			k *= 0.96 + Math.sin(v * 140 + noise(u * 6, v * 6) * 4) * 0.03;
			shade(0xE3CFA2, k);
		});

	function grass():Texture
		return image(512, 512, (u, v, x, y) -> {
			var blades = hash(x, y >> 1) * 0.5 + noise(x * 0.9, y * 0.25) * 0.5;
			var patch = fbm(u * 6, v * 6);
			var c = mix(0x4E7A2E, 0x8DAA4A, patch);
			shade(c, 0.7 + blades * 0.45);
		});

	function carpet(rgb:Int):Texture
		return image(256, 256, (u, v, x, y) -> shade(rgb, 0.86 + hash(x, y) * 0.1 + noise(x * 0.2, y * 0.2) * 0.08));

	function feltTex():Texture
		return image(256, 256, (u, v, x, y) -> {
			var k = 0.82 + noise(x * 0.35, y * 0.35) * 0.1 + hash(x, y) * 0.06 + fbm(u * 3, v * 3) * 0.14;
			shade(0xFFFFFF, k);
		});
}
