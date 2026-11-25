package image;

import haxe.io.Bytes;
import helder.image.*;
import helder.test.Gen;
import helder.test.Test;

// tests/image/Fuzz.hx's mutations as a property (natively and on
// wasm32-wasi, in the test lane): a seed image of tests/image mutated,
// decoded by Image.decode and AnimatedImage.decode (a JPEG also at 1/8)
// under a small ImageLimits budget, ends in a decode or an ImageError, each
// within a second, no read past the end swallowed. A failure shrinks to
// the fewest, simplest mutations of the first seed that fails. The fuzz
// lane (image-fuzz) still runs Fuzz.hx: a hang it stops with a watchdog,
// a native fault it keeps the input of, the peak memory it measures, none
// of which a property in the test's own process can.
function tests() {
	var seeds = new Map<String, Bytes>();
	for (dir in ["png", "jpeg", "gif", "webp", "apng"])
		for (f in sys.FileSystem.readDirectory('tests/image/$dir')) {
			if (StringTools.endsWith(f, ".rgba") || StringTools.endsWith(f, ".json")) continue;
			var b = sys.io.File.getBytes('tests/image/$dir/$f');
			if (b.length <= 16384) seeds.set('$dir/$f', b);
		}
	var names = [for (k in seeds.keys()) k];
	names.sort(Reflect.compare);
	var at = int(0, 0x7FFFFFFF);
	var mutation:Gen<Mutation> = oneOf([
		c -> Flip(c.draw(at), c.draw(int(0, 7))),
		c -> Set(c.draw(at), c.draw(pick([0, 0xFF, 0x7F, 0x80, 1]))),
		c -> Huge(c.draw(int(0, 63)), c.draw(bool())),
		c -> Cut(c.draw(at)),
		c -> Repeat(c.draw(at), c.draw(int(1, 64))),
		c -> Splice(c.draw(at), c.draw(pick(names)), c.draw(at), c.draw(int(1, 256))),
		c -> Zero(c.draw(at), c.draw(int(1, 32)))
	]);
	var input:Gen<{seed:String, mutations:Array<Mutation>}> = c -> {seed: c.draw(pick(names)), mutations: c.draw(array(mutation, 1, 8))};

	test("a mutated image: decoded, or an ImageError", () -> {
		var limits = [ImageLimits.maxPixels, ImageLimits.maxSide, ImageLimits.maxMemory];
		ImageLimits.maxPixels = 4194304;
		ImageLimits.maxSide = 8192;
		ImageLimits.maxMemory = 96 * 1048576.0;
		property(input, i -> {
			var b = seeds[i.seed].sub(0, seeds[i.seed].length);
			for (m in i.mutations) b = mutate(b, m, seeds);
			var jpeg = b.length > 2 && b.get(0) == 0xFF && b.get(1) == 0xD8;
			for (pass in 0...(jpeg ? 3 : 2)) {
				var t0 = haxe.Timer.stamp(), before = ByteReader.refused, decoded = true;
				try {
					if (pass == 2) JpegDecoder.decode(b, null, 8) else if (pass == 1) AnimatedImage.decode(b) else Image.decode(b);
				} catch (e:ImageError) {
					decoded = false;
				}
				assert(!decoded || ByteReader.refused == before, 'pass $pass: a read past the end refused, and still decoded');
				assert(haxe.Timer.stamp() - t0 < 1, 'pass $pass: over 1 s');
			}
		}, {cases: 150, seconds: 10});
		ImageLimits.maxPixels = Std.int(limits[0]);
		ImageLimits.maxSide = Std.int(limits[1]);
		ImageLimits.maxMemory = limits[2];
	});
}

// (Fuzz.mutate's kinds, each one's place a choice: shrinking to the start)
private enum Mutation {
	Flip(at:Int, bit:Int);
	Set(at:Int, value:Int);
	Huge(at:Int, wide:Bool);
	Cut(at:Int);
	Repeat(at:Int, n:Int);
	Splice(at:Int, from:String, start:Int, n:Int);
	Zero(at:Int, n:Int);
}

private function mutate(b:Bytes, m:Mutation, seeds:Map<String, Bytes>):Bytes {
	var len = b.length;
	if (len == 0) return b;
	return switch m {
		case Flip(at, bit):
			b.set(at % len, b.get(at % len) ^ (1 << bit));
			b;
		case Set(at, v):
			b.set(at % len, v);
			b;
		case Huge(at, wide):
			for (i in 0...(wide ? 4 : 2)) if (at + i < len) b.set(at + i, 0xFF);
			b;
		case Cut(at): b.sub(0, at % len);
		case Repeat(at, n):
			var p = at % len, n = Std.int(Math.min(n, len - p)), o = new haxe.io.BytesBuffer();
			o.add(b.sub(0, p + n));
			o.add(b.sub(p, len - p));
			o.getBytes();
		case Splice(at, from, start, n):
			var other = seeds[from], p = at % len, q = start % other.length;
			b.blit(p, other, q, Std.int(Math.min(Math.min(len - p, other.length - q), n)));
			b;
		case Zero(at, n):
			var p = at % len;
			b.fill(p, Std.int(Math.min(len - p, n)), 0);
			b;
	}
}
