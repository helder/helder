import haxe.io.Path;
import helder.os.Paths;
import helder.os.Places;
import helder.os.Trash;
import sys.FileSystem;
import sys.io.File;

using StringTools;

class PlacesTrashTest {
	static function main() {
		#if (helder.headless || hxmc.target == "wasm32-wasi")
		check(Places.user().length == 0 && Places.volumes().length == 0 && !Trash.available(), "desktop APIs unavailable");
		var threw = false;
		try Trash.move("file") catch (_:Dynamic) threw = true;
		check(threw, "move unavailable");
		#else
		var places = Places.user();
		check(places.length > 0 && places[0].kind == Home, "Home first");
		for (place in places)
			check(place.name != "" && FileSystem.isDirectory(place.path), place.path);
		var volumes = Places.volumes();
		check(volumes.length > 0 && volumes[0].root, "root volume first");
		check(volumes[0].total > 0 && volumes[0].free <= volumes[0].total, "root volume capacity");
		check(Trash.available(), "trash available");
		var dir = Path.join([FileSystem.fullPath(Paths.temp()), 'helder-trash-${Std.int(Sys.time())}-${Std.random(0x3FFFFFFF)}']);
		FileSystem.createDirectory(dir);
		var moved:Array<String> = [];
		var linux = Sys.systemName() == "Linux", data = Sys.getEnv("XDG_DATA_HOME");
		if (linux) Sys.putEnv("XDG_DATA_HOME", dir + "/data");
		try {
			var name = "space é.txt", file = dir + "/" + name, folder = dir + "/folder";
			File.saveContent(file, "one");
			move(file, moved);
			FileSystem.createDirectory(folder);
			File.saveContent(folder + "/child", "inside");
			move(folder, moved);
			if (linux) {
				File.saveContent(file, "two");
				move(file, moved);
				check(Path.withoutDirectory(moved[2]) == name + " 2", "numbered trash name");
				check(File.getContent(moved[0]) == "one" && File.getContent(moved[2]) == "two", "both files kept");
				var encoded = dir.urlEncode().replace("%2F", "/") + "/";
				for (suffix in ["", " 2"]) {
					var lines = File.getContent(dir + "/data/Trash/info/" + name + suffix + ".trashinfo").split("\n");
					check(lines[0] == "[Trash Info]" && lines[1] == "Path=" + encoded + "space%20%C3%A9.txt", "trashinfo path");
					check(~/^DeletionDate=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$/.match(lines[2]), "trashinfo date");
				}
				// (on a filesystem with 255-byte names, the source fits but its info name needs shortening)
				var longName = [for (_ in 0...125) "é"].join(""), longPath = dir + "/" + longName;
				File.saveContent(longPath, "long name");
				move(longPath, moved);
				var longInfo = File.getContent(dir + "/data/Trash/info/" + Path.withoutDirectory(moved[3]) + ".trashinfo");
				check(longInfo.contains("Path=" + encoded + longName.urlEncode() + "\n"), "full original name in trashinfo");
			}
		} catch (e:Dynamic) {
			clean(dir, moved);
			if (linux) Sys.putEnv("XDG_DATA_HOME", data);
			throw e;
		}
		clean(dir, moved);
		if (linux) Sys.putEnv("XDG_DATA_HOME", data);
		#end
		Sys.println("Places and Trash: passed");
	}

	static function move(path:String, moved:Array<String>) {
		var result = Trash.move(path);
		if (result != null) moved.push(result);
		check(!FileSystem.exists(path), "item moved: " + path);
		if (Sys.systemName() == "Windows") check(result == null, "Windows returns no path");
		else check(result != null && FileSystem.exists(result), "item in trash: " + path);
	}

	static function clean(dir:String, moved:Array<String>) {
		for (path in moved) remove(path);
		remove(dir);
	}

	static function remove(path:String) {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (child in FileSystem.readDirectory(path)) remove(path + "/" + child);
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}

	static function check(ok:Bool, what:String) {
		if (!ok) throw what;
	}
}
