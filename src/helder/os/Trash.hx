package helder.os;

// The system's trash (desktop only).
class Trash {
	@:typescript public static function available():Bool
		return #if (helder.headless) false
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"
			|| hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64") true
		#else false #end;

	// Answers the item's new path where the system gives it. Throws on failure.
	@:typescript public static function move(path:String):Null<String> {
		if (path == "" || path.indexOf("\x00") >= 0) throw "Trash: invalid path";
		return #if helder.headless throw "Trash: unavailable"
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64") helder.os.apple.MacTrash.move(path)
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64") helder.os.windows.WinTrash.move(path)
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64") helder.os.linux.LinuxTrash.move(path)
		#else throw "Trash: unavailable" #end;
	}
}
