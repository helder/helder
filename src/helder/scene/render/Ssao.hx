package helder.scene.render;

import helder.gfx.*;
import helder.math.Vec4;

// Screen-space ambient occlusion, a PostProcess's (post.ao = new
// Ssao({...})): GTAO (Jimenez et al. 2016) from the renderer's view
// buffers (ViewBuffers: their depth and normals, asked for by the chain),
// at half their size (halfRes) or whole, then blurred up to their size by
// depth (bilateral), before the frame's pass, whose standard material
// darkens its indirect light by it alone (the ambient, the environment's
// light and reflections: PbrShader's aoMap), not the sun's or the lamps'
// (three.js' classic passes darken the whole frame). Its targets are R8;
// nothing is allocated per frame.
//
//   post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});
//
// On a phone: one slice of 4 to 6 steps at half size (samples 4, slices 1).
// Its options alone: its passes are SsaoPass's, linked by a program that
// sets it on a chain (post.ao's setter).
class Ssao {
	// how far an occluder reaches (metres)
	public var radius:Float;
	// how dark: the occlusion's power (1 as found, 2 darker)
	public var intensity:Float;
	// the steps along each side of a slice
	public var samples:Int;
	// the slices of the hemisphere (1 or 2: the noise turns them per pixel)
	public var slices:Int;
	// at half the frame's size (a quarter of the pixels: the view buffers'
	// when they are at half, else half theirs), blurred up to theirs
	public var halfRes:Bool;
	// the last frame's occlusion (R8, the view buffers' size; red 1 open, 0 occluded)
	public var texture(default, null):Null<Texture> = null;

	public function new(?options:SsaoOptions) {
		radius = options?.radius ?? 0.5;
		intensity = options?.intensity ?? 1.0;
		samples = options?.samples ?? 8;
		slices = options?.slices ?? 2;
		halfRes = options?.halfRes ?? true;
	}
}

typedef SsaoOptions = {
	?radius:Float,
	?intensity:Float,
	?samples:Int,
	?slices:Int,
	?halfRes:Bool
}
