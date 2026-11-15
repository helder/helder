import helder.gfx.shader.Vec3;
import helder.scene.*;
import helder.scene.render.InstancedMesh;
import helder.scene.render.Light;
import helder.scene.render.Mesh;
import helder.scene.render.Material;
import helder.scene.render.Sprites;
import helder.scene.view.SceneRenderer;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// helder.scene.view (npm test -- 3d: natively): markup making a
// world's nodes, lights and cameras; properties bound to signals following
// them (a struct value, Vec3, bound through a Signal: hxmc does not yet
// pass a closure returning one where a function of another type is
// expected, memo's or a bare function's); Show adding and removing a
// subtree; For keyed rows; <instances> attaching an InstancedMesh; a spot
// light's shadow props (Light.castShadows, Light.shadow); <lod> (Lod's
// levels, a visible range).
class SceneUiTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('SceneUiTest: FAIL: $what');
		}
	}

	// (a check known to fail until its milestone lands, DESIGN-MARKUP.md 11:
	// said, not counted; one that passes is said too, to be made a check)
	static function known(what:String, ok:Bool)
		Sys.println('SceneUiTest: ' + (ok ? 'known failure now passes (make it a check): $what' : 'known failure: $what'));

	static function main() {
		var world = new World();
		var x = signal(1.0);
		var pos = signal(new Vec3(1, 0, 0));
		var shown = signal(true);
		var moons = signal(["io", "europa"]);
		var rocks = new InstancedMesh(new Mesh(), 8);
		var clouds = new Sprites(null, new Material(), 4);
		var hi = new Mesh(), lo = new Mesh();
		Render.render(<node name="planet" position={pos}>
			<instances name="belt" of={rocks}/>
			<node name="ring" scale={new Vec3(2, 0.1, 2)}/>
			<light kind="point" intensity={() -> x() * 2} range={8.0}/>
			<Show when={shown}><node name="flag"/></Show>
			<For each={moons}>{m -> <node name={m()}/>}</For>
			<hemisphereLight name="sky" sky={new helder.gfx.shader.Vec3(0.5, 0.6, 0.9)} ground={new helder.gfx.shader.Vec3(0.3, 0.2, 0.1)} intensity={2}/>
			<sprites name="clouds" of={clouds} mode="axis"/>
			<mesh name="post"><cylinderGeometry radiusTop={0.2} height={1} flat/><toonMaterial steps={3}/></mesh>
			<spotLight name="lamp" range={12.0} castShadows shadowSize={512} shadowBias={0.002} shadowRadius={1.5}/>
			<lod name="tree" levels={[{mesh: hi, until: 0.15}, {mesh: lo}]} hysteresis={0.2} end={80.0}/>
		</node>, SceneRenderer.root(world));
		var planet = world.root.find("planet");
		check("made", !planet.isNone && planet.parent == world.root && !world.root.find("ring").isNone);
		check("a static property", world.root.find("ring").scale.x == 2);
		check("a bound property", planet.position.x == 1);
		x(3);
		flush();
		pos(new Vec3(3, 0, 0));
		flush();
		check("follows its signal", planet.position.x == 3);
		var light:Null<Light> = null;
		for (c in planet.children())
			if (Light.of(c) != null && Light.of(c).kind == Point) light = Light.of(c);
		check("a light, its bound intensity", light != null && light.kind == Point && light.intensity == 6 && light.range == 8);
		check("Show: there", !world.root.find("flag").isNone && world.inTree(world.root.find("flag")));
		var flag = world.root.find("flag");
		shown(false);
		flush();
		check("Show: taken out", world.root.find("flag").isNone && !world.inTree(flag));
		shown(true);
		flush();
		check("Show: back", !world.root.find("flag").isNone);
		check("For: rows", !world.root.find("io").isNone && !world.root.find("europa").isNone);
		moons(["europa", "ganymede"]);
		flush();
		check("For: a row removed, one added", world.root.find("io").isNone || !world.inTree(world.root.find("io")));
		check("For: the new row", !world.root.find("ganymede").isNone && world.inTree(world.root.find("ganymede")));
		check("instances: the set on its node", InstancedMesh.of(world.root.find("belt")) == rocks);
		var sky = Light.of(world.root.find("sky"));
		check("<hemisphereLight>: a hemisphere light, its sky and ground", sky != null && sky.kind == Hemisphere && sky.groundColor.x == 0.3 && sky.intensity == 2);
		check("<sprites>: the set on its node, its mode", InstancedMesh.of(world.root.find("clouds")) == clouds && clouds.mode == Axis);
		// (its parts, the mesh's geometry and material: made once a device is there)
		var post = SceneRenderer.of(world.root.find("post"));
		check("<mesh>'s <cylinderGeometry> and <toonMaterial>: its parts", post != null && post.geometryPart != null && post.geometryPart.tag == "cylinderGeometry"
			&& post.materialPart != null && post.materialPart.tag == "toonMaterial");
		var g = post.geometryPart.geometry();
		check("<cylinderGeometry>: Geometry.cylinder of its props (flat: a vertex a corner)", g.vertexCount == g.count && Math.abs(g.bounds.max.y - 0.5) < 1e-6);
		check("<toonMaterial>: Material.toon of its props", post.materialPart.material().steps == 3);
		var lamp = Light.of(world.root.find("lamp"));
		check("<spotLight castShadows shadowSize shadowBias shadowRadius>: its shadow", lamp != null && lamp.castShadows && lamp.shadow != null
			&& lamp.shadow.size == 512 && lamp.shadow.bias == 0.002 && lamp.shadow.radius == 1.5 && lamp.shadow.strength == null);
		var tree = world.root.find("tree");
		var lod = helder.scene.render.Lod.of(tree);
		check("<lod levels>: its levels", lod != null && lod.levels.length == 2 && lod.levels[0].until == 0.15 && lod.levels[1].until == null);
		check("<lod hysteresis>", lod != null && lod.hysteresis == 0.2);
		check("<lod>: its first level drawn", helder.scene.render.MeshRenderer.of(tree) == hi);
		var range = tree.world.store(helder.scene.render.Lod.RANGE).get(tree);
		check("<lod end>: a visible range", range != null && range.end == 80 && range.begin == 0);
		leaks();
		Sys.println('SceneUiTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}

	// a <Show> of meshes toggled a hundred times and a For of them mounted and
	// unmounted: the world's live nodes where they started (2.4; M2 fixes
	// remove, which detaches its nodes but never disposes them)
	static function leaks() {
		var world = new World();
		var root = SceneRenderer.root(world);
		var shown = signal(true), rows = signal([for (k in 0...100) k]);
		var before = world.count;
		var dispose = Render.render(<node>
			<Show when={shown}><node name="a"><node name="b"/></node></Show>
			<For each={rows}>{k -> <node name="row"/>}</For>
		</node>, root);
		for (_ in 0...100) {
			shown(!shown.peek());
			flush();
		}
		rows([]);
		flush();
		rows([for (k in 0...100) k]);
		flush();
		dispose();
		flush();
		known('removed elements dispose their world nodes (${world.count - before} left of ${before} before)', world.count == before);
		world.dispose();
	}
}
