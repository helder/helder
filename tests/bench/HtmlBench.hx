import helder.dom.Dom;
import sys.io.File;

// helder.dom's parse of each file, the least time of runs (bench html: the
// file read and decoded before, not timed): a JSON line a file.
//
//   bin/bench/HtmlBench <runs> <file.html> ...
class HtmlBench {
	static function main() {
		var args = Sys.args();
		var runs = Std.parseInt(args[0]) ?? 5;
		for (f in args.slice(1)) {
			var html = File.getContent(f);
			var bytes = File.getBytes(f).length;
			var best = Math.POSITIVE_INFINITY;
			for (_ in 0...runs) {
				var t0 = haxe.Timer.stamp();
				var doc = Dom.parse(html);
				var t = haxe.Timer.stamp() - t0;
				if (doc.documentElement == null) throw "no document";
				if (t < best) best = t;
			}
			Sys.println(haxe.Json.stringify({file: f, bytes: bytes, ms: Math.round(best * 1e6) / 1000}));
		}
	}
}
