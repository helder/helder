package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.Geometry;
import helder.scene.render.InstancedMesh;
import helder.scene.render.Light;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.MeshRenderer;
import helder.scene.render.Shapes;
import helder.scene.render.Sprites;
import helder.scene.render.VertexData;
import helder.scene.view.SceneProps;

// helder.view's renderer for helder.scene: markup makes nodes of a World,
// and a property bound to a signal sets the node's value when the signal
// changes (no reconciliation, no re-render). Its markup is a <Scene>'s
// children (SceneTags: a box in ui's layout), or mounted into a world's root:
//
//   Render.render(<node name="spinner" position={pos} rotation={turn}>
//     <mesh shape="box" color={new Vec4(1, 0.5, 0.1, 1)}/>
//   </node>, SceneRenderer.root(world));
//
// Elements: node (position, rotation, scale: Vec3, Quat, Vec3; name,
// visible; outline: its selection group, 0 none, drawn by post.outline:
// Outline.select), mesh (a node drawing a geometry in a material: geometry and
// material made in code, shared; or its children, a geometry tag and a
// material tag, made from their props, again when one changes; or a shape
// made in code: shape box | sphere | plane, size, color, metallic,
// roughness; SceneRenderer.device must be set), the geometry tags
// (boxGeometry, sphereGeometry, cylinderGeometry, coneGeometry,
// capsuleGeometry, torusGeometry, torusKnotGeometry, ringGeometry,
// circleGeometry, planeGeometry, latheGeometry, tubeGeometry: Geometry's
// generators, their props its options), the material tags
// (standardMaterial, lambertMaterial, phongMaterial, toonMaterial,
// unlitMaterial, matcapMaterial, normalMaterial, depthMaterial: Material's
// factories, their props their options), the lights (directionalLight,
// pointLight, spotLight, hemisphereLight; light, its kind a prop: directional
// | point | spot | hemisphere), camera (fov, near, far), instances (a node
// drawing an InstancedMesh: of={set}, its data the program's), sprites (a
// node drawing Sprites: of={set}, mode spherical | axis | fixed);
// listeners (onClick, onPointerDown, onPointerUp, onPointerMove,
// onPointerCancel, onPointerEnter, onPointerLeave, onTap: a SceneEvent) on
// any, called by a <Scene>'s picking (at a pointer's press: the node hit
// then owns it until it lifts), the nearest node hit and then its
// ancestors.
//
//   <mesh position={p}><cylinderGeometry radiusTop={0.2} height={1} flat/><toonMaterial color={c} steps={3}/></mesh>
//   <mesh geometry={rail} material={grass}/>
//
// Other names are an error (@:elements), and so is a prop an element does
// not take (@:props: SceneProps, from Geometry's and Material's options),
// when compiling. Texts and markers are hidden nodes. <Ui> (SceneTags) goes
// back to ui inside a scene. A prototype of the reactive layer for scenes
// (see the README's roadmap): properties go through setProperty by name
// here, their names checked, their values when set.
@:elements("node", "mesh", "instances", "sprites", "light", "directionalLight", "pointLight", "spotLight", "hemisphereLight", "camera", "boxGeometry",
	"sphereGeometry", "cylinderGeometry", "coneGeometry", "capsuleGeometry", "torusGeometry", "torusKnotGeometry", "ringGeometry", "circleGeometry",
	"planeGeometry", "latheGeometry", "tubeGeometry", "standardMaterial", "lambertMaterial", "phongMaterial", "toonMaterial", "unlitMaterial",
	"matcapMaterial", "normalMaterial", "depthMaterial")
@:events(helder.scene.view.SceneEvents)
@:props(helder.scene.view.SceneProps)
class SceneRenderer implements helder.view.Renders<SceneNode> {
	// the device meshes are made on (a <Scene> sets it when first drawn: the meshes made before it, then)
	public static var device(default, set):Null<helder.gfx.Device>;
	// the world elements are made in: a <Scene>'s (WORLD, provided to its children), else root's
	public static var world:Null<World>;
	public static final WORLD = new helder.view.graph.Context<Null<World>>(null, true);
	// (the markup's nodes by their scene nodes' ids: picking's; the meshes waiting for a device)
	static final nodes = new Map<Int, SceneNode>();
	static final pending:Array<SceneNode> = [];

	static function set_device(d:Null<helder.gfx.Device>) {
		device = d;
		if (d != null) {
			for (n in pending)
				if (n.node.valid) n.remesh();
			pending.resize(0);
		}
		return d;
	}

	// the markup's node of a scene node (null: none, or not made by markup)
	public static function of(n:Node):Null<SceneNode>
		return nodes.get(n.id());

	// the node of world's root, to render into
	public static function root(w:World):SceneNode {
		world = w;
		return new SceneNode(w.root, "root");
	}

	public static function createElement(tag:String):SceneNode {
		var w = (helder.view.graph.Graph.getOwner() == null ? null : helder.view.graph.Graph.use(WORLD)) ?? world;
		if (w == null) throw "SceneRenderer: no world (a <Scene>'s children, or rendered into SceneRenderer.root(world))";
		var n = new SceneNode(w.node(tag), tag);
		n.node.detach();
		nodes.set(n.node.id(), n);
		return n;
	}

	// the geometry and material tags, each made with its factory (markup
	// calls a literal tag's element_<tag>, Renders: a program links the
	// generators, the shading models and their shaders its markup names, not
	// every one createElement's switch on a name would)
	public static function element_boxGeometry():SceneNode
		return madeBy("boxGeometry", n -> Geometry.box(SceneOptions.of(BoxOptions, n.props)));

	public static function element_sphereGeometry():SceneNode
		return madeBy("sphereGeometry", n -> Geometry.sphere(SceneOptions.of(SphereOptions, n.props)));

	public static function element_cylinderGeometry():SceneNode
		return madeBy("cylinderGeometry", n -> Geometry.cylinder(SceneOptions.of(CylinderOptions, n.props)));

	public static function element_coneGeometry():SceneNode
		return madeBy("coneGeometry", n -> Geometry.cone(SceneOptions.of(ConeOptions, n.props)));

	public static function element_capsuleGeometry():SceneNode
		return madeBy("capsuleGeometry", n -> Geometry.capsule(SceneOptions.of(CapsuleOptions, n.props)));

	public static function element_torusGeometry():SceneNode
		return madeBy("torusGeometry", n -> Geometry.torus(SceneOptions.of(TorusOptions, n.props)));

	public static function element_torusKnotGeometry():SceneNode
		return madeBy("torusKnotGeometry", n -> Geometry.torusKnot(SceneOptions.of(TorusKnotOptions, n.props)));

	public static function element_ringGeometry():SceneNode
		return madeBy("ringGeometry", n -> Geometry.ring(SceneOptions.of(RingOptions, n.props)));

	public static function element_circleGeometry():SceneNode
		return madeBy("circleGeometry", n -> Geometry.circle(SceneOptions.of(CircleOptions, n.props)));

	public static function element_planeGeometry():SceneNode
		return madeBy("planeGeometry", n -> Geometry.plane(SceneOptions.of(PlaneOptions, n.props)));

	public static function element_latheGeometry():SceneNode
		return madeBy("latheGeometry", n -> Geometry.lathe(n.get("points", [new helder.gfx.shader.Vec2(0, -0.5), new helder.gfx.shader.Vec2(0.5, 0), new helder.gfx.shader.Vec2(0, 0.5)]),
			SceneOptions.of(LatheOptions, n.props)));

	public static function element_tubeGeometry():SceneNode
		return madeBy("tubeGeometry", n -> Geometry.tube(n.get("curve", helder.scene.math.Curve3.line(new Vec3(0, -0.5, 0), new Vec3(0, 0.5, 0))), SceneOptions.of(TubeOptions, n.props)));

	public static function element_standardMaterial():SceneNode
		return madeBy("standardMaterial", n -> Material.standard(SceneOptions.of(MaterialOptions, n.props)));

	public static function element_lambertMaterial():SceneNode
		return madeBy("lambertMaterial", n -> Material.lambert(SceneOptions.of(MaterialOptions, n.props)));

	public static function element_phongMaterial():SceneNode
		return madeBy("phongMaterial", n -> Material.phong(SceneOptions.of(PhongOptions, n.props)));

	public static function element_toonMaterial():SceneNode
		return madeBy("toonMaterial", n -> Material.toon(SceneOptions.of(ToonOptions, n.props)));

	public static function element_unlitMaterial():SceneNode
		return madeBy("unlitMaterial", n -> Material.unlit(SceneOptions.of(MaterialOptions, n.props)));

	public static function element_matcapMaterial():SceneNode
		return madeBy("matcapMaterial", n -> Material.matcap(SceneOptions.of(MatcapOptions, n.props)));

	public static function element_normalMaterial():SceneNode
		return madeBy("normalMaterial", n -> Material.normals(SceneOptions.of(MaterialOptions, n.props)));

	public static function element_depthMaterial():SceneNode
		return madeBy("depthMaterial", n -> Material.depth(SceneOptions.float(n.get("near", 0.1)), SceneOptions.float(n.get("far", 100.0)), SceneOptions.of(MaterialOptions, n.props)));

	// (a part's node, its factory)
	static function madeBy(tag:String, make:SceneNode->Dynamic):SceneNode {
		var n = createElement(tag);
		n.make = make;
		return n;
	}

	public static function createText(text:String):SceneNode
		return createMarker("#text");

	public static function createMarker(name:String):SceneNode {
		var n = createElement(name);
		n.node.visible = false;
		return n;
	}

	public static function setText(node:SceneNode, text:String) {}

	public static function holdsText(el:SceneNode):Bool
		return false;

	public static function setProperty(el:SceneNode, name:String, value:Dynamic) {
		var n = el.node;
		changed();
		switch name {
			case "name": n.name = value;
			case "position": n.position = (value : Vec3);
			case "rotation": n.rotation = (value : Quat);
			case "scale": n.scale = (value : Vec3);
			case "visible": n.visible = value;
			// (its selection group: post.outline's, 0 none; Outline.select)
			case "outline": helder.scene.render.Outline.select(n, value);
			case _:
				// (a component's property: the component made again from them)
				el.props.set(name, value);
				switch el.tag {
					case "mesh": el.remesh();
					case "instances" | "sprites": el.reinstance();
					case "light" | "directionalLight" | "pointLight" | "spotLight" | "hemisphereLight": el.relight();
					case "camera": el.recamera();
					// (a geometry or a material of a mesh: the mesh made again)
					case t if (part(t) != None):
						el.made = null;
						if (el.parent != null && el.parent.tag == "mesh") el.parent.remesh();
					case _:
				}
		}
	}

	public static function setStyle(el:SceneNode, value:Dynamic) {}

	// (a listener kept by its kind, found by index at each event: SceneBox's dispatch)
	public static function listen(el:SceneNode, name:String, handler:Dynamic) {
		var k = LISTENERS.indexOf(name);
		if (k < 0) throw 'SceneRenderer: no event $name (${LISTENERS.join(", ")})';
		if (el.handlers == null) el.handlers = [for (_ in LISTENERS) null];
		el.handlers[k] = handler;
	}

	// the listeners a scene node takes, SceneNode.handlers' order (SceneBox's kinds)
	public static final LISTENERS = ["onPointerDown", "onPointerUp", "onPointerMove", "onPointerEnter", "onPointerLeave", "onClick", "onPointerCancel", "onTap"];

	public static function insert(parent:SceneNode, node:SceneNode, before:Null<SceneNode>) {
		parent.node.add(node.node);
		nodes.set(node.node.id(), node);
		changed();
		// (a mesh's geometry or material tag: its mesh made with it)
		if (parent.tag == "mesh")
			switch part(node.tag) {
				case IsGeometry:
					parent.geometryPart = node;
					parent.remesh();
				case IsMaterial:
					parent.materialPart = node;
					parent.remesh();
				case None:
			}
		if (before != null) {
			// (the scene graph appends: move the ones from before on after it)
			var after = false, move = [];
			for (c in parent.node.children()) {
				if (c == before.node) after = true;
				if (after && c != node.node) move.push(c);
			}
			for (c in move)
				parent.node.add(c);
		}
		node.parent = parent;
	}

	public static function remove(parent:SceneNode, node:SceneNode) {
		node.node.detach();
		node.parent = null;
		nodes.remove(node.node.id());
		changed();
		if (parent.geometryPart == node) {
			parent.geometryPart = null;
			parent.remesh();
		}
		if (parent.materialPart == node) {
			parent.materialPart = null;
			parent.remesh();
		}
	}

	// whether a tag is a geometry's or a material's (a mesh's parts)
	public static function part(tag:String):Part
		return StringTools.endsWith(tag, "Geometry") ? IsGeometry : StringTools.endsWith(tag, "Material") ? IsMaterial : None;

	// (a geometry uploaded once for its device, its primitives by material: a
	// mesh of markup per geometry and material, so that the same ones are
	// one instanced draw)
	static final uploads = new haxe.ds.ObjectMap<VertexData, Array<Mesh>>();

	public static function meshOf(device:helder.gfx.Device, geometry:VertexData, material:Material):Mesh {
		var list = uploads.get(geometry);
		if (list == null) {
			var m = Shapes.of(device, geometry, material);
			uploads.set(geometry, [m]);
			return m;
		}
		for (m in list)
			if (m.primitives[0].material == material) return m;
		var p = list[0].primitives[0];
		var m = new Mesh();
		m.addPrimitive(new helder.scene.render.Mesh.Primitive(p.vertices, p.indices, p.indexFormat, p.count, material, p.bounds, p.skinned));
		list.push(m);
		return m;
	}

	// a geometry's uploads let go (one made by a tag, made again)
	static function release(device:helder.gfx.Device, geometry:VertexData) {
		var list = uploads.get(geometry);
		if (list == null) return;
		list[0].dispose(device);
		uploads.remove(geometry);
	}

	// (a node's property or place changed: the <Scene>s drawn again)
	public static var changed:Void->Void = () -> {};

	public static function parentOf(node:SceneNode):Null<SceneNode>
		return node.parent;

	public static function arrange(parent:SceneNode, nodes:Array<SceneNode>, before:SceneNode)
		for (n in nodes)
			insert(parent, n, before);

	public static function isNode(v:Dynamic):Bool
		return Std.isOfType(v, SceneNode);
}

// a node of the scene as markup sees it: the World's node, its tag, the
// properties that make its components
@:rendered(helder.scene.view.SceneRenderer)
class SceneNode {
	public final node:Node;
	public final tag:String;
	public var parent:Null<SceneNode>;
	public final props = new Map<String, Dynamic>();
	// its listeners by kind (SceneRenderer.LISTENERS; null: none)
	public var handlers:Null<Array<Null<SceneEvent->Void>>> = null;
	// a mesh's geometry and material tags (null: none)
	public var geometryPart:Null<SceneNode> = null;
	public var materialPart:Null<SceneNode> = null;
	// a geometry or material tag's value, made from its props when asked (null: made again)
	public var made:Null<Dynamic> = null;
	// a geometry or material tag's factory over its props (its element_<tag>'s: the factory linked only by the tags markup names)
	public var make:Null<SceneNode->Dynamic> = null;
	// a mesh's own material (its color, metallic and roughness props'), kept
	var own:Null<Material> = null;
	// a geometry tag's last upload (let go when made again)
	var uploaded:Null<VertexData> = null;

	public function new(node:Node, tag:String) {
		this.node = node;
		this.tag = tag;
		if (SceneRenderer.part(tag) != None) node.visible = false;
		switch tag {
			case "light" | "directionalLight" | "pointLight" | "spotLight" | "hemisphereLight": relight();
			case "camera": recamera();
			case _:
		}
	}

	@:allow(helder.scene.view.SceneRenderer) function get(name:String, def:Dynamic):Dynamic
		return props.exists(name) ? props.get(name) : def;

	@:allow(helder.scene.view) function remesh() {
		var device = SceneRenderer.device;
		if (device == null) {
			@:privateAccess if (SceneRenderer.pending.indexOf(this) < 0) SceneRenderer.pending.push(this);
			return;
		}
		// (its geometry: its tag's, its prop's, else its shape's)
		var geometry:Null<VertexData> = geometryPart != null ? geometryPart.geometry() : get("geometry", null);
		if (geometry == null) {
			var size = SceneOptions.float(get("size", 1.0));
			geometry = switch (get("shape", "box") : String) {
				case "sphere": Geometry.sphere({radius: size / 2});
				case "plane": Geometry.plane({width: size, height: size}).rotated(-Math.PI / 2, 0, 0);
				case _: Geometry.box({width: size, height: size, depth: size});
			}
			// (kept: the same shape one upload)
			var key = (get("shape", "box") : String) + ":" + size;
			var shared = shapes.get(key);
			if (shared == null) shapes.set(key, shared = geometry);
			geometry = shared;
		}
		// (its material: its tag's, its prop's, else its own of color, metallic and roughness)
		var material:Null<Material> = materialPart != null ? materialPart.material() : get("material", null);
		if (material == null) {
			if (own == null) own = new Material(tag);
			own.baseColor = get("color", new Vec4(0.8, 0.8, 0.8, 1));
			own.metallic = SceneOptions.float(get("metallic", 0.0));
			own.roughness = SceneOptions.float(get("roughness", 0.5));
			material = own;
		}
		MeshRenderer.attach(node, SceneRenderer.meshOf(device, geometry, material));
	}

	// (the shapes of shape and size made so far: one geometry each)
	static final shapes = new Map<String, VertexData>();

	// a geometry tag's geometry, made from its props (Geometry's generator of its name)
	public function geometry():VertexData {
		if (made != null) return made;
		if (make == null) throw 'SceneRenderer: <$tag> made by createElement, not by its element_$tag';
		var g:VertexData = make(this);
		// (its last upload let go: none else draws it)
		var device = SceneRenderer.device;
		if (uploaded != null && device != null) @:privateAccess SceneRenderer.release(device, uploaded);
		uploaded = g;
		made = g;
		return g;
	}

	// a material tag's material, made from its props (Material's factory of its name)
	public function material():Material {
		if (made != null) return made;
		if (make == null) throw 'SceneRenderer: <$tag> made by createElement, not by its element_$tag';
		var m:Material = make(this);
		made = m;
		return m;
	}

	@:allow(helder.scene.view.SceneRenderer) function reinstance() {
		if (tag == "sprites") {
			var set:Null<Sprites> = get("of", null);
			if (set == null) {
				InstancedMesh.detach(node);
				return;
			}
			set.mode = switch (get("mode", "spherical") : String) {
				case "axis": Axis;
				case "fixed": Fixed;
				case _: Spherical;
			}
			Sprites.attach(node, set);
			return;
		}
		var set:Null<InstancedMesh> = get("of", null);
		if (set != null) InstancedMesh.attach(node, set) else InstancedMesh.detach(node);
	}

	@:allow(helder.scene.view.SceneRenderer) function relight() {
		var c:Vec3 = get("color", new Vec3(1, 1, 1));
		var i = SceneOptions.float(get("intensity", 1.0));
		var kind:String = switch tag {
			case "directionalLight": "directional";
			case "pointLight": "point";
			case "spotLight": "spot";
			case "hemisphereLight": "hemisphere";
			case _: get("kind", "directional");
		}
		Light.attach(node, switch kind {
			case "point": Light.pointLight(c, i, SceneOptions.float(get("range", 10.0)));
			case "spot": Light.spot(c, i, SceneOptions.float(get("range", 10.0)), SceneOptions.float(get("inner", 0.3)), SceneOptions.float(get("outer", 0.5)));
			case "hemisphere": Light.hemisphere(get("sky", new Vec3(0.3, 0.36, 0.48)), get("ground", new Vec3(0.12, 0.1, 0.09)), i);
			case _: Light.directional(c, i);
		});
	}

	@:allow(helder.scene.view.SceneRenderer) function recamera() {
		var cam = Camera.of(node);
		if (cam == null) cam = Camera.attach(node, Camera.perspective(SceneOptions.float(get("fov", 1.0)), SceneOptions.float(get("near", 0.1)), SceneOptions.float(get("far", 100.0))));
		else {
			cam.fovY = SceneOptions.float(get("fov", 1.0));
			cam.near = SceneOptions.float(get("near", 0.1));
			cam.far = SceneOptions.float(get("far", 100.0));
		}
	}
}

// what a tag is to a mesh (SceneRenderer.part)
enum abstract Part(Int) {
	var None;
	var IsGeometry;
	var IsMaterial;
}
