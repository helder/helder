package media;

import haxe.io.Bytes;
import helder.async.Async;
import helder.media.*;
import helder.test.Gen;
import helder.test.Test;

// helder.media's containers (Mp4, Matroska) against tests/media's files
// mutated (Gen.mutated): each opened from memory, its packets read, then
// seeks to the middle and the start, ends in packets or a MediaError;
// natively within 10 s a case and 256 MB more memory. The fuzz lane soaks
// it (HELDER_PROPERTY_SOAK).
function tests() {
	var seeds = new Map<String, Bytes>();
	for (f in sys.FileSystem.readDirectory("tests/media"))
		if (~/\.(mp4|webm|mkv|mov)$/.match(f)) seeds.set(f, sys.io.File.getBytes('tests/media/$f'));

	test("a mutated container: packets, or a MediaError", () -> property(mutated(seeds), b -> Async.run(_ -> attempt(b)),
		{cases: 150, seconds: 3, limit: 10, memory: 256}));
}

// (a memory source never suspends: an error is thrown, not resumed with,
// so catching it here is safe, helder.async's README, "Not yet")
@:coroutine private function attempt(b:Bytes):Bool {
	try {
		var m = Media.open(new MemorySource(b));
		var p;
		while ((p = m.next()) != null) m.read(p);
		m.seek(m.duration > 0 ? m.duration / 2 : 0.5);
		m.seek(0);
		m.close();
		return true;
	} catch (e:MediaError) {
		return false;
	}
}
