// title: HDR and post-processing
// summary: A scene drawn in linear light into half floats, then bloomed, tone mapped and graded by a PostProcess into the frame; tap or press Space to switch the tone mapping (ACES, AgX, none)
// tags: 3d, hdr, post-processing, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.ToneMap;

// An HDR renderer (offscreen, hdr: new Renderer(device, true, samples,
// true)) keeps light brighter than white in RGBA16F targets; a PostProcess
// turns that light into the 8-bit frame: bloom (no threshold: the brighter
// a pixel, the more it spreads), tone mapping, a grade, a vignette. The
// lamps' emission is far above 1, so they bloom; Clamp shows what tone
// mapping saves.
//
//   helder run docs/examples/scene-post
class Post {
	static function main() {
		var window = new Window({title: "HDR and post-processing", width: 640, height: 400});
		var device = Device.create(window.surface);
		var renderer = new Renderer(device, true, 1, true);
		renderer.sunColor = new Vec3(1.2, 1.15, 1.1);
		renderer.sky = new Vec3(0.04, 0.05, 0.08);
		renderer.ground = new Vec3(0.02, 0.02, 0.02);
		renderer.clearColor = new Vec4(0.01, 0.012, 0.02, 1);

		var post = new PostProcess(device, RGBA8, true);   // RGBA8, into the frame
		post.bloom = 0.08;                                 // the share of the light spread
		post.toneMap = Aces;
		post.saturation = 1.1;
		post.vignette = 0.3;

		var world = new World("post");
		var floor = world.node("floor");
		floor.position = new Vec3(0, -0.6, 0);
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new Vec4(0.25, 0.25, 0.28, 1), 0, 0.5), 8));
		var glow = [new Vec3(8, 2.4, 0.6), new Vec3(0.4, 2.2, 6), new Vec3(1.2, 1.2, 1.2)];   // emission: linear light, above 1
		var lamps = [];
		for (k in 0...3) {
			var n = world.node("lamp" + k);
			n.position = new Vec3(-1.6 + k * 1.6, 0, 0);
			MeshRenderer.attach(n, Shapes.sphere(device, new Material("lamp" + k, new Vec4(0.1, 0.1, 0.1, 1), 0, 0.5, glow[k]), 0.4, 32, 16));
			lamps.push(n);
		}
		var bar = world.node("bar");
		bar.position = new Vec3(0, 1, -1);
		MeshRenderer.attach(bar, Shapes.box(device, new Material("bar", new Vec4(0, 0, 0, 1), 0, 1, new Vec3(20, 14, 6)), 3.2, 0.06, 0.06));

		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = new Vec3(0, 0.8, 5);
		eye.lookAt(new Vec3(0, 0.2, 0));

		var maps = [Aces, AgX, Clamp];
		var mapped = 0;
		// (the HDR targets at the frame's size, made again when it changes)
		var w = device.width, h = device.height, start = -1.0;
		var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: w, height: h, format: Depth32F});
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			for (k in 0...3) lamps[k].position = new Vec3(-1.6 + k * 1.6, Math.sin(t * 1.5 + k) * 0.15, 0);
			if (w != device.width || h != device.height) {
				w = device.width;
				h = device.height;
				device.destroyTexture(light);
				device.destroyTexture(depth);
				light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
				depth = device.createTexture({width: w, height: h, format: Depth32F});
			}
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h, t);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case KeyDown if (e.key == 0x20):
				mapped = (mapped + 1) % maps.length;
				post.toneMap = maps[mapped];
			case PointerDown:
				mapped = (mapped + 1) % maps.length;
				post.toneMap = maps[mapped];
			case _:
		});
	}
}
