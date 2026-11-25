import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The compute tier's test stages (ComputeCheck): a prefix sum's step, a
// particle move that appends the particles it keeps and counts them into
// an indirect draw's arguments, a storage texture's gradient; and the
// render stages that draw their results (the kept particles as instances
// from the storage buffer, the texture sampled). Then workgroup memory and
// subgroups: a reduction (Sums, the design's), a prefix sum in workgroup
// memory (Prefix), the other subgroup operations' workgroup results
// (Extremes) and the lanes' ids checked against each other (Lanes).
@:structInit @:publicFields class ScanStep {
	var offset:Int;
	var count:Int;
}

@:structInit @:publicFields class Particle {
	// xy: the centre (clip space), w: 1 a particle to keep
	var pos:Vec4;
	var vel:Vec4;
}

@:structInit @:publicFields class MoveStep {
	var dt:Float;
	var count:Int;
}

@:structInit @:publicFields class GradientSize {
	var width:Int;
	var height:Int;
}

@:structInit @:publicFields class Count {
	var n:Int;
}

@:structInit @:publicFields class DotVertex {
	var corner:Vec2;
	var center:Vec4;
}

@:structInit @:publicFields class DotVaryings {
	var pos:Vec4;
}

@:structInit @:publicFields class ImageVertex {
	var pos:Vec2;
	var uv:Vec2;
}

@:structInit @:publicFields class ImageVaryings {
	var pos:Vec4;
	var uv:Vec2;
}

// one step of Hillis and Steele's inclusive scan: out[i] = in[i] + in[i - offset]
final Scan = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:ScanStep, src:Storage<Int>, dst:RWStorage<Int>}) {
		var i = id.x;
		if (i >= p.step.count) return;
		var v = p.src[i];
		if (i >= p.step.offset) v += p.src[i - p.step.offset];
		p.dst[i] = v;
	}
});

// each particle moved; the kept ones (pos.w 1) appended to kept, counted
// into the draw's instances (args[1])
final Move = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:MoveStep, particles:RWStorage<Particle>, kept:RWStorage<Vec4>, args:RWStorage<Int>}) {
		if (id.x >= p.step.count) return;
		var q = p.particles[id.x];
		var moved:Particle = {pos: vec4(q.pos.xyz + q.vel.xyz * p.step.dt, q.pos.w), vel: q.vel};
		p.particles[id.x] = moved;
		if (moved.pos.w > 0.5) {
			var k = atomicAdd(p.args, 1, 1);
			p.kept[k] = moved.pos;
		}
	}
});

// a gradient: red x * 8 / 255, green y * 8 / 255, blue 0.5
final Gradient = compute({
	size: [8, 8],
	main: function(id:ComputeInput, p:{size:GradientSize, image:StorageTexture}) {
		if (id.x >= p.size.width || id.y >= p.size.height) return;
		textureStore(p.image, id.x, id.y, vec4(id.x * 8 / 255.0, id.y * 8 / 255.0, 0.5, 1));
	}
});

// a kept particle: a square of 6x6 pixels (corner: -3..3 pixels, in clip units)
final DotShader = shader({
	vertex: function(v:DotVertex):DotVaryings return {pos: position(vec4(v.center.xy + v.corner, 0, 1))},
	fragment: function(i:DotVaryings):Vec4 return vec4(1, 1, 1, 1)
});

final ImageShader = shader({
	vertex: function(v:ImageVertex):ImageVaryings return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv},
	fragment: function(i:ImageVaryings, p:{image:Texture2D}):Vec4 return sample(p.image, i.uv)
});

// each workgroup's sum of its 256 values: its subgroups' first, then theirs
final Sums = compute({
	size: [256],
	main: function(id:ComputeInput, p:{count:Count, values:Storage<Float>, out:RWStorage<Float>}, w:{part:Workgroup<Float>}) {
		var v = id.x < p.count.n ? p.values[id.x] : 0.0;
		v = subgroupAdd(v);
		if (id.subgroupLane == 0) w.part[id.subgroupIndex] = v;
		barrier();
		if (id.localIndex == 0) {
			var s = 0.0;
			for (k in 0...id.subgroups)
				s += w.part[k];
			p.out[id.groupX] = s;
		}
	}
});

// an inclusive prefix sum of each workgroup's 256 values (Hillis and
// Steele's, in workgroup memory: a barrier between the steps' reads and writes)
final Prefix = compute({
	size: [256],
	main: function(id:ComputeInput, p:{count:Count, values:Storage<Int>, out:RWStorage<Int>}, w:{sums:Workgroup<Int>}) {
		var i = id.localIndex;
		w.sums[i] = id.x < p.count.n ? p.values[id.x] : 0;
		barrier();
		var offset = 1;
		while (offset < 256) {
			var v = w.sums[i];
			if (i >= offset) v += w.sums[i - offset];
			barrier();
			w.sums[i] = v;
			barrier();
			offset *= 2;
		}
		if (id.x < p.count.n) p.out[id.x] = w.sums[i];
	}
});

// each workgroup's smallest and largest value, whether all are above 0
// and whether any is 7: out[4 * group ...], its subgroups' first
final Extremes = compute({
	size: [64],
	main: function(id:ComputeInput, p:{count:Count, values:Storage<Int>, out:RWStorage<Int>},
			w:{@:length(16) var lo:Workgroup<Int>; @:length(16) var hi:Workgroup<Int>; var flags:Workgroup<Int>;}) {
		var inside = id.x < p.count.n;
		var v = inside ? p.values[id.x] : 0;
		var lo = subgroupMin(inside ? v : 1000000), hi = subgroupMax(inside ? v : -1000000);
		var all = subgroupAll(!inside || v > 0), any = subgroupAny(inside && v == 7);
		if (id.subgroupLane == 0) {
			w.lo[id.subgroupIndex] = lo;
			w.hi[id.subgroupIndex] = hi;
			w.flags[id.subgroupIndex] = (all ? 1 : 0) | (any ? 2 : 0);
		}
		barrier();
		if (id.localIndex == 0) {
			var a = w.lo[0], b = w.hi[0], f = w.flags[0];
			for (k in 1...id.subgroups) {
				if (w.lo[k] < a) a = w.lo[k];
				if (w.hi[k] > b) b = w.hi[k];
				f = (f & w.flags[k] & 1) | ((f | w.flags[k]) & 2);
			}
			p.out[4 * id.groupX] = a;
			p.out[4 * id.groupX + 1] = b;
			p.out[4 * id.groupX + 2] = f & 1;
			p.out[4 * id.groupX + 3] = f >> 1;
		}
	}
});

// 1 in out[x] where the invocation's subgroup ids agree with what its
// subgroup's lanes broadcast and shuffle (lane ^ 1: its neighbour's)
final Lanes = compute({
	size: [64],
	main: function(id:ComputeInput, p:{out:RWStorage<Int>}, w:{lane:Workgroup<Int>, group:Workgroup<Int>}) {
		var i = id.localIndex;
		w.lane[i] = id.subgroupLane;
		w.group[i] = id.subgroupIndex;
		var first = subgroupBroadcast(i, 0);
		var other = subgroupShuffle(i, id.subgroupLane ^ 1);
		var back = subgroupShuffle(other, id.subgroupLane ^ 1);
		var pair = subgroupShuffle(vec2(i, 1), id.subgroupLane ^ 1);
		var count = subgroupAdd(vec2(1, 0));
		barrier();
		var ok = w.lane[first] == 0 && w.group[first] == id.subgroupIndex && w.lane[other] == (id.subgroupLane ^ 1) && w.group[other] == id.subgroupIndex
			&& back == i && Std.int(pair.x) == other && Std.int(count.x) == id.subgroupSize && id.subgroupIndex * id.subgroupSize + id.subgroupLane == i
			&& id.subgroups * id.subgroupSize == 64;
		p.out[id.x] = ok ? 1 : 0;
	}
});
