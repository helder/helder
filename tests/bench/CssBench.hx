import helder.css.Css;
import sys.io.File;

// helder.css's speed on stylesheets (the bench css lane, natively and as
// wasm32-wasi): each sheet tokenized, and parsed as a stylesheet (tokens,
// then rules and declarations), each the least of RUNS (10) after one
// warm-up; a JSON line per sheet and phase.
//
//   CssBench <sheet.css>...
class CssBench {
	static function main() {
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 10;
		for (path in Sys.args()) {
			var bytes = File.getBytes(path), text = Css.decode(bytes).text, name = haxe.io.Path.withoutDirectory(path);
			var count = 0;
			report(name, bytes.length, "tokens", least(runs, () -> count = Css.tokens(text).length), count);
			var rules = 0;
			report(name, bytes.length, "sheet", least(runs, () -> rules = Css.sheet(text).length), rules);
		}
	}

	static function least(runs:Int, f:() -> Void):Float {
		f();
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...runs) {
			var t = haxe.Timer.stamp();
			f();
			var ms = (haxe.Timer.stamp() - t) * 1000;
			if (ms < best) best = ms;
		}
		return best;
	}

	static function report(name:String, bytes:Int, phase:String, ms:Float, count:Int)
		Sys.println('{"sheet":"$name","bytes":$bytes,"phase":"$phase","ms":${Math.round(ms * 1000) / 1000},"count":$count}');
}
