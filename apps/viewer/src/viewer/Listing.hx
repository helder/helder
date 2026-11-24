package viewer;

import viewer.Files;

enum abstract SortKey(String) to String {
	var Name = "name";
	var Kind = "kind";
	var Modified = "modified";
	var Size = "size";
}

typedef Order = {key:SortKey, ascending:Bool, foldersFirst:Bool};

// A folder's entries as the browser shows them: hidden ones left out
// unless asked for, filtered by a name's part, folders first, sorted by
// name (natural order: FolderModel.compare), kind, date or size, either
// way; batches merged into what is shown as they arrive, each sorted on
// its own (no sort of the whole for each one).
class Listing {
	public static function compare(order:Order):(Entry, Entry)->Int {
		var dir = order.ascending ? 1 : -1;
		function by(a:Entry, b:Entry):Int {
			var c = switch order.key {
				case Kind: Reflect.compare(Kinds.kind(a), Kinds.kind(b));
				case Modified: Reflect.compare(a.modified, b.modified);
				case Size: Reflect.compare(a.size, b.size);
				case Name: 0;
			}
			return c != 0 ? c : FolderModel.compare(a.name, b.name);
		}
		return (a, b) -> {
			if (order.foldersFirst && (a.kind == Folder) != (b.kind == Folder)) return a.kind == Folder ? -1 : 1;
			return dir * by(a, b);
		};
	}

	public static function shows(e:Entry, hidden:Bool, query:String):Bool
		return (hidden || !Kinds.hidden(e.name)) && (query == "" || e.name.toLowerCase().indexOf(query.toLowerCase()) >= 0);

	// entries filtered and sorted
	public static function of(entries:Array<Entry>, order:Order, hidden:Bool, query:String):Array<Entry> {
		var out = [for (e in entries) if (shows(e, hidden, query)) e];
		out.sort(compare(order));
		return out;
	}

	// sorted, with a batch's merged in (a new array)
	public static function merge(sorted:Array<Entry>, batch:Array<Entry>, order:Order, hidden:Bool, query:String):Array<Entry> {
		var add = of(batch, order, hidden, query);
		if (add.length == 0) return sorted;
		var cmp = compare(order), out = [], i = 0, j = 0;
		while (i < sorted.length && j < add.length)
			out.push(cmp(sorted[i], add[j]) <= 0 ? sorted[i++] : add[j++]);
		while (i < sorted.length)
			out.push(sorted[i++]);
		while (j < add.length)
			out.push(add[j++]);
		return out;
	}
}
