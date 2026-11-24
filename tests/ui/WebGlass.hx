import helder.ui.draw.UiWindow;

// Liquid Glass drawn in a browser (web-glass.mjs: wasm32-wasi in headless
// Chromium, on WebGPU and on WebGL2): GlassScene's stripes on a 400x300
// window, the fonts the page gives (DejaVu Sans, as GlassTest's golden)
class WebGlass {
	static function main() {
		var w = new UiWindow("Glass", GlassScene.W, GlassScene.H);
		GlassScene.build(w.root, "stripes");
		UiWindow.run();
	}
}
