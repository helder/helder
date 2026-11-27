package helder.typescript.js;

import helder.typescript.js.Values;

// An object's own properties beyond a typed class's fields: their keys in
// insertion order, each the slot of its value in the object's `slots`, and
// their attributes (Values.Attr). Objects given the same keys in the same
// order with the same attributes share a shape (V8's maps, JSC's
// structures), each made once from its parent by a transition, so a site
// that read a property of one reads it of the others by comparing shapes
// (Sites). A key is its string: hxmc's strings keep their hash, and ==
// compares their addresses and lengths first.
//
// A dictionary shape is an object's own, changed in place (an object of
// many keys, or one a key was deleted from, as V8's): sites never cache
// one. Its deleted keys stay as null slots until they are many.
class Shape {
	public final parent:Null<Shape>;
	// (the root it grew from: which kind of object it is a shape of)
	public final root:Shape;
	// (a dictionary's: the root of the shapes it came from)
	public var base:Null<Shape> = null;
	// (a typed class's instances': their fields, Layout.root's descendants')
	public final layout:Null<Layout>;
	public final keys:Array<Null<String>>;
	public final attrs:Array<Int>;
	public final dict:Bool;
	// (every property an enumerable, writable, configurable data property of a
	// string key: what a spread copies as it is)
	public final plain:Bool;
	// (its keys the program does not see: Attr.PRIVATE's)
	var secret:Int;
	// (a lookup table: a shape of many keys, a dictionary's)
	var index:Null<Map<String, Int>> = null;
	var deleted = 0;
	// (an index among its keys, so its keys' order is not OwnPropertyKeys': 0 not known yet, 1 no, 2 yes)
	var indexes = 0;
	// (its children: the first inline, the others by key and attributes)
	var nextKey:Null<String> = null;
	var nextAttr = 0;
	var next:Null<Shape> = null;
	var nexts:Null<Map<String, Shape>> = null;
	var children = 0;

	static inline var SCAN = 8;

	public function new(parent:Null<Shape>, keys:Array<Null<String>>, attrs:Array<Int>, dict:Bool, plain:Bool, ?layout:Layout) {
		this.parent = parent;
		root = parent == null ? this : parent.root;
		this.layout = parent == null ? layout : parent.layout;
		this.keys = keys;
		this.attrs = attrs;
		this.dict = dict;
		this.plain = plain;
		secret = parent == null ? 0 : parent.secret;
		if (!dict && attrs.length > 0 && attrs[attrs.length - 1] & Attr.PRIVATE != 0) secret++;
	}

	public function indexed():Bool {
		if (indexes == 0) indexes = Lambda.exists(keys, k -> k != null && Lib.index(k) >= 0) ? 2 : 1;
		return indexes == 2;
	}

	// (the number of slots, deleted ones included)
	public inline function size():Int return keys.length;

	public function slotOf(k:String):Int {
		if (index != null) {
			var i = index.get(k);
			return i == null ? -1 : i;
		}
		var n = keys.length;
		if (n > SCAN) {
			index = [];
			for (i in 0...n) if (keys[i] != null) index.set(keys[i], i);
			return slotOf(k);
		}
		for (i in 0...n) if (keys[i] == k) return i;
		return -1;
	}

	// the shape with one more key, or null where an object goes to a
	// dictionary (bounded: a key the program's text does not name, whose
	// shapes are bounded by their number of children)
	public function with(k:String, attr:Int, limit:Int, bounded:Bool):Null<Shape> {
		if (nextKey == k && nextAttr == attr && next != null) return next;
		var tag = attr == 0 ? k : k + "\x00" + attr;
		if (nexts != null && nexts.exists(tag)) return nexts.get(tag);
		if (keys.length >= limit || bounded && children >= (parent == null ? Shapes.ROOT_CHILDREN : Shapes.CHILDREN)) return null;
		var s = new Shape(this, keys.concat([k]), attrs.concat([attr]), false, plain && attr == 0 && !Symbols.isSymbolKey(k));
		children++;
		if (next == null) {
			nextKey = k;
			nextAttr = attr;
			next = s;
		}
		else {
			if (nexts == null) nexts = [];
			nexts.set(tag, s);
		}
		return s;
	}

	// a dictionary of the same keys, its own
	public function dictionary():Shape {
		var d = new Shape(null, keys.copy(), attrs.copy(), true, false, layout);
		d.base = root;
		d.deleted = deleted;
		d.secret = secret;
		return d;
	}

	// (a dictionary's changes, in place)
	public function add(k:String, attr:Int):Void {
		if (index != null) index.set(k, keys.length);
		keys.push(k);
		attrs.push(attr);
		if (attr & Attr.PRIVATE != 0) secret++;
	}

	public function delete(i:Int):Void {
		if (index != null) index.remove(keys[i]);
		keys[i] = null;
		if (attrs[i] & Attr.PRIVATE != 0) secret--;
		deleted++;
	}

	// (a dictionary's slots, deleted ones dropped, when they are half: the values' order with them)
	public function compact(values:Array<Dynamic>):Bool {
		if (deleted < 8 || deleted * 2 < keys.length) return false;
		var j = 0;
		for (i in 0...keys.length) if (keys[i] != null) {
			keys[j] = keys[i];
			attrs[j] = attrs[i];
			values[j] = values[i];
			j++;
		}
		keys.resize(j);
		attrs.resize(j);
		values.resize(j);
		deleted = 0;
		index = null;
		return true;
	}

	// its keys in order (null without any)
	public function names():Null<Array<String>> {
		if (keys.length == 0) return null;
		if (deleted == 0 && secret == 0) return cast keys;
		var out = [for (i in 0...keys.length) if (keys[i] != null && attrs[i] & Attr.PRIVATE == 0) keys[i]];
		return out.length == 0 ? null : out;
	}
}

class Shapes {
	// (a site's shape before it has one: no object's)
	public static final none = new Shape(null, [], [], false, true);
	// the roots: ordinary objects, and those with own properties of their
	// own (an array's elements and length, a function's name, length and
	// prototype, a typed array's elements), so a shape says which an object is
	public static final object = root();
	public static final array = root();
	public static final func = root();
	public static final typed = root();
	// (a primitive receiver's, at a site: no object's)
	public static final string = root();
	public static final number = root();
	public static final boolean = root();
	// (changed whenever an object a site read through, a prototype, changes
	// its keys or its prototype: the sites' records of what they found
	// beyond the receiver hold while it is the same)
	public static var epoch = 0;

	// (an object of more keys is a dictionary; one given keys by computed
	// names sooner: an object used as a map, V8's limit for keyed stores)
	public static inline var KEYS = 128;
	public static inline var KEYED = 32;
	// (a shape with more children: objects built from it in many ways, a map's keys)
	public static inline var CHILDREN = 64;
	public static inline var ROOT_CHILDREN = 1024;

	public static function root(?layout:Layout):Shape return new Shape(null, [], [], false, true, layout);

	// an object literal's final shape: its keys in order (distinct, from ordinary objects' root)
	public static function literal(keys:Array<String>):Shape {
		var s = object;
		for (k in keys) {
			var n = s.with(k, 0, KEYS, false);
			if (n == null) return null;
			s = n;
		}
		return s;
	}

	// the shape of these keys with these attributes from a root, else null
	public static function replay(root:Shape, keys:Array<Null<String>>, attrs:Array<Int>):Null<Shape> {
		var s = root;
		for (i in 0...keys.length) {
			s = s.with(keys[i], attrs[i], KEYS, true);
			if (s == null) return null;
		}
		return s;
	}

	// (from x's prototype to holder, or to the end: x's lookups through them recorded)
	public static function watch(from:Null<JsObject>, holder:Null<JsObject>):Void {
		var p = from;
		while (p != null) {
			p.watched = true;
			if (p == holder) return;
			p = p.proto;
		}
	}
}
