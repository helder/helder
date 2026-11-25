package viewer;

import helder.os.Places;
import viewer.Decode.Decoded;
import viewer.Files;
import viewer.Listing;
import helder.ui.actions.ActionState;
import viewer.ViewerActions;

using StringTools;

// The file browser and its full-size viewer without a window: a folder
// browsed, a file opened full size from it (the viewer stepping through
// the browser's list, in its order), the sidebar following the folder,
// the actions of the keymap and the menus. The shell gives it its window;
// tests drive it headless (MemoryFiles, a decode of their own).
class Explorer {
	public final files:Files;
	public final browser:Browser;
	public final sidebar:Sidebar;
	public final viewer:Viewer;
	// a file open full size
	public final full = new Cell(false);
	// its opening from its tile and closing into it
	public final zoom:Flight;
	// the path bar being edited (Mod+L)
	public final editingPath = helder.view.graph.Graph.signal(false);
	// the shell's: the system's file manager at a file, the default app, the clipboard
	public var reveal:Null<String->Void> = null;
	public var openDefault:Null<String->Void> = null;
	public var copy:Null<String->Void> = null;
	// the web's: a folder of the user's picked and shown (none: no button for it)
	public var openFolder:Null<Void->Void> = null;
	// a phone's: the system's folder picker, the folder added to the places
	// (none: no Add a folder…)
	public var addFolder:Null<Void->Void> = null;
	// the system's share sheet with these files (a phone's Open in…; none: not shown)
	public var share:Null<Array<String>->Void> = null;
	// the files opened last, the newest first (the shell's store: Recents, Open Recent)
	public final recent:Cell<Array<String>> = new Cell([]);
	// a tablet's sidebar over the folder, its inspector in a sheet
	public final sidebarOpen = new Cell(false);
	public final infoOpen = new Cell(false);
	// (the tablet's Get Info button: its sheet's popover's anchor)
	public var infoAnchor:Null<helder.ui.Node> = null;
	// the thumbnails' queue (the shell's; none: glyphs alone)
	public var thumbnails:Null<Thumbnails> = null;
	// the list's focus on its selection (the shell's, once the list is made)
	public var focusList:Null<Void->Void> = null;
	// the inspector's preview of a file (Preview.request; tests: Preview.now;
	// a Markdown document's: its text read and parsed)
	public final preview:(path:String, done:Preview.Shown->Void)->(Void->Void);
	// a file's text (a Markdown document's: read through files, by default on the loop)
	public final read:(path:String, done:Null<String>->Void)->Void;
	// a web address opened (a document's link): the system's browser, a new tab on the web
	public var openUrl:String->Bool = url -> helder.os.Links.open(url, false);

	var choosing = false;
	static inline var RECENT = 20;

	public function new(files:Files, decode:(path:String, side:Int, done:Decoded->Void) -> Void, ?places:Array<Place>, ?volumes:Array<Volume>,
			?preview:(path:String, done:Preview.Shown->Void)->(Void->Void), ?pdfSizes:(path:String, done:PdfPages.PdfSizes->Void)->Void,
			?read:(path:String, done:Null<String>->Void)->Void) {
		this.files = files;
		this.read = read ?? (path, done) -> readAll(files, path, done);
		var pictures = preview ?? #if (hxmc.target == "wasm32-wasi") (_, _) -> () -> {} #else Preview.request #end;
		this.preview = (path, done) -> FolderModel.isMarkdown(path) ? markdownPreview(path, done) : pictures(path, done);
		browser = new Browser(files);
		sidebar = new Sidebar(files, places ?? [], volumes ?? []);
		viewer = new Viewer(decode, null, pdfSizes);
		viewer.read = this.read;
		viewer.measure = (paths, done) -> measureAll(files, paths, done);
		zoom = new Flight(this);
		browser.onDir = d -> {
			if (!choosing) sidebar.follow(d);
			// (another folder: the decodes of the last let go)
			if (!full.value) viewer.release();
		};
		browser.onItems = () -> if (full.value) viewer.relist(browser.viewable());
		browser.onModified = paths -> viewer.modified(paths);
		browser.onMoved = (from, to) -> sidebar.moved(from, to);
		viewer.onOpened = p -> {
			var r = recent.value.filter(q -> q != p);
			r.unshift(p);
			if (r.length > RECENT) r.resize(RECENT);
			recent(r);
		};
	}

	// what the command line names: a folder browsed, a file full size in its folder
	public function start(path:String) {
		path = Browser.normalize(path);
		var e = files.stat(path);
		if (e == null || e.kind == Folder) {
			browser.go(path);
			return;
		}
		var dir = Browser.parent(path) ?? path, name = Browser.name(path);
		browser.go(dir, name);
		if (Kinds.viewable(e)) view(name);
	}

	// a place or a device chosen in the sidebar: there, its own level shown
	public function choose(path:String) {
		choosing = true;
		browser.go(path);
		choosing = false;
		sidebar.show(Browser.normalize(path));
	}

	// the selected entry (or one named) opened: a folder entered, a file the
	// viewer shows full size, any other the system's app for it
	public function open(?name:String):Bool {
		// (the last folder's rows still shown, this one's not read yet: theirs are not here)
		if (browser.stale) return false;
		var e = browser.entry(name ?? browser.selected.value);
		if (e == null) return false;
		browser.select(e.name);
		if (e.kind == Folder) browser.go(browser.path(e.name)) else if (Kinds.viewable(e)) view(e.name) else {
			var local = files.localPath(browser.path(e.name));
			if (local != null && openDefault != null) openDefault(local);
		}
		return true;
	}

	// a link of the Markdown document at from followed (its anchors are the
	// page's): a file the viewer shows opened full size in its folder (its
	// files stepped through; "other.md#usage" at that heading), a folder
	// browsed, another file the system's app's, a web or mail address the
	// browser's; false: nothing there
	public function follow(from:String, href:String):Bool {
		var h = StringTools.trim(href);
		if (h == "" || h.startsWith("#")) return false;
		var scheme = schemeOf(h);
		if (scheme != null) {
			return (scheme == "http" || scheme == "https" || scheme == "mailto") && openUrl(h);
		}
		var hash = h.indexOf("#"), anchor = hash >= 0 ? h.substr(hash + 1) : null;
		var part = hash >= 0 ? h.substr(0, hash) : h;
		if (part.indexOf("?") >= 0) part = part.substr(0, part.indexOf("?"));
		var target = resolve(Browser.parent(from) ?? "", try StringTools.urlDecode(part) catch (_:Dynamic) part);
		var e = files.stat(target);
		if (e == null) return false;
		if (e.kind == Folder) {
			close();
			browser.go(target);
			return true;
		}
		if (!Kinds.viewable(e)) {
			var local = files.localPath(target);
			if (local == null || openDefault == null) return false;
			openDefault(local);
			return true;
		}
		var dir = Browser.parent(target) ?? target, name = Browser.name(target);
		viewer.anchor = anchor;
		browser.go(dir, name);
		view(name);
		return true;
	}

	// a path relative to a folder ("../a/b.md"), or absolute ("/x")
	public static function resolve(dir:String, rel:String):String {
		if (rel.startsWith("/") || (rel.length > 2 && rel.charAt(1) == ":" && (rel.charAt(2) == "/" || rel.charAt(2) == "\\"))) return Browser.normalize(rel);
		var at = dir;
		for (seg in rel.replace("\\", "/").split("/"))
			switch seg {
				case "" | ".":
				case "..": at = Browser.parent(at) ?? at;
				case s: at = FolderModel.join(at, s);
			}
		return Browser.normalize(at);
	}

	// (a URL's scheme, lower case: "https"; null: a path. One letter is a Windows drive)
	static function schemeOf(h:String):Null<String> {
		var colon = h.indexOf(":");
		if (colon < 2) return null;
		for (i in 0...colon) {
			var c = h.charCodeAt(i);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (i > 0 && ((c >= "0".code && c <= "9".code) || c == "+".code || c == ".".code || c == "-".code));
			if (!ok) return null;
		}
		return h.substr(0, colon).toLowerCase();
	}

	// (a Markdown document's preview: the inspector shows its first screen, its words and headings)
	function markdownPreview(path:String, done:Preview.Shown->Void):Void->Void {
		var stopped = false;
		read(path, text -> if (!stopped) done({
			image: null,
			width: 0,
			height: 0,
			pages: 0,
			duration: 0,
			format: "Markdown",
			error: text == null ? "The file cannot be read" : null,
			markdown: text == null ? null : new MarkdownDoc(path, text)
		}));
		return () -> stopped = true;
	}

	// (a file's bytes through files, on the loop, as text)
	static function readAll(files:Files, path:String, done:Null<String>->Void)
		helder.async.Async.launch(_ -> {
			var s = files.open(path), out = new haxe.io.BytesBuffer(), chunk = haxe.io.Bytes.alloc(65536), at = 0.0, n = 0;
			try {
				while ((n = s.read(at, chunk, 0, chunk.length)) > 0) {
					out.addBytes(chunk, 0, n);
					at += n;
				}
			} catch (e:Dynamic) {
				s.close();
				throw e;
			}
			s.close();
			out.getBytes().toString();
		}).onCompletion((r, _) -> done(r));

	// (pictures' sizes as their headers say, Image.size, read through files
	// on the loop: one task each, a failed one null)
	static function measureAll(files:Files, paths:Array<String>, done:Array<Null<{width:Int, height:Int}>>->Void) {
		var sizes:Array<Null<{width:Int, height:Int}>> = [for (_ in paths) null], left = paths.length;
		if (left == 0) return done(sizes);
		for (i => p in paths)
			helder.async.Async.launch(_ -> header(files, p)).onCompletion((s, _) -> {
				sizes[i] = s;
				if (--left == 0) done(sizes);
			});
	}

	// (a file's first 64 KB; a JPEG's frame header past larger metadata,
	// EXIF's thumbnail or an ICC profile: its first MB)
	@:coroutine static function header(files:Files, path:String):Null<{width:Int, height:Int}> {
		var s = files.open(path), size:Null<{width:Int, height:Int}> = null;
		try {
			for (n in [65536, 1 << 20]) {
				var b = haxe.io.Bytes.alloc(n), got = s.read(0, b, 0, n);
				size = helder.image.Image.size(b, 0, got);
				if (size != null || got < n) break;
			}
		} catch (e:Dynamic) {
			s.close();
			throw e;
		}
		s.close();
		return size;
	}

	// a file of the folder full size, the viewer's list the browser's viewable files
	// (from the browser: zoomed from its tile; a link followed in place)
	public function view(name:String) {
		var names = browser.viewable(), was = full.value;
		Timing.opening(browser.path(name));
		viewer.view(browser.dir.value, names, name);
		full(true);
		if (!was) zoom.open(browser.path(name));
	}

	// back to the browser, the file viewed last selected
	public function close() {
		if (!full.value) return;
		var last = viewer.folder.name, path = viewer.folder.current;
		full(false);
		viewer.fullscreen(false);
		viewer.close();
		if (last != "") browser.select(last);
		if (focusList != null) focusList();
		zoom.close(path ?? "");
	}

	// what a path or menu action acts on: the file shown full size, else the selection
	public function target():Null<String> {
		if (full.value) return viewer.folder.current;
		var e = browser.current();
		return e == null ? null : browser.path(e.name);
	}

	public function trash():Int {
		if (full.value) {
			var name = viewer.folder.name;
			if (name == "") return 0;
			var n = browser.trash([name]);
			if (n > 0 && viewer.folder.files.length == 0) close();
			return n;
		}
		return browser.trash(browser.picked());
	}

	// --- a sidebar's folders: renamed, trashed (the folder shown, if it is
	// that one or inside it, followed)

	public function renameFolder(path:String, to:String):Null<String> {
		sidebar.renaming("");
		to = StringTools.trim(to);
		var move = files.rename, up = Browser.parent(path);
		if (to == "" || up == null || to == Browser.name(path) || move == null) return null;
		if (to.indexOf("/") >= 0 || to.indexOf("\\") >= 0) return browser.fail('"$to" is not a name a folder can have');
		var now = FolderModel.join(up, to);
		if (files.stat(now) != null) return browser.fail('"$to" is already there');
		try move(path, now) catch (e:Dynamic) return browser.fail('"${Browser.name(path)}" could not be renamed: $e');
		// (the row renamed in place; the folder shown followed only when it is that one or inside it)
		browser.record([{from: path, to: now}], true);
		browser.moved(path, now);
		var d = browser.dir.value;
		if (d == path || StringTools.startsWith(d, path + "/")) browser.go(now + d.substr(path.length));
		return null;
	}

	function trashFolder(path:String):Bool {
		var move = files.trash, to:Null<String> = null;
		if (move == null) return false;
		try to = move(path) catch (e:Dynamic) {
			browser.fail('"${Browser.name(path)}" could not be moved to the trash: $e');
			return false;
		}
		// (its row gone, the level kept; the folder shown left for its parent
		// only when it is that one or inside it)
		if (to != null) browser.record([{from: path, to: to}], true);
		browser.moved(path, null);
		var d = browser.dir.value, up = Browser.parent(path);
		if ((d == path || StringTools.startsWith(d, path + "/")) && up != null) browser.go(up);
		return true;
	}

	function revealPath(path:String):Bool {
		var local = files.localPath(path);
		if (local == null || reveal == null) return false;
		reveal(local);
		return true;
	}

	// --- actions (the keymap's and the menus'): true when taken

	public function perform(a:ViewerAction):Bool {
		switch a {
			case OpenRecent(path):
				start(path);
			case Back: browser.goBack();
			case Forward: browser.goForward();
			case Enclosing: browser.up();
			case Go(path): browser.go(path);
			case OpenSelected: return open();
			case ShowGrid: browser.layout(Grid);
			case ShowList: browser.layout(List);
			case SortBy(key): browser.sortBy(cast key);
			case Ascending:
				var o = browser.order.value;
				browser.setOrder({key: o.key, ascending: !o.ascending, foldersFirst: o.foldersFirst});
			case FoldersFirst:
				var o = browser.order.value;
				browser.setOrder({key: o.key, ascending: o.ascending, foldersFirst: !o.foldersFirst});
			case ShowHidden: browser.showHidden(!browser.hidden.value);
			case Search: browser.searching(true);
			case CloseSearch:
				if (!browser.searching.value && browser.query.value == "") return false;
				browser.closeSearch();
			case ToggleInspector: browser.inspector(!browser.inspector.value);
			case EditPath: editingPath(true);
			case Trash: return trash() > 0;
			case UndoTrash: return browser.undo();
			case Close: close();
			case NewFolder: return !full.value && browser.newFolder() != null;
			case Rename:
				var c = browser.current();
				if (full.value || c == null || files.rename == null) return false;
				browser.renaming(c.name);
			case GetInfo:
				browser.select("");
				browser.inspector(true);
			case RevealFolder: return revealPath(browser.dir.value);
			case RevealPath(path): return revealPath(path);
			case CopyPathOf(path):
				if (copy == null) return false;
				copy(files.localPath(path) ?? path);
			case RenameFolder(path):
				if (files.rename == null) return false;
				sidebar.renaming(path);
			case TrashFolder(path): return trashFolder(path);
			case CopyPath:
				var all = full.value ? [viewer.folder.current] : [for (n in browser.picked()) browser.path(n)];
				if (all.length == 0 || all[0] == null || copy == null) return false;
				copy([for (p in all) files.localPath(p) ?? p].join("\n"));
			case ShowInFolder:
				var t = target(), local = t == null ? null : files.localPath(t);
				if (local == null || reveal == null) return false;
				reveal(local);
			case OpenWithDefault:
				var t = target(), local = t == null ? null : files.localPath(t);
				if (local == null || openDefault == null) return false;
				openDefault(local);
			case _: return full.value || a == Open || a == CloseAbout ? viewer.perform(a) : false;
		}
		return true;
	}

	// what a menu shows it as
	public function actionState(a:ViewerAction):ActionState {
		var b = browser, o = b.order.value;
		inline function on(v:Bool)
			return v ? ActionState.Enabled : ActionState.Disabled;
		inline function check(v:Bool)
			return v ? ActionState.Checked : ActionState.Unchecked;
		return switch a {
			case Back: on(!full.value && b.canBack.value);
			case Forward: on(!full.value && b.canForward.value);
			case Enclosing: on(!full.value && Browser.parent(b.dir.value) != null);
			case OpenSelected: on(!full.value && b.current() != null);
			case ShowGrid: check(b.layout.value == Grid);
			case ShowList: check(b.layout.value == List);
			case SortBy(key): check(o.key == cast key);
			case Ascending: check(o.ascending);
			case FoldersFirst: check(o.foldersFirst);
			case ShowHidden: check(b.hidden.value);
			case ToggleInspector: check(b.inspector.value);
			case Trash: on(files.trash != null && target() != null);
			case UndoTrash: on(b.canUndo.value);
			case CopyPath | ShowInFolder | OpenWithDefault: on(target() != null);
			case NewFolder: on(!full.value && files.makeFolder != null);
			case Rename: on(!full.value && files.rename != null && b.current() != null);
			case RenameFolder(_): on(files.rename != null);
			case TrashFolder(_): on(files.trash != null);
			case RevealFolder | RevealPath(_): on(reveal != null);
			case CopyPathOf(_): on(copy != null);
			case Search | EditPath: on(!full.value);
			case Next | Previous | First | Last | ZoomIn | ZoomOut | Fit | ActualSize | NextPage | PreviousPage | FirstPage | LastPage | GoToPage | ScrollDown
				| ScrollUp | LineDown | LineUp | ToggleSource | PlayPause
				| StepForward | StepBack | ToggleMute | ToggleFullscreen | LeaveFullscreen | ToggleStatus | Close:
				full.value ? viewer.actionState(a) : Disabled;
			case _: Enabled;
		}
	}
}
