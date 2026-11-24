package helder.gfx.soft;

import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import hxmc.unsafe.Atomic;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A pass's tiles shaded (tile: a GC-free callback, Parallel's): each 64x64
// tile its triangles in the order they were drawn, a 2x2 quad at a time.
// A pixel is covered when its centre is inside the triangle's three edges
// (fixed point with 8 bits under the pixel, the edge functions exact in
// doubles; on an edge, only a top or left one's: GPUs' top-left rule); 4
// samples a pixel at the standard positions in a multisampled target, the
// pixel shaded once at its centre and written to the samples covered and
// passing the depth test. The depth test runs before the fragment stage
// (its depth written after it, the lanes it discarded left out), the
// varyings are interpolated perspective-correct (their planes over w, then
// divided by 1/w's plane), the colour blended as GPUs blend into the
// target's format: unorm values clamped and rounded to the nearest, sRGB
// decoded to blend and encoded to store, half floats rounded to halves.
// Everything read and written is outside the collector's heap (the pass's
// records, the targets, the textures, the uniform blocks' copies).
@:hxmc.unsafe(gc)
class Raster {
	public static inline var TILE = 64;

	// the pass
	public static inline var COLOR = 0;
	public static inline var DEPTH = 8;
	public static inline var W = 16;
	public static inline var H = 20;
	public static inline var TILES_X = 24;
	public static inline var TILES_Y = 28;
	public static inline var BINS = 32;
	public static inline var KIND = 40;
	public static inline var FORMAT = 44;
	public static inline var SAMPLES = 48;
	public static inline var DEPTH16 = 52;
	public static inline var TABLE = 56;
	public static inline var PASS = 64;

	// a tile's triangles: chunks of 63 (the first, the last, how many in the last)
	public static inline var FIRST = 0;
	public static inline var LAST = 8;
	public static inline var COUNT = 16;
	public static inline var BIN = 24;
	public static inline var CHUNK = 512;
	public static inline var ENTRIES = 63;

	// a triangle: its draw, its edges (A, B, C each, C biased by the fill
	// rule: covered where A x + B y + C >= 0 in fixed point), its pixels'
	// bounds (x1, y1 past them), the planes of z, 1/w and each varying over
	// w (a, b, c: c + a dx + b dy from the bounds' first pixel)
	public static inline var T_DRAW = 0;
	public static inline var T_EDGES = 8;
	public static inline var T_X0 = 80;
	public static inline var T_Y0 = 84;
	public static inline var T_X1 = 88;
	public static inline var T_Y1 = 92;
	public static inline var T_Z = 96;
	public static inline var T_W = 108;
	public static inline var T_V = 120;

	// a draw: its fragment stage's entry, its varyings' components, its
	// blend, depth test and write, its query's cell, then its bindings as
	// the stage's context has them (Abi.UNIFORMS on)
	public static inline var D_FS = 0;
	public static inline var D_N = 8;
	public static inline var D_BLEND = 12;
	public static inline var D_COMPARE = 16;
	public static inline var D_WRITE = 20;
	public static inline var D_QUERY = 24;
	public static inline var D_BINDINGS = 32;
	public static inline var DRAW = 32 + 256;

	// (the stage's context: Abi, then its input's and output's lanes)
	static inline var C_IN = 320;
	static inline var C_OUT = 320 + 64 + 16 * Abi.MAX_VARYINGS;
	static inline var C_SIZE = C_OUT + 64;

	@:hxmc.callback @:hxmc.unsafe public static function tile(pass:Ptr, i:Int):Int {
		var tilesX = Mem.getI32(pass, TILES_X), w = Mem.getI32(pass, W), h = Mem.getI32(pass, H);
		var tx = i % tilesX, ty = Std.int(i / tilesX);
		var x0 = tx * TILE, y0 = ty * TILE, x1 = x0 + TILE < w ? x0 + TILE : w, y1 = y0 + TILE < h ? y0 + TILE : h;
		var bin = Mem.getPtr(pass, BINS).add(BIN * i);
		var chunk = Mem.getPtr(bin, FIRST), last = Mem.getPtr(bin, LAST), count = Mem.getI32(bin, COUNT);
		if (chunk.isNull()) return 0;
		var c = Mem.stack(C_SIZE);
		Mem.setPtr(c, Abi.IN, c.add(C_IN));
		Mem.setPtr(c, Abi.OUT, c.add(C_OUT));
		var draw = Ptr.nil();
		while (!chunk.isNull()) {
			var n = chunk == last ? count : ENTRIES;
			for (k in 0...n) {
				var t = Mem.getPtr(chunk, 8 + 8 * k), d = Mem.getPtr(t, T_DRAW);
				if (d != draw) {
					draw = d;
					LibC.memcpy(c.add(Abi.UNIFORMS), d.add(D_BINDINGS), 256);
				}
				if (Mem.getI32(pass, SAMPLES) > 1) multi(pass, c, t, d, x0, y0, x1, y1) else single(pass, c, t, d, x0, y0, x1, y1);
			}
			chunk = Mem.getPtr(chunk, 0);
		}
		return 0;
	}

	// (a triangle's quads in the tile, one sample a pixel)
	static function single(pass:Ptr, c:Ptr, t:Ptr, d:Ptr, x0:Int, y0:Int, x1:Int, y1:Int) {
		var bx0 = Mem.getI32(t, T_X0), by0 = Mem.getI32(t, T_Y0);
		var qx0 = bx0 > x0 ? bx0 : x0, qy0 = by0 > y0 ? by0 : y0;
		var qx1 = Mem.getI32(t, T_X1), qy1 = Mem.getI32(t, T_Y1);
		if (qx1 > x1) qx1 = x1;
		if (qy1 > y1) qy1 = y1;
		if (qx0 >= qx1 || qy0 >= qy1) return;
		var w = Mem.getI32(pass, W), h = Mem.getI32(pass, H);
		var a0:Float = Mem.getF64(t, T_EDGES), b0:Float = Mem.getF64(t, T_EDGES + 8), c0:Float = Mem.getF64(t, T_EDGES + 16);
		var a1:Float = Mem.getF64(t, T_EDGES + 24), b1:Float = Mem.getF64(t, T_EDGES + 32), c1:Float = Mem.getF64(t, T_EDGES + 40);
		var a2:Float = Mem.getF64(t, T_EDGES + 48), b2:Float = Mem.getF64(t, T_EDGES + 56), c2:Float = Mem.getF64(t, T_EDGES + 64);
		var za = F32x4.splat(Mem.getF32(t, T_Z)), zb = F32x4.splat(Mem.getF32(t, T_Z + 4)), zc = F32x4.splat(Mem.getF32(t, T_Z + 8));
		var wa = F32x4.splat(Mem.getF32(t, T_W)), wb = F32x4.splat(Mem.getF32(t, T_W + 4)), wc = F32x4.splat(Mem.getF32(t, T_W + 8));
		var fs = Mem.getPtr(d, D_FS), n = Mem.getI32(d, D_N), blend = Mem.getI32(d, D_BLEND), compare = Mem.getI32(d, D_COMPARE);
		var write = Mem.getI32(d, D_WRITE) != 0, query = Mem.getPtr(d, D_QUERY);
		var depth = Mem.getPtr(pass, DEPTH), color = Mem.getPtr(pass, COLOR), depth16 = Mem.getI32(pass, DEPTH16) != 0;
		var tested = !depth.isNull() && (compare != 7 || write);
		var input = c.add(C_IN), output = c.add(C_OUT);
		var dx = F32x4.make(0, 1, 0, 1), dy = F32x4.make(0, 0, 1, 1);
		var px = F32x4.make(0.5, 1.5, 0.5, 1.5), py = F32x4.make(0.5, 0.5, 1.5, 1.5);
		var qy = qy0 & ~1;
		while (qy < qy1) {
			var Y = 256.0 * qy + 128;
			var rows = qy + 1 < h ? 15 : 3;
			var qx = qx0 & ~1;
			var e0 = a0 * (256.0 * qx + 128) + b0 * Y + c0, e1 = a1 * (256.0 * qx + 128) + b1 * Y + c1, e2 = a2 * (256.0 * qx + 128) + b2 * Y + c2;
			while (qx < qx1) {
				var m = (qx + 1 < w ? 15 : 5) & rows;
				m &= cover(e0, a0, b0) & cover(e1, a1, b1) & cover(e2, a2, b2);
				e0 += 512 * a0;
				e1 += 512 * a1;
				e2 += 512 * a2;
				if (m == 0) {
					qx += 2;
					continue;
				}
				var lx = F32x4.splat(qx - bx0) + dx, ly = F32x4.splat(qy - by0) + dy;
				var z = (zc + za * lx + zb * ly).clamp(F32x4.zero(), F32x4.splat(1));
				if (depth16) z = (z * F32x4.splat(65535)).round() / F32x4.splat(65535);
				var at = qy * w + qx;
				var old = F32x4.zero();
				if (tested) {
					old = F32x4.make(Mem.getF32(depth, 4 * at), m & 2 != 0 ? Mem.getF32(depth, 4 * at + 4) : 0, m & 4 != 0 ? Mem.getF32(depth, 4 * (at + w)) : 0,
						m & 8 != 0 ? Mem.getF32(depth, 4 * (at + w) + 4) : 0);
					m &= passes(compare, z, old);
					if (m == 0) {
						qx += 2;
						continue;
					}
				}
				var iw = wc + wa * lx + wb * ly, r = F32x4.splat(1) / iw;
				(F32x4.splat(qx) + px).storePtr(input, 0);
				(F32x4.splat(qy) + py).storePtr(input, 16);
				z.storePtr(input, 32);
				iw.storePtr(input, 48);
				var v = t.add(T_V);
				for (k in 0...n) {
					var p = v.add(12 * k);
					((F32x4.splat(Mem.getF32(p, 8)) + F32x4.splat(Mem.getF32(p, 0)) * lx + F32x4.splat(Mem.getF32(p, 4)) * ly) * r).storePtr(input, 64 + 16 * k);
				}
				Mem.setI32(c, Abi.MASK, m);
				m &= Fragment.call(fs, c);
				if (m == 0) {
					qx += 2;
					continue;
				}
				if (!query.isNull()) Atomic.store32(query, 1);
				if (tested && write) {
					var zs = F32x4.select(I32x4.make(-(m & 1), -((m >> 1) & 1), -((m >> 2) & 1), -((m >> 3) & 1)), z, old);
					Mem.setF32(depth, 4 * at, zs.get(0));
					if (m & 2 != 0) Mem.setF32(depth, 4 * at + 4, zs.get(1));
					if (m & 4 != 0) Mem.setF32(depth, 4 * (at + w), zs.get(2));
					if (m & 8 != 0) Mem.setF32(depth, 4 * (at + w) + 4, zs.get(3));
				}
				Blender.quad(pass, color, at, w, m, blend, output);
				qx += 2;
			}
			qy += 2;
		}
	}

	// the lanes of a quad inside an edge: its pixels' centres, 256 apart
	static inline function cover(e:Float, a:Float, b:Float):Int
		return (e >= 0 ? 1 : 0) | (e + 256 * a >= 0 ? 2 : 0) | (e + 256 * b >= 0 ? 4 : 0) | (e + 256 * (a + b) >= 0 ? 8 : 0);

	static inline function passes(compare:Int, z:F32x4, old:F32x4):Int
		return switch compare {
			case 0: 0;
			case 1: z.lt(old).bitmask();
			case 2: z.eq(old).bitmask();
			case 3: z.le(old).bitmask();
			case 4: z.gt(old).bitmask();
			case 5: z.ne(old).bitmask();
			case 6: z.ge(old).bitmask();
			case _: 15;
		}

	static inline function passes1(compare:Int, z:Float, old:Float):Bool
		return switch compare {
			case 0: false;
			case 1: z < old;
			case 2: z == old;
			case 3: z <= old;
			case 4: z > old;
			case 5: z != old;
			case 6: z >= old;
			case _: true;
		}

	// (the standard 4 sample positions, in 256ths of a pixel from its top left)
	static inline function sampleX(s:Int):Int
		return s == 0 ? 96 : s == 1 ? 224 : s == 2 ? 32 : 160;

	static inline function sampleY(s:Int):Int
		return s == 0 ? 32 : s == 1 ? 96 : s == 2 ? 160 : 224;

	// (a triangle's quads in the tile, 4 samples a pixel)
	static function multi(pass:Ptr, c:Ptr, t:Ptr, d:Ptr, x0:Int, y0:Int, x1:Int, y1:Int) {
		var bx0 = Mem.getI32(t, T_X0), by0 = Mem.getI32(t, T_Y0);
		// (a sample's pixel may be past the centres' bounds by one)
		var qx0 = bx0 - 1 > x0 ? bx0 - 1 : x0, qy0 = by0 - 1 > y0 ? by0 - 1 : y0;
		var qx1 = Mem.getI32(t, T_X1) + 1, qy1 = Mem.getI32(t, T_Y1) + 1;
		if (qx1 > x1) qx1 = x1;
		if (qy1 > y1) qy1 = y1;
		if (qx0 >= qx1 || qy0 >= qy1) return;
		var w = Mem.getI32(pass, W), h = Mem.getI32(pass, H);
		var a0:Float = Mem.getF64(t, T_EDGES), b0:Float = Mem.getF64(t, T_EDGES + 8), c0:Float = Mem.getF64(t, T_EDGES + 16);
		var a1:Float = Mem.getF64(t, T_EDGES + 24), b1:Float = Mem.getF64(t, T_EDGES + 32), c1:Float = Mem.getF64(t, T_EDGES + 40);
		var a2:Float = Mem.getF64(t, T_EDGES + 48), b2:Float = Mem.getF64(t, T_EDGES + 56), c2:Float = Mem.getF64(t, T_EDGES + 64);
		var za:Float = Mem.getF32(t, T_Z), zb:Float = Mem.getF32(t, T_Z + 4), zc:Float = Mem.getF32(t, T_Z + 8);
		var wa = F32x4.splat(Mem.getF32(t, T_W)), wb = F32x4.splat(Mem.getF32(t, T_W + 4)), wc = F32x4.splat(Mem.getF32(t, T_W + 8));
		var fs = Mem.getPtr(d, D_FS), n = Mem.getI32(d, D_N), blend = Mem.getI32(d, D_BLEND), compare = Mem.getI32(d, D_COMPARE);
		var write = Mem.getI32(d, D_WRITE) != 0, query = Mem.getPtr(d, D_QUERY);
		var depth = Mem.getPtr(pass, DEPTH), color = Mem.getPtr(pass, COLOR), depth16 = Mem.getI32(pass, DEPTH16) != 0;
		var tested = !depth.isNull() && (compare != 7 || write);
		var input = c.add(C_IN), output = c.add(C_OUT);
		var dx = F32x4.make(0, 1, 0, 1), dy = F32x4.make(0, 0, 1, 1);
		var px = F32x4.make(0.5, 1.5, 0.5, 1.5), py = F32x4.make(0.5, 0.5, 1.5, 1.5);
		var qy = qy0 & ~1;
		while (qy < qy1) {
			var qx = qx0 & ~1;
			while (qx < qx1) {
				// (samples: lane l's sample s at bit 4 l + s)
				var cov = 0, pix = 0;
				for (l in 0...4) {
					var x = qx + (l & 1), y = qy + (l >> 1);
					if (x >= w || y >= h) continue;
					for (s in 0...4) {
						var X = 256.0 * x + sampleX(s), Y = 256.0 * y + sampleY(s);
						if (a0 * X + b0 * Y + c0 >= 0 && a1 * X + b1 * Y + c1 >= 0 && a2 * X + b2 * Y + c2 >= 0) {
							var bit = 4 * l + s;
							if (tested) {
								var z = zc + za * (x - bx0 + sampleX(s) / 256 - 0.5) + zb * (y - by0 + sampleY(s) / 256 - 0.5);
								z = z < 0 ? 0 : z > 1 ? 1 : z;
								if (depth16) z = Math.fround(z * 65535) / 65535;
								if (!passes1(compare, z, Mem.getF32(depth, 4 * (4 * (y * w + x) + s)))) continue;
							}
							cov |= 1 << bit;
							pix |= 1 << l;
						}
					}
				}
				if (pix == 0) {
					qx += 2;
					continue;
				}
				var lx = F32x4.splat(qx - bx0) + dx, ly = F32x4.splat(qy - by0) + dy;
				var z = (F32x4.splat(zc) + F32x4.splat(za) * lx + F32x4.splat(zb) * ly).clamp(F32x4.zero(), F32x4.splat(1));
				var iw = wc + wa * lx + wb * ly, r = F32x4.splat(1) / iw;
				(F32x4.splat(qx) + px).storePtr(input, 0);
				(F32x4.splat(qy) + py).storePtr(input, 16);
				z.storePtr(input, 32);
				iw.storePtr(input, 48);
				var v = t.add(T_V);
				for (k in 0...n) {
					var p = v.add(12 * k);
					((F32x4.splat(Mem.getF32(p, 8)) + F32x4.splat(Mem.getF32(p, 0)) * lx + F32x4.splat(Mem.getF32(p, 4)) * ly) * r).storePtr(input, 64 + 16 * k);
				}
				Mem.setI32(c, Abi.MASK, pix);
				pix &= Fragment.call(fs, c);
				if (pix == 0) {
					qx += 2;
					continue;
				}
				if (!query.isNull()) Atomic.store32(query, 1);
				for (l in 0...4) {
					if (pix & (1 << l) == 0) continue;
					var x = qx + (l & 1), y = qy + (l >> 1);
					for (s in 0...4) {
						if (cov & (1 << (4 * l + s)) == 0) continue;
						var at = 4 * (y * w + x) + s;
						if (tested && write) {
							var z = zc + za * (x - bx0 + sampleX(s) / 256 - 0.5) + zb * (y - by0 + sampleY(s) / 256 - 0.5);
							z = z < 0 ? 0 : z > 1 ? 1 : z;
							if (depth16) z = Math.fround(z * 65535) / 65535;
							Mem.setF32(depth, 4 * at, z);
						}
						Blender.one(pass, color, at, blend, Mem.getF32(output, 4 * l), Mem.getF32(output, 16 + 4 * l), Mem.getF32(output, 32 + 4 * l),
							Mem.getF32(output, 48 + 4 * l));
					}
				}
				qx += 2;
			}
			qy += 2;
		}
	}
}

// (a stage's entry by its address, in the caller's state: a tile's safe region)
@:hxmc.c @:hxmc.fast extern class Fragment {
	@:hxmc.indirect static function call(f:Ptr, c:Ptr):Int;
}
