package viewer;

#if (hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

// The files a preview host's screens browse (helder.ui.Hosting: the
// studio's scenarios) in place of the machine's disk and places: the tests'
// folders and the web build's samples, read from the project's folder (where
// the host runs) into memory at their paths there, with an empty folder and
// one that cannot be read. Decodes, previews and thumbnails are made at once
// from those bytes, so a still is whole as it is drawn; neither the user's
// store nor their thumbnails' cache is opened.
class Sandbox {
	public static inline var HOME = "tests/fixtures/folder";
	public static inline var EMPTY = "tests/fixtures/empty";
	public static inline var LOCKED = "tests/fixtures/locked";
	// a folder of files made up (a UI monkey's: helder.scenario.Monkey writes
	// made in a case's boot, its file names and kinds), each a fixture's bytes
	public static inline var MADE = "tests/fixtures/made";
	public static final made = helder.view.graph.Graph.signal(([] : Array<Made>));
	static final FOLDERS = ["tests/fixtures/folder", "tests/fixtures/pdf", "tests/fixtures/markdown"];

	// (the files' bytes, read once: every screen's, never changed)
	static final read = new Map<String, Bytes>();

	public static function explorer():Explorer {
		var m = new MemoryFiles();
		function put(path:String, file:String, modified = 0.0) {
			var b = read.get(file);
			if (b == null) read.set(file, b = File.getBytes(file));
			m.add(path, b, modified);
		}
		for (d in FOLDERS) {
			m.add(d + "/");
			for (n in FileSystem.readDirectory(d))
				if (!FileSystem.isDirectory('$d/$n')) put('$d/$n', '$d/$n');
		}
		// (no video or audio: only some machines decode them, and a still is the same everywhere)
		for (f in Samples.FILES)
			if (!~/\.(mp4|mov|m4v|webm|mkv|m4a|mp3|flac|mka)$/i.match(f.file)) put(f.path, f.file, Samples.MODIFIED);
		m.add(EMPTY + "/").add(LOCKED + "/");
		// (only when made has files: the studio's stills of the fixtures' folders as they were)
		if (made.peek().length > 0) m.add(MADE + "/");
		var taken = new Map<String, Bool>();
		for (f in made.peek()) {
			var name = fileName(f.name, f.kind, taken), path = '$MADE/$name';
			switch f.kind {
				case Folder: m.add(path + "/");
				case Empty: m.add(path, haxe.io.Bytes.alloc(0));
				case Truncated:
					put(path, fixture(Truncated));
					m.add(path, m.bytes(path).sub(0, 4096));
				case k: put(path, fixture(k));
			}
		}
		m.denied.push(LOCKED);
		var places:Array<helder.os.Places.Place> = [
			{kind: Pictures, name: Samples.ROOT, path: Samples.ROOT},
			{kind: Documents, name: "Fixtures", path: "tests/fixtures"}
		];
		// (a file's bytes where it is now: moved, renamed, trashed and put back as the explorer does; gone, none)
		function bytes(path:String):Bytes
			return m.bytes(path) ?? Bytes.alloc(0);
		var x = new Explorer(m, (key, side, done) -> done(Decode.of({path: key, bytes: bytes(Decode.parseKey(key).path), side: side})), places, [],
			(path, done) -> Preview.from(path, bytes(path), done), (path, done) -> done(PdfPages.sizesIn({path: path, bytes: bytes(path)})),
			(path, done) -> done(m.text(path)));
		x.viewer.measure = (paths, done) -> done([for (p in paths) m.bytes(p) != null ? helder.image.Image.size(m.bytes(p)) : null]);
		var listed = x.browser.onItems;
		x.browser.onItems = () -> {
			if (listed != null) listed();
			tiles(x, m);
		};
		Kinds.utc(true);
		return x;
	}

	// (a made file's name: no slash or NUL, as no file system has, nor a
	// backslash, which haxe.io.Path (MemoryFiles' names) takes for a
	// separator everywhere; one a name, its kind's extension, numbered when taken)
	static function fileName(given:String, kind:MadeKind, taken:Map<String, Bool>):String {
		var base = ~/[\/\\\x00]/g.replace(given, "∕");
		if (base == "" || base == "." || base == "..") base = "unnamed";
		var ext = kind == Folder ? "" : "." + haxe.io.Path.extension(fixture(kind));
		var name = base + ext, n = 1;
		while (taken.exists(name.toLowerCase()))
			name = '$base ${++n}$ext';
		taken.set(name.toLowerCase(), true);
		return name;
	}

	// (a made kind's bytes: one of the fixtures)
	static function fixture(k:MadeKind):String
		return switch k {
			case Photo | Truncated: "tests/fixtures/folder/photo 2.jpg";
			case Small: "tests/fixtures/folder/photo 10.jpg";
			case Png | Empty: "tests/fixtures/folder/alpha.png";
			case Gif: "tests/fixtures/folder/anim.gif";
			case Webp: "tests/fixtures/folder/lossy.webp";
			case Text: "tests/fixtures/folder/notes.txt";
			case Markdown: "tests/fixtures/markdown/doc.md";
			case Pdf: "tests/fixtures/pdf/pages.pdf";
			case Video: "tests/fixtures/monkey/clip.mp4";
			case Audio: "tests/fixtures/monkey/song.m4a";
			case Broken | Folder: "tests/fixtures/folder/broken.jpg";
		}

	// (the folder's thumbnails made now, as the queue would make them; kept by content, every screen's)
	static function tiles(x:Explorer, m:MemoryFiles)
		for (e in x.browser.items.value) {
			var b = m.bytes(x.browser.path(e.name));
			if (b == null || Tiles.cached(x, e) != null || !Kinds.viewable(e) || FolderModel.isMedia(e.name) || FolderModel.isMarkdown(e.name)) continue;
			var d = Decode.of({path: x.browser.path(e.name), bytes: b, side: Thumbnails.SIDE});
			if (d.frames.length == 0) {
				Decode.release(d);
				continue;
			}
			var rgba = Bytes.alloc(d.pixelsWidth * d.pixelsHeight * 4);
			d.frames[0].pixels.blitToBytes(0, rgba, 0, rgba.length);
			Decode.release(d);
			var fit = helder.image.Resize.toFit(rgba, d.pixelsWidth, d.pixelsHeight, Thumbnails.SIDE, Thumbnails.SIDE);
			Tiles.remember(x, e, new helder.image.Image(fit.width, fit.height, fit.rgba));
		}
}

// a file of the made folder: its name (its kind's extension added) and what it is
typedef Made = {
	var name:String;
	var kind:MadeKind;
}

// (a fixture's bytes; a JPEG cut short; nothing; a folder)
enum abstract MadeKind(String) {
	var Photo;
	var Small;
	var Png;
	var Gif;
	var Webp;
	var Text;
	var Markdown;
	var Pdf;
	var Video;
	var Audio;
	var Broken;
	var Truncated;
	var Empty;
	var Folder;
}
#end
