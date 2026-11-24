package helder.ui;

import haxe.ds.StringMap;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A list's selection by key. The range of a Shift gesture is replaced
// as it grows or shrinks, over the selection made before that gesture.
class Selection {
	public var anchor(default, null):Null<String>;
	public var focus(default, null):Null<String>;
	public final version:Signal<Int> = Graph.signal(0);

	@:allow(helder.ui) final keyOf:Int->String;
	final count:Void->Int;
	var selected = new StringMap<Bool>();
	var base:Null<StringMap<Bool>>;
	var total = 0;
	var revision = 0;
	var at = -1;

	public function new(keyOf:Int->String, count:Void->Int) {
		this.keyOf = keyOf;
		this.count = count;
	}

	public function has(key:String):Bool
		return selected.exists(key);

	public function size():Int
		return total;

	// The keys present in the list, in its current order.
	public function keys():Array<String>
		return [for (i in indices()) keyOf(i)];

	public function focusIndex():Int {
		if (focus == null) return -1;
		if (!valid(at) || keyOf(at) != focus) at = indexOf(focus);
		return at;
	}

	public function select(i:Int) {
		if (!valid(i)) return;
		var k = keyOf(i), next = new StringMap<Bool>();
		next.set(k, true);
		replace(next, 1, k, k);
		at = i;
	}

	public function toggle(i:Int) {
		if (!valid(i)) return;
		var k = keyOf(i);
		if (selected.remove(k)) total-- else {
			selected.set(k, true);
			total++;
		}
		anchor = focus = k;
		at = i;
		base = null;
		bump();
	}

	public function extend(i:Int) {
		if (!valid(i)) return;
		var from = indexOf(anchor);
		if (from < 0) {
			from = focusIndex();
			if (from < 0) from = i;
		}
		if (base == null) base = selected.copy();
		var next = base.copy(), n = length(base);
		for (j in (from < i ? from : i)...((from > i ? from : i) + 1)) {
			var k = keyOf(j);
			if (!next.exists(k)) {
				next.set(k, true);
				n++;
			}
		}
		replace(next, n, keyOf(from), keyOf(i), true);
		at = i;
	}

	public function selectAll() {
		var next = new StringMap<Bool>();
		for (i in 0...count())
			next.set(keyOf(i), true);
		replace(next, length(next), anchor, focus);
	}

	public function clear()
		replace(new StringMap<Bool>(), 0, null, null);

	public function setKeys(keys:Array<String>, additive = false) {
		var next = additive ? selected.copy() : new StringMap<Bool>();
		for (k in keys)
			next.set(k, true);
		replace(next, length(next), anchor, focus);
	}

	public function prune() {
		var live = new StringMap<Bool>();
		for (i in 0...count())
			live.set(keyOf(i), true);
		var next = new StringMap<Bool>();
		for (k in selected.keys())
			if (live.exists(k)) next.set(k, true);
		if (base != null) {
			var kept = new StringMap<Bool>();
			for (k in base.keys())
				if (live.exists(k)) kept.set(k, true);
			base = kept;
		}
		replace(next, length(next), anchor != null && live.exists(anchor) ? anchor : null, focus != null && live.exists(focus) ? focus : null, base != null);
	}

	@:allow(helder.ui) function moveFocus(i:Int) {
		if (!valid(i)) return;
		var k = keyOf(i);
		if (focus == k) return;
		focus = k;
		at = i;
		bump();
	}

	@:allow(helder.ui) function indices():Array<Int>
		return total == 0 ? [] : [for (i in 0...count()) if (has(keyOf(i))) i];

	// (a marquee keeps even its starting keys that are filtered out)
	@:allow(helder.ui) function retainedKeys():Array<String>
		return [for (k in selected.keys()) k];

	function replace(next:StringMap<Bool>, n:Int, a:Null<String>, f:Null<String>, range = false) {
		if (!range) base = null;
		var changed = n != total || a != anchor || f != focus;
		if (!changed)
			for (k in next.keys())
				if (!has(k)) {
					changed = true;
					break;
				}
		if (!changed) return;
		selected = next;
		total = n;
		anchor = a;
		focus = f;
		bump();
	}

	function valid(i:Int):Bool
		return i >= 0 && i < count();

	function indexOf(key:Null<String>):Int {
		if (key != null)
			for (i in 0...count())
				if (keyOf(i) == key) return i;
		return -1;
	}

	function bump()
		version(++revision);

	static function length(keys:StringMap<Bool>):Int {
		var n = 0;
		for (_ in keys.keys())
			n++;
		return n;
	}
}
