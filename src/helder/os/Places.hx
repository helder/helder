package helder.os;

typedef Place = {kind:PlaceKind, name:String, path:String};

enum abstract PlaceKind(String) {
	var Home = "Home";
	var Desktop = "Desktop";
	var Documents = "Documents";
	var Downloads = "Downloads";
	var Pictures = "Pictures";
	var Movies = "Movies";
	var Music = "Music";
}

typedef Volume = {name:String, path:String, total:Float, free:Float, removable:Bool, network:Bool, root:Bool};

// Existing user folders, and mounted volumes a file browser can show.
class Places {
	@:typescript public static function user():Array<Place>
		return #if helder.headless []
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64") helder.os.cocoa.MacPlaces.user()
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64") helder.os.win32.WinPlaces.user()
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64") helder.os.linux.LinuxPlaces.user()
		#else [] #end;

	// The system volume first; capacities in bytes (zero when unknown).
	@:typescript public static function volumes():Array<Volume>
		return #if helder.headless []
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64") helder.os.cocoa.MacPlaces.volumes()
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64") helder.os.win32.WinPlaces.volumes()
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64") helder.os.linux.LinuxPlaces.volumes()
		#else [] #end;

	@:allow(helder.os) static final kinds:Array<PlaceKind> = [Home, Desktop, Documents, Downloads, Pictures, Movies, Music];

	#if sys
	@:allow(helder.os) static function directory(path:String):Bool
		return try sys.FileSystem.isDirectory(path) catch (_:Dynamic) false;
	#end
}
