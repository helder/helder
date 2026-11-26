package helder.gfx.soft;

import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A fragment's colour into the target, as GPUs blend it (helder.gfx.Blend:
// Opaque, Alpha, Additive, Premultiplied, Multiply, GL's factors) in the
// target's format: unorm values clamped before and after, rounded to the
// nearest; sRGB blended in linear values; RGBA16F rounded to halves. quad:
// a quad's four pixels at once (one sample a pixel), one: a sample
@:hxmc.unsafe(gc)
class Blender {
	public static function quad(pass:Ptr, color:Ptr, at:Int, w:Int, m:Int, blend:Int, out:Ptr) {
		var kind = Mem.getI32(pass, Raster.KIND), format = Mem.getI32(pass, Raster.FORMAT);
		var sr = F32x4.loadPtr(out, 0), sg = F32x4.loadPtr(out, 16), sb = F32x4.loadPtr(out, 32), sa = F32x4.loadPtr(out, 48);
		var zero = F32x4.zero(), one = F32x4.splat(1);
		var i0 = at, i1 = at + 1, i2 = at + w, i3 = at + w + 1;
		if (kind == SoftTexture.U8) {
			sr = sr.clamp(zero, one);
			sg = sg.clamp(zero, one);
			sb = sb.clamp(zero, one);
			sa = sa.clamp(zero, one);
			var srgb = format == (cast helder.gfx.TextureFormat.RGBA8Srgb : Int), table = Mem.getPtr(pass, Raster.TABLE);
			if (blend != 0) {
				var p0 = Mem.getI32(color, 4 * i0), p1 = m & 2 != 0 ? Mem.getI32(color, 4 * i1) : 0, p2 = m & 4 != 0 ? Mem.getI32(color, 4 * i2) : 0,
					p3 = m & 8 != 0 ? Mem.getI32(color, 4 * i3) : 0;
				var v = I32x4.make(p0, p1, p2, p3), k = F32x4.splat(1 / 255), mask = I32x4.splat(255);
				var dr, dg, db;
				if (srgb) {
					// (the table's floats gathered as their bits)
					inline function lin(p:Int, s:Int):Int
						return Mem.getI32(table, 4 * ((p >> s) & 255));
					dr = I32x4.make(lin(p0, 0), lin(p1, 0), lin(p2, 0), lin(p3, 0)).asF32x4();
					dg = I32x4.make(lin(p0, 8), lin(p1, 8), lin(p2, 8), lin(p3, 8)).asF32x4();
					db = I32x4.make(lin(p0, 16), lin(p1, 16), lin(p2, 16), lin(p3, 16)).asF32x4();
				} else {
					dr = F32x4.fromI32x4(v & mask) * k;
					dg = F32x4.fromI32x4((v >> 8) & mask) * k;
					db = F32x4.fromI32x4((v >> 16) & mask) * k;
				}
				var da = F32x4.fromI32x4((v >>> 24) & mask) * k;
				switch blend {
					case 1:
						var ia = one - sa;
						sr = sr * sa + dr * ia;
						sg = sg * sa + dg * ia;
						sb = sb * sa + db * ia;
						sa = sa + da * ia;
					case 2:
						sr = sr + dr;
						sg = sg + dg;
						sb = sb + db;
						sa = sa + da;
					case 3:
						var ia = one - sa;
						sr = sr + dr * ia;
						sg = sg + dg * ia;
						sb = sb + db * ia;
						sa = sa + da * ia;
					case _:
						sr = dr * sr;
						sg = dg * sg;
						sb = db * sb;
						sa = da;
				}
				sr = sr.clamp(zero, one);
				sg = sg.clamp(zero, one);
				sb = sb.clamp(zero, one);
				sa = sa.clamp(zero, one);
			}
			if (format == (cast helder.gfx.TextureFormat.R8 : Int)) {
				sg = zero;
				sb = zero;
				sa = one;
			} else if (format == (cast helder.gfx.TextureFormat.RG8 : Int)) {
				sb = zero;
				sa = one;
			}
			var k = F32x4.splat(255), h = F32x4.splat(0.5);
			var a = (sa * k + h).toI32x4();
			var px;
			if (srgb) {
				inline function code(v:F32x4, l:Int):Int
					return Formats.srgbCode(table, v.get(l));
				inline function lane(l:Int):Int
					return code(sr, l) | (code(sg, l) << 8) | (code(sb, l) << 16) | (a.get(l) << 24);
				px = I32x4.make(lane(0), lane(1), lane(2), lane(3));
			} else
				px = (sr * k + h).toI32x4() | ((sg * k + h).toI32x4() << 8) | ((sb * k + h).toI32x4() << 16) | (a << 24);
			if (m & 1 != 0) Mem.setI32(color, 4 * i0, px.get(0));
			if (m & 2 != 0) Mem.setI32(color, 4 * i1, px.get(1));
			if (m & 4 != 0) Mem.setI32(color, 4 * i2, px.get(2));
			if (m & 8 != 0) Mem.setI32(color, 4 * i3, px.get(3));
			return;
		}
		if (kind == SoftTexture.F1) {
			if (blend != 0) {
				var d = I32x4.make(Mem.getI32(color, 4 * i0), m & 2 != 0 ? Mem.getI32(color, 4 * i1) : 0, m & 4 != 0 ? Mem.getI32(color, 4 * i2) : 0,
					m & 8 != 0 ? Mem.getI32(color, 4 * i3) : 0).asF32x4();
				sr = switch blend {
					case 1: sr * sa + d * (one - sa);
					case 2: sr + d;
					case 3: sr + d * (one - sa);
					case _: d * sr;
				}
			}
			var bits = sr.asI32x4();
			if (m & 1 != 0) Mem.setI32(color, 4 * i0, bits.get(0));
			if (m & 2 != 0) Mem.setI32(color, 4 * i1, bits.get(1));
			if (m & 4 != 0) Mem.setI32(color, 4 * i2, bits.get(2));
			if (m & 8 != 0) Mem.setI32(color, 4 * i3, bits.get(3));
			return;
		}
		// (4 floats a pixel: the quad's pixels transposed to their channels and back)
		if (blend != 0) {
			var p0 = F32x4.loadPtr(color, 16 * i0), p1 = m & 2 != 0 ? F32x4.loadPtr(color, 16 * i1) : zero, p2 = m & 4 != 0 ? F32x4.loadPtr(color, 16 * i2) : zero,
				p3 = m & 8 != 0 ? F32x4.loadPtr(color, 16 * i3) : zero;
			var t0 = p0.shuffle(p1, 0, 4, 1, 5), t1 = p0.shuffle(p1, 2, 6, 3, 7), t2 = p2.shuffle(p3, 0, 4, 1, 5), t3 = p2.shuffle(p3, 2, 6, 3, 7);
			var dr = t0.shuffle(t2, 0, 1, 4, 5), dg = t0.shuffle(t2, 2, 3, 6, 7), db = t1.shuffle(t3, 0, 1, 4, 5), da = t1.shuffle(t3, 2, 3, 6, 7);
			switch blend {
				case 1:
					var ia = one - sa;
					sr = sr * sa + dr * ia;
					sg = sg * sa + dg * ia;
					sb = sb * sa + db * ia;
					sa = sa + da * ia;
				case 2:
					sr = sr + dr;
					sg = sg + dg;
					sb = sb + db;
					sa = sa + da;
				case 3:
					var ia = one - sa;
					sr = sr + dr * ia;
					sg = sg + dg * ia;
					sb = sb + db * ia;
					sa = sa + da * ia;
				case _:
					sr = dr * sr;
					sg = dg * sg;
					sb = db * sb;
					sa = da;
			}
		}
		if (format == (cast helder.gfx.TextureFormat.RGBA16F : Int)) {
			sr = halves(sr);
			sg = halves(sg);
			sb = halves(sb);
			sa = halves(sa);
		}
		var t0 = sr.shuffle(sg, 0, 4, 1, 5), t1 = sr.shuffle(sg, 2, 6, 3, 7), t2 = sb.shuffle(sa, 0, 4, 1, 5), t3 = sb.shuffle(sa, 2, 6, 3, 7);
		if (m & 1 != 0) t0.shuffle(t2, 0, 1, 4, 5).storePtr(color, 16 * i0);
		if (m & 2 != 0) t0.shuffle(t2, 2, 3, 6, 7).storePtr(color, 16 * i1);
		if (m & 4 != 0) t1.shuffle(t3, 0, 1, 4, 5).storePtr(color, 16 * i2);
		if (m & 8 != 0) t1.shuffle(t3, 2, 3, 6, 7).storePtr(color, 16 * i3);
	}

	// v's lanes as half floats store them (nearest, ties to even; past 65504 infinite)
	public static inline function halves(v:F32x4):F32x4 {
		var bits = v.asI32x4();
		var normal = ((bits + I32x4.splat(0xFFF) + ((bits >>> 13) & I32x4.splat(1))) & I32x4.splat(~0x1FFF)).asF32x4();
		var k = F32x4.splat(16777216);
		var tiny = (v * k).round() / k;
		var r = F32x4.select(v.abs().lt(F32x4.splat(6.103515625e-5)), tiny, normal);
		var inf = (I32x4.splat(0x7F800000) | (bits & I32x4.splat(0x80000000))).asF32x4();
		return F32x4.select(r.abs().gt(F32x4.splat(65504)), F32x4.select(v.ne(v), v, inf), r);
	}

	// one sample's colour (the texel at index at)
	public static function one(pass:Ptr, color:Ptr, at:Int, blend:Int, r:Float, g:Float, b:Float, a:Float) {
		var kind = Mem.getI32(pass, Raster.KIND), format = Mem.getI32(pass, Raster.FORMAT);
		if (kind == SoftTexture.U8) {
			inline function clamp(v:Float):Float
				return v < 0 ? 0 : v > 1 ? 1 : v;
			r = clamp(r);
			g = clamp(g);
			b = clamp(b);
			a = clamp(a);
			var srgb = format == (cast helder.gfx.TextureFormat.RGBA8Srgb : Int), table = Mem.getPtr(pass, Raster.TABLE);
			if (blend != 0) {
				var p = Mem.getI32(color, 4 * at);
				inline function ch(s:Int):Float
					return srgb && s < 24 ? (Mem.getF32(table, 4 * ((p >> s) & 255)) : Float) : ((p >>> s) & 255) / 255;
				var dr = ch(0), dg = ch(8), db = ch(16), da = ch(24);
				var o = mix(blend, r, g, b, a, dr, dg, db, da);
				r = clamp(o.x);
				g = clamp(o.y);
				b = clamp(o.z);
				a = clamp(o.w);
			}
			if (format == (cast helder.gfx.TextureFormat.R8 : Int)) {
				g = b = 0;
				a = 1;
			} else if (format == (cast helder.gfx.TextureFormat.RG8 : Int)) {
				b = 0;
				a = 1;
			}
			inline function code(v:Float):Int
				return Std.int(v * 255 + 0.5);
			var px = srgb ? Formats.srgbCode(table, r) | (Formats.srgbCode(table, g) << 8) | (Formats.srgbCode(table, b) << 16) | (code(a) << 24) : code(r) | (code(g) << 8)
				| (code(b) << 16) | (code(a) << 24);
			Mem.setI32(color, 4 * at, px);
			return;
		}
		if (kind == SoftTexture.F1) {
			if (blend != 0) r = mix(blend, r, 0, 0, a, Mem.getF32(color, 4 * at), 0, 0, 1).x;
			Mem.setF32(color, 4 * at, r);
			return;
		}
		if (blend != 0) {
			var o = mix(blend, r, g, b, a, Mem.getF32(color, 16 * at), Mem.getF32(color, 16 * at + 4), Mem.getF32(color, 16 * at + 8), Mem.getF32(color, 16 * at + 12));
			r = o.x;
			g = o.y;
			b = o.z;
			a = o.w;
		}
		if (format == (cast helder.gfx.TextureFormat.RGBA16F : Int)) {
			r = Formats.roundHalf(r);
			g = Formats.roundHalf(g);
			b = Formats.roundHalf(b);
			a = Formats.roundHalf(a);
		}
		Mem.setF32(color, 16 * at, r);
		Mem.setF32(color, 16 * at + 4, g);
		Mem.setF32(color, 16 * at + 8, b);
		Mem.setF32(color, 16 * at + 12, a);
	}

	static inline function mix(blend:Int, r:Float, g:Float, b:Float, a:Float, dr:Float, dg:Float, db:Float, da:Float):helder.math.Vec4
		return switch blend {
			case 1: new helder.math.Vec4(r * a + dr * (1 - a), g * a + dg * (1 - a), b * a + db * (1 - a), a + da * (1 - a));
			case 2: new helder.math.Vec4(r + dr, g + dg, b + db, a + da);
			case 3: new helder.math.Vec4(r + dr * (1 - a), g + dg * (1 - a), b + db * (1 - a), a + da * (1 - a));
			case _: new helder.math.Vec4(dr * r, dg * g, db * b, da);
		}
}
