import haxe.io.Bytes;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// Liquid Glass drawn (helder.ui.draw.GlassPass, GlassShader) over
// GlassScene's backgrounds, headless (bun run test ui-soft: the golden,
// the CPU's; ui-draw: the GPU's against it), stripes over text, in a key
// window's look. How near it comes to the system's: GlassKindsCheck.
//   GlassCheck <golden.png> <out.png> [--bless]
//   GlassCheck --smoke: no golden (Windows' D3D11, run where nothing else checks it), the
//   stripes blurred under the capsule, their contrast well under theirs beside it
class GlassCheck {
	static inline var TOLERANCE = 6;
	static inline var MAX_FAR = 0.002;
	static inline var MEAN = 0.5;

	static function main() {
		var a = Sys.args();
		if (a[0] == "--smoke") return smoke();
		golden(a[0], a[1], a[2] == "--bless");
	}

	// (scene bg drawn at scale k: its pixels, its glass)
	static function draw(f:DrawFrame, bg:String, k:Float, glass = true, labels = true, group = false):{pixels:Bytes, glass:Array<Glass>} {
		var ui = new Ui(helder.ui.TextEngines.standard(), Std.int(GlassScene.W), Std.int(GlassScene.H));
		var gs = GlassScene.build(ui.root, bg, glass, labels, group);
		f.scale = k;
		ui.update();
		return {pixels: f.draw(ui), glass: gs};
	}

	// (the golden: stripes over text, a group among the stripes' glass)
	static final GOLDEN = ["stripes", "text"];

	static function golden(golden:String, out:String, bless:Bool) {
		var W = GlassScene.W, H = GlassScene.H, f = new DrawFrame(W, H), all = Bytes.alloc(W * H * 4 * GOLDEN.length);
		for (i => bg in GOLDEN)
			all.blit(i * W * H * 4, draw(f, bg, 1, true, true, true).pixels, 0, W * H * 4);
		Sys.println('GlassCheck ($f)');
		f.dispose();
		File.saveBytes(out, Png.encode(all, W, H * GOLDEN.length));
		if (bless) {
			File.saveBytes(golden, Png.golden(all, W, H * GOLDEN.length));
			Sys.println('GlassCheck: blessed $golden');
			return;
		}
		var want = helder.image.PngDecoder.decode(File.getBytes(golden));
		var d = ImageDiff.of(all, want.rgba, W, H * GOLDEN.length, TOLERANCE), ok = d.within(MAX_FAR, MEAN);
		Sys.println('GlassCheck: ${ok ? "ok" : "FAILED"} ($d)');
		Sys.exit(ok ? 0 : 1);
	}

	static function smoke() {
		var W = GlassScene.W, f = new DrawFrame(W, GlassScene.H), px = draw(f, "stripes", 1).pixels;
		Sys.println('GlassCheck ($f)');
		f.dispose();
		// (over the label's top, and below the capsule)
		inline function spread(y:Int):Int {
			var lo = 255, hi = 0;
			for (x in 130...270) {
				var v = px.get((y * W + x) * 4 + 1);
				if (v < lo) lo = v;
				if (v > hi) hi = v;
			}
			return hi - lo;
		}
		var inside = spread(46), outside = spread(115), ok = inside < outside / 2 && outside > 150;
		Sys.println('GlassCheck: smoke ${ok ? "ok" : "FAILED"}: the stripes $inside levels apart under the glass, $outside beside it');
		Sys.exit(ok ? 0 : 1);
	}
}
