import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;

// helder.scene's frames natively against golden images (bun run test 3d), by
// helder.gfx's rule (GfxCheck.compareBytes: a pixel matches within 2 of
// each channel, at most 0.5% of them off), headless (Linux: an EGL pbuffer
// on llvmpipe; macOS: Metal; Windows: D3D11):
//
//   RenderCheck <scene> <golden.png> <out.png> [--bless]
//
// HXMC_ALLOC_ALL=1: also what a frame of the scene allocates, warm (four
// frames' hxmc.GcStats bytes, printed; the effects frame checks its own)
class RenderCheck {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;

	static function main() {
		var args = Sys.args();
		if (args.length < 3 || !Scenes.NAMES.contains(args[0])) {
			Sys.println("usage: RenderCheck " + Scenes.NAMES.join("|") + " <golden.png> <out.png> [--bless]");
			Sys.exit(2);
		}
		var name = args[0], golden = args[1], out = args[2];
		var device = try Device.create(Surface.headless(WIDTH, HEIGHT)) catch (e:String) {
			// (macOS virtual machines may have no GPU: check.sh skips, as gfx's)
			if (e != "helder.gfx: no Metal device") throw e;
			Sys.println("RenderCheck: skipped: no Metal device");
			Sys.exit(3);
			null;
		}
		var draw = Scenes.make(name, device);
		// (natively a lazy scene's files are read at once)
		if (!Scenes.ready()) throw 'RenderCheck: $name not ready';
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		var stats = Scenes.renderer;
		var drawsOk = true;
		if (stats != null) {
			Sys.println('RenderCheck: $name: ${stats.draws} draws, ${stats.instanced} instances in instanced draws, ${stats.culled} culled');
			// (169 nodes of two meshes: two instanced draws, unless culled)
			if (name == "instances" && (stats.draws > 2 || stats.instanced + stats.culled != 169)) drawsOk = false;
		}
		#if (target.name == "hxmc")
		if (Sys.getEnv("HXMC_ALLOC_ALL") == "1") {
			for (_ in 0...3) {
				var enc = device.beginFrame();
				draw(enc);
				device.endFrame();
			}
			var before = hxmc.GcStats.bytesAllocated();
			for (_ in 0...4) {
				var enc = device.beginFrame();
				draw(enc);
				device.endFrame();
			}
			Sys.println('RenderCheck: $name: ${hxmc.GcStats.bytesAllocated() - before} bytes allocated by 4 frames');
		}
		#end
		if (Scenes.probe != null) {
			var wrong = Scenes.probe();
			if (wrong != null) {
				Sys.println('RenderCheck: $name: FAIL: $wrong');
				drawsOk = false;
			} else
				Sys.println('RenderCheck: $name: its checks ok');
		}
		// (a twin: the scene drawn another way, the same frame by GfxCheck's rule)
		if (Scenes.twin != null) {
			var twin = Bytes.alloc(WIDTH * HEIGHT * 4);
			var enc = device.beginFrame();
			Scenes.twin(enc);
			device.readPixels(twin);
			device.endFrame();
			sys.io.File.saveBytes(haxe.io.Path.withoutExtension(out) + "-twin.png", Png.encode(twin, WIDTH, HEIGHT));
			if (!GfxCheck.compareBytes('$name, its twin', twin, Png.encode(pixels, WIDTH, HEIGHT))) drawsOk = false;
		}
		device.dispose();
		sys.io.File.saveBytes(out, Png.encode(pixels, WIDTH, HEIGHT));
		if (args[3] == "--bless") {
			sys.io.File.saveBytes(golden, Png.encode(pixels, WIDTH, HEIGHT));
			Sys.println('RenderCheck: blessed $golden');
			return;
		}
		var png = sys.io.File.getBytes(golden);
		// (HXMC_3D_TOLERANCE=n: channels within n levels of the golden's taken
		// as equal, then GfxCheck's rule; check.sh sets 3 on ARM64's llvmpipe,
		// whose filtering and arithmetic land up to 3 levels apart, gfx's own
		// frames there too)
		var tolerance = Std.parseInt(Sys.getEnv("HXMC_3D_TOLERANCE") ?? "");
		if (tolerance != null && tolerance > 0) {
			var g = Png.decode(png);
			if (g.width == WIDTH && g.height == HEIGHT)
				for (k in 0...WIDTH * HEIGHT * 4)
					if (Math.abs(pixels.get(k) - g.rgba.get(k)) <= tolerance) pixels.set(k, g.rgba.get(k));
			Sys.println('RenderCheck: $name: within $tolerance levels taken as equal');
		}
		Sys.exit(GfxCheck.compareBytes('$name, headless', pixels, png) && drawsOk ? 0 : 1);
	}
}
