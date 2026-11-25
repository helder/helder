import StageProbe.ProbeShader;
import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneEvent;
import helder.sprite.SpriteTags.*;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The boundary tags in windows (bun run test 3d: under Xvfb, Mesa): two
// <Surface>s, one with a reactive title, opened by Render.open; in the
// first a <Scene> box in ui's layout drawing a mesh (its pixels the
// scene's), a click over the mesh routed by ui's hit testing into the
// scene (picked), fingers picked at their presses (each its own, a tap,
// a cancel), a drag from the mesh orbiting the camera (<OrbitControls>),
// <Ui> over the mesh, a <Stick> drawn at rest; in the second a <Scene
// hdr> whose setup finds its post chain and adds a stage (StageProbe: the
// frame marked green) that prepares from the chain's context (the
// scene's light and its size); the second window closed by a Show, both
// by the root's dispose. The first box picks by triangles (pick="triangles":
// a click's uv and normal the face's) and holds <lines>, <axesHelper>,
// <boundsHelper> and <text3d> (their renderer's features added, their
// components on their nodes, a text following its signal), and a
// <TransformGizmo> on a node of its own: a drag on its arm moves the node
// along it, the camera not (the gizmo's gesture before the orbit's).
class SurfaceCheck implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('SurfaceCheck: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var title = signal("one");
		var second = signal(true);
		var picked = signal("");
		// (the last click's uv and normal's z: a struct local a closure assigns is not supported)
		var click:Array<Float> = [-1, -1, 0];
		var label = signal("one");
		var face = helder.text.FontFile.parse(helder.asset.Asset.embed("tests/canvas/fonts/DejaVuSans-canvas.ttf"));
		var path = new helder.scene.render.Lines(4, {width: 3});
		var touches:Array<String> = [];
		var orbit:Null<helder.scene.view.OrbitControls> = null;
		var stick = new helder.scene.input.VirtualStick({zone: helder.scene.input.Zone.rect(0, 0, 0.3, 1), radius: 20});
		var windows:Array<UiWindow> = [];
		var box:Null<helder.scene.view.SceneBox> = null;
		var sprites:Null<helder.sprite.SpriteBox> = null;
		// (the hdr box's setup: its post chain there, a stage added; what its prepare saw)
		var hdrBox:Null<helder.scene.view.SceneBox> = null;
		var setupPost = false, prepared = 0, preparedSize = "", preparedSource = false;
		function setup(r:helder.scene.render.Renderer) {
			var post = r.post;
			setupPost = post != null;
			if (post == null) return;
			var stage = post.add(ProbeShader);
			stage.prepare = enc -> {
				prepared++;
				preparedSize = '${post.width}x${post.height}';
				preparedSource = post.source != null;
			};
		}
		var world = new World("test"), eye = world.node("eye");
		eye.position = new Vec3(0, 0, 4);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		// (the gizmo's node: right of and below the mesh)
		var handle = world.node("handle");
		handle.position = new Vec3(1.2, -0.6, 0);
		var gizmo:Null<helder.scene.view.TransformGizmo> = null;
		// (the hdr box's world its own: a world's meshes are made on one device,
		// the first window's, and a GL context draws no other context's buffers)
		var hdrWorld = new World("hdr"), hdrEye = hdrWorld.node("eye");
		hdrEye.position = new Vec3(0, 0, 4);
		var hdrCamera = Camera.attach(hdrEye, Camera.perspective(0.8, 0.1, 100));
		var dispose = Render.open(<>
			<Surface title={title} width={320} height={200} background={0xFFFFFFFF} ref={w -> windows.push(w)}>
				<view flexDirection="row" flexGrow={1}>
					<view width={120}><text tag="label">{picked}</text><Sprites width={100} height={20} density={0.5} ref={b -> sprites = b}/></view>
					<Scene world={world} camera={camera} flexGrow={1} scale={0.5} pick="triangles" ref={b -> box = b}>
						<lines of={path} position={new Vec3(0, -1.2, 0)}/>
						<axesHelper size={0.5}/>
						<text3d font={face} text={label} size={0.3} billboard position={new Vec3(0, 1.1, 0)}/>
						<mesh name="cube" shape="box" size={1.4} color={new Vec4(1, 0.2, 0.1, 1)} onClick={(e:SceneEvent) -> {
							picked("box");
							click[0] = e.uv.x;
							click[1] = e.uv.y;
							click[2] = e.normal.z;
						}}
							onPointerDown={(e:SceneEvent) -> touches.push('down ${e.pointerId}')} onPointerMove={(e:SceneEvent) -> touches.push('move ${e.pointerId}')}
							onPointerUp={(e:SceneEvent) -> touches.push('up ${e.pointerId}')} onPointerCancel={(e:SceneEvent) -> touches.push('cancel ${e.pointerId}')}
							onTap={(e:SceneEvent) -> touches.push('tap ${e.pointerId}')}><boundsHelper/></mesh>
						<OrbitControls damping={0.0} ref={o -> orbit = o}/>
						<TransformGizmo of={handle} size={30.0} ref={g -> gizmo = g}/>
						<light kind="directional" intensity={2.0}/>
						<Ui><text tag="over">over</text></Ui>
					</Scene>
				</view>
				<Stick bind={stick} left={10} bottom={10} color={0xFF000000} knob={0xFF0000FF}/>
			</Surface>
			<Show when={second}><Surface title="two" width={160} height={100} background={0xFFFFFFFF} ref={w -> windows.push(w)}>
				<text>two</text>
				<Scene world={hdrWorld} camera={hdrCamera} flexGrow={1} hdr setup={setup} ref={b -> hdrBox = b}/>
			</Surface></Show>
		</>);
		check("two windows", windows.length == 2 && windows[0].window.title == "one" && windows[1].window.title == "two",
			[for (w in windows) w.window.title].join(", "));
		title("uno");
		flush();
		check("a reactive title", windows[0].window.title == "uno", windows[0].window.title);
		var w = windows[0];
		var pixels = Bytes.alloc(w.device.width * w.device.height * 4);
		var w2 = windows[1];
		var pixels2 = Bytes.alloc(w2.device.width * w2.device.height * 4);
		// (UiWindow.run's loop for a few frames: the windows mapped, their events handled; the fifth frame captured)
		var frames = 0;
		helder.os.App.run(() -> {
			for (x in windows)
				if (!x.window.closed && x.needsFrame()) x.frame();
			frames++;
			if (frames == 5) {
				w.capture = pixels;
				w2.capture = pixels2;
			}
			w.ui.requestFrame();
			if (frames == 7) helder.os.App.quit();
			helder.os.App.wait(0.02);
		}, e -> for (x in windows) if (x.window == e.window) x.handle(e));
		// (the box: x 120 to 320, y 0 to 200 in points; the mesh at its centre)
		var s = w.renderer.scale, pw = w.device.width;
		function at(x:Float, y:Float):Array<Int> {
			var o = (Std.int(y * s) * pw + Std.int(x * s)) * 4;
			return [pixels.get(o), pixels.get(o + 1), pixels.get(o + 2)];
		}
		if (Sys.args().length > 0) sys.io.File.saveBytes(Sys.args()[0], Png.encode(pixels, pw, w.device.height));
		// (the mesh's face: off the <Ui>'s label at the centre)
		var mid = at(185, 70), corner = at(124, 4), panel = at(60, 120);
		check("the scene drawn in its box: the mesh", mid[0] > 120 && mid[0] > mid[1] + 30 && mid[0] > mid[2] + 30, Std.string(mid));
		check("the scene drawn in its box: its clear colour", corner[0] < 40 && corner[1] < 40 && corner[2] < 50, Std.string(corner));
		check("<Sprites> density: drawn at its pixels a point", sprites.drawnWidth == Math.round(100 * Math.min(s, 0.5)), '${sprites.drawnWidth} at $s');
		// (scale 0.5: its world drawn at half the box's pixels, stretched over all of it)
		check("scale: drawn at half the box's pixels", box.drawnWidth == Math.round(200 * s * 0.5) && box.drawnHeight == Math.round(200 * s * 0.5),
			'${box.drawnWidth}x${box.drawnHeight} at $s');
		check("ui's beside it", panel[0] > 240 && panel[1] > 240 && panel[2] > 240, Std.string(panel));
		// (the hdr box: its setup saw its post chain; the stage it added prepared from the run's context and drew)
		check("<Scene hdr>: its post chain there in setup", setupPost);
		check("a stage added in setup: prepared each run, from the scene's light at its size",
			prepared >= 1 && preparedSource && hdrBox != null && preparedSize == '${hdrBox.drawnWidth}x${hdrBox.drawnHeight}',
			'$prepared runs, $preparedSize, source $preparedSource');
		var s2 = w2.renderer.scale, o2 = (Std.int(70 * s2) * w2.device.width + Std.int(10 * s2)) * 4;
		var probe = [pixels2.get(o2), pixels2.get(o2 + 1), pixels2.get(o2 + 2)];
		check("a stage added in setup: drawn (the frame marked green)", probe[1] > 220 && probe[0] < 120 && probe[2] < 120, Std.string(probe));
		// (the stick at rest: its ring at 10 points from the lower left, its knob in its centre)
		var ring = at(11, 170), knob = at(30, 170);
		check("<Stick> at rest: its ring and its knob", ring[0] < 80 && ring[1] < 80 && knob[2] > 200 && knob[0] < 80, '$ring, $knob');
		// (ui's hit testing: the box under the pointer, the scene's picking then)
		w.ui.pointerMove(220, 100);
		w.ui.pointerDown(220, 100, 1);
		w.ui.pointerUp(220, 100, 1);
		check("a click routed into the scene: the mesh picked", picked() == "box", picked());
		// (by triangles: the box's front face, left of and above its middle)
		w.ui.pointerMove(205, 85);
		w.ui.pointerDown(205, 85, 1);
		w.ui.pointerUp(205, 85, 1);
		check("pick=\"triangles\": the face's uv", click[0] > 0.05 && click[0] < 0.5 && click[1] > 0.05 && click[1] < 0.5, '$click');
		check("pick=\"triangles\": the face's normal", click[2] > 0.99, '$click');
		// (the phase 3 tags: the box's renderer given lines and debug drawing; the components on their nodes)
		var sr = box.renderer;
		check("<lines>, <axesHelper>: the renderer's LineRenderer and DebugDraw", @:privateAccess sr.lines != null && @:privateAccess sr.debug != null);
		var lineNodes = world.store(helder.scene.render.Lines.KIND);
		// (the gizmo's handles are lines too, on a node of their own)
		var pathAt = -1;
		for (k in 0...lineNodes.length)
			if (lineNodes.valueAt(k) == path) pathAt = k;
		check("<lines>: its lines on a node of the scene", lineNodes.length == 2 && pathAt >= 0 && lineNodes.nodeAt(pathAt).position.y == -1.2);
		var helpers = world.store(helder.scene.render.Helper.KIND);
		var bounds = false, axes = false;
		for (k in 0...helpers.length) {
			var h = helpers.valueAt(k);
			if (Std.isOfType(h, helder.scene.render.BoundsHelper)) bounds = h.ofParent && helpers.nodeAt(k).parent.name == "cube";
			if (Std.isOfType(h, helder.scene.render.AxesHelper)) axes = true;
		}
		check("<boundsHelper>: the mesh's it is in; <axesHelper> its own", bounds && axes);
		var texts = world.store(helder.scene.render.InstancedMesh.KIND), text:Null<helder.scene.render.Text3D> = null;
		for (k in 0...texts.length)
			if (Std.isOfType(texts.valueAt(k), helder.scene.render.Text3D)) text = cast texts.valueAt(k);
		check("<text3d>: made on the box's device, billboard", text != null && text.text == "one" && text.billboard && text.mesh.primitives.length > 0);
		var triangles = text == null ? 0 : text.mesh.primitives[0].count;
		label("three");
		flush();
		check("<text3d>: its text follows its signal", text != null && text.text == "three" && text.mesh.primitives[0].count != triangles);
		w.ui.pointerDown(130, 10, 1);
		w.ui.pointerUp(130, 10, 1);
		check("a click beside the mesh: none", picked() == "box");
		// (fingers: picked at their presses, each its own; the mesh keeps one dragged off it)
		picked("");
		flush();
		touches.resize(0);
		check("a finger on the scene (off the <Ui>'s label) is the game's", !w.ui.pointerDown(185, 70, 1, 1, Touch));
		// (a second finger beside the box, on the ui's panel)
		w.ui.pointerDown(60, 10, 1, 2, Touch);
		w.ui.pointerMove(188, 70, 1);
		w.ui.pointerMove(110, 150, 2);
		w.ui.pointerUp(188, 70, 1, 1);
		w.ui.pointerUp(110, 150, 1, 2);
		check("fingers picked at their presses, a tap", touches.join(", ") == "down 1, move 1, up 1, tap 1" && picked() == "box", touches.join(", ") + "; " + picked());
		touches.resize(0);
		w.ui.pointerDown(185, 70, 1, 3, Touch);
		w.ui.pointerCancel(3);
		check("a cancel", touches.join(", ") == "down 3, cancel 3", touches.join(", "));
		// (a drag from the mesh orbits the camera: no tap)
		touches.resize(0);
		var eye = camera.eye();
		w.ui.pointerDown(185, 70, 1, 4, Touch);
		w.ui.pointerMove(200, 70, 4);
		w.ui.pointerMove(240, 70, 4);
		w.ui.pointerUp(240, 70, 1, 4);
		var moved = camera.eye();
		check("a drag from the mesh orbits the camera", orbit != null && moved.x < eye.x - 0.5 && touches.join(", ") == "down 4, move 4, move 4, up 4", '$eye to $moved; ' + touches.join(", "));
		touches.resize(0);
		// (a drag on the gizmo's x arm, its middle: the node moved along x, the camera not)
		var before = handle.position, eyeBefore = camera.eye();
		var arm = gizmo == null ? new Vec3(-100, -100, 0) : @:privateAccess gizmo.onBox(handle.worldPosition() + new Vec3(@:privateAccess gizmo.length() * 0.6, 0, 0));
		var gx = 120 + arm.x, gy = arm.y;
		w.ui.pointerDown(gx, gy, 1, 5, Touch);
		w.ui.pointerMove(gx + 10, gy, 5);
		w.ui.pointerMove(gx + 20, gy, 5);
		w.ui.pointerUp(gx + 20, gy, 1, 5);
		var after = handle.position, eyeAfter = camera.eye();
		check("<TransformGizmo>: its handles drawn over the scene", gizmo != null && gizmo.lines.count == 30 && @:privateAccess sr.lines != null);
		check("<TransformGizmo>: a drag on its arm moves its node along it, the camera not",
			after.x > before.x + 0.2 && Math.abs(after.y - before.y) < 1e-9 && eyeAfter.x == eyeBefore.x && eyeAfter.z == eyeBefore.z,
			'$before to $after, the eye $eyeBefore to $eyeAfter, the arm at $gx, $gy');

		// (density: at most a quarter of a device pixel a point here, under scale's half)
		box.density = s * 0.25;
		w.ui.requestFrame();
		w.frame();
		check("density: drawn at its pixels a point", box.drawnWidth == Math.round(200 * s * 0.25), '${box.drawnWidth} at $s');
		var over = w.root.find("over");
		var r = over == null ? null : over.windowBounds();
		check("<Ui> over its node: the box's centre", r != null && Math.abs(r.x + r.width / 2 - 220) < 4 && Math.abs(r.y + r.height / 2 - 100) < 4,
			r == null ? "none" : '${r.x},${r.y} ${r.width}x${r.height}');
		check("the label follows the pick", w.root.find("label") != null);
		second(false);
		flush();
		check("a Show's <Surface> closed", windows[1].window.closed);
		dispose();
		check("the root disposed: closed", windows[0].window.closed);
		Sys.println('SurfaceCheck: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
