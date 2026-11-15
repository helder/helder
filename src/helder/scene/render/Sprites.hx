package helder.scene.render;

import haxe.ds.Vector;
import helder.gfx.Device;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.math.MathTools;

// Quads that face the camera (three's Sprite, Godot's billboard modes), as
// one InstancedMesh: clouds, halos, trees far off, particles of one's own.
// Each sprite is a position (in the world), a width and a height (scene
// units), a turn in the screen's plane, a cell of an atlas and a colour;
// all of them are one instanced draw. The renderer turns them before its
// pass (prepare: from the camera's view-projection, the matrices written
// into the instance data and uploaded), so nothing is allocated a frame.
//
//   mode Spherical  facing the camera, upright on the screen (turned by rotation)
//   mode Axis       turning about axis only (a tree, a cloud's column, a
//                   flame): upright along it, as near facing the camera as it can
//   mode Fixed      facing +z, turned by rotation about z (a decal of one's own)
//
// Its material is any (Material.unlit with Additive: halos; with a texture
// and alphaCutoff: leaves; a lit one: its normal faces the camera, so it is
// lit as a card). See-through ones are drawn after the opaque surfaces
// (Material.blend), Alpha's sorted far to near among themselves when the
// camera moves. An atlas is columns by rows cells of the material's
// texture, left to right then top to bottom (the material's uvScale set to a
// cell's share; a sprite's cell moves its uvs there: PbrShader.instanceUv).
//
//   var halos = new Sprites(device, Material.unlit({color: gold, texture: glow, blend: true, blending: Additive}), 64);
//   Sprites.attach(world.node("halos"), halos);
//   halos.count = lamps.length;
//   for (i in 0...halos.count) halos.set(i, lamps[i].x, lamps[i].y, lamps[i].z, 0.8, 0.8);
//
// InstancedMesh's own setTransform and setMatrix are overwritten by the
// turn: a sprite is set with set, setPosition, setSize, setRotation,
// setCell and setColor. Its bounds (InstancedMesh.bounds: the whole set's,
// culled by them) are the program's, as an InstancedMesh's.
class Sprites extends InstancedMesh {
	// (a sprite's floats: x, y, z, width, height, rotation, cell, r, g, b)
	static inline var FIELDS = 10;

	// what they are drawn with (the quad's)
	public final material:Material;
	// how they face the camera
	public var mode:SpriteMode;
	// the axis Axis turns about (the world's; unit)
	public var axis:Vec3;
	// the atlas' cells (1 by 1: the whole image)
	public final columns:Int;
	public final rows:Int;

	var sprites:Vector<Float>;
	// (the instances' order, far to near when sorted, and their depths)
	var order:Vector<Int>;
	var depths:Vector<Float>;
	// (what the last turn was made for: rewritten when the camera or a sprite changed)
	var turned = false;
	var lastViewProj:Mat4 = Mat4.identity();
	var lastCount = -1;

	// capacity sprites of material (count of them shown: all by default);
	// their quad (Geometry.plane) made on device (null: none, their data
	// alone: tests)
	public function new(device:Null<Device>, material:Material, capacity:Int, ?options:SpritesOptions) {
		super(device == null ? new Mesh() : Shapes.of(device, Geometry.plane(), material), capacity, options?.count ?? -1);
		this.material = material;
		mode = options?.mode ?? Spherical;
		var a = options?.axis ?? new Vec3(0, 1, 0);
		var l = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
		axis = l > 0 ? a / l : new Vec3(0, 1, 0);
		columns = Std.int(Math.max(1, options?.columns ?? 1));
		rows = Std.int(Math.max(1, options?.rows ?? 1));
		if (columns > 1 || rows > 1) material.uvScale = new Vec2(1 / columns, 1 / rows);
		castShadows = material.castShadows;
		sprites = new Vector(capacity * FIELDS);
		order = new Vector(capacity);
		depths = new Vector(capacity);
		for (i in 0...capacity)
			blank(i);
	}

	public static inline function attach(node:Node, sprites:Sprites):Sprites {
		InstancedMesh.attach(node, sprites);
		return sprites;
	}

	// sprite i at x, y, z, of width and height, turned by rotation
	// (radians, counter-clockwise on the screen; Axis: none), its atlas cell
	// (0 the first, left to right then down), its colour kept
	public function set(i:Int, x:Float, y:Float, z:Float, width:Float, height:Float, rotation = 0.0, cell = 0) {
		var o = i * FIELDS;
		sprites[o] = x;
		sprites[o + 1] = y;
		sprites[o + 2] = z;
		sprites[o + 3] = width;
		sprites[o + 4] = height;
		sprites[o + 5] = rotation;
		sprites[o + 6] = cell;
		turned = false;
	}

	override public function setPosition(i:Int, x:Float, y:Float, z:Float) {
		var o = i * FIELDS;
		sprites[o] = x;
		sprites[o + 1] = y;
		sprites[o + 2] = z;
		turned = false;
	}

	public function setSize(i:Int, width:Float, height:Float) {
		sprites[i * FIELDS + 3] = width;
		sprites[i * FIELDS + 4] = height;
		turned = false;
	}

	public function setRotation(i:Int, rotation:Float) {
		sprites[i * FIELDS + 5] = rotation;
		turned = false;
	}

	// (column + columns * row)
	public function setCell(i:Int, cell:Int) {
		sprites[i * FIELDS + 6] = cell;
		turned = false;
	}

	// sprite i's colour (linear rgb, times the material's base colour)
	override public function setColor(i:Int, r:Float, g:Float, b:Float) {
		var o = i * FIELDS;
		sprites[o + 7] = r;
		sprites[o + 8] = g;
		sprites[o + 9] = b;
		turned = false;
	}

	// sprite i's field: 0 to 2 its position, 3 and 4 its size, 5 its
	// rotation, 6 its cell, 7 to 9 its colour
	public inline function get(i:Int, field:Int):Float
		return sprites[i * FIELDS + field];

	override public function resize(capacity:Int) {
		var old = this.capacity;
		super.resize(capacity);
		if (capacity == old) return;
		var s = new Vector<Float>(capacity * FIELDS);
		Vector.blit(sprites, 0, s, 0, Std.int(Math.min(old, capacity)) * FIELDS);
		sprites = s;
		order = new Vector(capacity);
		depths = new Vector(capacity);
		for (i in old...capacity)
			blank(i);
		lastCount = -1;
		turned = false;
	}

	// the instances turned to the camera of viewProj (the renderer's, before
	// its upload): its axes from the view-projection's rows (a symmetric
	// projection's right and up, its back the third row's opposite); nothing
	// done when neither the camera nor a sprite changed
	override public function prepare(viewProj:Mat4) {
		if (turned && lastCount == count && same(viewProj, lastViewProj)) return;
		turned = true;
		lastViewProj = viewProj;
		var right = unit(new Vec3(viewProj.c0.x, viewProj.c1.x, viewProj.c2.x));
		var up = unit(new Vec3(viewProj.c0.y, viewProj.c1.y, viewProj.c2.y));
		var back = unit(new Vec3(viewProj.c0.z, viewProj.c1.z, viewProj.c2.z)) * -1;
		// (see-through by alpha: far to near, each frame's order from the last's)
		var sorted = material.blend && material.blending == Alpha;
		if (count != lastCount)
			for (i in 0...count)
				order[i] = i;
		lastCount = count;
		if (sorted) {
			for (i in 0...count) {
				var o = i * FIELDS;
				// (the view's depth: clip w plus z, both growing away from the eye,
				// a perspective's w and an orthographic's z)
				depths[i] = (viewProj.c0.w + viewProj.c0.z) * sprites[o] + (viewProj.c1.w + viewProj.c1.z) * sprites[o + 1]
					+ (viewProj.c2.w + viewProj.c2.z) * sprites[o + 2];
			}
			for (k in 1...count) {
				var i = order[k], d = depths[i], j = k - 1;
				while (j >= 0 && depths[order[j]] < d) {
					order[j + 1] = order[j];
					j--;
				}
				order[j + 1] = i;
			}
		}
		var d = data;
		for (k in 0...count) {
			var i = sorted ? order[k] : k;
			var s = i * FIELDS;
			var w = sprites[s + 3], h = sprites[s + 4], c = Math.cos(sprites[s + 5]), sn = Math.sin(sprites[s + 5]);
			var r:Vec3, u:Vec3, n:Vec3;
			switch mode {
				case Axis:
					// (upright along the axis, its face as near the camera's as the axis lets it)
					var x = cross(axis, back);
					var l = Math.sqrt(x.x * x.x + x.y * x.y + x.z * x.z);
					r = l > 1e-6 ? x / l : right;
					u = axis;
					n = cross(r, u);
				case Fixed:
					r = new Vec3(c, sn, 0);
					u = new Vec3(-sn, c, 0);
					n = new Vec3(0, 0, 1);
				case _:
					r = right * c + up * sn;
					u = up * c - right * sn;
					n = back;
			}
			var o = k * InstancedMesh.STRIDE;
			d.setFloat(o, r.x * w);
			d.setFloat(o + 4, r.y * w);
			d.setFloat(o + 8, r.z * w);
			d.setFloat(o + 12, sprites[s + 7] - 1);
			d.setFloat(o + 16, u.x * h);
			d.setFloat(o + 20, u.y * h);
			d.setFloat(o + 24, u.z * h);
			d.setFloat(o + 28, sprites[s + 8] - 1);
			d.setFloat(o + 32, n.x);
			d.setFloat(o + 36, n.y);
			d.setFloat(o + 40, n.z);
			d.setFloat(o + 44, sprites[s + 9] - 1);
			d.setFloat(o + 48, sprites[s]);
			d.setFloat(o + 52, sprites[s + 1]);
			d.setFloat(o + 56, sprites[s + 2]);
			// (the matrix's last w: 1 plus the cell, column + 256 * row)
			var cell = Std.int(sprites[s + 6]);
			d.setFloat(o + 60, 1 + cell % columns + 256 * Std.int(cell / columns));
		}
		changed();
	}

	// (sprite i at the origin, 1 by 1, white, the first cell)
	function blank(i:Int) {
		var o = i * FIELDS;
		for (k in 0...FIELDS)
			sprites[o + k] = k == 3 || k == 4 || k >= 7 ? 1 : 0;
	}

	static function same(a:Mat4, b:Mat4):Bool {
		for (k in 0...4) {
			var x = MathTools.col(a, k), y = MathTools.col(b, k);
			if (x.x != y.x || x.y != y.y || x.z != y.z || x.w != y.w) return false;
		}
		return true;
	}

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	static inline function unit(a:Vec3):Vec3 {
		var l = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
		return l > 0 ? a / l : a;
	}
}

// how sprites face the camera (Sprites.mode)
enum abstract SpriteMode(Int) to Int {
	// facing the camera, upright on the screen
	var Spherical;
	// turning about Sprites.axis only, upright along it
	var Axis;
	// facing +z, turned about z by their rotation
	var Fixed;
}

// what Sprites are made with (each optional): how they face the camera
// (Spherical), the axis Axis turns about (y), the atlas' columns and rows
// (1 by 1), the sprites shown (all)
typedef SpritesOptions = {
	?mode:SpriteMode,
	?axis:Vec3,
	?columns:Int,
	?rows:Int,
	?count:Int
}
