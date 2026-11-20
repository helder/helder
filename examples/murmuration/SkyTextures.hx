import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import SkyShader;

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
}
