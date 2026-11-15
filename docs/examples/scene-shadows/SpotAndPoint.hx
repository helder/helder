// title: Spot and point shadows
// summary: A lantern's point light casting all round (six tiles of the shadow atlas, kept while nothing near it moves) and two spot lights sweeping a courtyard of posts (a tile each, one filtered soft), beside the sun's cascade, in one atlas
// tags: 3d, lights, shadows, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// Shadows is one atlas: the sun's cascades and, with local (LocalShadows),
// once a point or spot light casts (castShadows), a square of tiles for them, a spot light's one and
// a point light's six (a cube's faces as six frusta). At most maxLocal
// lights cast a frame, the ones that matter most to the view; a tile whose
// light and casters stayed put is kept from the frame before. Each light's
// shadow has its own size and filter (light.shadow).
//
//   helder run docs/examples/scene-shadows
class SpotAndPoint {
	static function main() {
		var window = new Window("Spot and point shadows", 640, 400);
		var device = Device.create(window.surface);
		// #region shadows
		var shadows = new Shadows(device, 1024).local({atlas: 1024, maxLocal: 3});
		var renderer = new Renderer(device).use(shadows);
		// #endregion
		renderer.clearColor = new Color(0.03, 0.03, 0.05);
		renderer.sky = new Vec3(0.05, 0.06, 0.09);
		renderer.ground = new Vec3(0.03, 0.03, 0.03);

		var world = new World("shadows");
		var stone = Material.lambert({color: new Vec4(0.62, 0.6, 0.58, 1)});
		MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 16, height: 16}).rotated(-Math.PI / 2, 0, 0), stone));
		var post = Shapes.of(device, Geometry.box({width: 0.25, height: 1.4, depth: 0.25}), new Material("post", new Vec4(0.8, 0.7, 0.55, 1), 0, 0.6));
		for (i in 0...4)
			for (j in 0...4) {
				var n = world.node();
				n.position = new Vec3(-3 + i * 2, 0.7, -3 + j * 2);
				MeshRenderer.attach(n, post);
			}
		var ball = world.node("ball");
		ball.position = new Vec3(0, 0.6, 0);
		MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.6}), new Material("ball", new Vec4(0.85, 0.85, 0.9, 1), 0, 0.3)));
		// a dim moon: the sun's cascade, the same atlas
		var moon = world.node("moon");
		Light.attach(moon, Light.directional(new Vec3(0.5, 0.6, 0.9), 0.25));
		moon.lookAt(new Vec3(0.4, -1, -0.3));
		// #region lights
		// the lantern: a point light casting all round (still: its six tiles
		// drawn once, then kept)
		var lantern = world.node("lantern");
		lantern.position = new Vec3(1, 1.6, 1);
		var bulb = Light.attach(lantern, Light.pointLight(new Vec3(1, 0.75, 0.45), 9, 7));
		bulb.castShadows = true;
		// two spot lights sweeping, one with a soft edge (a disc of taps)
		var spots = [];
		for (k in 0...2) {
			var n = world.node("spot" + k);
			n.position = new Vec3(k == 0 ? -5 : 5, 3.5, k == 0 ? 4 : -4);
			var l = Light.attach(n, Light.spot(k == 0 ? new Vec3(0.6, 0.8, 1) : new Vec3(1, 0.5, 0.6), 30, 14, 0.25, 0.4));
			l.castShadows = true;
			l.shadow = k == 0 ? {size: 512} : {size: 512, radius: 3};
			spots.push(n);
		}
		// #endregion
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 60));
		eye.position = new Vec3(0, 7, 9);
		eye.lookAt(new Vec3(0, 0, 0));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			for (k in 0...2)
				spots[k].lookAt(new Vec3(Math.cos(t * 0.5 + k * 3) * 2.5, 0, Math.sin(t * 0.7 + k * 3) * 2.5));
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
}
