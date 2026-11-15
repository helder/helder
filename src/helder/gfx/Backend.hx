package helder.gfx;

enum abstract Backend(Int) {
	// OpenGL ES 3.1 through EGL (Linux, Android; 3.0 where the driver has no
	// more: no compute then, Device.has)
	var GL;
	// Metal (macOS)
	var Metal;
	// Direct3D 11 (Windows)
	var D3D11;
	// WebGPU (the browser, WebAssembly)
	var WebGPU;
	// WebGL2 (the browser without WebGPU): the GL back end on OpenGL ES 3.0's
	// web counterpart (no compute: the fallback tier)
	var WebGL2;
}
