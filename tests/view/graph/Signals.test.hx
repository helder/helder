package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// createSignal.test.ts
function tests() {
	Stores.hooks();
	afterEach(() -> flush());

	test("should store and return value on read", () -> {
		var x = signal(1);
		equals(x(), 1);
	});

	test("should update signal via setter", () -> {
		var x = signal(1);
		x(2);
		equals(x(), 1);
		flush();
		equals(x(), 2);
	});

	test("should update signal via update function", () -> {
		var x = signal(1);
		x(n -> n + 1);
		equals(x(), 1);
		flush();
		equals(x(), 2);
	});

	test("should accept equals option", () -> {
		// skip even numbers
		var x = signal(1, {equals: (prev, next) -> prev + 1 == next});
		x(11);
		equals(x(), 1);
		flush();
		equals(x(), 11);
		x(12);
		flush();
		equals(x(), 11);
		x(13);
		flush();
		equals(x(), 13);
		x(14);
		flush();
		equals(x(), 13);
	});

	test("should create signal derived from another signal", () -> {
		var x = signal(1);
		var y = signal(() -> x() + 1);
		equals(y(), 2);
		y(1);
		flush();
		equals(y(), 1);
		x(2);
		flush();
		equals(y(), 3);
	});

	test("should call unobserved callback when subscriber is disposed", () -> {
		var unobserved = new Spy();
		var x = signal(1, {unobserved: unobserved.fn0()});
		var disposer = root(dispose -> {
			memo(() -> x());
			dispose;
		});
		equals(unobserved.calls, 0);
		disposer();
		equals(unobserved.calls, 1);
		x(2);
		flush();
		equals(unobserved.calls, 1);
	});

	test("should call unobserved callback when signal is unobserved", () -> {
		var unobserved = new Spy();
		var x = signal(true);
		var y = signal(1, {unobserved: unobserved.fn0()});
		root(_ -> {
			memo(() -> x() ? y() : null);
		});
		equals(unobserved.calls, 0);
		x(false);
		flush();
		equals(unobserved.calls, 1);
	});

	// (helder's, Solid 2.0.4's answers: a free memo nothing observes lets go
	// of its sources, each told though one's callback throws, the first error
	// after; found by Jotai's tests, src/helder/view/graph/AtomsJotai.test.hx)
	test("unobserved through a free memo, one callback throwing", () -> {
		var log = [];
		var a = signal(0, {unobserved: () -> log.push("a")});
		var b = signal(0, {
			unobserved: () -> {
				log.push("b throws");
				throw "b";
			}
		});
		var d = memo(() -> {
			b();
			a();
		});
		var dispose = root(stop -> {
			effect(_ -> d(), (_, _) -> {});
			stop;
		});
		flush();
		try {
			dispose();
			flush();
		} catch (e:haxe.Exception) log.push('threw ${e.message}');
		equals(log, ["b throws", "a", "threw b"]);
	});

	test("a free memo observed again takes its sources back", () -> {
		var x = signal(1), d = memo(() -> x() * 2), seen = [];
		var dispose = root(stop -> {
			effect(_ -> d(), (v, _) -> seen.push(v));
			stop;
		});
		flush();
		dispose();
		flush();
		root(_ -> effect(_ -> d(), (v, _) -> seen.push(v)));
		flush();
		x(2);
		flush();
		equals(seen, [2, 2, 4]);
	});
}
