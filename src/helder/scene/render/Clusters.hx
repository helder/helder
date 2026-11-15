package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;

// The view's grid of cells (froxels: tiles across the view, slices of
// depth growing exponentially from the camera) and the lights that reach
// each, on the CPU (ClusteredLights' path without compute; its compute
// path, ClusterShader, does the same work a cell an invocation). A light
// reaches a cell when its sphere (its range about it) meets the cell's box
// in the view; a cell lists the first perCell that do, in the frame's
// order. The lists are the cluster map's texels (map, R32F: a row a tile's
// row and slice, a cell a block of perCell + 1 texels: its count, then
// its lights' rows). Each light is tested against the cells its sphere's
// bounds touch (a few of the grid, not all of it); assign allocates
// nothing.
class Clusters {
	public final tilesX:Int;
	public final tilesY:Int;
	public final slices:Int;
	public final perCell:Int;
	// the cluster map: its width (tilesX * (perCell + 1), 12 at least) and
	// height (tilesY * slices, then lights), its first light's row, its texels
	public final width:Int;
	public final height:Int;
	public final lights:Int;
	public final lightRow:Int;
	public final map:Bytes;
	// the last assign's lens (as ClusterGrid's: the slopes, the near depth, a slice's step of log depth)
	public var slopeX(default, null) = 1.0;
	public var slopeY(default, null) = 1.0;
	public var near(default, null) = 0.1;
	public var step(default, null) = 1.0;
	// the last assign's lists that were full (a light left out of a cell)
	public var overflow(default, null) = 0;

	public function new(tilesX = 16, tilesY = 9, slices = 24, perCell = 32, lights = 0) {
		this.tilesX = tilesX;
		this.tilesY = tilesY;
		this.slices = slices;
		this.perCell = perCell;
		this.lights = lights;
		width = Std.int(Math.max(tilesX * (perCell + 1), FrameLights.FLOATS));
		lightRow = tilesY * slices;
		height = lightRow + lights;
		map = Bytes.alloc(width * height * 4);
		for (_ in 0...slices) {
			depth0.push(0);
			depth1.push(0);
		}
		for (_ in 0...tilesX) {
			slopeX0.push(0);
			slopeX1.push(0);
		}
		for (_ in 0...tilesY) {
			slopeY0.push(0);
			slopeY1.push(0);
		}
	}

	// the lights' rows (FrameLights' data, its first rows of them; zeros after)
	@:noCompletion public function writeLights(l:FrameLights) {
		for (k in 0...lights)
			for (f in 0...FrameLights.FLOATS)
				map.setFloat(((lightRow + k) * width + f) * 4, k < l.count ? l.data[k * FrameLights.FLOATS + f] : 0);
	}

	// the lens for a perspective projection, its slices from near to far
	// (each slice's depths, each tile's slopes: worked out once a frame)
	public function lens(projection:Mat4, near:Float, far:Float) {
		slopeX = 1 / projection.c0.x;
		slopeY = 1 / projection.c1.y;
		this.near = near;
		step = Math.log(far / near) / slices;
		for (z in 0...slices) {
			depth0[z] = z > 0 ? near * Math.exp(z * step) : 0.0;
			depth1[z] = near * Math.exp((z + 1) * step);
		}
		for (x in 0...tilesX) {
			slopeX0[x] = (2.0 * x / tilesX - 1) * slopeX;
			slopeX1[x] = (2.0 * (x + 1) / tilesX - 1) * slopeX;
		}
		for (y in 0...tilesY) {
			slopeY1[y] = (1 - 2.0 * y / tilesY) * slopeY;
			slopeY0[y] = (1 - 2.0 * (y + 1) / tilesY) * slopeY;
		}
	}

	final depth0:Array<Float> = [];
	final depth1:Array<Float> = [];
	final slopeX0:Array<Float> = [];
	final slopeX1:Array<Float> = [];
	final slopeY0:Array<Float> = [];
	final slopeY1:Array<Float> = [];

	// a cell's count, its k-th light's row
	public inline function count(x:Int, y:Int, z:Int):Int
		return Std.int(map.getFloat(((y + z * tilesY) * width + x * (perCell + 1)) * 4));

	public inline function light(x:Int, y:Int, z:Int, k:Int):Int
		return Std.int(map.getFloat(((y + z * tilesY) * width + x * (perCell + 1) + 1 + k) * 4));

	// each cell's lights: of the count lights at (xs, ys, zs) (in the
	// world, their ranges rs), seen through view (the world to the view)
	public function assign(view:Mat4, xs:Array<Float>, ys:Array<Float>, zs:Array<Float>, rs:Array<Float>, count:Int) {
		for (r in 0...lightRow)
			for (x in 0...tilesX)
				map.setFloat((r * width + x * (perCell + 1)) * 4, 0);
		overflow = 0;
		for (k in 0...count) {
			var px = xs[k], py = ys[k], pz = zs[k], r = rs[k];
			// (its centre in the view)
			var cx = view.c0.x * px + view.c1.x * py + view.c2.x * pz + view.c3.x;
			var cy = view.c0.y * px + view.c1.y * py + view.c2.y * pz + view.c3.y;
			var cz = view.c0.z * px + view.c1.z * py + view.c2.z * pz + view.c3.z;
			// (the slices its depths span; in each, the tiles whose boxes' x
			// and y ranges meet its box's: contiguous runs, each a superset
			// of the cells reaches passes)
			var dmin = -cz - r, dmax = -cz + r;
			if (dmax <= 0) continue;
			var z0 = sliceOf(dmin), z1 = sliceOf(dmax);
			for (z in z0...z1 + 1) {
				var d0 = depth0[z], d1 = depth1[z];
				var x0 = -1, x1 = -2;
				for (x in 0...tilesX) {
					var sx0 = slopeX0[x], sx1 = slopeX1[x];
					if (Math.min(sx0 * d0, sx0 * d1) <= cx + r && Math.max(sx1 * d0, sx1 * d1) >= cx - r) {
						if (x0 < 0) x0 = x;
						x1 = x;
					}
				}
				var y0 = -1, y1 = -2;
				for (y in 0...tilesY) {
					var sy1 = slopeY1[y], sy0 = slopeY0[y];
					if (Math.min(sy0 * d0, sy0 * d1) <= cy + r && Math.max(sy1 * d0, sy1 * d1) >= cy - r) {
						if (y0 < 0) y0 = y;
						y1 = y;
					}
				}
				for (y in y0...y1 + 1)
					for (x in x0...x1 + 1)
						if (reaches(x, y, z, cx, cy, cz, r)) {
							var o = ((y + z * tilesY) * width + x * (perCell + 1)) * 4;
							var n = Std.int(map.getFloat(o));
							if (n < perCell) {
								map.setFloat(o + (1 + n) * 4, k);
								map.setFloat(o, n + 1);
							} else
								overflow++;
						}
			}
		}
	}

	// whether a sphere in the view (centre c, radius r) meets cell (x, y, z)'s
	// box: ClusterShader's test, the same numbers
	public function reaches(x:Int, y:Int, z:Int, cx:Float, cy:Float, cz:Float, r:Float):Bool {
		var d0 = depth0[z], d1 = depth1[z];
		var sx0 = slopeX0[x], sx1 = slopeX1[x];
		var sy1 = slopeY1[y], sy0 = slopeY0[y];
		var lx = Math.min(sx0 * d0, sx0 * d1), hx = Math.max(sx1 * d0, sx1 * d1);
		var ly = Math.min(sy0 * d0, sy0 * d1), hy = Math.max(sy1 * d0, sy1 * d1);
		var lz = -d1, hz = -d0;
		var qx = Math.min(Math.max(cx, lx), hx) - cx, qy = Math.min(Math.max(cy, ly), hy) - cy, qz = Math.min(Math.max(cz, lz), hz) - cz;
		return qx * qx + qy * qy + qz * qz <= r * r;
	}

	// (the slice of a depth, clamped to the grid's)
	function sliceOf(d:Float):Int {
		if (d <= near) return 0;
		var z = Math.floor(Math.log(d / near) / step);
		return z < 0 ? 0 : z >= slices ? slices - 1 : z;
	}
}
