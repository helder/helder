package helder.ui.draw;

import helder.gfx.Device;
import helder.gfx.PassDesc;
import helder.os.Surface;
import helder.image.Image;
import helder.test.Test;

// The renderer's textures given back when the system wants memory (trim:
// helder.os.App.lowMemory, an iOS app gone to the background): an image
// not drawn in the last frame lets its texture go, one drawn keeps it, and
// one drawn again is uploaded again
function tests() {
	describe("Renderer", () -> {
		test("trim: what the last frame did not draw let go", () -> {
			var device = Device.create(Surface.headless(64, 64)), r = new Renderer(device);
			// (larger than a page's images: a texture each)
			var a = new Image(300, 300), b = new Image(300, 300);
			function frame(images:Array<Image>) {
				var enc = device.beginFrame();
				enc.beginPass(({colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]} : PassDesc));
				r.begin(64, 64);
				for (img in images)
					r.image(img, 0, 0, 32, 32, 0, 0, 1, 1, 0);
				r.end(enc);
				enc.endPass();
				device.endFrame();
			}
			var none = device.textureBytes;
			frame([a, b]);
			var both = device.textureBytes;
			assert(both - none >= 2 * 300 * 300 * 4, 'both uploaded: ${both - none} bytes');
			frame([a]);
			r.trim();
			equals(device.textureBytes, both - 300 * 300 * 4);
			frame([a, b]);
			equals(device.textureBytes, both);
			device.dispose();
		});
	});
}
