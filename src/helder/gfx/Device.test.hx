package helder.gfx;

import haxe.io.Bytes;
import helder.math.Vec4;
import helder.os.Surface;
import helder.test.Gen;
import helder.test.Test;

// readPixels of a render target in RGBA8 (frameInto): its bytes as they
// are, R, G, B, A. (Metal swapped red and blue for every target, as for its
// BGRA layer; a check reading a video frame that way swapped them back, and
// once #242 read RGBA8 targets as they are, compared red with blue)
function tests() {
	describe("Device", () -> {
		// (natively: a headless device)
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("readPixels: any colour cleared into an RGBA8 render target reads back as itself", () -> {
			var device = Device.create(Surface.headless(4, 4)), target = device.createTexture({width: 4, height: 4, renderTarget: true});
			property(int(0, 0xFFFFFF), rgb -> {
				var r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255, px = Bytes.alloc(4 * 4 * 4);
				device.frameInto(target);
				var enc = device.beginFrame();
				enc.beginPass({colors: [{load: Clear, clear: new Vec4(r / 255, g / 255, b / 255, 1)}]});
				enc.endPass();
				device.readPixels(px);
				device.endFrame();
				device.frameInto(null);
				equals([px.get(0), px.get(1), px.get(2), px.get(3)], [r, g, b, 255]);
			});
			device.dispose();
		});
		#end
	});
}
