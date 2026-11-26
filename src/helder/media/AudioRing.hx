package helder.media;

import hxmc.unsafe.*;

// Decoded stereo frames between the player (writing, on its thread) and
// the audio callback (reading, on the audio thread): a ring of 32-bit
// floats off the heap, positions in frames, one writer and one reader;
// cleared only while the output is stopped
@:hxmc.unsafe(gc)
class AudioRing {
	public final capacity:Int;
	final data:Ptr<Float32>;
	// (frames written and read: the writer's and the reader's, atomics)
	final at:Ptr<Int32>;

	public function new(capacity:Int) {
		var c = 1;
		while (c < capacity) c <<= 1;
		this.capacity = c;
		data = LibC.malloc((c * 8 : Int64));
		at = LibC.malloc(8);
		clear();
	}

	public var written(get, never):Int;
	public var read(get, never):Int;

	inline function get_written():Int
		return Atomic.load32(at);

	inline function get_read():Int
		return Atomic.load32(at.add(4));

	public function available():Int
		return written - read;

	public function room():Int
		return capacity - available();

	public function clear() {
		Atomic.store32(at, 0);
		Atomic.store32(at.add(4), 0);
	}

	// n frames of from (interleaved stereo) from frame first, as many as fit
	public function write(from:AudioBuffer, first:Int, n:Int):Int {
		var w = written;
		if (n > room()) n = room();
		for (i in 0...n) {
			var k = ((w + i) & (capacity - 1)) * 2;
			Mem.setF32(data, k * 4, from.get((first + i) * 2));
			Mem.setF32(data, k * 4 + 4, from.get((first + i) * 2 + 1));
		}
		Atomic.store32(at, w + n);
		return n;
	}

	// (the audio thread) up to n frames into out, times gain: the frames given
	public function take(out:Ptr<Float32>, n:Int, gain:Float):Int {
		var r = read, k = written - r;
		if (k < n) n = k;
		for (i in 0...n) {
			var s = ((r + i) & (capacity - 1)) * 8;
			Mem.setF32(out, i * 8, Mem.getF32(data, s) * gain);
			Mem.setF32(out, i * 8 + 4, Mem.getF32(data, s + 4) * gain);
		}
		Atomic.store32(at.add(4), r + n);
		return n;
	}

	public function dispose() {
		LibC.free(data);
		LibC.free(at);
	}
}
