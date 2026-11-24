package helder.ui;

import helder.test.Test;
import helder.view.graph.Graph;

@:test.interp
function tests() {
	test("selection keys survive a reorder, a filter and new items", () -> {
		var items = ["a", "b", "c", "d", "e", "f"];
		var s = new Selection(i -> items[i], () -> items.length);
		s.select(0);
		s.toggle(2);
		s.extend(5);
		equals(s.keys(), ["a", "c", "d", "e", "f"]);
		s.extend(3);
		equals(s.keys(), ["a", "c", "d"]);
		s.extend(1);
		equals(s.keys(), ["a", "b", "c"]);
		equals(s.anchor, "c");
		equals(s.focus, "b");
		Graph.flush();
		equals(s.version.peek(), 5);
		items = ["c", "b", "a", "g"];
		equals(s.keys(), ["c", "b", "a"]);
		s.toggle(0);
		items = ["a", "g", "b"];
		equals(s.focusIndex(), -1);
		equals(s.size(), 2);
		s.prune();
		equals(s.focus, null);
		equals(s.anchor, null);
		s.selectAll();
		equals(s.keys(), ["a", "g", "b"]);
		s.clear();
		equals(s.size(), 0);
		s.setKeys(["b", "missing", "b"]);
		s.setKeys(["a"], true);
		equals(s.size(), 3);
		equals(s.keys(), ["a", "b"]);
		s.prune();
		equals(s.size(), 2);
	});
	test("pruned keys stay out of an extension when they return", () -> {
		var items = ["a", "b", "c", "d", "e"];
		var s = new Selection(i -> items[i], () -> items.length);
		s.select(0);
		s.toggle(2);
		s.extend(4);
		items = ["b", "c", "d", "e"];
		s.prune();
		items = ["a", "b", "c", "d", "e"];
		s.extend(3);
		equals(s.keys(), ["c", "d"]);
	});

}
