package viewer;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// The web build's sample folder: samples/ (its README.md says what each
// file is and where it comes from) as the browser lists it, "Samples" and
// its subfolders, read when compiling; on the web each file's bytes are
// fetched from beside the page (helder.asset's Asset.bytes) when first read.
class Samples {
	public static inline var ROOT = "Samples";
	// (a time of their own: a checkout's would differ run by run)
	public static inline var MODIFIED = 1795521600.0;

	#if !macro
	// the files: their paths under ROOT, in samples/ (file), their sizes
	public static final FILES:Array<{path:String, file:String, size:Int}> = list();

	#if (hxmc.target == "wasm32-wasi")
	// a file's bytes, fetched once
	public static function asset(path:String):Null<helder.asset.Asset<haxe.io.Bytes>>
		return assets(path);
	#end
	#end

	// the folder holding samples/ on the disk it was compiled on (the tests')
	public static macro function home():Expr {
		var dir = haxe.io.Path.directory(Context.getPosInfos(Context.currentPos()).file);
		return macro $v{sys.FileSystem.fullPath(haxe.io.Path.join([dir, "..", ".."]))};
	}

	static macro function list():Expr {
		var all:Array<Expr> = [];
		for (f in files()) {
			var path = ROOT + "/" + f.path, file = "samples/" + f.path, size = f.size;
			all.push(macro {path: $v{path}, file: $v{file}, size: $v{size}});
		}
		return macro $a{all};
	}

	static macro function assets(path:Expr):Expr {
		var cases:Array<Case> = [];
		for (f in files()) {
			var key = ROOT + "/" + f.path, file = "samples/" + f.path;
			cases.push({values: [macro $v{key}], expr: macro helder.asset.Asset.bytes($v{file})});
		}
		return {expr: ESwitch(path, cases, macro null), pos: Context.currentPos()};
	}

	static function files():Array<{path:String, size:Int}> {
		#if !macro
		return [];
		#else
		var root = haxe.io.Path.join([haxe.io.Path.directory(Context.getPosInfos(Context.currentPos()).file), "..", "..", "samples"]);
		var out = [];
		function walk(dir:String, rel:String) {
			Context.registerModuleDependency(Context.getLocalModule(), dir);
			for (n in sys.FileSystem.readDirectory(dir)) {
				if (StringTools.startsWith(n, ".") || rel == "" && n == "README.md") continue;
				var p = dir + "/" + n, r = rel == "" ? n : rel + "/" + n;
				if (sys.FileSystem.isDirectory(p)) walk(p, r) else out.push({path: r, size: Std.int(sys.FileSystem.stat(p).size)});
			}
		}
		walk(root, "");
		out.sort((a, b) -> Reflect.compare(a.path, b.path));
		return out;
		#end
	}
}
