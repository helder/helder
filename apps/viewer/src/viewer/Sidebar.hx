package viewer;

import helder.os.Places;
import viewer.Files;

typedef Row = {name:String, path:String, deeper:Bool};

// The sidebar, one level at a time: the overview (the user's places and
// the volumes), or a folder's level (its subfolders, a back row to its
// parent, the current folder highlighted among them). The level follows
// the folder shown: its parent, so the folder is among its siblings (a
// volume's top: the volume itself); a place chosen shows its own level;
// "›" (or a row's double click) goes a level deeper without moving the
// folder shown. Back retraces the way in (the levels gone through, from
// the overview by a place or a device chosen, or from a level); where the
// folder shown moves the level, the way is kept along it (up it, or deeper
// in by the parents between), else let go: back then goes to the real
// parent (a volume's top: the overview).
class Sidebar {
	// (a cell: the web's grow by the folders opened)
	public final places:Cell<Array<Place>>;
	public final volumes:Array<Volume>;
	// the level ("" the overview), its subfolders as they are read
	public final level = new Cell("");
	public final rows:Cell<Array<Row>> = new Cell([]);
	// the levels above the level on the way in, the last where back goes
	// ("" the overview; none: the real parent)
	public final way:Cell<Array<String>> = new Cell([]);
	// (the way of the level going to)
	var going:Array<String> = [];

	final files:Files;
	var stops:Array<Void->Void> = [];

	public function new(files:Files, places:Array<Place>, volumes:Array<Volume>) {
		this.files = files;
		this.places = new Cell(places);
		this.volumes = volumes;
	}

	// a place of its own (the web's: a folder opened, by its name)
	public function add(p:Place)
		places(places.value.concat([p]));

	// the level for a folder shown: its parent; a volume's top, itself
	public function levelFor(dir:String):String {
		var p = Browser.parent(dir);
		return p == null || isVolume(dir) ? dir : p;
	}

	public function follow(dir:String)
		show(levelFor(dir));

	// a place or a device chosen: its own level, back from it the overview
	public function choose(path:String)
		show(path, [""]);

	// the level shown (the one going to: target; the last one's rows kept
	// until its are read, or SLOW seconds pass, then both in one
	// write, so that going between levels never shows an empty one); the
	// way to it through (else retraced)
	public function show(path:String, ?through:Array<String>) {
		path = path == "" ? "" : Browser.normalize(path);
		var w = through ?? retrace(path);
		if (path == target) {
			going = w;
			if (level.value == path) way(w);
			return;
		}
		for (s in stops)
			s();
		stops = [];
		target = path;
		going = w;
		if (path == "") {
			level(path);
			rows([]);
			way(w);
			return;
		}
		var got:Array<Row> = [], shown = false;
		function land(r:Array<Row>) {
			shown = true;
			level(path);
			rows(r);
			way(going);
		}
		stops.push(files.list(path, b -> {
			if (target != path) return;
			for (e in b.entries)
				if (e.kind == Folder && !Kinds.hidden(e.name)) got.push({name: e.name, path: FolderModel.join(path, e.name), deeper: false});
			if (!b.done) return;
			got.sort((a, b) -> FolderModel.compare(a.name, b.name));
			land(got);
			for (r in got)
				deeper(path, r);
		}));
		// (a level not read in SLOW seconds: shown empty, its rows as they come; a
		// shorter wait pushed an empty level in, its rows popping in after)
		if (!shown && target == path) helder.async.Async.launch(_ -> {
			helder.async.Async.delay(SLOW);
			if (!shown && target == path) land([]);
		});
	}

	var target = "";
	static inline var SLOW = 1.0;

	// the folder renamed in place (its path; "" none)
	public final renaming = new Cell("");

	// a folder moved (renamed, trashed, put back, made: from null when new,
	// to null when gone): its row in the level shown, in place, the level
	// and its scroll kept (no listing again)
	public function moved(from:Null<String>, to:Null<String>) {
		var l = level.value;
		if (l == "" || target != l) return;
		if (from != null) from = Browser.normalize(from);
		var was = from == null ? null : Lambda.find(rows.value, r -> r.path == from);
		var e = to == null || Browser.parent(to) != l ? null : files.stat(to);
		var come = e != null && e.kind == Folder && !Kinds.hidden(e.name);
		if (was == null && !come) return;
		var r = [for (r in rows.value) if (r.path != from) r];
		if (come) {
			var path = FolderModel.join(l, e.name);
			if (!Lambda.exists(r, q -> q.path == path)) r.push({name: e.name, path: path, deeper: was?.deeper ?? false});
			r.sort((a, b) -> FolderModel.compare(a.name, b.name));
		}
		rows(r);
	}

	// (whether a row has subfolders of its own, for its "›": its listing stopped at the first)
	function deeper(at:String, row:Row) {
		var stop:Null<Void->Void> = null, found = false;
		stop = files.list(row.path, b -> {
			if (found || level.value != at) return;
			for (e in b.entries)
				if (e.kind == Folder && !Kinds.hidden(e.name)) found = true;
			if (!found) return;
			rows([for (r in rows.value) r.path == row.path ? {name: r.name, path: r.path, deeper: true} : r]);
			if (stop != null) stop();
		});
		stops.push(stop);
	}

	// the back row: the way in's last level, else the level above (a volume's top: the overview)
	public function back()
		show(backOf(level.value, way.value));

	// the back row's label (tracked: the level, its way; read as the model has them)
	public function backLabel():String {
		level();
		way();
		var to = backOf(level.value, way.value);
		return to == "" ? "Overview" : title(to);
	}

	function backOf(l:String, w:Array<String>):String
		return w.length > 0 ? w[w.length - 1] : l == "" || isVolume(l) ? "" : Browser.parent(l) ?? "";

	// (the way to level l from the way to the level going to: back along it
	// to one of its levels, deeper inside the deepest it is inside by the
	// parents between, else none)
	function retrace(l:String):Array<String> {
		if (l == "") return [];
		var p = going.concat([target]), i = p.length;
		while (--i >= 0)
			if (p[i] != "" && inside(l, p[i])) break;
		if (i < 0) return [];
		if (p[i] == l) return p.slice(0, i);
		var between = [], q = Browser.parent(l);
		while (q != null && q != p[i]) {
			between.unshift(q);
			q = Browser.parent(q);
		}
		return p.slice(0, i + 1).concat(between);
	}

	// (path the folder dir or inside it)
	static function inside(path:String, dir:String):Bool
		return path == dir || StringTools.startsWith(path, StringTools.endsWith(dir, "/") || StringTools.endsWith(dir, "\\") ? dir : dir + "/")
			|| StringTools.startsWith(path, dir + "\\");

	// a folder's name as the sidebar says it: a place's, a volume's, else its own
	public function title(path:String):String {
		for (p in places.value)
			if (Browser.normalize(p.path) == path) return p.name;
		for (v in volumes)
			if (Browser.normalize(v.path) == path) return v.name;
		return Browser.name(path);
	}

	public function isVolume(path:String):Bool {
		for (v in volumes)
			if (Browser.normalize(v.path) == path) return true;
		return Browser.parent(path) == null;
	}

	// the volume a path is on (the longest of their paths it starts with)
	public function volumeOf(path:String):Null<Volume> {
		var best:Null<Volume> = null, at = -1;
		for (v in volumes) {
			var p = Browser.normalize(v.path);
			if ((path == p || StringTools.startsWith(path, p == "/" ? "/" : p + "/") || StringTools.startsWith(path, p + "\\") || (StringTools.endsWith(p, "\\") && StringTools.startsWith(path, p))) && p.length > at) {
				best = v;
				at = p.length;
			}
		}
		return best;
	}

	// the place a path is a place's, or inside (Pictures for Pictures/Trips)
	public function placeOf(path:String):Null<Place> {
		var best:Null<Place> = null, at = -1;
		for (p in places.value) {
			var pp = Browser.normalize(p.path);
			if ((path == pp || StringTools.startsWith(path, pp + "/") || StringTools.startsWith(path, pp + "\\")) && pp.length > at) {
				best = p;
				at = pp.length;
			}
		}
		return best;
	}
}
