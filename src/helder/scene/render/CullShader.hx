package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// InstanceCulling's compute path (Device.has(Compute)): an invocation an
// instance of a set, its bounds' sphere (the set's mesh's, through its
// matrix) tested against the view's six planes and its level picked by its
// share of the view's height (Lod's coverage, the levels' thresholds); a
// kept one's matrix appended to its level's part of the output (a storage
// buffer, the set's instance buffer for its draws) and counted into the
// instances of each of its level's indirect draws (five Ints a draw, MAX
// of them a level): InstanceCulling.cullCpu's work.
@:structInit @:publicFields class CullView {
	// the view's planes (a, b, c, d: inside where a x + b y + c z + d > 0)
	@:length(6) var planes:Array<Vec4>;
	// the view-projection's fourth row (a point's w: its depth)
	var depthRow:Vec4;
	// the set's mesh's bounds' sphere (its centre, w its radius)
	var sphere:Vec4;
	// the levels' thresholds (Lod's until: x the first's ... w the fourth's)
	var until:Vec4;
	// x: the projection's vertical scale (Lod.coverageOf's)
	var scale:Vec4;
	var count:Int;
	var levels:Int;
	var capacity:Int;
}

final CullInstances = compute({
	size: [64],
	main: function(id:ComputeInput, p:{var view:CullView; var instances:Storage<Mat4>; var out:RWStorage<Mat4>; var args:RWStorage<Int>;}) {
		if (id.x >= p.view.count) return;
		var m = p.instances[id.x];
		var c = (m * vec4(p.view.sphere.xyz, 1)).xyz;
		var a = (m * vec4(1, 0, 0, 0)).xyz;
		var b = (m * vec4(0, 1, 0, 0)).xyz;
		var e = (m * vec4(0, 0, 1, 0)).xyz;
		var r = p.view.sphere.w * sqrt(max(dot(a, a), max(dot(b, b), dot(e, e))));
		var inside = true;
		var k = 0;
		while (k < 6) {
			if (dot(p.view.planes[k].xyz, c) + p.view.planes[k].w < -r) inside = false;
			k += 1;
		}
		if (!inside) return;
		var w = dot(p.view.depthRow.xyz, c) + p.view.depthRow.w;
		var cover = 1000000000.0;
		if (w > 0.0001) cover = r * p.view.scale.x / w;
		var level = 4;
		if (cover >= p.view.until.w) level = 3;
		if (cover >= p.view.until.z) level = 2;
		if (cover >= p.view.until.y) level = 1;
		if (cover >= p.view.until.x) level = 0;
		if (level >= p.view.levels) return;
		var slot = atomicAdd(p.args, level * 20 + 1, 1);
		atomicAdd(p.args, level * 20 + 6, 1);
		atomicAdd(p.args, level * 20 + 11, 1);
		atomicAdd(p.args, level * 20 + 16, 1);
		p.out[level * p.view.capacity + slot] = m;
	}
});
