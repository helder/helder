package helder.scene.render;

import helder.gfx.Texture;
import helder.gfx.shader.Vec4;
import helder.scene.Node;

// A baked lightmap, a component of a node (Bevy's model, not a material's
// field: nodes of one mesh and one material share both and keep their own
// lightmaps): its texture (an atlas several nodes share), its rectangle of
// it (rect: xy the offset, zw the scale of the second uvs, TEXCOORD_1: a
// primitive's uv1), the light it holds (the irradiance over pi a white
// surface reflects: linear RGBA16F, or sRGB-encoded RGBA8 with srgb) times
// intensity. Drawn with Lightmaps (renderer.use(new Lightmaps())): mode
// Indirect (the default) replaces the ambient (the sky's, the environment's,
// the probes') and keeps the lights; All has the lights baked too, none
// added. A primitive without second uvs is drawn as before. Baking is a
// tool's (Blender's, another's atlas).
//   Lightmap.attach(node, new Lightmap(baked, new Vec4(0, 0, 0.5, 0.5)));
class Lightmap {
	@:noCompletion public static final KIND = new StoreKind<Lightmap>("lightmap");

	public var texture:Texture;
	public var rect:Vec4;
	public var intensity = 1.0;
	public var mode:LightmapMode = Indirect;
	// whether its colours are sRGB-encoded (an image's RGBA8; RGBA16F's are linear)
	public var srgb = false;
	public var node(default, null):Node = Node.NONE;

	public function new(texture:Texture, ?rect:Vec4, srgb = false) {
		this.texture = texture;
		this.rect = rect != null ? rect : new Vec4(0, 0, 1, 1);
		this.srgb = srgb;
	}

	// lightmap on node (a node has one)
	public static function attach(node:Node, lightmap:Lightmap):Lightmap {
		lightmap.node = node;
		return node.world.store(KIND).set(node, lightmap);
	}

	public static inline function of(node:Node):Null<Lightmap>
		return node.world.store(KIND).get(node);
}

// what a Lightmap holds: the ambient light alone (the lights added), or all of it
enum abstract LightmapMode(String) {
	var Indirect = "indirect";
	var All = "all";
}
