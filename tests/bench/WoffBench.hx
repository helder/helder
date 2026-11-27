import haxe.io.Bytes;
import helder.compress.Brotli;
import helder.text.Woff;
import sys.io.File;

// WOFF2's and WOFF's unwrapping (helder.text.Woff) of each file, natively,
// the least time of runs: the whole of it, and of a WOFF2 its Brotli stream
// alone (bench woff: a JSON line a file).
//
//   bin/bench/WoffBench <runs> <file.woff2> ...
class WoffBench {
	static function main() {
		var args = Sys.args();
		var runs = Std.parseInt(args[0]) ?? 20;
		for (f in args.slice(1)) {
			var data = File.getBytes(f);
			var whole = Math.POSITIVE_INFINITY, brotli = Math.POSITIVE_INFINITY, size = 0;
			for (_ in 0...runs) {
				// (a copy each run: Woff keeps the last file's sfnt)
				var b = Bytes.alloc(data.length);
				b.blit(0, data, 0, data.length);
				var t0 = haxe.Timer.stamp();
				size = Woff.sfnt(b).length;
				whole = Math.min(whole, haxe.Timer.stamp() - t0);
				if (data.getString(0, 4) != "wOF2") continue;
				var at = stream(data), t1 = haxe.Timer.stamp();
				Brotli.exact(data, at.pos, at.len, at.size);
				brotli = Math.min(brotli, haxe.Timer.stamp() - t1);
			}
			Sys.println(haxe.Json.stringify({file: f, bytes: data.length, sfnt: size, ms: ms(whole), brotliMs: Math.isFinite(brotli) ? ms(brotli) : null}));
		}
	}

	static function ms(s:Float):Float
		return Math.round(s * 1e6) / 1000;

	// (a WOFF2's stream: after its table directory, its tables' sizes summed)
	static function stream(b:Bytes):{pos:Int, len:Int, size:Int} {
		var n = b.get(12) << 8 | b.get(13), at = 48, size = 0;
		function base128() {
			var v = 0;
			while (true) {
				var c = b.get(at++);
				v = v << 7 | (c & 0x7f);
				if (c & 0x80 == 0) return v;
			}
		}
		for (_ in 0...n) {
			var flags = b.get(at++), tag = flags & 63;
			if (tag == 63) at += 4;
			var length = base128(), version = flags >> 6;
			var glyfOrLoca = tag == 10 || tag == 11;
			size += (glyfOrLoca ? version == 0 : version != 0) ? base128() : length;
		}
		return {pos: at, len: b.get(20) << 24 | b.get(21) << 16 | b.get(22) << 8 | b.get(23), size: size};
	}
}
