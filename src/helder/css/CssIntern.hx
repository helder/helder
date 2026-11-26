package helder.css;

import haxe.ds.ObjectMap;
import helder.css.CssTerm;

// A document's interned values and groups: equal ones are one object, so
// groups compare their fields by identity and styles share groups.
class CssIntern {
	final lengths = new Map<String, CssLength>();
	final rgbas = new Map<String, CssRgba>();
	final displays = new Map<String, CssDisplay>();
	final lists = new Map<String, Array<CssTerm>>();
	final listIds = new ObjectMap<Array<CssTerm>, Int>();
	final groups:Array<Map<Int, Array<CssGroup>>> = [for (_ in 0...CssGroups.COUNT) new Map()];
	// (distinct groups, per group)
	public final counts:Array<Int> = [for (_ in 0...CssGroups.COUNT) 0];
	var values = 0;

	public function new() {}

	// (a lossless key: the terms' structure, numbers in full)
	public static function key(t:Array<CssTerm>):String
		return Std.string(t);

	public function length(t:Array<CssTerm>):Null<CssLength> {
		var k = key(t);
		var v = lengths.get(k);
		if (v != null) return v;
		v = CssLength.of(t);
		if (v == null) return null;
		v.id = values++;
		lengths.set(k, v);
		return v;
	}

	public function rgba(t:Array<CssTerm>):Null<CssRgba> {
		var k = key(t);
		var v = rgbas.get(k);
		if (v != null) return v;
		v = CssRgba.of(t);
		if (v == null) return null;
		v.id = values++;
		rgbas.set(k, v);
		return v;
	}

	public function display(t:Array<CssTerm>):CssDisplay {
		var k = key(t);
		var v = displays.get(k);
		if (v != null) return v;
		v = CssDisplay.of(t);
		v.id = values++;
		displays.set(k, v);
		return v;
	}

	public function terms(t:Array<CssTerm>):Array<CssTerm> {
		if (listIds.exists(t)) return t;
		var k = key(t);
		var v = lists.get(k);
		if (v != null) return v;
		lists.set(k, t);
		listIds.set(t, values++);
		return t;
	}

	public inline function id(t:Array<CssTerm>):Int
		return listIds.get(t) ?? -1;

	// The group interned: an equal one made before, or this one, now fixed.
	public function group(index:Int, g:CssGroup):CssGroup {
		if (g.id >= 0) return g;
		var h = @:privateAccess g.hash(this);
		var bucket = groups[index].get(h);
		if (bucket == null) groups[index].set(h, bucket = []);
		for (x in bucket) if (@:privateAccess x.same(g)) return x;
		g.id = values++;
		bucket.push(g);
		counts[index]++;
		return g;
	}
}
