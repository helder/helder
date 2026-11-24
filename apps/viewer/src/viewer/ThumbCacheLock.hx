package viewer;

import haxe.io.Bytes;
import hxmc.NativeSys;
import hxmc.unsafe.*;

// The PID in thumbs/lock is for inspection. A descriptor owns the file,
// so a crashed process gives it back, including if its PID is reused.
// Keep the inode after close: unlinking it could let two owners lock
// different files with the same name.
@:allow(viewer.ThumbCache)
@:hxmc.unsafe(gc)
class ThumbCacheLock {
	final fd:Int;

	function new(fd:Int)
		this.fd = fd;

	static function take(path:String):Null<ThumbCacheLock> {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || (!hxmc.target && helder.os == "windows"))
		var fd = Arena.scopedValue(a -> openWindows(a.wstring(path)));
		var pid = ThumbLockWindows.GetCurrentProcessId();
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64" || (!hxmc.target && (helder.os == "macos" || helder.os == "linux")))
		var fd = Arena.scopedValue(a -> openPosix(a.cstring(path)));
		var pid = ThumbLockPosix.getpid();
		#else
		var fd = -1, pid = 0;
		#end
		if (fd < 0) return null;
		var bytes = Bytes.ofString(pid + "\n");
		if (NativeSys.fileWrite(fd, bytes, 0, bytes.length) != bytes.length) {
			NativeSys.fileClose(fd);
			return null;
		}
		return new ThumbCacheLock(fd);
	}

	function close()
		NativeSys.fileClose(fd);

	// (on Windows keep the same eviction semantics as an open POSIX file:
	// an older read-only process may finish reading an unlinked segment)
	static function openReader(path:String):sys.io.FileInput {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || (!hxmc.target && helder.os == "windows"))
		var fd = Arena.scopedValue(a -> {
			var h = Win32.CreateFileW(a.wstring(path), 0x80000000, 7, Ptr.nil(), 3, 0x80, Ptr.nil());
			if (h.toI64() == -1) return -1;
			var fd = Win32._open_osfhandle(h, 0x8000);
			if (fd < 0) Win32.CloseHandle(h);
			return fd;
		});
		if (fd < 0) throw haxe.io.Error.Custom("cannot read " + path);
		return @:privateAccess new sys.io.FileInput(fd);
		#else
		return sys.io.File.read(path, true);
		#end
	}

	#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || (!hxmc.target && helder.os == "windows"))
	static function openWindows(path:Ptr):Int {
		// (CREATE_NEW, else CREATE_ALWAYS: only one handle can write)
		var h = Win32.CreateFileW(path, 0x40000000, 1, Ptr.nil(), 1, 0x80, Ptr.nil());
		if (h.toI64() == -1) h = Win32.CreateFileW(path, 0x40000000, 1, Ptr.nil(), 2, 0x80, Ptr.nil());
		if (h.toI64() == -1) return -1;
		var fd = Win32._open_osfhandle(h, 0x8001); // (_O_BINARY | _O_WRONLY)
		if (fd < 0) Win32.CloseHandle(h);
		return fd;
	}
	#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64" || (!hxmc.target && (helder.os == "macos" || helder.os == "linux")))
	static function openPosix(path:Ptr):Int {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || (!hxmc.target && helder.os == "macos"))
		var cloexec = 0x1000000, create = 0x200, exclusive = 0x800;
		#else
		var cloexec = 0x80000, create = 0x40, exclusive = 0x80;
		#end
		var fd = Posix.open(path, 1 | cloexec | create | exclusive, 0x180);
		if (fd < 0) fd = Posix.open(path, 1 | cloexec, 0);
		if (fd < 0) return -1;
		// (LOCK_EX | LOCK_NB, including against another instance in this process)
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || (!hxmc.target && helder.os == "macos"))
		var ok = ThumbLockMac.flock(fd, 6) == 0 && ThumbLockMac.ftruncate(fd, 0) == 0;
		#else
		// (flock and ftruncate, through syscall: hxmc's glibc imports lack flock)
		var arm = hxmc.Platform.arm();
		var ok = Posix.syscall(arm ? 32 : 73, fd, 6) == 0 && Posix.syscall(arm ? 46 : 77, fd, 0) == 0;
		#end
		if (ok) return fd;
		Posix.close(fd);
		return -1;
	}
	#end
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || (!hxmc.target && helder.os == "windows"))
@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") private extern class ThumbLockWindows {
	static function GetCurrentProcessId():Int;
}
#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64" || (!hxmc.target && (helder.os == "macos" || helder.os == "linux")))
@:hxmc.c @:hxmc.fast private extern class ThumbLockPosix {
	static function getpid():Int;
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || (!hxmc.target && helder.os == "macos"))
@:hxmc.c @:hxmc.fast private extern class ThumbLockMac {
	static function flock(fd:Int, mode:Int):Int;
	static function ftruncate(fd:Int, size:hxmc.I64):Int;
}
#end
#end
