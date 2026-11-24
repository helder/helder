package helder.os.linux;

#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
import haxe.io.Bytes;
import hxmc.Platform;
import hxmc.unsafe.*;
import sys.FileSystem;

using StringTools;

private typedef Entry = {device:haxe.Int64, mode:Int, uid:Int};

// The freedesktop trash. The info file reserves a name before the rename;
// another program may already have a file there even without its info.
@:hxmc.unsafe(gc)
class LinuxTrash {
	static inline var EEXIST = 17;
	static inline var ENOENT = 2;
	static inline var DIRECTORY = 0x4000;
	static inline var INFO_EXT = ".trashinfo";

	public static function move(path:String):String
		return Arena.scopedValue(a -> {
			// (resolve the parent, so a symlink itself can be trashed)
			var end = path.length;
			while (end > 1 && path.charAt(end - 1) == "/") end--;
			path = path.substr(0, end);
			var slash = path.lastIndexOf("/"), name = path.substr(slash + 1);
			if (name == "" || name == "." || name == "..") throw 'Trash: invalid item $path';
			var parent = canonical(a, slash < 0 ? "." : slash == 0 ? "/" : path.substr(0, slash));
			if (parent == null) throw 'Trash: cannot resolve $path';
			var source = join(parent, name), original:Ptr = a.cstring(source);
			var entry = status(original);
			if (entry == null) throw 'Trash: cannot read $source';

			var data = Sys.getEnv("XDG_DATA_HOME");
			if (data == null || !data.startsWith("/")) {
				var home = Sys.getEnv("HOME");
				data = home != null && home.startsWith("/") ? join(home, ".local/share") : null;
			}
			var uid = TrashFs.geteuid(), local = data == null ? null : existingParent(a, data);
			var directory:String, recorded:String;
			if (local != null && local.device == entry.device) {
				FileSystem.createDirectory(data);
				directory = join(data, "Trash");
				recorded = source;
			} else {
				var top = topdir(source);
				var shared = join(top, ".Trash"), sharedEntry = status(a.cstring(shared));
				var personal = sharedEntry != null && isDir(sharedEntry) && (sharedEntry.mode & 0x200) != 0 ? join(shared, '$uid') : null;
				directory = personal != null && setup(a, personal, uid) ? personal : join(top, '.Trash-$uid');
				recorded = source.substr(top == "/" ? 1 : top.length + 1);
			}
			var files = join(directory, "files"), info = join(directory, "info");
			if (!setup(a, directory, uid)) throw 'Trash: cannot use $directory';

			var encoded = recorded.urlEncode().replace("%2F", "/");
			var date = Date.now().toString().replace(" ", "T");
			var contents = Bytes.ofString('[Trash Info]\nPath=$encoded\nDeletionDate=$date\n');
			var bytes = a.copyBytes(contents), basename = Bytes.ofString(name);
			// (_PC_NAME_MAX: leave room for the info file's extension)
			var limit = Std.int(Math.min(nameMax(a, files), nameMax(a, info) - INFO_EXT.length));
			var attempt = 1;
			while (true) {
				var suffix = attempt == 1 ? "" : ' $attempt';
				if (limit <= suffix.length) throw 'Trash: name too long for $directory';
				var candidate = truncate(basename, limit - suffix.length) + suffix;
				attempt++;
				var dest = join(files, candidate), metadata = a.cstring(join(info, candidate + INFO_EXT));
				// (O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC; 0600)
				var fd = Posix.open(metadata, 0x800C1, 0x180);
				if (fd < 0) {
					if (Linux.errno() == EEXIST) continue;
					throw 'Trash: cannot reserve $dest';
				}
				if (!writeInfo(fd, bytes, contents.length)) {
					Posix.unlink(metadata);
					throw 'Trash: cannot write info for $source';
				}
				var error = rename(original, a.cstring(dest));
				if (error == 0) return dest;
				Posix.unlink(metadata);
				if (error != EEXIST) throw 'Trash: cannot move $source (errno $error)';
			}
			return null;
		});

	static function rename(source:Ptr, dest:Ptr):Int {
		// (renameat2, AT_FDCWD, RENAME_NOREPLACE: keep even an orphaned item)
		if (Linux.syscall(Platform.arm() ? 276 : 316, -100, source.toI64(), -100, dest.toI64(), 1, 0) == 0) return 0;
		var error = Linux.errno();
		// (older kernels and filesystems: the info file still reserves the name)
		if (error != Linux.ENOSYS && error != Linux.EINVAL && error != 95) return error; // (EOPNOTSUPP)
		if (status(dest) != null) return EEXIST;
		error = Linux.errno();
		if (error != ENOENT) return error;
		return Posix.rename(source, dest) == 0 ? 0 : Linux.errno();
	}

	static function nameMax(a:Arena, dir:String):Int {
		var max = TrashFs.pathconf(a.cstring(dir), 3).toInt();
		return max > 0 ? max : 255;
	}

	static function truncate(name:Bytes, limit:Int):String {
		var end = name.length;
		if (end > limit) {
			end = limit;
			while (end > 0 && (name.get(end) & 0xC0) == 0x80) end--;
		}
		return name.getString(0, end);
	}

	static function writeInfo(fd:Int, bytes:Ptr, size:Int):Bool {
		var offset = 0;
		while (offset < size) {
			var n = Posix.write(fd, bytes.add(offset), size - offset).toInt();
			if (n < 0 && Linux.errno() == Linux.EINTR) continue;
			if (n <= 0) break;
			offset += n;
		}
		return Posix.close(fd) == 0 && offset == size;
	}

	static function setup(a:Arena, dir:String, uid:Int):Bool
		return makePrivate(a, dir, uid) && makePrivate(a, join(dir, "files"), uid) && makePrivate(a, join(dir, "info"), uid);

	static function makePrivate(a:Arena, path:String, uid:Int):Bool {
		var p = a.cstring(path);
		// (0700; lstat refuses links even when they point to a directory)
		Posix.mkdir(p, 0x1C0);
		var entry = status(p);
		return entry != null && isDir(entry) && entry.uid == uid && (entry.mode & 0x3F) == 0;
	}

	static function existingParent(a:Arena, path:String):Null<Entry> {
		var end = path.length;
		while (end > 1 && path.charAt(end - 1) == "/") end--;
		path = path.substr(0, end);
		while (true) {
			var p = canonical(a, path);
			if (p != null) return status(a.cstring(p));
			if (Linux.errno() != ENOENT || path == "/") return null;
			path = path.substr(0, path.lastIndexOf("/"));
			if (path == "") path = "/";
		}
		return null;
	}

	static function topdir(path:String):String {
		var top = "/";
		for (mount in LinuxPlaces.mounts())
			if (mount.path.length > top.length && (path == mount.path || path.startsWith(mount.path + "/"))) top = mount.path;
		if (path == top) throw 'Trash: cannot move the mount point $path';
		return top;
	}

	static function canonical(a:Arena, path:String):Null<String> {
		var p:CString = cast Posix.realpath(a.cstring(path), Ptr.nil());
		if (p.isNull()) return null;
		var result = p.toString();
		LibC.free(p);
		return result;
	}

	static function status(path:Ptr):Null<Entry> {
		var st = Mem.stack(144);
		if (TrashFs.lstat(path, st) != 0) return null;
		// (struct stat on Linux x86-64 and arm64; the same in musl and glibc)
		return {device: Mem.getI64(st, 0), mode: Mem.getI32(st, Platform.arm() ? 16 : 24),
			uid: Mem.getI32(st, Platform.arm() ? 24 : 28)};
	}

	static inline function isDir(entry:Entry):Bool
		return (entry.mode & 0xF000) == DIRECTORY;

	static inline function join(dir:String, name:String):String
		return (dir.endsWith("/") ? dir : dir + "/") + name;
}

@:hxmc.c private extern class TrashFs {
	static function lstat(path:Ptr, st:Ptr):Int;
	static function geteuid():Int;
	static function pathconf(path:Ptr, name:Int):Int64;
}
#end
