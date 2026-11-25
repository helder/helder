package viewer;

import helder.os.Places;
import viewer.Files;

typedef Row = {name:String, path:String, deeper:Bool};

// The sidebar, one level at a time: the overview (the user's places and
// the volumes), or a folder's level (its subfolders, a back row to its
// parent, the current folder highlighted among them). The level follows
// the folder shown: its parent, so the folder is among its siblings (a
// volume's top: the volume itself); a place chosen shows its own level;
// "›" goes a level deeper without moving the folder shown.
class Sidebar {
	// (a cell: the web's grow by the folders opened)
	public final places:Cell<Array<Place>>;
	public final volumes:Array<Volume>;
	// the level ("" the overview), its subfolders as they are read
	public final level = new Cell("");
	public final rows:Cell<Array<Row>> = new Cell([]);

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

	public function show(path:String) {
		path = path == "" ? "" : Browser.normalize(path);
		if (path == level.value) return;
		for (s in stops)
			s();
		stops = [];
		level(path);
		rows([]);
		if (path == "") return;
		var got:Array<Row> = [];
		stops.push(files.list(path, b -> {
			if (level.value != path) return;
			for (e in b.entries)
				if (e.kind == Folder && !Kinds.hidden(e.name)) got.push({name: e.name, path: FolderModel.join(path, e.name), deeper: false});
			if (!b.done) return;
			got.sort((a, b) -> FolderModel.compare(a.name, b.name));
			rows(got);
			for (r in got)
				deeper(path, r);
		}));
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

	// the back row: the level above (a volume's top: the overview)
	public function back() {
		var l = level.value;
		show(l == "" || isVolume(l) ? "" : Browser.parent(l) ?? "");
	}

	public function backLabel():String {
		var l = level.value;
		if (l == "" || isVolume(l)) return "Overview";
		var p = Browser.parent(l);
		return p == null ? "Overview" : title(p);
	}

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
