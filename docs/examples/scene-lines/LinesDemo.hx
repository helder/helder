// title: Lines
// summary: Lines with a width: a path marching in dashes, its colour fading along it; zig-zags with mitred, round and bevelled joins; a ribbon as wide in metres as it is long; a ring hidden behind a pillar where it passes, and one drawn over everything
// tags: 3d, lines, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.Lines;

// Lines (helder.scene.render.Lines) are polylines or segments drawn as
// quads on the screen by a LineRenderer, so a width is a width on every
// back end: in pixels, or in metres (widthUnits: World, thinner far off).
// A program writes its points into the line's flat data each frame, as an
// InstancedMesh takes its instances: nothing is allocated, and the points
// are uploaded once when they changed.
//
//   helder run docs/examples/scene-lines
class LinesDemo {
	static function main() {
		var window = new Window("Lines", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Color(0.06, 0.07, 0.1);
		// #region lines
		renderer.use(new LineRenderer(device));
		var world = new World("lines");
		// a path to a target: dashed, marching (its dashes' offset moved each
		// frame), fading along it (see-through: its colours' alpha), round
		// at its joins and ends
		var aim = Lines.attach(world.node("aim"), new Lines(64, {width: 6, join: Round, cap: Round, dash: 0.25, gap: 0.15, transparent: true}));
		// three zig-zags: each join
		var joins:Array<LineJoin> = [Miter, Round, Bevel];
		for (k in 0...3) {
			var z = world.node("zigzag");
			z.position = new Vec3(-3.6, 2.4 - k * 0.7, -1);
			var l = Lines.attach(z, new Lines(6, {width: 10, join: joins[k], cap: k == 2 ? Square : Butt}));
			l.count = 6;
			for (i in 0...6)
				l.setPoint(i, i * 0.45, (i % 2) * 0.35, 0, 0.9, 0.5 + k * 0.2, 0.3);
		}
		// a ribbon 0.15 metres wide, away into the distance
		var road = Lines.attach(world.node("road"), new Lines(2, {width: 0.15, widthUnits: World, cap: Round}));
		road.count = 2;
		road.setPoint(0, 2.2, 0.02, 3, 0.3, 0.8, 1);
		road.setPoint(1, 0.8, 0.02, -12, 0.3, 0.8, 1);
		// a ring round the pillar, hidden behind it; a line over everything
		var ring = Lines.attach(world.node("ring"), new Lines(48, {width: 4, closed: true}));
		var over = Lines.attach(world.node("over"), new Lines(2, {width: 3, onTop: true}));
		// #endregion
		var pillar = world.node("pillar");
		pillar.position = new Vec3(1.8, 0.9, -1.2);
		MeshRenderer.attach(pillar, Shapes.of(device, Geometry.cylinder({radiusTop: 0.35, radiusBottom: 0.35, height: 1.8}), Material.lambert({color: new Vec4(0.75, 0.55, 0.35, 1)})));
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.of(device, Geometry.plane({width: 30, height: 30}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new Vec4(0.28, 0.3, 0.34, 1)})));
		var sun = world.node("sun");
		sun.rotation = Quat.fromEuler(-0.9, 0.5, 0);
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.9), 1.8));
		var eye = world.node("eye");
		eye.position = new Vec3(0, 3, 6.5);
		eye.lookAt(new Vec3(0, 0.6, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 100));
		App.run(() -> {
			var t = App.frame.time;
			// #region frame
			// (the path: a throw's arc to where the target bobs, refilled each frame)
			var tx = -1.2 + Math.sin(t * 0.7) * 1.2, tz = 0.8 + Math.cos(t * 0.5) * 0.6;
			aim.count = 32;
			for (i in 0...32) {
				var s = i / 31;
				aim.setPoint(i, -3 + (tx + 3) * s, 0.05 + Math.sin(s * Math.PI) * 1.6, 2.4 + (tz - 2.4) * s, 1, 0.8, 0.3, 1 - s * 0.8);
			}
			aim.dashOffset = -t * 0.8;
			// #endregion
			ring.count = 48;
			for (i in 0...48) {
				var a = i / 48 * Math.PI * 2;
				ring.setPoint(i, 1.8 + Math.cos(a) * 1.0, 0.9 + Math.sin(t + a * 2) * 0.15, -1.2 + Math.sin(a) * 1.0, 1, 0.85, 0.2);
			}
			over.count = 2;
			over.setPoint(0, 1.0, 0.3, -2.2, 1, 0.3, 0.7);
			over.setPoint(1, 2.6, 1.6, -0.2, 1, 0.3, 0.7);
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
