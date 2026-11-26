package helder.async;

import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import helder.view.graph.Atoms;

// A task's home, its dispatcher: a preview host's screen (helder.ui.ScreenContext)
// with a store of values of its own (helder.view.graph.Atoms). A task
// started while it is current takes it, and so do the task's children: its
// body, every continuation, timer and job's result run in that store and
// context, as TypeScript's timers and promises do. Once the store is
// cleared or let go, what is still pending there is dropped.
class Home extends Dispatcher {
	// the screen running now (ScreenContext sets it while one with a store is current)
	@:noCompletion public static var current:Null<Home> = null;

	final loop:Loop;
	final store:Atoms;
	final generation:Int;
	final enter:(Void->Void)->Void;

	// enter: f run in the screen (its context current)
	public function new(store:Atoms, enter:(Void->Void)->Void) {
		loop = Loop.current();
		this.store = store;
		generation = store.generation;
		this.enter = enter;
	}

	// whether its store is still as it was when it was made
	public inline function live():Bool
		return Atoms.live(store, generation);

	function get_scheduler():IScheduler
		return loop;

	public function dispatch(obj:IDispatchObject)
		if (live()) loop.dispatch(new Homed(this, obj));
}

private class Homed implements IDispatchObject {
	final home:Home;
	final obj:IDispatchObject;

	public function new(home, obj) {
		this.home = home;
		this.obj = obj;
	}

	public function onDispatch()
		if (home.live()) @:privateAccess home.enter(obj.onDispatch);
}
