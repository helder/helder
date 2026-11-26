package helder.scene.view;

import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.Surface;
import helder.scene.math.Quat;
import helder.scene.view.SceneTags.*;
import helder.test.Test;
import helder.ui.Ui;
import helder.ui.draw.*;
import helder.view.Render;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A <Scene> in a frame kept as data (helder.ui.draw.FrameArchive): one of
// markup alone as its tags and props (SceneData), built again and drawn in
// its place (PassCanvas, SceneReplay), its loop's frames as their props'
// steps; any other its box's picture (FrameWriter.pixels: the texture
// read back, a loop of it none); each replayed from the file as the live
// one drew it
function tests() {
	describe("SceneFrames", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("a scene set up in code: its box kept as its picture", () -> {
			var g = new Golden(240, 160), spin = Graph.signal(0.6);
			var dispose = Render.render(Fixture.toy(spin, false), g.ui.root);
			g.ui.update();
			var live = g.frame(() -> g.ui.paint(g.r));
			var writer = new FrameWriter();
			writer.gpu(g.r);
			g.ui.paint(writer);
			var a = new FrameArchive();
			a.add("toy", "k", 240, 160, writer.frame());
			var list = FrameArchive.decode(a.encode()).list("toy");
			var replay = g.frame(() -> list.replay(g.r));
			// (a loop it draws in: none, its frames drawn by no renderer)
			var looped = new FrameWriter();
			looped.gpu(g.r);
			g.ui.paint(looped);
			looped.loop(30);
			g.ui.paint(looped);
			var withLoop = looped.frame();
			dispose();
			g.dispose();
			assert(coloured(live) > 500, 'the scene drawn');
			equals([writer.passes, looped.passes], [0, 1]);
			equals(withLoop.loop, null);
			// (1x, the scene's texture read back and drawn as an image: the same pixels, 2 a channel allowed)
			equals(differ(live, replay, 2), 0);
		});
		test("a scene of markup alone kept as data: built again, drawn as it was", () -> {
			var g = new Golden(240, 160), spin = Graph.signal(0.6);
			var dispose = Render.render(Fixture.toy(spin, true), g.ui.root);
			g.ui.update();
			var live = g.frame(() -> g.ui.paint(g.r));
			var writer = new FrameWriter();
			writer.gpu(g.r);
			g.ui.paint(writer);
			var f = writer.frame();
			var a = new FrameArchive();
			a.add("toy", "k", 240, 160, f);
			var passes = [];
			var list = FrameArchive.decode(a.encode()).list("toy", passes);
			var scenes = [for (d in passes) SceneData.build(d)];
			var replay = g.frame(() -> list.replay(new PassCanvas(g.r, (k, x, y, w, h) -> scenes[k].draw(g.r, x, y, w, h))));
			// (the scene not drawn: not the live frame)
			var without = g.frame(() -> list.replay(new PassCanvas(g.r, (k, x, y, w, h) -> {})));
			dispose();
			for (s in scenes)
				s.box.dispose();
			g.dispose();
			equals({images: f.images.length, passes: passes.length, kind: passes[0].kind}, {images: 0, passes: 1, kind: "scene"});
			assert(coloured(live) > 500, 'the scene drawn');
			assert(differ(live, without, 2) > 500, 'the scene is what draws it');
			// (the scene's tags made again, drawn by the same renderer: within 2 a channel)
			equals(differ(live, replay, 2), 0);
		});
		test("a markup scene's loop: its frames' props, drawn as they were", () -> {
			var g = new Golden(240, 160), spin = Graph.signal(0.0);
			var dispose = Render.render(Fixture.toy(spin, true), g.ui.root);
			g.ui.update();
			var writer = new FrameWriter();
			writer.gpu(g.r);
			g.ui.paint(writer);
			writer.loop(30);
			var lives = [];
			for (f in 0...40) {
				if (f > 0) writer.next();
				spin(f * 0.1);
				Graph.flush();
				g.ui.update();
				g.ui.paint(writer);
				if (f % 13 == 0) lives.push({f: f, px: g.frame(() -> g.ui.paint(g.r))});
			}
			var a = new FrameArchive();
			a.add("toy", "k", 240, 160, writer.frame());
			var l = FrameArchive.decode(a.encode()).loop("toy", true);
			equals(l.lists.length, 40);
			var replay:Null<SceneData.SceneReplay> = null, off = [];
			for (s in lives) {
				var d = l.passes[s.f][0];
				if (replay == null) replay = SceneData.build(d) else replay.apply(d);
				var r = replay;
				off.push(differ(s.px, g.frame(() -> l.lists[s.f].replay(new PassCanvas(g.r, (k, x, y, w, h) -> r.draw(g.r, x, y, w, h)))), 2));
			}
			// (the frames differ: the scene turns)
			assert(differ(lives[0].px, lives[lives.length - 1].px, 2) > 100, 'it turns');
			dispose();
			replay.box.dispose();
			g.dispose();
			equals(off, [for (_ in lives) 0]);
		});
		test("a host's still: a scene in code its picture at 2x, its loop none", () -> {
			// (one device a process, as a program has: the last test's gone)
			SceneRenderer.device = null;
			var still = new helder.story.Story("Toy/Still", c -> Fixture.toy(0.6, false), 1, null, 240, 160);
			var spin = new helder.story.Story("Toy/Spinning", c -> Fixture.toy(0.6, false), 1, null, 240, 160, 2.0);
			var host = new helder.story.Host([still, spin], new helder.story.Host.HeadlessHost());
			host.still(true);
			host.show(["Toy/Still", "Toy/Spinning"]);
			host.frame(0);
			var images = [];
			for (s in host.screens) {
				var f = host.written(s, 60);
				images.push([for (i in f.images) '${i.width}x${i.height}']);
				equals(f.loop, null);
			}
			// (the box: 240 by 143 points, the text under it)
			equals(images, [["480x286"], ["480x286"]]);
			// (its screens let go: their <Scene>s' worlds with them)
			for (s in host.screens)
				s.reset();
			host.device.dispose();
		});
		#end
	});
}

// (the pixels that differ by more than tolerance in a channel)
function differ(a:Bytes, b:Bytes, tolerance:Int):Int {
	var n = 0;
	for (i in 0...a.length >> 2) {
		var d = 0;
		for (c in 0...3)
			d = Std.int(Math.max(d, Math.abs(a.get(i * 4 + c) - b.get(i * 4 + c))));
		if (d > tolerance) n++;
	}
	return n;
}

function coloured(px:Bytes):Int
	return [for (i in 0...px.length >> 2) if (px.get(i * 4) != px.get(i * 4 + 2)) i].length;

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (a renderer at 1x on a headless device, its frames read back)
private class Golden {
	static final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};

	public final ui:Ui;
	public final r:Renderer;
	final w:Int;
	final h:Int;
	final device:Device;

	public function new(w:Int, h:Int) {
		this.w = w;
		this.h = h;
		// (one device a process, as a program has: the last test's gone)
		SceneRenderer.device = null;
		device = Device.create(Surface.headless(w, h));
		r = new Renderer(device);
		r.background = 0xFFFFFFFF;
		ui = new Ui(new DrawText(), w, h);
	}

	public function frame(draw:() -> Void):Bytes {
		var enc = device.beginFrame();
		r.begin(w, h);
		draw();
		r.prepare(enc);
		enc.beginPass(pass);
		r.end(enc);
		enc.endPass();
		var b = Bytes.alloc(w * h * 4);
		device.readPixels(b);
		device.endFrame();
		return b;
	}

	public function dispose()
		device.dispose();
}
#end

private class Fixture implements helder.view.Markup {
	// (code: a renderer set up in code, a scene not of markup alone)
	public static function toy(spin:helder.view.graph.Read<Float>, markup:Bool)
		return <view width={240} height={160} background="#0f172a">
			<Scene flexGrow={1} antialias={false} setup={markup ? null : (r -> {})}>
				<camera position={new Vec3(0, 2.2, 6)} rotation={Quat.fromEuler(-0.35, 0, 0)} fov={0.8}/>
				<directionalLight intensity={1.6} rotation={Quat.fromEuler(-0.9, 0.6, 0)}/>
				<pointLight position={new Vec3(-2, 1.5, 2)} intensity={4} range={10}/>
				<mesh rotation={Quat.fromEuler(0.5, spin(), 0)}>
					<boxGeometry width={1.2} height={1.2} depth={1.2}/>
					<standardMaterial color={new Vec4(0.36, 0.55, 0.98, 1)} roughness={0.35}/>
				</mesh>
				<mesh position={new Vec3(-2.2, 0, 0)}>
					<sphereGeometry radius={0.6}/>
					<standardMaterial color={new Vec4(0.95, 0.55, 0.36, 1)} roughness={0.5}/>
				</mesh>
				<mesh position={new Vec3(2.2, 0, 0)} rotation={Quat.fromEuler(spin(), 0, 0)}>
					<torusGeometry radius={0.55} tube={0.2}/>
					<standardMaterial color={new Vec4(0.5, 0.85, 0.6, 1)} metallic={0.3} roughness={0.3}/>
				</mesh>
			</Scene>
			<text color="#ffffff" fontSize={14}>over the scene</text>
		</view>;
}
