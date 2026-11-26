package helder.typescript.js;

import haxe.io.Bytes;
import hxmc.rt.Stacks;

// The frames of an error's stack, as V8 writes them: `at f (file:line:column)`
// for each frame of the program's own functions, innermost first, then the
// async functions awaiting (Async.awaits). An error keeps its native stack
// when made (the return addresses: cheap) and is written when its stack is
// first read; the program's frames are named by hxmc's table of lines, the
// lowering's positions in it (Lines). The runtime's frames are left out, and
// a run of helder's between two of the program's is one `at <helder>` (a
// callback helder's API called). Without the table (WebAssembly) a frame
// is where the last `new` or `throw` ran (site).
class Frames {
	// (V8's Error.stackTraceLimit, its default)
	public static inline var MAX = 10;
	public static var site:Null<String> = null;

	public static function capture():Bytes
		return haxe.NativeStackTrace.callStack();

	// the last throw's (in the catch that caught it)
	public static function thrown():Bytes
		return haxe.NativeStackTrace.exceptionStack();

	public static function text(raw:Null<Bytes>, at:Null<String>, awaits:Null<Array<String>>, limit:Int):String {
		var b = new StringBuf(), n = 0;
		function frame(s:String) {
			if (n++ >= limit) return;
			b.add("\n    at ");
			b.add(s);
		}
		var api = false, k = 0;
		if (raw != null) while (k < raw.length >> 3 && n < limit) {
			var d = Stacks.frame(raw, k);
			k = Stacks.frameEnd(raw, k);
			if (d == null || d.file == null) continue;
			if (!Lines.typescript(d.file)) {
				if (d.name != null && StringTools.startsWith(d.name, "helder.") && !StringTools.startsWith(d.name, "helder.typescript.")
					&& !StringTools.startsWith(d.name, "helder.async.Errors"))
					api = true;
				continue;
			}
			if (api && n > 0) frame("<helder>");
			api = false;
			frame((d.name ?? "<anonymous>") + " (" + d.file + ":" + Lines.line(d.line) + ":" + Lines.column(d.line) + ")");
		}
		if (n == 0 && at != null) frame(at);
		if (awaits != null) for (a in awaits) frame(a);
		return b.toString();
	}
}
