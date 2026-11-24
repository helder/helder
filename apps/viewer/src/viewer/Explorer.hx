package viewer;

import helder.os.Places;
import viewer.Decode.Decoded;
import viewer.Files;
import viewer.Listing;
import helder.ui.actions.Actions.ActionState;
import viewer.ViewerActions;

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
	// the path bar being edited (Mod+L)
	public final editingPath = helder.view.graph.Graph.signal(false);
	// the shell's: the system's file manager at a file, the default app, the clipboard
	public var reveal:Null<String->Void> = null;
	public var openDefault:Null<String->Void> = null;
	public var copy:Null<String->Void> = null;
	// the web's: a folder of the user's picked and shown (none: no button for it)
	public var openFolder:Null<Void->Void> = null;
	// the thumbnails' queue (the shell's; none: glyphs alone)
	public var thumbnails:Null<Thumbnails> = null;
	// the list's focus on its selection (the shell's, once the list is made)
	public var focusList:Null<Void->Void> = null;
	// the inspector's preview of a file (Preview.request; tests: Preview.now)
	public final preview:(path:String, done:Preview.Shown->Void)->(Void->Void);

	var choosing = false;

	public function new(files:Files, decode:(path:String, side:Int, done:Decoded->Void) -> Void, ?places:Array<Place>, ?volumes:Array<Volume>,
			?preview:(path:String, done:Preview.Shown->Void)->(Void->Void), ?pdfSizes:(path:String, done:PdfPages.PdfSizes->Void)->Void) {
		this.files = files;
		this.preview = preview ?? #if (hxmc.target == "wasm32-wasi") (_, _) -> () -> {} #else Preview.request #end;
		browser = new Browser(files);
		sidebar = new Sidebar(files, places ?? [], volumes ?? []);
		viewer = new Viewer(decode, null, pdfSizes);
		browser.onDir = d -> {
			if (!choosing) sidebar.follow(d);
			// (another folder: the decodes of the last let go)
			if (!full.value) viewer.release();
		};
		browser.onItems = () -> if (full.value) viewer.relist(browser.viewable());
		browser.onModified = paths -> viewer.modified(paths);
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
		var e = browser.entry(name ?? browser.selected.value);
		if (e == null) return false;
		browser.select(e.name);
		if (e.kind == Folder) browser.go(browser.path(e.name)) else if (Kinds.viewable(e)) view(e.name) else {
			var local = files.localPath(browser.path(e.name));
			if (local != null && openDefault != null) openDefault(local);
		}
		return true;
	}

	// a file of the folder full size, the viewer's list the browser's viewable files
	public function view(name:String) {
		var names = browser.viewable();
		viewer.view(browser.dir.value, names, name);
		full(true);
	}

	// back to the browser, the file viewed last selected
	public function close() {
		if (!full.value) return;
		var last = viewer.folder.name;
		full(false);
		viewer.fullscreen(false);
		viewer.close();
		if (last != "") browser.select(last);
		if (focusList != null) focusList();
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
			case Search | EditPath: on(!full.value);
			case Next | Previous | First | Last | ZoomIn | ZoomOut | Fit | ActualSize | NextPage | PreviousPage | FirstPage | LastPage | GoToPage | ScrollDown
				| ScrollUp | LineDown | LineUp | PlayPause
				| StepForward | StepBack | ToggleMute | ToggleFullscreen | LeaveFullscreen | ToggleStatus | Close:
				full.value ? viewer.actionState(a) : Disabled;
			case _: Enabled;
		}
	}
}
