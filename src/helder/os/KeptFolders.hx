package helder.os;

// The grants Folders keeps on iOS and Android: in the store
// "helder-folders", each id's name and data (a bookmark's, in base64; a
// tree's URI), "ids" their order. An id is of what the grant is of (the
// folder's path, its tree's URI): the same folder picked again is the same.
class KeptFolders {
	static var store:Null<Store> = null;

	public static function all():Array<{id:String, name:String, data:String}> {
		var s = open();
		return [
			for (id in ids(s)) {
				var v = s.get("grant." + id), at = v == null ? -1 : v.indexOf("\n");
				if (at >= 0) {id: id, name: v.substr(0, at), data: v.substr(at + 1)};
			}
		];
	}

	public static function get(id:String):Null<{id:String, name:String, data:String}> {
		for (g in all())
			if (g.id == id) return g;
		return null;
	}

	// kept (again: its data replaced, its place the same): its id
	public static function keep(of:String, name:String, data:String):String {
		var s = open(), id = haxe.crypto.Md5.encode(of).substr(0, 12), all = ids(s);
		s.set("grant." + id, name + "\n" + data);
		if (!all.contains(id)) s.set("ids", all.concat([id]).join("\n"));
		return id;
	}

	// (its data made again: a stale bookmark's)
	public static function update(id:String, data:String) {
		var g = get(id);
		if (g != null) open().set("grant." + id, g.name + "\n" + data);
	}

	public static function remove(id:String) {
		var s = open();
		s.remove("grant." + id);
		s.set("ids", [for (i in ids(s)) if (i != id) i].join("\n"));
	}

	static function ids(s:Store):Array<String>
		return [for (i in (s.get("ids") ?? "").split("\n")) if (i != "") i];

	static function open():Store
		return store ??= Store.open("helder-folders");
}
