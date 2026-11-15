package helder.gfx;

// What the frames record, counted over every device (Encoder's): passes,
// draws, the instances they draw, pipelines, textures and vertex buffers
// set; and a 2D renderer's (helder.ui's Renderer): the quads it drew, the
// bytes of them it wrote to the GPU, the CPU it spent from its begin
// through the painting to its pass encoded (uiMs) and of that its
// upload's (uploadMs: the glyph atlas's and the quads') and its draws'
// (encodeMs: the encoder's calls, the driver's work in them: a software
// rasterizer's vertex stage too), in ms, and the GC bytes allocated
// from its begin to its end (uiBytes: hxmc's; the painting's too), the
// glyphs' texels it wrote (glyphTexels: the atlas's changed region, the
// large glyphs drawn alone). And a 3D renderer's (helder.scene's Renderer)
// draws of those, by pass: its main pass's (sceneDraws: renderer.draws),
// its shadow maps' (shadowDraws: every cascade's, Shadows.draws), its view
// buffers' prepass (prepassDraws: ViewBuffers.draws) and its
// post-processing's (postDraws: bloom, AO, DOF, the composite, the stages;
// PostProcess.draws), every renderer's summed.
// Counted from the last reset: a headless run's --stats resets them at
// each frame's start.
class FrameCounts {
	public static var passes = 0;
	public static var draws = 0;
	public static var instances = 0;
	public static var pipelines = 0;
	public static var textures = 0;
	public static var buffers = 0;
	public static var quads = 0;
	public static var uploaded = 0;
	public static var uiMs = 0.0;
	public static var uploadMs = 0.0;
	public static var encodeMs = 0.0;
	public static var uiBytes = 0.0;
	public static var glyphTexels = 0;
	public static var sceneDraws = 0;
	public static var shadowDraws = 0;
	public static var postDraws = 0;
	// compute dispatches (Encoder.dispatch, dispatchIndirect)
	public static var dispatches = 0;
	public static var prepassDraws = 0;
	// a 3D renderer's draws not drawn as hidden behind others (helder.scene's
	// Occlusion: Renderer.occluded), every renderer's summed
	public static var occluded = 0;

	public static function reset() {
		dispatches = 0;
		passes = draws = quads = instances = pipelines = textures = buffers = uploaded = glyphTexels = 0;
		sceneDraws = shadowDraws = postDraws = prepassDraws = occluded = 0;
		uiMs = uploadMs = encodeMs = uiBytes = 0;
	}
}
