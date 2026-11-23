package helder.os;

// haxe.EventLoop in App.run's turns: haxe.Timer's and MainLoop's events
// would run only once main returned, and App.run's main does not (in the
// browser it returns before the first frame). Installed by App only in a
// program that makes a haxe.Timer (@:ifFeature): the loop brings its
// threads' locks and maps, a fifth of a small program.
class HaxeLoop {
	public static function install():Bool {
		@:privateAccess App.eventTurn = () -> haxe.EventLoop.main.loopOnce(false);
		@:privateAccess App.eventNext = () -> @:privateAccess haxe.EventLoop.main.getNextTick();
		#if target.threaded
		// (on the program's thread while it runs; an empty one at its end, which the thread's end runs)
		@:privateAccess App.eventAdopt = on -> @:privateAccess haxe.EventLoop.eventsTls.value = on ? haxe.EventLoop.main : new haxe.EventLoop();
		#end
		return true;
	}
}
