package helder.os;

#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import haxe.io.Bytes;
import helder.media.ByteSource;
import helder.os.Folders;
import helder.os.objc.*;
import hxmc.objc.Block;
import hxmc.unsafe.*;

// helder.os.Folders on iOS: UIDocumentPickerViewController of folders
// (UTType public.folder, UniformTypeIdentifiers loaded when first asked)
// over the app's window, its delegate a class made at run time; the URL
// picked kept as a bookmark (KeptFolders: iOS's bookmarks carry the
// picker's security scope), resolved at the next launch (made again when
// stale), its access started once and held while the app runs. Listings
// and deletes are NSFileCoordinator's (a provider's folder read as it
// has it, its items' metadata only: nothing downloaded), FileManager's
// listing with the resource keys asked once, on a thread of their own;
// a file's first read is coordinated too (an iCloud file downloaded),
// then its path read.
@:hxmc.unsafe(gc)
class FoldersApple {
	static var delegate = Ptr.nil();
	static var picked:Null<Ptr->Void>;
	// (the grants resolved this run: their URLs, accessed, and paths)
	static final resolved = new Map<String, {url:Ptr, path:String}>();

	@:coroutine public static function pick():Null<FolderGrant> {
		var url:Ptr = Await.answer(done -> OsThread.run(() -> present(done)));
		if (url.isNull()) return null;
		var pool = Runtime.objc_autoreleasePoolPush();
		Msg.b(url, ObjC.sel("startAccessingSecurityScopedResource"));
		var g = keep(url);
		Runtime.objc_autoreleasePoolPop(pool);
		if (g == null) Msg.v(url, ObjC.sel("stopAccessingSecurityScopedResource"));
		ObjC.release(url);
		return g;
	}

	public static function granted():Array<FolderGrant>
		return [for (g in KeptFolders.all()) {id: g.id, name: g.name}];

	public static function forget(id:String) {
		var o = resolved.get(id);
		if (o != null) {
			Msg.v(o.url, ObjC.sel("stopAccessingSecurityScopedResource"));
			ObjC.release(o.url);
			resolved.remove(id);
		}
		KeptFolders.remove(id);
	}

	@:coroutine public static function list(grant:String, path:String, batch:(entries:Array<FolderEntry>, done:Bool) -> Void):Bool {
		var url = item(grant, path);
		if (url.isNull()) return false;
		var loop = helder.async.Loop.current();
		return Await.answer(done -> sys.thread.Thread.create(() -> {
			var ok = read(url, entries -> loop.post(() -> batch(entries, false)));
			ObjC.release(url);
			if (ok) loop.post(() -> batch([], true));
			done(ok);
		}));
	}

	public static function open(grant:String, path:String):ByteSource {
		var url = item(grant, path);
		if (url.isNull()) throw "Folders: no such grant";
		return new Coordinated(url);
	}

	public static function file(grant:String, path:String):Null<String> {
		var o = resolve(grant);
		return o == null ? null : path == "" ? o.path : o.path + "/" + path;
	}

	// (to the trash where the provider has one, else removed; coordinated as a delete)
	public static function delete(grant:String, path:String):Bool {
		var url = item(grant, path);
		if (url.isNull()) throw "Folders: no such grant";
		var pool = Runtime.objc_autoreleasePoolPush(), state = 0;
		var fm = Msg.id(ObjC.cls("NSFileManager"), ObjC.sel("defaultManager"));
		var accessor:Block<Ptr->Void> = u -> state = Msg.bPtrPtrPtr(fm, ObjC.sel("trashItemAtURL:resultingItemURL:error:"), u, Ptr.nil(), Ptr.nil()) ? 1
			: Msg.bPtrPtr(fm, ObjC.sel("removeItemAtURL:error:"), u, Ptr.nil()) ? 2 : 0;
		var c = Msg.id(Msg.idPtr(Msg.id(ObjC.cls("NSFileCoordinator"), ObjC.sel("alloc")), ObjC.sel("initWithFilePresenter:"), Ptr.nil()), ObjC.sel("autorelease"));
		// (NSFileCoordinatorWritingForDeleting)
		Msg.vPtrIntPtrPtr(c, ObjC.sel("coordinateWritingItemAtURL:options:error:byAccessor:"), url, 1, Ptr.nil(), cast accessor);
		Runtime.objc_autoreleasePoolPop(pool);
		ObjC.release(url);
		if (state == 0) throw "Folders: not deleted";
		return state == 1;
	}

	// a folder the app reads already (its own container's) kept as one
	// picked would be: the tests' (the picker cannot be answered unattended)
	public static function grant(path:String):Null<FolderGrant> {
		var pool = Runtime.objc_autoreleasePoolPush(), p = ObjC.str(path);
		var g = keep(Msg.idPtrBool(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:isDirectory:"), p, true));
		ObjC.release(p);
		Runtime.objc_autoreleasePoolPop(pool);
		return g;
	}

	// (the main thread: the picker over the window's topmost controller; done(the URL picked, retained; nil))
	static function present(done:Ptr->Void) {
		var host = helder.os.uikit.UIKitWindow.controllerNow();
		if (host.isNull()) return done(Ptr.nil());
		var pool = Runtime.objc_autoreleasePoolPush();
		var folder = ObjC.str("public.folder");
		var type = Msg.idPtr(PermissionsApple.load("UniformTypeIdentifiers", "UTType"), ObjC.sel("typeWithIdentifier:"), folder);
		ObjC.release(folder);
		var types = Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), type);
		var vc = Msg.id(Msg.idPtrBool(Msg.id(ObjC.cls("UIDocumentPickerViewController"), ObjC.sel("alloc")), ObjC.sel("initForOpeningContentTypes:asCopy:"),
			types, false), ObjC.sel("autorelease"));
		if (delegate.isNull()) {
			var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcFoldersDelegate"), 0);
			Runtime.class_addMethod(cls, ObjC.sel("documentPicker:didPickDocumentsAtURLs:"), Callback.addr(didPick), Mem.cstr("v@:@@"));
			Runtime.class_addMethod(cls, ObjC.sel("documentPickerWasCancelled:"), Callback.addr(cancelled), Mem.cstr("v@:@"));
			Runtime.objc_registerClassPair(cls);
			delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		}
		Msg.vPtr(vc, ObjC.sel("setDelegate:"), delegate);
		picked = done;
		var top = host;
		while (true) {
			var p = Msg.id(top, ObjC.sel("presentedViewController"));
			if (p.isNull()) break;
			top = p;
		}
		Msg.vPtrBoolPtr(top, ObjC.sel("presentViewController:animated:completion:"), vc, true, Ptr.nil());
		Runtime.objc_autoreleasePoolPop(pool);
	}

	@:hxmc.callback static function didPick(self:Ptr, cmd:Ptr, picker:Ptr, urls:Ptr):Void {
		var done = picked;
		picked = null;
		if (done == null) return;
		done(Msg.i(urls, ObjC.sel("count")).toInt() > 0 ? Runtime.objc_retain(Msg.idInt(urls, ObjC.sel("objectAtIndex:"), 0)) : Ptr.nil());
	}

	@:hxmc.callback static function cancelled(self:Ptr, cmd:Ptr, picker:Ptr):Void {
		var done = picked;
		picked = null;
		if (done != null) done(Ptr.nil());
	}

	// (an accessed URL kept as a bookmark, and resolved for this run: its grant; null when it cannot be)
	static function keep(url:Ptr):Null<FolderGrant> {
		var data = Msg.idIntPtrPtrPtr(url, ObjC.sel("bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:"), 0, Ptr.nil(), Ptr.nil(),
			Ptr.nil());
		if (data.isNull()) return null;
		var path = ObjC.string(Msg.id(url, ObjC.sel("path"))) ?? "", name = ObjC.string(Msg.id(url, ObjC.sel("lastPathComponent"))) ?? "Folder";
		var id = KeptFolders.keep(path, name, ObjC.string(Msg.idInt(data, ObjC.sel("base64EncodedStringWithOptions:"), 0)) ?? "");
		var was = resolved.get(id);
		if (was != null) {
			Msg.v(was.url, ObjC.sel("stopAccessingSecurityScopedResource"));
			ObjC.release(was.url);
		}
		resolved.set(id, {url: Runtime.objc_retain(url), path: path});
		return {id: id, name: name};
	}

	// (a grant's URL for this run: its bookmark resolved, accessed; null when forgotten or gone)
	static function resolve(id:String):Null<{url:Ptr, path:String}> {
		var o = resolved.get(id);
		if (o != null) return o;
		var g = KeptFolders.get(id);
		if (g == null) return null;
		var pool = Runtime.objc_autoreleasePoolPush(), stale:Ptr = LibC.malloc(8), text = ObjC.str(g.data);
		Mem.setI8(stale, 0, 0);
		var data = Msg.id(Msg.idPtrInt(Msg.id(ObjC.cls("NSData"), ObjC.sel("alloc")), ObjC.sel("initWithBase64EncodedString:options:"), text, 0),
			ObjC.sel("autorelease"));
		ObjC.release(text);
		var url = data.isNull() ? Ptr.nil() : Msg.idPtrIntPtrPtrPtr(ObjC.cls("NSURL"), ObjC.sel("URLByResolvingBookmarkData:options:relativeToURL:bookmarkDataIsStale:error:"),
			data, 0, Ptr.nil(), stale, Ptr.nil());
		if (!url.isNull()) {
			Msg.b(url, ObjC.sel("startAccessingSecurityScopedResource"));
			// (stale: the folder moved or was renamed; kept again, under the id it had)
			if (Mem.getU8(stale, 0) != 0) {
				var fresh = Msg.idIntPtrPtrPtr(url, ObjC.sel("bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:"), 0, Ptr.nil(),
					Ptr.nil(), Ptr.nil());
				if (!fresh.isNull()) KeptFolders.update(id, ObjC.string(Msg.idInt(fresh, ObjC.sel("base64EncodedStringWithOptions:"), 0)) ?? g.data);
			}
			o = {url: Runtime.objc_retain(url), path: ObjC.string(Msg.id(url, ObjC.sel("path"))) ?? ""};
			resolved.set(id, o);
		}
		LibC.free(stale);
		Runtime.objc_autoreleasePoolPop(pool);
		return o;
	}

	// (an item's URL in a grant, retained; nil: no such grant)
	static function item(grant:String, path:String):Ptr {
		var o = resolve(grant);
		if (o == null) return Ptr.nil();
		if (path == "") return Runtime.objc_retain(o.url);
		var p = ObjC.str(path);
		var u = Runtime.objc_retain(Msg.idPtr(o.url, ObjC.sel("URLByAppendingPathComponent:"), p));
		ObjC.release(p);
		return u;
	}

	// (a thread of its own: the folder's entries in batches of 500; false when it cannot be read)
	static function read(url:Ptr, batch:Array<FolderEntry>->Void):Bool {
		var pool = Runtime.objc_autoreleasePoolPush(), ok = false;
		var nameKey = ObjC.str("NSURLNameKey"), dirKey = ObjC.str("NSURLIsDirectoryKey"), sizeKey = ObjC.str("NSURLFileSizeKey"),
			dateKey = ObjC.str("NSURLContentModificationDateKey");
		var keys = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
		for (k in [nameKey, dirKey, sizeKey, dateKey])
			Msg.vPtr(keys, ObjC.sel("addObject:"), k);
		var accessor:Block<Ptr->Void> = u -> {
			var fm = Msg.id(ObjC.cls("NSFileManager"), ObjC.sel("defaultManager"));
			var all = Msg.idPtrPtrIntPtr(fm, ObjC.sel("contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:"), u, keys, 0, Ptr.nil());
			if (all.isNull()) return;
			ok = true;
			var n = Msg.i(all, ObjC.sel("count")).toInt(), out = [];
			for (i in 0...n) {
				var inner = Runtime.objc_autoreleasePoolPush();
				var v = Msg.idPtrPtr(Msg.idInt(all, ObjC.sel("objectAtIndex:"), i), ObjC.sel("resourceValuesForKeys:error:"), keys, Ptr.nil());
				function get(k:Ptr):Ptr
					return v.isNull() ? Ptr.nil() : Msg.idPtr(v, ObjC.sel("objectForKey:"), k);
				var name = ObjC.string(get(nameKey)) ?? "", folder = !get(dirKey).isNull() && Msg.b(get(dirKey), ObjC.sel("boolValue"));
				var size = get(sizeKey), date = get(dateKey);
				// (an iCloud file not downloaded, before iOS 17: ".name.icloud", its own name shown)
				if (!folder && StringTools.startsWith(name, ".") && StringTools.endsWith(name, ".icloud") && name.length > 8)
					name = name.substring(1, name.length - 7);
				if (name != "")
					out.push({name: name, folder: folder, size: size.isNull() || folder ? 0.0 : Msg.f(size, ObjC.sel("doubleValue")),
						modified: date.isNull() ? 0.0 : Msg.f(date, ObjC.sel("timeIntervalSince1970"))});
				Runtime.objc_autoreleasePoolPop(inner);
				if (out.length == 500) batch(out.splice(0, out.length));
			}
			if (out.length > 0) batch(out);
		};
		var c = Msg.id(Msg.idPtr(Msg.id(ObjC.cls("NSFileCoordinator"), ObjC.sel("alloc")), ObjC.sel("initWithFilePresenter:"), Ptr.nil()), ObjC.sel("autorelease"));
		// (NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly: the listing, nothing downloaded)
		Msg.vPtrIntPtrPtr(c, ObjC.sel("coordinateReadingItemAtURL:options:error:byAccessor:"), url, 1 << 2, Ptr.nil(), cast accessor);
		for (k in [nameKey, dirKey, sizeKey, dateKey])
			ObjC.release(k);
		Runtime.objc_autoreleasePoolPop(pool);
		return ok;
	}

	// (a thread's: the file read as its provider has it, downloaded first where it is not; its path, null when it cannot be)
	@:allow(helder.os) static function coordinated(url:Ptr):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush(), path:Null<String> = null;
		var accessor:Block<Ptr->Void> = u -> path = ObjC.string(Msg.id(u, ObjC.sel("path")));
		var c = Msg.id(Msg.idPtr(Msg.id(ObjC.cls("NSFileCoordinator"), ObjC.sel("alloc")), ObjC.sel("initWithFilePresenter:"), Ptr.nil()), ObjC.sel("autorelease"));
		Msg.vPtrIntPtrPtr(c, ObjC.sel("coordinateReadingItemAtURL:options:error:byAccessor:"), url, 0, Ptr.nil(), cast accessor);
		Runtime.objc_autoreleasePoolPop(pool);
		return path;
	}
}

// (a file's bytes: its first read coordinated on a thread, then its path read)
@:hxmc.unsafe(gc)
private class Coordinated implements ByteSource {
	public var size(get, never):Float;

	var url:Ptr;
	var source:Null<ByteSource> = null;

	public function new(url:Ptr)
		this.url = url;

	function get_size():Float
		return source == null ? -1 : source.size;

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (source == null) {
			var u = url;
			var path:Null<String> = Await.answer(done -> sys.thread.Thread.create(() -> done(FoldersApple.coordinated(u))));
			if (path == null) throw "Folders: the file cannot be read";
			source = new helder.media.FileSource(path);
		}
		return source.read(offset, b, pos, len);
	}

	public function close() {
		if (source != null) source.close();
		ObjC.release(url);
		url = Ptr.nil();
	}
}
#else
class FoldersApple {}
#end
