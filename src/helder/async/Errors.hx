package helder.async;

import haxe.CallStack;
import haxe.Exception;
#if (target.name == "hxmc" && !macro && hxmc.target != "wasm32-wasi")
import hxmc.rt.Stacks;
import hxmc.unsafe.Mem;
#end

// The program's hook for errors nothing caught: an exception out of a frame
// or an event (helder.os.App.run, every platform), an error in a task nobody
// awaits or observes, a failed Async.main. The handler gets the error and
// where it came from ("frame", "event", "task", "main") and answers whether
// it was handled: then the program goes on (the frame or event abandoned
// where it threw), else it fails as without one (printed, exit code 1). An
// error in the handler itself counts as not handled.
//
//   helder.os.App.onError = (e, source) -> { show(e.message, e.stack); true; };
//
// helder's own catches that pass an error on throw it as kept (in the
// catch) or carried (later, or on another thread), so that it keeps where
// it was thrown: hxmc gives a value thrown again the stack of that throw,
// and reports an uncaught one where it was thrown last.
class Errors {
	public static var handler:Null<(error:Exception, source:String) -> Bool> = null;
	static var reporting = false;
	// (the last error carried, and the function that threw it: a catch above
	// makes a new exception of its value, its stack from there)
	static var last:Null<Exception> = null;
	static var lastAt:Null<StackItem> = null;

	// e handed to the handler: whether it was handled
	public static function report(e:Exception, source:String):Bool {
		var h = handler;
		if (h == null || reporting) return false;
		reporting = true;
		var handled = try h(origin(e), source) catch (_:Exception) false;
		reporting = false;
		return handled;
	}

	// f run, an error out of it reported (rethrown when not handled)
	public static inline function guard(f:Void->Void, source:String) {
		try f() catch (e:Exception) if (!report(e, source)) throw kept(e);
	}

	// e to throw on from the catch that caught it, its stack going on from
	// its throw: `throw Errors.kept(e)`
	public static function kept(e:Exception):Exception {
		#if (target.name == "hxmc" && !macro && hxmc.target != "wasm32-wasi")
		if (Native.uncaught()) fail(e, null);
		// (else a throw in the catch came between: thrown as carried throws)
		if (e.native != e && !Native.continues(e)) carry(e);
		#end
		return e;
	}

	// e, caught earlier or on another thread, to throw here: its stack kept,
	// and this one where it was thrown again
	public static function carried(e:Exception):Exception {
		#if (target.name == "hxmc" && !macro && hxmc.target != "wasm32-wasi")
		var here = CallStack.callStack();
		if (Native.uncaught()) fail(e, here);
		carry(e, here);
		#end
		return e;
	}

	// e's message and where it was thrown, then where it was thrown again
	// (again: that stack, the frames it shares with the one before left out)
	public static function text(e:Exception, ?again:CallStack):String {
		var stacks = [];
		var x = e;
		while (x != null) {
			stacks.unshift(x.stack);
			x = x.previous;
		}
		var o = origin(e);
		if (o != e) stacks.unshift(o.stack);
		if (again != null) stacks.push(again);
		var b = new StringBuf();
		b.add(e.message);
		var prev:Null<CallStack> = null;
		for (s in stacks) {
			var all = [for (i in s) if (!internal(i)) i], n = all.length;
			if (prev != null) {
				var m = prev.length;
				while (n > 0 && m > 0 && Type.enumEq(all[n - 1], prev[m - 1])) {
					n--;
					m--;
				}
				if (n == 0) continue;
				b.add("\nRethrown at:");
			}
			b.add(CallStack.toString(all.slice(0, n)));
			prev = all;
		}
		return b.toString();
	}

	// (printed as hxmc prints an uncaught exception)
	static function fail(e:Exception, again:Null<CallStack>) {
		Sys.stderr().writeString("Uncaught exception: " + text(e, again) + "\n");
		Sys.exit(1);
	}

	static function carry(e:Exception, ?here:CallStack) {
		// (carried again: the first one's stack is where it was thrown)
		last = origin(e);
		lastAt = null;
		for (i in here ?? CallStack.callStack())
			if (!internal(i)) {
				lastAt = i;
				break;
			}
	}

	// the exception carried that e is a value of, if it is one
	static function origin(e:Exception):Exception {
		var c = last;
		if (c == null || c == e || c.native != e.native || e.stack.length == 0) return e;
		return switch [e.stack[0], lastAt] {
			case [FilePos(a, file, _, _), FilePos(b, f, _, _)] if (file == f && Type.enumEq(a, b)): c;
			case _: e;
		}
	}

	static function internal(i:StackItem):Bool
		return switch i {
			case FilePos(Method("helder.async.Errors", _), _, _, _): true;
			case _: false;
		}
}

#if (target.name == "hxmc" && !macro && hxmc.target != "wasm32-wasi")
// hxmc's runtime: its innermost try's handler, its record of the last throw
// (hxmc.rt.Stacks.rethrowing: what its interpreter sets for a catch that
// passes an exception on)
@:hxmc.unsafe(gc) @:access(hxmc.rt.Gc) @:access(hxmc.rt.Stacks) @:access(haxe.Exception)
private class Native {
	// whether no try catches what is thrown now
	public static function uncaught():Bool
		return hxmc.rt.Gc.hcur.isNull();

	// the next throw's stack going on from e's throw, if that is still the
	// thread's last and the frame that caught it is live: whether it does
	public static function continues(e:Exception):Bool {
		var b:Null<haxe.io.Bytes> = e.__nativeStack;
		var t = Stacks.thrown, n = Stacks.thrownLen, top = Stacks.thrownTop;
		if (b == null || t.isNull() || top.isNull() || n == 0 || b.length < 8 * n) return false;
		for (i in 0...2 * n)
			if (Mem.getI32(t, 4 * i) != b.getInt32(4 * i)) return false;
		// (as Stacks.lastThrowInto finds it)
		var f = Mem.frame();
		while (!f.isNull() && f.ult(top) && (f.toI64() & 7) == 0 && Stacks.known(Mem.getPtr(f, 8)))
			f = Stacks.callerOf(f, Mem.getPtr(f, 8));
		if (f != top) return false;
		Stacks.rethrowing = true;
		return true;
	}
}
#end
