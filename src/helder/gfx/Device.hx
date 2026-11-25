package helder.gfx;

import helder.async.Errors;
import helder.os.Surface;
#if hxmc.dev
import helder.dev.Hot;
#end

// A GPU device rendering to one Surface (a window, or headless), with a
// depth buffer of the colour target's size. Resources are created up front;
// a frame is beginFrame, passes recorded through the Encoder, endFrame
// (present). Main thread only. Under hxmc dev a device is disposed with the
// build (helder.dev.Hot.onDispose) when the next one is swapped in.
// Every call is recorded (Commands) and run in order (Replay): here, at
// each call that may throw and each pass's end (synchronous: headless
// surfaces, tests, games by default), or on the render thread (the thread
// option: helder.ui's windows), which owns the context and presents. A
// thread's device hands over what it recorded at pass and frame ends while
// the thread is free, and waits for it at beginFrame (one frame on its way
// at most), at calls that answer (readPixels, createShader: their errors
// thrown there), at settle and at dispose.
@:hxmc.unsafe(gc)
final class Device {
	@:noCompletion public final backend:Backend;
	public final surface:Surface;

	final impl:Impl;
	final replay:Replay;
	final encoder:Encoder;
	// what is being recorded; the other, handed to the render thread last
	@:allow(helder.gfx.Encoder) var commands = new Commands();
	var spare = new Commands();
	#if (hxmc.target != "wasm32-wasi")
	final thread:Null<RenderThread>;
	#end
	// (the frame's size as the render thread's back end has it, at beginFrame)
	var w = 0;
	var h = 0;
	var frames = 0;
	var disposed = false;
	// (the handles given, by kind)
	var bufferIds = 0;
	var textureIds = 0;
	var samplerIds = 0;
	var shaderIds = 0;
	var pipelineIds = 0;
	var computeIds = 0;
	var queryIds = 0;
	final infos = new Map<Int, TextureInfo>();

	function new(surface:Surface, antialias:Bool, threaded:Bool) {
		this.surface = surface;
		impl = new Impl(surface, antialias);
		backend = impl.backend;
		replay = new Replay(impl);
		encoder = new Encoder(this);
		w = impl.width;
		h = impl.height;
		#if (hxmc.target != "wasm32-wasi")
		thread = threaded ? RenderThread.acquire() : null;
		if (thread != null) {
			// (GL: its context current on the render thread from now on)
			impl.detach();
			// (Android: what the back end lets go of when the system takes the window, let go there, before it goes)
			var lost = surface.lost;
			if (lost != null) surface.lost = () -> answer(_ -> lost());
		}
		#end
		#if hxmc.dev
		// (hxmc dev: a build swapped out releases its buffers, textures, samplers,
		// shaders and pipelines; the surface and the GPU device stay the host's)
		Hot.onDispose(dispose);
		#end
	}

	// antialias: a window's frames multisampled, 4 samples a pixel (in the
	// browser the page's run option antialias decides when it is set);
	// headless surfaces stay single-sampled, readPixels reads the frame
	// resolved; render targets are multisampled by their own samples
	// (TextureDesc.samples, resolved through ColorTarget.resolve). thread:
	// executed and presented on the render thread (a window's, natively;
	// helder.ui's windows ask for it); HELDER_RENDER_THREAD=0 turns it off,
	// =1 on for every window
	@:typescript public static function create(surface:Surface, ?options:{?antialias:Bool, ?thread:Bool}):Device
		return new Device(surface, options != null && options.antialias == true, threads(surface, options != null && options.thread == true));

	static function threads(surface:Surface, asked:Bool):Bool {
		#if (hxmc.target == "wasm32-wasi")
		return false;
		#else
		var env = Sys.getEnv("HELDER_RENDER_THREAD");
		if (surface.kind == Headless || env == "0") return false;
		return asked || env == "1";
		#end
	}

	// whether its commands run on the render thread
	public var threaded(get, never):Bool;

	inline function get_threaded()
		return #if (hxmc.target == "wasm32-wasi") false #else thread != null #end;

	// ---- running what was recorded

	// inline: run here; on the render thread: handed over once it is free
	// (idle: a pass's end, only when it already is and there is enough to
	// be worth its waking: a tile's pass alone costs less than that)
	@:allow(helder.gfx.Encoder) function flush(idle = false) {
		#if (hxmc.target != "wasm32-wasi")
		var t = thread;
		if (t != null) {
			if (idle && (commands.length < HANDOVER || !t.poll())) return;
			t.wait();
			settled();
			if (commands.length == 0) return;
			t.submit(replay, commands);
			var c = commands;
			commands = spare;
			spare = c;
			return;
		}
		#end
		if (commands.length == 0) return;
		try
			replay.run(commands, true)
		catch (e:haxe.Exception) {
			commands.clear();
			throw Errors.kept(e);
		}
		commands.clear();
		presented();
	}

	static inline var HANDOVER = 16 * 1024;

	// (inline: run at once, so that its errors are thrown by the call)
	inline function ran()
		if (!threaded) flush();

	// until what was recorded has run
	function sync() {
		flush();
		#if (hxmc.target != "wasm32-wasi")
		if (thread != null) {
			thread.wait();
			settled();
		}
		#end
	}

	// (the render thread done with the last commands: the other's to record
	// into, what threw there thrown here)
	function settled() {
		spare.clear();
		var e = replay.error;
		presented();
		if (e != null) {
			replay.error = null;
			throw Errors.carried(e);
		}
	}

	// (Metal: a frame presented; a macOS window shows itself at its first, here, on its thread)
	function presented()
		if (impl.presented() && surface.onPresent != null) surface.onPresent();

	// until what was handed to the render thread has run: the last frame
	// presented (synchronous: at once). helder.ui's loop waits so before it
	// takes the next events, so that a frame shows the input it was drawn
	// for, as without the thread; a program that does not, overlaps its next
	// frame with this one's present (a frame more on its way, its input older)
	@:typescript public function settle()
		if (threaded) sync();

	// f run where the back end is, in order with what was recorded, not
	// waited for (helder.ui's compositor: its frame handed over with the program's)
	@:noCompletion public function inOrder(f:Replay->Void) {
		commands.call(f);
		ran();
	}

	// work the render thread does between what the devices hand it (the
	// compositor's frames: helder.ui.layers.Compositor), with this device's
	// back end; false where there is no render thread (synchronous)
	@:noCompletion public function addIdle(i:RenderIdle):Bool {
		#if (hxmc.target != "wasm32-wasi")
		if (thread != null) {
			thread.addIdle(i, replay);
			return true;
		}
		#end
		return false;
	}

	@:noCompletion public function removeIdle(i:RenderIdle) {
		#if (hxmc.target != "wasm32-wasi")
		if (thread != null) thread.removeIdle(i);
		#end
	}

	// the render thread woken to ask its idle work when it is due (any thread)
	@:noCompletion public function wake() {
		#if (hxmc.target != "wasm32-wasi")
		if (thread != null) thread.wake();
		#end
	}

	// f run where the back end is, after what was recorded, waited for
	function answer(f:Replay->Void) {
		commands.call(f);
		sync();
	}

	public function createBuffer(d:BufferDesc):Buffer {
		var data = d.data;
		if (data != null && data.length < d.size) throw "helder.gfx: createBuffer: data has fewer than size bytes";
		var id = threaded ? ++bufferIds : 0, c = commands;
		c.begin(Replay.CREATE_BUFFER);
		c.int(id);
		c.int(d.size);
		c.int(cast d.usage);
		c.int(data != null ? 1 : 0);
		if (data != null) c.bytes(data, 0, d.size);
		c.end();
		ran();
		return new Buffer(id == 0 ? replay.made : id);
	}

	// size bytes of data from dataOffset (default: the rest) into the buffer
	// at offset, before the next commands: a frame's draws read what the
	// buffer holds when the frame is submitted (endFrame), so data that
	// changes within a frame goes to other offsets. A Storage or Indirect
	// buffer (one the GPU writes) is written after the frames committed
	// before are done (Metal waits for them: its buffers are shared memory)
	public function writeBuffer(b:Buffer, offset:Int, data:haxe.io.Bytes, dataOffset = 0, size = -1) {
		if (size < 0) size = data.length - dataOffset;
		if (dataOffset < 0 || offset < 0 || size < 0 || dataOffset + size > data.length) throw "helder.gfx: writeBuffer: outside the data";
		var c = commands;
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(offset);
		c.bytes(data, dataOffset, size);
		c.end();
		ran();
	}

	// the bytes of the textures alive: their levels' and samples', as their
	// formats store them (the GPU's own padding and alignment aside)
	@:noCompletion public var textureBytes(default, null) = 0.0;

	final textureSizes = new Map<Int, Float>();

	// (checked by the back end: TextureInfo.of)
	public function createTexture(d:TextureDesc):Texture {
		var info = TextureInfo.of(d), id = threaded ? ++textureIds : 0, c = commands, data = d.data;
		c.begin(Replay.CREATE_TEXTURE);
		c.int(id);
		c.int(d.width);
		c.int(d.height);
		c.int(d.format == null ? Replay.NONE : cast d.format);
		c.int(d.mipLevels == null ? Replay.NONE : d.mipLevels);
		c.int((d.renderTarget == true ? 1 : 0) | (d.storage == true ? 2 : 0) | (d.cube == true ? 4 : 0) | (data != null ? 8 : 0));
		c.int(d.samples == null ? Replay.NONE : d.samples);
		c.int(d.layers == null ? Replay.NONE : d.layers);
		// (each layer's first level: what the back ends upload of it)
		if (data != null) c.bytes(data, 0, Std.int(Math.min(data.length, info.format.levelBytes(info.width, info.height) * info.layers)));
		c.end();
		ran();
		if (id == 0) id = replay.made;
		infos.set(id, info);
		var t = new Texture(id);
		var format:TextureFormat = d.format == null ? RGBA8 : d.format;
		var levels = d.mipLevels == null ? 1 : d.mipLevels, bytes = 0.0, l = 0;
		while (levels == 0 ? (d.width | d.height) >> l != 0 : l < levels) {
			bytes += format.levelBytes(d.width >> l > 0 ? d.width >> l : 1, d.height >> l > 0 ? d.height >> l : 1);
			l++;
		}
		bytes *= (d.samples == null ? 1 : d.samples) * (d.layers != null ? d.layers : d.cube == true ? 6 : 1);
		textureSizes.set(t.id(), bytes);
		textureBytes += bytes;
		return t;
	}

	// texels into the texture's mip level (default 0), rows top to bottom:
	// all of them (its width * height * texelSize bytes), or the region w x h
	// at x, y (w * h * texelSize bytes from dataOffset), as a glyph atlas
	// updates the part that changed; not into a render target; layer: a 2D
	// array's or a cube's face (TextureDesc.layers, cube)
	public function writeTexture(t:Texture, data:haxe.io.Bytes, x = 0, y = 0, w = -1, h = -1, dataOffset = 0, level = 0, layer = 0) {
		var info = infos.get(t.id()), n = data.length - dataOffset;
		if (info != null) {
			info.checkWrite(data, x, y, w, h, dataOffset, level, layer);
			w = info.w;
			h = info.h;
			n = info.format.levelBytes(w, h);
		} else if (dataOffset < 0 || n < 0) throw "helder.gfx: writeTexture: outside the texture or the data";
		var c = commands;
		c.begin(Replay.WRITE_TEXTURE);
		c.int(t.id());
		c.int(x);
		c.int(y);
		c.int(w);
		c.int(h);
		c.int(level);
		c.int(layer);
		c.bytes(data, dataOffset, n);
		c.end();
		ran();
	}

	// whether its GPU samples textures of a format: the compressed ones (BC1,
	// BC3, ASTC4x4) where it has them (GL's extensions, WebGL2's, WebGPU's
	// features), the others everywhere
	public function supports(format:TextureFormat):Bool {
		var k:Int = cast format, v = supported.get(k);
		if (v == null) {
			var r = false;
			ask(_ -> r = impl.supports(format));
			supported.set(k, v = r);
		}
		return v;
	}

	final supported = new Map<Int, Bool>();
	final features = new Map<Int, Bool>();
	var maxSize = 0;
	var shares:Null<Null<String>> = null;
	var shareAsked = false;

	// (a fact of the back end: here inline, else where it runs)
	inline function ask(f:Replay->Void)
		if (threaded) answer(f) else f(replay);

	// whether it has a feature of the compute tier (Feature: Compute,
	// StorageTextures, Indirect): WebGPU, Metal, D3D11 at feature level
	// 11_0 and a GL ES 3.1 context do; WebGL2 and GL ES 3.0 do not (their
	// programs take the render stages' path)
	@:typescript public function has(feature:Feature):Bool {
		var k:Int = cast feature, v = features.get(k);
		if (v == null) {
			var r = false;
			ask(_ -> r = impl.has(feature));
			features.set(k, v = r);
		}
		return v;
	}

	// the largest side of a 2D texture it creates: GL's and WebGL2's asked
	// (phones' often 4096), WebGPU's device limit (8192 by default), Metal's
	// and D3D11's 16384 (Apple's GPUs since A9, feature level 11)
	public var maxTextureSize(get, never):Int;

	function get_maxTextureSize() {
		if (maxSize == 0) ask(_ -> maxSize = impl.maxTextureSize());
		return maxSize;
	}

	// whether textures are filled from images the browser decoded
	// (writeTextureImage; helder.gfx.ImageTexture): in a browser
	@:noCompletion public var decodesImages(get, never):Bool;

	inline function get_decodesImages()
		return hxmc.Platform.os() == 3;

	// the texture (RGBA8 or RGBA8Srgb, not a render target, the image's
	// size) filled from a browser image (helder.image.WebImages' handle): at
	// once when the browser decoded it, else when it has (the texture blank
	// until then); its mip levels after the first generated then; release:
	// the image freed after. Only where decodesImages
	@:noCompletion public function writeTextureImage(t:Texture, image:Int, release = false) {
		var c = commands;
		c.begin(Replay.WRITE_TEXTURE_IMAGE);
		c.int(t.id());
		c.int(image);
		c.int(release ? 1 : 0);
		c.end();
		ran();
	}

	// the texture's mip levels after the first, each filtered down from the
	// one before (GL's glGenerateMipmap, D3D11's GenerateMips, Metal's blit,
	// a pass on WebGPU); outside a pass, after the first level was written or
	// rendered (not R32F or a depth format)
	public function generateMips(t:Texture) {
		one(Replay.GENERATE_MIPS, t.id());
		ran();
	}

	// (a command of one argument)
	inline function one(op:Int, v:Int) {
		var c = commands;
		c.begin(op);
		c.int(v);
		c.end();
	}

	// ---- shared textures (helder.story's native preview host: its frames
	// drawn into textures another process samples, without copies)
	//
	// sharing: how this device shares a texture with another process:
	// "iosurface" (Metal: an IOSurface, found by its id), "dxgi" (Direct3D 11:
	// a texture with a keyed mutex, by its DXGI shared handle), "dmabuf" (GL:
	// a dma-buf exported through EGL_MESA_image_dma_buf_export, the other
	// process taking its file descriptor with pidfd_getfd, imported with
	// EGL_EXT_image_dma_buf_import); null: none (WebGPU, WebGL2, Android, an
	// EGL without those extensions: llvmpipe without udmabuf), a copy then.
	@:noCompletion public var sharing(get, never):Null<String>;

	function get_sharing() {
		if (!shareAsked) {
			ask(_ -> shares = impl.sharing());
			shareAsked = true;
		}
		return shares;
	}

	// a render target of width x height another process opens (openShared):
	// the frame drawn into with frameInto, its handle a string to give that
	// process (null: this device cannot share). The texture's format is the
	// frame's (Metal: BGRA8, sampled as RGBA); destroyed by destroyTexture.
	@:noCompletion public function createShared(width:Int, height:Int):Null<{texture:Texture, handle:String}> {
		var id = threaded ? ++textureIds : 0, handle:Null<String> = null;
		answer(r -> {
			var made = r.impl.createShared(width, height);
			if (made == null) return;
			r.make(r.textures, id, made.id);
			handle = made.handle;
		});
		if (handle == null) return null;
		if (id == 0) id = replay.made;
		textureSizes.set(id, width * height * 4.0);
		textureBytes += width * height * 4.0;
		return {texture: new Texture(id), handle: handle};
	}

	// another process's shared texture (its createShared's handle, its
	// size), sampled like any texture (null: it cannot be opened here: its
	// process gone, another kind of handle); destroyed by destroyTexture
	// (the memory is the other process's too: freed when both let go).
	// Synchronised: a Direct3D 11 frame holds its keyed mutex from the
	// first draw that samples it to endFrame; Metal and GL rely on the
	// producer's frame being complete before it hands the handle over (its
	// endFrame waits for the GPU) and on the producer not drawing into a
	// texture this one samples (helder.story's buffers)
	@:noCompletion public function openShared(handle:String, width:Int, height:Int):Null<Texture> {
		var id = threaded ? ++textureIds : 0, opened = 0;
		answer(r -> r.make(r.textures, id, opened = r.impl.openShared(handle, width, height)));
		return opened == 0 ? null : new Texture(id == 0 ? opened : id);
	}

	// the next frames drawn into t (a shared texture, or a render target of
	// the frame's format) instead of the surface: beginFrame to endFrame at
	// its size, its passes without a colour texture into it, readPixels
	// reading it; null: the surface again. A frame into a shared texture
	// waits for the GPU at endFrame (its pixels complete for the other process)
	@:noCompletion public function frameInto(t:Null<Texture>) {
		one(Replay.FRAME_INTO, t == null ? 0 : t.id());
		ran();
	}

	// frees a buffer or a texture (its handle is not used again)
	public function destroyBuffer(b:Buffer) {
		one(Replay.DESTROY_BUFFER, b.id());
		ran();
	}

	public function destroyTexture(t:Texture) {
		var bytes = textureSizes.get(t.id());
		if (bytes != null) {
			textureBytes -= bytes;
			textureSizes.remove(t.id());
		}
		infos.remove(t.id());
		one(Replay.DESTROY_TEXTURE, t.id());
		ran();
	}

	public function createSampler(d:SamplerDesc):Sampler {
		var id = threaded ? ++samplerIds : 0, c = commands;
		c.begin(Replay.CREATE_SAMPLER);
		c.int(id);
		c.int(d.filter == null ? Replay.NONE : cast d.filter);
		c.int(d.mipFilter == null ? Replay.NONE : cast d.mipFilter);
		c.int(d.wrap == null ? Replay.NONE : cast d.wrap);
		c.end();
		ran();
		return new Sampler(id == 0 ? replay.made : id);
	}

	// throws the compiler's log when the source does not compile
	public function createShader(d:ShaderDesc):Shader {
		var id = threaded ? ++shaderIds : 0;
		answer(r -> r.make(r.shaders, id, r.impl.createShader(d)));
		return new Shader(id == 0 ? replay.made : id);
	}

	// a compute stage's pipeline (a ComputeShader's pipeline(); d.program: its
	// shader created first); throws where the device has no compute
	// (has(Compute))
	public function createComputePipeline(d:ComputePipelineDesc):ComputePipeline {
		if (!has(Compute)) throw "helder.gfx: createComputePipeline: this device has no compute stages (" + backend + ")";
		var s = (d.shader != null ? d.shader : createShader({stage: Compute, code: d.program})).id(), id = threaded ? ++computeIds : 0;
		answer(r -> r.make(r.computes, id, r.impl.createComputePipeline(Replay.at(r.shaders, s))));
		return new ComputePipeline(id == 0 ? replay.made : id);
	}

	// size bytes (default: the rest of dst from dstOffset) of a buffer at
	// offset into dst: what the GPU wrote there (a compute stage's storage),
	// after the work recorded before it, which it waits for (tests, a
	// result the CPU needs; in a frame or outside one); WebGPU reads back
	// asynchronously only (readBuffer in src/helder/gfx/imports.mjs)
	public function readBuffer(b:Buffer, offset:Int, dst:haxe.io.Bytes, dstOffset = 0, size = -1) {
		if (size < 0) size = dst.length - dstOffset;
		if (offset < 0 || dstOffset < 0 || dstOffset + size > dst.length) throw "helder.gfx: readBuffer: outside dst";
		var id = b.id();
		answer(r -> r.impl.readBuffer(Replay.at(r.buffers, id), offset, dst, dstOffset, size));
	}

	// ---- occlusion queries (every back end: GL ES 3.0's and WebGL2's
	// ANY_SAMPLES_PASSED_CONSERVATIVE, WebGPU's occlusion query sets, Metal's
	// visibility results, D3D11's occlusion queries)
	//
	// count queries, each counting whether any sample of the draws inside
	// it passed the depth test: a pass naming the set (PassDesc.queries),
	// Encoder.beginQuery(k) ... endQuery() about its draws, answered a frame
	// or more later by queryResult, never waited for
	public function createQueries(count:Int):QuerySet {
		if (count <= 0) throw "helder.gfx: createQueries: count must be positive";
		var id = threaded ? ++queryIds : 0, c = commands;
		c.begin(Replay.CREATE_QUERIES);
		c.int(id);
		c.int(count);
		c.end();
		ran();
		if (threaded) answers.set(id, [for (_ in 0...count) -1]);
		return new QuerySet(id == 0 ? replay.made : id);
	}

	public function destroyQueries(q:QuerySet) {
		one(Replay.DESTROY_QUERIES, q.id());
		answers.remove(q.id());
		ran();
	}

	// (the render thread's: every set's answers as they were at the first
	// question of a frame, asked again at the next; answers come a frame or
	// more later anyway)
	final answers = new Map<Int, Array<Int>>();
	var answered = -1;

	// query k's last answer: 1 some sample passed, 0 none, -1 none yet (not
	// begun, or its first answer still on its way); a query begun again
	// before its last answer came is not begun (its draws drawn, uncounted),
	// so an answer always comes
	public function queryResult(q:QuerySet, k:Int):Int {
		var id = q.id();
		if (!threaded) {
			flush();
			return impl.queryResult(Replay.at(replay.queries, id), k);
		}
		if (answered != frames) {
			answered = frames;
			var all = answers;
			answer(r -> for (s => a in all)
				for (i in 0...a.length)
					a[i] = r.impl.queryResult(Replay.at(r.queries, s), i));
		}
		var a = answers.get(id);
		return a == null || k < 0 || k >= a.length ? -1 : a[k];
	}

	// query k's last answer let go (-1 until one begun after this comes;
	// one on its way now is let go too): what was out of view since
	public function resetQuery(q:QuerySet, k:Int) {
		var c = commands;
		c.begin(Replay.RESET_QUERY);
		c.int(q.id());
		c.int(k);
		c.end();
		ran();
		var a = answers.get(q.id());
		if (a != null && k >= 0 && k < a.length) a[k] = -1;
	}

	// (d.program: its shaders created first)
	public function createPipeline(d:PipelineDesc):Pipeline {
		if (d.program != null)
			d = {
				vertex: createShader({stage: Vertex, code: d.program.vertex}),
				fragment: createShader({stage: Fragment, code: d.program.fragment}),
				layout: d.layout,
				topology: d.topology,
				cull: d.cull,
				blend: d.blend,
				depthCompare: d.depthCompare,
				depthWrite: d.depthWrite,
				colorFormat: d.colorFormat,
				depthFormat: d.depthFormat,
				samples: d.samples
			};
		var vs = d.vertex == null ? 0 : d.vertex.id(), fs = d.fragment == null ? 0 : d.fragment.id(), id = threaded ? ++pipelineIds : 0;
		var layout = d.layout, topology = d.topology, cull = d.cull, blend = d.blend, depthCompare = d.depthCompare, depthWrite = d.depthWrite,
			colorFormat = d.colorFormat, depthFormat = d.depthFormat, samples = d.samples;
		answer(r -> r.make(r.pipelines, id, r.impl.createPipeline({
			vertex: vs == 0 ? null : new Shader(Replay.at(r.shaders, vs)),
			fragment: fs == 0 ? null : new Shader(Replay.at(r.shaders, fs)),
			layout: layout,
			topology: topology,
			cull: cull,
			blend: blend,
			depthCompare: depthCompare,
			depthWrite: depthWrite,
			colorFormat: colorFormat,
			depthFormat: depthFormat,
			samples: samples
		})));
		return new Pipeline(id == 0 ? replay.made : id);
	}

	// the frame's encoder (the same object each frame); null: no frame now
	// (a hidden window: Metal has no drawable for it), skip it
	@:typescript public function beginFrame():Null<Encoder> {
		commands.begin(Replay.BEGIN_FRAME);
		commands.end();
		sync();
		w = impl.width;
		h = impl.height;
		frames++;
		return replay.began ? encoder : null;
	}

	// what the frame presented next changed: rectangles x0, y0, x1, y1 in
	// its pixels, rows from the top (a window's kept frame: Renderer.regions;
	// null: all of it), told the system where it takes them as it presents
	// (EGL_KHR/EXT_swap_buffers_with_damage: Wayland's damage_buffer,
	// Android's; DXGI's Present1 dirty rectangles), so that it composites
	// only those; its frame drawn whole still
	public function damaged(rects:Null<Array<Int>>) {
		var c = commands;
		c.begin(Replay.DAMAGED);
		c.int(rects == null ? -1 : rects.length);
		if (rects != null) for (v in rects)
			c.int(v);
		c.end();
	}

	// (until the window's next frame is taken without queueing it behind
	// another: Windows' swap chain, one frame queued at most; helder.ui's
	// window waits so before a turn's input, the frame after shown at the
	// next vsync, and the frame waits for nothing more; elsewhere nothing)
	@:noCompletion public function waitFrame() {
		#if (!helder.os || helder.os == "windows")
		if (hxmc.Platform.os() == 2) answer(r -> r.impl.waitFrame());
		#end
	}

	// submits the frame and presents it
	@:typescript public function endFrame() {
		#if helder.headless
		// (a headless run's window: its frame read before it is presented, for the run's outputs)
		if (surface.kind == Headless) helder.os.headless.Headless.run.present(surface, width, height, readPixels);
		#end
		commands.begin(Replay.END_FRAME);
		commands.end();
		flush();
		// (a window not shown yet: shown once this frame is presented, not at the next's)
		if (threaded && surface.onPresent != null) sync();
	}

	// the frame's colour target as RGBA8, rows top to bottom (width * height
	// * 4 bytes into dst), after the passes and before endFrame; waits for
	// the GPU (tests and screenshots)
	@:typescript public function readPixels(dst:haxe.io.Bytes)
		answer(r -> r.impl.readPixels(dst));

	// the size of the colour target in pixels
	@:typescript public var width(get, never):Int;
	@:typescript public var height(get, never):Int;

	inline function get_width()
		return threaded ? w : impl.width;

	inline function get_height()
		return threaded ? h : impl.height;

	// what was recorded run (on the render thread: drained), then everything
	// let go, the context too
	@:typescript public function dispose() {
		if (disposed) return;
		disposed = true;
		try {
			commands.call(r -> r.impl.dispose());
			sync();
		} catch (e:haxe.Exception) {
			release();
			throw Errors.kept(e);
		}
		release();
	}

	function release() {
		#if (hxmc.target != "wasm32-wasi")
		if (thread != null) thread.release();
		#end
		commands.free();
		spare.free();
	}
}
