import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;

// What each of post's effects costs a frame (DESIGN-3D.md 7's budgets),
// measured headless on the machine's software rasterizer (Linux: Mesa's
// llvmpipe; Windows: D3D11's WARP): EffectScenes' courtyard at a phone's
// render size (0.75 of 1080 x 2400: 810 x 1800), each configuration
// drawn FRAMES times after WARM frames, each frame read back (the GPU's work
// done), its median time; "plain" is the frame with no effect (bloom off),
// "views" the view buffers' prepass alone; bench-* phase 7's effects
// (SSR, TAA, SMAA, motion blur of the camera and by objects, god rays,
// occlusion culling). A CPU's rasterizer is not a
// phone's GPU: the ratios to plain are what carry over, the ms do not.
//
//   EffectBench [width height]
class EffectBench {
	static inline var WARM = 4;
	static inline var FRAMES = 15;

	static function main() {
		var args = Sys.args();
		var w = args.length > 1 ? Std.parseInt(args[0]) : 810, h = args.length > 1 ? Std.parseInt(args[1]) : 1800;
		var device = Device.create(Surface.headless(w, h));
		var pixels = Bytes.alloc(w * h * 4);
		var plain = 0.0;
		Sys.println('EffectBench: ${w}x$h, the median of $FRAMES frames (each read back)');
		var names = ["plain", "views", "ssao", "dof", "tiltshift", "outline", "fxaa", "lut", "effects"];
		// (phase 7's: EffectScenes' bench-*; BENCH=a,b: those alone)
		names = names.concat(["bench-ssr", "bench-taa", "bench-smaa", "bench-motion", "bench-objects", "bench-godrays", "bench-occlusion"]);
		var only = Sys.getEnv("BENCH");
		if (only != null) names = ["plain"].concat(only.split(","));
		for (name in names) {
			var draw = EffectScenes.make(name, device);
			var times = [];
			for (k in 0...WARM + FRAMES) {
				var t0 = haxe.Timer.stamp();
				var enc = device.beginFrame();
				draw(enc);
				device.readPixels(pixels);
				device.endFrame();
				if (k >= WARM) times.push((haxe.Timer.stamp() - t0) * 1000);
			}
			times.sort(Reflect.compare);
			var ms = times[times.length >> 1];
			if (name == "plain") plain = ms;
			var r = Scenes.renderer;
			Sys.println('EffectBench: $name: ${Math.round(ms * 10) / 10} ms (+${Math.round((ms - plain) * 10) / 10} ms, ${Math.round(ms / plain * 100) / 100}x plain); draws: main ${r.draws}, prepass ${r.prepassDraws}, post ${r.post.draws}');
		}
	}
}
