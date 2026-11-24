package helder.os.linux;

#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
import helder.os.PathsDesktop;
import helder.os.Places;
import helder.os.Places.Place;
import helder.os.Places.Volume;
import hxmc.unsafe.*;
import sys.io.File;

using StringTools;

// /proc/self/mountinfo is per mount namespace. Its paths escape a space,
// tab, newline or backslash as three octal digits.
@:hxmc.unsafe(gc)
class LinuxPlaces {
	static final NETWORK = ["nfs", "nfs4", "cifs", "smb3", "fuse.sshfs"];
	static final PSEUDO = ["autofs", "bpf", "cgroup", "cgroup2", "configfs", "debugfs", "devpts", "devtmpfs", "efivarfs",
		"fusectl", "hugetlbfs", "mqueue", "nsfs", "proc", "pstore", "ramfs", "rpc_pipefs", "securityfs", "sysfs", "tmpfs", "tracefs"];

	public static function user():Array<Place> {
		var home = Sys.getEnv("HOME") ?? "";
		var config = Sys.getEnv("XDG_CONFIG_HOME");
		if (config == null || !config.startsWith("/")) config = home + "/.config";
		var dirs = try File.getContent(config + "/user-dirs.dirs") catch (_:Dynamic) null;
		var keys = ["", "DESKTOP", "DOCUMENTS", "DOWNLOAD", "PICTURES", "VIDEOS", "MUSIC"];
		var defaults = ["", "/Desktop", "/Documents", "/Downloads", "/Pictures", "/Videos", "/Music"];
		var result:Array<Place> = [];
		for (i in 0...keys.length) {
			var path = i == 0 ? home : PathsDesktop.userDir(dirs, "XDG_" + keys[i] + "_DIR", home);
			if (path == null && home.startsWith("/")) path = home + defaults[i];
			if (path == null || !path.startsWith("/") || !Places.directory(path)) continue;
			result.push({kind: Places.kinds[i], name: basename(path), path: path});
		}
		return result;
	}

	public static function volumes():Array<Volume>
		return Arena.scopedValue(a -> {
			var result:Array<Volume> = [], seen = new Map<String, Bool>();
			var stats = a.alloc(128);
			for (mount in mounts()) {
				var path = mount.path, root = path == "/", network = NETWORK.contains(mount.fs);
				var removable = under(path, "/media") || under(path, "/run/media");
				if (!root && (PSEUDO.contains(mount.fs) || !(removable || under(path, "/mnt") || network && under(path, "/home")))) continue;
				if (seen.exists(path)) continue;
				seen.set(path, true);
				var v:Volume = {name: root ? "Computer" : basename(path), path: path, total: 0, free: 0,
					removable: removable, network: network, root: root};
				if (LinuxVolumes.statvfs(a.cstring(path), stats) == 0) {
					// (64-bit struct statvfs: f_frsize, f_blocks, f_bavail)
					var unit = (Mem.getI64(stats, 8) : haxe.Int64).toFloat();
					v.total = unit * (Mem.getI64(stats, 16) : haxe.Int64).toFloat();
					v.free = unit * (Mem.getI64(stats, 32) : haxe.Int64).toFloat();
				}
				if (root) result.unshift(v) else result.push(v);
			}
			return result;
		});

	@:allow(helder.os.linux.LinuxTrash) static function mounts():Array<{path:String, fs:String}> {
		var text = try File.getContent("/proc/self/mountinfo") catch (_:Dynamic) "";
		var escape = ~/\\([0-7])([0-7])([0-7])/g;
		var result = [];
		for (line in text.split("\n")) {
			var fields = line.split(" "), sep = fields.indexOf("-", 6);
			if (sep < 0 || sep + 1 >= fields.length) continue;
			var path = escape.map(fields[4], r -> String.fromCharCode(64 * Std.parseInt(r.matched(1)) + 8 * Std.parseInt(r.matched(2)) + Std.parseInt(r.matched(3))));
			result.push({path: path, fs: fields[sep + 1]});
		}
		return result;
	}

	static inline function under(path:String, base:String):Bool
		return path == base || path.startsWith(base + "/");

	static function basename(path:String):String {
		var end = path.length;
		while (end > 1 && path.charAt(end - 1) == "/") end--;
		return end == 1 && path.charAt(0) == "/" ? "/" : path.substring(path.lastIndexOf("/", end - 1) + 1, end);
	}
}

#if (hxmc.libc == "glibc")
@:hxmc.lib("libc.so.6")
#end
@:hxmc.c private extern class LinuxVolumes {
	static function statvfs(path:Ptr, stats:Ptr):Int;
}
#end
