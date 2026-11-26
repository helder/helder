package helder.scene.view;

import helder.math.Vec4;
import helder.scene.render.MeshRenderer;
import helder.scene.view.SceneRenderer.SceneNode;
import helder.scene.view.SceneTags.*;
import helder.test.Test;
import helder.ui.Ui;
import helder.view.Render;

// Markup's geometry and material tags share a value by their props
// (SceneNode.parts), its upload one a device (SceneRenderer.uploads), held
// while a tag in the scene uses them: unmounted, taken out, or its <Scene>
// gone, they are let go (a preview host mounts screens over and over)
function tests() {
	describe("SceneParts", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("meshes of distinct props unmounted: no part, no upload left", () -> {
			var f = new Fixture(), before = f.held();
			var unmount = Render.render(Parts.distinct(20), SceneRenderer.root(f.world));
			// (20 geometries and 20 materials, 10 shapes: 50 parts, 30 uploads)
			equals(f.held(), [before[0] + 50, before[1] + 30]);
			unmount();
			equals(f.held(), before);
			f.dispose();
		});
		test("mounted again: the same props still one mesh", () -> {
			var f = new Fixture(), before = f.held();
			Render.render(Parts.distinct(4), SceneRenderer.root(f.world))();
			var unmount = Render.render(Parts.twins(), SceneRenderer.root(f.world));
			var a = MeshRenderer.of(f.world.root.find("a")), b = MeshRenderer.of(f.world.root.find("b"));
			equals(a != null && a == b, true);
			equals(f.held(), [before[0] + 2, before[1] + 1]);
			unmount();
			equals(f.held(), before);
			f.dispose();
		});
		test("taken out and put back (a boundary hiding it): let go, made again", () -> {
			var f = new Fixture(), before = f.held(), root = SceneRenderer.root(f.world);
			var unmount = Render.render(Parts.twins(), root);
			var a = SceneRenderer.of(f.world.root.find("a")), p = a.parent;
			SceneRenderer.remove(p, a);
			equals([MeshRenderer.of(a.node) == null, f.held()[0] == before[0] + 2], [true, true]);
			SceneRenderer.insert(p, a, null);
			equals(MeshRenderer.of(a.node) != null && MeshRenderer.of(a.node) == MeshRenderer.of(f.world.root.find("b")), true);
			unmount();
			equals(f.held(), before);
			f.dispose();
		});
		test("a <Scene> of its own world unmounted: its parts let go", () -> {
			var f = new Fixture(), before = f.held(), ui = new Ui(null, 100, 100);
			var unmount = Render.render(Parts.scene(), ui.root);
			ui.update();
			equals(f.held()[0] > before[0], true);
			unmount();
			equals(f.held(), before);
			f.dispose();
		});
		test("another device: the last one's uploads let go", () -> {
			var f = new Fixture(), before = f.held();
			var unmount = Render.render(Parts.distinct(4), SceneRenderer.root(f.world));
			var g = new Fixture();
			equals(g.held()[1], 0);
			unmount();
			equals(f.held()[0], before[0]);
			g.dispose();
			f.dispose();
		});
		#end
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (a world on a headless device, the device the meshes are made on)
private class Fixture {
	public final world = new World();
	final device:helder.gfx.Device;

	public function new() {
		SceneRenderer.device = null;
		device = helder.gfx.Device.create(helder.os.Surface.headless(16, 16));
		SceneRenderer.device = device;
	}

	// [shared parts, uploads]
	public function held():Array<Int>
		return [Lambda.count(@:privateAccess SceneNode.parts), Lambda.count([for (k in @:privateAccess SceneRenderer.uploads.keys()) k])];

	public function dispose() {
		world.dispose();
		SceneRenderer.device = null;
		device.dispose();
	}
}

private class Parts implements helder.view.Markup {
	// (n boxes of their own size and colour, n / 2 shapes of their own size)
	public static function distinct(n:Int)
		return <node>
			{[for (i in 0...n) <mesh>
				<boxGeometry width={1 + i} height={1} depth={1}/>
				<lambertMaterial color={new Vec4(i / n, 0, 0, 1)}/>
			</mesh>]}
			{[for (i in 0...n >> 1) <mesh shape="box" size={2 + i}/>]}
		</node>;

	public static function twins()
		return <node>
			<mesh name="a"><cylinderGeometry radiusTop={0.3} height={2}/><lambertMaterial color={new Vec4(0, 1, 0, 1)}/></mesh>
			<mesh name="b"><cylinderGeometry radiusTop={0.3} height={2}/><lambertMaterial color={new Vec4(0, 1, 0, 1)}/></mesh>
		</node>;

	public static function scene()
		return <view width={100} height={100}>
			<Scene flexGrow={1}>
				<mesh><torusGeometry radius={0.7} tube={0.1}/><standardMaterial color={new Vec4(0, 0, 1, 1)}/></mesh>
			</Scene>
		</view>;
}
#end
