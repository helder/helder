package helder.view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// (made at the module's top level: the default store their home)
final count = signal(0);
final double = memo(() -> count() * 2);
// (an answer each store asks for: the first answered by hand, the next never)
final loads:Array<Later<Int>> = [];
final slow = memo(() -> {
	var l = new Later<Int>();
	if (count() == 0) l.resolve(0) else loads.push(l);
	l;
});

// atoms in stores (Jotai's): each store its own nodes of them, the default
// the atoms themselves; one graph, a flush's transactions a store each
function tests() {
	test("a store's writes, unseen by another and the default", () -> {
		var a = new Atoms("a"), b = new Atoms("b");
		a.run(() -> count(3));
		flush();
		equals([a.run(() -> count()), b.run(() -> count()), count()], [3, 0, 0]);
		count(1);
		flush();
		equals([a.run(() -> count()), b.run(() -> count()), count()], [3, 0, 1]);
		count(0);
		flush();
		a.dispose();
		b.dispose();
	});
	test("a memo a store's, computed from its nodes", () -> {
		var a = new Atoms("a"), b = new Atoms("b");
		var shown = [];
		a.run(() -> root(_ -> renderEffect(() -> double(), v -> shown.push(v))));
		flush();
		a.run(() -> count(5));
		flush();
		equals(shown, [0, 10]);
		equals([a.run(() -> double()), b.run(() -> double()), double()], [10, 0, 0]);
		a.dispose();
		b.dispose();
	});
	test("one store held on its async, another's write in the same flush committed", () -> {
		var a = new Atoms("a"), b = new Atoms("b");
		var inA = [], inB = [];
		a.run(() -> root(_ -> renderEffect(() -> '${count()}:${slow()}', v -> inA.push(v))));
		b.run(() -> root(_ -> renderEffect(() -> count(), v -> inB.push(v))));
		flush();
		a.run(() -> count(1));
		b.run(() -> count(1));
		flush();
		equals(inA, ["0:0"]);
		equals(inB, [0, 1]);
		equals([a.run(() -> count.peek()), b.run(() -> count.peek())], [0, 1]);
		a.dispose();
		b.dispose();
	});
	test("a signal made in a store: its home there, the default seeing through to it", () -> {
		var a = new Atoms("a"), b = new Atoms("b");
		var local = a.run(() -> signal(1));
		local(2);
		flush();
		equals([local(), a.run(() -> local()), b.run(() -> local())], [2, 2, 1]);
		a.dispose();
		b.dispose();
	});
	test("a top-level effect run in each store", () -> {
		var seen = [];
		effect(() -> count(), (v, _) -> {
			seen.push(v);
			null;
		});
		flush();
		var a = new Atoms("a");
		flush();
		a.run(() -> count(4));
		flush();
		equals(seen, [0, 0, 4]);
		a.dispose();
	});
}
