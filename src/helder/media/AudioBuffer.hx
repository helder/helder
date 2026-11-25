package helder.media;

import hxmc.unsafe.*;

// Interleaved stereo 32-bit floats off the collected heap, grown as
// decoders need: where they write a packet's frames (a C decoder writes
// there while the collector may run)
@:hxmc.unsafe(gc)
class AudioBuffer {
	public var data(default, null):Ptr<Float32> = Ptr.nil();
	// frames it holds room for
	public var frames(default, null) = 0;

	public function new() {}

	public function room(n:Int) {
		if (n <= frames) return;
		var next = frames == 0 ? 4096 : frames;
		while (next < n) next *= 2;
		var d:Ptr<Float32> = LibC.malloc((next * 8 : Int64));
		if (!data.isNull()) {
			LibC.memcpy(d, data, (frames * 8 : Int64));
			LibC.free(data);
		}
		data = d;
		frames = next;
	}

	public inline function set(i:Int, v:Float)
		Mem.setF32(data, i * 4, v);

	public inline function get(i:Int):Float
		return Mem.getF32(data, i * 4);

	public function dispose() {
		if (!data.isNull()) LibC.free(data);
		data = Ptr.nil();
		frames = 0;
	}
}
