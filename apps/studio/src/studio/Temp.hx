package studio;

import helder.cli.TestCommand;

// A test's folder of its own in the system's temp: unique to its run, since
// runs from other checkouts share TMPDIR; removed when done, failed or not
class Temp {
	public static function dir(name:String):String {
		var base = Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp";
		var d = haxe.io.Path.normalize('$base/$name-${Std.int(haxe.Timer.stamp() * 1000)}-${Std.random(1 << 30)}');
		TestCommand.mkdirs(d);
		return d;
	}

	// (a build still writing into it may keep it: left to the system's temp then)
	public static function remove(dir:String)
		try if (sys.FileSystem.exists(dir)) TestCommand.rmrf(dir) catch (_:Dynamic) {}

	public static function within<T>(name:String, f:String->T):T {
		var d = dir(name);
		var out = try f(d) catch (e:haxe.Exception) {
			remove(d);
			throw e;
		}
		remove(d);
		return out;
	}
}
