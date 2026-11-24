import haxe.Timer;
import haxe.io.Path;
import helder.async.Async;
import sys.FileSystem;
import viewer.ThumbCache;
import viewer.Thumbnails;

// One request at a time: per-file latency from request to image, including
// the job's handoff. The cold pass starts with an empty cache; the warm
// pass reopens it. Small files still decode both times.
//   cd apps/viewer && helder build tests/bench/ThumbBench.hx
//   bin/<target>/ThumbBench <folder>
class ThumbBench {
	static function main() {
		var args = Sys.args();
		if (args.length != 1 || !FileSystem.isDirectory(args[0])) {
			Sys.stderr().writeString("usage: ThumbBench <folder>\n");
			Sys.exit(1);
		}
		var paths = files(FileSystem.fullPath(args[0]));
		var dir = helder.os.Paths.temp() + "/viewer-thumb-bench-" + Std.random(0x40000000);
		try {
			var cold = pass(paths, dir), warm = pass(paths, dir);
			Sys.println("extension   files    cold median/p95 (ms)    warm median/p95 (ms)");
			var kinds = [for (kind in cold.keys()) kind];
			kinds.sort(Reflect.compare);
			for (kind in kinds) {
				var a = cold.get(kind), b = warm.get(kind);
				Sys.println(StringTools.rpad(kind, " ", 12) + StringTools.rpad(Std.string(a.length), " ", 9) + stats(a) + "                 " + stats(b));
			}
			var bytes = 0.0;
			for (name in FileSystem.readDirectory(dir)) bytes += FileSystem.stat(dir + "/" + name).size;
			Sys.println('Cache: $bytes bytes on disk for ${paths.length} files');
		} catch (e:Dynamic) {
			clean(dir);
			throw e;
		}
		clean(dir);
	}

	static function files(folder:String):Array<String> {
		var out = [], pending = [folder], seen = new Map<String, Bool>();
		while (pending.length > 0) {
			var dir = pending.pop(), target = FileSystem.fullPath(dir);
			if (seen.exists(target)) continue;
			seen.set(target, true);
			for (name in FileSystem.readDirectory(dir)) {
				var path = dir + "/" + name;
				if (FileSystem.isDirectory(path)) pending.push(path) else out.push(path);
			}
		}
		out.sort(Reflect.compare);
		return out;
	}

	static function pass(paths:Array<String>, dir:String):Map<String, Array<Float>> {
		var cache = new ThumbCache(512 << 20, 16 << 20, dir);
		if (cache.readOnly) {
			cache.close();
			throw "ThumbBench: cannot write a cache at " + dir;
		}
		var queue = new Thumbnails(cache);
		var elapsed = new Map<String, Array<Float>>();
		try Async.run(_ -> {
			for (path in paths) {
				var st = FileSystem.stat(path), kind = Path.extension(path).toLowerCase();
				if (kind == "") kind = "(none)";
				var times = elapsed.get(kind);
				if (times == null) {
					times = [];
					elapsed.set(kind, times);
				}
				var start = Timer.stamp();
				var ms = Async.suspend(cont -> {
					queue.request(path, st.size, st.mtime.getTime(), Thumbnails.SIDE, 0, _ -> Async.resumeLater(cont, (Timer.stamp() - start) * 1000, null));
				});
				times.push(ms);
			}
		}) catch (e:Dynamic) {
			queue.close();
			throw e;
		}
		queue.close();
		return elapsed;
	}

	static function stats(t:Array<Float>):String {
		t.sort(Reflect.compare);
		var middle = t.length >> 1;
		var median = (t.length & 1) == 1 ? t[middle] : (t[middle - 1] + t[middle]) / 2;
		return ms(median) + "/" + ms(t[Math.ceil(t.length * 0.95) - 1]);
	}

	static function ms(n:Float):String
		return Std.string(Math.round(n * 1000) / 1000);

	static function clean(dir:String) {
		if (!FileSystem.exists(dir)) return;
		for (name in FileSystem.readDirectory(dir)) FileSystem.deleteFile(dir + "/" + name);
		FileSystem.deleteDirectory(dir);
	}
}
