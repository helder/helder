package viewer;

import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// FolderModel: natural order, wrapping, the neighbours by distance, the
// browser's list given again (the one shown kept)
function tests() {
	describe("FolderModel", () -> {
		test("natural order: numbers by value, letters without case", () -> {
			var names = ["img10.png", "IMG2.png", "img1.png", "a.jpg", "img02.png", "B.gif", "img2.png", "photo 10.jpg", "photo 9.jpg"];
			names.sort(FolderModel.compare);
			equals(names, ["a.jpg", "B.gif", "img1.png", "IMG2.png", "img2.png", "img02.png", "img10.png", "photo 9.jpg", "photo 10.jpg"]);
			equals(FolderModel.compare("x", "x"), 0);
			assert(FolderModel.compare("file99999999999999999999.png", "file100000000000000000000.png") < 0, "long runs by length");
		});
		test("file names in any script (tests/fixtures/scripts): each listed, opened, decoded", () -> {
			var dir = "tests/fixtures/scripts", m = new FolderModel();
			m.setEntries(FileSystem.readDirectory(dir));
			equals(m.files.length, 10);
			for (name in ["مرحبا بالعالم.png", "שלום עולם.png", "हिन्दी चित्र.png", "ภาพถ่ายทะเล.png", "日本の写真.png", "🎉 party 🎈.png", "photo של יום ٢٠٢٦.png"]) {
				assert(m.files.contains(name), name);
				var d = Decode.decode(File.getBytes('$dir/$name'));
				equals([d.width, d.height], [480, 320], name);
			}
		});
		test("images only, by extension", () -> {
			var m = new FolderModel();
			m.setEntries(["notes.txt", "b.JPG", "a.webp", "c.gif", "d.png", "e.jpeg", ".hidden"]);
			equals(m.files, ["a.webp", "b.JPG", "c.gif", "d.png", "e.jpeg"]);
			equals(m.index, 0);
		});
		test("next and previous wrap; first, last; the neighbours nearest first", () -> {
			var m = new FolderModel();
			m.setEntries(["1.png", "2.png", "3.png", "4.png", "5.png"], "1.png");
			m.go(-1);
			equals(m.name, "5.png");
			m.go(1);
			equals(m.name, "1.png");
			equals(m.around(2), [0, 1, 4, 2, 3]);
			m.last();
			equals(m.name, "5.png");
			m.first();
			equals(m.name, "1.png");
			var one = new FolderModel();
			one.setEntries(["only.png"]);
			equals(one.go(1), false);
			equals(one.around(2), [0]);
		});
		test("the browser's list: the one shown kept by name, else the one at its place", () -> {
			var m = new FolderModel();
			m.set("/pics", ["img1.png", "img2.png", "img10.png"], "img2.png");
			equals(m.current, "/pics/img2.png");
			equals(m.relist(["img1.png", "img2.png", "img10.png"]), false);
			assert(m.relist(["img1.png", "img2.png", "img3.png", "img10.png"]));
			equals(m.name, "img2.png");
			m.relist(["img1.png", "img3.png", "img10.png"]);
			equals(m.name, "img3.png");
			// (a file the list leaves out, opened by its name: there too)
			m.set("/pics", ["a.png"], "notes.txt");
			equals(m.files, ["a.png", "notes.txt"]);
			equals(m.name, "notes.txt");
		});
	});
}

