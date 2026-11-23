package helder.gfx.metal;

import helder.gfx.*;
import helder.gfx.metal.Metal;
import helder.os.Surface;
import helder.os.objc.*;
import hxmc.unsafe.*;

// The Metal back end (macOS): the system's default device and a command
// queue, rendering to a window's CAMetalLayer (each frame to its next
// drawable) or, headless, to an offscreen texture. A frame is a command
// buffer in an autorelease pool, a pass a render command encoder. Shaders
// are MSL compiled at run time (newLibraryWithSource), their entry point
// main0; vertex buffer slots are buffer indices VERTEX_BUFFERS + slot (the
// lower ones are the uniform blocks' slots: setUniforms copies a block
// into the command stream, setVertexBytes and setFragmentBytes, at most
// 4 KB). The colour target is BGRA8 (the layer's own format): readPixels
// swaps it to RGBA. The depth buffer is a Depth32Float texture of the target's size,
// remade when the drawable's size changes. A texture at slot n is [[texture(n)]] and its
// sampler [[sampler(n)]], in both stages. A render target is a texture in
// the GPU's memory (StorageModePrivate); generateMips is a blit. With
// antialias a window's frame is multisampled (4 samples a pixel): its
// passes render into a multisampled colour texture beside the depth buffer,
// resolved into the drawable at each pass's end (and kept, for a next
// pass's Load), the frame's pipelines (no colorFormat) made for it; render
// targets and headless targets stay single-sampled.
// The compute tier: a compute pass is a compute command encoder (serial
// dispatches: each sees what the ones before wrote; Metal orders the
// encoders after it) in the frame's command buffer, else in one of its own
// committed at endCompute; its uniform blocks setBytes, its storage buffers
// setBuffer at their slots, its textures (storage ones ShaderWrite) at
// theirs; a dispatch gives the workgroup's size (ShaderCode.workgroupSize).
// readBuffer commits the frame's work so far and waits for it (as
// readPixels), then copies from the buffer's shared memory.
// The system's layers (helder.ui.draw.CaLayers): a frame may be drawn onto
// another CAMetalLayer of the window (planeFrame), single-sampled, the
// frame's pipelines made again for it without depth, its drawable kept to
// be presented with the Core Animation transaction that places the layer
// (takePresents); the window's own frames then take no drawable (quiet),
// only rendering into targets (tiles, groups), as the layers are drawn
// from what they rendered.
@:hxmc.unsafe(gc)
class MetalBackend {
	public final backend = Backend.Metal;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final device:Ptr;
	final queue:Ptr;
	final layer:Ptr; // Cocoa: the CAMetalLayer
	final target:Ptr; // headless: the colour texture
	final pass:Ptr; // MTLRenderPassDescriptor, reused
	final attachment:Ptr; // its colour attachment 0
	final depthAttachment:Ptr; // and its depth attachment
	var depth = Ptr.nil(); // the depth texture, of depthWidth x depthHeight
	var depthWidth = 0;
	var depthHeight = 0;
	final samples:Int; // the frame's samples a pixel
	var msaa = Ptr.nil(); // multisampled: the frame's colour texture, of the depth's size
	// native memory: an out-parameter, the structs passed by value
	final scratch:Ptr<Ptr>;
	final clear:Ptr<MTLClearColor>;
	final viewport:Ptr<MTLViewport>;
	final origin:Ptr<MTLOrigin>;
	final size:Ptr<MTLSize>;
	final uniforms:Ptr<UInt8>; // a block on its way to setVertexBytes (MAX_BYTES)
	var readback = Ptr.nil(); // readPixels' MTLBuffer
	final region:Ptr<MTLRegion>; // writeTexture's
	var readbackSize = 0;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = [];
	// (Storage and Indirect buffers: the GPU writes them, writeBuffer waits for the work committed)
	final gpuWritten:Array<Bool> = [];
	// the last command buffer committed (retained), which such a write waits for
	var inFlight = Ptr.nil();
	final shaders:Array<Ptr> = []; // MTLFunction
	final libraries:Array<Ptr> = [];
	final pipelines:Array<MtlPipeline> = [];
	final textures:Array<Ptr> = []; // MTLTexture
	final infos:Array<TextureInfo> = [];
	final samplers:Array<Ptr> = []; // MTLSamplerState
	final computes:Array<MtlCompute> = [];
	final workgroups = new Map<Int, Array<Int>>(); // the compute shaders' workgroup sizes
	// a compute pass: its encoder, its pipeline, whether its command buffer is its own; the dispatch's sizes
	var computeEnc = Ptr.nil();
	var computePipeline:Null<MtlCompute> = null;
	var ownCompute = false;
	final groupSize:Ptr<MTLSize>;
	final threadSize:Ptr<MTLSize>;

	// the frame
	var pool = Ptr.nil();
	var cmd = Ptr.nil();
	var drawable = Ptr.nil();
	var texture = Ptr.nil();
	var enc = Ptr.nil();
	var pipeline:MtlPipeline = null;
	// drawIndexed's index buffer, type (MTL.IndexType*) and offset
	var ibuf = Ptr.nil();
	var itype = 0;
	var ioffset = 0;

	// frameInto's texture (0: the surface's), the headless target's size, the
	// textures made by createShared (their frames waited for at endFrame)
	var frameTarget = 0;
	var targetWidth = 0;
	var targetHeight = 0;
	final shared = new Map<Int, Bool>();

	// (the system's layers: the window's frames drawing onto no drawable;
	// planeFrame's layer, the next frame onto it; whether this one is; the
	// drawables drawn, presented with the transaction)
	public var quiet = false;
	// (the GPU's time on the command buffers that completed before the next was committed: a bench's)
	@:noCompletion public var gpuSeconds = 0.0;
	var plane = Ptr.nil();
	var planing = false;
	final presents:Array<Ptr> = [];

	static inline var VERTEX_BUFFERS = 16;
	static inline var MAX_SLOTS = 8;
	static inline var MAX_BYTES = 4096;

	public function new(surface:Surface, antialias:Bool) {
		this.surface = surface;
		samples = antialias && surface.kind == Cocoa ? 4 : 1;
		var pool = Runtime.objc_autoreleasePoolPush();
		device = Metal.MTLCreateSystemDefaultDevice();
		if (device.isNull()) throw "helder.gfx: no Metal device";
		queue = Msg.id(device, ObjC.sel("newCommandQueue"));
		scratch = LibC.malloc(8);
		clear = LibC.malloc(32);
		viewport = LibC.malloc(48);
		origin = LibC.malloc(24);
		size = LibC.malloc(24);
		region = LibC.malloc(48);
		uniforms = LibC.malloc(MAX_BYTES);
		groupSize = LibC.malloc(24);
		threadSize = LibC.malloc(24);
		pass = make("MTLRenderPassDescriptor");
		attachment = Msg.idInt(Msg.id(pass, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		depthAttachment = Msg.id(pass, ObjC.sel("depthAttachment"));
		if (surface.kind == Cocoa) {
			layer = surface.display;
			target = Ptr.nil();
			Msg.vPtr(layer, ObjC.sel("setDevice:"), device);
			Msg.vInt(layer, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
			// (readPixels copies from the drawable's texture)
			Msg.vBool(layer, ObjC.sel("setFramebufferOnly:"), false);
		} else {
			layer = Ptr.nil();
			var d = make("MTLTextureDescriptor");
			Msg.vInt(d, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
			Msg.vInt(d, ObjC.sel("setWidth:"), surface.width);
			Msg.vInt(d, ObjC.sel("setHeight:"), surface.height);
			Msg.vInt(d, ObjC.sel("setUsage:"), MTL.TextureUsageRenderTarget);
			Msg.vInt(d, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
			target = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), d);
			Runtime.objc_release(d);
			if (target.isNull()) throw "helder.gfx: cannot create a " + surface.width + "x" + surface.height + " texture";
		}
		width = targetWidth = surface.width;
		height = targetHeight = surface.height;
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// ---- shared textures: IOSurfaces (Device.createShared, openShared)

	public function sharing():Null<String>
		return "iosurface";

	// an IOSurface (BGRA, global: looked up by its id from another process)
	// and a render target on it, of the frame's format
	public function createShared(w:Int, h:Int):Null<{id:Int, handle:String}> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var dict = Msg.id(ObjC.cls("NSMutableDictionary"), ObjC.sel("dictionary"));
		function set(key:String, value:Ptr) {
			var k = ObjC.str(key);
			Msg.vPtrPtr(dict, ObjC.sel("setObject:forKey:"), value, k);
			ObjC.release(k);
		}
		inline function num(v:Int):Ptr
			return Msg.idInt(ObjC.cls("NSNumber"), ObjC.sel("numberWithInt:"), v);
		set("IOSurfaceWidth", num(w));
		set("IOSurfaceHeight", num(h));
		set("IOSurfaceBytesPerElement", num(4));
		set("IOSurfacePixelFormat", num(0x42475241)); // 'BGRA'
		set("IOSurfaceIsGlobal", Msg.idInt(ObjC.cls("NSNumber"), ObjC.sel("numberWithBool:"), 1));
		var surf = IOSurface.IOSurfaceCreate(dict);
		Runtime.objc_autoreleasePoolPop(pool);
		if (surf.isNull()) return null;
		var t = surfaceTexture(surf, w, h, MTL.TextureUsageShaderReadRenderTarget);
		var id = IOSurface.IOSurfaceGetID(surf);
		// (the texture keeps the surface)
		MtlCF.CFRelease(surf);
		if (t.isNull()) return null;
		textures.push(t);
		infos.push(TextureInfo.of({width: w, height: h, renderTarget: true}));
		shared.set(textures.length, true);
		return {id: textures.length, handle: "iosurface:" + id};
	}

	public function openShared(handle:String, w:Int, h:Int):Int {
		if (!StringTools.startsWith(handle, "iosurface:")) return 0;
		var n = Std.parseInt(handle.substr(10));
		if (n == null) return 0;
		var surf = IOSurface.IOSurfaceLookup(n);
		if (surf.isNull()) return 0;
		var t = surfaceTexture(surf, w, h, MTL.TextureUsageShaderRead);
		MtlCF.CFRelease(surf);
		if (t.isNull()) return 0;
		textures.push(t);
		infos.push(TextureInfo.of({width: w, height: h}));
		return textures.length;
	}

	function surfaceTexture(surf:Ptr, w:Int, h:Int, usage:Int):Ptr {
		var d = make("MTLTextureDescriptor");
		Msg.vInt(d, ObjC.sel("setPixelFormat:"), MTL.PixelFormatBGRA8Unorm);
		Msg.vInt(d, ObjC.sel("setWidth:"), w);
		Msg.vInt(d, ObjC.sel("setHeight:"), h);
		Msg.vInt(d, ObjC.sel("setUsage:"), usage);
		var t = MtlMsg.idPtrPtrInt(device, ObjC.sel("newTextureWithDescriptor:iosurface:plane:"), d, surf, 0);
		Runtime.objc_release(d);
		return t;
	}

	public function frameInto(id:Int)
		frameTarget = id;

	// the next frame onto layer's next drawable (a CAMetalLayer of the
	// window's: helder.ui.draw.CaLayers), kept for takePresents
	public function planeFrame(layer:Ptr)
		plane = layer;

	// the drawables drawn by plane frames since, retained: presented by the
	// caller in its transaction, then released
	public function takePresents():Array<Ptr> {
		var p = presents.copy();
		presents.resize(0);
		if (p.length > 0) shown = true;
		return p;
	}

	// (a plane frame's pipeline: one sample, no depth)
	function planePipeline(p:MtlPipeline):MtlPipeline {
		if (p.plane == null) p.plane = build(p.desc, true);
		return p.plane;
	}

	// the depth texture (and the multisampled colour one), when the
	// target's size is not theirs
	function sizeDepth() {
		if (depthWidth == width && depthHeight == height) return;
		ObjC.release(depth);
		ObjC.release(msaa);
		depth = frameTexture(MTL.PixelFormatDepth32Float);
		msaa = samples > 1 ? frameTexture(MTL.PixelFormatBGRA8Unorm) : Ptr.nil();
		depthWidth = width;
		depthHeight = height;
	}

	// a texture of the frame's size and samples, in the GPU's memory
	function frameTexture(format:Int):Ptr {
		var d = make("MTLTextureDescriptor");
		Msg.vInt(d, ObjC.sel("setPixelFormat:"), format);
		Msg.vInt(d, ObjC.sel("setWidth:"), width);
		Msg.vInt(d, ObjC.sel("setHeight:"), height);
		Msg.vInt(d, ObjC.sel("setUsage:"), MTL.TextureUsageRenderTarget);
		Msg.vInt(d, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
		if (samples > 1) {
			Msg.vInt(d, ObjC.sel("setTextureType:"), MTL.TextureType2DMultisample);
			Msg.vInt(d, ObjC.sel("setSampleCount:"), samples);
		}
		var t = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), d);
		Runtime.objc_release(d);
		if (t.isNull()) throw "helder.gfx: cannot create a " + width + "x" + height + " frame texture";
		return t;
	}

	// a new instance of a class ([[cls alloc] init]: owned, not autoreleased)
	static inline function make(cls:String):Ptr
		return Msg.id(Msg.id(ObjC.cls(cls), ObjC.sel("alloc")), ObjC.sel("init"));

	// an NSError's description
	static function describe(error:Ptr):String
		return error.isNull() ? "(no error)" : ObjC.string(Msg.id(error, ObjC.sel("localizedDescription")));

	public function createBuffer(d:BufferDesc):Int {
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "helder.gfx: createBuffer: data has fewer than size bytes";
		var b = Msg.idIntInt(device, ObjC.sel("newBufferWithLength:options:"), size, MTL.ResourceStorageModeShared);
		if (b.isNull()) throw "helder.gfx: cannot create a buffer of " + size + " bytes";
		// (a fast call: the Bytes cannot move during it)
		if (data != null) LibC.memcpy(Msg.id(b, ObjC.sel("contents")), BytesPtr.of(data, 0, size), (size : Int64));
		buffers.push(b);
		gpuWritten.push(d.usage == Storage || d.usage == Indirect);
		return buffers.length;
	}

	// (shared memory: what the GPU reads when the frame runs)
	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		var b = buffers[id - 1];
		if (offset + size > Msg.i(b, ObjC.sel("length")).toInt()) throw "helder.gfx: writeBuffer: past the buffer's end";
		// (shared memory, written at once: a buffer the GPU writes may be in use by a
		// frame committed and not yet run, whose work would then see this write)
		if (gpuWritten[id - 1] && !inFlight.isNull()) Msg.v(inFlight, ObjC.sel("waitUntilCompleted"));
		var dst:Ptr<UInt8> = Msg.id(b, ObjC.sel("contents"));
		LibC.memcpy(dst.add(offset), BytesPtr.of(data, dataOffset, size), (size : Int64));
	}

	// (a command buffer committed: the one writes into GPU-written buffers wait for)
	function committed(c:Ptr) {
		if (!inFlight.isNull() && Msg.i(inFlight, ObjC.sel("status")) == 4)
			gpuSeconds += Msg.f(inFlight, ObjC.sel("GPUEndTime")) - Msg.f(inFlight, ObjC.sel("GPUStartTime"));
		if (!inFlight.isNull()) Runtime.objc_release(inFlight);
		inFlight = Runtime.objc_retain(c);
	}

	static function pixelFormat(f:TextureFormat):Int
		return switch f {
			case RGBA8: MTL.PixelFormatRGBA8Unorm;
			case RGBA8Srgb: MTL.PixelFormatRGBA8UnormSrgb;
			case R8: MTL.PixelFormatR8Unorm;
			case RG8: MTL.PixelFormatRG8Unorm;
			case RGBA16F: MTL.PixelFormatRGBA16Float;
			case R32F: MTL.PixelFormatR32Float;
			case RGBA32F: MTL.PixelFormatRGBA32Float;
			case Depth16: MTL.PixelFormatDepth16Unorm;
			case Depth32F: MTL.PixelFormatDepth32Float;
			case BC1: MTL.PixelFormatBC1_RGBA;
			case BC3: MTL.PixelFormatBC3_RGBA;
			case ASTC4x4: MTL.PixelFormatASTC_4x4_LDR;
		}

	// whether the device samples a format: BC on macOS's GPUs; ASTC on
	// Apple's (not asked yet: false)
	public function supports(f:TextureFormat):Bool
		return f != ASTC4x4;

	public function createTexture(d:TextureDesc):Int {
		var info = TextureInfo.of(d), target = info.target;
		var desc = make("MTLTextureDescriptor");
		Msg.vInt(desc, ObjC.sel("setPixelFormat:"), pixelFormat(info.format));
		Msg.vInt(desc, ObjC.sel("setWidth:"), info.width);
		Msg.vInt(desc, ObjC.sel("setHeight:"), info.height);
		Msg.vInt(desc, ObjC.sel("setMipmapLevelCount:"), info.levels);
		// (a render target: in the GPU's memory only, as depth textures must be;
		// multisampled, only drawn into and resolved)
		var multi = info.samples > 1;
		Msg.vInt(desc, ObjC.sel("setUsage:"), (multi ? MTL.TextureUsageRenderTarget : target ? MTL.TextureUsageShaderRead | MTL.TextureUsageRenderTarget : MTL.TextureUsageShaderRead)
			| (info.storage ? MTL.TextureUsageShaderWrite : 0));
		if (target || info.storage) Msg.vInt(desc, ObjC.sel("setStorageMode:"), MTL.StorageModePrivate);
		if (info.cube) Msg.vInt(desc, ObjC.sel("setTextureType:"), MTL.TextureTypeCube);
		else if (info.array) {
			Msg.vInt(desc, ObjC.sel("setTextureType:"), MTL.TextureType2DArray);
			Msg.vInt(desc, ObjC.sel("setArrayLength:"), info.layers);
		}
		if (multi) {
			Msg.vInt(desc, ObjC.sel("setTextureType:"), MTL.TextureType2DMultisample);
			Msg.vInt(desc, ObjC.sel("setSampleCount:"), info.samples);
		}
		var t = Msg.idPtr(device, ObjC.sel("newTextureWithDescriptor:"), desc);
		Runtime.objc_release(desc);
		if (t.isNull()) throw "helder.gfx: cannot create a " + d.width + "x" + d.height + " texture";
		textures.push(t);
		infos.push(info);
		if (d.data != null)
			for (l in 0...info.layers)
				writeTexture(textures.length, d.data, 0, 0, -1, -1, l * info.format.levelBytes(info.width, info.height), 0, l);
		return textures.length;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int, layer:Int) {
		var t = textures[id - 1], info = infos[id - 1];
		info.checkWrite(data, x, y, w, h, dataOffset, level, layer);
		w = info.w;
		h = info.h;
		var f = info.format, n = f.texelSize;
		region.value.origin.x = x;
		region.value.origin.y = y;
		region.value.origin.z = 0;
		region.value.size.width = w;
		region.value.size.height = h;
		region.value.size.depth = 1;
		// (a copy first: the Bytes may move during a message)
		// (compressed: rows of blocks)
		var bytes = f.levelBytes(w, h), row = f.compressed ? ((w + 3) >> 2) * f.blockBytes : w * n;
		if (info.cube || info.array)
			Arena.scoped(a -> MtlMsg.vRegionIntIntPtrIntInt(t, ObjC.sel("replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:"), region.value, level, layer,
				a.copyBytes(data, dataOffset, bytes), row, bytes));
		else
			Arena.scoped(a -> MtlMsg.vRegionIntPtrInt(t, ObjC.sel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"), region.value, level, a.copyBytes(data, dataOffset, bytes), row));
	}

	// a blit in the frame's command buffer (between its passes), else in one of its own
	public function generateMips(id:Int) {
		infos[id - 1].checkMips();
		var own = cmd.isNull();
		var pool = own ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
		var c = own ? Msg.id(queue, S.commandBuffer) : cmd;
		var blit = Msg.id(c, ObjC.sel("blitCommandEncoder"));
		Msg.vPtr(blit, ObjC.sel("generateMipmapsForTexture:"), textures[id - 1]);
		Msg.v(blit, S.endEncoding);
		if (own) {
			Msg.v(c, S.commit);
			Runtime.objc_autoreleasePoolPop(pool);
		}
	}

	public function destroyBuffer(id:Int) {
		var b = buffers[id - 1];
		if (b.isNull()) return;
		Runtime.objc_release(b);
		buffers[id - 1] = Ptr.nil();
	}

	public function destroyTexture(id:Int) {
		var t = textures[id - 1];
		if (t.isNull()) return;
		Runtime.objc_release(t);
		textures[id - 1] = Ptr.nil();
		shared.remove(id);
		if (frameTarget == id) frameTarget = 0;
	}

	public function createSampler(d:SamplerDesc):Int {
		var desc = make("MTLSamplerDescriptor");
		var f = d.filter == Nearest ? MTL.SamplerMinMagFilterNearest : MTL.SamplerMinMagFilterLinear;
		var w = switch d.wrap {
			case null | Repeat: MTL.SamplerAddressModeRepeat;
			case Clamp: MTL.SamplerAddressModeClampToEdge;
			case Mirror: MTL.SamplerAddressModeMirrorRepeat;
		}
		Msg.vInt(desc, ObjC.sel("setMinFilter:"), f);
		Msg.vInt(desc, ObjC.sel("setMagFilter:"), f);
		Msg.vInt(desc, ObjC.sel("setMipFilter:"), d.mipFilter == null ? 0 : d.mipFilter == Nearest ? 1 : 2);
		Msg.vInt(desc, ObjC.sel("setSAddressMode:"), w);
		Msg.vInt(desc, ObjC.sel("setTAddressMode:"), w);
		var s = Msg.idPtr(device, ObjC.sel("newSamplerStateWithDescriptor:"), desc);
		Runtime.objc_release(desc);
		if (s.isNull()) throw "helder.gfx: cannot create a sampler";
		samplers.push(s);
		return samplers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.msl == null) throw "helder.gfx: createShader: no MSL source for the Metal back end";
		var pool = Runtime.objc_autoreleasePoolPush();
		var src = ObjC.str(d.code.msl);
		scratch.value = Ptr.nil();
		var lib = Msg.idPtrPtrPtr(device, ObjC.sel("newLibraryWithSource:options:error:"), src, Ptr.nil(), scratch);
		ObjC.release(src);
		var error = lib.isNull() ? describe(scratch.value) : null;
		var fn = Ptr.nil();
		if (!lib.isNull()) {
			var name = ObjC.str("main0");
			fn = Msg.idPtr(lib, ObjC.sel("newFunctionWithName:"), name);
			ObjC.release(name);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		if (error != null) throw "helder.gfx: the shader does not compile:\n" + error;
		if (fn.isNull()) throw "helder.gfx: the shader has no function main0";
		libraries.push(lib);
		shaders.push(fn);
		if (d.stage == Compute) workgroups.set(shaders.length, d.code.workgroupSize == null ? [1, 1, 1] : d.code.workgroupSize);
		return shaders.length;
	}

	// ---- the compute tier

	public function has(f:Feature):Bool
		return true;

	public function createComputePipeline(shader:Int):Int {
		var size = workgroups.get(shader);
		if (size == null) throw "helder.gfx: createComputePipeline: not a compute shader";
		scratch.value = Ptr.nil();
		var pool = Runtime.objc_autoreleasePoolPush();
		var state = Msg.idPtrPtr(device, ObjC.sel("newComputePipelineStateWithFunction:error:"), shaders[shader - 1], scratch);
		var error = state.isNull() ? describe(scratch.value) : null;
		Runtime.objc_autoreleasePoolPop(pool);
		if (error != null) throw "helder.gfx: the compute pipeline does not link:\n" + error;
		computes.push(new MtlCompute(state, size));
		return computes.length;
	}

	public function beginCompute() {
		if (!computeEnc.isNull()) throw "helder.gfx: beginCompute: in a compute pass already";
		ownCompute = cmd.isNull();
		if (ownCompute) {
			pool = Runtime.objc_autoreleasePoolPush();
			cmd = Msg.id(queue, S.commandBuffer);
		}
		computeEnc = Msg.id(cmd, S.computeCommandEncoder);
		computePipeline = null;
	}

	public function setComputePipeline(id:Int) {
		var c = computes[id - 1];
		if (c == computePipeline) return;
		computePipeline = c;
		Msg.vPtr(computeEnc, S.setComputePipelineState, c.state);
		threadSize.value.width = c.size[0];
		threadSize.value.height = c.size[1];
		threadSize.value.depth = c.size[2];
	}

	public function setStorage(slot:Int, id:Int)
		MtlMsg.vPtrIntInt(computeEnc, S.setBuffer, buffers[id - 1], 0, slot);

	public function setStorageTexture(slot:Int, id:Int)
		MtlMsg.vPtrInt(computeEnc, S.setTextureAt, textures[id - 1], slot);

	public function dispatch(x:Int, y:Int, z:Int) {
		groupSize.value.width = x;
		groupSize.value.height = y;
		groupSize.value.depth = z;
		MtlMsg.vSizeSize(computeEnc, S.dispatchThreadgroups, groupSize.value, threadSize.value);
	}

	public function dispatchIndirect(id:Int, offset:Int)
		MtlMsg.vPtrIntSize(computeEnc, S.dispatchThreadgroupsWithIndirectBuffer, buffers[id - 1], offset, threadSize.value);

	public function endCompute() {
		Msg.v(computeEnc, S.endEncoding);
		computeEnc = Ptr.nil();
		computePipeline = null;
		if (ownCompute) {
			Msg.v(cmd, S.commit);
			committed(cmd);
			cmd = Ptr.nil();
			Runtime.objc_autoreleasePoolPop(pool);
			pool = Ptr.nil();
			ownCompute = false;
		}
	}

	public function drawIndirect(id:Int, offset:Int)
		MtlMsg.vIntPtrInt(enc, S.drawPrimitivesIndirect, pipeline.topology, buffers[id - 1], offset);

	public function drawIndexedIndirect(id:Int, offset:Int)
		MtlMsg.vIntIntPtrIntPtrInt(enc, S.drawIndexedPrimitivesIndirect, pipeline.topology, itype, ibuf, ioffset, buffers[id - 1], offset);

	// the work so far committed and waited for (a frame's: it goes on in a new command buffer), then the shared memory read
	public function readBuffer(id:Int, offset:Int, dst:haxe.io.Bytes, dstOffset:Int, size:Int) {
		var b = buffers[id - 1];
		if (offset + size > Msg.i(b, ObjC.sel("length")).toInt()) throw "helder.gfx: readBuffer: past the buffer's end";
		var inFrame = !cmd.isNull();
		var own = inFrame ? Ptr.nil() : Runtime.objc_autoreleasePoolPush();
		var c = inFrame ? cmd : Msg.id(queue, S.commandBuffer);
		Msg.v(c, S.commit);
		Msg.v(c, ObjC.sel("waitUntilCompleted"));
		if (inFrame) cmd = Msg.id(queue, S.commandBuffer) else Runtime.objc_autoreleasePoolPop(own);
		var src:Ptr<UInt8> = Msg.id(b, ObjC.sel("contents"));
		BytesPtr.copyIn(dst, dstOffset, src.add(offset), size);
	}

	public function createPipeline(d:PipelineDesc):Int {
		pipelines.push(build(d, false));
		return pipelines.length;
	}

	// (plane: the frame's format, one sample and no depth, for planeFrame's)
	function build(d:PipelineDesc, plane:Bool):MtlPipeline {
		if (d.layout.length > MAX_SLOTS) throw "helder.gfx: more than " + MAX_SLOTS + " vertex buffers";
		var frame = d.colorFormat == null;
		var pool = Runtime.objc_autoreleasePoolPush();
		var desc = make("MTLRenderPipelineDescriptor");
		Msg.vPtr(desc, ObjC.sel("setVertexFunction:"), shaders[d.vertex.id() - 1]);
		Msg.vPtr(desc, ObjC.sel("setFragmentFunction:"), shaders[d.fragment.id() - 1]);
		var color = Msg.idInt(Msg.id(desc, ObjC.sel("colorAttachments")), ObjC.sel("objectAtIndexedSubscript:"), 0);
		Msg.vInt(color, ObjC.sel("setPixelFormat:"), d.colorFormat == null ? MTL.PixelFormatBGRA8Unorm : pixelFormat(d.colorFormat));
		Msg.vInt(desc, ObjC.sel("setRasterSampleCount:"), frame ? (plane ? 1 : samples) : d.samples == null ? 1 : d.samples);
		var blend:Blend = d.blend == null ? Opaque : d.blend;
		if (blend != Opaque) {
			Msg.vBool(color, ObjC.sel("setBlendingEnabled:"), true);
			var multiply = blend == Multiply;
			Msg.vInt(color, ObjC.sel("setSourceRGBBlendFactor:"), multiply ? MTL.BlendFactorDestinationColor : blend == Premultiplied || blend == Additive ? MTL.BlendFactorOne : MTL.BlendFactorSourceAlpha);
			Msg.vInt(color, ObjC.sel("setDestinationRGBBlendFactor:"), multiply ? MTL.BlendFactorZero : blend == Additive ? MTL.BlendFactorOne : MTL.BlendFactorOneMinusSourceAlpha);
			Msg.vInt(color, ObjC.sel("setRgbBlendOperation:"), MTL.BlendOperationAdd);
			Msg.vInt(color, ObjC.sel("setSourceAlphaBlendFactor:"), multiply ? MTL.BlendFactorZero : MTL.BlendFactorOne);
			Msg.vInt(color, ObjC.sel("setDestinationAlphaBlendFactor:"), blend == Additive || multiply ? MTL.BlendFactorOne : MTL.BlendFactorOneMinusSourceAlpha);
			Msg.vInt(color, ObjC.sel("setAlphaBlendOperation:"), MTL.BlendOperationAdd);
		}
		Msg.vInt(desc, ObjC.sel("setDepthAttachmentPixelFormat:"), d.depthFormat != null ? pixelFormat(d.depthFormat) : frame && !plane ? MTL.PixelFormatDepth32Float : MTL.PixelFormatInvalid);
		var vd = make("MTLVertexDescriptor");
		var attributes = Msg.id(vd, ObjC.sel("attributes")), layouts = Msg.id(vd, ObjC.sel("layouts"));
		for (slot in 0...d.layout.length) {
			var l = d.layout[slot];
			var ld = Msg.idInt(layouts, ObjC.sel("objectAtIndexedSubscript:"), VERTEX_BUFFERS + slot);
			Msg.vInt(ld, ObjC.sel("setStride:"), l.stride);
			// (an instance buffer: one element per instance, the step rate 1 by default)
			if (l.step == Instance) Msg.vInt(ld, ObjC.sel("setStepFunction:"), MTL.VertexStepFunctionPerInstance);
			for (a in l.attributes) {
				var ad = Msg.idInt(attributes, ObjC.sel("objectAtIndexedSubscript:"), a.location);
				Msg.vInt(ad, ObjC.sel("setFormat:"), switch a.format {
					case Float1: MTL.VertexFormatFloat;
					case Float2: MTL.VertexFormatFloat2;
					case Float3: MTL.VertexFormatFloat3;
					case Float4: MTL.VertexFormatFloat4;
					case UByte4Norm: MTL.VertexFormatUChar4Normalized;
				});
				Msg.vInt(ad, ObjC.sel("setOffset:"), a.offset);
				Msg.vInt(ad, ObjC.sel("setBufferIndex:"), VERTEX_BUFFERS + slot);
			}
		}
		Msg.vPtr(desc, ObjC.sel("setVertexDescriptor:"), vd);
		scratch.value = Ptr.nil();
		var state = Msg.idPtrPtr(device, ObjC.sel("newRenderPipelineStateWithDescriptor:error:"), desc, scratch);
		Runtime.objc_release(vd);
		Runtime.objc_release(desc);
		var error = state.isNull() ? describe(scratch.value) : null;
		Runtime.objc_autoreleasePoolPop(pool);
		if (error != null) throw "helder.gfx: the pipeline does not link:\n" + error;
		var ds = make("MTLDepthStencilDescriptor");
		Msg.vInt(ds, ObjC.sel("setDepthCompareFunction:"), d.depthCompare == null ? (cast Compare.Always : Int) : (cast d.depthCompare : Int));
		Msg.vBool(ds, ObjC.sel("setDepthWriteEnabled:"), d.depthWrite == true);
		var depthState = Msg.idPtr(device, ObjC.sel("newDepthStencilStateWithDescriptor:"), ds);
		Runtime.objc_release(ds);
		return new MtlPipeline(state, depthState, d);
	}

	// false: no drawable this frame (the window is hidden)
	public function beginFrame():Bool {
		pool = Runtime.objc_autoreleasePoolPush();
		if (!plane.isNull()) {
			drawable = Msg.id(plane, S.nextDrawable);
			plane = Ptr.nil();
			if (drawable.isNull()) {
				Runtime.objc_autoreleasePoolPop(pool);
				return false;
			}
			texture = Msg.id(drawable, S.texture);
			width = Msg.i(texture, S.width).toInt();
			height = Msg.i(texture, S.height).toInt();
			planing = true;
			cmd = Msg.id(queue, S.commandBuffer);
			return true;
		}
		if (frameTarget != 0) {
			texture = textures[frameTarget - 1];
			width = infos[frameTarget - 1].width;
			height = infos[frameTarget - 1].height;
		} else if (layer.isNull()) {
			texture = target;
			width = targetWidth;
			height = targetHeight;
		} else if (quiet) {
			// (no drawable: the system's layers are drawn from what this frame renders into targets)
			var sz = MtlMsg.size(layer, S.drawableSize);
			texture = Ptr.nil();
			width = Std.int(sz.width);
			height = Std.int(sz.height);
			cmd = Msg.id(queue, S.commandBuffer);
			return true;
		} else {
			drawable = Msg.id(layer, S.nextDrawable);
			if (drawable.isNull()) {
				Runtime.objc_autoreleasePoolPop(pool);
				return false;
			}
			texture = Msg.id(drawable, S.texture);
			width = Msg.i(texture, S.width).toInt();
			height = Msg.i(texture, S.height).toInt();
		}
		sizeDepth();
		cmd = Msg.id(queue, S.commandBuffer);
		return true;
	}

	public function beginPass(p:PassDesc) {
		var c = p.colors[0], d = p.depth, w = width, h = height;
		var depthTexture = planing ? Ptr.nil() : depth;
		if (c.texture != null) {
			// (a render target, its depth texture or none)
			var info = infos[c.texture.id() - 1];
			info.checkPass(d, c.layer == null ? 0 : c.layer);
			w = info.width;
			h = info.height;
			depthTexture = d == null ? Ptr.nil() : textures[d.texture.id() - 1];
			if (info.samples > 1 || c.resolve != null)
				info.checkSamples(d == null ? null : infos[d.texture.id() - 1], c.resolve == null ? null : infos[c.resolve.id() - 1]);
		}
		var resolve = c.texture == null && samples > 1 && !planing, into = c.texture != null && c.resolve != null;
		Msg.vPtr(attachment, S.setTexture, c.texture != null ? textures[c.texture.id() - 1] : resolve ? msaa : texture);
		Msg.vPtr(attachment, S.setResolveTexture, resolve ? texture : into ? textures[c.resolve.id() - 1] : Ptr.nil());
		// (a cube's face, a 2D array's layer)
		Msg.vInt(attachment, S.setSlice, c.texture != null && c.layer != null ? c.layer : 0);
		Msg.vInt(attachment, S.setLoadAction, switch c.load {
			case Clear: MTL.LoadActionClear;
			case Load: MTL.LoadActionLoad;
			case DontCare: MTL.LoadActionDontCare;
		});
		Msg.vInt(attachment, S.setStoreAction, resolve ? MTL.StoreActionStoreAndMultisampleResolve : into ? MTL.StoreActionMultisampleResolve : MTL.StoreActionStore);
		if (c.load == Clear) {
			var k = c.clear;
			clear.value.red = k == null ? 0 : k.r;
			clear.value.green = k == null ? 0 : k.g;
			clear.value.blue = k == null ? 0 : k.b;
			clear.value.alpha = k == null ? 1 : k.a;
			MtlMsg.vClear(attachment, S.setClearColor, clear.value);
		}
		Msg.vPtr(depthAttachment, S.setTexture, depthTexture);
		Msg.vInt(depthAttachment, S.setLoadAction, d == null || d.load == Load ? MTL.LoadActionLoad : MTL.LoadActionClear);
		Msg.vInt(depthAttachment, S.setStoreAction, MTL.StoreActionStore);
		Msg.vFloat(depthAttachment, S.setClearDepth, d == null || d.clear == null ? 1 : d.clear);
		// (the pass's occlusion queries: its visibility result buffer)
		passQueries = p.queries == null ? 0 : p.queries.id();
		if (passQueries != 0) Msg.vPtr(pass, ObjC.sel("setVisibilityResultBuffer:"), querySets[passQueries - 1].buffer);
		enc = Msg.idPtr(cmd, S.renderCommandEncoderWithDescriptor, pass);
		viewport.value.originX = 0;
		viewport.value.originY = 0;
		viewport.value.width = w;
		viewport.value.height = h;
		viewport.value.znear = 0;
		viewport.value.zfar = 1;
		MtlMsg.vViewport(enc, S.setViewport, viewport.value);
		// (GL's front faces)
		Msg.vInt(enc, S.setFrontFacingWinding, MTL.WindingCounterClockwise);
		pipeline = null;
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (planing && p.desc.colorFormat == null) p = planePipeline(p);
		if (p == pipeline) return;
		pipeline = p;
		Msg.vPtr(enc, S.setRenderPipelineState, p.state);
		Msg.vInt(enc, S.setCullMode, p.cull);
		Msg.vPtr(enc, S.setDepthStencilState, p.depth);
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int)
		MtlMsg.vPtrIntInt(enc, S.setVertexBuffer, buffers[id - 1], offset, VERTEX_BUFFERS + slot);

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "helder.gfx: setUniforms: outside the data";
		if (size > MAX_BYTES) throw "helder.gfx: setUniforms: a block of more than " + MAX_BYTES + " bytes";
		// (a copy first: the Bytes may move during a message)
		LibC.memcpy(uniforms, BytesPtr.of(data, offset, size), (size : Int64));
		if (!computeEnc.isNull()) {
			MtlMsg.vPtrIntInt(computeEnc, S.setBytes, uniforms, size, slot);
			return;
		}
		MtlMsg.vPtrIntInt(enc, S.setVertexBytes, uniforms, size, slot);
		MtlMsg.vPtrIntInt(enc, S.setFragmentBytes, uniforms, size, slot);
	}

	public function draw(vertices:Int, instances:Int, first:Int)
		MtlMsg.vIntIntIntInt(enc, S.drawPrimitives, pipeline.topology, first, vertices, instances);

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		var t = textures[texture - 1], s = samplers[sampler - 1];
		if (!computeEnc.isNull()) {
			MtlMsg.vPtrInt(computeEnc, S.setTextureAt, t, slot);
			MtlMsg.vPtrInt(computeEnc, S.setSamplerState, s, slot);
			return;
		}
		MtlMsg.vPtrInt(enc, S.setVertexTexture, t, slot);
		MtlMsg.vPtrInt(enc, S.setFragmentTexture, t, slot);
		MtlMsg.vPtrInt(enc, S.setVertexSamplerState, s, slot);
		MtlMsg.vPtrInt(enc, S.setFragmentSamplerState, s, slot);
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int) {
		ibuf = buffers[id - 1];
		itype = format == UInt16 ? MTL.IndexTypeUInt16 : MTL.IndexTypeUInt32;
		ioffset = offset;
	}

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int) {
		var at = ioffset + first * (itype == MTL.IndexTypeUInt16 ? 2 : 4);
		MtlMsg.vIntIntIntPtrIntIntIntInt(enc, S.drawIndexedPrimitives, pipeline.topology, count, itype, ibuf, at, instances, baseVertex, 0);
	}

	public function endPass() {
		Msg.v(enc, S.endEncoding);
		enc = Ptr.nil();
		if (passQueries != 0) Msg.vPtr(pass, ObjC.sel("setVisibilityResultBuffer:"), Ptr.nil());
		passQueries = 0;
	}

	// ---- occlusion queries (a pass's visibility result buffer, shared
	// memory: 8 bytes a query, MTLVisibilityResultModeBoolean, cleared by the
	// CPU when begun): each query's state (begun, its frame's command buffer
	// kept until it completed) and last answer (-1 none)
	final querySets:Array<Null<{buffer:Ptr, pending:Array<Bool>, results:Array<Int>, buffers:Array<Ptr>, stale:Array<Bool>}>> = [];
	var passQueries = 0;
	var activeQuery = -1;

	public function createQueries(count:Int):Int {
		var b = Msg.idIntInt(device, ObjC.sel("newBufferWithLength:options:"), count * 8, MTL.ResourceStorageModeShared);
		if (b.isNull()) throw "helder.gfx: createQueries: no buffer for " + count + " queries";
		LibC.memset(Msg.id(b, ObjC.sel("contents")), 0, (count * 8 : Int64));
		querySets.push({
			buffer: b,
			pending: [for (_ in 0...count) false],
			results: [for (_ in 0...count) -1],
			buffers: [for (_ in 0...count) Ptr.nil()],
			stale: [for (_ in 0...count) false]
		});
		return querySets.length;
	}

	public function destroyQueries(id:Int) {
		var q = querySets[id - 1];
		if (q == null) return;
		for (c in q.buffers)
			if (!c.isNull()) Runtime.objc_release(c);
		ObjC.release(q.buffer);
		querySets[id - 1] = null;
	}

	public function queryResult(id:Int, k:Int):Int {
		var q = querySets[id - 1];
		if (q == null || k < 0 || k >= q.results.length) return -1;
		// (its frame's command buffer completed, MTLCommandBufferStatusCompleted or Error: its answer there)
		if (q.pending[k] && Msg.i(q.buffers[k], ObjC.sel("status")) >= 4) {
			var p:Ptr<Int32> = Msg.id(q.buffer, ObjC.sel("contents"));
			q.results[k] = q.stale[k] ? -1 : p.offset(k * 2).value != 0 || p.offset(k * 2 + 1).value != 0 ? 1 : 0;
			q.pending[k] = q.stale[k] = false;
			Runtime.objc_release(q.buffers[k]);
			q.buffers[k] = Ptr.nil();
		}
		return q.results[k];
	}

	public function resetQuery(id:Int, k:Int) {
		var q = querySets[id - 1];
		if (q == null || k < 0 || k >= q.results.length) return;
		q.results[k] = -1;
		if (q.pending[k]) q.stale[k] = true;
	}

	public function beginQuery(k:Int) {
		activeQuery = -1;
		var q = passQueries == 0 ? null : querySets[passQueries - 1];
		if (q == null || k < 0 || k >= q.results.length) return;
		// (its last answer still to come: not begun again, so that one comes)
		if (q.pending[k]) {
			queryResult(passQueries, k);
			if (q.pending[k]) return;
		}
		var p:Ptr<Int32> = Msg.id(q.buffer, ObjC.sel("contents"));
		p.offset(k * 2).value = 0;
		p.offset(k * 2 + 1).value = 0;
		Msg.vIntInt(enc, ObjC.sel("setVisibilityResultMode:offset:"), 1, k * 8);
		activeQuery = k;
	}

	public function endQuery() {
		if (activeQuery < 0) return;
		var q = querySets[passQueries - 1];
		Msg.vIntInt(enc, ObjC.sel("setVisibilityResultMode:offset:"), 0, 0);
		q.pending[activeQuery] = true;
		q.buffers[activeQuery] = Runtime.objc_retain(cmd);
		activeQuery = -1;
	}

	public function endFrame() {
		if (planing) {
			// (presented with the transaction that places its layer: scheduled first, as presentsWithTransaction asks)
			planing = false;
			Msg.v(cmd, S.commit);
			committed(cmd);
			Msg.v(cmd, ObjC.sel("waitUntilScheduled"));
			presents.push(Runtime.objc_retain(drawable));
			cmd = Ptr.nil();
			drawable = Ptr.nil();
			texture = Ptr.nil();
			Runtime.objc_autoreleasePoolPop(pool);
			pool = Ptr.nil();
			return;
		}
		var presented = !drawable.isNull() && frameTarget == 0;
		if (presented) Msg.vPtr(cmd, S.presentDrawable, drawable);
		Msg.v(cmd, S.commit);
		committed(cmd);
		// (a frame into a shared texture: complete before the other process is told)
		if (frameTarget != 0 && shared.exists(frameTarget)) Msg.v(cmd, ObjC.sel("waitUntilCompleted"));
		cmd = Ptr.nil();
		drawable = Ptr.nil();
		texture = Ptr.nil();
		Runtime.objc_autoreleasePoolPop(pool);
		pool = Ptr.nil();
		if (presented) shown = true;
	}

	// (a drawable presented since asked last: Device calls Surface.onPresent,
	// on the program's thread, the render thread's present not being AppKit's)
	var shown = false;

	public function presented():Bool {
		var p = shown;
		shown = false;
		return p;
	}

	// the frame's passes so far, then a copy of the target into a shared
	// buffer, waited for; the frame goes on in a new command buffer
	public function readPixels(dst:haxe.io.Bytes) {
		var row = width * 4, n = row * height;
		if (dst.length < n) throw "helder.gfx: readPixels: " + n + " bytes needed";
		if (readbackSize < n) {
			ObjC.release(readback);
			readback = Msg.idIntInt(device, ObjC.sel("newBufferWithLength:options:"), n, MTL.ResourceStorageModeShared);
			readbackSize = n;
		}
		var blit = Msg.id(cmd, ObjC.sel("blitCommandEncoder"));
		origin.value.x = 0;
		origin.value.y = 0;
		origin.value.z = 0;
		size.value.width = width;
		size.value.height = height;
		size.value.depth = 1;
		MtlMsg.vCopy(blit, ObjC.sel("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:"),
			texture, 0, 0, origin.value, size.value, readback, 0, row, n);
		Msg.v(blit, S.endEncoding);
		Msg.v(cmd, S.commit);
		Msg.v(cmd, ObjC.sel("waitUntilCompleted"));
		if (Msg.i(cmd, ObjC.sel("status")) == MTL.CommandBufferStatusError)
			throw "helder.gfx: the GPU failed: " + describe(Msg.id(cmd, ObjC.sel("error")));
		cmd = Msg.id(queue, S.commandBuffer);
		var src:Ptr<UInt8> = Msg.id(readback, ObjC.sel("contents"));
		for (i in 0...width * height) {
			dst.set(4 * i, src[4 * i + 2]);
			dst.set(4 * i + 1, src[4 * i + 1]);
			dst.set(4 * i + 2, src[4 * i]);
			dst.set(4 * i + 3, src[4 * i + 3]);
		}
	}

	public function dispose() {
		if (!inFlight.isNull()) Runtime.objc_release(inFlight);
		for (d in presents)
			Runtime.objc_release(d);
		presents.resize(0);
		for (p in pipelines) {
			Runtime.objc_release(p.state);
			Runtime.objc_release(p.depth);
			if (p.plane != null) {
				Runtime.objc_release(p.plane.state);
				Runtime.objc_release(p.plane.depth);
			}
		}
		for (c in computes)
			Runtime.objc_release(c.state);
		for (o in shaders.concat(libraries).concat(buffers).concat(textures).concat(samplers))
			Runtime.objc_release(o);
		ObjC.release(readback);
		ObjC.release(target);
		ObjC.release(depth);
		ObjC.release(msaa);
		Runtime.objc_release(pass);
		Runtime.objc_release(queue);
		#if hxmc.dev_host
		// (handing over: the layer keeps its device and its last frame for the next build)
		if (!layer.isNull() && !helder.dev.Hosted.handingOver) Msg.vPtr(layer, ObjC.sel("setDevice:"), Ptr.nil());
		#else
		if (!layer.isNull()) Msg.vPtr(layer, ObjC.sel("setDevice:"), Ptr.nil());
		#end
		Runtime.objc_release(device);
		LibC.free(scratch);
		LibC.free(clear);
		LibC.free(viewport);
		LibC.free(origin);
		LibC.free(size);
		LibC.free(region);
		LibC.free(uniforms);
		LibC.free(groupSize);
		LibC.free(threadSize);
	}
}

// a compute pipeline state and its workgroup's size
@:hxmc.unsafe(gc)
private class MtlCompute {
	public final state:Ptr;
	public final size:Array<Int>;

	public function new(state:Ptr, size:Array<Int>) {
		this.state = state;
		this.size = size;
	}
}

// a render pipeline state and its draw state
@:hxmc.unsafe(gc)
private class MtlPipeline {
	public final state:Ptr;
	public final depth:Ptr; // MTLDepthStencilState
	public final topology:Int;
	public final cull:Int;
	public final desc:PipelineDesc;
	// (its plane frames' variant, made at first use)
	public var plane:Null<MtlPipeline> = null;

	public function new(state:Ptr, depth:Ptr, d:PipelineDesc) {
		this.state = state;
		this.depth = depth;
		desc = d;
		topology = switch d.topology {
			case null | Triangles: MTL.PrimitiveTypeTriangle;
			case TriangleStrip: MTL.PrimitiveTypeTriangleStrip;
			case Lines: MTL.PrimitiveTypeLine;
			case Points: MTL.PrimitiveTypePoint;
		}
		cull = switch d.cull {
			case null | None: MTL.CullModeNone;
			case Front: MTL.CullModeFront;
			case Back: MTL.CullModeBack;
		}
	}
}

// the selectors of a frame's messages, registered once
@:hxmc.unsafe(gc)
private class S {
	public static final nextDrawable = ObjC.sel("nextDrawable");
	public static final drawableSize = ObjC.sel("drawableSize");
	public static final texture = ObjC.sel("texture");
	public static final width = ObjC.sel("width");
	public static final height = ObjC.sel("height");
	public static final commandBuffer = ObjC.sel("commandBuffer");
	public static final setTexture = ObjC.sel("setTexture:");
	public static final setResolveTexture = ObjC.sel("setResolveTexture:");
	public static final setLoadAction = ObjC.sel("setLoadAction:");
	public static final setSlice = ObjC.sel("setSlice:");
	public static final setStoreAction = ObjC.sel("setStoreAction:");
	public static final setClearColor = ObjC.sel("setClearColor:");
	public static final setClearDepth = ObjC.sel("setClearDepth:");
	public static final setDepthStencilState = ObjC.sel("setDepthStencilState:");
	public static final drawIndexedPrimitives = ObjC.sel("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:");
	public static final renderCommandEncoderWithDescriptor = ObjC.sel("renderCommandEncoderWithDescriptor:");
	// (the compute tier)
	public static final computeCommandEncoder = ObjC.sel("computeCommandEncoder");
	public static final setComputePipelineState = ObjC.sel("setComputePipelineState:");
	public static final setBuffer = ObjC.sel("setBuffer:offset:atIndex:");
	public static final setBytes = ObjC.sel("setBytes:length:atIndex:");
	public static final setTextureAt = ObjC.sel("setTexture:atIndex:");
	public static final setSamplerState = ObjC.sel("setSamplerState:atIndex:");
	public static final dispatchThreadgroups = ObjC.sel("dispatchThreadgroups:threadsPerThreadgroup:");
	public static final dispatchThreadgroupsWithIndirectBuffer = ObjC.sel("dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:");
	public static final drawPrimitivesIndirect = ObjC.sel("drawPrimitives:indirectBuffer:indirectBufferOffset:");
	public static final drawIndexedPrimitivesIndirect = ObjC.sel("drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:");
	public static final setViewport = ObjC.sel("setViewport:");
	public static final setFrontFacingWinding = ObjC.sel("setFrontFacingWinding:");
	public static final setRenderPipelineState = ObjC.sel("setRenderPipelineState:");
	public static final setCullMode = ObjC.sel("setCullMode:");
	public static final setVertexBuffer = ObjC.sel("setVertexBuffer:offset:atIndex:");
	public static final setVertexBytes = ObjC.sel("setVertexBytes:length:atIndex:");
	public static final setVertexTexture = ObjC.sel("setVertexTexture:atIndex:");
	public static final setFragmentTexture = ObjC.sel("setFragmentTexture:atIndex:");
	public static final setVertexSamplerState = ObjC.sel("setVertexSamplerState:atIndex:");
	public static final setFragmentSamplerState = ObjC.sel("setFragmentSamplerState:atIndex:");
	public static final setFragmentBytes = ObjC.sel("setFragmentBytes:length:atIndex:");
	public static final drawPrimitives = ObjC.sel("drawPrimitives:vertexStart:vertexCount:instanceCount:");
	public static final endEncoding = ObjC.sel("endEncoding");
	public static final presentDrawable = ObjC.sel("presentDrawable:");
	public static final commit = ObjC.sel("commit");
}
