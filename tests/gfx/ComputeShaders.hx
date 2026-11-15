import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The compute tier's test stages (ComputeTest): a prefix sum's step, a
// particle move that appends the particles it keeps and counts them into
// an indirect draw's arguments, a storage texture's gradient; and the
// render stages that draw their results (the kept particles as instances
// from the storage buffer, the texture sampled).
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
