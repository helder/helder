import helder.image.PngDecoder;

// Two PNGs of one size compared (ImageDiff), the soft lane's measure of
// the CPU's canvas against a GPU's frames:
//   PngDiff <a.png> <b.png> [tolerance (3)] [--max <share>] [--out <diff.png>]
// prints how they differ; with --max, exits 1 when more than that share
// of the pixels differ by more than the tolerance; --out writes where
// (each pixel's difference, scaled up, red past the tolerance) and prints
// the bounds of those past it in a 16-pixel grid.
class PngDiff {
	static function main() {
		var args = Sys.args();
		var max = args.indexOf("--max");
		var share = max < 0 ? -1.0 : Std.parseFloat(args[max + 1]);
		if (max >= 0) args.splice(max, 2);
		var o = args.indexOf("--out"), out = o < 0 ? null : args[o + 1];
		if (o >= 0) args.splice(o, 2);
		var a = PngDecoder.decode(sys.io.File.getBytes(args[0])), b = PngDecoder.decode(sys.io.File.getBytes(args[1]));
		var tolerance = args.length > 2 ? Std.parseInt(args[2]) : 3;
		if (a.width != b.width || a.height != b.height) {
			Sys.println('${args[0]}: ${a.width}x${a.height}, ${args[1]}: ${b.width}x${b.height}');
			Sys.exit(1);
		}
		var d = ImageDiff.of(a.rgba, b.rgba, a.width, a.height, tolerance);
		var off = Math.round(d.far / d.count * 100000) / 1000;
		var ok = share < 0 || d.within(share);
		if (out != null) {
			var w = a.width, h = a.height, px = haxe.io.Bytes.alloc(w * h * 4), cells = new Map<Int, Int>();
			for (i in 0...w * h) {
				var m = 0;
				for (k in 0...3)
					m = Std.int(Math.max(m, Math.abs(a.rgba.get(4 * i + k) - b.rgba.get(4 * i + k))));
				var v = Std.int(Math.min(255, m * 8));
				px.set(4 * i, m > tolerance ? 255 : v);
				px.set(4 * i + 1, m > tolerance ? 0 : v);
				px.set(4 * i + 2, m > tolerance ? 0 : v);
				px.set(4 * i + 3, 255);
				if (m > tolerance) {
					var c = Std.int((i % w) / 16) + Std.int(i / w / 16) * 10000;
					cells.set(c, (cells.get(c) ?? 0) + 1);
				}
			}
			sys.io.File.saveBytes(out, helder.image.PngEncoder.encode(px, w, h, true));
			var list = [for (c => n in cells) {c: c, n: n}];
			list.sort((x, y) -> y.n - x.n);
			Sys.println([for (e in list.slice(0, 12)) '${e.c % 10000 * 16},${Std.int(e.c / 10000) * 16}: ${e.n}'].join("  "));
		}
		Sys.println('${args[0]}: $d ($off% off)' + (ok ? "" : ' FAIL (more than ${share * 100}%)'));
		Sys.exit(ok ? 0 : 1);
	}
}
