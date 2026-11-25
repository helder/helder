package viewer;

import haxe.io.Bytes;
import helder.async.Async;
import helder.media.ByteSource;
import helder.os.Folders;
import helder.test.Test;
import viewer.Files;
import viewer.GrantFiles;

// GrantFiles over a stand-in of helder.os.Folders (a folder per grant, in
// memory, listed in batches of two a turn): the grants as tops and places,
// their folders listed and known, a file's bytes, its path on disk where
// the grant has one, a delete, what is missing or cannot be read; the
// shell's showFolder making a grant a place and going there
function tests() {
	describe("GrantFiles", () -> {
		test("tops, listings in batches, stat", async(() -> {
			var f = new GrantFiles(new FakeGrants());
			equals(f.places().map(p -> p.name + " " + p.path), ["Trip g1", "Phone g2"]);
			equals(f.stat("g1").kind, Folder);
			var batches = [];
			var got = listed(f, "g1", batches);
			equals(got.map(e -> e.name), ["Day 2", "a.jpg", "b.jpg"]);
			equals(batches, [2, 1]);
			equals(f.stat("g1/a.jpg").size, 3);
			equals(f.stat("g1/Day 2").kind, Folder);
			equals(listed(f, "g1/Day 2", []).map(e -> e.name), ["c.jpg"]);
			equals(f.stat("g1/Day 2/c.jpg").modified, 1700000000);
		}));
		test("bytes, a path on disk where there is one", async(() -> {
			var f = new GrantFiles(new FakeGrants());
			listed(f, "g1", []);
			equals(FileBytes.read(f, "g1/a.jpg").toString(), "abc");
			equals(f.localPath("g1/a.jpg"), "/disk/Trip/a.jpg");
			equals(f.localPath("g2"), null);
			equals(f.localPath("nope/a.jpg"), null);
		}));
		test("delete: gone from the grant and from what is known", async(() -> {
			var grants = new FakeGrants(), f = new GrantFiles(grants);
			listed(f, "g1", []);
			equals(f.delete("g1/b.jpg"), false);
			equals(f.stat("g1/b.jpg"), null);
			equals(listed(f, "g1", []).map(e -> e.name), ["Day 2", "a.jpg"]);
			equals(Std.string(throws(() -> f.delete("g1"))), "Not a grant's own folder");
		}));
		test("missing, unreadable", async(() -> {
			var f = new GrantFiles(new FakeGrants());
			equals(error(f, "nope"), "missing");
			equals(error(f, "g2"), "denied");
			equals(error(f, "g1/gone"), "denied");
		}));
		test("showFolder: a place, gone to", () -> {
			var grants = new FakeGrants(), f = new GrantFiles(grants);
			var x = new Explorer(f, (_, _, _) -> {}, f.places(), [], (_, _) -> () -> {});
			grants.all.push({id: "g3", name: "Card"});
			Shell.showFolder(x, f, {id: "g3", name: "Card"});
			equals(x.sidebar.places.value.map(p -> p.name), ["Trip", "Phone", "Card"]);
			equals(x.sidebar.title("g3"), "Card");
			equals(x.browser.dir.value, "g3");
			Shell.showFolder(x, f, {id: "g3", name: "Card"});
			equals(x.sidebar.places.value.length, 3);
		});
	});
	describe("PhoneFiles", () -> {
		test("the app's folder by its path, a grant by its id; no trash in a grant", async(() -> {
			var disk = new MemoryFiles();
			disk.add("/docs/");
			disk.add("/docs/x.jpg", Bytes.ofString("xy"));
			var grants = new GrantFiles(new FakeGrants()), f = new PhoneFiles(disk, grants);
			equals(f.stat("/docs/x.jpg").size, 2);
			equals(f.stat("g1").kind, Folder);
			listed(grants, "g1", []);
			equals(f.localPath("g1/a.jpg"), "/disk/Trip/a.jpg");
			equals(FileBytes.read(f, "g1/a.jpg").toString(), "abc");
			var failed = false;
			try f.trash("g1/a.jpg") catch (_:Dynamic) failed = true;
			equals(failed, true);
			f.trash("/docs/x.jpg");
			equals(disk.stat("/docs/x.jpg"), null);
		}));
	});
}

// (a listing's entries, its batches' sizes pushed to batches)
@:coroutine private function listed(f:GrantFiles, dir:String, batches:Array<Int>):Array<Entry> {
	var all:Array<Entry> = [];
	return Async.suspend(cont -> {
		f.list(dir, b -> {
			for (e in b.entries) all.push(e);
			batches.push(b.entries.length);
			if (b.done) Async.resumeLater(cont, all, null);
		});
	});
}

@:coroutine private function error(f:GrantFiles, dir:String):Null<String>
	return Async.suspend(cont -> f.list(dir, b -> if (b.done) Async.resumeLater(cont, b.error, null)));

// (g1 "Trip": a.jpg, b.jpg, Day 2/c.jpg, on a disk; g2 "Phone": unreadable)
private class FakeGrants implements Grants {
	public final all:Array<FolderGrant> = [{id: "g1", name: "Trip"}, {id: "g2", name: "Phone"}];

	final files = ["g1/a.jpg" => "abc", "g1/b.jpg" => "defg", "g1/Day 2/c.jpg" => "h"];

	public function new() {}

	public function granted():Array<FolderGrant>
		return all.copy();

	@:coroutine public function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool {
		if (grant != "g1") return false;
		var dir = path == "" ? grant : grant + "/" + path, out:Array<FolderEntry> = [], folders = new Map<String, Bool>();
		for (p => text in files) {
			if (!StringTools.startsWith(p, dir + "/")) continue;
			var rest = p.substr(dir.length + 1), slash = rest.indexOf("/");
			if (slash < 0) out.push({name: rest, folder: false, size: text.length, modified: 1700000000});
			else if (!folders.exists(rest.substr(0, slash))) {
				folders.set(rest.substr(0, slash), true);
				out.push({name: rest.substr(0, slash), folder: true, size: 0, modified: 0});
			}
		}
		if (out.length == 0 && path != "") return false;
		out.sort((a, b) -> Reflect.compare(a.name, b.name));
		while (out.length > 2) {
			batch(out.splice(0, 2), false);
			Async.delay(0);
		}
		batch(out, true);
		return true;
	}

	public function open(grant:String, path:String):ByteSource
		return new TextSource(files.get(grant + "/" + path) ?? throw "No such file");

	public function file(grant:String, path:String):Null<String>
		return grant == "g1" ? "/disk/Trip" + (path == "" ? "" : "/" + path) : null;

	public function delete(grant:String, path:String):Bool {
		if (!files.remove(grant + "/" + path)) throw "Not deleted";
		return false;
	}
}

private class TextSource implements ByteSource {
	public var size(get, never):Float;

	final b:Bytes;

	public function new(text:String)
		b = Bytes.ofString(text);

	function get_size():Float
		return b.length;

	@:coroutine public function read(offset:Float, to:Bytes, pos:Int, len:Int):Int {
		var n = Std.int(Math.max(0, Math.min(len, b.length - offset)));
		if (n > 0) to.blit(pos, b, Std.int(offset), n);
		return n;
	}

	public function close() {}
}
