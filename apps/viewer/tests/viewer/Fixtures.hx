package viewer;

import helder.ui.Node;
import helder.view.*;
import sys.FileSystem;
import sys.io.File;

// The tests' folders as MemoryFiles, at their paths on disk (so the
// decodes, which read the disk, find the same files)
class Fixtures implements Markup {
	public static function files(dirs:Array<String>):MemoryFiles {
		var m = new MemoryFiles();
		for (d in dirs) {
			m.add(d + "/");
			for (n in FileSystem.readDirectory(d))
				if (!FileSystem.isDirectory('$d/$n')) m.add('$d/$n', File.getBytes('$d/$n'));
		}
		return m;
	}

	// an explorer of them, decoding at once on this thread
	public static function explorer(?dirs:Array<String>):Explorer
		return new Explorer(files(dirs ?? ["tests/fixtures/folder", "tests/fixtures/pdf"]), (path, side, done) -> done(Decode.file({path: path, side: side})),
			[], [], Preview.now);

	// (on this disk: a story's program runs elsewhere, helder publish's)
	static function sample(f:{file:String}):haxe.io.Bytes
		return File.getBytes(Samples.home() + "/" + f.file);

	// the web build's sample folder as its browser has it (Samples: its
	// paths, the files' bytes read here), decoding at once from those bytes
	// as the web's decodes do (Decode.of), the PDF's sizes too; no previews
	public static function samples():Explorer {
		var m = new MemoryFiles(), bytes = new Map<String, haxe.io.Bytes>();
		for (f in Samples.FILES) {
			bytes.set(f.path, sample(f));
			m.add(f.path, bytes.get(f.path), Samples.MODIFIED);
		}
		return new Explorer(m, (path, side, done) -> done(Decode.of({path: path, bytes: bytes.get(Decode.parseKey(path).path), side: side})),
			[{kind: Pictures, name: Samples.ROOT, path: Samples.ROOT}], [], (_, _) -> () -> {},
			(path, done) -> done(PdfPages.sizesIn({path: path, bytes: bytes.get(path)})));
	}

	// the thumbnails of the folder shown made at once (Tiles', as the queue
	// would make them: the samples' pictures and the PDF's first page)
	public static function thumbnails(x:Explorer) {
		for (e in x.browser.items.value) {
			var f = Lambda.find(Samples.FILES, f -> f.path == x.browser.path(e.name));
			if (f == null || !Kinds.viewable(e) || FolderModel.isMedia(e.name)) continue;
			var d = Decode.of({path: f.path, bytes: sample(f), side: Thumbnails.SIDE});
			if (d.frames.length == 0) continue;
			var rgba = haxe.io.Bytes.alloc(d.pixelsWidth * d.pixelsHeight * 4);
			d.frames[0].pixels.blitToBytes(0, rgba, 0, rgba.length);
			Decode.release(d);
			var fit = helder.image.Resize.toFit(rgba, d.pixelsWidth, d.pixelsHeight, Thumbnails.SIDE, Thumbnails.SIDE);
			Tiles.remember(x, e, new helder.image.Image(fit.width, fit.height, fit.rgba));
		}
	}

	// the window's content, dark or light, at a laptop's size (the stories'
	// trees are taken in a phone's whatever a story's width: Stories.tree)
	public static function themed(x:Explorer, dark:Bool):View
		return <view width={1100} height={700} shrink={0} ref={(n:Node) -> if (n.ui != null) n.ui.dark = dark}>{Shell.view(x)}</view>;
}
