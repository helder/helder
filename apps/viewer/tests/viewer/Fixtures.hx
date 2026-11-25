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
	public static function explorer(?dirs:Array<String>):Explorer {
		Kinds.utc = true;
		Tiles.forget();
		var m = files(dirs ?? ["tests/fixtures/folder", "tests/fixtures/pdf"]);
		var x = new Explorer(m, (path, side, done) -> done(Decode.file({path: path, side: side})), [], [], Preview.now, null, (path, done) -> done(m.text(path)));
		// (a document's pictures measured at once, as its text is read)
		x.viewer.measure = (paths, done) -> done([for (p in paths) FileSystem.exists(p) ? helder.image.Image.size(File.getBytes(p)) : null]);
		return x;
	}

	// (on this disk: a story's program runs elsewhere, helder publish's)
	static function sample(f:{file:String}):haxe.io.Bytes
		return File.getBytes(Samples.home() + "/" + f.file);

	// the web build's sample folder as its browser has it (Samples: its
	// paths, the files' bytes read here), decoding at once from those bytes
	// as the web's decodes do (Decode.of), the PDF's sizes too; no previews
	// (keep: the files kept, by name; a story's leaves out video and audio,
	// which only some machines decode, so its counts are the same everywhere)
	public static function samples(?keep:String->Bool):Explorer {
		Kinds.utc = true;
		Tiles.forget();
		var m = new MemoryFiles(), bytes = new Map<String, haxe.io.Bytes>();
		for (f in Samples.FILES) {
			if (keep != null && !keep(f.file)) continue;
			bytes.set(f.path, sample(f));
			m.add(f.path, bytes.get(f.path), Samples.MODIFIED);
		}
		var x = new Explorer(m, (path, side, done) -> done(Decode.of({path: path, bytes: bytes.get(Decode.parseKey(path).path), side: side})),
			[{kind: Pictures, name: Samples.ROOT, path: Samples.ROOT}], [], (_, _) -> () -> {},
			(path, done) -> done(PdfPages.sizesIn({path: path, bytes: bytes.get(path)})), (path, done) -> done(m.text(path)));
		x.viewer.measure = (paths, done) -> done([for (p in paths) bytes.exists(p) ? helder.image.Image.size(bytes.get(p)) : null]);
		return x;
	}

	// the thumbnails of the folder shown made at once (Tiles', as the queue
	// would make them: the samples' pictures and the PDF's first page)
	public static function thumbnails(x:Explorer) {
		for (e in x.browser.items.value) {
			var f = Lambda.find(Samples.FILES, f -> f.path == x.browser.path(e.name));
			if (f == null || !Kinds.viewable(e) || FolderModel.isMedia(e.name) || FolderModel.isMarkdown(e.name)) continue;
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
		return <view width={1100} height={700} shrink={0} ref={(n:Node) -> if (n.ui != null) n.ui.dark = dark}>{Shell.view(x, () -> helder.ui.SizeClass.Expanded)}</view>;

	// (the browser, dark, with a marquee dragged from under the grid's cells
	// up over its first row, frame by frame as a mouse would; done once it is)
	public static function marquee(x:Explorer, done:Void->Void):View {
		var frames = 0;
		return <view width={1100} height={700} shrink={0} ref={(n:Node) -> helder.ui.Clock.add(_ -> {
			var grid = n.ui == null ? null : n.ui.root.find("grid");
			if (grid == null || grid.height == 0) return true;
			var bottom = grid.absY + grid.height - 20, right = grid.absX + grid.width - 20;
			switch frames++ {
				case 0: n.ui.pointerDown(right, bottom, 1);
				case 1: n.ui.pointerMove(right - 100, bottom - 100);
				case _:
					n.ui.pointerMove(grid.absX + 120, grid.absY + 60);
					done();
					return false;
			}
			true;
		})}>{themed(x, true)}</view>;
	}

	// (the phone stories' markup: on Windows a story file's own isn't processed)
	public static function phone(x:Explorer, at:viewer.Phone.PhoneState->Void):View
		return <helder.ui.controls.Standard.Themed look={Shell.look}><Phone.Root x={x} at={at}/></helder.ui.controls.Standard.Themed>;

	public static function tile(name:String):View
		return <view grow={1}>{Tiles.large({name: name, kind: File, size: 0, modified: 0, created: 0})}</view>;
}
