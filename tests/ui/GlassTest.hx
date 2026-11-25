import haxe.io.Bytes;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// Liquid Glass drawn (helder.ui.draw.GlassPass, GlassShader) over
// GlassScene's backgrounds, headless (bun run test ui-soft: the golden,
// the CPU's; ui-draw: the GPU's against it), stripes over text;
// and against the system's (macOS 26's NSGlassEffectView over the same
// backgrounds, tests/ui/glass-reference/: glass-reference.swift's), how
// near it comes: the mean difference over the glass and its rim, and the
// two side by side.
//   GlassTest <golden.png> <out.png> [--bless]
//   GlassTest --smoke: no golden (Windows' D3D11, run where nothing else checks it), the
//   stripes blurred under the capsule, their contrast well under theirs beside it
//   GlassTest --backgrounds dir [scale]: the backgrounds alone, dir/<bg>.png
//   GlassTest --compare refdir outdir [scale]: against refdir/<bg>.png,
//   outdir/<bg>.png the two side by side, the numbers printed
class GlassTest {
	static inline var TOLERANCE = 6;
	static inline var MAX_FAR = 0.002;
	static inline var MEAN = 0.5;

	static function main() {
		var a = Sys.args();
		if (a[0] == "--backgrounds") return backgrounds(a[1], a.length > 2 ? Std.parseFloat(a[2]) : 1);
		if (a[0] == "--compare") return compare(a[1], a[2], a.length > 3 ? Std.parseFloat(a[3]) : 1);
		if (a[0] == "--smoke") return smoke();
		if (a[0] == "--tune") return tune(a[1], Std.parseFloat(a[2]), a[3], [for (v in a[4].split(",")) Std.parseInt(v)]);
		golden(a[0], a[1], a[2] == "--bless");
	}

	// (scene bg drawn at scale k: its pixels, its glass)
	static function draw(f:DrawFrame, bg:String, k:Float, glass = true, labels = true, group = false):{pixels:Bytes, glass:Array<Glass>} {
		var ui = new Ui(new DrawText(), Std.int(GlassScene.W), Std.int(GlassScene.H));
		var gs = GlassScene.build(ui.root, bg, glass, labels, group);
		f.scale = k;
		ui.update();
		return {pixels: f.draw(ui), glass: gs};
	}

	// (the golden: stripes over text, a group among the stripes' glass; the
	// photo and the gradient, which compress poorly, only compared with the system's)
	static final GOLDEN = ["stripes", "text"];

	static function golden(golden:String, out:String, bless:Bool) {
		var W = GlassScene.W, H = GlassScene.H, f = new DrawFrame(W, H), all = Bytes.alloc(W * H * 4 * GOLDEN.length);
		for (i => bg in GOLDEN)
			all.blit(i * W * H * 4, draw(f, bg, 1, true, true, true).pixels, 0, W * H * 4);
		Sys.println('GlassTest ($f)');
		f.dispose();
		File.saveBytes(out, Png.encode(all, W, H * GOLDEN.length));
		if (bless) {
			// (compressed, RGB: the golden in the repository small)
			File.saveBytes(golden, helder.image.PngEncoder.encode(all, W, H * GOLDEN.length, true));
			Sys.println('GlassTest: blessed $golden');
			return;
		}
		var want = helder.image.PngDecoder.decode(File.getBytes(golden));
		var d = ImageDiff.of(all, want.rgba, W, H * GOLDEN.length, TOLERANCE), ok = d.within(MAX_FAR, MEAN);
		Sys.println('GlassTest: ${ok ? "ok" : "FAILED"} ($d)');
		Sys.exit(ok ? 0 : 1);
	}

	static function smoke() {
		var W = GlassScene.W, f = new DrawFrame(W, GlassScene.H), px = draw(f, "stripes", 1).pixels;
		Sys.println('GlassTest ($f)');
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
		Sys.println('GlassTest: smoke ${ok ? "ok" : "FAILED"}: the stripes $inside levels apart under the glass, $outside beside it');
		Sys.exit(ok ? 0 : 1);
	}

	static function backgrounds(dir:String, k:Float) {
		var W = Math.round(GlassScene.W * k), H = Math.round(GlassScene.H * k), f = new DrawFrame(W, H);
		for (bg in GlassScene.backgrounds) {
			var d = draw(f, bg, k, false);
			File.saveBytes('$dir/$bg.png', Png.encode(d.pixels, W, H));
			// (the glass, as the reference tool takes it)
			var ui = new Ui(new DrawText(), Std.int(GlassScene.W), Std.int(GlassScene.H));
			var gs = GlassScene.build(ui.root, bg);
			ui.update();
			File.saveContent('$dir/$bg.txt', [for (g in gs) GlassScene.spec(g)].join(" "));
		}
		f.dispose();
	}

	// (a search, one parameter at a time, of the look's parameters given
	// (GlassPass.regular's or clear's indices) that comes nearest the
	// references (at scale k) inside that variant's glass: the capsule, the clear rectangle)
	static function tune(refs:String, k:Float, variant:String, which:Array<Int>) {
		var W = Math.round(GlassScene.W * k), H = Math.round(GlassScene.H * k), f = new DrawFrame(W, H), shape = variant == "clear" ? 1 : 0;
		var bgs = [for (bg in GlassScene.backgrounds) if (sys.FileSystem.exists('$refs/$bg.png')) bg];
		var wants = [for (bg in bgs) helder.image.PngDecoder.decode(File.getBytes('$refs/$bg.png')).rgba];
		var look = variant == "clear" ? GlassPass.clear : GlassPass.regular;
		function loss():Float {
			var sum = 0.0, n = 0;
			for (i => bg in bgs) {
				var d = draw(f, bg, k, true, false), b = GlassScene.box(d.glass[shape], k), want = wants[i];
				for (y in b[1] + 1...b[3] - 1)
					for (x in b[0] + 1...b[2] - 1) {
						var o = (y * W + x) * 4;
						for (c in 0...3)
							sum += Math.abs(d.pixels.get(o + c) - want.get(o + c));
						n += 3;
					}
			}
			return sum / n;
		}
		var best = loss();
		for (round in 0...4)
			for (j in which) {
				var st = Math.max(Math.abs(look[j]) * 0.25, 0.05) / (1 << round), moved = true;
				while (moved) {
					moved = false;
					for (dir in [-1, 1]) {
						var was = look[j];
						look[j] = Math.max(0, was + dir * st);
						var l = loss();
						if (l < best - 0.001) {
							best = l;
							moved = true;
							break;
						}
						look[j] = was;
					}
				}
			}
		Sys.println('GlassTest: $variant: ${[for (x in look) Math.round(x * 1000) / 1000]}, ${Math.round(best * 100) / 100} levels');
		f.dispose();
	}

	static function compare(refs:String, outDir:String, k:Float) {
		var W = Math.round(GlassScene.W * k), H = Math.round(GlassScene.H * k), f = new DrawFrame(W, H), total = 0.0, outside = 0.0;
		var names = ["regular", "clear", "tinted"], sums = [0.0, 0.0, 0.0];
		var c = 0;
		for (bg in GlassScene.backgrounds) {
			// (iOS's references: no photo)
			if (!sys.FileSystem.exists('$refs/$bg.png')) continue;
			c++;
			var d = draw(f, bg, k, true, false), want = helder.image.PngDecoder.decode(File.getBytes('$refs/$bg.png')).rgba;
			// (over each glass's box grown by its shadow's reach; outside them all)
			var m = Math.round(8 * k), boxes = [for (g in d.glass) GlassScene.box(g, k)], line = [];
			inline function diff(x:Int, y:Int):Float {
				var o = (y * W + x) * 4, v = 0.0;
				for (c in 0...3)
					v += Math.abs(d.pixels.get(o + c) - want.get(o + c));
				return v / 3;
			}
			for (i => b in boxes) {
				var sum = 0.0, n = 0;
				for (y in Std.int(Math.max(0, b[1] - m))...Std.int(Math.min(H, b[3] + m)))
					for (x in Std.int(Math.max(0, b[0] - m))...Std.int(Math.min(W, b[2] + m))) {
						sum += diff(x, y);
						n++;
					}
				sums[i] += sum / n;
				line.push('${names[i]} ${Math.round(sum / n * 100) / 100}');
			}
			var out = 0.0, n = 0;
			for (y in 0...H)
				for (x in 0...W)
					if (!Lambda.exists(boxes, b -> x >= b[0] - m && x < b[2] + m && y >= b[1] - m && y < b[3] + m)) {
						out += diff(x, y);
						n++;
					}
			var side = Bytes.alloc(W * H * 8);
			for (y in 0...H) {
				side.blit(y * W * 8, want, y * W * 4, W * 4);
				side.blit(y * W * 8 + W * 4, d.pixels, y * W * 4, W * 4);
			}
			File.saveBytes('$outDir/$bg.png', Png.encode(side, W * 2, H));
			var whole = ImageDiff.of(d.pixels, want, W, H, 255);
			total += whole.mean;
			outside += out / n;
			Sys.println('GlassTest: $bg: ${line.join(", ")}; outside the glass ${Math.round(out / n * 100) / 100}; the frame ${Math.round(whole.mean * 100) / 100} (mean levels)');
		}
		Sys.println('GlassTest: against the system\'s, mean levels: ' + [for (i => s in sums) '${names[i]} ${Math.round(s / c * 100) / 100}'].join(", ")
			+ ', outside the glass ${Math.round(outside / c * 100) / 100}, the frame ${Math.round(total / c * 100) / 100}');
		f.dispose();
	}
}
