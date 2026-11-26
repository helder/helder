package helder.ui;

import helder.test.Gen;
import helder.test.Test;
import helder.view.graph.Graph;

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
	test("a selection against a set: selects, toggles, extends, prunes and lists changed", () -> stateful({
		setup: () -> new Model(),
		steps: [
			{name: "select", run: (m, c) -> m.select(c.draw(int(0, 11)))},
			{name: "toggle", run: (m, c) -> m.toggle(c.draw(int(0, 11)))},
			{name: "extend", run: (m, c) -> m.extend(c.draw(int(0, 11)))},
			{name: "select all", run: (m, c) -> m.selectAll()},
			{name: "clear", run: (m, c) -> m.clear()},
			{name: "set keys", run: (m, c) -> m.setKeys(c.draw(array(pick(POOL), 0, 4)), c.draw(bool()))},
			{name: "prune", run: (m, c) -> m.prune()},
			{name: "move focus", run: (m, c) -> m.moveFocus(c.draw(int(0, 11)))},
			{name: "list", run: (m, c) -> m.list(c.draw(array(pick(POOL), 0, 12)))}
		],
		check: m -> m.check()
	}, {cases: 150, steps: 30}));
}

private final POOL = [for (k in 0...12) String.fromCharCode(97 + k)];

// (the selection's model: a set, its anchor and focus, the set a Shift range grows over)
private class Model {
	var items = ["a", "b", "c", "d", "e", "f"];
	final real:Selection;
	var sel = new Map<String, Bool>();
	var anchor:Null<String> = null;
	var focus:Null<String> = null;
	var base:Null<Map<String, Bool>> = null;
	var version = 0;
	var changed = false;

	public function new()
		real = new Selection(i -> items[i], () -> items.length);

	public function select(i:Int) {
		real.select(i);
		if (i >= items.length) return;
		set([items[i] => true], items[i], items[i]);
	}

	public function toggle(i:Int) {
		real.toggle(i);
		if (i >= items.length) return;
		var k = items[i];
		if (!sel.remove(k)) sel.set(k, true);
		anchor = focus = k;
		base = null;
		changed = true;
	}

	public function extend(i:Int) {
		real.extend(i);
		if (i >= items.length) return;
		var from = items.indexOf(anchor);
		if (from < 0) from = items.indexOf(focus);
		if (from < 0) from = i;
		if (base == null) base = sel.copy();
		var next = base.copy();
		for (j in (from < i ? from : i)...(from > i ? from : i) + 1)
			next.set(items[j], true);
		var keep = base;
		set(next, items[from], items[i]);
		base = keep;
	}

	public function selectAll() {
		real.selectAll();
		set([for (k in items) k => true], anchor, focus);
	}

	public function clear() {
		real.clear();
		set(new Map(), null, null);
	}

	public function setKeys(keys:Array<String>, additive:Bool) {
		real.setKeys(keys, additive);
		var next = additive ? sel.copy() : new Map();
		for (k in keys)
			next.set(k, true);
		set(next, anchor, focus);
	}

	public function prune() {
		real.prune();
		var next = [for (k in sel.keys()) if (items.contains(k)) k => true];
		var keep = base == null ? null : [for (k in base.keys()) if (items.contains(k)) k => true];
		set(next, items.contains(anchor) ? anchor : null, items.contains(focus) ? focus : null);
		base = keep;
	}

	public function moveFocus(i:Int) {
		@:privateAccess real.moveFocus(i);
		if (i >= items.length || focus == items[i]) return;
		focus = items[i];
		changed = true;
	}

	public function list(keys:Array<String>) {
		var next = [];
		for (k in keys)
			if (!next.contains(k)) next.push(k);
		items = next;
	}

	public function check() {
		equals(real.keys(), [for (k in items) if (sel.exists(k)) k], "keys");
		equals(real.size(), Lambda.count(sel), "size");
		equals(real.anchor, anchor, "anchor");
		equals(real.focus, focus, "focus");
		equals(real.focusIndex(), items.indexOf(focus), "focusIndex");
		Graph.flush();
		if (changed) version++;
		changed = false;
		equals(real.version.peek(), version, "version: bumped once a change");
	}

	function set(next:Map<String, Bool>, a:Null<String>, f:Null<String>) {
		var same = a == anchor && f == focus && Lambda.count(next) == Lambda.count(sel);
		for (k in next.keys())
			if (!sel.exists(k)) same = false;
		if (!same) changed = true;
		sel = next;
		anchor = a;
		focus = f;
		base = null;
	}
}
