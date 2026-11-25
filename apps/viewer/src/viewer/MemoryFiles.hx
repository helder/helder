package viewer;

import haxe.io.Bytes;
import viewer.Files;

// Files in memory, for tests: folders made as files are added, listings
// given at once in batches of `size`, a watch polled by poll(), the
// trash a folder of its own ("/Trash") that records what went in.
class MemoryFiles implements Files {
	public var trash(default, null):Null<String->Null<String>>;
	public var rename(default, null):Null<(from:String, to:String)->Void>;
	public var size = NativeFiles.BATCH;
	// listings held back until release() (a slow disk); what was trashed
	public var hold = false;
	public final trashed:Array<String> = [];

	final items = new Map<String, {entry:Entry, bytes:Bytes}>();
	final held:Array<Void->Void> = [];
	final watches:Array<{dir:String, changed:Array<Entry>->Void}> = [];

	public function new() {
		trash = path -> {
			var e = items.get(path);
			if (e == null) throw "No such file";
			var to = "/Trash/" + e.entry.name;
			move(path, to);
			trashed.push(path);
			return to;
		};
		rename = (from, to) -> move(from, to);
	}

	// a file (its folders made), or a folder when bytes is null and the
	// path ends in "/"
	public function add(path:String, ?bytes:Bytes, modified = 0.0):MemoryFiles {
		var folder = StringTools.endsWith(path, "/");
		if (folder) path = path.substr(0, path.length - 1);
		var name = haxe.io.Path.withoutDirectory(path);
		items.set(path, {
			entry: {name: name, kind: folder ? Folder : File, size: bytes == null ? 0 : bytes.length, modified: modified, created: 0},
			bytes: bytes ?? Bytes.alloc(0)
		});
		var up = parent(path);
		if (up != null && !items.exists(up)) add(up + "/");
		return this;
	}

	public function remove(path:String) {
		for (p in [for (k in items.keys()) k])
			if (p == path || StringTools.startsWith(p, path + "/")) items.remove(p);
	}

	public function release() {
		hold = false;
		for (f in held.splice(0, held.length))
			f();
	}

	// the watches told what changed
	public function poll()
		for (w in watches.copy())
			w.changed(children(w.dir));

	public function list(dir:String, batch:Batch->Void):Void->Void {
		var stopped = false;
		function run() {
			if (stopped) return;
			var d = items.get(dir);
			if (d == null || d.entry.kind != Folder) {
				batch({entries: [], done: true, error: d == null ? "missing" : "notfolder"});
				return;
			}
			var all = children(dir), at = 0;
			while (!stopped) {
				var part = all.slice(at, at + size);
				at += size;
				batch({entries: part, done: at >= all.length});
				if (at >= all.length) break;
			}
		}
		if (hold) held.push(run) else run();
		return () -> stopped = true;
	}

	public function stat(path:String):Null<Entry> {
		var e = items.get(path);
		return e == null ? null : e.entry;
	}

	public function open(path:String):helder.media.ByteSource {
		var e = items.get(path);
		if (e == null) throw "No such file";
		return new helder.media.MemorySource(e.bytes);
	}

	// a file's text, at once (the tests' Explorer.read; null: none)
	public function text(path:String):Null<String> {
		var e = items.get(path);
		return e == null || e.entry.kind == Folder ? null : e.bytes.toString();
	}

	public function localPath(path:String):Null<String>
		return null;

	public function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void {
		var w = {dir: dir, changed: changed};
		watches.push(w);
		return () -> watches.remove(w);
	}

	function children(dir:String):Array<Entry>
		return [for (p => e in items) if (parent(p) == dir) e.entry];

	function move(from:String, to:String) {
		var e = items.get(from);
		if (e == null) throw "No such file";
		items.remove(from);
		add(to, e.bytes, e.entry.modified);
	}

	static function parent(path:String):Null<String> {
		var slash = path.lastIndexOf("/");
		return slash < 0 ? null : slash == 0 ? (path == "/" ? null : "/") : path.substr(0, slash);
	}
}
