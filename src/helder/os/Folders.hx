package helder.os;

// a folder the user gave the app: its id (kept across launches; the web:
// the page's while it is open) and its name
typedef FolderGrant = {id:String, name:String};

// a folder's entry: its size in bytes, modified in seconds since the epoch (0: not known)
typedef FolderEntry = {name:String, folder:Bool, size:Float, modified:Float};

// Folders the user gives the app in the system's folder picker, where an
// app has no paths of its own to browse: iOS's (UIDocumentPickerViewController
// of folders: On My iPhone, iCloud Drive, an external drive, a server, any
// Files provider; a security-scoped bookmark kept), Android's (the Storage
// Access Framework's document tree, its permission kept; never all of the
// storage), the web's (the File System Access API's showDirectoryPicker:
// helder.os.web.WebFolders, read only, kept while the page is). The grants
// picked stay until forgotten (iOS and Android: the store
// "helder-folders"); inside one a path is relative, "" the folder itself,
// "Trips/2024" a folder inside it. Desktops have none: their programs
// read paths (Places, FileDialog), and a sandboxed Mac app's bookmarks
// are not here yet.
class Folders {
	@:typescript public static function available():Bool
		return #if helder.headless false
		#elseif (hxmc.target == "wasm32-wasi") helder.os.web.WebFolders.available()
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") true
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64") true
		#else false #end;

	// the system's folder picker: the folder picked, kept; null when cancelled
	@:typescript @:coroutine public static function pick():Null<FolderGrant> {
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return null;
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebFolders.pick();
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return FoldersApple.pick();
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidFolders.pick();
		#else
		return null;
		#end
	}

	// the folders kept, in the order picked
	@:typescript public static function granted():Array<FolderGrant>
		return #if helder.headless []
		#elseif (hxmc.target == "wasm32-wasi") helder.os.web.WebFolders.granted()
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") FoldersApple.granted()
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64") helder.os.android.AndroidFolders.granted()
		#else [] #end;

	// the folder no longer kept (Android: its permission given back)
	@:typescript public static function forget(id:String):Void {
		#if helder.headless
		#elseif (hxmc.target == "wasm32-wasi")
		helder.os.web.WebFolders.forget(id);
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		FoldersApple.forget(id);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.AndroidFolders.forget(id);
		#end
	}

	// a folder's entries in batches as they are read (batch on the caller's
	// loop, the last done): whether it was read (false: no such folder, no
	// access, the grant forgotten)
	@:coroutine public static function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool {
		#if helder.headless
		return false;
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebFolders.list(grant, path, batch);
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return FoldersApple.list(grant, path, batch);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidFolders.list(grant, path, batch);
		#else
		return false;
		#end
	}

	// a file's bytes; throws when it cannot be opened
	public static function open(grant:String, path:String):helder.media.ByteSource
		return #if helder.headless throw "Folders: unavailable"
		#elseif (hxmc.target == "wasm32-wasi") helder.os.web.WebFolders.open(grant, path)
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") FoldersApple.open(grant, path)
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64") helder.os.android.AndroidFolders.open(grant, path)
		#else throw "Folders: unavailable" #end;

	// the item on disk, where it is one (iOS's, readable while the app runs);
	// null elsewhere (Android's documents, the web's)
	@:typescript public static function file(grant:String, path:String):Null<String>
		return #if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") #if helder.headless null #else FoldersApple.file(grant, path) #end
		#else null #end;

	// the file or folder deleted: true when it went to a trash it can be put
	// back from (iOS: FileManager's trashItem, where the provider has one),
	// false when it is gone (Android's documents have no trash); throws when
	// it was not deleted (the web: read only)
	@:typescript public static function delete(grant:String, path:String):Bool {
		if (path == "") throw "Folders: not the folder itself";
		return #if helder.headless throw "Folders: unavailable"
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") FoldersApple.delete(grant, path)
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64") helder.os.android.AndroidFolders.delete(grant, path)
		#else throw "Folders: read only" #end;
	}
}
