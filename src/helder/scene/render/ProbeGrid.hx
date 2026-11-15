package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.scene.Node;

// A grid of light probes, a component of a node: a box (size, centred on
// its node's position, the world's axes) of nx x ny x nz probes at its
// corners and between, each the light there as spherical harmonics (Sh).
// With Probes, a draw whose centre is in the box is lit by the probes
// around it, blended trilinearly on the CPU (Unity's light probes, on a
// grid): its diffuse light, per draw, evaluated at its vertices. Filled by
// a program (set, fill), or read from its bytes (read, write: baked once,
// by a tool or a program, kept as an asset).
//   var grid = new ProbeGrid(new Vec3(12, 4, 8), 4, 2, 3);
//   grid.fill(p -> Sh.ofHemisphere(...));
//   ProbeGrid.attach(world.node("gi"), grid);
class ProbeGrid {
	public static final KIND = new StoreKind<ProbeGrid>("probeGrid");

	// the box's size (scene units) and its probes along each axis (2 or more)
	public final size:Vec3;
	public final nx:Int;
	public final ny:Int;
	public final nz:Int;
	// each probe, x fastest, then y, then z
	public final probes:Array<Sh>;
	// its light's scale
	public var intensity = 1.0;
	public var node(default, null):Node = Node.NONE;

	public function new(size:Vec3, nx:Int, ny:Int, nz:Int) {
		if (nx < 2 || ny < 2 || nz < 2) throw "helder.scene: ProbeGrid: two probes or more along each axis";
		this.size = size;
		this.nx = nx;
		this.ny = ny;
		this.nz = nz;
		probes = [for (_ in 0...nx * ny * nz) new Sh()];
	}

	// grid on node (a node has one)
	public static function attach(node:Node, grid:ProbeGrid):ProbeGrid {
		grid.node = node;
		return node.world.store(KIND).set(node, grid);
	}

	public static inline function of(node:Node):Null<ProbeGrid>
		return node.world.store(KIND).get(node);

	// probe (i, j, k)'s place relative to the box's centre
	public function offset(i:Int, j:Int, k:Int):Vec3
		return new Vec3(size.x * (i / (nx - 1) - 0.5), size.y * (j / (ny - 1) - 0.5), size.z * (k / (nz - 1) - 0.5));

	public inline function at(i:Int, j:Int, k:Int):Sh
		return probes[(k * ny + j) * nx + i];

	public function set(i:Int, j:Int, k:Int, sh:Sh)
		probes[(k * ny + j) * nx + i] = sh;

	// each probe's light from f (its place, relative to the box's centre)
	public function fill(f:Vec3->Sh) {
		for (k in 0...nz)
			for (j in 0...ny)
				for (i in 0...nx)
					set(i, j, k, f(offset(i, j, k)));
	}

	// whether a point relative to the box's centre is inside it
	public inline function holds(p:Vec3):Bool
		return Math.abs(p.x) <= size.x * 0.5 && Math.abs(p.y) <= size.y * 0.5 && Math.abs(p.z) <= size.z * 0.5;

	// the light at a point relative to the box's centre (held in the box),
	// its eight probes blended trilinearly, into out (nothing allocated)
	public function sample(p:Vec3, out:Sh):Sh {
		inline function cell(v:Float, s:Float, n:Int):Float
			return Math.min(Math.max((v / s + 0.5) * (n - 1), 0), n - 1);
		var fx = cell(p.x, size.x, nx), fy = cell(p.y, size.y, ny), fz = cell(p.z, size.z, nz);
		var i = Std.int(Math.min(fx, nx - 2)), j = Std.int(Math.min(fy, ny - 2)), k = Std.int(Math.min(fz, nz - 2));
		var tx = fx - i, ty = fy - j, tz = fz - k;
		var c = out.coefficients;
		for (q in 0...27)
			c[q] = 0;
		for (dz in 0...2)
			for (dy in 0...2)
				for (dx in 0...2) {
					var w = (dx == 0 ? 1 - tx : tx) * (dy == 0 ? 1 - ty : ty) * (dz == 0 ? 1 - tz : tz) * intensity;
					if (w > 0) out.addScaled(at(i + dx, j + dy, k + dz), w);
				}
		return out;
	}

	// the grid as bytes (its size, counts, each probe's 27 floats; read gives it back)
	public function write():Bytes {
		var b = Bytes.alloc(28 + probes.length * 108);
		b.setInt32(0, 0x42504847); // "GHPB"
		b.setFloat(4, size.x);
		b.setFloat(8, size.y);
		b.setFloat(12, size.z);
		b.setInt32(16, nx);
		b.setInt32(20, ny);
		b.setInt32(24, nz);
		for (p in 0...probes.length)
			for (q in 0...27)
				b.setFloat(28 + p * 108 + q * 4, probes[p].coefficients[q]);
		return b;
	}

	public static function read(b:Bytes):ProbeGrid {
		if (b.length < 28 || b.getInt32(0) != 0x42504847) throw "helder.scene: ProbeGrid.read: not a probe grid";
		var g = new ProbeGrid(new Vec3(b.getFloat(4), b.getFloat(8), b.getFloat(12)), b.getInt32(16), b.getInt32(20), b.getInt32(24));
		if (b.length < 28 + g.probes.length * 108) throw "helder.scene: ProbeGrid.read: too few bytes";
		for (p in 0...g.probes.length)
			for (q in 0...27)
				g.probes[p].coefficients[q] = b.getFloat(28 + p * 108 + q * 4);
		return g;
	}
}
