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
// The renderer takes the world's first directional light (its cascades
// Shadows'), its first hemisphere light, and up to MAX_LIGHTS point and
// spot lights a frame (the nearest the view and the brightest): each draw
// lit by the eight that reach its bounds most, or each pixel by its
// cell's with ClusteredLights. A light casts shadows with Shadows when
// castShadows (a directional light by default, a point or spot light when
// asked: Shadows' tiles, within its budget), filtered as shadow says.
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
	// whether it casts shadows (Shadows): a directional light's first of
	// the world (its cascades), a point or spot light's (its tiles of the
	// atlas: a spot's one, a point's six) while within shadows.maxLocal
	public var castShadows:Bool;
	// its shadow's size and filter (null: Shadows' defaults)
	public var shadow:Null<LightShadow> = null;

	function new(kind:LightKind, color:Vec3, intensity:Float, range:Float) {
		this.kind = kind;
		this.color = color;
		this.intensity = intensity;
		this.range = range;
		castShadows = kind == Directional;
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

// a light's shadow (light.shadow = {size: 512, radius: 1.5}; a field left
// out: Shadows' default)
typedef LightShadow = {
	// a point or spot light's tile in texels (a point light's each face's:
	// six), a power of two (Shadows.tileSize; a point light's faces half)
	?size:Int,
	// the depth offset against acne: a point or spot light's in metres a
	// metre from it (Shadows.localBias); a directional light's as Shadows.bias
	?bias:Float,
	// a point or spot light's offset of the point along its normal, in its
	// tile's texels (Shadows.normalBias)
	?normalBias:Float,
	// a point or spot light's soft filter: a disc of taps this many of its
	// tile's texels wide (0: the 3x3 filter; Shadows.localRadius)
	?radius:Float,
	// how dark, 0 (none) to 1 (Shadows.strength)
	?strength:Float,
	// whether its tiles may be kept from a frame to the next while the
	// light and what casts into them stay put (true; Shadows.cached)
	?cached:Bool
}

// what kind of light a Light is
enum abstract LightKind(Int) to Int {
	var Directional;
	var Point;
	var Spot;
	var Hemisphere;
}
