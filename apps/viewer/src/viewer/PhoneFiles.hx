package viewer;

import helder.media.ByteSource;
import viewer.Files;

// A phone's files: the app's own folders on disk (its Documents, which the
// system's Files app shows as the app's) by their absolute paths, and the
// folders the user gave it (GrantFiles) by their grants' ids.
class PhoneFiles implements Files {
	public var trash(default, null):Null<String->Null<String>>;
	public var rename(default, null):Null<(from:String, to:String)->Void>;

	final disk:Files;
	final grants:GrantFiles;

	public function new(disk:Files, grants:GrantFiles) {
		this.disk = disk;
		this.grants = grants;
		// (a granted folder has no trash: a move there fails, and the browser
		// keeps the item)
		trash = path -> {
			var t = of(path).trash;
			if (t == null) throw "no trash here";
			return t(path);
		};
		rename = (from, to) -> {
			var r = of(from).rename;
			if (r != null) r(from, to);
		};
	}

	// (a grant's id is never an absolute path)
	function of(path:String):Files
		return StringTools.startsWith(path, "/") ? disk : grants;

	public function list(dir:String, batch:Batch->Void):Void->Void
		return of(dir).list(dir, batch);

	public function stat(path:String):Null<Entry>
		return of(path).stat(path);

	public function open(path:String):ByteSource
		return of(path).open(path);

	public function localPath(path:String):Null<String>
		return of(path).localPath(path);

	public function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void
		return of(dir).watch(dir, every, changed);
}
