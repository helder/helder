package helder.media;

import haxe.io.Bytes;
import sys.io.File;
import sys.io.FileInput;

// A local file as a ByteSource: natively, and on wasm32-wasi where the
// runtime has files (node's WASI; a browser has none: WebSource). Reads
// do not suspend: a local file's are short.
class FileSource implements ByteSource {
	public var size(get, never):Float;

	final input:FileInput;
	final total:Float;
	var at = 0.0;

	public function new(path:String) {
		var s = hxmc.NativeSys.stat(path);
		if (s == null) throw new MediaError('no file $path');
		total = s[9];
		input = File.read(path, true);
	}

	function get_size():Float
		return total;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int
		return readAt(offset, b, pos, len);

	// (a plain function: helder.async's coroutines rethrow a caught error, README "Not yet")
	function readAt(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || pos < 0 || len < 0 || pos + len > b.length) throw new MediaError("read out of range");
		if (offset >= total || len == 0) return 0;
		if (len > total - offset) len = Std.int(total - offset);
		move(offset);
		var n = 0;
		while (n < len) {
			var k = try input.readBytes(b, pos + n, len - n) catch (e:haxe.io.Eof) 0;
			if (k <= 0) break;
			n += k;
		}
		at = offset + n;
		return n;
	}

	// (seek takes an Int: a far offset in steps from where the file is, so
	// that files past 2 GiB read too)
	function move(offset:Float) {
		if (offset == at) return;
		var d = offset - at;
		if (Math.abs(d) > offset) {
			input.seek(0, SeekBegin);
			d = offset;
		}
		while (d != 0) {
			var step = d > 0x40000000 ? 0x40000000 : d < -0x40000000 ? -0x40000000 : Std.int(d);
			input.seek(step, SeekCur);
			d -= step;
		}
		at = offset;
	}

	public function close()
		input.close();
}
