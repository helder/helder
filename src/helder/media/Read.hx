package helder.media;

import haxe.io.Bytes;

class Read {
	// the most a box or an element read whole may take
	public static final LIMIT = 1 << 28;

	// n bytes at offset, fewer at the end
	@:coroutine public static function bytes(source:ByteSource, offset:Float, n:Int):Bytes {
		if (n < 0 || n > LIMIT) throw new MediaError("element too large");
		if (source.size >= 0 && offset + n > source.size) n = offset >= source.size ? 0 : Std.int(source.size - offset);
		var b = Bytes.alloc(n), got = 0;
		while (got < n) {
			var k = source.read(offset + got, b, got, n - got);
			if (k <= 0) break;
			got += k;
		}
		return got == n ? b : b.sub(0, got);
	}
}
