package viewer;

import haxe.io.Bytes;
import helder.test.Test;
import viewer.Files;

// The browser without a window, on MemoryFiles: navigation and its
// history, the sidebar's level for a folder, the order, the filter and
// folders first, listings in batches with the selection kept, a file
// opened full size and back, the trash and its undo, several selected
function tests() {
	describe("Browser", () -> {
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
