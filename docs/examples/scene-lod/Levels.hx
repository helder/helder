// title: Levels of detail
// summary: A road of trees coming and going: each node's mesh picked by the share of the view it covers (Lod, red the finest, then green, then blue), and a forest of 6000 instances culled and levelled one by one (InstanceCulling: on the GPU where it can)
// tags: 3d, lod, instancing, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.Lod.LodLevel;

// A Lod on a node lists its meshes from the finest to the coarsest, each
// drawn while the node covers at least its `until` of the view's height
// (the same at any resolution or field of view), within a band of
// hysteresis so a node at the edge does not flicker. An InstancedMesh's
// levels are picked an instance at a time by InstanceCulling, which also
// drops the instances out of view: on the GPU (a dispatch a set, indirect
// draws) where the device has compute, else on the CPU.
//
//   helder run docs/examples/scene-lod
class Levels {
	static function main() {
		var window = new Window("Levels of detail", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Vec4(0.55, 0.65, 0.8, 1);
		renderer.sky = new Vec3(0.45, 0.5, 0.6);
		var world = new World("lod");
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2.2));
		sun.lookAt(new Vec3(-0.4, -0.8, -0.3));
		MeshRenderer.attach(world.node("ground"),
			Shapes.of(device, Geometry.plane({width: 400, height: 400}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new Vec4(0.35, 0.45, 0.3, 1)})));
		// #region levels
		var levels:Array<LodLevel> = [
			{mesh: tree(device, 24, new Vec4(0.85, 0.25, 0.2, 1)), until: 0.12},
			{mesh: tree(device, 10, new Vec4(0.25, 0.7, 0.3, 1)), until: 0.04},
			{mesh: tree(device, 5, new Vec4(0.25, 0.4, 0.85, 1)), until: 0.006}
		];
		var road = world.node("road");
		for (k in 0...40) {
			var n = world.node();
			n.position = new Vec3(k % 2 == 0 ? -3 : 3, 0, -k * 6);
			road.add(n);
			Lod.attach(n, levels);
		}
		// a forest of instances: culled and levelled one by one
		var forest = new InstancedMesh(levels[0].mesh, 6000);
		forest.levels = levels;
		for (i in 0...6000) {
			var x = (i % 100) * 3.5 - 175, z = -Std.int(i / 100) * 3.5 - 8;
			if (Math.abs(x) < 8) x += x < 0 ? -10 : 10;
			forest.setTransform(i, x + Math.sin(i * 12.9) * 1.2, 0, z + Math.cos(i * 7.3) * 1.2, 0, 0, 0, 1, 0.8 + (i % 5) * 0.1);
		}
		InstancedMesh.attach(world.node("forest"), forest);
		renderer.use(new InstanceCulling(device));
		// #endregion
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 400));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			// (along the road and back)
			var z = 20 - (1 - Math.cos(t * 0.25)) * 100;
			eye.position = new Vec3(0, 2.5, z);
			eye.lookAt(new Vec3(0, 1.5, z - 20));
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.draw(enc, world, camera);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}

	// a tree of a cone's segments: a trunk and a crown of a colour
	static function tree(device:Device, segments:Int, color:Vec4):Mesh
		return Shapes.of(device, Geometry.cone({radius: 1.2, height: 3.5, radialSegments: segments}).translated(0, 2.25, 0), Material.lambert({color: color}));
}
