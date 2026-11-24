package helder.gfx.soft;

import haxe.io.Bytes;
import hxmc.I64;
import hxmc.unsafe.BytesPtr;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A texture of the CPU back end: a record outside the collector's heap (its
// size, levels, layers, how its texels are stored) and its texels, every
// level and layer in one allocation, so that tiles shade into it and sample
// it from any thread while a collection runs. Three kinds of texel: 4
// bytes of RGBA8 (RGBA8, RGBA8Srgb, R8 and RG8 widened, BC1, BC3 and ASTC
// decoded when written), 4 floats (RGBA16F, rounded to halves when
// written, RGBA32F) and 1 float (R32F, the depth formats; Depth16 rounded
// to its 16 bits when written). A multisampled one has its samples' texels
// one after another, a pixel's together.
@:hxmc.unsafe(gc)
class SoftTexture {
	public static inline var DATA = 0;
	public static inline var WIDTH = 8;
	public static inline var HEIGHT = 12;
	public static inline var LEVELS = 16;
	public static inline var LAYERS = 20;
	public static inline var KIND = 24;
	public static inline var SRGB = 28;
	public static inline var SAMPLES = 32;
	public static inline var FORMAT = 36;
	// (the sRGB table: Formats.srgb)
	public static inline var TABLE = 40;
	// each level's offset (layer 0) and one layer's bytes at it, 16 levels
	public static inline var OFFSETS = 48;
	public static inline var STRIDES = 112;
	public static inline var SIZE = 176;

	public static inline var U8 = 0;
	public static inline var F4 = 1;
	public static inline var F1 = 2;

	public static function make(d:TextureDesc):Ptr {
		var format:TextureFormat = d.format == null ? RGBA8 : d.format;
		var w = d.width, h = d.height;
		var layers = d.cube == true ? 6 : d.layers != null ? d.layers : 1, samples = d.samples != null && d.samples > 1 ? d.samples : 1;
		var levels = d.mipLevels == null ? 1 : d.mipLevels;
		if (levels <= 0) {
			levels = 1;
			while ((w | h) >> levels != 0)
				levels++;
		}
		if (levels > 16) levels = 16;
		var kind = kindOf(format), size = texel(kind) * samples;
		var r:Ptr = LibC.malloc(SIZE);
		Mem.zero(r, SIZE);
		var off = 0;
		for (l in 0...levels) {
			var lw = w >> l > 0 ? w >> l : 1, lh = h >> l > 0 ? h >> l : 1;
			Mem.setI32(r, OFFSETS + 4 * l, off);
			Mem.setI32(r, STRIDES + 4 * l, lw * lh * size);
			off += lw * lh * size * layers;
		}
		var data:Ptr = LibC.malloc(((off > 0 ? off : 16) : I64));
		if (data.isNull()) throw "helder.gfx: out of memory for a texture of " + off + " bytes";
		Mem.zero(data, (off : I64));
		Mem.setPtr(r, DATA, data);
		Mem.setI32(r, WIDTH, w);
		Mem.setI32(r, HEIGHT, h);
		Mem.setI32(r, LEVELS, levels);
		Mem.setI32(r, LAYERS, layers);
		Mem.setI32(r, KIND, kind);
		Mem.setI32(r, SRGB, format == RGBA8Srgb ? 1 : 0);
		Mem.setI32(r, SAMPLES, samples);
		Mem.setI32(r, FORMAT, cast format);
		Mem.setPtr(r, TABLE, Formats.srgb());
		// (an RGBA8 texture's alpha 1, as a GPU's new texture reads for R8 and RG8: written whole anyway)
		return r;
	}

	public static function free(r:Ptr) {
		LibC.free(Mem.getPtr(r, DATA));
		LibC.free(r);
	}

	public static function kindOf(f:TextureFormat):Int
		return switch f {
			case RGBA16F | RGBA32F: F4;
			case R32F | Depth16 | Depth32F: F1;
			case _: U8;
		}

	public static inline function texel(kind:Int):Int
		return kind == F4 ? 16 : 4;

	public static inline function width(r:Ptr, level:Int):Int {
		var w = Mem.getI32(r, WIDTH) >> level;
		return w > 0 ? w : 1;
	}

	public static inline function height(r:Ptr, level:Int):Int {
		var h = Mem.getI32(r, HEIGHT) >> level;
		return h > 0 ? h : 1;
	}

	// where a level's layer starts
	public static inline function at(r:Ptr, level:Int, layer:Int):Ptr
		return Mem.getPtr(r, DATA).add(Mem.getI32(r, OFFSETS + 4 * level) + layer * Mem.getI32(r, STRIDES + 4 * level));

	// texels of the texture's format (rows top to bottom, w x h at x, y) into a level's layer
	public static function write(r:Ptr, src:Bytes, pos:Int, x:Int, y:Int, w:Int, h:Int, level:Int, layer:Int) {
		var format:TextureFormat = cast Mem.getI32(r, FORMAT), lw = width(r, level), base = at(r, level, layer);
		switch format {
			case BC1 | BC3 | ASTC4x4:
				var px = new haxe.ds.Vector<Int>(64), bw = (w + 3) >> 2, bh = (h + 3) >> 2, size = format == BC1 ? 8 : 16, lh = height(r, level);
				for (by in 0...bh)
					for (bx in 0...bw) {
						var b = pos + (by * bw + bx) * size;
						try
							switch format {
								case BC1: helder.image.BlockCompress.Decoder.bc1(src, b, px, false);
								case BC3:
									helder.image.BlockCompress.Decoder.bc1(src, b + 8, px, true);
									helder.image.BlockCompress.Decoder.bc3Alpha(src, b, px);
								case _: helder.image.BlockCompress.Decoder.astc(src, b, px);
							}
						catch (_:Dynamic)
							// (ASTC's other kinds of block, which helder's encoder never writes: magenta)
							for (k in 0...16) {
								px[4 * k] = 255;
								px[4 * k + 1] = 0;
								px[4 * k + 2] = 255;
								px[4 * k + 3] = 255;
							}
						for (k in 0...16) {
							var tx = x + bx * 4 + (k & 3), ty = y + by * 4 + (k >> 2);
							if (tx >= lw || ty >= lh) continue;
							var p = base.add(4 * (ty * lw + tx));
							Mem.setI32(p, 0, px[4 * k] | (px[4 * k + 1] << 8) | (px[4 * k + 2] << 16) | (px[4 * k + 3] << 24));
						}
					}
			case RGBA8 | RGBA8Srgb:
				for (j in 0...h)
					LibC.memcpy(base.add(4 * ((y + j) * lw + x)), BytesPtr.of(src, pos + 4 * w * j, 4 * w), (4 * w : I64));
			case R8 | RG8:
				var n = format == R8 ? 1 : 2;
				for (j in 0...h)
					for (i in 0...w) {
						var s = pos + n * (j * w + i), g = n == 2 ? src.get(s + 1) : 0;
						Mem.setI32(base, 4 * ((y + j) * lw + x + i), src.get(s) | (g << 8) | (255 << 24));
					}
			case RGBA16F:
				for (j in 0...h)
					for (i in 0...w)
						for (c in 0...4)
							Mem.setF32(base, 16 * ((y + j) * lw + x + i) + 4 * c, Formats.half(src.getUInt16(pos + 8 * (j * w + i) + 2 * c)));
			case RGBA32F:
				for (j in 0...h)
					LibC.memcpy(base.add(16 * ((y + j) * lw + x)), BytesPtr.of(src, pos + 16 * w * j, 16 * w), (16 * w : I64));
			case R32F:
				for (j in 0...h)
					LibC.memcpy(base.add(4 * ((y + j) * lw + x)), BytesPtr.of(src, pos + 4 * w * j, 4 * w), (4 * w : I64));
			case _:
				throw "helder.gfx: writeTexture: a depth texture is written by passes";
		}
	}

	// each level after the first from the one before: 2x2 texels averaged
	// (the last row or column of an odd size taken twice), sRGB in linear values
	public static function mips(r:Ptr) {
		var levels = Mem.getI32(r, LEVELS), layers = Mem.getI32(r, LAYERS), kind = Mem.getI32(r, KIND), srgb = Mem.getI32(r, SRGB) != 0;
		var t = Mem.getPtr(r, TABLE);
		for (l in 1...levels)
			for (layer in 0...layers) {
				var src = at(r, l - 1, layer), dst = at(r, l, layer);
				var sw = width(r, l - 1), sh = height(r, l - 1), dw = width(r, l), dh = height(r, l);
				for (y in 0...dh)
					for (x in 0...dw) {
						var x0 = 2 * x, y0 = 2 * y, x1 = x0 + 1 < sw ? x0 + 1 : x0, y1 = y0 + 1 < sh ? y0 + 1 : y0;
						if (kind == U8) {
							var out = 0;
							for (c in 0...4) {
								inline function v(px:Int, py:Int):Float {
									var b = Mem.getU8(src, 4 * (py * sw + px) + c);
									return srgb && c < 3 ? (Mem.getF32(t, 4 * b) : Float) : b / 255;
								}
								var avg = (v(x0, y0) + v(x1, y0) + v(x0, y1) + v(x1, y1)) * 0.25;
								var code = srgb && c < 3 ? Formats.srgbCode(t, avg) : Std.int(avg * 255 + 0.5);
								out |= code << (8 * c);
							}
							Mem.setI32(dst, 4 * (y * dw + x), out);
						} else {
							var n = kind == F4 ? 4 : 1;
							for (c in 0...n) {
								inline function v(px:Int, py:Int):Float
									return Mem.getF32(src, 4 * n * (py * sw + px) + 4 * c);
								var avg = (v(x0, y0) + v(x1, y0) + v(x0, y1) + v(x1, y1)) * 0.25;
								if (Mem.getI32(r, FORMAT) == (cast TextureFormat.RGBA16F : Int)) avg = Formats.roundHalf(avg);
								Mem.setF32(dst, 4 * n * (y * dw + x) + 4 * c, avg);
							}
						}
					}
			}
	}

	// a level's layer as RGBA8, rows top to bottom (readPixels; floats clamped to 0..1)
	public static function read(r:Ptr, level:Int, layer:Int, dst:Bytes, pos:Int) {
		var w = width(r, level), h = height(r, level), kind = Mem.getI32(r, KIND), src = at(r, level, layer);
		var samples = Mem.getI32(r, SAMPLES);
		if (kind == U8 && samples == 1) {
			BytesPtr.copyIn(dst, pos, src, 4 * w * h);
			return;
		}
		for (i in 0...w * h) {
			if (kind == U8) {
				dst.setInt32(pos + 4 * i, Mem.getI32(src, 4 * samples * i));
				continue;
			}
			var n = kind == F4 ? 4 : 1;
			for (c in 0...4) {
				var v:Float = c < n ? Mem.getF32(src, 4 * n * samples * i + 4 * c) : c == 3 ? 1 : 0;
				dst.set(pos + 4 * i + c, Std.int(Math.min(Math.max(v, 0), 1) * 255 + 0.5));
			}
		}
	}
}
