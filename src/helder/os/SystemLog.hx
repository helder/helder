package helder.os;

import helder.os.objc.*;
import hxmc.Platform;
import hxmc.unsafe.*;

// A line in the system's log, release builds included (what a profiler,
// a device's console or a test runner reads, not the program's output):
// macOS's and iOS's unified log (NSLog: Console.app, `log stream`,
// Instruments' os_log), Android's logcat (info, the tag given), the
// browser's console; elsewhere the standard error.
//
//   SystemLog.write("SHOPBENCH home_ready");
@:hxmc.unsafe(gc)
class SystemLog {
	public static function write(line:String, tag = "helder") {
		if (Platform.os() == Platform.MACOS) {
			var pool = Runtime.objc_autoreleasePoolPush();
			Foundation.NSLog(Msg.id(ObjC.str("%@"), ObjC.sel("autorelease")), Msg.id(ObjC.str(line), ObjC.sel("autorelease")));
			Runtime.objc_autoreleasePoolPop(pool);
		} else if (Platform.target() >= 9)
			Arena.scoped(a -> helder.os.android.Native.Log.__android_log_write(4, a.cstring(tag), a.cstring(line)));
		else if (Platform.os() == Platform.WASI)
			Arena.scoped(a -> helder.os.web.Dom.console_log(a.cstring(line)));
		else
			Sys.stderr().writeString(line + "\n");
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/Foundation.framework/Foundation") private extern class Foundation {
	// (variadic: the format's arguments as C's)
	@:hxmc.varargs(1) static function NSLog(format:Ptr, arg:Ptr):Void;
}
