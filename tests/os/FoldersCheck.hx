import haxe.io.Bytes;
import helder.os.Folders;

// helder.os.Folders on a phone, each line printed, the last "folders: ok"
// (or "folders: kept ok" for a grant kept from an earlier launch): a
// folder of "a.txt" ("hello") and "Sub/b.txt" ("bye") granted, listed,
// a file read, one deleted, the grant still there at the next launch,
// then forgotten. iOS (tests/pack/ios.sh): the picker cannot be answered
// unattended, so the folder is made in the app's Documents and kept as
// the picker's would be (a bookmark), resolved again as at a launch.
// Android (tests/os/folders-android.sh): the picker, answered by the
// script (adb), at /sdcard/Download/helder-folders, which it pushed.
// Elsewhere: "folders: unavailable".
class FoldersCheck {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		// (no window, no App.run: the activity's commands answered here while
		// it runs, so that the main thread, which the picker needs, is free)
		var done = false, loop = helder.async.Loop.current();
		helder.async.Async.launch(_ -> {
			check();
			done = true;
		});
		while (!done) {
			loop.turn(0);
			helder.os.android.MainThread.wait(0.02);
		}
		#else
		helder.async.Async.run(_ -> check());
		#end
	}

	@:coroutine static function check() {
		if (!Folders.available()) {
			Sys.println("folders: unavailable");
			return;
		}
		try {
			// (iOS: a run's own grant each time, the kept one a bookmark resolved again)
			#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			for (k in Folders.granted())
				Folders.forget(k.id);
			#end
			var kept = Folders.granted(), g:Null<FolderGrant> = null;
			if (kept.length > 0) {
				g = kept[0];
				Sys.println('folders: kept ${g.name}');
				var names = list(g.id, "");
				// (Android starts main again when the activity is made again, the
				// picker's return among the times: the script's second launch is
				// the one with a "kept" file it put in the folder)
				#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
				if (!names.contains("kept (0)")) {
					Sys.println("folders: kept, the same launch");
					return;
				}
				#end
				Sys.println('folders: listed ${names.join(", ")}');
				if (!names.contains("a.txt (5)")) throw "a.txt not listed";
				Folders.forget(g.id);
				Sys.println('folders: forgotten ${Folders.granted().length}');
				Sys.println("folders: kept ok");
				return;
			}
			g = grant();
			if (g == null) throw "nothing granted";
			Sys.println('folders: granted ${g.name}');
			if (Folders.granted().filter(k -> k.id == g.id).length != 1) throw "not among the granted";
			var names = list(g.id, "");
			Sys.println('folders: listed ${names.join(", ")}');
			if (names.join(",") != "Sub/,a.txt (5)") throw "not its entries";
			Sys.println('folders: listed Sub ${list(g.id, "Sub").join(", ")}');
			var s = Folders.open(g.id, "a.txt"), b = Bytes.alloc(16);
			var n = s.read(0, b, 0, 16);
			s.close();
			Sys.println('folders: read ${b.getString(0, n)}');
			if (b.getString(0, n) != "hello") throw "not its bytes";
			Sys.println('folders: deleted to a trash ${Folders.delete(g.id, "Sub/b.txt")}');
			Sys.println('folders: listed Sub ${list(g.id, "Sub").join(", ")}');
			Sys.println("folders: ok");
		} catch (e:Dynamic) Sys.println('folders: failed $e');
	}

	// (the entries' names, sorted: a folder's with "/", a file's with its size)
	@:coroutine static function list(grant:String, path:String):Array<String> {
		var all = [];
		var ok = Folders.list(grant, path, (entries, _) -> for (e in entries) all.push(e.folder ? e.name + "/" : '${e.name} (${e.size})'));
		if (!ok) throw 'not listed: "$path"';
		all.sort(Reflect.compare);
		return all;
	}

	@:coroutine static function grant():Null<FolderGrant> {
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		var dir = helder.os.Paths.documents() + "/FoldersCheck";
		sys.FileSystem.createDirectory(dir + "/Sub");
		sys.io.File.saveContent(dir + "/a.txt", "hello");
		sys.io.File.saveContent(dir + "/Sub/b.txt", "bye");
		var g = helder.os.FoldersApple.grant(dir);
		// (as at the next launch: the bookmark resolved again)
		@:privateAccess helder.os.FoldersApple.resolved.clear();
		return g;
		#else
		Sys.println("folders: picking");
		return Folders.pick();
		#end
	}
}
