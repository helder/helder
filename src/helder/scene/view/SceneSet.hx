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
		n.scope.invalidate();
	}

	public static function any_position(n:SceneNode, v:Vec3) {
		#if hxmc.dev
		if (n.bound & 1 != 0 && !same3(n.node.position, n.wrotePosition)) fight(n, "position");
		n.bound |= 1;
		n.wrotePosition = v;
		#end
		n.node.position = v;
		n.scope.invalidate();
	}

	public static function any_rotation(n:SceneNode, v:Quat) {
		#if hxmc.dev
		var q = n.node.rotation, w = n.wroteRotation;
		if (n.bound & 2 != 0 && (q.x != w.x || q.y != w.y || q.z != w.z || q.w != w.w)) fight(n, "rotation");
		n.bound |= 2;
		n.wroteRotation = v;
		#end
		n.node.rotation = v;
		n.scope.invalidate();
	}

	public static function any_scale(n:SceneNode, v:Vec3) {
		#if hxmc.dev
		if (n.bound & 4 != 0 && !same3(n.node.scale, n.wroteScale)) fight(n, "scale");
		n.bound |= 4;
		n.wroteScale = v;
		#end
		n.node.scale = v;
		n.scope.invalidate();
	}

	#if hxmc.dev
	static inline function same3(a:Vec3, b:Vec3):Bool
		return a.x == b.x && a.y == b.y && a.z == b.z;

	// (a dev build's check, DESIGN-MARKUP.md 3.2: a prop bound and written in
	// code too, its binding about to overwrite what code wrote; said once a node)
	// (what a fight is told to: printed; a test's own)
	public static var onFight:Null<(SceneNode, String) -> Void> = null;

	static function fight(n:SceneNode, prop:String) {
		if (n.said) return;
		n.said = true;
		if (onFight != null) return onFight(n, prop);
		var at = n.source == null ? "" : " (" + n.source.toString() + ")";
		Sys.println('helder.scene: <${n.tag}>\'s $prop is bound and was written in code since its binding set it$at: a prop is bound or driven (onFrame, Frame.on), never both; the binding now overwrites it');
	}
	#end

	public static function any_visible(n:SceneNode, v:Bool) {
		n.node.visible = v;
		n.scope.invalidate();
	}

	// (its selection group: post.outline's, 0 none; Outline.select)
	public static function any_outline(n:SceneNode, v:Int) {
		helder.scene.render.Outline.select(n.node, v);
		n.scope.invalidate();
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
		n.scope.invalidate();
	}

	static function intensity(n:SceneNode, v:Float) {
		light(n).intensity = v;
		n.scope.invalidate();
	}

	static function range(n:SceneNode, v:Float) {
		light(n).range = v;
		n.scope.invalidate();
	}

	static function inner(n:SceneNode, v:Float) {
		light(n).innerCone = v;
		n.scope.invalidate();
	}

	static function outer(n:SceneNode, v:Float) {
		light(n).outerCone = v;
		n.scope.invalidate();
	}

	static function castShadows(n:SceneNode, v:Bool) {
		light(n).castShadows = v;
		@:privateAccess n.castSet = true;
		n.scope.invalidate();
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
		n.scope.invalidate();
	}

	public static inline function hemisphereLight_intensity(n:SceneNode, v:Float)
		intensity(n, v);

	// --- the camera's: its Camera, in place

	public static function camera_fov(n:SceneNode, v:Float) {
		Camera.of(n.node).fovY = v;
		n.scope.invalidate();
	}

	public static function camera_near(n:SceneNode, v:Float) {
		Camera.of(n.node).near = v;
		n.scope.invalidate();
	}

	public static function camera_far(n:SceneNode, v:Float) {
		Camera.of(n.node).far = v;
		n.scope.invalidate();
	}

	// --- a mesh's own material (its shape's, without a material part or
	// prop), in place

	public static function mesh_color(n:SceneNode, v:Vec4) {
		@:privateAccess n.ownMaterial().baseColor = v;
		n.scope.invalidate();
	}

	public static function mesh_metallic(n:SceneNode, v:Float) {
		@:privateAccess n.ownMaterial().metallic = v;
		n.scope.invalidate();
	}

	public static function mesh_roughness(n:SceneNode, v:Float) {
		@:privateAccess n.ownMaterial().roughness = v;
		n.scope.invalidate();
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
