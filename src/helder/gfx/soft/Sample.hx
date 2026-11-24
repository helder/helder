package helder.gfx.soft;

import helder.gfx.shader.TextureCube;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
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
		return lanes(at(b, 0, uv.x.get(0), uv.y.get(0), lod, wrap), at(b, 0, uv.x.get(1), uv.y.get(1), lod, wrap), at(b, 0, uv.x.get(2), uv.y.get(2), lod, wrap),
			at(b, 0, uv.x.get(3), uv.y.get(3), lod, wrap));
	}

	public static function flatLevel(b:Ptr, uv:Lane2, level:Lane):Lane4 {
		var wrap = Mem.getI32(b, WRAP);
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

	static inline function lanes(a:Vec4, b:Vec4, c:Vec4, d:Vec4):Lane4
		return new Lane4(Lane.make(a.x, b.x, c.x, d.x), Lane.make(a.y, b.y, c.y, d.y), Lane.make(a.z, b.z, c.z, d.z), Lane.make(a.w, b.w, c.w, d.w));

	// the quad's level of detail: log2 of its larger derivative in texels
	static inline function quadLod(u:Lane, v:Lane, w:Int, h:Int):Float {
		var ux = (u.get(1) - u.get(0)) * w, vx = (v.get(1) - v.get(0)) * h, uy = (u.get(2) - u.get(0)) * w, vy = (v.get(2) - v.get(0)) * h;
		var rho = Math.max(ux * ux + vx * vx, uy * uy + vy * vy);
		return rho > 0 ? 0.5 * Math.log(rho) / Math.log(2) : -1.0;
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
