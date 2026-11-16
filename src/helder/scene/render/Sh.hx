package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.TextureFormat;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// Light around a point as L2 spherical harmonics (Ramamoorthi and Hanrahan,
// "An Efficient Representation for Irradiance Environment Maps"): nine RGB
// coefficients of the radiance arriving from each direction (the real SH
// basis, bands 0 to 2), from which the diffuse light along any normal is a
// polynomial of it: smooth, cheap, free of seams. An Environment's diffuse
// light (Environment.sh), a LightProbe's, a ProbeGrid's at a point.
//
// coefficients: 27 floats, coefficient k's red, green and blue at 3k, in the
// order Y00, Y1-1 (y), Y10 (z), Y11 (x), Y2-2 (xy), Y2-1 (yz), Y20 (3z^2 - 1),
// Y21 (xz), Y22 (x^2 - y^2). Directions are the world's (y up).
//
// irradiance(n) is the irradiance along n over pi (the light a white
// Lambertian surface reflects: an environment atlas' irradiance row's
// meaning); pack writes it as the seven vectors a shader evaluates
// (irradianceOf in PbrShader: Unity's SHAr, SHAg, SHAb, SHBr, SHBg, SHBb, SHC).
class Sh {
	public final coefficients:Array<Float>;

	public function new(?coefficients:Array<Float>) {
		this.coefficients = coefficients != null ? coefficients : [for (_ in 0...27) 0.0];
		if (this.coefficients.length != 27) throw "helder.scene: Sh: 27 coefficients (nine RGB)";
	}

	// (the basis' constants)
	static inline var Y0 = 0.282095;
	static inline var Y1 = 0.488603;
	static inline var Y2 = 1.092548;
	static inline var Y20 = 0.315392;
	static inline var Y22 = 0.546274;

	// the nine basis functions at a unit direction, into out (nine floats)
	public static function basis(x:Float, y:Float, z:Float, out:Array<Float>) {
		out[0] = Y0;
		out[1] = Y1 * y;
		out[2] = Y1 * z;
		out[3] = Y1 * x;
		out[4] = Y2 * x * y;
		out[5] = Y2 * y * z;
		out[6] = Y20 * (3 * z * z - 1);
		out[7] = Y2 * x * z;
		out[8] = Y22 * (x * x - y * y);
	}

	// a copy
	public function copy():Sh
		return new Sh(coefficients.copy());

	// every coefficient 0
	public function clear():Sh {
		for (k in 0...27)
			coefficients[k] = 0;
		return this;
	}

	// a light of colour c from the unit direction d (a delta: the sun's
	// light as a point of the sky), added
	public function addDirectional(d:Vec3, c:Vec3):Sh {
		var b = scratch;
		basis(d.x, d.y, d.z, b);
		for (k in 0...9) {
			coefficients[3 * k] += c.x * b[k];
			coefficients[3 * k + 1] += c.y * b[k];
			coefficients[3 * k + 2] += c.z * b[k];
		}
		return this;
	}

	// o's coefficients times w, added
	public function addScaled(o:Sh, w:Float):Sh {
		for (k in 0...27)
			coefficients[k] += o.coefficients[k] * w;
		return this;
	}

	// every coefficient times s
	public function scale(s:Float):Sh {
		for (k in 0...27)
			coefficients[k] *= s;
		return this;
	}

	// a's blended towards b by t, into this (nothing allocated)
	public function setLerp(a:Sh, b:Sh, t:Float):Sh {
		for (k in 0...27)
			coefficients[k] = a.coefficients[k] + (b.coefficients[k] - a.coefficients[k]) * t;
		return this;
	}

	// the irradiance along the unit normal n over pi (Lambert's reflected
	// light for a white surface)
	public function irradiance(n:Vec3):Vec3 {
		var b = scratch;
		basis(n.x, n.y, n.z, b);
		var r = 0.0, g = 0.0, bl = 0.0;
		for (k in 0...9) {
			// (each band convolved with the clamped cosine, over pi: 1, 2/3, 1/4)
			var a = k == 0 ? 1.0 : k < 4 ? 2 / 3 : 0.25;
			r += coefficients[3 * k] * b[k] * a;
			g += coefficients[3 * k + 1] * b[k] * a;
			bl += coefficients[3 * k + 2] * b[k] * a;
		}
		return new Vec3(Math.max(r, 0), Math.max(g, 0), Math.max(bl, 0));
	}

	// the radiance arriving from the unit direction d (the band-limited light
	// itself, not convolved: a probe's preview)
	public function radiance(d:Vec3):Vec3 {
		var b = scratch;
		basis(d.x, d.y, d.z, b);
		var r = 0.0, g = 0.0, bl = 0.0;
		for (k in 0...9) {
			r += coefficients[3 * k] * b[k];
			g += coefficients[3 * k + 1] * b[k];
			bl += coefficients[3 * k + 2] * b[k];
		}
		return new Vec3(r, g, bl);
	}

	// the seven vectors of irradiance's polynomial (over pi) into out from at:
	// for each of red, green and blue its band 0 and 1 (x, y, z: the normal's
	// factors, w the constant), then its band 2's xy, yz, zz, zx, then the
	// x^2 - y^2 factor of each (rgb); what PbrObject's and the prefilter's
	// blocks hold
	public function pack(out:Array<Vec4>, at = 0) {
		var c = coefficients, a1 = 2 / 3 * Y1, a2 = 0.25 * Y2;
		for (ch in 0...3) {
			out[at + ch] = new Vec4(a1 * c[9 + ch], a1 * c[3 + ch], a1 * c[6 + ch], Y0 * c[ch] - 0.25 * Y20 * c[18 + ch]);
			out[at + 3 + ch] = new Vec4(a2 * c[12 + ch], a2 * c[15 + ch], 0.75 * Y20 * c[18 + ch], a2 * c[21 + ch]);
		}
		out[at + 6] = new Vec4(0.25 * Y22 * c[24], 0.25 * Y22 * c[25], 0.25 * Y22 * c[26], 0);
	}

	// the light of a sky over a ground (a hemisphere light: sky above,
	// ground below, the horizon between blended as the standard material's
	// ambient blends them by the normal's height)
	public static function ofHemisphere(sky:Vec3, ground:Vec3):Sh {
		// (the colours' channels: a closure takes no struct)
		var sr = sky.x, sg = sky.y, sb = sky.z, gr = ground.x, gg = ground.y, gb = ground.z;
		return ofFunction(d -> {
			var t = d.y * 0.5 + 0.5;
			return new Vec3(gr + (sr - gr) * t, gg + (sg - gg) * t, gb + (sb - gb) * t);
		}, 32);
	}

	// the radiance f gives each direction, projected (integrated over a grid
	// of the sphere, size rows of latitude by twice as many of longitude)
	public static function ofFunction(f:Vec3->Vec3, size = 64):Sh {
		var sh = new Sh(), b = [for (_ in 0...9) 0.0], c = sh.coefficients;
		var w = size * 2, h = size;
		for (y in 0...h) {
			var theta = (y + 0.5) / h * Math.PI, st = Math.sin(theta), ct = Math.cos(theta);
			var dw = (2 * Math.PI / w) * (Math.PI / h) * st;
			for (x in 0...w) {
				var phi = ((x + 0.5) / w - 0.5) * 2 * Math.PI;
				var d = new Vec3(st * Math.sin(phi), ct, -st * Math.cos(phi));
				var l = f(d);
				basis(d.x, d.y, d.z, b);
				for (k in 0...9) {
					c[3 * k] += l.x * b[k] * dw;
					c[3 * k + 1] += l.y * b[k] * dw;
					c[3 * k + 2] += l.z * b[k] * dw;
				}
			}
		}
		return sh;
	}

	// an equirectangular image's light (longitude across, -z at its centre,
	// latitude down: Environment's layout), its texels of format (RGBA8:
	// sRGB-encoded, decoded as the standard material decodes it, c^2.2;
	// RGBA16F, RGBA32F: linear), each its solid angle's share, times intensity
	public static function ofEquirect(width:Int, height:Int, texels:Bytes, format:TextureFormat = RGBA8, intensity = 1.0):Sh {
		if (format != RGBA8 && format != RGBA8Srgb && format != RGBA16F && format != RGBA32F)
			throw "helder.scene: Sh.ofEquirect: RGBA8, RGBA16F or RGBA32F texels";
		if (texels.length < width * height * format.texelSize) throw "helder.scene: Sh.ofEquirect: too few texels";
		var sh = new Sh(), b = [for (_ in 0...9) 0.0], c = sh.coefficients;
		for (y in 0...height) {
			var theta = (y + 0.5) / height * Math.PI, st = Math.sin(theta), ct = Math.cos(theta);
			var dw = (2 * Math.PI / width) * (Math.PI / height) * st * intensity;
			for (x in 0...width) {
				var phi = ((x + 0.5) / width - 0.5) * 2 * Math.PI;
				var dx = st * Math.sin(phi), dz = -st * Math.cos(phi);
				var p = y * width + x, r = 0.0, g = 0.0, bl = 0.0;
				switch format {
					case RGBA16F:
						r = half(texels.getUInt16(8 * p));
						g = half(texels.getUInt16(8 * p + 2));
						bl = half(texels.getUInt16(8 * p + 4));
					case RGBA32F:
						r = texels.getFloat(16 * p);
						g = texels.getFloat(16 * p + 4);
						bl = texels.getFloat(16 * p + 8);
					case _:
						r = Math.pow(texels.get(4 * p) / 255, 2.2);
						g = Math.pow(texels.get(4 * p + 1) / 255, 2.2);
						bl = Math.pow(texels.get(4 * p + 2) / 255, 2.2);
				}
				basis(dx, ct, dz, b);
				for (k in 0...9) {
					c[3 * k] += r * b[k] * dw;
					c[3 * k + 1] += g * b[k] * dw;
					c[3 * k + 2] += bl * b[k] * dw;
				}
			}
		}
		return sh;
	}

	// an IEEE 754 binary16's value
	public static function half(h:Int):Float {
		var e = (h >> 10) & 31, m = h & 1023, s = (h & 0x8000) != 0 ? -1.0 : 1.0;
		if (e == 0) return s * m * Math.pow(2, -24);
		if (e == 31) return m == 0 ? s * Math.POSITIVE_INFINITY : Math.NaN;
		return s * (1 + m / 1024) * Math.pow(2, e - 15);
	}

	// (irradiance's and addDirectional's basis: one array, nothing allocated)
	static final scratch = [for (_ in 0...9) 0.0];
}
