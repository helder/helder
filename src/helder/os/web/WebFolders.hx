package helder.os.web;

import haxe.io.Bytes;
import helder.media.ByteSource;
import helder.os.Folders;
import hxmc.unsafe.*;

// helder.os.Folders in a browser (src/helder/os/imports.mjs), read only:
// a folder the user picks (the File System Access API's
// showDirectoryPicker, where the browser has it: Chromium's), and, its own
// extra, what is dropped on the page (a folder's handle, or its entry
// where there are none; files, a folder of their own), each a grant of the
// page's while it is open. A folder is a handle, listed in batches as it is
// read, its subfolders' handles and its files' Files kept by their paths
// (a path not listed yet: its folders listed down to it); a file's bytes
// are helder.media's (WebSource.ofBlob of the File kept).
@:hxmc.unsafe(gc)
class WebFolders {
	#if (hxmc.target == "wasm32-wasi")
	static final picks = new Map<Int, Int->Void>();
	static final lists = new Map<Int, {loop:helder.async.Loop, f:(lines:String, state:Int) -> Void}>();
	static var next = 1;
	static var dropped:Null<{loop:helder.async.Loop, f:FolderGrant->Void}> = null;
	static final grants:Array<Grant> = [];

	public static function available():Bool
		return FolderImports.folders_available() == 1;

	@:coroutine public static function pick():Null<FolderGrant> {
		var folder:Int = helder.os.Await.answer(done -> {
			var id = next++;
			picks.set(id, done);
			FolderImports.folders_pick(Callback.addr(picked), id);
		});
		return folder == 0 ? null : grant(folder);
	}

	public static function granted():Array<FolderGrant>
		return [for (g in grants) g.grant];

	public static function forget(id:String)
		grants.remove(find(id));

	@:coroutine public static function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool {
		var g = find(grant);
		if (g == null) return false;
		var h = folder(g, path);
		return h != 0 && read(g, path, h, batch);
	}

	// (opened when first read: a file of a folder not listed yet found first)
	public static function open(grant:String, path:String):ByteSource {
		var g = find(grant);
		if (g == null) throw "Folders: no such grant";
		return new Later(g, path);
	}

	// what is dropped on the page from now on: a grant of it
	public static function onDrop(f:FolderGrant->Void) {
		if (dropped == null) FolderImports.folders_drop(Callback.addr(drop));
		dropped = {loop: helder.async.Loop.current(), f: f};
	}

	static function grant(folder:Int):FolderGrant {
		var name = text(FolderImports.folders_name(folder));
		var g:Grant = {grant: {id: "web-" + folder, name: name == "" ? "Folder" : name}, folders: ["" => folder], files: new Map()};
		grants.push(g);
		return g.grant;
	}

	static function find(id:String):Null<Grant> {
		for (g in grants)
			if (g.grant.id == id) return g;
		return null;
	}

	// (a folder's handle, its parents listed down to it where they were not; 0: none)
	@:coroutine static function folder(g:Grant, path:String):Int {
		var at = "", h = g.folders.get("") ?? 0;
		for (part in path.split("/"))
			if (part != "") {
				var p = at == "" ? part : at + "/" + part;
				if (!g.folders.exists(p)) read(g, at, h, (_, _) -> {});
				h = g.folders.get(p) ?? 0;
				if (h == 0) return 0;
				at = p;
			}
		return h;
	}

	@:coroutine static function read(g:Grant, dir:String, h:Int, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool
		return helder.os.Await.answer(done -> {
			var id = next++;
			lists.set(id, {loop: helder.async.Loop.current(), f: (lines, state) -> {
				if (state < 0) return done(false);
				batch([for (l in lines.split("\n")) if (l != "") known(g, dir, l.split("\t"))], state != 0);
				if (state != 0) done(true);
			}});
			FolderImports.folders_list(h, Callback.addr(listed), id);
		});

	// (an entry's line kept: a folder's handle, a file's File and size, by its path)
	static function known(g:Grant, dir:String, c:Array<String>):FolderEntry {
		var p = dir == "" ? c[1] : dir + "/" + c[1], folder = c[0] == "folder";
		if (folder) g.folders.set(p, Std.parseInt(c[4])) else g.files.set(p, {blob: c[4], size: Std.parseFloat(c[2])});
		return {name: c[1], folder: folder, size: Std.parseFloat(c[2]), modified: Std.parseFloat(c[3]) / 1000};
	}

	// (a file's File, its folder listed first where it was not)
	@:coroutine static function blob(g:Grant, path:String):Null<{blob:String, size:Float}> {
		var f = g.files.get(path);
		if (f != null) return f;
		var slash = path.lastIndexOf("/"), dir = slash < 0 ? "" : path.substr(0, slash), h = folder(g, dir);
		if (h != 0) read(g, dir, h, (_, _) -> {});
		return g.files.get(path);
	}

	@:hxmc.callback static function picked(id:Int, folder:Int):Int {
		var f = picks.get(id);
		picks.remove(id);
		if (f != null) f(folder);
		return 0;
	}

	@:hxmc.callback static function listed(id:Int, lines:Int, state:Int):Int {
		var l = lists.get(id);
		if (state != 0) lists.remove(id);
		if (l == null) return 0;
		var s = state < 0 ? "" : text(lines);
		l.loop.post(() -> l.f(s, state));
		return 0;
	}

	@:hxmc.callback static function drop(folder:Int):Int {
		var d = dropped;
		if (d != null) d.loop.post(() -> d.f(grant(folder)));
		return 0;
	}

	static inline function text(h:Int):String
		return CanvasWindow.take(h);
	#end
}

#if (hxmc.target == "wasm32-wasi")
// (a grant: its folders' handles and its files' Files by path, "" the folder itself)
private typedef Grant = {grant:FolderGrant, folders:Map<String, Int>, files:Map<String, {blob:String, size:Float}>};

// (a file's bytes, its File found at the first read)
private class Later implements ByteSource {
	public var size(get, never):Float;

	final g:Grant;
	final path:String;
	var source:Null<ByteSource> = null;

	public function new(g:Grant, path:String) {
		this.g = g;
		this.path = path;
	}

	function get_size():Float
		return source == null ? g.files.get(path)?.size ?? -1 : source.size;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (source == null) {
			var f = @:privateAccess WebFolders.blob(g, path);
			if (f == null) throw "Folders: no such file";
			source = helder.media.WebSource.ofBlob(f.blob);
		}
		return source.read(offset, b, pos, len);
	}

	public function close()
		if (source != null) source.close();
}

@:hxmc.c @:hxmc.lib("hxmc_os") private extern class FolderImports {
	static function folders_available():Int;
	// done(id, the folder's handle; 0: cancelled, none)
	static function folders_pick(done:Ptr, id:Int):Void;
	static function folders_name(folder:Int):Int;
	// done(id, a string handle of the batch's lines, 1 last, 0 more, -1 failed)
	static function folders_list(folder:Int, done:Ptr, id:Int):Void;
	// dropped(a folder's handle) for each drop from now on
	static function folders_drop(dropped:Ptr):Void;
}
#end
