package helder.scene.view;

import helder.math.Vec2;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.math.Quat;
import helder.scene.render.Light;
import helder.scene.view.SceneRenderer.SceneNode;
import helder.ui.draw.PassData;

// A <Scene> of markup alone as data (helder.ui.draw.PassData) for a frame
// kept as data (a studio's stills, FrameWriter.data): its tags, each its
// node's place, its props (the make props markup gave it, the set props as
// its light, camera and own material have them), its children; built again
// with SceneRenderer's own elements and props where the frame is shown
// (build), a loop's next frame its changed props set (apply). A scene that
// is not markup alone (a node made in code, a prop of an object: a
// geometry or a material made in code, a set of instances, a font; its
// renderer set up in code, effects, helpers, a ui inside it) is none:
// its picture is kept instead.
@:access(helder.scene.view.SceneBox)
class SceneData {
	public static inline var KIND = "scene";

	public static function capture(box:SceneBox):Null<PassData> {
		if (box.camera != null || box.onRenderer != null || box.postSetters.length > 0 || box.rendererSetters.length > 0 || box.overlays.length > 0) return null;
		var root = new PassElement("scene").set("hdr", Flag(box.hdr)).set("antialias", Flag(box.antialias));
		for (c in box.world.root.children()) {
			// (the camera the box made, a scene without one: made again so)
			if (box.fallback != null && Camera.of(c) == box.fallback) continue;
			var e = element(c);
			if (e == null) return null;
			root.children.push(e);
		}
		return new PassData(KIND, root);
	}

	static function element(n:helder.scene.Node):Null<PassElement> {
		var s = SceneRenderer.of(n);
		if (s == null) return null;
		var e = new PassElement(s.tag);
		if (n.name != s.tag) e.set("name", Text(n.name));
		var p = n.position, r = n.rotation, k = n.scale;
		e.set("position", Vec([p.x, p.y, p.z]));
		e.set("rotation", Vec([r.x, r.y, r.z, r.w]));
		e.set("scale", Vec([k.x, k.y, k.z]));
		if (!n.visible && !StringTools.startsWith(s.tag, "#")) e.set("visible", Flag(false));
		// (the set props, as their components have them)
		var light = Light.of(n);
		if (light != null) {
			var c = light.color;
			e.set(s.tag == "hemisphereLight" ? "sky" : "color", Vec([c.x, c.y, c.z]));
			e.set("intensity", Num(light.intensity));
			if (s.tag == "light" || s.tag == "pointLight" || s.tag == "spotLight") e.set("range", Num(light.range));
			if (s.tag == "light" || s.tag == "spotLight") {
				e.set("inner", Num(light.innerCone));
				e.set("outer", Num(light.outerCone));
			}
			if (s.tag == "hemisphereLight") {
				var g = light.groundColor;
				e.set("ground", Vec([g.x, g.y, g.z]));
			}
			if (@:privateAccess s.castSet) e.set("castShadows", Flag(light.castShadows));
		}
		var cam = s.tag == "camera" ? Camera.of(n) : null;
		if (cam != null) {
			e.set("fov", Num(cam.fovY));
			e.set("near", Num(cam.near));
			e.set("far", Num(cam.far));
		}
		var own:Null<helder.scene.render.Material> = @:privateAccess s.own;
		if (own != null) {
			var c = own.baseColor;
			e.set("color", Vec([c.x, c.y, c.z, c.w]));
			e.set("metallic", Num(own.metallic));
			e.set("roughness", Num(own.roughness));
		}
		// (the make props: values alone)
		var names = [for (name in s.props.keys()) name];
		names.sort(Reflect.compare);
		for (name in names) {
			var v = value(s.props.get(name));
			if (v == null) return null;
			e.set(name, v);
		}
		for (c in n.children()) {
			var x = element(c);
			if (x == null) return null;
			e.children.push(x);
		}
		return e;
	}

	static function value(v:Dynamic):Null<PassValue> {
		if (v == null) return null;
		if (Std.isOfType(v, Bool)) return Flag(v);
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return Num(v);
		if (Std.isOfType(v, String)) return Text(v);
		if (Std.isOfType(v, helder.math.Vec2.Vec2Data)) {
			var a:Vec2 = cast v;
			return Vec([a.x, a.y]);
		}
		if (Std.isOfType(v, helder.math.Vec3.Vec3Data)) {
			var a:Vec3 = cast v;
			return Vec([a.x, a.y, a.z]);
		}
		if (Std.isOfType(v, helder.math.Vec4.Vec4Data)) {
			var a:Vec4 = cast v;
			return Vec([a.x, a.y, a.z, a.w]);
		}
		if (Std.isOfType(v, helder.math.Quat.QuatData)) {
			var a:Quat = cast v;
			return Vec([a.x, a.y, a.z, a.w]);
		}
		return null;
	}

	// a scene of data built: its box (not in a tree: drawn where its frame
	// is, SceneReplay.draw), each element's markup node in the data's order
	public static function build(d:PassData):SceneReplay {
		var box = new SceneBox(new World("scene"));
		box.hdr = flag(d.root.get("hdr"));
		box.antialias = flag(d.root.get("antialias"));
		var nodes = [];
		for (c in d.root.children)
			SceneRenderer.insert(box.root, make(c, nodes), null);
		return new SceneReplay(box, nodes, d);
	}

	static function make(e:PassElement, nodes:Array<SceneNode>):SceneNode {
		var n = create(e.tag);
		nodes.push(n);
		for (k => name in e.names)
			SceneRenderer.setProperty(n, name, convert(name, e.values[k]));
		for (c in e.children)
			SceneRenderer.insert(n, make(c, nodes), null);
		return n;
	}

	// (a tag's element: the geometry and material tags by their factories, linked all)
	static function create(tag:String):SceneNode
		return switch tag {
			case "boxGeometry": SceneRenderer.element_boxGeometry();
			case "sphereGeometry": SceneRenderer.element_sphereGeometry();
			case "cylinderGeometry": SceneRenderer.element_cylinderGeometry();
			case "coneGeometry": SceneRenderer.element_coneGeometry();
			case "capsuleGeometry": SceneRenderer.element_capsuleGeometry();
			case "torusGeometry": SceneRenderer.element_torusGeometry();
			case "torusKnotGeometry": SceneRenderer.element_torusKnotGeometry();
			case "ringGeometry": SceneRenderer.element_ringGeometry();
			case "circleGeometry": SceneRenderer.element_circleGeometry();
			case "planeGeometry": SceneRenderer.element_planeGeometry();
			case "latheGeometry": SceneRenderer.element_latheGeometry();
			case "tubeGeometry": SceneRenderer.element_tubeGeometry();
			case "standardMaterial": SceneRenderer.element_standardMaterial();
			case "lambertMaterial": SceneRenderer.element_lambertMaterial();
			case "phongMaterial": SceneRenderer.element_phongMaterial();
			case "toonMaterial": SceneRenderer.element_toonMaterial();
			case "unlitMaterial": SceneRenderer.element_unlitMaterial();
			case "matcapMaterial": SceneRenderer.element_matcapMaterial();
			case "normalMaterial": SceneRenderer.element_normalMaterial();
			case "depthMaterial": SceneRenderer.element_depthMaterial();
			case t if (StringTools.startsWith(t, "#")): SceneRenderer.createMarker(t);
			case t: SceneRenderer.createElement(t);
		}

	static function flag(v:Null<PassValue>):Bool
		return switch v {
			case Flag(b): b;
			case _: false;
		}

	// (a value as its prop takes it: a Quat a rotation's four numbers, a Vec4 any other's)
	public static function convert(name:String, v:PassValue):Dynamic
		return switch v {
			case Num(x): x;
			case Flag(b): b;
			case Text(s): s;
			case Vec(a) if (a.length == 2): new Vec2(a[0], a[1]);
			case Vec(a) if (a.length == 3): new Vec3(a[0], a[1], a[2]);
			case Vec(a) if (name == "rotation"): new Quat(a[0], a[1], a[2], a[3]);
			case Vec(a): new Vec4(a[0], a[1], a[2], a[3]);
		}

	// whether two scenes are the same tags, the same props by name, in the same order
	public static function alike(a:PassElement, b:PassElement):Bool {
		if (a.tag != b.tag || a.names.length != b.names.length || a.children.length != b.children.length) return false;
		for (k in 0...a.names.length)
			if (a.names[k] != b.names[k]) return false;
		for (k in 0...a.children.length)
			if (!alike(a.children[k], b.children[k])) return false;
		return true;
	}
}

// (a scene of data built: its box, its elements' markup nodes, the data it
// shows; a loop's next frame applied: its changed props set, else built again)
class SceneReplay {
	public var box(default, null):SceneBox;
	var nodes:Array<SceneNode>;
	var shown:PassData;

	public function new(box:SceneBox, nodes:Array<SceneNode>, shown:PassData) {
		this.box = box;
		this.nodes = nodes;
		this.shown = shown;
	}

	// the scene of d: its props that changed set (the same tags), else made again
	public function apply(d:PassData) {
		if (d == shown) return;
		if (!SceneData.alike(shown.root, d.root)) {
			box.dispose();
			var r = SceneData.build(d);
			box = r.box;
			nodes = r.nodes;
			shown = d;
			return;
		}
		var k = 0;
		function walk(a:PassElement, b:PassElement) {
			var n = nodes[k++];
			for (j in 0...b.values.length)
				if (!same(a.values[j], b.values[j])) SceneRenderer.setProperty(n, b.names[j], SceneData.convert(b.names[j], b.values[j]));
			for (c in 0...b.children.length)
				walk(a.children[c], b.children[c]);
		}
		for (c in 0...d.root.children.length)
			walk(shown.root.children[c], d.root.children[c]);
		shown = d;
	}

	static function same(a:PassValue, b:PassValue):Bool
		return switch [a, b] {
			case [Num(x), Num(y)]: x == y;
			case [Flag(x), Flag(y)]: x == y;
			case [Text(x), Text(y)]: x == y;
			case [Vec(x), Vec(y)]: x.length == y.length && [for (i in 0...x.length) x[i] == y[i]].indexOf(false) < 0;
			case _: false;
		}

	// drawn where its frame's list has it (the list's GPU texture of its mark): into c, at x, y, w by h
	public function draw(c:helder.ui.Canvas, x:Float, y:Float, w:Float, h:Float)
		box.paintContent(c, x, y, w, h);
}
