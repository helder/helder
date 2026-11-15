package helder.scene.render;

// Screen-space reflections, a PostProcess's (post.ssr = new Ssr({...})):
// from the view buffers' depth and normals (asked for by the chain), each
// glossy pixel's reflected ray marched through the depth in view space at
// half the frame's size (or whole), its hit refined between its last two
// steps, the scene's light there taken; then, at the frame's size, mixed
// over the scene's light by the surface's Fresnel (Schlick's, its F0 from
// its metalness: the view buffers keep no base colour, a metal's
// reflection is untinted), its gloss and the hit's confidence (faded at
// the screen's edges, with the distance, for rays towards the camera).
// Where nothing is hit the scene keeps what the frame's pass gave it (the
// environment's or the sky's reflection). Desktop and web: no renderer
// listed ships it on phones. Its targets are RGBA16F; nothing is allocated
// per frame. Its options alone: its passes are SsrPass's, linked by a
// program that sets it on a chain.
//
//   post.ssr = new Ssr({maxDistance: 8, thickness: 0.2});
class Ssr {
	// how much of the reflection is mixed in (1: as Fresnel says)
	public var intensity:Float;
	// how far a ray goes (metres)
	public var maxDistance:Float;
	// how thick a surface is taken to be behind its depth (metres): a ray
	// behind it by more passes behind it
	public var thickness:Float;
	// the steps along a ray (16 to 48), then 4 halvings between the last two
	public var steps:Int;
	// the roughest surface that reflects (0..1: rougher ones keep their
	// own light); the reflection fades towards it
	public var maxRoughness:Float;
	// at half the frame's size (a quarter of the rays)
	public var halfRes:Bool;
	// the last frame's reflections (RGBA16F: rgb the light hit, a its weight)
	public var texture(default, null):Null<helder.gfx.Texture> = null;

	public function new(?options:SsrOptions) {
		intensity = options?.intensity ?? 1.0;
		maxDistance = options?.maxDistance ?? 8.0;
		thickness = options?.thickness ?? 0.25;
		steps = options?.steps ?? 32;
		maxRoughness = options?.maxRoughness ?? 0.6;
		halfRes = options?.halfRes ?? true;
	}
}

typedef SsrOptions = {
	?intensity:Float,
	?maxDistance:Float,
	?thickness:Float,
	?steps:Int,
	?maxRoughness:Float,
	?halfRes:Bool
}
