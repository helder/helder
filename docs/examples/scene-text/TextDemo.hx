// title: Text in the world
// summary: Text3D: a word extruded and bevelled, lit and casting its shadow; a score turned to the camera over a ball, counting up; a flat sign; all of it helder.text's outlines made geometry
// tags: 3d, text, geometry, docs
// demo: canvas 640x400
import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.text.FontFile;

// Text3D draws a text as geometry: helder.text lays it out, helder.canvas
// gives its glyphs' outlines (their holes too), and Geometry.text makes
// them flat or extruded with a bevel. It is depth tested, lit or unlit,
// fogged and shadowed like any mesh, in one instanced draw, and sharp at
// any distance. billboard turns it to the camera. Setting text makes its
// glyphs again (a score's change, not every frame's).
//
//   helder run docs/examples/scene-text
class TextDemo {
	static function main() {
		var window = new Window("Text in the world", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Color(0.08, 0.1, 0.14);
		renderer.use(new Shadows(device, 2048));
		var world = new World("text");
		// #region text
		var font = FontFile.parse(Asset.embed("examples/fx/fonts/Inter.ttf"));
		var word = world.node("word");
		word.position = new Vec3(-0.6, 0.55, 0);
		Text3D.attach(word, new Text3D(device, font, "helder", {size: 1.1, depth: 0.3, bevelSize: 0.025, lit: true, castShadows: true,
			color: new Vec4(0.95, 0.6, 0.3, 1)}));
		var tag = world.node("tag");
		tag.position = new Vec3(2.4, 1.3, -0.6);
		var score = Text3D.attach(tag, new Text3D(device, font, "0", {size: 0.35, billboard: true, color: new Vec4(1, 0.95, 0.55, 1)}));
		var sign = world.node("sign");
		sign.position = new Vec3(-2.6, 1.9, -2);
		sign.rotation = Quat.fromEuler(0, 0.4, 0);
		Text3D.attach(sign, new Text3D(device, font, "Text in the world\ndepth tested, lit, sharp", {size: 0.22, align: 0, color: new Vec4(0.6, 0.9, 1, 1)}));
		// #endregion text
		var ball = world.node("ball");
		ball.position = new Vec3(2.4, 0.45, -0.6);
		MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.45}), Material.lambert({color: new Vec4(0.35, 0.6, 0.95, 1)})));
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.of(device, Geometry.plane({width: 30, height: 30}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new Vec4(0.32, 0.34, 0.38, 1)})));
		var sun = world.node("sun");
		sun.rotation = Quat.fromEuler(-0.8, 0.6, 0);
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.9), 2));
		var rig = world.node("rig");
		var eye = world.node("eye", rig);
		eye.position = new Vec3(0, 2.6, 6.5);
		eye.lookAt(new Vec3(0, 0.6, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		var shown = -1;
		App.run(() -> {
			var t = App.frame.time;
			rig.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.sin(t * 0.3) * 0.5);
			// (the score: its glyphs made again only when it changes)
			var n = Std.int(t * 4) % 1000;
			if (n != shown) {
				shown = n;
				score.text = Std.string(n);
			}
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
