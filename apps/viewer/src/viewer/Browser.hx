package viewer;

import viewer.Files;
import viewer.Listing;

using StringTools;

enum abstract Layout(String) to String {
	var Grid = "grid";
	var List = "list";
}

// The browser without its window: the folder shown, its history, its
// entries as they are read (batches merged in, the selection kept by name),
// the order, the filter, what is selected, the trash and its undo. Every
// file it reads or changes goes through its Files.
class Browser {
	// (a folder with fewer entries is watched every WATCH_EVERY seconds; a larger one when refresh() is called)
	public static inline var WATCH_BELOW = 5000;
	public static inline var WATCH_EVERY = 2.0;

	public final files:Files;
	public final dir = new Cell("");
	// what is shown (filtered, sorted), how many entries were read, while reading
	public final items:Cell<Array<Entry>> = new Cell([]);
	public final total = new Cell(0);
	public final reading = new Cell(false);
	// why the folder cannot be read ("missing", "notfolder", "denied"; "" read)
	public final error = new Cell("");
	// the selection (by name: kept through sorts, batches and the watch) and
	// its focus, the entry the inspector and Open act on ("" none)
	public final selection:helder.ui.Selection;
	public final selected = new Cell("");
	public final layout = new Cell(Grid);
	public final order:Cell<Order> = new Cell(({key: Name, ascending: true, foldersFirst: true} : Order));
	public final hidden = new Cell(false);
	public final query = new Cell("");
	public final searching = new Cell(false);
	public final inspector = new Cell(true);
	public final canBack = new Cell(false);
	public final canForward = new Cell(false);
	public final canUndo = new Cell(false);
	// the folder changed (the sidebar follows it)
	public var onDir:Null<String->Void> = null;
	// the entries changed (the viewer's list follows them); files changed on disk named
	public var onItems:Null<Void->Void> = null;
	public var onModified:Null<Array<String>->Void> = null;

	var all:Array<Entry> = [];
	var stopList:Null<Void->Void> = null;
	var stopWatch:Null<Void->Void> = null;
	var keep = "";
	final back:Array<{dir:String, selected:String}> = [];
	final forward:Array<{dir:String, selected:String}> = [];
	final undone:Array<Array<{from:String, to:String}>> = [];

	public function new(files:Files) {
		this.files = files;
		// (an index of an older list, a view's not yet updated: no key)
		selection = new helder.ui.Selection(i -> {
			var e = items.value[i];
			e == null ? "" : e.name;
		}, () -> items.value.length);
	}

	// --- where it is

	public function go(path:String, ?select:String) {
		path = normalize(path);
		if (path == dir.value) {
			if (select != null) this.select(select);
			return;
		}
		if (dir.value != "") back.push({dir: dir.value, selected: selected.value});
		forward.resize(0);
		load(path, select ?? "");
	}

	public function goBack():Bool {
		var to = back.pop();
		if (to == null) return false;
		forward.push({dir: dir.value, selected: selected.value});
		load(to.dir, to.selected);
		return true;
	}

	public function goForward():Bool {
		var to = forward.pop();
		if (to == null) return false;
		back.push({dir: dir.value, selected: selected.value});
		load(to.dir, to.selected);
		return true;
	}

	// the enclosing folder, the one left selected
	public function up():Bool {
		var d = dir.value, p = parent(d);
		if (p == null) return false;
		go(p, name(d));
		return true;
	}

	// the folder read again (a large one's watch: the window's focus)
	public function refresh() {
		var d = dir.value;
		if (d == "") return;
		var got:Array<Entry> = [];
		files.list(d, b -> {
			if (dir.value != d || b.error != null) return;
			got = got.concat(b.entries);
			if (b.done) rescan(got);
		});
	}

	// the folder read again from the start (Try again)
	public function reload()
		if (dir.value != "") load(dir.value, selected.value);

	function load(path:String, select:String) {
		stop();
		dir(path);
		all = [];
		keep = select;
		items([]);
		selection.clear();
		total(0);
		error("");
		selected(select);
		query("");
		searching(false);
		reading(true);
		canBack(back.length > 0);
		canForward(forward.length > 0);
		if (onDir != null) onDir(path);
		stopList = files.list(path, b -> if (dir.value == path) batch(b));
	}

	function stop() {
		if (stopList != null) stopList();
		if (stopWatch != null) stopWatch();
		stopList = stopWatch = null;
	}

	// (a batch merged in, the selection held: the name asked for once it arrives)
	function batch(b:Batch) {
		if (b.error != null) error(b.error);
		all = all.concat(b.entries);
		total(all.length);
		items(Listing.merge(items.value, b.entries, order.value, hidden.value, query.value));
		if (keep != "" && entry(keep) != null) {
			select(keep);
			keep = "";
		}
		if (b.done) {
			reading(false);
			keep = "";
		}
		if (onItems != null) onItems();
		if (b.done) {
			stopList = null;
			if (b.error == null && all.length < WATCH_BELOW) stopWatch = files.watch(dir.value, WATCH_EVERY, rescan);
		}
	}

	// the folder as it is now (the watch's): added, removed and changed
	// entries, the selection kept by name (gone: the one now in its place)
	public function rescan(entries:Array<Entry>) {
		var before = new Map<String, Entry>();
		for (e in all)
			before.set(e.name, e);
		var modified = [];
		for (e in entries) {
			var b = before.get(e.name);
			if (b != null && (b.size != e.size || b.modified != e.modified)) modified.push(path(e.name));
		}
		var at = indexOf(selected.value);
		all = entries;
		total(all.length);
		reshow();
		selection.prune();
		if (selected.value != "" && entry(selected.value) == null) {
			var shown = items.value;
			select(shown.length == 0 ? "" : shown[Std.int(Math.min(Math.max(at, 0), shown.length - 1))].name);
		}
		if (modified.length > 0 && onModified != null) onModified(modified);
		if (onItems != null) onItems();
	}

	// --- how it is shown

	public function setOrder(o:Order) {
		order(o);
		reshow();
	}

	public function sortBy(key:SortKey) {
		var o = order.value;
		// (the column chosen again: the other way)
		setOrder({key: key, ascending: o.key == key ? !o.ascending : true, foldersFirst: o.foldersFirst});
	}

	public function showHidden(on:Bool) {
		hidden(on);
		reshow();
	}

	public function search(q:String) {
		query(q);
		reshow();
		var shown = items.value;
		selection.prune();
		if (shown.length > 0 && indexOf(selected.value) < 0) select(shown[0].name);
	}

	public function closeSearch() {
		searching(false);
		if (query.value != "") search("");
	}

	function reshow() {
		items(Listing.of(all, order.value, hidden.value, query.value));
		if (onItems != null) onItems();
	}

	// --- the selection

	public function select(name:String) {
		selected(name);
		var i = indexOf(name);
		if (i >= 0) selection.select(i) else selection.clear();
	}

	// the selection changed by the list's or the grid's own input: its focus the selected
	public function selectionChanged() {
		var f = selection.focus;
		var name = f != null && selection.has(f) ? f : selection.size() > 0 ? selection.keys()[0] : "";
		selected(name);
	}

	// what is selected, in the order shown (none: the focus alone, if any)
	public function picked():Array<String> {
		if (selection.size() > 0) return selection.keys();
		return selected.value != "" && indexOf(selected.value) >= 0 ? [selected.value] : [];
	}

	public function entry(name:String):Null<Entry> {
		for (e in items.value)
			if (e.name == name) return e;
		return null;
	}

	public function indexOf(name:String):Int {
		var shown = items.value;
		for (i in 0...shown.length)
			if (shown[i].name == name) return i;
		return -1;
	}

	public function current():Null<Entry>
		return entry(selected.value);

	public function path(name:String):String
		return FolderModel.join(dir.value, name);

	// the viewer's list: what it opens, in the order shown
	public function viewable():Array<String>
		return [for (e in items.value) if (Kinds.viewable(e)) e.name];

	// --- the trash

	// the names to the trash: how many went; Undo puts back those whose new place is known
	public function trash(names:Array<String>):Int {
		var move = files.trash;
		if (move == null) return 0;
		var gone = new Map<String, Bool>(), group = [];
		for (name in names) {
			var from = path(name), to:Null<String> = null;
			try {
				to = move(from);
			} catch (_:Dynamic) {
				continue;
			}
			gone.set(name, true);
			if (to != null) group.push({from: from, to: to});
		}
		var n = Lambda.count(gone);
		if (n == 0) return 0;
		if (group.length > 0) undone.push(group);
		rescan([for (e in all) if (!gone.exists(e.name)) e]);
		canUndo(undone.length > 0 && files.rename != null);
		return n;
	}

	// the last trashed put back where they were, selected
	public function undo():Bool {
		var group = undone.pop(), rename = files.rename;
		canUndo(undone.length > 0 && rename != null);
		if (group == null || rename == null) return false;
		var back = [for (u in group) if (try {
			rename(u.to, u.from);
			true;
		} catch (_:Dynamic) false) u.from];
		if (back.length == 0) return false;
		var d = parent(back[0]);
		if (d == dir.value) {
			var names = [for (p in back) name(p) => true];
			var put = [for (p in back) files.stat(p)].filter(e -> e != null);
			rescan([for (x in all) if (!names.exists(x.name)) x].concat(put));
			select(name(back[0]));
			if (back.length > 1) selection.setKeys([for (p in back) name(p)]);
		} else if (d != null) go(d, name(back[0]));
		return true;
	}

	// --- paths

	public static function parent(path:String):Null<String> {
		path = normalize(path);
		var slash = Std.int(Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\")));
		if (slash < 0 || path == "/" || isDrive(path)) return null;
		var p = path.substr(0, slash);
		return p == "" ? "/" : isDrive(p + "\\") && p.length == 2 ? p + "\\" : p;
	}

	public static function name(path:String):String {
		path = normalize(path);
		var slash = Std.int(Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\")));
		return slash < 0 || path == "/" || isDrive(path) ? path : path.substr(slash + 1);
	}

	// the folders from the top down to path ("/", "/Users", "/Users/ben")
	public static function ancestry(path:String):Array<String> {
		var out = [];
		var p:Null<String> = normalize(path);
		while (p != null) {
			out.unshift(p);
			p = parent(p);
		}
		return out;
	}

	public static function normalize(p:String):String {
		while (p.length > 1 && (p.endsWith("/") || p.endsWith("\\")) && !isDrive(p))
			p = p.substr(0, p.length - 1);
		return isDrive(p + "\\") && p.length == 2 ? p + "\\" : p;
	}

	// (Windows' "C:\")
	static function isDrive(p:String):Bool
		return p.length == 3 && p.charAt(1) == ":" && (p.charAt(2) == "\\" || p.charAt(2) == "/");
}
