package viewer;

import sys.FileSystem;
import sys.io.File;

// The tests' folders as MemoryFiles, at their paths on disk (so the
// decodes, which read the disk, find the same files)
class Fixtures {
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
}
