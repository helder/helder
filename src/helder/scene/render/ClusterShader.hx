package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// ClusteredLights' compute path (Device.has(Compute)): one invocation a
// cell of the view's grid, each testing every light of the frame (lights:
// FrameLights' data, three vectors a light, the first its position and
// range) against its box in the view, the ones that reach it written after
// its count into its block of the cluster map (an R32F storage texture,
// the fragment stage samples it as it samples the CPU's): Clusters.assign's
// work, the same test in the same order, so both give the same lists; and
// past the cells an invocation a light's vector, copying it into the map's
// lights' rows (Clusters.writeLights': the CPU writes no storage texture).
@:structInit @:publicFields class ClusterGrid {
	// the camera's view (the world to the view: the camera down -z)
	var view:Mat4;
	// x and y: the view's slopes (one over the projection's first two
	// diagonal entries), z: the first slice's near depth, w: a slice's step
	// of log depth (log(far / near) over the slices)
	var lens:Vec4;
	var tilesX:Int;
	var tilesY:Int;
	var slices:Int;
	// a cell's lights at most, the frame's lights, the map's lights' rows,
	// the first of them
	var perCell:Int;
	var lights:Int;
	var rows:Int;
	var lightRow:Int;
}

final ClusterAssign = compute({
	size: [64],
	main: function(id:ComputeInput, p:{var grid:ClusterGrid; var lights:Storage<Vec4>; @:format(R32F) var clusterMap:StorageTexture;}) {
		var cells = p.grid.tilesX * p.grid.tilesY * p.grid.slices;
		if (id.x >= cells + p.grid.rows * 3) return;
		if (id.x >= cells) {
			// (a light's vector into its row)
			var j = id.x - cells;
			var light = Std.int(j / 3);
			var part = j - light * 3;
			var v = p.lights[j];
			var row = p.grid.lightRow + light;
			textureStore(p.clusterMap, part * 4, row, vec4(v.x, 0, 0, 0));
			textureStore(p.clusterMap, part * 4 + 1, row, vec4(v.y, 0, 0, 0));
			textureStore(p.clusterMap, part * 4 + 2, row, vec4(v.z, 0, 0, 0));
			textureStore(p.clusterMap, part * 4 + 3, row, vec4(v.w, 0, 0, 0));
			return;
		}
		var x = id.x % p.grid.tilesX;
		var rest = Std.int(id.x / p.grid.tilesX);
		var y = rest % p.grid.tilesY;
		var z = Std.int(rest / p.grid.tilesY);
		// (the cell's box in the view: its tile's slopes at its slice's depths,
		// the first slice from the camera)
		var d0 = 0.0;
		if (z > 0) d0 = p.grid.lens.z * exp(z * p.grid.lens.w);
		var d1 = p.grid.lens.z * exp((z + 1) * p.grid.lens.w);
		var sx0 = (2.0 * x / p.grid.tilesX - 1) * p.grid.lens.x;
		var sx1 = (2.0 * (x + 1) / p.grid.tilesX - 1) * p.grid.lens.x;
		var sy1 = (1 - 2.0 * y / p.grid.tilesY) * p.grid.lens.y;
		var sy0 = (1 - 2.0 * (y + 1) / p.grid.tilesY) * p.grid.lens.y;
		var lo = vec3(min(sx0 * d0, sx0 * d1), min(sy0 * d0, sy0 * d1), -d1);
		var hi = vec3(max(sx1 * d0, sx1 * d1), max(sy1 * d0, sy1 * d1), -d0);
		var column = x * (p.grid.perCell + 1);
		var row = y + z * p.grid.tilesY;
		var n = 0;
		var k = 0;
		while (k < p.grid.lights) {
			var pos = p.lights[k * 3];
			var c = (p.grid.view * vec4(pos.xyz, 1)).xyz;
			var q = clamp(c, lo, hi) - c;
			if (n < p.grid.perCell && dot(q, q) <= pos.w * pos.w) {
				textureStore(p.clusterMap, column + 1 + n, row, vec4(k, 0, 0, 0));
				n += 1;
			}
			k += 1;
		}
		textureStore(p.clusterMap, column, row, vec4(n, 0, 0, 0));
	}
});
