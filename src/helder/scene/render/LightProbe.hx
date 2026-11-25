package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.scene.Node;

// A light probe, a component of a node: the light around its node's position
// as spherical harmonics (Sh: baked, projected from an image or a function,
// Sh.ofHemisphere), lighting the draws whose centres are within radius of it
// with Probes (three.js's LightProbe, placed). A draw takes the nearest
// probe that reaches it, blended towards the next nearest by their
// distances; a ProbeGrid that holds the draw comes first. Diffuse light
// only, a draw's (its centre's) and evaluated at its vertices: nothing
// per pixel.
class LightProbe {
	@:noCompletion public static final KIND = new StoreKind<LightProbe>("lightProbe");

	public var sh:Sh;
	// how far it reaches (scene units)
	public var radius:Float;
	// its light's scale
	public var intensity = 1.0;
	public var node(default, null):Node = Node.NONE;

	public function new(sh:Sh, radius = 10.0) {
		this.sh = sh;
		this.radius = radius;
	}

	// probe on node (a node has one; the one it had is replaced)
	public static function attach(node:Node, probe:LightProbe):LightProbe {
		probe.node = node;
		return node.world.store(KIND).set(node, probe);
	}

	public static inline function of(node:Node):Null<LightProbe>
		return node.world.store(KIND).get(node);
}
