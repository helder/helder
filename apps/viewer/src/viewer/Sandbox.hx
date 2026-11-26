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
	static final FOLDERS = ["tests/fixtures/folder", "tests/fixtures/pdf", "tests/fixtures/markdown"];

	// (the files' bytes, read once: every screen's, never changed)
	static final read = new Map<String, Bytes>();

	public static function explorer():Explorer {
		var m = new MemoryFiles(), bytes = new Map<String, Bytes>();
		function put(path:String, file:String, modified = 0.0) {
			var b = read.get(file);
			if (b == null) read.set(file, b = File.getBytes(file));
			bytes.set(path, b);
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
		m.denied.push(LOCKED);
		var places:Array<helder.os.Places.Place> = [
			{kind: Pictures, name: Samples.ROOT, path: Samples.ROOT},
			{kind: Documents, name: "Fixtures", path: "tests/fixtures"}
		];
		var x = new Explorer(m, (key, side, done) -> done(Decode.of({path: key, bytes: bytes.get(Decode.parseKey(key).path), side: side})), places, [],
			(path, done) -> Preview.from(path, bytes.get(path), done), (path, done) -> done(PdfPages.sizesIn({path: path, bytes: bytes.get(path)})),
			(path, done) -> done(m.text(path)));
		x.viewer.measure = (paths, done) -> done([for (p in paths) bytes.exists(p) ? helder.image.Image.size(bytes.get(p)) : null]);
		var listed = x.browser.onItems;
		x.browser.onItems = () -> {
			if (listed != null) listed();
			tiles(x, bytes);
		};
		Kinds.utc(true);
		return x;
	}

	// (the folder's thumbnails made now, as the queue would make them; kept by content, every screen's)
	static function tiles(x:Explorer, bytes:Map<String, Bytes>)
		for (e in x.browser.items.value) {
			var b = bytes.get(x.browser.path(e.name));
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
#end
