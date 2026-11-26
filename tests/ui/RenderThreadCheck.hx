import helder.math.Vec4;
import haxe.io.Bytes;
import haxe.Timer;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// The render thread (helder.gfx.RenderThread) in a real window (bun run
// test ui-draw; Linux: Xvfb):
// - frames: DamageCheck's trees changed at random over frames, drawn whole
//   and kept, from tiles and not, each frame read back, on a device whose
//   commands run on the render thread, then on a synchronous one on the
//   same window: the same pixels;
// - stress: textures and buffers made, written from arrays reused at once,
//   read back, destroyed while frames are on their way, the window resized
//   meanwhile; then a helder.ui.UiWindow closed with a frame on its way: nothing left
//   in the back end's tables, the device's texture bytes back to 0;
// - --time n: a helder.ui.UiWindow of 400 rows scrolled a pixel a frame, n frames
//   each way: frame times, and the time from a frame's start (its events
//   handled) to its present returning (input to present), printed; with
//   --work ms, that much of the program's own work after each frame.
//   RenderThreadCheck [--time n [--work ms]]
class RenderThreadCheck {
	static inline var W = 320;
	static inline var H = 240;
	static inline var FRAMES = 40;

	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failed++;
		Sys.println('RenderThreadCheck: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : ' ($detail)'));
	}

	static function main() {
		var a = Sys.args(), t = a.indexOf("--time");
		var k = a.indexOf("--work");
		if (t >= 0) return time(Std.parseInt(a[t + 1]) ?? 300, k >= 0 ? Std.parseFloat(a[k + 1]) / 1000 : 0);
		var win = new Window({title: "RenderThreadCheck", width: W, height: H});
		var step = 0, threaded:Array<Array<Bytes>> = [];
		App.run(() -> {
			switch step++ {
				case 0:
					var device = Device.create(win.surface, {antialias: true, thread: true});
					Sys.println('RenderThreadCheck: a window of ${device.width}x${device.height}, ${device.threaded ? "on the render thread" : "synchronous (HELDER_RENDER_THREAD=0)"}');
					for (tiles in [false, true])
						for (tree in 0...2)
							threaded.push(frames(device, tree, tiles));
					device.dispose();
				case 1:
					var device = Device.create(win.surface, {antialias: true});
					var k = 0;
					for (tiles in [false, true])
						for (tree in 0...2) {
							var mine = frames(device, tree, tiles), theirs = threaded[k++], off = 0, first = -1;
							for (f in 0...mine.length)
								if (mine[f].compare(theirs[f]) != 0) {
									off++;
									if (first < 0) first = f;
								}
							check('tree $tree${tiles ? " from tiles" : ""}: the render thread\'s frames those of the synchronous path', off == 0,
								'$off of ${mine.length} frames differ${first < 0 ? "" : ", the first " + first}');
						}
					device.dispose();
				case 2:
					stress(win);
				case _:
					win.close();
					closing();
					Sys.println("RenderThreadCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
					Sys.exit(failed == 0 ? 0 : 1);
			}
		}, e -> {});
	}

	// (DamageCheck's tree, two renderers: drawn whole, then kept; each frame read back)
	static function frames(device:Device, tree:Int, tiles:Bool):Array<Bytes> {
		var w = device.width, h = device.height, scale = w / W, out = [];
		var made = [@:privateAccess DamageCheck.build(tree), @:privateAccess DamageCheck.build(tree)], rs = [for (k in 0...2) new Renderer(device)];
		for (k in 0...2) {
			rs[k].scale = scale;
			rs[k].groups = true;
			rs[k].tiles = tiles;
			made[k].ui.scale = scale;
		}
		rs[1].keep = true;
		var seed = tree * 31 + (tiles ? 7 : 0) + 1, t = Clock.now + 10;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		for (f in 0...FRAMES) {
			var op = rnd(10), i = rnd(1000), j = rnd(1000);
			for (m in made)
				@:privateAccess DamageCheck.change(m, op, i, j, f, tiles);
			t += 0.016;
			Clock.tick(t);
			for (k in 0...2) {
				var pixels = Bytes.alloc(w * h * 4);
				@:privateAccess DamageCheck.frame(device, made[k].ui, rs[k], w, h, pixels);
				out.push(pixels);
			}
		}
		return out;
	}

	// (resources made, written, read and destroyed while frames are on their way)
	static function stress(win:Window) {
		var device = Device.create(win.surface, {thread: true});
		var compute = device.has(Compute), seed = 12345;
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var textures:Array<Texture> = [], buffers:Array<Buffer> = [], made = 0, destroyed = 0, reads = 0, wrong = 0;
		var src = Bytes.alloc(64 * 64 * 4), back = Bytes.alloc(256), pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0.2, 0.3, 0.4, 1)}]};
		var target = device.createTexture({width: 64, height: 64, renderTarget: true});
		for (f in 0...240) {
			if (f % 60 == 30) win.resize(W + rnd(200), H + rnd(120));
			for (_ in 0...rnd(4)) {
				var s = 4 << rnd(5);
				src.fill(0, s * s * 4, f & 0xFF);
				textures.push(device.createTexture({width: s, height: s, data: src}));
				// (the array reused at once: the device copied it)
				src.fill(0, src.length, 0xEE);
				made++;
			}
			if (textures.length > 0) {
				var t = textures[rnd(textures.length)];
				device.writeTexture(t, src, 0, 0, 4, 4);
			}
			if (compute && rnd(3) == 0) {
				var b = device.createBuffer({size: 256, usage: Storage});
				for (i in 0...64)
					src.setInt32(i * 4, f * 1000 + i);
				device.writeBuffer(b, 0, src, 0, 256);
				src.fill(0, 256, 0);
				buffers.push(b);
				made++;
				if (rnd(2) == 0) {
					device.readBuffer(b, 0, back);
					reads++;
					for (i in 0...64)
						if (back.getInt32(i * 4) != f * 1000 + i) {
							wrong++;
							break;
						}
				}
			}
			var enc = device.beginFrame();
			if (enc != null) {
				enc.beginPass({colors: [{load: Clear, texture: target}]});
				enc.endPass();
				enc.beginPass(pass);
				enc.endPass();
				// (destroyed after the passes recorded, before they ran)
				while (textures.length > 8) {
					device.destroyTexture(textures.shift());
					destroyed++;
				}
				while (buffers.length > 4) {
					device.destroyBuffer(buffers.shift());
					destroyed++;
				}
				device.endFrame();
			}
		}
		for (t in textures)
			device.destroyTexture(t);
		for (b in buffers)
			device.destroyBuffer(b);
		destroyed += textures.length + buffers.length;
		device.destroyTexture(target);
		var r = @:privateAccess device.replay, live = 0;
		device.beginFrame();
		device.endFrame();
		@:privateAccess device.sync();
		for (t in [r.textures, r.buffers])
			for (v in t)
				if (v != 0) live++;
		check('stress: $made made, $destroyed destroyed, $reads read back while frames were on their way: none left', live == 0 && made == destroyed
			&& device.textureBytes == 0, '$live handles alive, ${device.textureBytes} texture bytes');
		check('stress: what was read back is what was written, the arrays reused at once', wrong == 0, '$wrong of $reads wrong');
		device.dispose();
	}

	// (a helder.ui.UiWindow closed right after a frame handed to the render thread)
	static function closing() {
		var w = new helder.ui.UiWindow({title: "RenderThreadCheck", width: W, height: H});
		var node = new Node();
		node.style.set({width: 100, height: 50, background: 0xFF3B82F6});
		w.root.append(node);
		w.frame();
		node.style.background = 0xFFEF4444;
		w.ui.requestFrame();
		w.frame();
		w.close();
		check('a window closed with a frame on its way', true);
	}

	static function time(n:Int, work:Float) {
		var w = new helder.ui.UiWindow({title: "RenderThreadCheck", width: 800, height: 600});
		var list = new Node();
		list.style.set({overflow: Scroll, height: 600, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...400) {
			var row = new Node();
			row.style.set({flexDirection: Row, padding: 3, columnGap: 6, background: i % 3 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF, alignItems: Center, borderRadius: 4});
			var box = new Node();
			box.style.set({width: 12, height: 12, background: 0xFF000000 | (i * 40503) & 0xFFFFFF, borderRadius: 6});
			row.append(box);
			row.append(new TextNode("Row " + i + " with a label of a few words"));
			list.append(row);
		}
		w.root.append(list);
		var starts:Array<Float> = [], presents:Array<Float> = [], busy:Array<Float> = [], k = 0;
		// (on the render thread: read once it is done)
		@:privateAccess w.device.replay.onEndFrame = () -> presents.push(Timer.stamp());
		App.run(() -> {
			var t0 = Timer.stamp();
			w.ui.scrollTo(w.root.children[0], 0, (k * 3) % 4000);
			w.frame();
			busy.push(Timer.stamp() - t0);
			// (the program's own work after a frame: an app's, accessibility's, a job's reply)
			var until = Timer.stamp() + work;
			while (Timer.stamp() < until) {}
			// (as helder.ui.UiWindow.run does, before the next events)
			w.device.settle();
			starts.push(t0);
			if (++k == n) {
				var threaded = w.device.threaded;
				w.close();
				report(starts, [for (i in 0...presents.length) presents[i] - starts[i]], busy, threaded);
				Sys.exit(0);
			}
		}, e -> {});
	}

	static function report(starts:Array<Float>, latency:Array<Float>, busy:Array<Float>, threaded:Bool) {
		var gaps = [for (i in 1...starts.length) starts[i] - starts[i - 1]];
		// (the first frames: shaders, atlases, tiles made)
		for (a in [gaps, latency, busy])
			a.splice(0, Std.int(a.length / 10));
		Sys.println('RenderThreadCheck: ${threaded ? "render thread" : "synchronous"}: frame ${stats(gaps)}, start to present ${stats(latency)}, the program\'s ${stats(busy)}');
	}

	static function stats(a:Array<Float>):String {
		var s = a.copy();
		s.sort(Reflect.compare);
		var sum = 0.0;
		for (v in s)
			sum += v;
		inline function ms(v:Float) return Math.round(v * 10000) / 10;
		return 'mean ${ms(sum / s.length)} ms, p50 ${ms(s[Std.int(s.length / 2)])}, p95 ${ms(s[Std.int(s.length * 0.95)])}';
	}
}
