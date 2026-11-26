package helder.async;

import haxe.io.Bytes;

// A child that ends with its parent, however the parent ends (SIGKILL
// too): the parent gives it a pipe for stdin that it never writes to and
// ENV=1 in its environment; the child reads its stdin to its end, which
// comes when the pipe's last writer is gone (the parent's descriptors
// closed by the system), then ends itself. The same on every system, no
// signal forwarded (a SIGKILL reaches no handler).
//
//   if (Parent.piped()) Async.launch(_ -> Parent.watch(() -> Sys.exit(0)));
class Parent {
	public static inline var ENV = "HELDER_EXIT_WITH_STDIN";

	// whether this process was started so (the variable taken out of its
	// environment: a child of its own is told by its own pipe, or not at all)
	public static function piped():Bool {
		var on = Sys.getEnv(ENV) == "1";
		if (on) Sys.putEnv(ENV, null);
		return on;
	}

	// a child's environment with ENV in it (its stdin to be kept open, never written)
	public static function env(?base:Map<String, String>):Map<String, String> {
		var e = base ?? Process.environment();
		e.set(ENV, "1");
		return e;
	}

	// stdin read to its end (the parent gone), then gone()
	@:coroutine public static function watch(gone:Void->Void) {
		var s = Process.input(), b = Bytes.alloc(256);
		try while (s.read(b, 0, b.length) > 0) {} catch (_:haxe.Exception) {}
		gone();
	}
}
