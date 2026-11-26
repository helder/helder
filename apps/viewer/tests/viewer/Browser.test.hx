package viewer;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import viewer.Files;
import viewer.Listing;

// The browser without a window, on MemoryFiles: navigation and its
// history, the sidebar's level for a folder, the order, the filter and
// folders first, listings in batches with the selection kept, a file
// opened full size and back, the trash and its undo, several selected,
// a new folder, a rename, files moved and copied into a folder; between
// folders (random goes, backs and forwards, on a disk slow or not) never
// a list gone empty but a folder's read empty or failed, a folder seen
// lately shown as it was at once; and against a list (a stateful
// property: sorts, filters, selections, the trash and its undo)
function tests() {
	describe("Browser", () -> {
		test("the selection all hidden, the focus toggled off: none selected", () -> {
			var b = new Browser(new MemoryFiles().add("/f/.h.png", Bytes.alloc(1)).add("/f/a.png", Bytes.alloc(1)));
			b.go("/f");
			b.showHidden(true);
			b.select(".h.png");
			b.selection.toggle(b.indexOf("a.png"));
			b.selectionChanged();
			b.showHidden(false);
			b.selection.toggle(b.indexOf("a.png"));
			b.selectionChanged();
			equals(b.selected.value, "");
		});
		test("against a list: sorts, filters, the selection, the trash and undo", () -> stateful({
			setup: () -> new Model(),
			steps: [
				{name: "sort", run: (m, c) -> m.sort(c.draw(pick([Name, Kind, Modified, Size])), c.draw(bool()), c.draw(bool()))},
				{name: "hidden", run: (m, c) -> m.hidden(c.draw(bool()))},
				{name: "search", run: (m, c) -> m.search(c.draw(pick(["", "a", "e", "png", "x"])))},
				{name: "select", run: (m, c) -> m.select(c.draw(pick(NAMES)))},
				{name: "toggle", run: (m, c) -> m.toggle(c.draw(int(0, 9)))},
				{name: "trash", run: (m, c) -> m.trash()},
				{name: "undo", run: (m, c) -> m.undo()},
				{name: "watch", run: (m, c) -> m.watch()}
			],
			check: m -> m.check()
		}, {cases: 100, steps: 30}));
		test("between folders: never a list gone blank but for a folder read empty", () -> stateful({
			setup: () -> {
				var files = new MemoryFiles().add("/a/1.png", Bytes.alloc(1)).add("/a/2.png", Bytes.alloc(2)).add("/b/x.mjs", Bytes.alloc(3)).add("/c/")
					.add("/d/e/y.png", Bytes.alloc(4));
				var b = new Browser(files);
				b.go("/a");
				{files: files, b: b};
			},
			steps: [
				{name: "go", run: (s, c) -> blank(s, () -> {
					s.files.hold = c.draw(bool());
					s.b.go(c.draw(pick(["/a", "/b", "/c", "/d", "/d/e", "/missing"])));
				})},
				{name: "disk answers", run: (s, c) -> blank(s, () -> s.files.release())},
				{name: "back", run: (s, c) -> blank(s, () -> s.b.goBack())},
				{name: "forward", run: (s, c) -> blank(s, () -> s.b.goForward())}
			]
		}, {cases: 80, steps: 25}));
		test("a folder seen lately: as it was, at once, the disk slow", () -> {
			var files = tree(), b = new Browser(files);
			b.go("/Users/ben/Pictures");
			b.go("/Users/ben/Pictures/Trips");
			files.hold = true;
			b.goBack();
			equals(b.stale, false);
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			// (read again: the same, replaced whole)
			files.release();
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(b.reading.value, false);
			// (a folder not seen yet: the last one's kept, never emptied, until it is read)
			files.hold = true;
			b.go("/Users/ben/Pictures/Trips/Iceland");
			equals(b.stale, true);
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			files.release();
			equals(names(b), ["x.jpg"]);
		});
		test("navigation and history", () -> {
			var b = new Browser(tree());
			b.go("/Users/ben/Pictures");
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			b.go("/Users/ben/Pictures/Trips");
			equals(b.canBack.value, true);
			equals(b.canForward.value, false);
			b.select("Iceland");
			b.go("/Users/ben/Pictures/Trips/Iceland");
			assert(b.goBack());
			equals(b.dir.value, "/Users/ben/Pictures/Trips");
			equals(b.selected.value, "Iceland");
			assert(b.goForward());
			equals(b.dir.value, "/Users/ben/Pictures/Trips/Iceland");
			// (the enclosing folder, the one left selected)
			assert(b.up());
			equals(b.dir.value, "/Users/ben/Pictures/Trips");
			equals(b.selected.value, "Iceland");
			equals(b.canForward.value, false);
			equals(Browser.parent("/"), null);
			equals(Browser.ancestry("/Users/ben"), ["/", "/Users", "/Users/ben"]);
			equals(Browser.parent("C:\\Users"), "C:\\");
		});
		test("the sidebar's level: the folder's parent, a volume's top its own", () -> {
			var files = tree();
			var s = new Sidebar(files, [{kind: Pictures, name: "Pictures", path: "/Users/ben/Pictures"}],
				[{name: "Disk", path: "/", total: 100, free: 40, removable: false, network: false, root: true}]);
			equals(s.levelFor("/Users/ben/Pictures/Trips/Iceland"), "/Users/ben/Pictures/Trips");
			equals(s.levelFor("/"), "/");
			s.follow("/Users/ben/Pictures/Trips");
			equals(s.level.value, "/Users/ben/Pictures");
			equals([for (r in s.rows.value) r.name], ["Trips"]);
			// (Trips has a folder inside: its "›")
			equals(s.rows.value[0].deeper, true);
			equals(s.title("/Users/ben/Pictures"), "Pictures");
			equals(s.backLabel(), "ben");
			s.back();
			equals(s.level.value, "/Users/ben");
			s.show("/");
			equals(s.backLabel(), "Overview");
			s.back();
			equals(s.level.value, "");
			equals(s.volumeOf("/Users/ben").name, "Disk");
			equals(s.placeOf("/Users/ben/Pictures/Trips").name, "Pictures");
			// (a place chosen: its own level)
			var x = new Explorer(files, (_, _, _) -> {}, s.places.value, s.volumes, Preview.now);
			x.choose("/Users/ben/Pictures");
			equals(x.sidebar.level.value, "/Users/ben/Pictures");
			x.browser.go("/Users/ben/Pictures/Trips/Iceland");
			equals(x.sidebar.level.value, "/Users/ben/Pictures/Trips");
		});
		test("order, folders first, hidden files, the filter", () -> {
			var b = new Browser(tree());
			b.go("/Users/ben/Pictures");
			b.sortBy(Size);
			equals(names(b), ["Trips", "notes.txt", "a.jpg", "b.png"]);
			b.sortBy(Size);
			equals(names(b), ["Trips", "b.png", "a.jpg", "notes.txt"]);
			b.setOrder({key: Name, ascending: true, foldersFirst: false});
			equals(names(b), ["a.jpg", "b.png", "notes.txt", "Trips"]);
			b.setOrder({key: Kind, ascending: true, foldersFirst: true});
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			b.setOrder({key: Kind, ascending: false, foldersFirst: true});
			equals(names(b), ["Trips", "notes.txt", "b.png", "a.jpg"]);
			b.setOrder({key: Name, ascending: true, foldersFirst: true});
			b.showHidden(true);
			equals(names(b), ["Trips", ".secret", "a.jpg", "b.png", "notes.txt"]);
			b.showHidden(false);
			b.search("PNG");
			equals(names(b), ["b.png"]);
			equals(b.selected.value, "b.png");
			b.closeSearch();
			equals(names(b).length, 4);
		});
		test("batches merged in order, the view's selection kept, the watch", () -> {
			var files = new MemoryFiles();
			files.size = 3;
			for (i in [10, 2, 7, 1, 5, 9, 3])
				files.add('/big/img$i.png', Bytes.alloc(i));
			var b = new Browser(files), seen = [];
			b.onItems = () -> seen.push(b.items.value.length);
			b.go("/big", "img5.png");
			equals(seen, [3, 6, 7]);
			equals(names(b), ["img1.png", "img2.png", "img3.png", "img5.png", "img7.png", "img9.png", "img10.png"]);
			equals(b.selected.value, "img5.png");
			equals(b.reading.value, false);
			// (the watch: one added, the selected one removed: the one now at its place)
			files.add("/big/img4.png", Bytes.alloc(4));
			files.remove("/big/img5.png");
			files.poll();
			equals(names(b), ["img1.png", "img2.png", "img3.png", "img4.png", "img7.png", "img9.png", "img10.png"]);
			equals(b.selected.value, "img4.png");
			// (a slow disk: reading until it answers)
			files.hold = true;
			b.go("/");
			equals(b.reading.value, true);
			files.release();
			equals(b.reading.value, false);
			equals(names(b), ["big"]);
			// (a folder that is not there)
			b.go("/nowhere");
			equals(b.error.value, "missing");
		});
		test("a file opened full size: the viewer's list the browser's, back with it selected", () -> {
			var shown = [];
			var x = new Explorer(tree(), (path, _, _) -> shown.push(path), [], [], Preview.now);
			x.browser.go("/Users/ben/Pictures");
			x.open("a.jpg");
			equals(x.full.value, true);
			equals(x.viewer.folder.files, ["a.jpg", "b.png"]);
			equals(x.viewer.folder.name, "a.jpg");
			x.viewer.next();
			x.close();
			equals(x.full.value, false);
			equals(x.browser.selected.value, "b.png");
			// (a folder opened: entered; a file the viewer does not show: the system's app)
			var opened = [];
			x.openDefault = p -> opened.push(p);
			x.open("notes.txt");
			equals(x.full.value, false);
			x.open("Trips");
			equals(x.browser.dir.value, "/Users/ben/Pictures/Trips");
			// (the command line: a file, full size in its folder)
			x.start("/Users/ben/Pictures/b.png");
			equals(x.browser.dir.value, "/Users/ben/Pictures");
			equals([x.full.value, x.viewer.folder.name == "b.png"], [true, true]);
		});
		test("the trash and its undo", () -> {
			var files = tree();
			var b = new Browser(files);
			b.go("/Users/ben/Pictures");
			b.select("a.jpg");
			equals(b.trash(["a.jpg"]), 1);
			equals(files.trashed, ["/Users/ben/Pictures/a.jpg"]);
			equals(names(b), ["Trips", "b.png", "notes.txt"]);
			equals(b.selected.value, "b.png");
			equals(b.canUndo.value, true);
			assert(b.undo());
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(b.selected.value, "a.jpg");
			equals(files.stat("/Users/ben/Pictures/a.jpg") != null, true);
			equals(b.canUndo.value, false);
		});
		test("several selected: kept by name through a sort, trashed together, put back together", () -> {
			var files = tree();
			var b = new Browser(files);
			b.go("/Users/ben/Pictures");
			b.select("a.jpg");
			b.selection.extend(b.indexOf("b.png"));
			b.selectionChanged();
			equals(b.picked(), ["a.jpg", "b.png"]);
			b.sortBy(Name);
			equals(b.picked(), ["b.png", "a.jpg"]);
			b.sortBy(Name);
			equals(b.trash(b.picked()), 2);
			equals(names(b), ["Trips", "notes.txt"]);
			assert(b.undo());
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(b.picked(), ["a.jpg", "b.png"]);
		});
		test("a new folder: untitled, numbered, selected and renamed in place", () -> {
			var b = new Browser(tree());
			b.go("/Users/ben/Pictures");
			equals(b.newFolder(), "untitled folder");
			equals([b.selected.value, b.renaming.value], ["untitled folder", "untitled folder"]);
			equals(b.newFolder(), "untitled folder 2");
			equals(b.entry("untitled folder 2")?.kind, Folder);
		});
		test("a rename: refused names, a name taken, undone", () -> {
			var files = tree();
			var b = new Browser(files);
			b.go("/Users/ben/Pictures");
			b.renaming("a.jpg");
			equals(b.rename("a.jpg", " c.jpg "), null);
			equals(b.renaming.value, "");
			equals(names(b), ["Trips", "b.png", "c.jpg", "notes.txt"]);
			equals(b.selected.value, "c.jpg");
			equals(b.rename("c.jpg", "b.png"), '"b.png" is already in this folder');
			equals(b.notice.value, '"b.png" is already in this folder');
			equals(b.rename("c.jpg", "x/y"), '"x/y" is not a name a file can have');
			assert(b.undo());
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(files.stat("/Users/ben/Pictures/c.jpg"), null);
		});
		test("files moved into a folder, copied, undone; the folder itself left out", () -> {
			var files = tree();
			var b = new Browser(files);
			b.go("/Users/ben/Pictures");
			var t = "/Users/ben/Pictures/Trips";
			equals(b.transfer(["/Users/ben/Pictures/a.jpg", "/Users/ben/Pictures/b.png", t], t, false), 2);
			equals(names(b), ["Trips", "notes.txt"]);
			equals(files.stat(t + "/a.jpg") != null, true);
			assert(b.undo());
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(files.stat(t + "/a.jpg"), null);
			// (a copy: both; already there: nothing)
			equals(b.transfer(["/Users/ben/Pictures/notes.txt"], t + "/Iceland", true), 1);
			equals(names(b), ["Trips", "a.jpg", "b.png", "notes.txt"]);
			equals(files.stat(t + "/Iceland/notes.txt")?.size, 10);
			equals(b.transfer([t + "/Iceland/x.jpg"], t + "/Iceland", false), 0);
			// (a folder moved with what is in it)
			equals(b.transfer([t + "/Iceland"], "/Users/ben/Pictures", false), 1);
			equals(files.stat("/Users/ben/Pictures/Iceland/x.jpg") != null, true);
			equals(names(b), ["Iceland", "Trips", "a.jpg", "b.png", "notes.txt"]);
		});
	});
}

private function tree():MemoryFiles
	return new MemoryFiles().add("/Users/ben/Pictures/a.jpg", Bytes.alloc(200))
		.add("/Users/ben/Pictures/b.png", Bytes.alloc(300))
		.add("/Users/ben/Pictures/notes.txt", Bytes.alloc(10))
		.add("/Users/ben/Pictures/.secret", Bytes.alloc(1))
		.add("/Users/ben/Pictures/Trips/Iceland/")
		.add("/Users/ben/Pictures/Trips/Iceland/x.jpg", Bytes.alloc(5));

private function names(b:Browser):Array<String>
	return [for (e in b.items.value) e.name];

// (a step on the browser: a list that showed entries empty after it only
// for the folder that is empty (/c: read now, or as last read), or failed)
private function blank(s:{files:MemoryFiles, b:Browser}, step:Void->Void) {
	var b = s.b, had = b.items.value.length > 0;
	step();
	if (had && b.items.value.length == 0) assert(b.error.value != "" || b.dir.value == "/c", 'blank at ${b.dir.value}, reading ${b.reading.value}');
}

private final NAMES = ["apple.png", "bird.jpg", "cat.txt", "dune", "echo.mjs", ".hidden.png", "fig", "grape.jpg", "kiwi"];

// (a Browser on a folder of MemoryFiles, read in batches of two, and its
// model: the entries, the order, the filter, the selection and its focus,
// the trash's groups)
private class Model {
	final files = new MemoryFiles();
	final b:Browser;
	var all:Array<Entry> = [];
	var order:Order = {key: Name, ascending: true, foldersFirst: true};
	var showHidden = false;
	var query = "";
	var sel:Array<String> = [];
	var focus:Null<String> = null;
	var selected = "";
	final undos:Array<Array<Entry>> = [];

	public function new() {
		files.size = 2;
		for (k in 0...NAMES.length) {
			var n = NAMES[k];
			if (n.indexOf(".") < 0) files.add('/f/$n/') else files.add('/f/$n', Bytes.alloc(k * 37 % 11 + 1), k * 5 % 9);
		}
		b = new Browser(files);
		b.go("/f");
		all = [for (n in NAMES) files.stat('/f/$n')];
	}

	public function sort(key:SortKey, ascending:Bool, foldersFirst:Bool) {
		b.setOrder(order = {key: key, ascending: ascending, foldersFirst: foldersFirst});
	}

	public function hidden(on:Bool) {
		b.showHidden(showHidden = on);
	}

	public function search(q:String) {
		b.search(query = q);
		prune();
		var s = shown();
		if (s.length > 0 && s.indexOf(selected) < 0) choose(s[0]);
	}

	public function select(name:String) {
		b.select(name);
		choose(name);
	}

	// (the model's select)
	function choose(name:String) {
		selected = name;
		var on = shown().contains(name);
		sel = on ? [name] : [];
		focus = on ? name : null;
	}

	// (the list's own input: a key toggled, the browser told)
	public function toggle(i:Int) {
		b.selection.toggle(i);
		b.selectionChanged();
		var s = shown();
		if (i < s.length) {
			if (!sel.remove(s[i])) sel.push(s[i]);
			focus = s[i];
		}
		var keys = [for (n in s) if (sel.contains(n)) n];
		selected = focus != null && sel.contains(focus) ? focus : keys.length > 0 ? keys[0] : "";
	}

	public function trash() {
		var s = shown();
		var picked = sel.length > 0 ? [for (n in s) if (sel.contains(n)) n] : selected != "" && s.contains(selected) ? [selected] : [];
		equals(b.trash(b.picked()), picked.length, "trashed");
		if (picked.length == 0) return;
		undos.push([for (n in picked) Lambda.find(all, e -> e.name == n)]);
		rescan([for (e in all) if (!picked.contains(e.name)) e]);
	}

	public function undo() {
		var group = undos.pop();
		equals(b.undo(), group != null, "undone");
		if (group == null) return;
		var names = [for (e in group) e.name];
		rescan([for (e in all) if (!names.contains(e.name)) e].concat(group));
		choose(names[0]);
		if (names.length > 1) sel = names.copy();
	}

	public function watch() {
		files.poll();
		rescan(all);
	}

	public function check() {
		equals([for (e in b.items.value) e.name], shown(), "shown");
		equals(b.total.value, all.length, "total");
		var s = shown();
		equals(b.selection.keys(), [for (n in s) if (sel.contains(n)) n], "selection");
		equals(b.selection.size(), sel.length, "selection size");
		equals(b.selected.value, selected, "selected");
		equals(b.canUndo.value, undos.length > 0, "canUndo");
	}

	// (the folder as it is now: the selection pruned, the selected gone: the one now in its place)
	function rescan(entries:Array<Entry>) {
		var at = shown().indexOf(selected);
		all = entries;
		prune();
		var s = shown();
		if (selected != "" && !s.contains(selected)) choose(s.length == 0 ? "" : s[Std.int(Math.min(Math.max(at, 0), s.length - 1))]);
	}

	function prune() {
		var s = shown();
		sel = sel.filter(n -> s.contains(n));
		if (focus != null && !s.contains(focus)) focus = null;
	}

	function shown():Array<String> {
		var out = [for (e in all) if ((showHidden || !StringTools.startsWith(e.name, ".")) && (query == "" || e.name.indexOf(query) >= 0)) e];
		var dir = order.ascending ? 1 : -1;
		out.sort((a, b) -> {
			if (order.foldersFirst && (a.kind == Folder) != (b.kind == Folder)) return a.kind == Folder ? -1 : 1;
			var c = switch order.key {
				case Kind: Reflect.compare(Kinds.kind(a), Kinds.kind(b));
				case Modified: Reflect.compare(a.modified, b.modified);
				case Size: Reflect.compare(a.size, b.size);
				case Name: 0;
			}
			return dir * (c != 0 ? c : Reflect.compare(a.name, b.name));
		});
		return [for (e in out) e.name];
	}
}

