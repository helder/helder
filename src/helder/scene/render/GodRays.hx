package helder.scene.render;

// God rays, a PostProcess's (post.godRays = new GodRays({...})): the sky's
// light (where the view buffers' depth is the far plane's) blurred towards
// the sun's place on the screen, at a quarter of the frame's size, added to
// the scene's light before the curve, so what stands before the sky casts
// shafts of shadow through the glow (Mitchell's "Volumetric Light
// Scattering as a Post-Process", GPU Gems 3). The sun is the renderer's:
// the world's first directional light, else Renderer.sunDirection; behind
// the camera, none. One pass at a quarter of the pixels; its target RGBA16F;
// nothing is allocated per frame. Volumetric fog is not this. Its options
// alone: its pass is GodRaysPass's, linked by a program that sets it.
//
//   post.godRays = new GodRays({intensity: 0.6, decay: 0.96});
class GodRays {
	// how much light the shafts add
	public var intensity:Float;
	// how far towards the sun each pixel gathers (a share of the way)
	public var density:Float;
	// how much each tap weighs against the one nearer the pixel (0..1: less
	// fades the shafts sooner)
	public var decay:Float;
	// the taps along the way (24 for phones, 32, 48)
	public var samples:Int;
	// how tight the glow is about the sun (more: only near it)
	public var falloff:Float;
	// the last frame's shafts (RGBA16F, a quarter of the frame's size)
	public var texture(default, null):Null<helder.gfx.Texture> = null;

	public function new(?options:GodRaysOptions) {
		intensity = options?.intensity ?? 0.5;
		density = options?.density ?? 0.85;
		decay = options?.decay ?? 0.96;
		samples = options?.samples ?? 32;
		falloff = options?.falloff ?? 2.5;
	}
}

typedef GodRaysOptions = {
	?intensity:Float,
	?density:Float,
	?decay:Float,
	?samples:Int,
	?falloff:Float
}
