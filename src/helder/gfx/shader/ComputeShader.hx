package helder.gfx.shader;

import helder.math.*;
import haxe.io.Bytes;
import helder.gfx.ComputePipelineDesc;
import helder.gfx.ShaderCode;
import helder.gfx.shader.Shader.TextureBinding;
import helder.gfx.shader.Shader.UniformBlock;

// A compute stage: what compute({size, main}) makes (ShaderMath.compute, a
// definition), its function compiled at build time, on the devices that
// have them (Device.has(Compute): WebGPU, Metal, D3D11, GL ES 3.1; not
// WebGL2, which keeps the render stages' path):
//
//   @:structInit @:publicFields class Particle { var pos:Vec4; var vel:Vec4; }
//   @:structInit @:publicFields class Step { var dt:Float; var count:Int; }
//
//   final Update = compute({
//     size: [64],
//     main: function(id:ComputeInput, p:{step:Step, particles:RWStorage<Particle>}) {
//       if (id.x >= p.step.count) return;
//       var q = p.particles[id.x];
//       p.particles[id.x] = {pos: q.pos + q.vel * p.step.dt, vel: q.vel};
//     }
//   });
//   var pipeline = device.createComputePipeline(Update.pipeline());
//   ...
//   enc.beginCompute();
//   enc.setComputePipeline(pipeline);
//   enc.setUniforms(Update.params.step.block.binding, stepBytes);
//   enc.setStorage(Update.params.particles.binding, particles);  // a Storage buffer
//   enc.dispatch(Update.groups(count));
//   enc.endCompute();
//
// The function takes the invocation's ids (ComputeInput) and one object of
// parameters, as the render stages do (and a third, its workgroup memory:
// Workgroup; barrier() and the subgroup operations, ShaderMath): its fields uniform blocks (structs,
// std140), textures (Texture2D, sampled at the first mip level or one
// given), storage buffers (Storage<T> read, RWStorage<T> read and written:
// std430) and storage textures (StorageTexture, written), at slots 0, 1,
// ... in order. It returns nothing: it writes its storage. size is the
// workgroup's, x, y, z (1 for the ones left out; 256 invocations at most).
// The shader has:
//
//   code                 its ShaderCode, in the target's languages (its workgroupSize)
//   size                 the workgroup's size
//   pipeline()           a ComputePipelineDesc of it (Device.createComputePipeline)
//   emulated()           one of its second form, its subgroups made of
//                        workgroup memory (what a device without them runs)
//   groups(n, axis)      the workgroups that cover n invocations along an axis
//   params.<name>        a uniform block's writer (UniformWriter), a
//                        texture's slot (TextureSlot), a storage buffer's
//                        (StorageSlot: .binding, .stride, store and load
//                        the CPU's bytes as std430) or a storage texture's
//                        (StorageTextureSlot: .binding, .format)
//   main                 the function as CPU code (ComputeInput.at gives the ids)
//   uniformBytes(), uniformBinding, bind(encoder)
//                        the block of the uniform(...)s it reads
class ComputeShader<P> {
	public final code:ShaderCode;
	public final size:Array<Int>;
	public final uniforms:Array<UniformBlock>;
	public final textures:Array<TextureBinding>;
	public final params:P;

	public function new(code, size, uniforms, textures, params) {
		this.code = code;
		this.size = size;
		this.uniforms = uniforms;
		this.textures = textures;
		this.params = params;
	}

	public function pipeline():ComputePipelineDesc
		return {program: code};

	// a pipeline of its second form, its subgroups made of workgroup
	// memory (ShaderCode.emulated: what a device without Feature.Subgroups
	// runs; tests run it where the device has them), else pipeline()
	public function emulated():ComputePipelineDesc
		return {program: helder.gfx.ShaderCode.emulatedForm(code)};

	// the workgroups that cover n invocations along an axis (0: x, 1: y, 2: z)
	public inline function groups(n:Int, axis = 0):Int
		return Std.int((n + size[axis] - 1) / size[axis]);

	// the slot of the block of the uniform(...)s the stage reads (-1: none)
	public var uniformBinding(default, null) = -1;

	// that block with the uniforms' values now (null: none)
	public function uniformBytes():Null<Bytes>
		return null;
}

// a storage buffer parameter's slot (Encoder.setStorage(slot.binding, ...))
// and its elements' std430 layout. Each parameter's is a class of its own
// (its element's type T) with store(values:Array<T>, bytes, offset = 0),
// storeAt(value:T, bytes, offset), load(bytes, i, offset = 0):T and
// bytesOf(values:Array<T>):Bytes: the elements written as the GPU reads
// them, one read back (Device.readBuffer's bytes)
class StorageSlot {
	// the parameter's name
	public final name:String;
	public final binding:Int;
	// the bytes an element takes in the buffer
	public final stride:Int;
	// RWStorage: the stage writes it
	public final writable:Bool;

	public function new(name, binding, stride, writable) {
		this.name = name;
		this.binding = binding;
		this.stride = stride;
		this.writable = writable;
	}
}

// a storage texture parameter's slot (Encoder.setStorageTexture(slot.binding, ...)) and its format
class StorageTextureSlot {
	public final name:String;
	public final binding:Int;
	public final format:helder.gfx.TextureFormat;

	public function new(name, binding, format) {
		this.name = name;
		this.binding = binding;
		this.format = format;
	}
}
