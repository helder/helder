package helder.gfx;

import helder.os.Surface;
#if (helder.soft || (helder.os && helder.os != "web"))
#if helder.soft
import helder.gfx.soft.SoftBackend as Native;
#elseif (helder.os == "macos" || helder.os == "ios")
import helder.gfx.metal.MetalBackend as Native;
#elseif (helder.os == "windows")
import helder.gfx.d3d11.D3D11Backend as Native;
#else
import helder.gfx.gl.GLBackend as Native;
#end

// The back end of this target: Metal on macOS and iOS, D3D11 on Windows, GL
// elsewhere; the CPU's (helder.gfx.soft) with -D helder.soft, on any. A
// build for one system (helder.os: helder.compiler.Os) has its own only,
// its methods forwarded; the browser's two, and a build that names no
// system (every back end typed), are told apart below, the browser's
// without the native ones.
@:forward(backend, width, height, createBuffer, writeBuffer, createTexture, writeTexture, supports, generateMips, destroyBuffer, destroyTexture,
	createSampler, createShader, createPipeline, beginFrame, beginPass, setPipeline, setVertexBuffer, setIndexBuffer, setUniforms, setTexture, draw,
	drawIndexed, endPass, createQueries, destroyQueries, queryResult, resetQuery, beginQuery, endQuery, endFrame, readPixels, has, createComputePipeline,
	readBuffer, beginCompute, setComputePipeline, setStorage, setStorageTexture, dispatch, dispatchIndirect, endCompute, drawIndirect, drawIndexedIndirect,
	sharing, createShared, openShared, frameInto, dispose)
abstract Impl(Native) {
	public inline function new(surface:Surface, antialias:Bool)
		this = new Native(surface, antialias);

	#if helder.soft
	// (a texture's record: the soft canvas reads a <Scene>'s pixels where they are)
	public inline function textureRecord(id:Int):hxmc.unsafe.Ptr
		return this.textureRecord(id);
	#end

	public inline function writeTextureImage(id:Int, image:Int, release:Bool)
		throw "helder.gfx: writeTextureImage: in a browser only";

	public inline function maxTextureSize():Int
		return #if (helder.os == "linux" || helder.os == "android") this.maxTextureSize() #else 16384 #end;

	public inline function damaged(rects:Null<Array<Int>>)
		#if (helder.os != "macos" && helder.os != "ios") this.damaged(rects) #else {} #end;

	// (until the window's swap chain takes a frame without queueing it: Direct3D 11's; the CPU's has none)
	public inline function waitFrame()
		#if (helder.os == "windows" && !helder.soft) this.waitFrame() #else {} #end;

	// (whether waitFrame paces the next frame: Direct3D 11's latency object)
	public inline function paces():Bool
		return #if (helder.os == "windows" && !helder.soft) this.paces() #else false #end;

	public inline function presentResult():Int
		return #if (helder.os == "windows" && !helder.soft) this.presentResult #else 0 #end;

	// (a test's: the window's frames' GPU time, timed from now on: Direct3D 11's; -1 none)
	public inline function gpuTime():Float
		return #if (helder.os == "windows" && !helder.soft) this.gpuTime() #else -1 #end;

	public inline function software():Bool
		return #if (helder.os == "windows" && !helder.soft) this.software #else false #end;

	// (the back end's context let go by this thread, used by the render thread from now on: GL's)
	public inline function detach()
		#if (helder.os == "linux" || helder.os == "android") this.detach() #else {} #end;

	// (whether a frame was presented since asked last: Metal's, which a macOS window shows itself at)
	public inline function presented():Bool
		return #if (helder.os == "macos" || helder.os == "ios") this.presented() #else false #end;
}
#elseif (helder.os == "web")
import helder.gfx.gl.GLBackend;
import helder.gfx.webgpu.WebGPU;
import helder.gfx.webgpu.WebGPUBackend;

// The browser's two back ends (WebAssembly): WebGPU when the JavaScript side
// has a device (requested before main: WebGPU.ready), else GL on WebGL2,
// told apart by the object's class (no field has a back end's type, which
// would compile all its methods). The native ones are not loaded: a web
// build types neither Metal's nor Direct3D 11's.
abstract Impl(Any) {
	// (antialias: the page's run option antialias, when set, decides)
	public inline function new(surface:Surface, antialias:Bool)
		this = WebGPU.ready() != 0 ? new WebGPUBackend(surface, antialias) : new GLBackend(surface, antialias);

	// (WebGL2's)
	inline function webgl():Bool
		return Std.isOfType(this, GLBackend);

	inline function gl():GLBackend
		return cast this;

	inline function wgpu():WebGPUBackend
		return cast this;

	public var backend(get, never):Backend;
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_backend()
		return webgl() ? gl().backend : wgpu().backend;

	inline function get_width()
		return webgl() ? gl().width : wgpu().width;

	inline function get_height()
		return webgl() ? gl().height : wgpu().height;

	public inline function createBuffer(d:BufferDesc):Int
		return webgl() ? gl().createBuffer(d) : wgpu().createBuffer(d);

	public inline function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int)
		webgl() ? gl().writeBuffer(id, offset, data, dataOffset, size) : wgpu().writeBuffer(id, offset, data, dataOffset, size);

	public inline function createTexture(d:TextureDesc):Int
		return webgl() ? gl().createTexture(d) : wgpu().createTexture(d);

	public inline function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int, layer:Int)
		webgl() ? gl().writeTexture(id, data, x, y, w, h, dataOffset, level, layer) : wgpu().writeTexture(id, data, x, y, w, h, dataOffset, level, layer);

	public inline function writeTextureImage(id:Int, image:Int, release:Bool)
		webgl() ? gl().writeTextureImage(id, image, release) : wgpu().writeTextureImage(id, image, release);

	public inline function supports(f:TextureFormat):Bool
		return webgl() ? gl().supports(f) : wgpu().supports(f);

	public inline function maxTextureSize():Int
		return webgl() ? gl().maxTextureSize() : wgpu().maxTextureSize();

	public inline function generateMips(id:Int)
		webgl() ? gl().generateMips(id) : wgpu().generateMips(id);

	public inline function destroyBuffer(id:Int)
		webgl() ? gl().destroyBuffer(id) : wgpu().destroyBuffer(id);

	public inline function destroyTexture(id:Int)
		webgl() ? gl().destroyTexture(id) : wgpu().destroyTexture(id);

	public inline function createSampler(d:SamplerDesc):Int
		return webgl() ? gl().createSampler(d) : wgpu().createSampler(d);

	public inline function createShader(d:ShaderDesc):Int
		return webgl() ? gl().createShader(d) : wgpu().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return webgl() ? gl().createPipeline(d) : wgpu().createPipeline(d);

	public inline function beginFrame():Bool
		return webgl() ? gl().beginFrame() : wgpu().beginFrame();

	public inline function beginPass(p:PassDesc)
		webgl() ? gl().beginPass(p) : wgpu().beginPass(p);

	public inline function setPipeline(id:Int)
		webgl() ? gl().setPipeline(id) : wgpu().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		webgl() ? gl().setVertexBuffer(slot, id, offset) : wgpu().setVertexBuffer(slot, id, offset);

	public inline function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		webgl() ? gl().setIndexBuffer(id, format, offset) : wgpu().setIndexBuffer(id, format, offset);

	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int)
		webgl() ? gl().setUniforms(slot, data, offset, size) : wgpu().setUniforms(slot, data, offset, size);

	public inline function setTexture(slot:Int, texture:Int, sampler:Int)
		webgl() ? gl().setTexture(slot, texture, sampler) : wgpu().setTexture(slot, texture, sampler);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		webgl() ? gl().draw(vertices, instances, first) : wgpu().draw(vertices, instances, first);

	public inline function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		webgl() ? gl().drawIndexed(count, instances, first, baseVertex) : wgpu().drawIndexed(count, instances, first, baseVertex);

	public inline function endPass()
		webgl() ? gl().endPass() : wgpu().endPass();

	public inline function createQueries(count:Int):Int
		return webgl() ? gl().createQueries(count) : wgpu().createQueries(count);

	public inline function destroyQueries(id:Int)
		webgl() ? gl().destroyQueries(id) : wgpu().destroyQueries(id);

	public inline function queryResult(id:Int, k:Int):Int
		return webgl() ? gl().queryResult(id, k) : wgpu().queryResult(id, k);

	public inline function resetQuery(id:Int, k:Int)
		webgl() ? gl().resetQuery(id, k) : wgpu().resetQuery(id, k);

	public inline function beginQuery(k:Int)
		webgl() ? gl().beginQuery(k) : wgpu().beginQuery(k);

	public inline function endQuery()
		webgl() ? gl().endQuery() : wgpu().endQuery();

	public inline function endFrame()
		webgl() ? gl().endFrame() : wgpu().endFrame();

	public inline function damaged(rects:Null<Array<Int>>) {}

	public inline function waitFrame() {}

	public inline function paces():Bool
		return false;

	public inline function presentResult():Int
		return 0;

	public inline function gpuTime():Float
		return -1;

	public inline function software():Bool
		return false;

	public inline function readPixels(dst:haxe.io.Bytes)
		webgl() ? gl().readPixels(dst) : wgpu().readPixels(dst);

	// ---- the compute tier (Device.has: WebGL2's GLBackend has none)

	public inline function has(f:Feature):Bool
		return webgl() ? gl().has(f) : wgpu().has(f);

	public inline function createComputePipeline(shader:Int):Int
		return webgl() ? gl().createComputePipeline(shader) : wgpu().createComputePipeline(shader);

	public inline function readBuffer(id:Int, offset:Int, dst:haxe.io.Bytes, dstOffset:Int, size:Int)
		webgl() ? gl().readBuffer(id, offset, dst, dstOffset, size) : wgpu().readBuffer(id, offset, dst, dstOffset, size);

	public inline function beginCompute()
		webgl() ? gl().beginCompute() : wgpu().beginCompute();

	public inline function setComputePipeline(id:Int)
		webgl() ? gl().setComputePipeline(id) : wgpu().setComputePipeline(id);

	public inline function setStorage(slot:Int, id:Int)
		webgl() ? gl().setStorage(slot, id) : wgpu().setStorage(slot, id);

	public inline function setStorageTexture(slot:Int, id:Int)
		webgl() ? gl().setStorageTexture(slot, id) : wgpu().setStorageTexture(slot, id);

	public inline function dispatch(x:Int, y:Int, z:Int)
		webgl() ? gl().dispatch(x, y, z) : wgpu().dispatch(x, y, z);

	public inline function dispatchIndirect(id:Int, offset:Int)
		webgl() ? gl().dispatchIndirect(id, offset) : wgpu().dispatchIndirect(id, offset);

	public inline function endCompute()
		webgl() ? gl().endCompute() : wgpu().endCompute();

	public inline function drawIndirect(id:Int, offset:Int)
		webgl() ? gl().drawIndirect(id, offset) : wgpu().drawIndirect(id, offset);

	public inline function drawIndexedIndirect(id:Int, offset:Int)
		webgl() ? gl().drawIndexedIndirect(id, offset) : wgpu().drawIndexedIndirect(id, offset);

	// (shared textures: none in a browser)
	public inline function sharing():Null<String>
		return null;

	public inline function createShared(width:Int, height:Int):Null<{id:Int, handle:String}>
		return null;

	public inline function openShared(handle:String, width:Int, height:Int):Int
		return 0;

	public inline function frameInto(id:Int)
		if (id != 0) throw "helder.gfx: frameInto: not in a browser";

	public inline function detach() {}

	public inline function presented():Bool
		return false;

	public inline function dispose()
		webgl() ? gl().dispose() : wgpu().dispose();
}
#else
import helder.gfx.d3d11.D3D11Backend;
import helder.gfx.gl.GLBackend;
import helder.gfx.metal.MetalBackend;
import helder.gfx.webgpu.WebGPU;
import helder.gfx.webgpu.WebGPUBackend;
import hxmc.Platform;

// The back end of this target: Metal on macOS, D3D11 on Windows, GL
// elsewhere; in the browser (WebAssembly), WebGPU when the JavaScript side
// has a device (requested before main: WebGPU.ready), else GL on WebGL2.
// Platform.os() is known when compiling, so each call reaches one back end's
// code only (and imports only its libraries), or in the browser one of
// those two, told apart by the object's class: no field has a back end's
// type, which would compile all its methods.
abstract Impl(Any) {
	// (antialias: every back end's; in the browser the page's run option antialias, when set, decides)
	public inline function new(surface:Surface, antialias:Bool)
		this = Platform.os() == 1 ? new MetalBackend(surface, antialias) : Platform.os() == 2 ? new D3D11Backend(surface, antialias) : Platform.os() != 3 ? new GLBackend(surface,
			antialias) : WebGPU.ready() != 0 ? new WebGPUBackend(surface, antialias) : new GLBackend(surface, antialias);

	// (the browser: WebGL2's)
	inline function webgl():Bool
		return Std.isOfType(this, GLBackend);

	inline function mtl():MetalBackend
		return cast this;

	inline function d3d():D3D11Backend
		return cast this;

	inline function gl():GLBackend
		return cast this;

	inline function wgpu():WebGPUBackend
		return cast this;

	public var backend(get, never):Backend;
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_backend()
		return Platform.os() == 1 ? mtl().backend : Platform.os() == 2 ? d3d().backend : Platform.os() != 3 ? gl().backend : webgl() ? gl().backend : wgpu().backend;

	inline function get_width()
		return Platform.os() == 1 ? mtl().width : Platform.os() == 2 ? d3d().width : Platform.os() != 3 ? gl().width : webgl() ? gl().width : wgpu().width;

	inline function get_height()
		return Platform.os() == 1 ? mtl().height : Platform.os() == 2 ? d3d().height : Platform.os() != 3 ? gl().height : webgl() ? gl().height : wgpu().height;

	public inline function createBuffer(d:BufferDesc):Int
		return Platform.os() == 1 ? mtl().createBuffer(d) : Platform.os() == 2 ? d3d().createBuffer(d) : Platform.os() != 3 ? gl().createBuffer(d) : webgl() ? gl().createBuffer(d) : wgpu().createBuffer(d);

	public inline function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int)
		Platform.os() == 1 ? mtl().writeBuffer(id, offset, data, dataOffset, size) : Platform.os() == 2 ? d3d().writeBuffer(id, offset, data, dataOffset, size) : Platform.os() != 3 ? gl().writeBuffer(id, offset, data, dataOffset, size) : webgl() ? gl().writeBuffer(id, offset, data, dataOffset, size) : wgpu().writeBuffer(id, offset, data, dataOffset, size);

	public inline function createTexture(d:TextureDesc):Int
		return Platform.os() == 1 ? mtl().createTexture(d) : Platform.os() == 2 ? d3d().createTexture(d) : Platform.os() != 3 ? gl().createTexture(d) : webgl() ? gl().createTexture(d) : wgpu().createTexture(d);

	public inline function writeTexture(id:Int, data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int, layer:Int)
		Platform.os() == 1 ? mtl().writeTexture(id, data, x, y, w, h, dataOffset, level, layer) : Platform.os() == 2 ? d3d().writeTexture(id, data, x, y, w, h, dataOffset,
			level, layer) : Platform.os() != 3 ? gl().writeTexture(id, data, x, y, w, h, dataOffset, level, layer) : webgl() ? gl().writeTexture(id, data, x, y, w, h,
			dataOffset, level, layer) : wgpu().writeTexture(id, data, x, y, w, h, dataOffset, level, layer);

	// (the browser's: WebGPU's or WebGL2's)
	public inline function writeTextureImage(id:Int, image:Int, release:Bool)
		Platform.os() != 3 ? throw "helder.gfx: writeTextureImage: in a browser only" : webgl() ? gl().writeTextureImage(id, image, release) : wgpu().writeTextureImage(id, image, release);

	public inline function supports(f:TextureFormat):Bool
		return Platform.os() == 1 ? mtl().supports(f) : Platform.os() == 2 ? d3d().supports(f) : Platform.os() != 3 ? gl().supports(f) : webgl() ? gl().supports(f) : wgpu().supports(f);

	public inline function maxTextureSize():Int
		return Platform.os() == 1 || Platform.os() == 2 ? 16384 : Platform.os() != 3 || webgl() ? gl().maxTextureSize() : wgpu().maxTextureSize();

	public inline function generateMips(id:Int)
		Platform.os() == 1 ? mtl().generateMips(id) : Platform.os() == 2 ? d3d().generateMips(id) : Platform.os() != 3 ? gl().generateMips(id) : webgl() ? gl().generateMips(id) : wgpu().generateMips(id);

	public inline function destroyBuffer(id:Int)
		Platform.os() == 1 ? mtl().destroyBuffer(id) : Platform.os() == 2 ? d3d().destroyBuffer(id) : Platform.os() != 3 ? gl().destroyBuffer(id) : webgl() ? gl().destroyBuffer(id) : wgpu().destroyBuffer(id);

	public inline function destroyTexture(id:Int)
		Platform.os() == 1 ? mtl().destroyTexture(id) : Platform.os() == 2 ? d3d().destroyTexture(id) : Platform.os() != 3 ? gl().destroyTexture(id) : webgl() ? gl().destroyTexture(id) : wgpu().destroyTexture(id);

	public inline function createSampler(d:SamplerDesc):Int
		return Platform.os() == 1 ? mtl().createSampler(d) : Platform.os() == 2 ? d3d().createSampler(d) : Platform.os() != 3 ? gl().createSampler(d) : webgl() ? gl().createSampler(d) : wgpu().createSampler(d);

	public inline function createShader(d:ShaderDesc):Int
		return Platform.os() == 1 ? mtl().createShader(d) : Platform.os() == 2 ? d3d().createShader(d) : Platform.os() != 3 ? gl().createShader(d) : webgl() ? gl().createShader(d) : wgpu().createShader(d);

	public inline function createPipeline(d:PipelineDesc):Int
		return Platform.os() == 1 ? mtl().createPipeline(d) : Platform.os() == 2 ? d3d().createPipeline(d) : Platform.os() != 3 ? gl().createPipeline(d) : webgl() ? gl().createPipeline(d) : wgpu().createPipeline(d);

	public inline function beginFrame():Bool
		return Platform.os() == 1 ? mtl().beginFrame() : Platform.os() == 2 ? d3d().beginFrame() : Platform.os() != 3 ? gl().beginFrame() : webgl() ? gl().beginFrame() : wgpu().beginFrame();

	public inline function beginPass(p:PassDesc)
		Platform.os() == 1 ? mtl().beginPass(p) : Platform.os() == 2 ? d3d().beginPass(p) : Platform.os() != 3 ? gl().beginPass(p) : webgl() ? gl().beginPass(p) : wgpu().beginPass(p);

	public inline function setPipeline(id:Int)
		Platform.os() == 1 ? mtl().setPipeline(id) : Platform.os() == 2 ? d3d().setPipeline(id) : Platform.os() != 3 ? gl().setPipeline(id) : webgl() ? gl().setPipeline(id) : wgpu().setPipeline(id);

	public inline function setVertexBuffer(slot:Int, id:Int, offset:Int)
		Platform.os() == 1 ? mtl().setVertexBuffer(slot, id, offset) : Platform.os() == 2 ? d3d().setVertexBuffer(slot, id, offset) : Platform.os() != 3 ? gl().setVertexBuffer(slot, id, offset) : webgl() ? gl().setVertexBuffer(slot, id, offset) : wgpu().setVertexBuffer(slot, id, offset);

	public inline function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		Platform.os() == 1 ? mtl().setIndexBuffer(id, format, offset) : Platform.os() == 2 ? d3d().setIndexBuffer(id, format, offset) : Platform.os() != 3 ? gl().setIndexBuffer(id, format, offset) : webgl() ? gl().setIndexBuffer(id, format, offset) : wgpu().setIndexBuffer(id, format, offset);

	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int)
		Platform.os() == 1 ? mtl().setUniforms(slot, data, offset, size) : Platform.os() == 2 ? d3d().setUniforms(slot, data, offset, size) : Platform.os() != 3 ? gl().setUniforms(slot, data, offset, size) : webgl() ? gl().setUniforms(slot, data, offset, size) : wgpu().setUniforms(slot, data, offset, size);

	public inline function setTexture(slot:Int, texture:Int, sampler:Int)
		Platform.os() == 1 ? mtl().setTexture(slot, texture, sampler) : Platform.os() == 2 ? d3d().setTexture(slot, texture, sampler) : Platform.os() != 3 ? gl().setTexture(slot, texture, sampler) : webgl() ? gl().setTexture(slot, texture, sampler) : wgpu().setTexture(slot, texture, sampler);

	public inline function draw(vertices:Int, instances:Int, first:Int)
		Platform.os() == 1 ? mtl().draw(vertices, instances, first) : Platform.os() == 2 ? d3d().draw(vertices, instances, first) : Platform.os() != 3 ? gl().draw(vertices, instances, first) : webgl() ? gl().draw(vertices, instances, first) : wgpu().draw(vertices, instances, first);

	public inline function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		Platform.os() == 1 ? mtl().drawIndexed(count, instances, first, baseVertex) : Platform.os() == 2 ? d3d().drawIndexed(count, instances, first, baseVertex) : Platform.os() != 3 ? gl().drawIndexed(count, instances, first, baseVertex) : webgl() ? gl().drawIndexed(count, instances, first, baseVertex) : wgpu().drawIndexed(count, instances, first, baseVertex);

	public inline function endPass()
		Platform.os() == 1 ? mtl().endPass() : Platform.os() == 2 ? d3d().endPass() : Platform.os() != 3 ? gl().endPass() : webgl() ? gl().endPass() : wgpu().endPass();

	public inline function createQueries(count:Int):Int
		return Platform.os() == 1 ? mtl().createQueries(count) : Platform.os() == 2 ? d3d().createQueries(count) : Platform.os() != 3 ? gl().createQueries(count) : webgl() ? gl().createQueries(count) : wgpu().createQueries(count);

	public inline function destroyQueries(id:Int)
		Platform.os() == 1 ? mtl().destroyQueries(id) : Platform.os() == 2 ? d3d().destroyQueries(id) : Platform.os() != 3 ? gl().destroyQueries(id) : webgl() ? gl().destroyQueries(id) : wgpu().destroyQueries(id);

	public inline function queryResult(id:Int, k:Int):Int
		return Platform.os() == 1 ? mtl().queryResult(id, k) : Platform.os() == 2 ? d3d().queryResult(id, k) : Platform.os() != 3 ? gl().queryResult(id, k) : webgl() ? gl().queryResult(id, k) : wgpu().queryResult(id, k);

	public inline function resetQuery(id:Int, k:Int)
		Platform.os() == 1 ? mtl().resetQuery(id, k) : Platform.os() == 2 ? d3d().resetQuery(id, k) : Platform.os() != 3 ? gl().resetQuery(id, k) : webgl() ? gl().resetQuery(id, k) : wgpu().resetQuery(id, k);

	public inline function beginQuery(k:Int)
		Platform.os() == 1 ? mtl().beginQuery(k) : Platform.os() == 2 ? d3d().beginQuery(k) : Platform.os() != 3 ? gl().beginQuery(k) : webgl() ? gl().beginQuery(k) : wgpu().beginQuery(k);

	public inline function endQuery()
		Platform.os() == 1 ? mtl().endQuery() : Platform.os() == 2 ? d3d().endQuery() : Platform.os() != 3 ? gl().endQuery() : webgl() ? gl().endQuery() : wgpu().endQuery();

	public inline function endFrame()
		Platform.os() == 1 ? mtl().endFrame() : Platform.os() == 2 ? d3d().endFrame() : Platform.os() != 3 ? gl().endFrame() : webgl() ? gl().endFrame() : wgpu().endFrame();

	public inline function damaged(rects:Null<Array<Int>>)
		if (Platform.os() == 2) d3d().damaged(rects) else if (Platform.os() != 1 && Platform.os() != 3) gl().damaged(rects);

	public inline function waitFrame()
		if (Platform.os() == 2) d3d().waitFrame();

	public inline function paces():Bool
		return Platform.os() == 2 && d3d().paces();

	public inline function presentResult():Int
		return Platform.os() == 2 ? d3d().presentResult : 0;

	public inline function gpuTime():Float
		return Platform.os() == 2 ? d3d().gpuTime() : -1;

	public inline function software():Bool
		return Platform.os() == 2 && d3d().software;

	public inline function readPixels(dst:haxe.io.Bytes)
		Platform.os() == 1 ? mtl().readPixels(dst) : Platform.os() == 2 ? d3d().readPixels(dst) : Platform.os() != 3 ? gl().readPixels(dst) : webgl() ? gl().readPixels(dst) : wgpu().readPixels(dst);

	// ---- the compute tier (Device.has: WebGL2's GLBackend has none)

	public inline function has(f:Feature):Bool
		return Platform.os() == 1 ? mtl().has(f) : Platform.os() == 2 ? d3d().has(f) : Platform.os() != 3 ? gl().has(f) : webgl() ? gl().has(f) : wgpu().has(f);

	public inline function createComputePipeline(shader:Int):Int
		return Platform.os() == 1 ? mtl().createComputePipeline(shader) : Platform.os() == 2 ? d3d().createComputePipeline(shader) : Platform.os() != 3 ? gl().createComputePipeline(shader) : webgl() ? gl().createComputePipeline(shader) : wgpu().createComputePipeline(shader);

	public inline function readBuffer(id:Int, offset:Int, dst:haxe.io.Bytes, dstOffset:Int, size:Int)
		Platform.os() == 1 ? mtl().readBuffer(id, offset, dst, dstOffset, size) : Platform.os() == 2 ? d3d().readBuffer(id, offset, dst, dstOffset, size) : Platform.os() != 3 ? gl().readBuffer(id, offset, dst, dstOffset, size) : webgl() ? gl().readBuffer(id, offset, dst, dstOffset, size) : wgpu().readBuffer(id, offset, dst, dstOffset, size);

	public inline function beginCompute()
		Platform.os() == 1 ? mtl().beginCompute() : Platform.os() == 2 ? d3d().beginCompute() : Platform.os() != 3 ? gl().beginCompute() : webgl() ? gl().beginCompute() : wgpu().beginCompute();

	public inline function setComputePipeline(id:Int)
		Platform.os() == 1 ? mtl().setComputePipeline(id) : Platform.os() == 2 ? d3d().setComputePipeline(id) : Platform.os() != 3 ? gl().setComputePipeline(id) : webgl() ? gl().setComputePipeline(id) : wgpu().setComputePipeline(id);

	public inline function setStorage(slot:Int, id:Int)
		Platform.os() == 1 ? mtl().setStorage(slot, id) : Platform.os() == 2 ? d3d().setStorage(slot, id) : Platform.os() != 3 ? gl().setStorage(slot, id) : webgl() ? gl().setStorage(slot, id) : wgpu().setStorage(slot, id);

	public inline function setStorageTexture(slot:Int, id:Int)
		Platform.os() == 1 ? mtl().setStorageTexture(slot, id) : Platform.os() == 2 ? d3d().setStorageTexture(slot, id) : Platform.os() != 3 ? gl().setStorageTexture(slot, id) : webgl() ? gl().setStorageTexture(slot, id) : wgpu().setStorageTexture(slot, id);

	public inline function dispatch(x:Int, y:Int, z:Int)
		Platform.os() == 1 ? mtl().dispatch(x, y, z) : Platform.os() == 2 ? d3d().dispatch(x, y, z) : Platform.os() != 3 ? gl().dispatch(x, y, z) : webgl() ? gl().dispatch(x, y, z) : wgpu().dispatch(x, y, z);

	public inline function dispatchIndirect(id:Int, offset:Int)
		Platform.os() == 1 ? mtl().dispatchIndirect(id, offset) : Platform.os() == 2 ? d3d().dispatchIndirect(id, offset) : Platform.os() != 3 ? gl().dispatchIndirect(id, offset) : webgl() ? gl().dispatchIndirect(id, offset) : wgpu().dispatchIndirect(id, offset);

	public inline function endCompute()
		Platform.os() == 1 ? mtl().endCompute() : Platform.os() == 2 ? d3d().endCompute() : Platform.os() != 3 ? gl().endCompute() : webgl() ? gl().endCompute() : wgpu().endCompute();

	public inline function drawIndirect(id:Int, offset:Int)
		Platform.os() == 1 ? mtl().drawIndirect(id, offset) : Platform.os() == 2 ? d3d().drawIndirect(id, offset) : Platform.os() != 3 ? gl().drawIndirect(id, offset) : webgl() ? gl().drawIndirect(id, offset) : wgpu().drawIndirect(id, offset);

	public inline function drawIndexedIndirect(id:Int, offset:Int)
		Platform.os() == 1 ? mtl().drawIndexedIndirect(id, offset) : Platform.os() == 2 ? d3d().drawIndexedIndirect(id, offset) : Platform.os() != 3 ? gl().drawIndexedIndirect(id, offset) : webgl() ? gl().drawIndexedIndirect(id, offset) : wgpu().drawIndexedIndirect(id, offset);

	// (shared textures: Metal's, D3D11's and GL's; none in a browser)
	public inline function sharing():Null<String>
		return Platform.os() == 1 ? mtl().sharing() : Platform.os() == 2 ? d3d().sharing() : Platform.os() != 3 ? gl().sharing() : null;

	public inline function createShared(width:Int, height:Int):Null<{id:Int, handle:String}>
		return Platform.os() == 1 ? mtl().createShared(width, height) : Platform.os() == 2 ? d3d().createShared(width, height) : Platform.os() != 3 ? gl().createShared(width,
			height) : null;

	public inline function openShared(handle:String, width:Int, height:Int):Int
		return Platform.os() == 1 ? mtl().openShared(handle, width, height) : Platform.os() == 2 ? d3d().openShared(handle, width, height) : Platform.os() != 3 ? gl().openShared(handle,
			width, height) : 0;

	public inline function frameInto(id:Int)
		Platform.os() == 1 ? mtl().frameInto(id) : Platform.os() == 2 ? d3d().frameInto(id) : Platform.os() != 3 ? gl().frameInto(id) : if (id != 0) throw "helder.gfx: frameInto: not in a browser";

	// (the back end's context let go by this thread, used by the render thread from now on: GL's)
	public inline function detach()
		if (Platform.os() != 1 && Platform.os() != 2 && Platform.os() != 3) gl().detach();

	// (whether a frame was presented since asked last: Metal's, which a macOS window shows itself at)
	public inline function presented():Bool
		return Platform.os() == 1 ? mtl().presented() : false;

	public inline function dispose()
		Platform.os() == 1 ? mtl().dispose() : Platform.os() == 2 ? d3d().dispose() : Platform.os() != 3 ? gl().dispose() : webgl() ? gl().dispose() : wgpu().dispose();
}
#end
