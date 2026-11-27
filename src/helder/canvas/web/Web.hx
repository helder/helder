package helder.canvas.web;

// The DOM facade's canvases drawn by the browser's own Canvas 2D from now
// on (WebCanvas): `useWeb()` in helder/canvas, for a web build
// (wasm32 with src/helder/canvas/imports.mjs). A class apart: a program
// that never calls it keeps none of it.
class Web {
	public static function use() {
		// (natively an error, and WebCanvas not built: helder/canvas's
		// TypeScript declarations export useWeb on every target, and a native
		// program keeping the class linked its browser imports through the
		// painter's dispatch, which macOS can't load: the canvas lane's)
		#if (hxmc.target == "wasm32-wasi")
		helder.canvas.dom.Canvas.backend = (w, h) -> new WebCanvas(w, h);
		#else
		throw "useWeb: a web build's (wasm32-wasi)";
		#end
	}
}
