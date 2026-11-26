package helder.image;

import haxe.io.Bytes;

// RGBA8 pixels as a PNG file (8-bit RGBA, not interlaced): each row
// filtered as libpng's heuristic picks (the filter of the smallest sum of
// its bytes as signed), then deflated (Deflate: the fixed Huffman codes and
// LZ77 matches found by a hash of three bytes, a short chain): a flat
// colour's rows down to a few bytes, an icon's to a fraction. For what is
// written once, by a build (helder's app icons and splash images), not a
// frame's: no zlib, pure Haxe.
class PngEncoder {
	// (opaque: written as 8-bit RGB, the alpha dropped: no alpha channel, as
	// the App Store wants its screenshots)
	// (quick: each row Up's filter, deflated quickly: a frame's picture, written
	// as a program runs, a few times the bytes)
	public static function encode(rgba:Bytes, width:Int, height:Int, opaque = false, quick = false):Bytes {
		if (rgba.length != width * height * 4) throw 'PngEncoder: ${rgba.length} bytes are not ${width}x$height RGBA';
		if (opaque) {
			var rgb = Bytes.alloc(width * height * 3);
			for (p in 0...width * height) {
				rgb.set(3 * p, rgba.get(4 * p));
				rgb.set(3 * p + 1, rgba.get(4 * p + 1));
				rgb.set(3 * p + 2, rgba.get(4 * p + 2));
			}
			rgba = rgb;
		}
		var bpp = opaque ? 3 : 4;
		var stride = width * bpp;
		var raw = Bytes.alloc((stride + 1) * height);
		var trial = [for (_ in 0...5) Bytes.alloc(stride)];
		if (quick) for (y in 0...height) {
			var row = y * stride, at = y * (stride + 1);
			raw.set(at, y > 0 ? 2 : 0);
			if (y == 0) raw.blit(at + 1, rgba, row, stride) else for (i in 0...stride)
				raw.set(at + 1 + i, rgba.get(row + i) - rgba.get(row - stride + i));
		} else for (y in 0...height) {
			var row = y * stride, up = (y - 1) * stride;
			var best = 0, bestSum = -1;
			for (f in 0...5) {
				var t = trial[f], sum = 0;
				for (i in 0...stride) {
					var x = rgba.get(row + i);
					var a = i >= bpp ? rgba.get(row + i - bpp) : 0, b = y > 0 ? rgba.get(up + i) : 0, c = i >= bpp && y > 0 ? rgba.get(up + i - bpp) : 0;
					var v:Int = switch f {
						case 0: x;
						case 1: x - a;
						case 2: x - b;
						case 3: x - ((a + b) >> 1);
						case _:
							var p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
							x - (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
					}
					v &= 0xFF;
					t.set(i, v);
					sum += v < 128 ? v : 256 - v;
				}
				if (bestSum < 0 || sum < bestSum) {
					best = f;
					bestSum = sum;
				}
			}
			raw.set(y * (stride + 1), best);
			raw.blit(y * (stride + 1) + 1, trial[best], 0, stride);
		}
		var o = new haxe.io.BytesOutput();
		o.bigEndian = true;
		for (b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
			o.writeByte(b);
		var ihdr = Bytes.alloc(13);
		ihdr.set(0, width >>> 24);
		ihdr.set(1, width >> 16);
		ihdr.set(2, width >> 8);
		ihdr.set(3, width);
		ihdr.set(4, height >>> 24);
		ihdr.set(5, height >> 16);
		ihdr.set(6, height >> 8);
		ihdr.set(7, height);
		ihdr.set(8, 8);
		ihdr.set(9, opaque ? 2 : 6);
		chunk(o, "IHDR", ihdr);
		chunk(o, "IDAT", Deflate.zlib(raw, quick));
		chunk(o, "IEND", Bytes.alloc(0));
		return o.getBytes();
	}

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;

	static function chunk(o:haxe.io.BytesOutput, type:String, data:Bytes) {
		o.writeInt32(data.length);
		var td = Bytes.alloc(4 + data.length);
		td.blit(0, Bytes.ofString(type), 0, 4);
		td.blit(4, data, 0, data.length);
		o.writeFullBytes(td, 0, td.length);
		o.writeInt32(haxe.crypto.Crc32.make(td));
	}
}
