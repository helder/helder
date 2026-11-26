package helder.async;

// helder.async for code that has no coroutines (a TypeScript program,
// helder/async's delay): each a task started now on this thread's loop,
// which TypeScript awaits as a promise (cancelling the promise cancels it).
// Haxe's is Async.delay.
@:noCompletion class Tasks {
	// done after that many seconds
	public static function delay(seconds:Float):Task<Any>
		return Async.launch(@:coroutine function(_) {
			Async.delay(seconds);
			return null;
		});
}
