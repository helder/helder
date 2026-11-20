import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import SkyShader;

class SkyTextures {
	public static inline var WEATHER_SIZE = 1024;

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

	// Mips filter the cloud octaves and ripple slopes before the horizon compresses them.
	public static function weather(device:Device):Texture {
		var n = WEATHER_SIZE, b = Bytes.alloc(n * n * 4);
		for (y in 0...n)
			for (x in 0...n) {
				var u = (x + 0.5) / n, v = (y + 0.5) / n;
				var a = u + (tiled(u, v, 4, 0) - 0.5) * 0.038;
				var c = v + (tiled(u, v, 4, 1) - 0.5) * 0.038;
				var billow = tiled(a, c, 23, 4), fine = tiled(a, c, 49, 5);
				var rough = tiled(a, c, 103, 6), grain = tiled(a, c, 211, 7);
				var base = 0.50 * tiled(a, c, 4, 2) + 0.26 * tiled(a, c, 11, 3) + 0.22 * billow * billow + 0.15 * fine * fine;
				var erosion = 0.090 * (1 - rough) + 0.037 * (1 - grain);
				var i = (y * n + x) * 4;
				b.set(i, byte(base));
				b.set(i + 1, byte(tiled(u, v, 64, 8)));
				b.set(i + 2, byte(tiled(u, v, 64, 9)));
				b.set(i + 3, byte(erosion * 8));
			}
		var t = device.createTexture({width: n, height: n, data: b, mipLevels: 0});
		device.generateMips(t);
		return t;
	}

	static inline function byte(x:Float):Int
		return Std.int(Math.max(0, Math.min(255, x * 255 + 0.5)));

	static function tiled(u:Float, v:Float, period:Int, seed:Int):Float {
		var x = (u - Math.floor(u)) * period, y = (v - Math.floor(v)) * period;
		var ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
		var sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
		var jx = (ix + 1) % period, jy = (iy + 1) % period;
		inline function h(i:Int, j:Int)
			return hash(new Vec2(i + seed * 101, j + seed * 37));
		var a = h(ix, iy), b = h(jx, iy), c = h(ix, jy), d = h(jx, jy);
		var top = a + (b - a) * sx, bottom = c + (d - c) * sx;
		return top + (bottom - top) * sy;
	}
}
