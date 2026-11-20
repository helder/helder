package helder.os;

import helder.async.Async;
import helder.async.Loop;

// A coroutine waiting for what the system answers later, on whichever
// thread (a completion handler's queue, Java's main thread, a promise):
// start gets the function to call with it, which resumes the coroutine on
// its own loop, held meanwhile.
class Await {
	@:coroutine @:allow(helder.os) static function answer<T>(start:(T->Void)->Void):T {
		var loop = Loop.current();
		return Async.suspend(cont -> {
			var done = false;
			loop.hold();
			start(v -> loop.post(() -> {
				if (done) return;
				done = true;
				loop.release();
				cont.resume(v, null);
			}));
		});
	}
}
