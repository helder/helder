package helder.os.android;

import haxe.io.Bytes;
import helder.media.ByteSource;
import helder.os.Folders;
import helder.os.KeptFolders;
import hxmc.unsafe.*;

// helder.os.Folders on Android: the Storage Access Framework's document
// tree (ACTION_OPEN_DOCUMENT_TREE, started for its result through
// org.hxmc.Request), its permission taken persistable and its URI kept
// (KeptFolders), never all of the storage (no MANAGE_EXTERNAL_STORAGE). A
// path's document is found by its folders' children (DocumentsContract's
// queries: id, name, type, size, date), the ids kept by path for the run;
// a folder's children read 500 rows at a time, each batch a post of the
// main thread's. A file's bytes are its descriptor's
// (ContentResolver.openFileDescriptor, detached), read on any thread;
// a delete is DocumentsContract.deleteDocument's, for good. Only the
// framework's classes: nothing of classes.dex but Request's.
@:hxmc.android @:helder.android.dex("Request")
@:hxmc.unsafe(gc)
class AndroidFolders {
	static inline var DIRECTORY = "vnd.android.document/directory";

	// (the grants' trees this run: their URIs, global references, and their documents' ids by path)
	static final trees = new Map<String, {uri:Ptr, docs:Map<String, String>}>();

	@:coroutine public static function pick():Null<FolderGrant>
		return helder.os.Await.answer(done -> MainThread.post(() -> {
			try {
				AndroidRequest.start(i -> {
					var intent = Jni.cls("android.content.Intent");
					var tree = Jni.newObject(intent, Jni.method(intent, "<init>", "(Ljava/lang/String;)V"),
						Jni.string("android.intent.action.OPEN_DOCUMENT_TREE").toI64());
					// (FLAG_GRANT_READ_URI_PERMISSION, WRITE, PERSISTABLE, PREFIX)
					Jni.obj(tree, Jni.method(intent, "addFlags", "(I)Landroid/content/Intent;"), 0x1 | 0x2 | 0x40 | 0x80);
					Jni.obj(i, Jni.method(intent, "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"),
						Jni.string("intent").toI64(), tree.toI64());
				}, (code, data) -> done(code == -1 ? taken(data) : null));
			} catch (e:Dynamic) {
				Sys.println("helder.os: Folders.pick: " + Std.string(e));
				done(null);
			}
		}));

	public static function granted():Array<FolderGrant>
		return [for (g in KeptFolders.all()) {id: g.id, name: g.name}];

	public static function forget(id:String) {
		var g = KeptFolders.get(id);
		if (g == null) return;
		MainThread.run(() -> {
			try Jni.call(resolver(), Jni.method(Jni.cls("android.content.ContentResolver"), "releasePersistableUriPermission", "(Landroid/net/Uri;I)V"),
				parse(g.data).toI64(), 0x1 | 0x2)
			catch (_:Dynamic) {}
			var t = trees.get(id);
			if (t != null) Jni.deleteGlobal(t.uri);
			trees.remove(id);
		});
		KeptFolders.remove(id);
	}

	@:coroutine public static function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool {
		var loop = helder.async.Loop.current();
		return helder.os.Await.answer(done -> MainThread.post(() -> {
			var t = tree(grant), dir = t == null ? null : try doc(t, path) catch (_:Dynamic) null;
			if (dir == null) return done(false);
			var cursor = try children(t.uri, dir) catch (_:Dynamic) Ptr.nil();
			if (cursor.isNull()) return done(false);
			function next() {
				Jni.pushFrame();
				var rows = try read(cursor, 500) catch (_:Dynamic) null;
				Jni.popFrame();
				if (rows == null) {
					close(cursor);
					return done(false);
				}
				for (r in rows)
					t.docs.set(path == "" ? r.name : path + "/" + r.name, r.id);
				var entries = [for (r in rows) r.entry], last = rows.length < 500;
				loop.post(() -> batch(entries, last));
				if (!last) return MainThread.post(next);
				close(cursor);
				done(true);
			}
			next();
		}));
	}

	public static function open(grant:String, path:String):ByteSource {
		var fd = -1;
		MainThread.run(() -> {
			var t = tree(grant), id = t == null ? null : try doc(t, path) catch (_:Dynamic) null;
			if (id == null) return;
			Jni.pushFrame();
			try {
				var pfd = Jni.obj(resolver(), Jni.method(Jni.cls("android.content.ContentResolver"), "openFileDescriptor",
					"(Landroid/net/Uri;Ljava/lang/String;)Landroid/os/ParcelFileDescriptor;"), document(t.uri, id).toI64(), Jni.string("r").toI64());
				if (!pfd.isNull()) fd = Jni.int(pfd, Jni.method(Jni.cls("android.os.ParcelFileDescriptor"), "detachFd", "()I"));
			} catch (e:Dynamic) Sys.println("helder.os: Folders.open: " + Std.string(e));
			Jni.popFrame();
		});
		if (fd < 0) throw "Folders: the file cannot be opened";
		return new FdSource(fd);
	}

	public static function delete(grant:String, path:String):Bool {
		var gone = false;
		MainThread.run(() -> {
			var t = tree(grant), id = t == null ? null : try doc(t, path) catch (_:Dynamic) null;
			if (id == null) return;
			Jni.pushFrame();
			var contract = Jni.cls("android.provider.DocumentsContract");
			gone = try Jni.staticBool(contract, Jni.staticMethod(contract, "deleteDocument", "(Landroid/content/ContentResolver;Landroid/net/Uri;)Z"),
				resolver().toI64(), document(t.uri, id).toI64()) catch (_:Dynamic) false;
			Jni.popFrame();
			if (gone) t.docs.remove(path);
		});
		if (!gone) throw "Folders: not deleted";
		return false;
	}

	// (the main thread: the result's tree, its permission taken and kept; its grant)
	static function taken(data:Ptr):Null<FolderGrant> {
		if (data.isNull()) return null;
		try {
			var intent = Jni.cls("android.content.Intent");
			var uri = Jni.obj(data, Jni.method(intent, "getData", "()Landroid/net/Uri;"));
			if (uri.isNull()) return null;
			var flags = Jni.int(data, Jni.method(intent, "getFlags", "()I")) & (0x1 | 0x2);
			Jni.call(resolver(), Jni.method(Jni.cls("android.content.ContentResolver"), "takePersistableUriPermission", "(Landroid/net/Uri;I)V"), uri.toI64(),
				flags);
			var text = Jni.fromString(Jni.obj(uri, Jni.method(Jni.cls("java.lang.Object"), "toString", "()Ljava/lang/String;")));
			var contract = Jni.cls("android.provider.DocumentsContract");
			var root = Jni.staticObj(contract, Jni.staticMethod(contract, "getTreeDocumentId", "(Landroid/net/Uri;)Ljava/lang/String;"), uri.toI64());
			var name = nameOf(document(uri, Jni.fromString(root))) ?? "Folder";
			var id = KeptFolders.keep(text, name, text);
			var was = trees.get(id);
			if (was != null) Jni.deleteGlobal(was.uri);
			trees.set(id, {uri: Jni.global(uri), docs: ["" => Jni.fromString(root)]});
			return {id: id, name: name};
		} catch (e:Dynamic) {
			Sys.println("helder.os: Folders.pick: " + Std.string(e));
			return null;
		}
	}

	// (the main thread: a grant's tree for this run; null: forgotten)
	static function tree(id:String):Null<{uri:Ptr, docs:Map<String, String>}> {
		var t = trees.get(id);
		if (t != null) return t;
		var g = KeptFolders.get(id);
		if (g == null) return null;
		var uri = parse(g.data), contract = Jni.cls("android.provider.DocumentsContract");
		var root = Jni.staticObj(contract, Jni.staticMethod(contract, "getTreeDocumentId", "(Landroid/net/Uri;)Ljava/lang/String;"), uri.toI64());
		t = {uri: Jni.global(uri), docs: ["" => Jni.fromString(root)]};
		trees.set(id, t);
		return t;
	}

	// (the main thread: a path's document id, its folders' children read where not known; null: none)
	static function doc(t:{uri:Ptr, docs:Map<String, String>}, path:String):Null<String> {
		var at = "";
		for (part in path.split("/"))
			if (part != "") {
				var p = at == "" ? part : at + "/" + part;
				if (!t.docs.exists(p)) {
					var parent = t.docs.get(at);
					if (parent == null) return null;
					var cursor = children(t.uri, parent);
					if (cursor.isNull()) return null;
					while (true) {
						Jni.pushFrame();
						var rows = try read(cursor, 500) catch (_:Dynamic) [];
						Jni.popFrame();
						for (r in rows)
							t.docs.set(at == "" ? r.name : at + "/" + r.name, r.id);
						if (rows.length < 500) break;
					}
					close(cursor);
				}
				if (!t.docs.exists(p)) return null;
				at = p;
			}
		return t.docs.get(at);
	}

	static final COLUMNS = ["document_id", "_display_name", "mime_type", "_size", "last_modified"];

	// (the main thread: a folder's children's cursor, a global reference; nil when none)
	static function children(tree:Ptr, parent:String):Ptr {
		Jni.pushFrame();
		var contract = Jni.cls("android.provider.DocumentsContract");
		var uri = Jni.staticObj(contract, Jni.staticMethod(contract, "buildChildDocumentsUriUsingTree",
			"(Landroid/net/Uri;Ljava/lang/String;)Landroid/net/Uri;"), tree.toI64(), Jni.string(parent).toI64());
		var c = Jni.obj(resolver(), Jni.method(Jni.cls("android.content.ContentResolver"), "query",
			"(Landroid/net/Uri;[Ljava/lang/String;Landroid/os/Bundle;Landroid/os/CancellationSignal;)Landroid/database/Cursor;"), uri.toI64(),
			Jni.strings(COLUMNS).toI64(), 0, 0);
		var g = c.isNull() ? Ptr.nil() : Jni.global(c);
		Jni.popFrame();
		return g;
	}

	// (the main thread: at most n rows more of the cursor)
	static function read(cursor:Ptr, n:Int):Array<{id:String, name:String, entry:FolderEntry}> {
		var c = Jni.cls("android.database.Cursor"), out = [];
		var next = Jni.method(c, "moveToNext", "()Z"), string = Jni.method(c, "getString", "(I)Ljava/lang/String;"),
			long = Jni.method(c, "getLong", "(I)J"), isNull = Jni.method(c, "isNull", "(I)Z");
		while (out.length < n && Jni.bool(cursor, next)) {
			var name = Jni.obj(cursor, string, 1);
			if (name.isNull()) continue;
			var mime = Jni.obj(cursor, string, 2), folder = !mime.isNull() && Jni.fromString(mime) == DIRECTORY;
			var size = folder || Jni.bool(cursor, isNull, 3) ? 0.0 : num(Jni.long(cursor, long, 3));
			var date = Jni.bool(cursor, isNull, 4) ? 0.0 : num(Jni.long(cursor, long, 4)) / 1000;
			var n = Jni.fromString(name);
			out.push({id: Jni.fromString(Jni.obj(cursor, string, 0)), name: n, entry: {name: n, folder: folder, size: size, modified: date}});
			for (o in [name, mime])
				if (!o.isNull()) Jni.deleteLocal(o);
		}
		return out;
	}

	static function close(cursor:Ptr) {
		try Jni.call(cursor, Jni.method(Jni.cls("android.database.Cursor"), "close", "()V")) catch (_:Dynamic) {}
		Jni.deleteGlobal(cursor);
	}

	// (the main thread: a document's display name)
	static function nameOf(uri:Ptr):Null<String> {
		var c = Jni.obj(resolver(), Jni.method(Jni.cls("android.content.ContentResolver"), "query",
			"(Landroid/net/Uri;[Ljava/lang/String;Landroid/os/Bundle;Landroid/os/CancellationSignal;)Landroid/database/Cursor;"), uri.toI64(),
			Jni.strings(["_display_name"]).toI64(), 0, 0);
		if (c.isNull()) return null;
		var cls = Jni.cls("android.database.Cursor"), name:Null<String> = null;
		if (Jni.bool(c, Jni.method(cls, "moveToFirst", "()Z"))) {
			var s = Jni.obj(c, Jni.method(cls, "getString", "(I)Ljava/lang/String;"), 0);
			if (!s.isNull()) name = Jni.fromString(s);
		}
		Jni.call(c, Jni.method(cls, "close", "()V"));
		return name;
	}

	// (the main thread: a document's URI in the tree, a local reference)
	static function document(tree:Ptr, id:String):Ptr {
		var contract = Jni.cls("android.provider.DocumentsContract");
		return Jni.staticObj(contract, Jni.staticMethod(contract, "buildDocumentUriUsingTree", "(Landroid/net/Uri;Ljava/lang/String;)Landroid/net/Uri;"),
			tree.toI64(), Jni.string(id).toI64());
	}

	static function parse(uri:String):Ptr {
		var cls = Jni.cls("android.net.Uri");
		return Jni.staticObj(cls, Jni.staticMethod(cls, "parse", "(Ljava/lang/String;)Landroid/net/Uri;"), Jni.string(uri).toI64());
	}

	// (a long as a Float: its millions and the rest)
	@:allow(helder.os.android) static function num(v:haxe.Int64):Float
		return haxe.Int64.toInt(v / 1000000) * 1e6 + haxe.Int64.toInt(v % 1000000);

	static function resolver():Ptr
		return Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getContentResolver", "()Landroid/content/ContentResolver;"));
}

// (a document's descriptor, detached: its bytes at any offset, on any thread; its size where it seeks)
@:hxmc.unsafe(gc)
private class FdSource implements ByteSource {
	public var size(get, never):Float;

	var fd:Int;
	final total:Float;
	var at = 0.0;

	public function new(fd:Int) {
		this.fd = fd;
		var end = Posix.lseek(fd, 0, 2);
		total = end < 0 ? -1 : AndroidFolders.num(end);
		Posix.lseek(fd, 0, 0);
	}

	function get_size():Float
		return total;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int
		return readAt(offset, b, pos, len);

	// (a plain function: helder.async's coroutines rethrow a caught error)
	function readAt(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (fd < 0) throw "Folders: closed";
		if (offset < 0 || pos < 0 || len < 0 || pos + len > b.length) throw "Folders: read out of range";
		if (len == 0 || (total >= 0 && offset >= total)) return 0;
		if (offset != at && Posix.lseek(fd, (Std.int(offset / 1e6) : haxe.Int64) * 1000000 + Std.int(offset % 1e6), 0) < 0) throw "Folders: the file does not seek";
		at = offset;
		var buf = LibC.malloc(len), n = 0;
		while (n < len) {
			var k = Posix.read(fd, buf.add(n), len - n).toInt();
			if (k <= 0) break;
			n += k;
		}
		if (n > 0) BytesPtr.copyIn(b, pos, buf, n);
		LibC.free(buf);
		at += n;
		return n;
	}

	public function close() {
		if (fd >= 0) Posix.close(fd);
		fd = -1;
	}
}
