package helder.scene.render;

import helder.math.Mat4;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Node;
import helder.scene.StoreKind;

// Levels of detail, a component of a node: its meshes from the finest to
// the coarsest, each drawn while the node covers at least its `until` of
// the view's height (its bounds' sphere, Babylon's screen coverage: the
// same at any field of view or resolution), the last one's 0 by default
// (drawn however far; an until past 0: beyond it nothing is drawn). A
// level holds within a band of hysteresis about its threshold (0.1: 5%
// each way), so a node at the edge does not flicker between two. The
// renderer picks the level as it extracts the frame's draws (Lod.pick:
// set when a program first attaches one, so a program without links
// none of this); nodes of one level and material still batch.
//
//   Lod.attach(world.node("tree"), [{mesh: hi, until: 0.15}, {mesh: mid, until: 0.04}, {mesh: lo}]);
//
// A visible range (Lod.range: Godot's, three's LOD with nothing past it)
// draws a node and what is under it only while the camera is between
// begin and end metres from it: a cluster of nodes swapped for one far
// off (HLOD). The level is the last camera's: a world drawn by several
// cameras keeps one level a node.
class Lod {
	@:noCompletion public static final KIND = new StoreKind<Lod>("lod");
	public static final RANGE = new StoreKind<VisibleRange>("visibleRange");

	public final levels:Array<LodLevel>;
	// the band about each threshold a level holds within (a share of it)
	public var hysteresis = 0.1;
	// the last level drawn (levels.length: none; -1 before the first frame)
	public var level(default, null) = -1;
	// the last share of the view's height its bounds covered
	public var coverage(default, null) = 0.0;

	public function new(levels:Array<LodLevel>, hysteresis = 0.1) {
		if (levels.length == 0) throw "helder.scene: a Lod of no levels";
		this.levels = levels;
		this.hysteresis = hysteresis;
	}

	// the levels on node (its MeshRenderer the first's, made if it has none)
	public static function attach(node:Node, levels:Array<LodLevel>, hysteresis = 0.1):Lod {
		pick = picked;
		var l = node.world.store(KIND).set(node, new Lod(levels, hysteresis));
		if (MeshRenderer.of(node) == null) MeshRenderer.attach(node, levels[0].mesh);
		return l;
	}

	public static inline function of(node:Node):Null<Lod>
		return node.world.store(KIND).get(node);

	// node and what is under it drawn only while the camera is begin to end
	// metres from it
	public static function range(node:Node, begin:Float, end:Float):VisibleRange {
		pick = picked;
		return node.world.store(RANGE).set(node, new VisibleRange(begin, end));
	}

	// the renderer's: a node's mesh at the level its coverage picks, null
	// when it is not drawn (past its last level, out of its range), the
	// view the renderer's (its viewProj and eye as it extracts: a struct
	// through a function value would be boxed); null until a Lod or a range
	// is made
	@:noCompletion public static var pick:Null<(Node, Mesh, Renderer) -> Null<Mesh>> = null;

	static function picked(node:Node, mesh:Mesh, r:Renderer):Null<Mesh>
		return meshOf(node, mesh, @:privateAccess r.extractViewProj, @:privateAccess r.extractEye);

	// a node's mesh seen through viewProj from eye: its level's (Lod), null
	// past its last level or out of its visible range, else mesh
	public static function meshOf(node:Node, mesh:Mesh, viewProj:Mat4, eye:Vec3):Null<Mesh> {
		var world = node.world;
		var ranges = world.store(RANGE);
		if (ranges.length > 0) {
			var n = node;
			while (!n.isNone) {
				var r = ranges.get(n);
				if (r != null) {
					var p = n.worldPosition(), dx = p.x - eye.x, dy = p.y - eye.y, dz = p.z - eye.z;
					var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
					if (d < r.begin || d >= r.end) return null;
				}
				n = n.parent;
			}
		}
		var lod = world.store(KIND).get(node);
		if (lod == null) return mesh;
		var b = lod.levels[0].mesh.bounds;
		if (b.isEmpty()) return lod.levels[0].mesh;
		var model = node.worldMatrix();
		// (its bounds' sphere in the world: the box's centre and half diagonal, by the matrix's largest scale)
		var c = model * new Vec4((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2, 1);
		var hx = (b.max.x - b.min.x) / 2, hy = (b.max.y - b.min.y) / 2, hz = (b.max.z - b.min.z) / 2;
		var s = Math.max(len(model.c0), Math.max(len(model.c1), len(model.c2)));
		var radius = Math.sqrt(hx * hx + hy * hy + hz * hz) * s;
		var k = lod.choose(coverageOf(viewProj, c.x, c.y, c.z, radius));
		return k < lod.levels.length ? lod.levels[k].mesh : null;
	}

	static inline function len(v:Vec4):Float
		return Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);

	// the share of the view's height a sphere (centre x, y, z, radius r)
	// covers through viewProj: its radius times the projection's vertical
	// scale (the length of the matrix's second row: the view a rotation)
	// over its depth (the fourth row's w; 1 for an orthographic camera)
	public static function coverageOf(viewProj:Mat4, x:Float, y:Float, z:Float, r:Float):Float {
		var m = viewProj;
		var sy = Math.sqrt(m.c0.y * m.c0.y + m.c1.y * m.c1.y + m.c2.y * m.c2.y);
		var w = m.c0.w * x + m.c1.w * y + m.c2.w * z + m.c3.w;
		return w > 0.0001 ? r * sy / w : 1e9;
	}

	// the level for a coverage, from the last one within its bands
	// (levels.length: none)
	public function choose(coverage:Float):Int {
		this.coverage = coverage;
		var n = levels.length;
		var k = level;
		if (k < 0) {
			// (the first frame: the plain thresholds)
			k = 0;
			while (k < n && coverage < until(k))
				k++;
		} else {
			var up = 1 + hysteresis / 2, down = 1 - hysteresis / 2;
			while (k > 0 && coverage >= until(k - 1) * up)
				k--;
			while (k < n && coverage < until(k) * down)
				k++;
		}
		return level = k;
	}

	inline function until(k:Int):Float
		return untilOf(levels[k]);

	// a level's threshold (none given: 0, however far)
	public static inline function untilOf(l:LodLevel):Float
		return l.until != null ? l.until : 0.0;
}

// a level of a Lod ({mesh: m, until: 0.1}): its mesh, the least share of
// the view's height it is drawn at (null: 0, however far)
typedef LodLevel = {
	mesh:Mesh,
	?until:Float
}

// a node's visible range (Lod.range): metres from the camera
class VisibleRange {
	public var begin:Float;
	public var end:Float;

	public function new(begin:Float, end:Float) {
		this.begin = begin;
		this.end = end;
	}
}
