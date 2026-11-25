package helder.os.web;

import hxmc.unsafe.*;

// a folder's entry: a folder's own handle (0 for a file), a file's name
// for helder.media (WebSource.blob: the page keeps its File by it)
typedef WebEntry = {name:String, folder:Bool, size:Float, modified:Float, handle:Int, blob:String};

// The browser's folders, read only (src/helder/os/imports.mjs): one the
// user picks (the File System Access API's showDirectoryPicker, where the
// browser has it: Chromium's), or what is dropped on the page (a folder's
// handle, or its entry where there are none; files, a folder of their
// own). A folder is a handle, listed in batches as it is read; a file's
// bytes are helder.media's (WebSource.blob of its entry's blob).
@:hxmc.unsafe(gc)
class WebFolders {
	#if (hxmc.target == "wasm32-wasi")
	static final picks = new Map<Int, Int->Void>();
	static final lists = new Map<Int, {loop:helder.async.Loop, batch:(entries:Array<WebEntry>, done:Bool, failed:Bool) -> Void}>();
	static var next = 1;
	static var dropped:Null<{loop:helder.async.Loop, f:Int->Void}> = null;

	public static function available():Bool
		return Folders.folders_available() == 1;

	// the folder picked (its handle; 0 when cancelled)
	@:coroutine public static function pick():Int
		return helder.os.Await.answer(done -> {
			var id = next++;
			picks.set(id, done);
			Folders.folders_pick(Callback.addr(picked), id);
		});

	public static function name(folder:Int):String
		return text(Folders.folders_name(folder));

	// the folder's entries in batches, on the loop
	public static function list(folder:Int, batch:(entries:Array<WebEntry>, done:Bool, failed:Bool) -> Void) {
		var id = next++;
		lists.set(id, {loop: helder.async.Loop.current(), batch: batch});
		Folders.folders_list(folder, Callback.addr(listed), id);
	}

	// what is dropped on the page from now on: the folder of it
	public static function onDrop(f:Int->Void) {
		if (dropped == null) Folders.folders_drop(Callback.addr(drop));
		dropped = {loop: helder.async.Loop.current(), f: f};
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
		var entries = state < 0 ? [] : [
			for (l in text(lines).split("\n")) if (l != "") {
				var c = l.split("\t");
				{name: c[1], folder: c[0] == "folder", size: Std.parseFloat(c[2]), modified: Std.parseFloat(c[3]) / 1000,
					handle: c[0] == "folder" ? Std.parseInt(c[4]) : 0, blob: c[0] == "folder" ? "" : c[4]};
			}
		];
		l.loop.post(() -> l.batch(entries, state != 0, state < 0));
		return 0;
	}

	@:hxmc.callback static function drop(folder:Int):Int {
		var d = dropped;
		if (d != null) d.loop.post(() -> d.f(folder));
		return 0;
	}

	static inline function text(h:Int):String
		return CanvasWindow.take(h);
	#end
}

#if (hxmc.target == "wasm32-wasi")
@:hxmc.c @:hxmc.lib("hxmc_os") private extern class Folders {
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
