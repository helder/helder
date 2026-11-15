import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.*;
import helder.scene.render.*;

// Phase 5's frames (src/helder/scene/DESIGN-3D.md): indirect light (Scenes):
//   sh          the environment frame's spheres (mirror to rough, metal and
//               not) lit by the same panorama prefiltered by helder
//               (Environment.prefilter: an octahedral atlas, its irradiance
//               from the image's spherical harmonics; a dispatch where the
//               device has compute, a fragment pass elsewhere, one golden);
//               its probe checks the harmonics (brighter from the sky)
class IndirectScenes {
	public static final NAMES = ["sh"];

	public static function make(name:String, device:Device):Encoder->Void {
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		return switch name {
			case "sh":
				Images.decode = Images.png;
				var env = Environment.prefilterImage(device, "image/png", Asset.embed("panorama.png"), {size: 64, levels: 6, samples: 64});
				var r = new Renderer(device).use(env);
				Scenes.renderer = r;
				for (k in 0...5) {
					var rough = 0.05 + k * 0.235;
					var metal = world.node("metal" + k), plastic = world.node("plastic" + k);
					metal.position = new Vec3(-2.4 + k * 1.2, 0.65, 0);
					plastic.position = new Vec3(-2.4 + k * 1.2, -0.65, 0);
					MeshRenderer.attach(metal, Shapes.sphere(device, new Material("metal", new Vec4(0.95, 0.93, 0.88, 1), 1, rough), 0.5, 32, 16));
					MeshRenderer.attach(plastic, Shapes.sphere(device, new Material("plastic", new Vec4(0.8, 0.2, 0.15, 1), 0, rough), 0.5, 32, 16));
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2));
				sun.lookAt(new Vec3(0.35, -0.45, 0.82));
				eye.position = new Vec3(0, 0.3, 5.5);
				eye.lookAt(new Vec3(0, 0, 0));
				Scenes.probe = () -> {
					var up = env.sh.irradiance(new Vec3(0, 1, 0)), down = env.sh.irradiance(new Vec3(0, -1, 0));
					up.x + up.y + up.z > down.x + down.y + down.z ? null : 'sh: the sky (${up}) no brighter than the ground (${down})';
				};
				blackCorner(device, r);
				enc -> r.draw(enc, world, camera);
			case _: throw 'IndirectScenes: no scene $name';
		}
	}

	// (a bright background: a black mark in the corner, where the tests'
	// check that something was drawn looks for the clear colour)
	public static function blackCorner(device:Device, r:Renderer) {
		var ui = new helder.ui.draw.Renderer(device);
		var markPass:PassDesc = {colors: [{load: Load}]};
		r.inject(AfterPass, (enc, frame) -> {
			ui.begin(device.width, device.height);
			ui.rect(0, 0, 4, 4, 0, 0xFF000000, 0, 0);
			enc.beginPass(markPass);
			ui.end(enc);
			enc.endPass();
		});
	}
}
