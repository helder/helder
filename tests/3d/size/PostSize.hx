import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;

// What each of post's effects adds to a program (sizes.sh's post table):
// a window drawing a scene in HDR through a PostProcess (bloom, the grade:
// -D post_effect=none), and with one effect set (-D post_effect=ssao, dof,
// outline, fxaa, lut), or all (all). An effect a program never sets is not
// linked (its class, its passes, its shaders, the view buffers it reads).
class PostSize {
	static function main() {
		var window = new Window("PostSize", 320, 240);
		var device = Device.create(window.surface);
		var world = new helder.scene.World();
		var eye = world.node("eye");
		var camera = helder.scene.Camera.attach(eye, helder.scene.Camera.perspective(1, 0.1, 100));
		eye.position = new Vec3(0, 1, 5);
		eye.lookAt(new Vec3(0, 0, 0));
		helder.scene.render.MeshRenderer.attach(world.node("box"),
			helder.scene.render.Shapes.box(device, new helder.scene.render.Material("box", new Vec4(0.8, 0.5, 0.3, 1), 0, 0.5)));
		var renderer = new helder.scene.render.Renderer(device, true, 1, true);
		var post = new helder.scene.render.PostProcess(device, RGBA8, true);
		post.bloom = 0.05;
		renderer.post = post;
		#if (post_effect == "ssao" || post_effect == "all")
		post.ao = new helder.scene.render.Ssao({radius: 0.5});
		#end
		#if (post_effect == "dof" || post_effect == "all")
		post.dof = helder.scene.render.Dof.tiltShift({band: 0.2});
		#end
		#if (post_effect == "outline" || post_effect == "all")
		post.outline = new helder.scene.render.Outline({width: 2});
		#end
		#if (post_effect == "fxaa" || post_effect == "all")
		post.antialias = Fxaa;
		#end
		#if (post_effect == "lut" || post_effect == "all")
		post.lut = helder.scene.render.Lut.identity(device);
		#end
		var light = device.createTexture({width: 320, height: 240, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: 320, height: 240, format: Depth32F});
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.drawInto(enc, world, camera, light, depth, 320, 240);
			post.run(enc, light, null, 320, 240);
			device.endFrame();
		}, ev -> if (ev.kind == Close) window.close());
	}
}
