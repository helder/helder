package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.math.Quat;
import helder.scene.render.Light;
import helder.scene.view.SceneRenderer.SceneNode;

// SceneRenderer's typed setters (@:setters, Renders): markup sets a prop
// with the function of its element and name (<element>_<prop>, else
// any_<prop>), its value typed as SceneProps declares it when compiling:
// no name looked up, no map, no struct through a function of Dynamic
// (DESIGN-MARKUP.md 3.1, 10.1). A node's props write its node; a set prop
// writes its component in place (a light's intensity, a camera's fov, a
// mesh's own material's colour); the others are make props, by name
// (prop): their component made again from them. Each is its own function,
// so a program links the setters its markup names.
class SceneSet {
	// --- every element's: its node's

	public static function any_name(n:SceneNode, v:String) {
		n.node.name = v;
		SceneRenderer.changed();
	}

	public static function any_position(n:SceneNode, v:Vec3) {
		n.node.position = v;
		SceneRenderer.changed();
	}

	public static function any_rotation(n:SceneNode, v:Quat) {
		n.node.rotation = v;
		SceneRenderer.changed();
	}

	public static function any_scale(n:SceneNode, v:Vec3) {
		n.node.scale = v;
		SceneRenderer.changed();
	}

	public static function any_visible(n:SceneNode, v:Bool) {
		n.node.visible = v;
		SceneRenderer.changed();
	}

	// (its selection group: post.outline's, 0 none; Outline.select)
	public static function any_outline(n:SceneNode, v:Int) {
		helder.scene.render.Outline.select(n.node, v);
		SceneRenderer.changed();
	}

	// a make prop (or one of no setter of its own yet): by name, its
	// component made again (SceneRenderer.setProperty)
	public static function prop(n:SceneNode, name:String, v:Dynamic)
		SceneRenderer.setProperty(n, name, v);

	// --- the lights': their Light, in place

	static inline function light(n:SceneNode):Light
		return Light.of(n.node);

	static function color(n:SceneNode, v:Vec3) {
		light(n).color = v;
		SceneRenderer.changed();
	}

	static function intensity(n:SceneNode, v:Float) {
		light(n).intensity = v;
		SceneRenderer.changed();
	}

	static function range(n:SceneNode, v:Float) {
		light(n).range = v;
		SceneRenderer.changed();
	}

	static function inner(n:SceneNode, v:Float) {
		light(n).innerCone = v;
		SceneRenderer.changed();
	}

	static function outer(n:SceneNode, v:Float) {
		light(n).outerCone = v;
		SceneRenderer.changed();
	}

	static function castShadows(n:SceneNode, v:Bool) {
		light(n).castShadows = v;
		@:privateAccess n.castSet = true;
		SceneRenderer.changed();
	}

	public static inline function light_color(n:SceneNode, v:Vec3)
		color(n, v);

	public static inline function light_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	public static inline function light_range(n:SceneNode, v:Float)
		range(n, v);

	public static inline function light_inner(n:SceneNode, v:Float)
		inner(n, v);

	public static inline function light_outer(n:SceneNode, v:Float)
		outer(n, v);

	public static inline function light_castShadows(n:SceneNode, v:Bool)
		castShadows(n, v);

	public static inline function directionalLight_color(n:SceneNode, v:Vec3)
		color(n, v);

	public static inline function directionalLight_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	public static inline function directionalLight_castShadows(n:SceneNode, v:Bool)
		castShadows(n, v);

	public static inline function pointLight_color(n:SceneNode, v:Vec3)
		color(n, v);

	public static inline function pointLight_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	public static inline function pointLight_range(n:SceneNode, v:Float)
		range(n, v);

	public static inline function pointLight_castShadows(n:SceneNode, v:Bool)
		castShadows(n, v);

	public static inline function spotLight_color(n:SceneNode, v:Vec3)
		color(n, v);

	public static inline function spotLight_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	public static inline function spotLight_range(n:SceneNode, v:Float)
		range(n, v);

	public static inline function spotLight_inner(n:SceneNode, v:Float)
		inner(n, v);

	public static inline function spotLight_outer(n:SceneNode, v:Float)
		outer(n, v);

	public static inline function spotLight_castShadows(n:SceneNode, v:Bool)
		castShadows(n, v);

	public static inline function hemisphereLight_sky(n:SceneNode, v:Vec3)
		color(n, v);

	public static function hemisphereLight_ground(n:SceneNode, v:Vec3) {
		light(n).groundColor = v;
		SceneRenderer.changed();
	}

	public static inline function hemisphereLight_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	// --- the camera's: its Camera, in place

	public static function camera_fov(n:SceneNode, v:Float) {
		Camera.of(n.node).fovY = v;
		SceneRenderer.changed();
	}

	public static function camera_near(n:SceneNode, v:Float) {
		Camera.of(n.node).near = v;
		SceneRenderer.changed();
	}

	public static function camera_far(n:SceneNode, v:Float) {
		Camera.of(n.node).far = v;
		SceneRenderer.changed();
	}

	// --- a mesh's own material (its shape's, without a material part or
	// prop), in place

	public static function mesh_color(n:SceneNode, v:Vec4) {
		@:privateAccess n.ownMaterial().baseColor = v;
		SceneRenderer.changed();
	}

	public static function mesh_metallic(n:SceneNode, v:Float) {
		@:privateAccess n.ownMaterial().metallic = v;
		SceneRenderer.changed();
	}

	public static function mesh_roughness(n:SceneNode, v:Float) {
		@:privateAccess n.ownMaterial().roughness = v;
		SceneRenderer.changed();
	}

	// the same by name (SceneRenderer.setProperty: a spread, a late
	// literal's, TypeScript's markup), whether name is a set prop of n's
	@:allow(helder.scene.view.SceneRenderer) static function byName(n:SceneNode, name:String, v:Dynamic):Bool {
		switch [n.tag, name] {
			case ["light" | "directionalLight" | "pointLight" | "spotLight", "color"] | ["hemisphereLight", "sky"]:
				color(n, (v : Vec3));
			case ["light" | "directionalLight" | "pointLight" | "spotLight" | "hemisphereLight", "intensity"]:
				intensity(n, SceneOptions.float(v));
			case ["light" | "pointLight" | "spotLight", "range"]:
				range(n, SceneOptions.float(v));
			case ["light" | "spotLight", "inner"]:
				inner(n, SceneOptions.float(v));
			case ["light" | "spotLight", "outer"]:
				outer(n, SceneOptions.float(v));
			case ["light" | "directionalLight" | "pointLight" | "spotLight", "castShadows"]:
				castShadows(n, v == true);
			case ["hemisphereLight", "ground"]:
				hemisphereLight_ground(n, (v : Vec3));
			case ["camera", "fov"]:
				camera_fov(n, SceneOptions.float(v));
			case ["camera", "near"]:
				camera_near(n, SceneOptions.float(v));
			case ["camera", "far"]:
				camera_far(n, SceneOptions.float(v));
			case ["mesh", "color"]:
				mesh_color(n, (v : Vec4));
			case ["mesh", "metallic"]:
				mesh_metallic(n, SceneOptions.float(v));
			case ["mesh", "roughness"]:
				mesh_roughness(n, SceneOptions.float(v));
			case _:
				return false;
		}
		return true;
	}
}
