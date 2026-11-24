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

	// the window's content, dark or light, at a laptop's size (the stories'
	// trees are taken in a phone's whatever a story's width: Stories.tree)
	public static function themed(x:Explorer, dark:Bool):View
		return <view width={1100} height={700} shrink={0} ref={(n:Node) -> if (n.ui != null) n.ui.dark = dark}>{Shell.view(x)}</view>;
}
