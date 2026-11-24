package helder.gfx.soft;

import helder.gfx.shader.TextureCube;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A shader's sample() on the CPU back end: a texture bound with its
// sampler (a binding: the texture's record, the filter, the mip filter, the
// wrap mode), read as GPUs read it. In the fragment stage the mip level is
// the quad's: its lanes' footprint in texels, log2 of the larger of its
// two derivatives (lane 1 - lane 0 across, lane 2 - lane 0 down), one level
// for the four pixels as GPUs take it; nearest mips round it, linear ones
// blend the two levels about it. Bilinear filtering weighs the four texels
// about the point by its fraction in float (GPUs' 8 bits of sub-texel
// precision aside); a cube's face is the direction's largest component
// (TextureCube.faceOf, the CPU's own), filtered within it (clamped at its
// edges, not across to the next face). No anisotropy: helder's samplers
// have none. Reads only memory outside the collector's heap: tiles sample
// on any thread.
@:hxmc.unsafe(gc)
class Sample {
	public static inline var TEXTURE = 0;
	public static inline var FILTER = 8;
	public static inline var MIP = 12;
	public static inline var WRAP = 16;
	public static inline var SIZE = 24;

	// ---- scalar (a value every lane shares, the vertex stage's first level, the reference)

	public static function flatAt(b:Ptr, uv:Vec2, level:Float):Vec4
		return at(b, 0, uv.x, uv.y, level, Mem.getI32(b, WRAP));

	public static function arrayAt(b:Ptr, uv:Vec2, layer:Float, level:Float):Vec4
		return at(b, layerOf(b, layer), uv.x, uv.y, level, Mem.getI32(b, WRAP));

	public static function cubeAt(b:Ptr, dir:Vec3, level:Float):Vec4 {
		var f = TextureCube.faceOf(dir);
		return at(b, Std.int(f.x), f.y, f.z, level, 1);
	}

	// ---- lanes

	public static function flat(b:Ptr, uv:Lane2):Lane4 {
		var t = Mem.getPtr(b, TEXTURE);
		if (t.isNull()) return Lane4.zero();
		var lod = quadLod(uv.x, uv.y, Mem.getI32(t, SoftTexture.WIDTH), Mem.getI32(t, SoftTexture.HEIGHT)), wrap = Mem.getI32(b, WRAP);
		#if !helder.soft.exact
		return quad(b, t, 0, uv.x, uv.y, lod, wrap);
		#end
		return lanes(at(b, 0, uv.x.get(0), uv.y.get(0), lod, wrap), at(b, 0, uv.x.get(1), uv.y.get(1), lod, wrap), at(b, 0, uv.x.get(2), uv.y.get(2), lod, wrap),
			at(b, 0, uv.x.get(3), uv.y.get(3), lod, wrap));
	}

	public static function flatLevel(b:Ptr, uv:Lane2, level:Lane):Lane4 {
		var wrap = Mem.getI32(b, WRAP);
		#if !helder.soft.exact
		var l = level.get(0);
		if (level.get(1) == l && level.get(2) == l && level.get(3) == l) {
			var t = Mem.getPtr(b, TEXTURE);
			return t.isNull() ? Lane4.zero() : quad(b, t, 0, uv.x, uv.y, l, wrap);
		}
		#end
		return lanes(at(b, 0, uv.x.get(0), uv.y.get(0), level.get(0), wrap), at(b, 0, uv.x.get(1), uv.y.get(1), level.get(1), wrap),
			at(b, 0, uv.x.get(2), uv.y.get(2), level.get(2), wrap), at(b, 0, uv.x.get(3), uv.y.get(3), level.get(3), wrap));
	}

	public static function array(b:Ptr, uv:Lane2, layer:Lane):Lane4 {
		var t = Mem.getPtr(b, TEXTURE);
		if (t.isNull()) return Lane4.zero();
		var lod = quadLod(uv.x, uv.y, Mem.getI32(t, SoftTexture.WIDTH), Mem.getI32(t, SoftTexture.HEIGHT)), wrap = Mem.getI32(b, WRAP);
		return lanes(at(b, layerOf(b, layer.get(0)), uv.x.get(0), uv.y.get(0), lod, wrap), at(b, layerOf(b, layer.get(1)), uv.x.get(1), uv.y.get(1), lod, wrap),
			at(b, layerOf(b, layer.get(2)), uv.x.get(2), uv.y.get(2), lod, wrap), at(b, layerOf(b, layer.get(3)), uv.x.get(3), uv.y.get(3), lod, wrap));
	}

	public static function arrayLevel(b:Ptr, uv:Lane2, layer:Lane, level:Lane):Lane4 {
		var wrap = Mem.getI32(b, WRAP);
		return lanes(at(b, layerOf(b, layer.get(0)), uv.x.get(0), uv.y.get(0), level.get(0), wrap),
			at(b, layerOf(b, layer.get(1)), uv.x.get(1), uv.y.get(1), level.get(1), wrap), at(b, layerOf(b, layer.get(2)), uv.x.get(2), uv.y.get(2),
				level.get(2), wrap), at(b, layerOf(b, layer.get(3)), uv.x.get(3), uv.y.get(3), level.get(3), wrap));
	}

	public static function cube(b:Ptr, dir:Lane3):Lane4 {
		var t = Mem.getPtr(b, TEXTURE);
		if (t.isNull()) return Lane4.zero();
		// (the footprint on the unit cube: the direction over its largest component, half a face a unit)
		inline function onCube(i:Int):Vec3 {
			var x = dir.x.get(i), y = dir.y.get(i), z = dir.z.get(i);
			var m = Math.max(Math.abs(x), Math.max(Math.abs(y), Math.abs(z)));
			if (m == 0) m = 1;
			return new Vec3(x / m, y / m, z / m);
		}
		var c0 = onCube(0), c1 = onCube(1), c2 = onCube(2);
		var dx = c1 - c0, dy = c2 - c0;
		var rho = 0.5 * Mem.getI32(t, SoftTexture.WIDTH) * Math.max(Math.sqrt(dx.x * dx.x + dx.y * dx.y + dx.z * dx.z), Math.sqrt(dy.x * dy.x + dy.y * dy.y + dy.z * dy.z));
		var lod = rho > 0 ? Math.log(rho) / Math.log(2) : -1.0;
		inline function one(i:Int):Vec4
			return cubeAt(b, new Vec3(dir.x.get(i), dir.y.get(i), dir.z.get(i)), lod);
		return lanes(one(0), one(1), one(2), one(3));
	}

	public static function cubeLevel(b:Ptr, dir:Lane3, level:Lane):Lane4 {
		inline function one(i:Int):Vec4
			return cubeAt(b, new Vec3(dir.x.get(i), dir.y.get(i), dir.z.get(i)), level.get(i));
		return lanes(one(0), one(1), one(2), one(3));
	}

	#if !helder.soft.exact
	// the four lanes at one level of detail (a quad's, or a level every lane
	// names), SIMD: their texels' coordinates and weights in lanes, the
	// texels gathered and turned into channels
	static function quad(b:Ptr, t:Ptr, layer:Int, u:Lane, v:Lane, lod:Float, wrap:Int):Lane4 {
		var linear = Mem.getI32(b, FILTER) != 0, mip = Mem.getI32(b, MIP), levels = Mem.getI32(t, SoftTexture.LEVELS);
		if (mip < 0 || levels == 1 || !(lod > 0)) return level(t, 0, layer, u.f32(), v.f32(), linear, wrap);
		var top = levels - 1.0;
		if (lod > top) lod = top;
		if (mip == 0) return level(t, Std.int(lod + 0.5), layer, u.f32(), v.f32(), linear, wrap);
		var l0 = Math.floor(lod), f = lod - l0;
		var a = level(t, l0, layer, u.f32(), v.f32(), linear, wrap);
		if (f == 0 || l0 >= levels - 1) return a;
		var c = level(t, l0 + 1, layer, u.f32(), v.f32(), linear, wrap);
		return a + (c - a) * Lane4.fill(Lane.splat(f));
	}

	static function level(t:Ptr, level:Int, layer:Int, u:F32x4, v:F32x4, linear:Bool, wrap:Int):Lane4 {
		var w = SoftTexture.width(t, level), h = SoftTexture.height(t, level), base = SoftTexture.at(t, level, layer);
		var fw = F32x4.splat(w), fh = F32x4.splat(h);
		var kind = Mem.getI32(t, SoftTexture.KIND);
		if (!linear) return fetch(t, kind, base, wraps((u * fw).floor(), w, wrap) + wraps((v * fh).floor(), h, wrap) * I32x4.splat(w));
		var x = u * fw - F32x4.splat(0.5), y = v * fh - F32x4.splat(0.5);
		var x0 = x.floor(), y0 = y.floor(), fx = Lane.ofF32(x - x0), fy = Lane.ofF32(y - y0);
		var one = F32x4.splat(1), xa = wraps(x0, w, wrap), xb = wraps(x0 + one, w, wrap), ya = wraps(y0, h, wrap) * I32x4.splat(w), yb = wraps(y0 + one, h, wrap) * I32x4.splat(w);
		var a = fetch(t, kind, base, xa + ya), bb = fetch(t, kind, base, xb + ya), c = fetch(t, kind, base, xa + yb), d = fetch(t, kind, base, xb + yb);
		var top = a + (bb - a) * Lane4.fill(fx), bottom = c + (d - c) * Lane4.fill(fx);
		return top + (bottom - top) * Lane4.fill(fy);
	}

	// (whole texel coordinates, as floats, held in 0...n by the wrap mode)
	static inline function wraps(i:F32x4, n:Int, wrap:Int):I32x4 {
		var fn = F32x4.splat(n);
		return switch wrap {
			case 1: i.clamp(F32x4.zero(), F32x4.splat(n - 1)).toI32x4();
			case 2:
				var p = F32x4.splat(2 * n), k = i - (i / p).floor() * p;
				F32x4.select(k.lt(fn), k, p - F32x4.splat(1) - k).toI32x4();
			case _:
				// (i less its multiple of n, by n's reciprocal: one step back or on where that rounded)
				var k = i - (i * F32x4.splat(1 / n)).floor() * fn;
				k = F32x4.select(k.ge(fn), k - fn, F32x4.select(k.lt(F32x4.zero()), k + fn, k));
				k.toI32x4();
		}
	}

	// the texels at indices i of a level's layer, as channels
	static inline function fetch(t:Ptr, kind:Int, base:Ptr, i:I32x4):Lane4 {
		var i0 = i.get(0), i1 = i.get(1), i2 = i.get(2), i3 = i.get(3);
		// (one texel for all four: a data texture's lookups by an index every lane shares)
		var one = i0 == i1 && i0 == i2 && i0 == i3;
		if (kind == SoftTexture.U8) {
			var p = one ? I32x4.splat(Mem.getI32(base, 4 * i0)) : I32x4.make(Mem.getI32(base, 4 * i0), Mem.getI32(base, 4 * i1), Mem.getI32(base, 4 * i2),
				Mem.getI32(base, 4 * i3));
			var k = F32x4.splat(1 / 255), m = I32x4.splat(255);
			var a = Lane.ofF32(F32x4.fromI32x4((p >>> 24) & m) * k);
			if (Mem.getI32(t, SoftTexture.SRGB) != 0) {
				var s = Mem.getPtr(t, SoftTexture.TABLE);
				inline function ch(sh:Int):Lane
					return Lane.make(Mem.getF32(s, 4 * ((p.get(0) >> sh) & 255)), Mem.getF32(s, 4 * ((p.get(1) >> sh) & 255)), Mem.getF32(s, 4 * ((p.get(2) >> sh) & 255)),
						Mem.getF32(s, 4 * ((p.get(3) >> sh) & 255)));
				return new Lane4(ch(0), ch(8), ch(16), a);
			}
			return new Lane4(Lane.ofF32(F32x4.fromI32x4(p & m) * k), Lane.ofF32(F32x4.fromI32x4((p >> 8) & m) * k), Lane.ofF32(F32x4.fromI32x4((p >> 16) & m) * k), a);
		}
		if (kind == SoftTexture.F4) {
			if (one) {
				var p = F32x4.loadPtr(base, 16 * i0);
				return new Lane4(Lane.ofF32(p.swizzle(0, 0, 0, 0)), Lane.ofF32(p.swizzle(1, 1, 1, 1)), Lane.ofF32(p.swizzle(2, 2, 2, 2)), Lane.ofF32(p.swizzle(3, 3, 3, 3)));
			}
			var p0 = F32x4.loadPtr(base, 16 * i0), p1 = F32x4.loadPtr(base, 16 * i1), p2 = F32x4.loadPtr(base, 16 * i2), p3 = F32x4.loadPtr(base, 16 * i3);
			var t0 = p0.shuffle(p1, 0, 4, 1, 5), t1 = p0.shuffle(p1, 2, 6, 3, 7), t2 = p2.shuffle(p3, 0, 4, 1, 5), t3 = p2.shuffle(p3, 2, 6, 3, 7);
			return new Lane4(Lane.ofF32(t0.shuffle(t2, 0, 1, 4, 5)), Lane.ofF32(t0.shuffle(t2, 2, 3, 6, 7)), Lane.ofF32(t1.shuffle(t3, 0, 1, 4, 5)),
				Lane.ofF32(t1.shuffle(t3, 2, 3, 6, 7)));
		}
		return new Lane4(Lane.make(Mem.getF32(base, 4 * i0), Mem.getF32(base, 4 * i1), Mem.getF32(base, 4 * i2), Mem.getF32(base, 4 * i3)), Lane.zero(), Lane.zero(),
			Lane.splat(1));
	}
	#end

	static inline function lanes(a:Vec4, b:Vec4, c:Vec4, d:Vec4):Lane4
		return new Lane4(Lane.make(a.x, b.x, c.x, d.x), Lane.make(a.y, b.y, c.y, d.y), Lane.make(a.z, b.z, c.z, d.z), Lane.make(a.w, b.w, c.w, d.w));

	// the quad's level of detail: log2 of its larger derivative in texels
	static inline function quadLod(u:Lane, v:Lane, w:Int, h:Int):Float {
		var ux = (u.get(1) - u.get(0)) * w, vx = (v.get(1) - v.get(0)) * h, uy = (u.get(2) - u.get(0)) * w, vy = (v.get(2) - v.get(0)) * h;
		var rho = Math.max(ux * ux + vx * vx, uy * uy + vy * vy);
		#if helder.soft.exact
		return rho > 0 ? 0.5 * Math.log(rho) / Math.log(2) : -1.0;
		#else
		return rho > 0 ? 0.5 * 1.4426950408889634 * Lane.splat(rho).log().get(0) : -1.0;
		#end
	}

	static inline function layerOf(b:Ptr, layer:Float):Int {
		var t = Mem.getPtr(b, TEXTURE);
		var n = t.isNull() ? 1 : Mem.getI32(t, SoftTexture.LAYERS);
		var l = Math.floor(layer + 0.5);
		return l < 0 ? 0 : l >= n ? n - 1 : l;
	}

	// the binding's texture at u, v of a layer, at a level of detail
	public static function at(b:Ptr, layer:Int, u:Float, v:Float, lod:Float, wrap:Int):Vec4 {
		var t = Mem.getPtr(b, TEXTURE);
		if (t.isNull()) return new Vec4(0, 0, 0, 0);
		var linear = Mem.getI32(b, FILTER) != 0, mip = Mem.getI32(b, MIP), levels = Mem.getI32(t, SoftTexture.LEVELS);
		if (mip < 0 || levels == 1 || !(lod > 0)) return filtered(t, 0, layer, u, v, linear, wrap);
		var top = levels - 1.0;
		if (lod > top) lod = top;
		if (mip == 0) return filtered(t, Std.int(lod + 0.5), layer, u, v, linear, wrap);
		var l0 = Math.floor(lod), f = lod - l0;
		var a = filtered(t, l0, layer, u, v, linear, wrap);
		if (f == 0 || l0 >= levels - 1) return a;
		var c = filtered(t, l0 + 1, layer, u, v, linear, wrap);
		return a + (c - a) * f;
	}

	static function filtered(t:Ptr, level:Int, layer:Int, u:Float, v:Float, linear:Bool, wrap:Int):Vec4 {
		var w = SoftTexture.width(t, level), h = SoftTexture.height(t, level), base = SoftTexture.at(t, level, layer);
		if (!linear) return texel(t, base, w, wrapped(Math.floor(u * w), w, wrap), wrapped(Math.floor(v * h), h, wrap));
		var x = u * w - 0.5, y = v * h - 0.5;
		var x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
		var xa = wrapped(x0, w, wrap), xb = wrapped(x0 + 1, w, wrap), ya = wrapped(y0, h, wrap), yb = wrapped(y0 + 1, h, wrap);
		var a = texel(t, base, w, xa, ya), b = texel(t, base, w, xb, ya), c = texel(t, base, w, xa, yb), d = texel(t, base, w, xb, yb);
		var top = a + (b - a) * fx, bottom = c + (d - c) * fx;
		return top + (bottom - top) * fy;
	}

	static inline function wrapped(i:Int, n:Int, wrap:Int):Int
		return switch wrap {
			case 1: i < 0 ? 0 : i >= n ? n - 1 : i;
			case 2:
				var k = i % (2 * n);
				if (k < 0) k += 2 * n;
				k < n ? k : 2 * n - 1 - k;
			case _:
				var k = i % n;
				k < 0 ? k + n : k;
		}

	static inline function texel(t:Ptr, base:Ptr, w:Int, x:Int, y:Int):Vec4 {
		var kind = Mem.getI32(t, SoftTexture.KIND);
		if (kind == SoftTexture.U8) {
			var p = Mem.getI32(base, 4 * (y * w + x));
			var a = ((p >>> 24) & 255) / 255;
			if (Mem.getI32(t, SoftTexture.SRGB) != 0) {
				var s = Mem.getPtr(t, SoftTexture.TABLE);
				return new Vec4(Mem.getF32(s, 4 * (p & 255)), Mem.getF32(s, 4 * ((p >> 8) & 255)), Mem.getF32(s, 4 * ((p >> 16) & 255)), a);
			}
			return new Vec4((p & 255) / 255, ((p >> 8) & 255) / 255, ((p >> 16) & 255) / 255, a);
		}
		if (kind == SoftTexture.F4) {
			var o = 16 * (y * w + x);
			return new Vec4(Mem.getF32(base, o), Mem.getF32(base, o + 4), Mem.getF32(base, o + 8), Mem.getF32(base, o + 12));
		}
		return new Vec4(Mem.getF32(base, 4 * (y * w + x)), 0, 0, 1);
	}
}
