package helder.typescript;

using StringTools;

// A program whose helder/* modules are another helder's than the
// compiler's (a project's tsconfig.json paths to an older checkout): its
// declarations are not the ones the compiler lowers, so what it names of
// helder is "not in the program" (TSHX004). The other helder's source
// directory, or null.
class Mixed {
	public static function of(files:Array<String>, src:String):Null<String> {
		var own = haxe.io.Path.normalize(src.replace("\\", "/"));
		var module = ~/^(.*)\/helder\/([a-z0-9_]+)(\/[a-z0-9_]+)*\/index\.(d\.)?ts$/;
		for (f in files) {
			var p = haxe.io.Path.normalize(f.replace("\\", "/"));
			if (p.startsWith(own + "/") || !module.match(p)) continue;
			if (sys.FileSystem.exists('$own/helder/${module.matched(2)}')) return module.matched(1);
		}
		return null;
	}

	// a TSHX004's message with its cause, when that is it
	public static function explain(message:String, files:Array<String>, src:String):String {
		if (message.indexOf("TSHX004") < 0) return message;
		var other = of(files, src);
		return other == null ? message : message
			+ '\nTSHX004: two helder sources mixed: the program imports helder from $other/helder (a tsconfig.json\'s paths?), the compiler is $src/helder';
	}
}
