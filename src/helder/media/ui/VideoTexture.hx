package helder.media.ui;

import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.gfx.Device;
import helder.gfx.Encoder;
import helder.gfx.Pipeline;
import helder.gfx.Sampler;
import helder.gfx.Texture;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.media.VideoFrame;
import helder.media.ui.VideoShader;

// A video's frames as an RGBA texture of their size upright (target), each
// converted from its planes in a pass of its own (VideoShader): the planes
// are the decoder's surfaces opened as textures (Device.openShared: Apple's
// IOSurfaces, no copy), kept by their handle while the decoder's pool
// reuses them (at most KEEP; one not used for long let go); in a browser
// the frame copied into an RGBA texture on the GPU first; on Android the
// decoder's AHardwareBuffer sampled as an external texture, its YUV the
// driver's to convert
class VideoTexture {
	static inline var KEEP = 24;

	public var target(default, null):Null<Texture>;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final device:Device;
	final pipeline:Pipeline;
	final triangle:Buffer;
	final sampler:Sampler;
	final bytes = Bytes.alloc(64);
	final planes = new Map<String, Texture>();
	final used:Array<String> = [];
	final retired:Array<Texture> = [];
	var luma:Null<Texture>;
	var chroma:Null<Texture>;

	public function new(device:Device) {
		this.device = device;
		var desc = VideoShader.pipeline({});
		desc.colorFormat = RGBA8;
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (hxmc.Platform.target() >= 9) desc = external(desc);
		#end
		pipeline = device.createPipeline(desc);
		var v = VideoShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
	}

	// f's pass made ready (record it, Renderer.beforePass): false when its
	// planes cannot be opened here (no such textures: another back end)
	public function prepare(f:VideoFrame, rotation:Int):Bool {
		var turned = rotation == 90 || rotation == 270;
		var w = turned ? f.height : f.width, h = turned ? f.width : f.height;
		if (target == null || w != width || h != height) {
			if (target != null) retired.push(target);
			target = device.createTexture({width: w, height: h, renderTarget: true});
			width = w;
			height = h;
		}
		#if (hxmc.target == "wasm32-wasi")
		return browser(f, rotation);
		#else
		#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
		if (hxmc.Platform.target() >= 9) return android(f, rotation);
		#end
		luma = open(f.plane(0), f.width, f.height);
		chroma = open(f.plane(1), (f.width + 1) >> 1, (f.height + 1) >> 1);
		if (luma == null || chroma == null) return false;
		var m = matrix(f);
		VideoShader.params.video.write({
			r: m[0],
			g: m[1],
			b: m[2],
			turn: new Vec4(Std.int(rotation / 90) & 3, 0.25 / ((f.width + 1) >> 1), 0, 0)
		}, bytes);
		return true;
		#end
	}

	#if (hxmc.target == "wasm32-wasi")
	var rgb:Null<Texture>;
	var rgbWidth = 0;
	var rgbHeight = 0;

	// (the browser's frame, a VideoFrame or <video>, copied into an RGBA
	// texture on the GPU (Device.writeTextureImage: copyExternalImageToTexture,
	// texImage2D; the browser converts its colours), then turned as planes
	// are; WebGPU's importExternalTexture would save the copy, but its
	// texture lasts a task only and needs a binding of its own)
	function browser(f:VideoFrame, rotation:Int):Bool {
		var t = rgb;
		if (t == null || rgbWidth != f.width || rgbHeight != f.height) {
			if (t != null) retired.push(t);
			t = rgb = device.createTexture({width: f.width, height: f.height});
			rgbWidth = f.width;
			rgbHeight = f.height;
		}
		device.writeTextureImage(t, f.handle());
		luma = chroma = t;
		VideoShader.params.video.write({
			r: new Vec4(1, 0, 0, 0),
			g: new Vec4(0, 1, 0, 0),
			b: new Vec4(0, 0, 1, 0),
			turn: new Vec4(Std.int(rotation / 90) & 3, 1, 1, 1)
		}, bytes);
		return true;
	}
	#end

	#if ((!helder.os || helder.os == "android") && hxmc.target != "wasm32-wasi")
	// (Android's pass: the decoder's AHardwareBuffers as external textures,
	// samplerExternalOES, the driver converting their YUV as the codec
	// tagged them; GLSL ES's, the shader's own otherwise)
	static function external(desc:helder.gfx.PipelineDesc):helder.gfx.PipelineDesc {
		var f = VideoShader.fragmentCode, glsl = f.glsl ?? "";
		glsl = StringTools.replace(glsl, "sampler2D", "samplerExternalOES");
		glsl = StringTools.replace(glsl, "#version 300 es\n", "#version 300 es\n#extension GL_OES_EGL_image_external_essl3 : require\n");
		return {program: {vertex: VideoShader.vertexCode, fragment: {glsl: glsl, bindings: f.bindings}}, layout: desc.layout, colorFormat: RGBA8};
	}

	// (f's buffer, opened the first time it comes (the decoder's pool
	// reuses them), its crop the share sampled, turned as planes are)
	function android(f:VideoFrame, rotation:Int):Bool {
		var h = f.plane(0);
		if (h == null) return false;
		var at = h.split(":"), bw = Std.parseInt(at[2]) ?? f.width, bh = Std.parseInt(at[3]) ?? f.height;
		var t = open(h, bw, bh);
		if (t == null) return false;
		luma = chroma = t;
		VideoShader.params.video.write({
			r: new Vec4(1, 0, 0, 0),
			g: new Vec4(0, 1, 0, 0),
			b: new Vec4(0, 0, 1, 0),
			turn: new Vec4(Std.int(rotation / 90) & 3, f.width / bw, 1, f.height / bh)
		}, bytes);
		return true;
	}
	#end

	// (a plane's texture, opened the first time its surface comes)
	function open(handle:Null<String>, w:Int, h:Int):Null<Texture> {
		if (handle == null) return null;
		var t = planes.get(handle);
		used.remove(handle);
		used.push(handle);
		if (t != null) return t;
		t = device.openShared(handle, w, h);
		if (t == null) return null;
		planes.set(handle, t);
		while (used.length > KEEP) {
			var old = used.shift(), o = planes.get(old);
			planes.remove(old);
			if (o != null) retired.push(o);
		}
		return t;
	}

	public function record(enc:Encoder) {
		var t = target, l = luma, c = chroma;
		if (t == null || l == null || c == null) return;
		enc.beginPass({colors: [{load: DontCare, texture: t}]});
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, triangle);
		enc.setUniforms(VideoShader.uniforms[0].binding, bytes);
		enc.setTexture(VideoShader.textures[0].binding, l, sampler);
		enc.setTexture(VideoShader.textures[1].binding, c, sampler);
		enc.draw(3);
		enc.endPass();
		// (what was let go before this frame: done with once this pass was recorded after it)
		for (o in retired) device.destroyTexture(o);
		retired.resize(0);
	}

	// Y'CbCr to R'G'B' for its matrix, range and depth: rows over the
	// sampled Y', Cb, Cr and 1 (P010's 10 bits at the top of 16: read as
	// v * 64 / 65535)
	public static function matrix(f:VideoFrame):Array<Vec4> {
		var kr = 0.299, kb = 0.114;
		if (f.matrix == "709") {
			kr = 0.2126;
			kb = 0.0722;
		} else if (f.matrix == "2020") {
			kr = 0.2627;
			kb = 0.0593;
		}
		var kg = 1 - kr - kb;
		var deep = f.bits > 8, top = deep ? 1023.0 : 255.0, read = deep ? 65535.0 / 64 : 255.0;
		// (video range: Y' from 16 to 235, C from 16 to 240 around 128, in units of the depth's 256ths)
		var unit = (top + 1) / 256, ys = f.full ? top : 219 * unit, cs = f.full ? top : 224 * unit;
		var ya = read / ys, yb = f.full ? 0.0 : -16 * unit / ys;
		var ca = read / cs, cb = -128 * unit / cs;
		var rv = 2 * (1 - kr), bu = 2 * (1 - kb), gu = -2 * kb * (1 - kb) / kg, gv = -2 * kr * (1 - kr) / kg;
		return [
			new Vec4(ya, 0, rv * ca, yb + rv * cb),
			new Vec4(ya, gu * ca, gv * ca, yb + (gu + gv) * cb),
			new Vec4(ya, bu * ca, 0, yb + bu * cb)
		];
	}

	public function dispose() {
		#if (hxmc.target == "wasm32-wasi")
		if (rgb != null) device.destroyTexture(rgb);
		rgb = null;
		#end
		for (t in planes) device.destroyTexture(t);
		planes.clear();
		for (t in retired) device.destroyTexture(t);
		retired.resize(0);
		if (target != null) device.destroyTexture(target);
		target = null;
		device.destroyBuffer(triangle);
	}
}
