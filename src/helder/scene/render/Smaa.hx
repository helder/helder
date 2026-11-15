package helder.scene.render;

// SMAA, a PostProcess's (post.smaa = new Smaa()): Jimenez et al.'s
// morphological antialiasing of the light the composite reads, its edges
// and their blending weights in two passes, blended in the composite (its
// own variant), in place of FXAA's (SmaaShaders' notes: the orthogonal
// patterns, their areas worked out; no diagonal or corner patterns: SMAA's
// medium preset). Its options alone: its passes are SmaaPass's, linked by
// a program that sets it on a chain.
//
//   post.smaa = new Smaa({threshold: 0.1});
class Smaa {
	// the edges' threshold, of perceptual luma (0.1 SMAA's medium, 0.05 finer)
	public var threshold:Float;

	public function new(?options:SmaaOptions)
		threshold = options?.threshold ?? 0.1;
}

typedef SmaaOptions = {
	?threshold:Float
}
