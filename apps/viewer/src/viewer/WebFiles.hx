package viewer;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import helder.asset.Asset;
import helder.media.ByteSource;
import helder.os.web.WebFolders;
import viewer.Files;

// The browser's files (the web build's): the sample folder (Samples:
// bundled beside the page, fetched when first read) and the folders the
// user opens or drops (helder.os.web.WebFolders), each a top of its own
// by its name ("Holiday", "Holiday 2" for a second). A folder's entries are
// known once it is listed; a file's bytes are read through helder.media's
// WebSource (the Blob of a file picked or dropped). Read only: nothing
// is watched, trashed or renamed, and no file is on a disk (localPath).
class WebFiles implements Files {
	public var trash(default, null):Null<String->Null<String>> = null;
	public var rename(default, null):Null<(from:String, to:String)->Void> = null;

	// what is known: the entries by path, the samples' folders' entries, the
	// opened folders' handles, their files' Blobs' names
	final entries = new Map<String, Entry>();
	final samples = new Map<String, Array<Entry>>();
	final folders = new Map<String, Int>();
	final blobs = new Map<String, String>();

	public function new() {
		folder(Samples.ROOT);
		for (f in Samples.FILES) {
			var e:Entry = {name: Browser.name(f.path), kind: File, size: f.size, modified: Samples.MODIFIED, created: 0};
			entries.set(f.path, e);
			folder(Browser.parent(f.path)).push(e);
		}
	}

	// a folder picked or dropped (WebFolders' handle) as a top of its own: its path
	public function mount(handle:Int):String {
		var name = WebFolders.name(handle), path = name == "" ? "Folder" : name, n = 2;
		while (entries.exists(path))
			path = (name == "" ? "Folder" : name) + " " + n++;
		folders.set(path, handle);
		entries.set(path, {name: path, kind: Folder, size: 0, modified: 0, created: 0});
		return path;
	}

	public function list(dir:String, batch:Batch->Void):Void->Void {
		var own = samples.get(dir);
		if (own != null) {
			batch({entries: own.copy(), done: true});
			return () -> {};
		}
		var h = folders.get(dir);
		if (h == null) {
			batch({entries: [], done: true, error: entries.exists(dir) ? "notfolder" : "missing"});
			return () -> {};
		}
		var stopped = false;
		WebFolders.list(h, (got, done, failed) -> {
			if (stopped) return;
			if (failed) {
				batch({entries: [], done: true, error: "denied"});
				return;
			}
			batch({entries: [for (w in got) known(dir, w)], done: done});
		});
		return () -> stopped = true;
	}

	public function stat(path:String):Null<Entry>
		return entries.get(path);

	public function open(path:String):ByteSource {
		var sample = Samples.asset(path);
		if (sample != null) return new AssetSource(sample);
		var blob = blobs.get(path);
		if (blob == null) throw "No such file";
		return helder.media.WebSource.ofBlob(blob);
	}

	// the file's bytes, all of them
	@:coroutine public function bytes(path:String):Bytes {
		var sample = Samples.asset(path);
		if (sample != null) return sample.load();
		var e = entries.get(path);
		if (e == null || e.kind == Folder) throw "No such file";
		var s = open(path), b = Bytes.alloc(Std.int(e.size)), at = 0;
		try {
			var n = 0;
			while (at < b.length && (n = s.read(at, b, at, b.length - at)) > 0)
				at += n;
		} catch (err:Dynamic) {
			s.close();
			throw err;
		}
		s.close();
		return at < b.length ? b.sub(0, at) : b;
	}

	public function localPath(path:String):Null<String>
		return null;

	public function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void
		return () -> {};

	// (a sample folder's entries, the folder made first, in its own)
	function folder(path:String):Array<Entry> {
		var own = samples.get(path);
		if (own != null) return own;
		own = [];
		samples.set(path, own);
		var e:Entry = {name: Browser.name(path), kind: Folder, size: 0, modified: Samples.MODIFIED, created: 0};
		entries.set(path, e);
		var up = Browser.parent(path);
		if (up != null) folder(up).push(e);
		return own;
	}

	// (a listed entry kept: its path's entry, a folder's handle, a file's Blob)
	function known(dir:String, w:WebEntry):Entry {
		var p = FolderModel.join(dir, w.name);
		var e:Entry = {name: w.name, kind: w.folder ? Folder : File, size: w.size, modified: w.modified, created: 0};
		entries.set(p, e);
		if (w.folder) folders.set(p, w.handle) else blobs.set(p, w.blob);
		return e;
	}
}

// (a sample's bytes, fetched by its first read)
private class AssetSource implements ByteSource {
	public var size(get, never):Float;

	final asset:Asset<Bytes>;

	public function new(asset:Asset<Bytes>)
		this.asset = asset;

	function get_size():Float
		return asset.ready ? asset.peek().length : -1;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		var all = asset.load(), n = Std.int(Math.max(0, Math.min(len, all.length - offset)));
		if (n > 0) b.blit(pos, all, Std.int(offset), n);
		return n;
	}

	public function close() {}
}
#end
