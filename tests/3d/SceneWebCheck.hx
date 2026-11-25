import helder.gfx.*;
import helder.os.*;

// helder.scene's frames in a browser, on WebGPU or WebGL2 (web.mjs runs it
// in headless Chromium and compares the pixels with <scene>.png, as
// RenderCheck does natively):
//
//   SceneWebCheck headless <scene>   an offscreen target, drawn once by main
//   SceneWebCheck window <scene>     a canvas of 256x192 pixels, drawn by
//                                   App.run's frames from the browser's loop
class SceneWebCheck {
	static function main() {
		var mode = Sys.args()[0], scene = Sys.args()[1];
		if (mode == "headless") {
			var device = Device.create(Surface.headless(256, 192));
			var draw = Scenes.make(scene, device);
			draw(device.beginFrame());
			device.endFrame();
			Sys.println('SceneWebCheck: headless: ${device.width}x${device.height} (${name(device.backend)})');
			return;
		}
		var w = new Window("SceneWebCheck", 256, 192);
		var device = Device.create(w.surface);
		var draw = Scenes.make(scene, device);
		var frames = 0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc != null) {
				draw(enc);
				device.endFrame();
			}
			// (3 frames once the scene has what it draws: a lazy one loads first)
			if (Scenes.ready() && ++frames == 3) Sys.println('SceneWebCheck: window: 3 frames (${name(device.backend)})');
		}, e -> {});
	}

	static function name(b:Backend):String
		return switch b {
			case WebGPU: "WebGPU";
			case WebGL2: "WebGL2";
			case _: "?";
		}
}
