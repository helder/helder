package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.World;

// A light, a component of a node, as glTF's KHR_lights_punctual and
// three.js's lights: what kind of light it is (kind), its colour (linear)
// times its intensity.
//
//   Directional   shines down its node's -z, from far away (the sun)
//   Point         shines from its node's position, falling off with the
//                 inverse square of the distance, windowed to nothing at
//                 its range
//   Spot          a point light within a cone down its node's -z
//   Hemisphere    the ambient from above (color, the sky's) and below
//                 (groundColor), blended by a surface's normal: three's
//                 HemisphereLight, the renderer's sky and ground (which a
//                 world without one uses)
//
// The renderer takes the world's first directional light (shadowed by
// Shadows), its first hemisphere light, and up to four point and spot
// lights.
class Light {
	public static final KIND = new StoreKind<Light>("light");

	public var kind(default, null):LightKind;
	public var color:Vec3;
	public var intensity:Float;
	// a point or spot light's reach (scene units)
	public var range:Float;
	// a spot light's cones (radians from its axis)
	public var innerCone = 0.0;
	public var outerCone = 0.0;
	// a hemisphere light's colour from below (linear; color is the sky's)
	public var groundColor:Vec3 = new Vec3(0, 0, 0);

	function new(kind:LightKind, color:Vec3, intensity:Float, range:Float) {
		this.kind = kind;
		this.color = color;
		this.intensity = intensity;
		this.range = range;
	}

	public static function directional(color:Vec3, intensity:Float):Light
		return new Light(Directional, color, intensity, 0);

	public static function pointLight(color:Vec3, intensity:Float, range:Float):Light
		return new Light(Point, color, intensity, range);

	// a point light shining down its node's -z within a cone: full inside
	// inner, fading to nothing at outer (radians from the axis)
	public static function spot(color:Vec3, intensity:Float, range:Float, inner:Float, outer:Float):Light {
		var l = new Light(Spot, color, intensity, range);
		l.innerCone = inner;
		l.outerCone = outer;
		return l;
	}

	// three's HemisphereLight: the sky's colour from above, the ground's from
	// below, both times intensity (in place of the renderer's sky and ground)
	public static function hemisphere(sky:Vec3, ground:Vec3, intensity = 1.0):Light {
		var l = new Light(Hemisphere, sky, intensity, 0);
		l.groundColor = ground;
		return l;
	}

	// whether it shines from a point (a point or a spot light)
	public var local(get, never):Bool;

	inline function get_local():Bool
		return kind == Point || kind == Spot;

	public static inline function attach(node:Node, light:Light):Light
		return node.world.store(KIND).set(node, light);

	public static inline function of(node:Node):Null<Light>
		return node.world.store(KIND).get(node);
}

// what kind of light a Light is
enum abstract LightKind(Int) to Int {
	var Directional;
	var Point;
	var Spot;
	var Hemisphere;
}
