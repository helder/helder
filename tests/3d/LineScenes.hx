import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.*;
import helder.math.Quat;
import helder.scene.render.*;
import helder.scene.render.Lines;

// Line reference frames: lines with width,
// debug drawing, the helpers, text in the world (Scenes):
//   lines      a zig-zag three times, 9 pixels wide (Miter joins and butt
//              caps, Round joins and caps, Bevel joins and square caps),
//              its colour blended along it; a line 0.12 metres wide running
//              away (thinner far off); a dashed ring round a pillar (its back
//              hidden by it); a line drawn over everything through the
//              pillar; a see-through one over the floor
//   debugdraw  each of DebugDraw's calls (through Debug's, kept in a test
//              build) in a frame: a line, a ray, an arrow, a box, a turned
//              box, a sphere, a circle, a point's cross, axes, a grid, a
//              second camera's frustum, a directional, a point and a spot
//              light, a chain's bones, a curve, and lines over everything;
//              its probe checks a frame allocates nothing (hxmc.GcStats)
//   helpers    the helpers on nodes: an infinite grid under it all, axes on
//              a turned node, a turned box's bounds, a spot and a point
//              light's, a second camera's frustum, a chain's skeleton
//   text3d     Text3D: a word extruded and bevelled, lit, casting its shadow;
//              a flat label turned to the camera (billboard) over a sphere;
//              two lines aligned right, unlit, far off; a raycast at the
//              word hitting its glyphs' triangles (its probe)
class LineScenes {
	public static final NAMES = ["lines", "debugdraw", "helpers", "text3d"];

	public static function make(name:String, device:Device):Encoder->Void {
		var r = new Renderer(device);
		Scenes.renderer = r;
		r.clearColor = new Vec4(0.06, 0.07, 0.1, 1);
		var world = new World();
		var floor = world.node("floor");
		MeshRenderer.attach(floor,
			Shapes.of(device, Geometry.plane({width: 12, height: 12}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new Vec4(0.32, 0.34, 0.38, 1)})));
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.9), 1.8));
		sun.rotation = Quat.fromEuler(-0.9, 0.5, 0);
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 60));
		eye.position = new Vec3(0, 3.2, 6.2);
		eye.lookAt(new Vec3(0, 0.6, 0));
		return switch name {
			case "lines":
				var lines = new LineRenderer(device);
				r.use(lines);
				var pillar = world.node("pillar");
				pillar.position = new Vec3(1.6, 0.8, -0.6);
				MeshRenderer.attach(pillar, Shapes.of(device, Geometry.box({width: 0.6, height: 1.6, depth: 0.6}), Material.lambert({color: new Vec4(0.75, 0.55, 0.35, 1)})));
				// (three zig-zags: each join and cap)
				var styles:Array<LinesOptions> = [
					{width: 9, join: Miter, cap: Butt},
					{width: 9, join: Round, cap: Round},
					{width: 9, join: Bevel, cap: Square}
				];
				for (s in 0...3) {
					var z = world.node("zigzag");
					z.position = new Vec3(-3.2, 2.2 - s * 0.75, 0);
					var l = Lines.attach(z, new Lines(8, styles[s]));
					l.count = 6;
					for (i in 0...6)
						l.setPoint(i, i * 0.45, (i % 2) * 0.4, 0, 1 - i * 0.15, 0.4 + i * 0.1, 0.2 + s * 0.3);
				}
				// (0.12 metres wide, from near the camera into the distance)
				var road = Lines.attach(world.node("road"), new Lines(2, {width: 0.12, widthUnits: World, cap: Round}));
				road.count = 2;
				road.setPoint(0, -1.4, 0.02, 3.5, 0.3, 0.9, 1);
				road.setPoint(1, -0.2, 0.02, -8, 0.3, 0.9, 1);
				// (a dashed ring round the pillar: behind it hidden)
				var ring = Lines.attach(world.node("ring"), new Lines(40, {width: 5, closed: true, dash: 0.25, gap: 0.15, join: Round}));
				ring.count = 40;
				for (i in 0...40) {
					var a = i / 40 * Math.PI * 2;
					ring.setPoint(i, 1.6 + Math.cos(a) * 1.1, 0.9, -0.6 + Math.sin(a) * 1.1, 1, 0.85, 0.2);
				}
				// (over everything: through the pillar)
				var over = Lines.attach(world.node("over"), new Lines(2, {width: 4, overlay: true, toneMapped: false}));
				over.count = 2;
				over.setPoint(0, 0.6, 0.5, -1.6, 1, 0.2, 0.6);
				over.setPoint(1, 2.8, 1.3, 0.4, 1, 0.2, 0.6);
				// (see-through, over the floor; segments: two crossing)
				var glass = Lines.attach(world.node("glass"), new Lines(4, {segments: true, width: 14, transparent: true}));
				glass.count = 4;
				glass.setPoint(0, -2.6, 0.05, 2.2, 0.2, 1, 0.4, 0.45);
				glass.setPoint(1, 0.4, 0.05, 1.6, 0.2, 1, 0.4, 0.45);
				glass.setPoint(2, -2.0, 0.05, 1.2, 0.9, 0.3, 1, 0.45);
				glass.setPoint(3, -0.4, 0.05, 2.6, 0.9, 0.3, 1, 0.45);
				Scenes.probe = () -> lines.draws == 7 ? null : '${lines.draws} line draws (7: three zig-zags, the road, the ring, the line over, the see-through)';
				enc -> r.draw(enc, world, camera);
			case "debugdraw":
				var debug = new DebugDraw();
				r.use(debug);
				var other = world.node("other");
				var lens = Camera.attach(other, Camera.perspective(0.6, 0.3, 2.2));
				other.position = new Vec3(2.6, 1.2, 1.2);
				other.lookAt(new Vec3(3.2, 0.6, -1.5));
				var sunNode = world.node("sun2"), bulb = world.node("bulb"), spot = world.node("spot");
				Light.attach(sunNode, Light.directional(new Vec3(1, 0.9, 0.5), 1));
				sunNode.position = new Vec3(-2.6, 2.4, -1.5);
				sunNode.rotation = Quat.fromEuler(-1.1, 0.3, 0);
				Light.attach(bulb, Light.pointLight(new Vec3(0.4, 0.8, 1), 0.5, 0.45));
				bulb.position = new Vec3(-1.2, 0.6, 1.4);
				Light.attach(spot, Light.spot(new Vec3(1, 0.4, 0.8), 1, 1.4, 0.2, 0.35));
				spot.position = new Vec3(-0.4, 1.9, -1.2);
				spot.rotation = Quat.fromEuler(-Math.PI / 2, 0, 0);
				var chain = bones(world, new Vec3(0.9, 0.05, 1.6));
				var skin = new Skin(device, chain, [for (_ in 0...chain.length) for (k in 0...16) k % 5 == 0 ? 1.0 : 0.0]);
				var curve = helder.scene.math.Curve3.catmullRom([new Vec3(-3.4, 0.3, 2.2), new Vec3(-2.6, 1.1, 2.6), new Vec3(-1.8, 0.3, 2.4), new Vec3(-1.2, 1.0, 2.0)]);
				var box = new helder.scene.math.Aabb(new Vec3(0.4, 0, -1.6), new Vec3(1.2, 0.8, -0.8));
				var calls = () -> {
					var turned = Quat.fromEuler(0.3, 0.6, 0.2).toMat4();
					Debug.grid(new Vec3(0, 0.01, 0), 6, 12);
					Debug.line(new Vec3(-3.4, 0.2, -1.6), new Vec3(-2.0, 1.4, -1.6), 0xFF4040);
					Debug.ray(new Vec3(-1.8, 0.2, -1.4), new Vec3(0.3, 1, 0), 1.2);
					Debug.arrow(new Vec3(-1.0, 0.1, 0.6), new Vec3(0.2, 0.9, 0.2), 0x40FFC0);
					Debug.aabb(box);
					Debug.boxOf(helder.math.Mat4.translation(1.9, 0.5, 0.2) * turned, new Vec3(-0.35, -0.35, -0.35), new Vec3(0.35, 0.35, 0.35), 0xFFE040);
					Debug.sphere(new Vec3(0.4, 0.9, 0.9), 0.45);
					Debug.circle(new Vec3(-2.8, 0.02, 0.4), new Vec3(0, 1, 0), 0.5, 0xFF80FF);
					Debug.cross3(new Vec3(-2.8, 0.5, 0.4), 0.3);
					Debug.axes(helder.math.Mat4.translation(2.8, 0.02, 1.6) * turned, 0.6);
					Debug.frustum(lens, 1.5);
					Debug.light(sunNode);
					Debug.light(bulb);
					Debug.light(spot);
					Debug.skeleton(skin);
					Debug.path(curve, 24);
					Debug.overlay(true);
					Debug.line(new Vec3(0.2, 0.4, -1.8), new Vec3(1.4, 0.4, -0.6), 0xFFFFFF);
					Debug.overlay(false);
				};
				Scenes.probe = () -> {
					var segments = debug.drawn;
					if (segments < 300) return '$segments segments drawn (each call)';
					var wrong = framesAllocate(device, enc -> {
						calls();
						r.draw(enc, world, camera);
					});
					wrong;
				};
				enc -> {
					calls();
					r.draw(enc, world, camera);
				}
			case "helpers":
				r.use(new DebugDraw());
				// (turned: no line of it along the pixels' rows, where back ends round apart)
				var grid = world.node("grid");
				grid.rotation = Quat.fromEuler(0, 0.35, 0);
				GridHelper.attach(grid, {size: 8, divisions: 8, fade: 6});
				floor.visible = false;
				var a = world.node("axes");
				a.position = new Vec3(-2.4, 0.6, 0.4);
				a.rotation = Quat.fromEuler(0.4, 0.8, 0);
				AxesHelper.attach(a, 0.8);
				var box = world.node("box");
				box.position = new Vec3(-0.1, 0.55, -0.2);
				box.rotation = Quat.fromEuler(0, 0.7, 0.3);
				MeshRenderer.attach(box, Shapes.of(device, Geometry.torusKnot({radius: 0.35, tube: 0.12}), Material.lambert({color: new Vec4(0.8, 0.45, 0.3, 1)})));
				BoundsHelper.attach(box);
				var spot = world.node("spot");
				Light.attach(spot, Light.spot(new Vec3(1, 0.85, 0.4), 4, 1.6, 0.2, 0.4));
				spot.position = new Vec3(1.0, 1.8, -1.0);
				spot.rotation = Quat.fromEuler(-Math.PI / 2, 0, 0);
				LightHelper.attach(spot);
				var bulb = world.node("bulb");
				Light.attach(bulb, Light.pointLight(new Vec3(0.3, 0.7, 1), 3, 0.6));
				bulb.position = new Vec3(2.2, 0.7, 0.8);
				LightHelper.attach(bulb);
				var other = world.node("other");
				Camera.attach(other, Camera.perspective(0.6, 0.3, 2));
				other.position = new Vec3(-0.2, 1.6, 2.2);
				other.lookAt(new Vec3(-1.2, 0.4, 0));
				CameraHelper.attach(other, 0xFFC040, 1.4);
				var chain = bones(world, new Vec3(0.9, 0.05, 1.4));
				var holder = world.node("skinned");
				Skin.attach(holder, new Skin(device, chain, [for (_ in 0...chain.length) for (k in 0...16) k % 5 == 0 ? 1.0 : 0.0]));
				SkeletonHelper.attach(holder);
				Scenes.probe = () -> framesAllocate(device, enc -> r.draw(enc, world, camera));
				enc -> r.draw(enc, world, camera);
			case "text3d":
				r.use(new Shadows(device, 1024));
				var font = helder.text.FontFile.parse(helder.asset.Asset.embed("tests/canvas/fonts/DejaVuSans-Bold-canvas.ttf"));
				var word = world.node("word");
				word.position = new Vec3(-0.4, 0.45, 0.3);
				word.rotation = Quat.fromEuler(0, 0.25, 0);
				var solid = Text3D.attach(word, new Text3D(device, font, "helder", {size: 0.9, depth: 0.25, bevelSize: 0.02, lit: true, castShadows: true,
					color: new Vec4(0.95, 0.55, 0.25, 1)}));
				var ball = world.node("ball");
				ball.position = new Vec3(2.2, 0.45, -0.4);
				MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.45}), Material.lambert({color: new Vec4(0.35, 0.6, 0.9, 1)})));
				var tag = world.node("tag");
				tag.position = new Vec3(2.2, 1.25, -0.4);
				Text3D.attach(tag, new Text3D(device, font, "ball 42", {size: 0.3, billboard: true, color: new Vec4(1, 0.95, 0.6, 1)}));
				var sign = world.node("sign");
				sign.position = new Vec3(3.6, 2.0, -2.45);
				Text3D.attach(sign, new Text3D(device, font, "phase 3
lines, text", {size: 0.32, align: 1, color: new Vec4(0.6, 0.95, 0.7, 1)}));
				// (rays across the word at its middle's height: some through its glyphs, some between them)
				function hits():Int {
					var hit = new Hit(), n = 0;
					for (k in 0...40)
						if (world.raycast(new Vec3(-2 + k * 0.08, 0.45, 5), new Vec3(0, 0, -1), hit) && hit.node == word && hit.instance == 0 && hit.triangle >= 0) n++;
					return n;
				}
				Scenes.probe = () -> {
					var n = hits();
					if (n < 10) return 'only $n of 40 rays hit the word';
					solid.text = "hel";
					var fewer = hits();
					solid.text = "helder";
					if (fewer >= n) return 'the word made shorter, as many hits ($fewer, $n)';
					null;
				};
				enc -> r.draw(enc, world, camera);
			case n: throw 'LineScenes: no scene $n';
		}
	}

	// (a chain of five bones standing up from base, bending)
	static function bones(world:World, base:Vec3):Array<Node> {
		var chain = [];
		var parent:Null<Node> = null;
		for (k in 0...5) {
			var j = world.node("bone", parent);
			j.position = k == 0 ? base : new Vec3(0, 0.3, 0);
			j.rotation = Quat.fromEuler(0, 0, k == 0 ? 0 : 0.35);
			chain.push(j);
			parent = j;
		}
		return chain;
	}

	// (the frame drawn again: once warm, nothing allocated by a frame)
	static function framesAllocate(device:Device, draw:Encoder->Void):Null<String> {
		for (_ in 0...3) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		#if (target.name == "hxmc")
		var before = hxmc.GcStats.bytesAllocated();
		for (_ in 0...4) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		var bytes = hxmc.GcStats.bytesAllocated() - before;
		if (bytes != 0) return '$bytes bytes allocated by 4 frames (none expected)';
		#end
		return null;
	}
}
