package helder.view.graph;

import helder.async.Async;
import helder.async.Loop;
import helder.test.Test;
import helder.ui.ScreenContext;
import helder.view.graph.Graph.*;

final landed = signal(0);

// (a screen of its own store, f run in it)
function screen(name:String, f:Void->Void):{store:Atoms, context:ScreenContext} {
	var store = new Atoms(name), context = new ScreenContext(name, true, null, store);
	context.run(f);
	return {store: store, context: context};
}

// (the loop turned for that long, outside every screen)
function wait(seconds:Float) {
	var done = false;
	Async.launch(_ -> {
		Async.delay(seconds);
		done = true;
	});
	Loop.current().runUntil(() -> done);
}

// helder.async in stores (helder.async.Home): a task started in a screen
// runs there, its continuations, children and jobs' results too
function tests() {
	afterEach(() -> {
		landed(0);
		flush();
	});
	test("a task's continuation lands in its screen's store", () -> {
		var where = [];
		var s = screen("a", () -> Async.launch(_ -> {
			Async.delay(0.01);
			landed(5);
			where.push(ScreenContext.current.name);
		}));
		wait(0.03);
		flush();
		equals(where, ["a"]);
		equals([s.store.run(() -> landed.peek()), landed.peek()], [5, 0]);
		equals(helder.async.Home.current, null);
		s.store.dispose();
	});
	test("its children and two screens apart", () -> {
		var a = screen("a", () -> Async.launch(task -> task.async(_ -> {
			Async.delay(0.01);
			landed(1);
		})));
		var b = screen("b", () -> Async.launch(_ -> {
			Async.delay(0.02);
			landed(2);
		}));
		wait(0.04);
		flush();
		equals([a.store.run(() -> landed.peek()), b.store.run(() -> landed.peek()), landed.peek()], [1, 2, 0]);
		a.store.dispose();
		b.store.dispose();
	});
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	test("a job's result lands in its screen's store", () -> {
		var s = screen("a", () -> Async.launch(_ -> landed(helder.jobs.Jobs.job(AtomsAsyncWork.words).run("one two three"))));
		var n = 0;
		while (s.store.run(() -> landed.peek()) == 0 && n++ < 100) {
			wait(0.01);
			flush();
		}
		equals([s.store.run(() -> landed.peek()), landed.peek()], [3, 0]);
		s.store.dispose();
	});
	#end
	test("a store cleared or let go drops what was pending in it", () -> {
		var ran = 0;
		var a = screen("a", () -> Async.launch(_ -> {
			Async.delay(0.01);
			ran++;
		}));
		var b = screen("b", () -> Async.launch(_ -> {
			Async.delay(0.01);
			ran++;
		}));
		a.store.clear();
		b.store.dispose();
		wait(0.03);
		equals(ran, 0);
		// (what is started after a clear runs)
		a.context.run(() -> Async.launch(_ -> ran++));
		wait(0.01);
		equals(ran, 1);
		a.store.dispose();
	});
}

class AtomsAsyncWork {
	public static function words(s:String):Int
		return s.split(" ").length;
}
