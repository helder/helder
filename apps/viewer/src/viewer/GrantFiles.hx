package viewer;

import helder.media.ByteSource;
import helder.os.Folders;
import helder.os.Places.Place;
import viewer.Files;

// what GrantFiles reads: helder.os.Folders (Grants.system), or the tests' own
interface Grants {
	function granted():Array<FolderGrant>;
	@:coroutine function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool;
	function open(grant:String, path:String):ByteSource;
	function file(grant:String, path:String):Null<String>;
	function delete(grant:String, path:String):Bool;
}

// The folders the user gave the viewer (helder.os.Folders: a phone's, the
// browser's), each a top of its own by its grant's id: "<id>/Trips/2024".
// An entry is known once its folder is listed; a file's bytes are the
// grant's, its path on disk where it has one (iOS's: decoded and made
// thumbnails of as the desktop's are). Nothing is watched or renamed; no
// trash (a phone's documents have none: delete, for good, is the shell's
// to confirm).
class GrantFiles implements Files {
	public var trash(default, null):Null<String->Null<String>> = null;
	public var rename(default, null):Null<(from:String, to:String)->Void> = null;

	final grants:Grants;
	final entries = new Map<String, Entry>();

	public function new(?grants:Grants) {
		this.grants = grants ?? new SystemGrants();
		for (g in this.grants.granted())
			add(g);
	}

	// a grant's folder known, a top of its own: its path
	public function add(g:FolderGrant):String {
		entries.set(g.id, {name: g.name, kind: Folder, size: 0, modified: 0, created: 0});
		return g.id;
	}

	// the granted folders, the sidebar's places
	public function places():Array<Place>
		return [for (g in grants.granted()) {kind: Pictures, name: g.name, path: g.id}];

	public function list(dir:String, batch:Batch->Void):Void->Void {
		var at = split(dir), stopped = false;
		if (!entries.exists(at.grant)) {
			batch({entries: [], done: true, error: "missing"});
			return () -> {};
		}
		helder.async.Async.launch(_ -> {
			var ok = grants.list(at.grant, at.path, (got, done) -> if (!stopped) batch({entries: [for (f in got) known(dir, f)], done: done}));
			if (!ok && !stopped) batch({entries: [], done: true, error: entries.get(dir)?.kind == File ? "notfolder" : "denied"});
		});
		return () -> stopped = true;
	}

	public function stat(path:String):Null<Entry>
		return entries.get(path);

	public function open(path:String):ByteSource {
		var at = split(path);
		return grants.open(at.grant, at.path);
	}

	public function localPath(path:String):Null<String> {
		var at = split(path);
		return entries.exists(at.grant) ? grants.file(at.grant, at.path) : null;
	}

	public function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void
		return () -> {};

	// the file or folder deleted: whether it went to a trash (Folders.delete); throws when it was not
	public function delete(path:String):Bool {
		var at = split(path);
		if (at.path == "") throw "Not a grant's own folder";
		var trashed = grants.delete(at.grant, at.path);
		for (p in [for (k in entries.keys()) k])
			if (p == path || StringTools.startsWith(p, path + "/")) entries.remove(p);
		return trashed;
	}

	// (a path's grant and its path in it)
	static function split(path:String):{grant:String, path:String} {
		var slash = path.indexOf("/");
		return slash < 0 ? {grant: path, path: ""} : {grant: path.substr(0, slash), path: path.substr(slash + 1)};
	}

	function known(dir:String, f:FolderEntry):Entry {
		var e:Entry = {name: f.name, kind: f.folder ? Folder : File, size: f.size, modified: f.modified, created: 0};
		entries.set(FolderModel.join(dir, f.name), e);
		return e;
	}
}

// (helder.os.Folders')
private class SystemGrants implements Grants {
	public function new() {}

	public function granted():Array<FolderGrant>
		return Folders.granted();

	@:coroutine public function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool
		return Folders.list(grant, path, batch);

	public function open(grant:String, path:String):ByteSource
		return Folders.open(grant, path);

	public function file(grant:String, path:String):Null<String>
		return Folders.file(grant, path);

	public function delete(grant:String, path:String):Bool
		return Folders.delete(grant, path);
}
