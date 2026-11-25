import helder.ui.UiWindow;

// Liquid Glass drawn in a browser (web-glass.mjs: wasm32-wasi in headless
// Chromium, on WebGPU and on WebGL2): GlassScene's stripes on a 400x300
// window, as GlassCheck's golden draws it (its own Inter)
class WebGlass {
	static function main() {
		var w = new UiWindow("Glass", GlassScene.W, GlassScene.H);
		GlassScene.build(w.root, "stripes", true, true, true);
		UiWindow.run();
	}
}
