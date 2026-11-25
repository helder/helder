package studio;

import helder.ui.draw.DisplayList;
import helder.ui.draw.FrameArchive;

using StringTools;

// The screens' stills kept as data (helder.ui.draw.FrameArchive) in
// <out>/frames.hframes, each under a key of what made it (Sources: its
// story's file and what that imports, the project's other files, helder's,
// the format, the story's name).
// On open a screen whose key is the file's is drawn from it, nothing built
// or run (Previews: its host started at an edit, a hovered loop, Play, a
// request about a screen); one whose files changed shows its old frame,
// dimmed, until the program draws it. The host writes each still it
// settles (NativeHost's Host.still): kept here under the key of the files
// its build was made from, the file written a moment after.
class Stills {
	public static inline var FILE = "frames.hframes";

	final project:Project;
	final path:String;
	final archive:FrameArchive;
	var dirty = false;

	public function new(project:Project) {
		this.project = project;
		path = '${project.out}/$FILE';
		var b = try sys.io.File.getBytes(path) catch (_:Dynamic) null;
		archive = (b == null ? null : try FrameArchive.decode(b) catch (_:Dynamic) null) ?? new FrameArchive();
	}

	// a screen's still from the file (null: none, or a font it draws gone)
	public function list(name:String):Null<DisplayList>
		return try archive.list(name) catch (e:Dynamic) {
			Sys.println('studio: $FILE: $name: $e');
			null;
		}

	// a screen's loop from the file (decoded once: its lists kept), null: none
	public function loop(name:String):Null<{fps:Int, lists:Array<DisplayList>, ms:Float}> {
		if (!archive.looped(name)) return null;
		var l = loops.get(name);
		if (l != null) return l;
		var t0 = haxe.Timer.stamp();
		var d = try archive.loop(name) catch (e:Dynamic) {
			Sys.println('studio: $FILE: $name\'s loop: $e');
			null;
		}
		if (d == null) return null;
		loops.set(name, l = {fps: d.fps, lists: d.lists, ms: Math.round((haxe.Timer.stamp() - t0) * 10000) / 10});
		return l;
	}

	final loops = new Map<String, {fps:Int, lists:Array<DisplayList>, ms:Float}>();

	public function looped(name:String):Bool
		return archive.looped(name);

	public function size(name:String):Null<{width:Float, height:Float}>
		return archive.size(name);

	// whether a screen's still (its story's file: file) is of the files now
	public function fresh(name:String, file:String, sources:Sources):Bool
		return archive.key(name) == sources.key(file, name);

	// a host's still (path: a frames file of it alone) kept, of the files its build was made from
	public function took(name:String, file:String, path:String, sources:Sources) {
		var b = try sys.io.File.getBytes(path) catch (_:Dynamic) null;
		var one = b == null ? null : FrameArchive.decode(b);
		if (one == null) return;
		archive.take(one, name, sources.key(file, name));
		loops.remove(name);
		dirty = true;
	}

	// the screens not in the project any more let go
	public function keep(names:Array<String>)
		for (n in archive.names())
			if (!names.contains(n)) {
				archive.remove(n);
				dirty = true;
			}

	// the file written when a still changed (whole, then named over the old)
	public function save() {
		if (!dirty) return;
		dirty = false;
		try {
			helder.cli.TestCommand.mkdirs(project.out);
			sys.io.File.saveBytes(path + ".part", archive.encode());
			if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
			sys.FileSystem.rename(path + ".part", path);
		} catch (e:Dynamic)
			Sys.println('studio: $FILE not written: $e');
	}
}
