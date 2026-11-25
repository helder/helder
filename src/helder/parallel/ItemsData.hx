package helder.parallel;

#if !macro
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// An Items' memory: its record (what helder.gfx.soft.Buffers takes for a
// storage binding: the bytes' address, then their count) and the elements
// after it, length of them at stride bytes, padded to a multiple of 4
// elements (the range form reads 4 in a row), zeroed; freed by dispose()
// or, never disposed, once collected (a finaliser).
@:noCompletion @:hxmc.unsafe(gc)
class ItemsData {
	public static inline var DATA = 0;
	public static inline var BYTES = 8;
	static inline var HEAD = 16;

	public final length:Int;
	public final stride:Int;

	var record:Ptr;

	public function new(length:Int, stride:Int) {
		if (length < 0) throw new haxe.Exception('Items: a length of $length');
		this.length = length;
		this.stride = stride;
		var size = HEAD + ((length + 3) & ~3) * stride;
		record = LibC.malloc(size);
		if (record.isNull()) throw new haxe.Exception('Items: no memory for $length items of $stride bytes');
		LibC.memset(record, 0, size);
		Mem.setPtr(record, DATA, record.add(HEAD));
		Mem.setI32(record, BYTES, length * stride);
		hxmc.NativeGc.finalise(collected, this);
	}

	public var disposed(get, never):Bool;

	function get_disposed()
		return record.isNull();

	public function dispose() {
		if (record.isNull()) return;
		LibC.free(record);
		record = Ptr.nil();
	}

	static function collected(d:ItemsData) {
		if (d.record.isNull()) return;
		#if debug
		Sys.println('helder.parallel: an Items of ${d.length} was collected, never disposed');
		#end
		d.dispose();
	}

	// (the record, a storage binding; null once disposed)
	public inline function binding():Ptr
		return record;

	// the byte of element i (a bounds check)
	public function at(i:Int):Int {
		if (record.isNull()) throw new haxe.Exception('Items: disposed');
		if (i < 0 || i >= length) throw new haxe.Exception('Items: index $i outside 0...$length');
		return HEAD + i * stride;
	}

	public function f32(o:Int):Float
		return Mem.getF32(record, o);

	public function setF32(o:Int, v:Float)
		Mem.setF32(record, o, v);

	public function i32(o:Int):Int
		return Mem.getI32(record, o);

	public function setI32(o:Int, v:Int)
		Mem.setI32(record, o, v);
}
#end
