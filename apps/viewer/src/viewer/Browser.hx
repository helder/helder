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
	// where the view goes when a folder is shown: its top (0), the place it
	// had in the history (back, forward, read again), or the entry asked to
	// be selected in view (-1: up's folder left); scrolled, the view's
	// scroll now (the list's or the grid's), kept with the history
	public var offset(default, null) = 0.0;
	public var scrolled:Void->Float = () -> 0;
	// items are still the last folder's: kept until this one's first batch
	// comes, never emptied nor dimmed meanwhile (either, for a moment, reads
	// as a flash), waiting after STALE seconds (the view takes no presses on
	// them); a folder seen lately shows its entries as they were at once
	// (back, forward), replaced whole when it is read again
	public var stale(default, null) = false;
	public final waiting = new Cell(false);
	public static inline var STALE = 0.15;
	// (folders seen lately, their entries as last read: the newest last)
	static inline var SEEN = 32;
	final seen = new Map<String, Array<Entry>>();
	final seenOrder:Array<String> = [];
	var fromSeen = false;
	var loads = 0;
	// the folder changed (the sidebar follows it)
	public var onDir:Null<String->Void> = null;
	// the entries changed (the viewer's list follows them); files changed on disk named
	public var onItems:Null<Void->Void> = null;
	public var onModified:Null<Array<String>->Void> = null;
	// an entry moved (renamed, trashed, put back, moved into a folder: to
	// null when gone; from null when new), so that the sidebar's rows follow
	public var onMoved:Null<(from:Null<String>, to:Null<String>)->Void> = null;

	var all:Array<Entry> = [];
	var stopList:Null<Void->Void> = null;
	var stopWatch:Null<Void->Void> = null;
	var keep = "";
	final back:Array<Place> = [];
	final forward:Array<Place> = [];
	// (the undo's groups; stay: put back without going to their folder, the sidebar's)
	final undone:Array<{moves:Array<{from:String, to:String}>, stay:Bool}> = [];

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
		if (dir.value != "") back.push(here());
		forward.resize(0);
		load(path, select ?? "", select == null || select == "" ? 0 : -1);
	}

	public function goBack():Bool {
		var to = back.pop();
		if (to == null) return false;
		forward.push(here());
		load(to.dir, to.selected, to.scroll);
		return true;
	}

	public function goForward():Bool {
		var to = forward.pop();
		if (to == null) return false;
		back.push(here());
		load(to.dir, to.selected, to.scroll);
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
		if (dir.value != "") load(dir.value, selected.value, scrolled());

	function here():Place
		return {dir: dir.value, selected: selected.value, scroll: scrolled()};

	function load(path:String, select:String, at:Float) {
		Timing.going(path);
		stop();
		offset = at;
		dir(path);
		all = [];
		keep = select;
		var load = ++loads, was = seen.get(path);
		fromSeen = was != null;
		waiting(false);
		if (was != null) {
			// (as it was when last read: at once, read again under it)
			stale = false;
			items(Listing.of(was, order.value, hidden.value, ""));
		} else {
			stale = items.value.length > 0;
			if (!stale) items([]) else helder.async.Async.launch(_ -> {
				helder.async.Async.delay(STALE);
				if (stale && loads == load) waiting(true);
			});
		}
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
		// (shown as it was when last read: kept until it is read whole, then replaced in one frame)
		if (fromSeen && !b.done && b.error == null) return;
		// (the last folder's entries, kept until now, replaced whole: in one frame)
		var was = stale || fromSeen ? [] : items.value;
		if (fromSeen) b = {entries: all, done: true, error: b.error};
		fromSeen = false;
		stale = false;
		waiting(false);
		var t0 = Timing.on ? haxe.Timer.stamp() : 0.0;
		var merged = Listing.merge(was, b.entries, order.value, hidden.value, query.value);
		if (Timing.on) Timing.mark('batch ${b.entries.length}${b.done ? " done" : ""} merged in ${Math.round((haxe.Timer.stamp() - t0) * 10000) / 10} ms');
		items(merged);
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
			if (b.error == null) remember(dir.value, all);
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
		remember(dir.value, all);
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

	// (a folder's entries as read: kept for its next visit, a small one's, the last SEEN folders')
	function remember(path:String, entries:Array<Entry>) {
		seenOrder.remove(path);
		if (entries.length >= WATCH_BELOW) {
			seen.remove(path);
			return;
		}
		seen.set(path, entries.copy());
		seenOrder.push(path);
		while (seenOrder.length > SEEN)
			seen.remove(seenOrder.shift());
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
		var f = selection.focus, keys = selection.keys();
		// (those selected may all be filtered out: none then)
		var name = f != null && selection.has(f) ? f : keys.length > 0 ? keys[0] : "";
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
			told(from, to);
		}
		var n = Lambda.count(gone);
		if (n == 0) return 0;
		record(group);
		rescan([for (e in all) if (!gone.exists(e.name)) e]);
		return n;
	}

	// the last trashed, renamed or moved put back where they were, selected
	// (the sidebar's, stay: where they were, the folder shown not left)
	public function undo():Bool {
		var last = undone.pop(), rename = files.rename;
		canUndo(undone.length > 0 && rename != null);
		if (last == null || rename == null) return false;
		var group = [for (u in last.moves) if (try {
			rename(u.to, u.from);
			true;
		} catch (_:Dynamic) false) u];
		if (group.length == 0) return false;
		if (last.stay) {
			for (u in group)
				moved(u.to, u.from);
			return true;
		}
		for (u in group)
			told(u.to, u.from);
		var back = [for (u in group) u.from], d = parent(back[0]);
		if (d == dir.value) {
			// (a rename's or a move's new name in this folder goes too)
			var names = [for (p in back) name(p) => true];
			for (u in group)
				if (parent(u.to) == d) names.set(name(u.to), true);
			var put = [for (p in back) files.stat(p)].filter(e -> e != null);
			rescan([for (x in all) if (!names.exists(x.name)) x].concat(put));
			select(name(back[0]));
			if (back.length > 1) selection.setKeys([for (p in back) name(p)]);
		} else if (d != null) go(d, name(back[0]));
		return true;
	}

	// --- changes: a new folder, a name, files moved or copied into a folder

	// what went wrong, shown a moment ("" none), and the entry renamed in place ("" none)
	public final notice = new Cell("");
	public final renaming = new Cell("");

	// a new folder ("untitled folder", numbered when there is one), selected
	// and renamed in place: its name; null when none could be made (notice says why)
	public function newFolder():Null<String> {
		var make = files.makeFolder;
		if (make == null) {
			fail("Folders cannot be made here");
			return null;
		}
		var name = "untitled folder", k = 2;
		while (Lambda.exists(all, e -> e.name == name))
			name = 'untitled folder ${k++}';
		try make(path(name)) catch (e:Dynamic) {
			fail('The folder could not be made: $e');
			return null;
		}
		var made = files.stat(path(name)) ?? ({name: name, kind: Folder, size: 0, modified: Date.now().getTime() / 1000, created: 0} : Entry);
		told(null, path(name));
		rescan(all.concat([made]));
		select(name);
		renaming(name);
		return name;
	}

	// an entry named to: null when done (or nothing to do), else why not (in
	// notice too); undone by Undo, as a trash is
	public function rename(name:String, to:String):Null<String> {
		renaming("");
		to = StringTools.trim(to);
		if (to == "" || to == name) return null;
		if (to.indexOf("/") >= 0 || to.indexOf("\\") >= 0 || to == "." || to == "..") return fail('"$to" is not a name a file can have');
		var move = files.rename, was = Lambda.find(all, e -> e.name == name);
		if (move == null || was == null) return fail("Names cannot be changed here");
		if (Lambda.exists(all, e -> e.name == to)) return fail('"$to" is already in this folder');
		try move(path(name), path(to)) catch (e:Dynamic) return fail('"$name" could not be renamed: $e');
		record([{from: path(name), to: path(to)}]);
		told(path(name), path(to));
		var now = files.stat(path(to)) ?? ({name: to, kind: was.kind, size: was.size, modified: was.modified, created: was.created} : Entry);
		rescan([for (e in all) if (e.name != name) e].concat([now]));
		select(to);
		return null;
	}

	// files (paths) moved, or copied, into the folder into: how many; the
	// moves undone by Undo; what is already there, the folder itself or one
	// inside it left out
	public function transfer(paths:Array<String>, into:String, copying:Bool):Int {
		into = normalize(into);
		var act = copying ? files.copy : files.rename;
		if (act == null) {
			fail(copying ? "Files cannot be copied here" : "Files cannot be moved here");
			return 0;
		}
		var group = [], done = [], failed:Null<String> = null;
		for (p in paths) {
			p = normalize(p);
			var to = FolderModel.join(into, name(p));
			if (p == into || StringTools.startsWith(into, p + "/") || parent(p) == into) continue;
			try {
				act(p, to);
				done.push({from: p, to: to});
				if (!copying) group.push({from: p, to: to});
				told(copying ? null : p, to);
			} catch (e:Dynamic) {
				failed ??= '"${name(p)}" could not be ${copying ? "copied" : "moved"}: $e';
			}
		}
		if (failed != null) fail(failed);
		record(group);
		// (the folder shown, what left it and what came in)
		var d = dir.value, gone = [for (m in done) if (!copying && parent(m.from) == d) name(m.from) => true];
		var came = [for (m in done) if (parent(m.to) == d) files.stat(m.to)].filter(e -> e != null);
		if (Lambda.count(gone) > 0 || came.length > 0) rescan([for (e in all) if (!gone.exists(e.name)) e].concat(came));
		return done.length;
	}

	// an entry moved by others (the sidebar's rename and trash: to null when
	// gone), the folder shown and the sidebar told
	public function moved(from:Null<String>, to:Null<String>) {
		var d = dir.value, gone = from != null && parent(from) == d ? name(from) : null;
		var came = to != null && parent(to) == d ? files.stat(to) : null;
		if (gone != null || came != null) rescan([for (e in all) if (e.name != gone && (came == null || e.name != came.name)) e].concat(came == null ? [] : [came]));
		told(from, to);
	}

	// moves Undo puts back (stay: without going to their folder)
	public function record(moves:Array<{from:String, to:String}>, stay = false) {
		if (moves.length > 0) undone.push({moves: moves, stay: stay});
		canUndo(undone.length > 0 && files.rename != null);
	}

	inline function told(from:Null<String>, to:Null<String>)
		if (onMoved != null) onMoved(from, to);

	// (why something could not be done, in notice for a few seconds: null, to return)
	public function fail(why:String):Null<String> {
		notice(why);
		#if (target.name == "hxmc")
		helder.async.Async.launch(_ -> {
			helder.async.Async.delay(4);
			if (notice.value == why) notice("");
		});
		#end
		return why;
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

// (a folder of the history: what was selected, the view's scroll)
private typedef Place = {dir:String, selected:String, scroll:Float};
