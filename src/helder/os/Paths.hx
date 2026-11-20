package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

// The app's directories, absolute, each made when missing; null where
// there are none (the web):
// - data: persistent and the app's own;
// - cache: kept while there is room, which the system may empty;
// - temp: for a while;
// - documents: the user's, where they see the app's files: the Files app
//   on iOS (Info.plist's UIFileSharingEnabled and
//   LSSupportsOpeningDocumentsInPlace, set by use), the app's folder of
//   Android's shared storage, the desktop's Documents.
// The desktop's data and cache are under the app's name (macOS: its bundle
// id; else the executable's name).
class Paths {
	static inline var TEMP = 0;
	static inline var DOCUMENTS = 9;
	static inline var CACHE = 13;
	static inline var DATA = 14;

	@:typescript public static function data():Null<String>
		return made(find(DATA));

	@:typescript public static function cache():Null<String>
		return made(find(CACHE));

	@:typescript public static function temp():Null<String>
		return made(find(TEMP));

	@:typescript public static function documents():Null<String>
		return made(Documents.find());

	// (which: NSSearchPathDirectory's numbers, the other systems' mapped from
	// them; app: the desktop's folder under data and cache, helder.os.Store's)
	@:allow(helder.os) static function find(which:Int, ?app:String):Null<String> {
		#if (target.name == "hxmc")
		if (Platform.os() == Platform.WASI) return null;
		if (Platform.os() == Platform.MACOS) {
			var d = PathsApple.dir(which);
			return d == null || Platform.apple() >= 1 || which == TEMP || which == DOCUMENTS ? d : d + "/" + (app ?? PathsApple.bundleId() ?? name());
		}
		if (Platform.os() == Platform.WINDOWS) return PathsDesktop.windows(which, app ?? name());
		if (Platform.target() >= 9) return which == DATA ? helder.os.android.AndroidPaths.files() : helder.os.android.AndroidPaths.dir(which == DOCUMENTS ? "documents" : "cache");
		var home = Sys.getEnv("HOME") ?? "";
		var dirs = which != DOCUMENTS ? null : try sys.io.File.getContent((Sys.getEnv("XDG_CONFIG_HOME") ?? home + "/.config") + "/user-dirs.dirs") catch (_:Dynamic) null;
		return PathsDesktop.linux(which, Sys.getEnv, dirs, app ?? name());
		#else
		return null;
		#end
	}

	// (the executable's name, without its extension)
	static function name():String
		return haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(Sys.programPath()));

	static function made(d:Null<String>):Null<String> {
		if (d == null || d == "") return null;
		#if sys
		try if (!sys.FileSystem.exists(d)) sys.FileSystem.createDirectory(d) catch (_:Dynamic) {}
		#end
		return d;
	}
}

// (its own class: what an iOS app's Info.plist needs by use)
@:helder.ios.plist("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace")
private class Documents {
	public static function find():Null<String>
		return @:privateAccess Paths.find(Paths.DOCUMENTS);
}
