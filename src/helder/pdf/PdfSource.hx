package helder.pdf;

import haxe.io.Bytes;

// A PDF file's bytes at any offset, read synchronously: a Bytes' (Pdf.open's),
// a file's on disk (seeked), or a slower reader's blocks fetched first
// (PdfFetched). Document reads through it what a page needs (Pdf.openSource):
// the header, the tail, each object at its offset; read puts up to len bytes
// at offset into b from pos and returns how many (fewer only at the end).
interface PdfSource {
	var size(get, never):Int;
	function read(offset:Int, b:Bytes, pos:Int, len:Int):Int;
	function close():Void;
}

// A file in memory
class PdfBytes implements PdfSource {
	public final bytes:Bytes;
	public var size(get, never):Int;

	public function new(bytes:Bytes)
		this.bytes = bytes;

	function get_size():Int
		return bytes.length;

	public function read(offset:Int, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || offset >= bytes.length || len <= 0) return 0;
		var n = len < bytes.length - offset ? len : bytes.length - offset;
		b.blit(pos, bytes, offset, n);
		return n;
	}

	public function close() {}
}

// A file read by an asynchronous reader (a browser's Blob, a phone's
// document), its blocks of BLOCK bytes given as they are fetched (add): a
// read of one not given yet throws PdfMissing, which says where; its
// caller fetches that block and does again what it was doing (PdfMissing's
// own: the document's objects read so far are kept)
class PdfFetched implements PdfSource {
	public static inline var BLOCK = 65536;

	public var size(get, never):Int;

	final length:Int;
	final blocks = new Map<Int, Bytes>();

	public function new(size:Int)
		length = size;

	function get_size():Int
		return length;

	// the block at index (its bytes: BLOCK, the last one fewer)
	public function add(index:Int, bytes:Bytes)
		blocks.set(index, bytes);

	public function read(offset:Int, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || offset >= length || len <= 0) return 0;
		if (len > length - offset) len = length - offset;
		var done = 0;
		while (done < len) {
			var at = offset + done, i = Std.int(at / BLOCK), block = blocks.get(i);
			if (block == null) throw new PdfMissing(i, Std.int(Math.min(BLOCK, length - i * BLOCK)));
			var from = at - i * BLOCK, n = Std.int(Math.min(len - done, block.length - from));
			if (n <= 0) break;
			b.blit(pos + done, block, from, n);
			done += n;
		}
		return done;
	}

	public function close()
		blocks.clear();
}

// A read of a block PdfFetched has not been given: fetch it (offset:
// index * BLOCK, length bytes) and try again. Not a PdfError: what catches
// those lets it through.
class PdfMissing {
	public final index:Int;
	public final length:Int;

	public function new(index:Int, length:Int) {
		this.index = index;
		this.length = length;
	}

	public function toString():String
		return 'helder.pdf: block ${index} not read yet';
}
