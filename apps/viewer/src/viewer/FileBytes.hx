package viewer;

import haxe.io.Bytes;

// A file's bytes, all of them, through its Files' ByteSource: what the
// decodes read where a file is not on a disk (the web's, Android's
// documents).
class FileBytes {
	@:coroutine public static function read(files:Files, path:String):Bytes {
		var e = files.stat(path);
		if (e == null || e.kind == Folder) throw "No such file";
		// (a small file in one read, its size known: one more finds its end)
		var s = files.open(path), out = new haxe.io.BytesBuffer(), at = 0.0;
		var chunk = Bytes.alloc(e.size > 0 && e.size < 1 << 20 ? Std.int(e.size) + 1 : 1 << 20);
		try {
			var n = 0;
			while ((n = s.read(at, chunk, 0, chunk.length)) > 0) {
				out.addBytes(chunk, 0, n);
				at += n;
			}
		} catch (err:Dynamic) {
			s.close();
			throw err;
		}
		s.close();
		return out.getBytes();
	}
}
