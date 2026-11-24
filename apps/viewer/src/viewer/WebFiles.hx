package viewer;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import helder.asset.Asset;
import helder.media.ByteSource;
import viewer.Files;

// The browser's files (the web build's): the sample folder (Samples:
// bundled beside the page, fetched when first read) and the folders the
// user opens or drops (helder.os.Folders, WebFolders: grants), each a top
// of its own (GrantFiles). Read only: nothing is watched, trashed or
// renamed, and no file is on a disk (localPath).
class WebFiles implements Files {
	public var trash(default, null):Null<String->Null<String>> = null;
	public var rename(default, null):Null<(from:String, to:String)->Void> = null;

	// the folders opened and dropped
	public final grants = new GrantFiles();

	// the samples' entries by path, their folders' entries
	final entries = new Map<String, Entry>();
	final samples = new Map<String, Array<Entry>>();

	public function new() {
		folder(Samples.ROOT);
		for (f in Samples.FILES) {
			var e:Entry = {name: Browser.name(f.path), kind: File, size: f.size, modified: Samples.MODIFIED, created: 0};
			entries.set(f.path, e);
			folder(Browser.parent(f.path)).push(e);
		}
	}

	public function list(dir:String, batch:Batch->Void):Void->Void {
		var own = samples.get(dir);
		if (own != null) {
			batch({entries: own.copy(), done: true});
			return () -> {};
		}
		if (entries.exists(dir)) {
			batch({entries: [], done: true, error: "notfolder"});
			return () -> {};
		}
		return grants.list(dir, batch);
	}

	public function stat(path:String):Null<Entry>
		return entries.get(path) ?? grants.stat(path);

	public function open(path:String):ByteSource {
		var sample = Samples.asset(path);
		return sample != null ? new AssetSource(sample) : grants.open(path);
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
