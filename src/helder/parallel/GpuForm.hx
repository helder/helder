package helder.parallel;

#if !macro
// A call site's GPU form, as data (ParallelMacro writes one beside each
// each and kernel): the compute stage's code in the build's languages, its
// uniform block (the captures' values and the count, at their std140
// offsets) and its storage buffers' slots. GpuRunner dispatches it; data
// alone, so that a program that never sets Parallel.device compiles none
// of helder.gfx's calls.
@:noCompletion
class GpuForm {
	// the stage (ShaderCode: helder.gfx's, written as a ComputeShader's)
	public final code:helder.gfx.ShaderCode;
	// the uniform block: its size, its slot, the count's offset in it
	public final block:Int;
	public final binding:Int;
	public final count:Int;
	// each captured value: its kind (KINT, KBOOL, KFLOAT, KVEC + n, KMAT),
	// its place in the dispatch's context, its offset in the block
	public final kinds:Array<Int>;
	public final from:Array<Int>;
	public final to:Array<Int>;
	// each Items: its storage slot, whether the stage writes it
	public final slots:Array<Int>;
	public final writes:Array<Bool>;
	// (GpuRunner's: the pipeline made on a device, the block's bytes)
	public var pipeline:Any = null;
	public var device:Any = null;
	public final bytes:haxe.io.Bytes;

	public static inline var KINT = 0;
	public static inline var KBOOL = 1;
	public static inline var KFLOAT = 2;
	public static inline var KMAT = 3;
	public static inline var KVEC = 10;

	public function new(code, block, binding, count, kinds, from, to, slots, writes) {
		this.code = code;
		this.block = block;
		this.binding = binding;
		this.count = count;
		this.kinds = kinds;
		this.from = from;
		this.to = to;
		this.slots = slots;
		this.writes = writes;
		bytes = haxe.io.Bytes.alloc(block);
	}
}
#end
