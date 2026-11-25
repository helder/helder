package helder.os.linux;

// Paths on Linux: the XDG base directories and user-dirs.dirs, with the
// specifications' defaults.
class Paths {
	public static function path(which:Int, env:String->Null<String>, userDirs:Null<String>, name:String):String {
		var home = env("HOME") ?? "";
		// (a relative one is invalid: the default then)
		function base(key:String, fallback:String):String {
			var v = env(key);
			return v != null && StringTools.startsWith(v, "/") ? v : home + fallback;
		}
		return switch which {
			case 0:
				var t = env("TMPDIR");
				t != null && StringTools.startsWith(t, "/") ? t : "/tmp";
			case 9: userDir(userDirs, "XDG_DOCUMENTS_DIR", home) ?? home + "/Documents";
			case 13: base("XDG_CACHE_HOME", "/.cache") + "/" + name;
			case _: base("XDG_DATA_HOME", "/.local/share") + "/" + name;
		}
	}

	// user-dirs.dirs' KEY="$HOME/Documents" (absolute, or $HOME's)
	public static function userDir(text:Null<String>, key:String, home:String):Null<String> {
		if (text == null) return null;
		for (line in text.split("\n")) {
			var l = StringTools.trim(line);
			if (!StringTools.startsWith(l, key + "=")) continue;
			var v = l.substr(key.length + 1);
			if (v.length >= 2 && v.charAt(0) == '"' && v.charAt(v.length - 1) == '"') v = v.substr(1, v.length - 2);
			if (v == "$HOME" || StringTools.startsWith(v, "$HOME/")) v = home + v.substr(5);
			return StringTools.startsWith(v, "/") ? v : null;
		}
		return null;
	}
}
