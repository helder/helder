package helder.scene.render;

import helder.gfx.Device;
import helder.math.Mat4;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Node;
import helder.scene.math.MathTools;

// Text in the world (Godot's Label3D and TextMesh, three's TextGeometry): a
// component drawing a text's glyphs as geometry (Geometry.text: helder.text's
// layout, its outlines through helder.canvas, flat or extruded) in one
// instanced draw, sized in the scene's units (size: the em's height),
// centred on its node (align: its lines left, centred or right), depth
// tested, fogged and sorted with the scene, sharp at any distance. Unlit by
// default (its colour as given); lit: a lambert material, or any of the
// program's. billboard: turned to face the camera each frame (its node's
// position and scale kept). Setting text makes its geometry again (a
// score's change, not a frame's); nothing is allocated a frame. Rays hit
// it (world.raycast: its triangles).
//
//   var label = Text3D.attach(world.node("score"), new Text3D(device, font, "0", {size: 0.3, billboard: true}));
//   label.text = Std.string(score);
class Text3D extends InstancedMesh {
	public final font:helder.text.FontFile;
	public var text(default, set):String;
	public final size:Float;
	public final depth:Float;
	public final align:Float;
	public final material:Material;
	// turned to face the camera
	public var billboard:Bool;
	// its node (Text3D.attach's)
	public var node(default, null):Node = Node.NONE;
	final on:Null<Device>;
	final options:Null<Text3DOptions>;

	public function new(device:Null<Device>, font:helder.text.FontFile, text:String, ?options:Text3DOptions) {
		var depth = options?.depth ?? 0.0;
		var color = options?.color ?? new Vec4(1, 1, 1, 1);
		var material = options?.material ?? (options?.lit == true ? Material.lambert({color: color, doubleSided: depth == 0}) : Material.unlit({color: color, doubleSided: depth == 0}));
		super(make(device, font, text, material, options), 1);
		on = device;
		this.font = font;
		this.options = options;
		this.material = material;
		this.depth = depth;
		size = options?.size ?? 0.3;
		align = options?.align ?? 0.5;
		billboard = options?.billboard ?? false;
		castShadows = options?.castShadows ?? false;
		this.text = text;
		built = true;
	}

	public static function attach(node:Node, t:Text3D):Text3D {
		t.node = node;
		InstancedMesh.attach(node, t);
		return t;
	}

	// (its mesh made: a text set after makes it again)
	var built = false;

	function set_text(s:String):String {
		if (s == text) return s;
		if (built) {
			// (the new glyphs' primitives in its mesh, the old ones let go)
			var fresh = make(on, font, s, material, options);
			mesh.take(fresh);
			if (on != null) fresh.dispose(on);
		}
		changed();
		return text = s;
	}

	// (its glyphs centred on its node: across by align, the lines' middle at 0, the depth's too)
	static function make(device:Null<Device>, font:helder.text.FontFile, s:String, material:Material, options:Null<Text3DOptions>):Mesh {
		var depth = options?.depth ?? 0.0;
		var g = Geometry.text(font, s, {
			size: options?.size ?? 0.3,
			depth: depth,
			align: options?.align ?? 0.5,
			bevelSize: options?.bevelSize,
			lineHeight: options?.lineHeight,
			letterSpacing: options?.letterSpacing
		});
		var m = new Mesh();
		if (g.count == 0) return m;
		var b = g.bounds;
		var moved = g.transformed(Mat4.translation(0, -(b.min.y + b.max.y) / 2, -depth / 2));
		if (device != null) m.addData(device, moved, material) else m.addCpu(moved, material);
		return m;
	}

	// (its instance's matrix: its node's, turned to the camera when billboard)
	override public function prepare(viewProj:Mat4) {
		if (node.isNone || !node.valid) return;
		var m = node.worldMatrix();
		if (billboard) {
			var sx = len(m.c0.x, m.c0.y, m.c0.z), sy = len(m.c1.x, m.c1.y, m.c1.z), sz = len(m.c2.x, m.c2.y, m.c2.z);
			var right = unit(new Vec3(viewProj.c0.x, viewProj.c1.x, viewProj.c2.x));
			var up = unit(new Vec3(viewProj.c0.y, viewProj.c1.y, viewProj.c2.y));
			var back = unit(new Vec3(viewProj.c0.z, viewProj.c1.z, viewProj.c2.z)) * -1;
			m = new Mat4(new Vec4(right.x * sx, right.y * sx, right.z * sx, 0), new Vec4(up.x * sy, up.y * sy, up.z * sy, 0),
				new Vec4(back.x * sz, back.y * sz, back.z * sz, 0), m.c3);
		}
		var d = data;
		for (c in 0...4) {
			var col = MathTools.col(m, c);
			d.setFloat(c * 16, col.x);
			d.setFloat(c * 16 + 4, col.y);
			d.setFloat(c * 16 + 8, col.z);
			// (the first three columns' w: the colour less 1, white)
			d.setFloat(c * 16 + 12, c == 3 ? 1 : 0);
		}
		changed();
	}

	static inline function len(x:Float, y:Float, z:Float):Float
		return Math.sqrt(x * x + y * y + z * z);

	static inline function unit(a:Vec3):Vec3 {
		var l = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
		return l > 0 ? a / l : a;
	}
}

// what a Text3D is made with (each optional): the em's height (0.3), a
// depth (0: flat, double-sided), a bevel, the lines' alignment (0.5:
// centred), height and letter spacing (Geometry.text's), its colour
// (white), lit (false: unlit, its colour as given) or a material of its
// own, turned to the camera (billboard), casting shadows (false)
typedef Text3DOptions = {
	?size:Float,
	?depth:Float,
	?bevelSize:Float,
	?align:Float,
	?lineHeight:Float,
	?letterSpacing:Float,
	?color:Vec4,
	?lit:Bool,
	?material:Material,
	?billboard:Bool,
	?castShadows:Bool
}
