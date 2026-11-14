package helder.gfx.webgpu;

import hxmc.unsafe.*;

// WebGPU through JavaScript (WebAssembly): imports of the module
// "hxmc_gfx", which src/helder/gfx/imports.mjs provides. The adapter and the
// device are requested before the module starts (the import convention of
// src/helder/os/browser.mjs lets imports.mjs wait), so they are ready here.
// GPU objects are handles into the loader's table of JavaScript objects (0:
// none). Formats, usages and states are helder.gfx's own enums' values, mapped
// on the JavaScript side. None calls back (@:hxmc.fast: memory may be passed
// by its address).
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_gfx") extern class WebGPU {
	// 1: there is a device (navigator.gpu and an adapter)
	static function ready():Int;
	// a colour target: a canvas (its handle: helder.os.Surface's) configured
	// for WebGPU in the preferred format, or a texture of that size (RGBA8)
	// (antialias 1: the canvas's frames multisampled, 4 samples a pixel; the page's run option antialias, when set, decides)
	static function target_canvas(canvas:Int, antialias:Int):Int;
	static function target_texture(width:Int, height:Int):Int;
	static function buffer(size:Int, usage:Int, data:Ptr, length:Int):Int;
	// size bytes at data into the buffer at offset (multiples of 4: WebGPU's writeBuffer)
	static function write_buffer(buffer:Int, offset:Int, data:Ptr, size:Int):Void;
	// a texture: its TextureFormat, mip levels, whether it is a render
	// target, its samples a pixel; its first level's texels at data (or none)
	// (storage 1: a compute stage writes it, STORAGE_BINDING)
	static function texture(width:Int, height:Int, format:Int, levels:Int, target:Int, samples:Int, storage:Int, data:Ptr):Int;
	// width x height texels at data into the mip level at x, y
	static function write_texture(texture:Int, x:Int, y:Int, width:Int, height:Int, level:Int, data:Ptr):Void;
	// the levels after the first, each a pass sampling the one before (in
	// the frame's command encoder, else in one of its own)
	static function generate_mips(texture:Int):Void;
	// 1: the device samples the TextureFormat (a compressed one: its feature asked for, the adapter having it)
	static function supports(format:Int):Int;
	// the device's maxTextureDimension2D
	static function max_texture():Int;
	// the texture (RGBA8 or RGBA8Srgb, the image's size) filled from a
	// browser image (helder_image's), at once when it is decoded, else once
	// it is; its levels after the first generated then; release 1: the
	// image freed after
	static function texture_image(texture:Int, image:Int, release:Int):Void;
	// a sampler: Filter, mip filter (0: none, 1: Nearest, 2: Linear), Wrap
	static function sampler(filter:Int, mipFilter:Int, wrap:Int):Int;
	// WGSL; errors are reported asynchronously, on the console
	static function shader(wgsl:CString):Int;
	// a pipeline: its vertex buffers (instance: 1 steps per instance) and
	// their attributes, then the rest
	static function pipeline_begin():Void;
	static function pipeline_buffer(stride:Int, instance:Int):Void;
	static function pipeline_attribute(location:Int, format:Int, offset:Int):Void;
	// a resource of the pipeline (ShaderCode.bindings: kind, slot, a uniform
	// block's size, a storage texture's TextureFormat): its bind group layout
	static function pipeline_binding(slot:Int, kind:Int, size:Int):Void;
	// a compute pipeline of the module's main and the resources given (pipeline_begin, pipeline_binding)
	static function compute_pipeline_end(shader:Int):Int;
	// a compute pass (in the frame's command encoder, else in one of its own, submitted at compute_end)
	static function compute_begin():Void;
	static function set_compute_pipeline(pipeline:Int):Void;
	// the storage buffer or texture at the slot, for the bind group
	static function set_storage(slot:Int, buffer:Int):Void;
	static function set_storage_texture(slot:Int, texture:Int):Void;
	static function dispatch(x:Int, y:Int, z:Int):Void;
	static function dispatch_indirect(buffer:Int, offset:Int):Void;
	static function compute_end():Void;
	static function draw_indirect(buffer:Int, offset:Int):Void;
	static function draw_indexed_indirect(buffer:Int, offset:Int):Void;
	// (colorFormat: a TextureFormat, -1 the target's; depthFormat: -1 none;
	// samples: a render target's, the frame's its own)
	static function pipeline_end(vertex:Int, fragment:Int, target:Int, topology:Int, cull:Int, blend:Int, depthCompare:Int, depthWrite:Int,
		colorFormat:Int, depthFormat:Int, samples:Int):Int;
	// a frame: a command encoder for the target's texture (the canvas's
	// current one) and its depth texture (depth32float, remade when the size
	// changes); 0: none now
	static function frame_begin(target:Int):Int;
	// a pass into the color texture (0: the frame's target and its depth
	// texture) resolved into resolve (0: none; a multisampled colour's), and
	// the depth texture (0: none); loads: LoadOp
	static function pass_begin(color:Int, resolve:Int, load:Int, r:Float, g:Float, b:Float, a:Float, depthTexture:Int, depthLoad:Int, depth:Float):Void;
	static function set_pipeline(pipeline:Int):Void;
	static function set_vertex_buffer(slot:Int, buffer:Int, offset:Int):Void;
	// size bytes at data into the frame's uniform ring at offset (256-byte
	// aligned), bound at the slot (a dynamic offset); written to the GPU
	// when the frame is submitted
	static function set_uniforms(slot:Int, offset:Int, data:Ptr, size:Int):Void;
	// the texture and sampler at the slot, for the bind group
	static function set_texture(slot:Int, texture:Int, sampler:Int):Void;
	static function set_index_buffer(buffer:Int, format:Int, offset:Int):Void;
	static function draw(vertices:Int, instances:Int, first:Int):Void;
	static function draw_indexed(count:Int, instances:Int, first:Int, baseVertex:Int):Void;
	static function pass_end():Void;
	// submits the frame (the canvas presents it when the task ends)
	static function frame_end():Void;
	static function release(handle:Int):Void;
}
