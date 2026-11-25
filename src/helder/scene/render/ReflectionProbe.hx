package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.scene.Node;

// A reflection probe, a component of a node: the scene seen from its node's
// position, captured once (six faces into a cube, then prefiltered into its
// column of Probes' atlas: its rows by roughness), reflected by the draws
// whose bounds are in its box (size: centred on the node, the world's
// axes), parallax-corrected: a reflection is looked up where it leaves
// the box, so a room's walls reflect where they are (Godot's and Unity's
// box projection). A draw takes the two probes that hold most of it, A
// blended over B (or the environment) by its share inside A's box, the
// box's walls soft over blend. Captured when first drawn with Probes, again after
// capture(); never every frame.
//   var hall = ReflectionProbe.attach(world.node("hall"), new ReflectionProbe(new Vec3(12, 4, 8), 0.5));
//   hall.node.position = new Vec3(0, 2, 0);
class ReflectionProbe {
	@:noCompletion public static final KIND = new StoreKind<ReflectionProbe>("reflectionProbe");

	// its box's size (scene units), centred on its node
	public var size:Vec3;
	// the depth inside its box over which it fades out towards its walls
	public var blend:Float;
	// its light's scale
	public var intensity = 1.0;
	public var node(default, null):Node = Node.NONE;
	// (Probes': its column of the atlas, 0 none yet; whether it is to be captured)
	@:allow(helder.scene.render.Probes) var column = 0;
	@:allow(helder.scene.render.Probes) var stale = true;

	public function new(size:Vec3, blend = 0.5) {
		this.size = size;
		this.blend = blend;
	}

	// probe on node (a node has one)
	public static function attach(node:Node, probe:ReflectionProbe):ReflectionProbe {
		probe.node = node;
		return node.world.store(KIND).set(node, probe);
	}

	public static inline function of(node:Node):Null<ReflectionProbe>
		return node.world.store(KIND).get(node);

	// captured again at the next frame drawn with Probes (the scene changed)
	public function capture()
		stale = true;

	// whether it has been captured since it was attached or capture() was called
	public var captured(get, never):Bool;

	inline function get_captured()
		return !stale;

	// how much of a box (its centre, its half size; the world's axes) is in
	// this one: 0 outside, 1 inside, the walls soft over blend (along each
	// axis the membership averaged over the box's extent, Simpson's rule)
	public function weight(cx:Float, cy:Float, cz:Float, ex:Float, ey:Float, ez:Float):Float {
		var p = node.worldPosition();
		return axis(cx - p.x, ex, size.x * 0.5) * axis(cy - p.y, ey, size.y * 0.5) * axis(cz - p.z, ez, size.z * 0.5);
	}

	inline function member(d:Float, half:Float):Float
		return blend <= 0 ? (Math.abs(d) <= half ? 1 : 0) : Math.min(Math.max((half - Math.abs(d)) / blend, 0), 1);

	inline function axis(c:Float, e:Float, half:Float):Float
		return (member(c - e, half) + 4 * member(c, half) + member(c + e, half)) / 6;
}
