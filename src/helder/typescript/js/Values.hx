package helder.typescript.js;

import helder.typescript.js.Shapes;

// JavaScript values: undefined is Seed.undefinedValue, null is null, numbers
// are Float, strings String, booleans Bool; everything else is a JsObject.
class Hole {
	public function new() {}
}

class Accessor {
	public var getter:Dynamic;
	public var setter:Dynamic;
	public function new(getter:Dynamic, setter:Dynamic) {
		this.getter = getter;
		this.setter = setter;
	}
}

// Property attributes other than the default (enumerable, writable, configurable).
class Attr {
	public static inline var HIDDEN = 1;
	public static inline var READONLY = 2;
	public static inline var LOCKED = 4;
	// (in a shape: the value is an Accessor; a class-private element's, or
	// another key the program does not see: JsObject.attr leaves them out)
	public static inline var ACCESSOR = 8;
	public static inline var PRIVATE = 16;
	// (a frozen built-in's member, Builtins.freeze: not written, redefined or
	// deleted; unlike READONLY it does not stop an object inheriting it from
	// having one of its own)
	public static inline var FROZEN = 32;
}

// What an object is, for the property paths: one field to test where
// Std.isOfType would walk the class chain.
class Form {
	public static inline var PLAIN = 0;
	public static inline var ARRAY = 1;
	public static inline var TYPED = 2;
	public static inline var FUNCTION = 3;
}

class JsObject {
	public var proto:JsObject;
	// its own properties beyond a typed class's fields (Shapes), their
	// values by slot (null before the first)
	public var shape:Shape;
	public var slots:Array<Dynamic> = null;
	// an instance of a typed class (helder.typescript.lower): its declared
	// fields in slots of its own, before the others (its shapes' root's)
	public var layout(get, never):Layout;
	// (zero for a new object: compiled code makes typed instances without this constructor)
	public var bits = 0;
	// (a Form: zero, plain, for compiled code's typed instances too)
	public var form = Form.PLAIN;

	static inline var NOT_EXTENSIBLE = 1;
	// a typed class's prototype (helder.typescript.lower): compiled code
	// calls its methods directly, so changing it diverges
	static inline var LOCKED = 2;
	// (a site's record found a property through it: Shapes.epoch)
	static inline var WATCHED = 4;
	// (a proxy: Proxies, its traps)
	public static inline var PROXY = 8;
	// (an object type's instance whose layout no longer holds its properties: deopt)
	public static inline var DEOPT = 16;

	public var extensible(get, set):Bool;
	public var locked(get, set):Bool;
	public var watched(get, set):Bool;
	// (null without own properties beyond the layout's)
	public var names(get, never):Array<String>;

	public function new(proto:JsObject) {
		this.proto = proto;
		shape = Shapes.object;
	}

	inline function get_extensible():Bool return bits & NOT_EXTENSIBLE == 0;

	inline function set_extensible(v:Bool):Bool {
		bits = v ? bits & ~NOT_EXTENSIBLE : bits | NOT_EXTENSIBLE;
		return v;
	}

	inline function get_locked():Bool return bits & LOCKED != 0;

	function set_locked(v:Bool):Bool {
		// (its own: a site never writes it from a record)
		if (v && !shape.dict) shape = shape.dictionary();
		bits = v ? bits | LOCKED : bits & ~LOCKED;
		return v;
	}

	inline function get_watched():Bool return bits & WATCHED != 0;

	inline function set_watched(v:Bool):Bool {
		bits = v ? bits | WATCHED : bits & ~WATCHED;
		return v;
	}

	inline function get_names():Array<String> return shape.names();

	inline function get_layout():Layout return shape.layout;

	// a typed class's instance
	public function setLayout(l:Layout):Void shape = l.root;

	// (its keys or prototype changed: what sites found through it is stale)
	inline function changed():Void if (bits & WATCHED != 0) Shapes.epoch++;

	public inline function hasOwn(k:String):Bool
		return layout != null && layout.index.exists(k) || shape.slotOf(k) >= 0;

	// an own property's value (an Accessor for an accessor property); hasOwn(k) first
	public function getOwn(k:String):Dynamic {
		if (layout != null) {
			var i = layout.index.get(k);
			if (i != null) return layout.get(this, i);
		}
		var i = shape.slotOf(k);
		return i < 0 ? null : slots[i];
	}

	// an own property's value, or absent: one lookup where hasOwn and getOwn take two
	public function lookup(k:String, absent:Dynamic):Dynamic {
		if (layout != null) {
			var i = layout.index.get(k);
			if (i != null) return layout.get(this, i);
		}
		var i = shape.slotOf(k);
		return i < 0 ? absent : slots[i];
	}

	// an own property's names, in order
	public function ownNames():Array<String> {
		var own = shape.names();
		return layout == null ? own : own == null ? layout.names : layout.names.concat(own);
	}

	public function attr(k:String):Int {
		if (layout != null && layout.index.exists(k)) {
			var i = shape.slotOf(fieldAttr(k));
			return i < 0 ? 0 : slots[i];
		}
		var i = shape.slotOf(k);
		return i < 0 ? 0 : shape.attrs[i] & ~(Attr.ACCESSOR | Attr.PRIVATE);
	}

	// (a typed class's field's attributes other than the default: a key of their own)
	static inline function fieldAttr(k:String):String return "\x00!" + k;

	public function setOwn(k:String, v:Dynamic, attribute:Int = 0):Void {
		if (locked) Seed.diverge("changeable", this, "a typed class's prototype (" + k + ")");
		if (layout != null && layout.plain && layout.index.exists(k) && (attribute != 0 || Std.isOfType(v, Accessor))) {
			Layout.deopt(this);
			setOwn(k, v, attribute);
			return;
		}
		if (layout != null && layout.index.exists(k)) {
			// (a typed class's field is a plain writable value: what its slot holds)
			if (attribute & Attr.READONLY != 0 || Std.isOfType(v, Accessor)) Seed.diverge("a writable field", v, "property " + k);
			layout.set(this, layout.index.get(k), v);
			var i = shape.slotOf(fieldAttr(k));
			if (i >= 0) slots[i] = attribute;
			else if (attribute != 0) add(fieldAttr(k), attribute, Attr.PRIVATE, Shapes.KEYS, true);
			return;
		}
		var a = Std.isOfType(v, Accessor) ? attribute | Attr.ACCESSOR : attribute;
		var i = shape.slotOf(k);
		if (i < 0) {
			add(k, v, a, Shapes.KEYS, true);
			return;
		}
		slots[i] = v;
		if (shape.attrs[i] != a) reattr(i, a);
	}

	// an own property's value set, its attributes kept
	public function writeOwn(k:String, v:Dynamic):Void {
		if (locked) Seed.diverge("changeable", this, "a typed class's prototype (" + k + ")");
		if (layout != null) {
			var i = layout.index.get(k);
			if (i != null) {
				layout.set(this, i, v);
				return;
			}
		}
		var i = shape.slotOf(k);
		if (i < 0) add(k, v, Std.isOfType(v, Accessor) ? Attr.ACCESSOR : 0, Shapes.KEYS, true);
		else slots[i] = v;
	}

	// a new own property (limit: the keys its shapes may have; bounded: its
	// name not in the program's text, Shape.with)
	public function add(k:String, v:Dynamic, a:Int, limit:Int, bounded:Bool):Void {
		if (layout != null && shadowsMethod(k)) Seed.diverge("a field", v, "method " + k + " of a typed class's instance");
		if (slots == null) slots = [];
		if (shape.dict) shape.add(k, a);
		else {
			var next = shape.with(k, a, limit, bounded);
			if (next == null) {
				shape = shape.dictionary();
				shape.add(k, a);
			}
			else shape = next;
		}
		slots.push(v);
		changed();
	}

	// (a property's attributes changed)
	function reattr(i:Int, a:Int):Void {
		if (!shape.dict) {
			var attrs = shape.attrs.copy();
			attrs[i] = a;
			var s = Shapes.replay(shape.root, shape.keys, attrs);
			if (s != null) {
				shape = s;
				changed();
				return;
			}
			shape = shape.dictionary();
		}
		shape.attrs[i] = a;
		changed();
	}

	public function removeOwn(k:String):Void {
		if (locked) Seed.diverge("changeable", this, "a typed class's prototype (" + k + ")");
		if (layout != null && layout.index.exists(k)) {
			if (!layout.plain) Seed.diverge("deletable", this, "field " + k);
			Layout.deopt(this);
		}
		var i = shape.slotOf(k);
		if (i < 0) return;
		// (the last one added: its parent's shape again, as V8 does)
		if (!shape.dict && i == shape.size() - 1 && shape.parent != null) {
			shape = shape.parent;
			slots.pop();
		}
		else {
			if (!shape.dict) shape = shape.dictionary();
			shape.delete(i);
			slots[i] = null;
			shape.compact(slots);
		}
		changed();
	}

	// (an object type's instance (Layout.plain) given what its layout does not
	// hold, a value of another type, an accessor, an attribute, a delete: an
	// ordinary object of the same properties in their order from then on)
	public function deopt():Void {
		var l = layout;
		var keys:Array<Null<String>> = [], attrs:Array<Int> = [], values:Array<Dynamic> = [];
		for (i in 0...l.names.length) {
			keys.push(l.names[i]);
			attrs.push(0);
			values.push(l.get(this, i));
		}
		for (i in 0...shape.size()) if (shape.keys[i] != null) {
			keys.push(shape.keys[i]);
			attrs.push(shape.attrs[i]);
			values.push(slots[i]);
		}
		var s = Shapes.replay(Shapes.object, keys, attrs);
		if (s == null) {
			s = Shapes.object.dictionary();
			for (i in 0...keys.length) s.add(keys[i], attrs[i]);
		}
		shape = s;
		slots = values;
		bits |= DEOPT;
		changed();
	}

	// (its prototype set)
	public function reproto(p:JsObject):Void {
		if (locked) Seed.diverge("changeable", this, "a typed class's prototype (its prototype)");
		proto = p;
		changed();
	}

	// (an own property hiding a method of a typed class's locked prototype)
	function shadowsMethod(k:String):Bool {
		var p = proto;
		while (p != null && p.locked) {
			if (p.hasOwn(k)) return true;
			p = p.proto;
		}
		return false;
	}

	// [[Class]]-like tag for Object.prototype.toString and inspection
	public function tag():String return "Object";
}

// A typed class's fields (the frontend's typed classes): their names in
// definition order, and its code that reads and writes them by number.
class Layout {
	public final names:Array<String>;
	public final index:Map<String, Int> = [];
	// (its instances' shapes' root: theirs only)
	public final root:Shape;
	public final get:(JsObject, Int) -> Dynamic;
	public final set:(JsObject, Int, Dynamic) -> Void;
	// (an object type's, lower.Reps' object layouts: a value its slot does
	// not take, a delete, an accessor deopt the instance rather than diverge)
	public final plain:Bool;
	// (an ordinary object's shape of its names: what a spread of an instance makes)
	var keys:Null<Shape> = null;
	// (an index or a symbol among its names: Json's, which writes the names in their order)
	var indexes = 0;

	public function indexed():Bool {
		if (indexes == 0) indexes = Lambda.exists(names, k -> Lib.index(k) >= 0 || Symbols.isSymbolKey(k)) ? 2 : 1;
		return indexes == 2;
	}

	public function ordinary():Null<Shape> return keys != null ? keys : keys = Shapes.literal(names);

	// (JsObject.deopt, set by the first object type's layout: a program without one links none of it)
	public static var deopt:JsObject->Void = null;

	public function new(names:Array<String>, get:(JsObject, Int) -> Dynamic, set:(JsObject, Int, Dynamic) -> Void, plain = false) {
		this.names = names;
		this.plain = plain;
		root = Shapes.root(this);
		for (i in 0...names.length) index.set(names[i], i);
		this.get = get;
		this.set = set;
	}
}

// Arrays keep elements densely (holes are Lib.hole); indices too far past the
// end live in slots like other properties.
// A number array (helder.typescript.lower's, made where the checker types
// the elements numbers: number[], a branded number's, T extends number's)
// keeps them unboxed in `nums` while each is a number, dense and the array
// extensible or not: then `items` is empty and `length` is nums.length.
// Reading `items` makes it an ordinary array first (a hole, another value,
// a length beyond the elements: whatever the code reading it does next), so
// the runtime's code over items holds for both; its common paths (Lib's
// get and put, push, pop, the iteration) read and write nums in place.
class JsArray extends JsObject {
	public var nums:Array<Float> = null;
	@:isVar public var items(get, set):Array<Dynamic> = [];
	public var length:Float = 0;
	public var lengthWritable(default, null) = true;

	public function new(proto:JsObject) {
		super(proto);
		form = Form.ARRAY;
		shape = Shapes.array;
	}

	override public function tag():String return "Array";

	public function lockLength():Void {
		lengthWritable = false;
		// Leave the plain-array mutation fast paths.
		if (!shape.dict) shape = shape.dictionary();
	}

	inline function get_items():Array<Dynamic> {
		if (nums != null) generic();
		return items;
	}

	function generic():Void {
		var n = nums;
		nums = null;
		items = [for (x in n) (x : Dynamic)];
	}

	function set_items(v:Array<Dynamic>):Array<Dynamic> {
		nums = null;
		return items = v;
	}

	// (the elements to read, holes as Lib.hole, without changing the array)
	public function elements():Array<Dynamic> return nums != null ? [for (x in nums) (x : Dynamic)] : items;

	// (Array.prototype's own properties changed: compiled code's push and pop
	// on number arrays, and for-of's stepping, are its built-ins' only while not)
	override public function writeOwn(k:String, v:Dynamic):Void {
		if (this == Builtins.ArrayProto) Builtins.arrayProtoChanged(k);
		super.writeOwn(k, v);
	}

	override public function setOwn(k:String, v:Dynamic, attribute:Int = 0):Void {
		if (this == Builtins.ArrayProto) Builtins.arrayProtoChanged(k);
		super.setOwn(k, v, attribute);
	}

	override public function removeOwn(k:String):Void {
		if (this == Builtins.ArrayProto) Builtins.arrayProtoChanged(k);
		super.removeOwn(k);
	}
}

class JsFunction extends JsObject {
	public static inline var PLAIN = 0; // function: callable and constructible
	public static inline var METHOD = 1; // arrow, method or accessor: callable only
	public static inline var BASE = 2; // class without extends: constructible only
	// (a Haxe value the program sees as this function: a helder.view.graph node or Read, Interop.toJs)
	public var haxe:Dynamic = null;
	public static inline var DERIVED = 3; // class with extends
	public var kind:Int;
	// compiled code: (this, args...) for functions, (this, newTarget, args...) for classes
	public var impl:Dynamic;
	// a built-in: (this, args, newTarget) -> result
	public var native:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic;
	// (a built-in reading at most three arguments by their places: called without
	// a list, the missing ones undefined; Builtins.fixed)
	public var fixed:(Dynamic, Dynamic, Dynamic, Dynamic) -> Dynamic = null;
	// (impl as the closure it is, by its arity (no rest): Lib.call's, converted
	// from Dynamic once here rather than at each call)
	public var impl0:Dynamic->Dynamic = null;
	public var impl1:(Dynamic, Dynamic) -> Dynamic = null;
	public var impl2:(Dynamic, Dynamic, Dynamic) -> Dynamic = null;
	public var impl3:(Dynamic, Dynamic, Dynamic, Dynamic) -> Dynamic = null;
	public var impl4:(Dynamic, Dynamic, Dynamic, Dynamic, Dynamic) -> Dynamic = null;
	public var arity:Int;
	public var rest:Bool;
	public var deletedSpecial:Map<String, Bool> = null;
	public var name:String;
	// classes: the instance field initializer (this) -> Void, and the superclass
	public var fields:Dynamic;
	public var parent:Dynamic;
	// a typed class (helder.typescript.lower): its instances' layout, and
	// what makes one (an instance of its own hxmc class) from a prototype
	public var instanceLayout:Layout = null;
	public var alloc:JsObject->JsObject = null;
	public function new(proto:JsObject, kind:Int, name:String, arity:Int) {
		super(proto);
		form = Form.FUNCTION;
		shape = Shapes.func;
		this.kind = kind;
		this.name = name;
		this.arity = arity;
	}

	override public function tag():String return "Function";
}

class JsError extends JsObject {
	// (where it was made: its stack written when first read, Frames)
	public var frames:Null<haxe.io.Bytes> = null;
	public var site:Null<String> = null;
	public var awaits:Null<Array<String>> = null;
	public var stack:Null<String> = null;
	override public function tag():String return "Error";
}

class JsMap extends JsObject {
	public var keys:Array<Dynamic> = [];
	public var values:Array<Dynamic> = [];
	public var active:Array<Bool> = [];
	public var isSet:Bool;
	// (a WeakMap or WeakSet: same representation, its own methods)
	public var weak = false;
	// (the live entries)
	public var count = 0;
	// (lookup indexes: strings, other primitive keys by encoding, objects and symbols by identity)
	public var stringIndex:Map<String, Int> = null;
	public var primitiveIndex:Map<String, Int> = null;
	// (numbers that are 32-bit integers: no encoding made for them)
	public var intIndex:haxe.ds.IntMap<Int> = null;
	public var objectIndex:haxe.ds.ObjectMap<Dynamic, Int> = null;
	public function new(proto:JsObject, isSet:Bool) {
		super(proto);
		this.isSet = isSet;
	}

	override public function tag():String return isSet ? "Set" : "Map";
}

// Built-in iterators over arrays, strings, maps and sets.
class JsIterator extends JsObject {
	public var target:Dynamic;
	public var index:Float = 0;
	public var kind:String;
	public var finished = false;
	public function new(proto:JsObject, target:Dynamic, kind:String) {
		super(proto);
		this.target = target;
		this.kind = kind;
	}
}
