package helder.media;

import haxe.io.Bytes;

// Bytes already in memory as a ByteSource.
class MemorySource implements ByteSource {
	public var size(get, never):Float;

	final bytes:Bytes;

	public function new(bytes:Bytes)
		this.bytes = bytes;

	function get_size():Float
		return bytes.length;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || pos < 0 || len < 0 || pos + len > b.length) throw new MediaError("read out of range");
		if (offset >= bytes.length) return 0;
		var at = Std.int(offset), n = len < bytes.length - at ? len : bytes.length - at;
		b.blit(pos, bytes, at, n);
		return n;
	}

	public function close() {}
}
