package viewer;

import helder.media.ByteSource;

enum abstract EntryKind(String) to String {
	var File = "file";
	var Folder = "folder";
	var Link = "link";
}

// a folder's entry: its name, kind, size in bytes, times in seconds since
// the epoch (0: not known)
typedef Entry = {name:String, kind:EntryKind, size:Float, modified:Float, created:Float};

// a batch of a listing: its entries, whether it is the last, why it failed
typedef Batch = {entries:Array<Entry>, done:Bool, ?error:String};

// The browser's file access: everything it reads or changes goes through
// one (NativeFiles, the disk's; MemoryFiles, the tests'). A viewer-local
// stand-in for hxmc's asynchronous file system to come (benmerckx/hxmc#171).
interface Files {
	// the folder's entries in batches (of 2,000), as they are read; stop()
	// ends a listing early
	function list(dir:String, batch:Batch->Void):Void->Void;
	function stat(path:String):Null<Entry>;
	function open(path:String):ByteSource;
	// the file on disk (what decodes and the system's apps take), null when none
	function localPath(path:String):Null<String>;
	// changed(entries) when the folder's listing differs from the last,
	// looked at every few seconds; stop() ends it
	function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void;
	// to the system's trash: the item's new path where it is known (null
	// when there is no trash)
	var trash(default, null):Null<String->Null<String>>;
	var rename(default, null):Null<(from:String, to:String)->Void>;
	// a folder made (New Folder), a file or folder copied with what is in it
	// (a drop with Option, Alt: a copy); null where they cannot be; they throw
	// when they fail
	var makeFolder(default, null):Null<String->Void>;
	var copy(default, null):Null<(from:String, to:String)->Void>;
}

// (what a disk's Files share: a file, or a folder and what is in it, copied)
class Disk {
	public static function copy(from:String, to:String) {
		if (!sys.FileSystem.isDirectory(from)) {
			sys.io.File.copy(from, to);
			return;
		}
		sys.FileSystem.createDirectory(to);
		for (n in sys.FileSystem.readDirectory(from))
			copy(from + "/" + n, to + "/" + n);
	}
}
