package helder.image;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;

// The encoders read back by helder's decoders: a PNG the same pixels (its
// alpha dropped when opaque), a JPEG within a tolerance of a smooth image
// (transparent pixels the background's), each the size it was given.
function tests() {
	test("png: any pixels decoded back the same", () -> property(picture, p -> {
		for (opaque in [false, true]) {
			var d = PngDecoder.decode(PngEncoder.encode(p.rgba, p.width, p.height, opaque));
			equals([d.width, d.height], [p.width, p.height]);
			var want = p.rgba.sub(0, p.rgba.length);
			if (opaque) for (i in 0...p.width * p.height) want.set(i * 4 + 3, 255);
			if (d.rgba.compare(want) != 0) fail('opaque $opaque: pixels differ');
		}
	}, {cases: 100}));
	test("jpeg: a smooth image decoded back within a tolerance", () -> property(c -> {
		var w = c.draw(int(1, 48)), h = c.draw(int(1, 48));
		var from = [for (_ in 0...3) c.draw(int(0, 255))], to = [for (_ in 0...3) c.draw(int(0, 255))];
		var rgba = Bytes.alloc(w * h * 4);
		for (y in 0...h) for (x in 0...w) {
			var t = (x + y) / (w + h);
			for (k in 0...3)
				rgba.set((y * w + x) * 4 + k, Math.round(from[k] + (to[k] - from[k]) * t));
			rgba.set((y * w + x) * 4 + 3, 255);
		}
		{width: w, height: h, rgba: rgba, quality: c.draw(int(60, 100))};
	}, p -> {
		var d = JpegDecoder.decode(JpegEncoder.encode(p.rgba, p.width, p.height, p.quality));
		equals([d.width, d.height], [p.width, p.height]);
		var sum = 0.0, most = 0;
		for (i in 0...p.width * p.height) for (k in 0...3) {
			var e = Std.int(Math.abs(d.rgba.get(i * 4 + k) - p.rgba.get(i * 4 + k)));
			sum += e;
			if (e > most) most = e;
		}
		var mean = sum / (p.width * p.height * 3);
		assert(mean <= 4 && most <= 24, 'quality ${p.quality}: off by $mean on average, $most at most');
	}, {cases: 60}));
	test("jpeg: transparent pixels as the background", () -> property(c -> c.draw(int(0, 0xFFFFFF)), bg -> {
		var d = JpegDecoder.decode(JpegEncoder.encode(Bytes.alloc(16 * 16 * 4), 16, 16, 95, bg));
		for (k in 0...3) {
			var e = Math.abs(d.rgba.get(k) - (bg >> (16 - 8 * k) & 255));
			assert(e <= 3, 'channel $k off by $e');
		}
	}, {cases: 40}));
}

// (any pixels: runs of a few colours and noise, so that the filters and matches all come up)
private final picture:Gen<{width:Int, height:Int, rgba:Bytes}> = c -> {
	var w = c.draw(int(1, 40)), h = c.draw(int(1, 40));
	var colors = c.draw(array(int(0, 0x7FFFFFFF), 1, 4)), seed = c.draw(int(1, 0x7FFFFFFF)), noisy = c.draw(bool());
	var rgba = Bytes.alloc(w * h * 4), x = seed;
	for (i in 0...w * h) {
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		rgba.setInt32(i * 4, noisy && x & 3 == 0 ? x : colors[Std.int(i / 7) % colors.length]);
	}
	{width: w, height: h, rgba: rgba};
}
