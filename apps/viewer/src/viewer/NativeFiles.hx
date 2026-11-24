package viewer;

import helder.async.Async;
import helder.jobs.Channel;
import helder.jobs.Jobs;
import viewer.Files;

// The disk, through the system: a folder read on helder.jobs' pool (its
// names, then a stat of each, sent back 2,000 at a time over a channel),
// so the window never waits for it; a watch lists the folder again every
// few seconds; the trash is helder.os's.
class NativeFiles implements Files {
	public static inline var BATCH = 2000;

	public var trash(default, null):Null<String->Null<String>>;
	public var rename(default, null):Null<(from:String, to:String)->Void>;

	public function new() {
		trash = helder.os.Trash.available() ? p -> helder.os.Trash.move(p) : null;
		rename = (from, to) -> sys.FileSystem.rename(from, to);
	}

	public function list(dir:String, batch:Batch->Void):Void->Void {
		var ch = new Channel<Batch>(), stopped = false;
		Async.launch(t -> {
			t.async(_ -> Jobs.job(read).run({dir: dir, out: ch}));
			var b:Null<Batch>;
			while ((b = ch.receive()) != null)
				if (!stopped && !deliver(batch, b)) {
					stopped = true;
					ch.close();
				}
		});
		return () -> {
			stopped = true;
			ch.close();
		};
	}

	public function stat(path:String):Null<Entry>
		return entry(path, haxe.io.Path.withoutDirectory(path));

	public function open(path:String):helder.media.ByteSource
		return new helder.media.FileSource(path);

	public function localPath(path:String):Null<String>
		return path;

	public function watch(dir:String, every:Float, changed:Array<Entry>->Void):Void->Void {
		var stopped = false, last:Null<String> = null;
		Async.launch(_ -> while (!stopped) {
			var all = Jobs.job(whole).run(dir);
			if (stopped) break;
			if (all.error == null) {
				var sig = signature(all.entries);
				if (last != null && sig != last) changed(all.entries);
				last = sig;
			}
			Async.delay(every);
		});
		return () -> stopped = true;
	}

	// (a batch handed over; its handler failing: the listing ends, unreadable)
	static function deliver(batch:Batch->Void, b:Batch):Bool {
		try {
			batch(b);
			return true;
		} catch (e:Dynamic) {
			try batch({entries: [], done: true, error: "denied"}) catch (_:Dynamic) {}
			return false;
		}
	}

	static function signature(entries:Array<Entry>):String
		return [for (e in entries) e.name + "\x00" + e.size + "\x00" + e.modified].join("\x01");

	// (on the pool: the names, then each one's stat, in batches; a channel the
	// browser closed ends it)
	static function read(input:{dir:String, out:Channel<Batch>}):Int {
		var names = try hxmc.NativeSys.readDirectory(input.dir) catch (_:Dynamic) null;
		if (names == null) {
			try input.out.send({entries: [], done: true, error: failure(input.dir)}) catch (_:Dynamic) {}
			input.out.close();
			return 0;
		}
		var out = [];
		for (n in names) {
			var e = try entry(FolderModel.join(input.dir, n), n) catch (_:Dynamic) null;
			if (e != null) out.push(e);
			if (out.length < BATCH) continue;
			try input.out.send({entries: out, done: false}) catch (_:Dynamic) return 0;
			out = [];
		}
		try input.out.send({entries: out, done: true}) catch (_:Dynamic) {}
		input.out.close();
		return 0;
	}

	// (the watch's: the whole folder at once)
	static function whole(dir:String):Batch {
		var names = try hxmc.NativeSys.readDirectory(dir) catch (_:Dynamic) null;
		if (names == null) return {entries: [], done: true, error: failure(dir)};
		var out = [];
		for (n in names) {
			var e = try entry(FolderModel.join(dir, n), n) catch (_:Dynamic) null;
			if (e != null) out.push(e);
		}
		return {entries: out, done: true};
	}

	// (stat's fields: gid uid atime mtime ctime dev ino nlink rdev size mode;
	// Windows' ctime is the creation time, the others' a change's)
	static function entry(path:String, name:String):Null<Entry> {
		var s = hxmc.NativeSys.stat(path);
		if (s == null) return null;
		var folder = Std.int(s[10]) & 0xF000 == 0x4000;
		return {
			name: name,
			kind: folder ? Folder : File,
			size: folder ? 0 : s[9],
			modified: s[3],
			created: hxmc.Platform.os() == 2 ? s[4] : 0
		};
	}

	// (why a folder cannot be read: gone, not a folder, or not allowed)
	static function failure(dir:String):String {
		var s = try hxmc.NativeSys.stat(dir) catch (_:Dynamic) null;
		return s == null ? "missing" : Std.int(s[10]) & 0xF000 != 0x4000 ? "notfolder" : "denied";
	}
}
