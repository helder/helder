package helder.typescript;

import sys.FileSystem;

// What a generation of the declaration files read (Generator): a header
// (the compiler that ran it), then a line per file or directory, its size
// and time when it was read, and its path. Fresh while each is as it was.
class Stamp {
	public static function fresh(file:String, header:String):Bool {
		var text = try sys.io.File.getContent(file) catch (_:Dynamic) return false;
		var lines = text.split("\n");
		if (lines[0] != header) return false;
		for (i in 1...lines.length) {
			var line = lines[i];
			if (line == "") continue;
			var at = line.indexOf(" ", line.indexOf(" ") + 1);
			if (at < 0 || entry(line.substr(at + 1)) != line.substr(0, at)) return false;
		}
		return true;
	}

	// a file's or directory's size and modification time ("-": none)
	public static function entry(path:String):String {
		var s = try FileSystem.stat(path) catch (_:Dynamic) return "- -";
		return s.size + " " + s.mtime.getTime();
	}

	// (entries: path => entry; written whole or not at all, as builds may run at once)
	public static function write(file:String, header:String, entries:Map<String, String>) {
		var paths = [for (p in entries.keys()) p];
		paths.sort(Reflect.compare);
		atomic(file, [header].concat([for (p in paths) entries.get(p) + " " + p]).join("\n") + "\n");
	}

	// (a temporary file beside it, renamed over it)
	public static function atomic(file:String, text:String) {
		var dir = haxe.io.Path.directory(file);
		if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		var tmp = file + "." + Std.random(0x7fffffff) + ".tmp";
		try {
			sys.io.File.saveContent(tmp, text);
			FileSystem.rename(tmp, file);
		} catch (e:Dynamic) {
			try FileSystem.deleteFile(tmp) catch (_:Dynamic) {}
			throw e;
		}
	}
}
