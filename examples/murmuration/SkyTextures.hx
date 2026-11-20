import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import SkyShader;

// The sky's noise, made once instead of each pixel: the hills' heights
// along the horizon (far, middle, near: SkyShader's ridges around the
// circle, so the ends meet) and a tiling cloud of five octaves.
class SkyTextures {
	public static function hills(device:Device):Texture {
		var n = 2048, b = Bytes.alloc(n * 4);
		for (i in 0...n) {
			var t = (i + 0.5) / n * Math.PI * 2 - Math.PI;
			var a = new Vec2(Math.cos(t), Math.sin(t));
			var hs = [ridge(a, 2.3, 11, 0.004, 0.05), ridge(a, 3.7, 37, 0.0, 0.04), ridge(a, 6.0, 71, -0.012, 0.03)];
			for (k in 0...3)
				b.set(i * 4 + k, Std.int(Math.max(0, Math.min(255, (hs[k] + 0.02) / 0.1 * 255 + 0.5))));
			b.set(i * 4 + 3, 255);
		}
		return device.createTexture({width: n, height: 1, data: b});
	}

	public static function clouds(device:Device):Texture {
		var n = 512, b = Bytes.alloc(n * n * 4);
		for (y in 0...n)
			for (x in 0...n) {
				var s = 0.0, a = 0.5;
				for (o in 0...5) {
					var period = 4 << o;
					s += a * tiled(x / n * period, y / n * period, period, o);
					a *= 0.5;
				}
				var v = Std.int(Math.max(0, Math.min(255, s * 255)));
				for (k in 0...4)
					b.set((y * n + x) * 4 + k, v);
			}
		var t = device.createTexture({width: n, height: n, data: b, mipLevels: 0});
		device.generateMips(t);
		return t;
	}

	// value noise repeating every period cells
	static function tiled(x:Float, y:Float, period:Int, seed:Int):Float {
		var ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
		var ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
		inline function h(i:Int, j:Int)
			return hash(new Vec2(((i % period) + period) % period + seed * 101, ((j % period) + period) % period + seed * 37));
		var ix = Std.int(ix), iy = Std.int(iy);
		var top = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * ux, bottom = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * ux;
		return top + (bottom - top) * uy;
	}
}
