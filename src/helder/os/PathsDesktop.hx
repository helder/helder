package helder.os;

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
import hxmc.unsafe.*;
#end

// Paths on Windows (SHGetKnownFolderPath's RoamingAppData, LocalAppData
// and Documents; GetTempPathW) and Linux (the XDG base directories and
// user-dirs.dirs, with the specifications' defaults).
@:hxmc.unsafe(gc)
class PathsDesktop {
	// which: Paths' (0 temp, 9 documents, 13 cache, 14 data); name: the app's
	public static function windows(which:Int, name:String):Null<String> {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (which == 0)
			return Arena.scopedValue(a -> {
				var buf = a.alloc(2 * 262 + 2, 2);
				// (its trailing backslash taken off)
				Kernel.GetTempPathW(262, buf) == 0 ? null : ~/\\$/.replace(wide(buf), "");
			});
		var folder = switch which {
			case 9: "FDD39AD0-238F-46AF-ADB4-6C85480369C7";
			case 13: "F1B32785-6FBA-4FCF-9D55-7B8E7F157091";
			case _: "3EB685DB-65F9-4CF6-A03A-E3EF65729F3D";
		}
		var d = known(folder);
		return d == null || which == 9 ? d : d + "\\" + name;
		#else
		return null;
		#end
	}

	public static function linux(which:Int, env:String->Null<String>, userDirs:Null<String>, name:String):String {
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

	#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
	// (KF_FLAG_CREATE by default; the path CoTaskMemFree's)
	@:allow(helder.os.win32.WinPlaces) static function known(guid:String, flags = 0x8000):Null<String>
		return Arena.scopedValue(a -> {
			var id = a.alloc(16, 4), hex = StringTools.replace(guid, "-", "");
			inline function byte(k:Int):Int
				return Std.parseInt("0x" + hex.substr(2 * k, 2));
			// (Data1, Data2 and Data3 little-endian, Data4 as written)
			for (k in 0...16)
				Mem.setI8(id, k, byte(k < 4 ? 3 - k : k < 6 ? 9 - k : k < 8 ? 13 - k : k));
			var out:Ptr<Ptr> = a.alloc(8);
			out.value = Ptr.nil();
			if (Shell.SHGetKnownFolderPath(id, flags, Ptr.nil(), out) != 0 || out.value.isNull()) null else {
				var s = wide(out.value);
				Ole.CoTaskMemFree(out.value);
				s;
			}
		});

	@:allow(helder.os.win32.WinPlaces) static function wide(p:Ptr):String {
		var w:Ptr<UInt16> = cast p, b = new StringBuf(), k = 0;
		while (w[k] != 0) {
			var c:Int = w[k++];
			if (c >= 0xD800 && c < 0xDC00) c = 0x10000 + ((c - 0xD800) << 10) + ((w[k++] : Int) - 0xDC00);
			b.addChar(c);
		}
		return b.toString();
	}
	#end
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("shell32") private extern class Shell {
	static function SHGetKnownFolderPath(id:Ptr, flags:Int, token:Ptr, path:Ptr<Ptr>):Int;
}

@:hxmc.c @:hxmc.lib("ole32") private extern class Ole {
	static function CoTaskMemFree(p:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel {
	static function GetTempPathW(size:Int, buf:Ptr):Int;
}
#end
