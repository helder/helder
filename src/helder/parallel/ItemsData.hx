package helder.parallel;

#if !macro
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// An Items' memory: its record (what helder.gfx.soft.Buffers takes for a
// storage binding: the bytes' address, then their count) and its bytes,
// length elements of stride bytes, padded to a multiple of 4 elements (the
// range form reads 4 in a row), zeroed; freed by dispose() or, never
// disposed, once collected (a finaliser).
//
// Where its values are (state): the CPU's bytes (CPU), its GPU buffer's
// (GPU), or both; a copy moves only when the other side reads (GpuRunner:
// the dispatch's and the draws' side, reached from Parallel.device alone,
// so that a program without a GPU has none of helder.gfx). On a device
// whose buffers the CPU shares (Metal, the CPU back end) the bytes become
// the buffer's own (shared): nothing is copied, a read after a dispatch
// waits for it.
@:noCompletion @:hxmc.unsafe(gc)
class ItemsData {
	public static inline var DATA = 0;
	public static inline var BYTES = 8;
	static inline var HEAD = 16;

	public static inline var CPU = 1;
	public static inline var GPU = 2;

	public final length:Int;
	public final stride:Int;
	// the bytes held (padded): what a GPU buffer of them takes
	public final size:Int;

	var record:Ptr;
	var own:Ptr;

	public var state = CPU;
	// (GpuRunner's: the helder.gfx.Buffer, its device; the bytes the buffer's)
	public var buffer:Any = null;
	public var device:Any = null;
	public var shared = false;
	// a GPU draws it (Items.buffer), or a dispatch wrote it last: Auto moves
	// the bodies that write it there
	public var drawn = false;
	public var byGpu = false;
	// (shared bytes a dispatch or a draw may still be reading: the CPU's next
	// access waits for the GPU first. Without it a write after a dispatch
	// (Particles' next births) landed in memory the dispatch had not read yet:
	// Metal's shared buffers, whose dispatches outside a frame run after the
	// call returns)
	public var busy = false;

	public function new(length:Int, stride:Int) {
		if (length < 0) throw new haxe.Exception('Items: a length of $length');
		this.length = length;
		this.stride = stride;
		size = ((length + 3) & ~3) * stride;
		record = LibC.malloc(HEAD);
		own = LibC.malloc(size == 0 ? 16 : size);
		if (record.isNull() || own.isNull()) throw new haxe.Exception('Items: no memory for $length items of $stride bytes');
		LibC.memset(own, 0, size);
		Mem.setPtr(record, DATA, own);
		Mem.setI32(record, BYTES, length * stride);
		hxmc.NativeGc.finalise(collected, this);
	}

	public var disposed(get, never):Bool;

	function get_disposed()
		return record.isNull();

	public function dispose()
		free(true);

	function free(now:Bool) {
		if (record.isNull()) return;
		if (buffer != null) Parallel.release(this, now);
		if (!own.isNull()) LibC.free(own);
		LibC.free(record);
		record = own = Ptr.nil();
	}

	static function collected(d:ItemsData) {
		if (d.record.isNull()) return;
		#if debug
		Sys.println('helder.parallel: an Items of ${d.length} was collected, never disposed');
		#end
		d.free(false);
	}

	// (the record, a storage binding; null once disposed)
	public inline function binding():Ptr
		return record;

	// the bytes
	public inline function bytes():Ptr
		return Mem.getPtr(record, DATA);

	// (the bytes the buffer's from now on, its copy of them made: the own ones freed)
	public function adopt(memory:Ptr) {
		Mem.setPtr(record, DATA, memory);
		LibC.free(own);
		own = Ptr.nil();
		shared = true;
	}

	// (the values the CPU's: read back first where they are the GPU's alone,
	// waited for where the GPU may still read its shared bytes)
	public inline function cpu()
		if (state & CPU == 0 || busy) Parallel.fetch(this);

	// (written on the CPU: the GPU's copy stale, unless the bytes are its)
	public inline function cpuWrote() {
		state = shared ? CPU | GPU : CPU;
		byGpu = false;
	}

	// the byte of element i (a bounds check), its values the CPU's
	public function at(i:Int):Int {
		if (record.isNull()) throw new haxe.Exception('Items: disposed');
		if (i < 0 || i >= length) throw new haxe.Exception('Items: index $i outside 0...$length');
		cpu();
		return i * stride;
	}

	// (the same, for a write)
	public function atWrite(i:Int):Int {
		var o = at(i);
		cpuWrote();
		return o;
	}

	public function f32(o:Int):Float
		return Mem.getF32(bytes(), o);

	public function setF32(o:Int, v:Float)
		Mem.setF32(bytes(), o, v);

	public function i32(o:Int):Int
		return Mem.getI32(bytes(), o);

	public function setI32(o:Int, v:Int)
		Mem.setI32(bytes(), o, v);
}
#end
