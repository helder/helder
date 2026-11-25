package helder.scene.view;

import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.gfx.shader.Vec4 as V4;
import helder.os.Surface;
import helder.scene.math.Quat;
import helder.scene.view.SceneTags.*;
import helder.test.Test;
import helder.ui.Ui;
import helder.ui.draw.*;
import helder.view.Render;

// A <Scene> in a frame kept as data (helder.ui.draw.FrameArchive): its
// box the picture its pass drew (FrameWriter.pixels: the texture read
// back), the frame replayed from the file as the live one drew it
function tests() {
	describe("SceneFrames", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("a scene's box kept as its picture", () -> {
			var w = 240, h = 160;
			SceneRenderer.device = null;
			var device = Device.create(Surface.headless(w, h)), r = new Renderer(device);
			r.background = 0xFFFFFFFF;
			var ui = new Ui(new DrawText(), w, h);
			var dispose = Render.render(Fixture.toy(), ui.root);
			ui.update();
			final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.shader.Vec4(1, 1, 1, 1)}]};
			function frame(draw:() -> Void):Bytes {
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
			var live = frame(() -> ui.paint(r));
			var writer = new FrameWriter();
			writer.gpu(r);
			ui.paint(writer);
			var a = new FrameArchive();
			a.add("toy", "k", w, h, writer.frame());
			var list = FrameArchive.decode(a.encode()).list("toy");
			var replay = frame(() -> list.replay(r));
			// (a loop it draws in: none, its frames drawn by no renderer)
			var looped = new FrameWriter();
			looped.gpu(r);
			ui.paint(looped);
			looped.loop(30);
			ui.paint(looped);
			var withLoop = looped.frame();
			dispose();
			device.dispose();
			// (the scene drawn: not the background alone)
			var most = 0, off = 0, coloured = 0;
			for (i in 0...w * h) {
				var d = 0;
				for (c in 0...3) {
					var x = live.get(i * 4 + c), y = replay.get(i * 4 + c);
					d = Std.int(Math.max(d, Math.abs(x - y)));
				}
				if (d > most) most = d;
				if (d > 2) off++;
				var p = live.getInt32(i * 4);
				if (live.get(i * 4) != live.get(i * 4 + 2)) coloured++;
			}
			assert(coloured > 500, 'the scene drawn: $coloured coloured pixels');
			equals([writer.passes, looped.passes], [0, 1]);
			equals(withLoop.loop, null);
			// (1x, the scene's texture read back and drawn as an image: the same pixels, 2 a channel allowed)
			equals(off, 0);
		});
		test("a host's still: the scene's picture at 2x, its loop none (played live)", () -> {
			// (one device a process, as a program has: the last test's gone)
			SceneRenderer.device = null;
			var still = new helder.story.Story("Toy/Still", c -> Fixture.toy(), 1, null, 240, 160);
			var spin = new helder.story.Story("Toy/Spinning", c -> Fixture.toy(), 1, null, 240, 160, 2.0);
			var host = new helder.story.Host([still, spin], new helder.story.Host.HeadlessHost());
			host.still(true);
			host.show(["Toy/Still", "Toy/Spinning"]);
			host.frame(0);
			var a = new FrameArchive(), images = [];
			for (s in host.screens) {
				var f = host.written(s, 60);
				a.add(s.name, "k", s.width, s.height, f);
				images.push([for (i in f.images) '${i.width}x${i.height}']);
				equals(f.loop, null);
			}
			// (the box: 240 by 143 points, the text under it)
			equals(images, [["480x286"], ["480x286"]]);
			notEquals(FrameArchive.decode(a.encode()).list("Toy/Still"), null);
			host.device.dispose();
		});
		#end
	});
}

private class Fixture implements helder.view.Markup {
	public static function toy()
		return <view width={240} height={160} background="#0f172a">
			<Scene grow={1} antialias={false}>
				<camera position={new Vec3(0, 2.2, 6)} rotation={Quat.fromEuler(-0.35, 0, 0)} fov={0.8}/>
				<directionalLight intensity={1.6} rotation={Quat.fromEuler(-0.9, 0.6, 0)}/>
				<mesh rotation={Quat.fromEuler(0.5, 0.6, 0)}>
					<boxGeometry width={1.2} height={1.2} depth={1.2}/>
					<standardMaterial color={new Vec4(0.36, 0.55, 0.98, 1)} roughness={0.35}/>
				</mesh>
				<mesh position={new Vec3(-2.2, 0, 0)}>
					<sphereGeometry radius={0.6}/>
					<standardMaterial color={new Vec4(0.95, 0.55, 0.36, 1)} roughness={0.5}/>
				</mesh>
			</Scene>
			<text color="#ffffff" font-size={14}>over the scene</text>
		</view>;
}
