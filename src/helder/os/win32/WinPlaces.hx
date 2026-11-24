package helder.os.win32;

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
import helder.os.PathsDesktop;
import helder.os.Places;
import helder.os.Places.Place;
import helder.os.Places.Volume;
import helder.os.win32.FileOpenDialog.Shell32Com;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class WinPlaces {
	public static function user():Array<Place>
		return withShell(userFolders);

	static function userFolders():Array<Place> {
		// (FOLDERID_Profile, Desktop, Documents, Downloads, Pictures, Videos, Music)
		var ids = ["5E6C858F-0E22-4760-9AFE-EA3317B67173", "B4BFCC3A-DB2C-424C-B029-7FE99A87C641", "FDD39AD0-238F-46AF-ADB4-6C85480369C7",
			"374DE290-123F-4565-9164-39C4925E467B", "33E28130-4E1E-4676-835A-98395C3BC3BB", "18989B1D-99B5-455B-841C-AB7C74E4DDFC", "4BD8D571-6D19-48D3-BE97-422220080E43"];
		var result:Array<Place> = [];
		for (i in 0...ids.length) {
			var path = PathsDesktop.known(ids[i], 0);
			if (path == null || !Places.directory(path)) continue;
			var name = Arena.scopedValue(a -> displayName(a, a.wstring(path)));
			result.push({kind: Places.kinds[i], name: name ?? haxe.io.Path.withoutDirectory(path), path: path});
		}
		return result;
	}

	public static function volumes():Array<Volume>
		return withShell(drives);

	static function drives():Array<Volume>
		return Arena.scopedValue(a -> {
			var result:Array<Volume> = [], drives = Kernel.GetLogicalDrives();
			var windows = a.alloc(2 * 260, 2);
			var n = Kernel.GetSystemWindowsDirectoryW(windows, 260);
			var system = n > 0 && n < 260 ? PathsDesktop.wide(windows).substr(0, 2).toUpperCase() : Sys.getEnv("SystemDrive")?.toUpperCase();
			var label = a.alloc(2 * 261, 2);
			var total:Ptr<Int64> = a.alloc(8), free:Ptr<Int64> = a.alloc(8);
			var mode:Ptr<Int32> = a.alloc(4, 4);
			// (SEM_FAILCRITICALERRORS: an empty drive must not show a dialog)
			var changed = Kernel.SetThreadErrorMode(1, mode) != 0;
			for (i in 0...26) {
				if ((drives & (1 << i)) == 0) continue;
				var letter = String.fromCharCode(65 + i) + ":", path = letter + "\\", p = a.wstring(path);
				var type = Kernel.GetDriveTypeW(p);
				if (type <= 1) continue; // (DRIVE_UNKNOWN, DRIVE_NO_ROOT_DIR)
				var hasLabel = Kernel.GetVolumeInformationW(p, label, 261, Ptr.nil(), Ptr.nil(), Ptr.nil(), Ptr.nil(), 0) != 0;
				if (type == 5 && !hasLabel) continue; // (DRIVE_CDROM, no media)
				var name = displayName(a, p);
				if (name == null) {
					var fallback = hasLabel ? PathsDesktop.wide(label) : "";
					name = fallback != "" ? '$fallback ($letter)' : type == 3 ? 'Local Disk ($letter)' : letter;
				}
				total.value = 0;
				free.value = 0;
				Kernel.GetDiskFreeSpaceExW(p, free, total, Ptr.nil());
				var v:Volume = {name: name, path: path, total: (total.value : haxe.Int64).toFloat(), free: (free.value : haxe.Int64).toFloat(), removable: type == 2,
					network: type == 4, root: letter == system};
				if (v.root) result.unshift(v) else result.push(v);
			}
			if (changed) Kernel.SetThreadErrorMode(mode.value, Ptr.nil());
			return result;
		});

	// (SHGetFileInfoW uses COM on the calling thread)
	static function withShell<T>(read:Void->T):T {
		var apartment = Shell32Com.CoInitializeEx(Ptr.nil(), 2);
		try {
			var result = read();
			if (apartment >= 0) Shell32Com.CoUninitialize();
			return result;
		} catch (e:Dynamic) {
			if (apartment >= 0) Shell32Com.CoUninitialize();
			throw e;
		}
	}

	static function displayName(a:Arena, path:Ptr):Null<String> {
		// (SHFILEINFOW: hIcon, iIcon, dwAttributes, szDisplayName, szTypeName)
		var info = a.alloc(696);
		if (Shell.SHGetFileInfoW(path, 0, info, 696, 0x200).isNull()) return null;
		var name = PathsDesktop.wide(info.add(16));
		return name == "" ? null : name;
	}
}

@:hxmc.c @:hxmc.lib("shell32") private extern class Shell {
	static function SHGetFileInfoW(path:Ptr, attributes:Int, info:Ptr, size:Int, flags:Int):Ptr;
}

@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel {
	static function GetLogicalDrives():Int;
	static function GetDriveTypeW(root:Ptr):Int;
	static function GetSystemWindowsDirectoryW(out:Ptr, size:Int):Int;
	static function SetThreadErrorMode(mode:Int, old:Ptr<Int32>):Int;
	static function GetVolumeInformationW(root:Ptr, label:Ptr, labelSize:Int, serial:Ptr, maxComponent:Ptr, flags:Ptr, fs:Ptr, fsSize:Int):Int;
	static function GetDiskFreeSpaceExW(root:Ptr, available:Ptr<Int64>, total:Ptr<Int64>, free:Ptr):Int;
}
#end
