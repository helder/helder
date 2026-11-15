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
// them, struct values (Quat, Vec3, Vec4) inline through the typed setters,
// set props written in place (DESIGN-MARKUP.md 10.1); Show adding and removing a
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
		check("Show: taken out, its node disposed", world.root.find("flag").isNone && !flag.valid);
		shown(true);
		flush();
		check("Show: back", !world.root.find("flag").isNone);
		check("For: rows", !world.root.find("io").isNone && !world.root.find("europa").isNone);
		moons(["europa", "ganymede"]);
		flush();
		check("For: a row removed (its node disposed), one added", world.root.find("io").isNone);
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
		typed();
		leaks();
		frames();
		#if hxmc.dev
		fights();
		#end
		Sys.println('SceneUiTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}

	// (DESIGN-MARKUP.md 10.1: struct values inline, constant and reactive,
	// through each prop's typed setter; set props written in place)
	static final up = new Vec3(0, 1, 0);

	static function typed() {
		var world = new World();
		var angle = signal(0.5), lift = signal(1.0), red = signal(0.25), power = signal(2.0), kind = signal("point");
		Render.render(<node>
			<node name="turned" rotation={helder.scene.math.Quat.axisAngle(up, angle())} position={new Vec3(0, lift(), 0)} scale={new Vec3(2, 2, 2)}/>
			<node name="fixed" rotation={helder.scene.math.Quat.axisAngle(up, 0.25)}/>
			<mesh name="painted" shape="box" color={new helder.gfx.shader.Vec4(red(), 0, 0, 1)} roughness={0.75}/>
			<light name="bulb" kind={kind()} intensity={power()} range={6} castShadows/>
			<camera name="lens" fov={angle() * 2}/>
		</node>, SceneRenderer.root(world));
		var turned = world.root.find("turned"), fixed = world.root.find("fixed");
		inline function near(a:Float, b:Float)
			return Math.abs(a - b) < 1e-9;
		check("an inline Quat, reactive", near(turned.rotation.y, Math.sin(0.25)));
		check("an inline Quat, constant", near(fixed.rotation.y, Math.sin(0.125)));
		check("an inline Vec3, reactive and constant", turned.position.y == 1 && turned.scale.x == 2);
		angle(1.0);
		lift(3.0);
		flush();
		check("an inline Quat follows its signal", near(turned.rotation.y, Math.sin(0.5)));
		check("an inline Vec3 follows its signal", turned.position.y == 3);
		var painted = world.root.find("painted");
		var own = @:privateAccess SceneRenderer.of(painted).ownMaterial();
		check("an inline Vec4 on a mesh's own material", own.baseColor.x == 0.25 && own.roughness == 0.75);
		red(0.5);
		flush();
		check("its own material's colour in place", @:privateAccess SceneRenderer.of(painted).ownMaterial() == own && own.baseColor.x == 0.5);
		var bulb = world.root.find("bulb"), light = Light.of(bulb);
		check("a light's set props", light.kind == Point && light.intensity == 2 && light.range == 6 && light.castShadows);
		power(5.0);
		flush();
		check("a light's intensity in place (the same Light)", Light.of(bulb) == light && light.intensity == 5);
		kind("spot");
		flush();
		var spot = Light.of(bulb);
		check("a make prop (kind): a new light, its set props kept", spot.kind == Spot && spot.intensity == 5 && spot.range == 6 && spot.castShadows);
		var lens = Camera.of(world.root.find("lens"));
		check("a camera's fov in place", lens != null && near(lens.fovY, 2.0));
		world.dispose();
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
			<For each={rows}>{k -> <node name="row"><node name="inner"/></node>}</For>
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
		check('removed elements dispose their world nodes (${world.count - before} left of ${before} before)', world.count == before);
		world.dispose();
	}

	// (3.3: an element's onFrame and a component's Frame.on, run by the
	// scope's frame while mounted, stopped with their owner)
	static function frames() {
		var world = new World();
		var scope = helder.scene.view.SceneScope.of(world);
		var shown = signal(true);
		var ticks = 0, spun = 0.0;
		Render.render(<node>
			<Show when={shown}>
				<node name="spinner" onFrame={f -> {
					ticks++;
					f.node.rotation = helder.scene.math.Quat.axisAngle(up, spun += f.dt);
				}}/>
				<Spinner/>
			</Show>
		</node>, SceneRenderer.root(world));
		check("onFrame: registered", scope.active);
		// (the first frame's seconds 0, then the time since the last, at most 0.1; one run a time)
		scope.frame(1.0);
		scope.frame(1.05);
		scope.frame(1.05);
		check("onFrame: run once a frame, given its seconds", ticks == 2 && Math.abs(spun - 0.05) < 1e-9 && spinnerTicks == 2);
		check("onFrame: its node written", Math.abs(world.root.find("spinner").rotation.y - Math.sin(0.025)) < 1e-9);
		shown(false);
		flush();
		scope.frame(2.0);
		check("onFrame and Frame.on: stopped with their owner", ticks == 2 && spinnerTicks == 2 && !scope.active);
		world.dispose();
	}

	#if hxmc.dev
	// (3.2's dev check: a bound prop written in code, then its binding again: said once, where it is written)
	static function fights() {
		var world = new World();
		var lift = signal(1.0);
		var told:Array<String> = [];
		helder.scene.view.SceneSet.onFight = (n, prop) -> told.push(n.tag + " " + prop + " " + (n.source != null));
		Render.render(<node name="fought" position={new Vec3(0, lift(), 0)}/>, SceneRenderer.root(world));
		lift(2.0);
		flush();
		check("bound, not driven: nothing said", told.length == 0);
		world.root.find("fought").position = new Vec3(5, 0, 0);
		lift(3.0);
		flush();
		lift(4.0);
		flush();
		check("bound and driven: said once, with its source", told.join(",") == "node position true");
		helder.scene.view.SceneSet.onFight = null;
		world.dispose();
	}
	#end

	static var spinnerTicks = 0;

	static function Spinner(props:{}):helder.scene.view.SceneView {
		helder.scene.view.Frame.on(dt -> spinnerTicks++);
		return <node name="spun"/>;
	}
}
