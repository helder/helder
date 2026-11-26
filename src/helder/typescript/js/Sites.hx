package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Shapes;

// What a site found for a receiver of a shape (Bun's and JSC's inline
// caches, as records: no code is patched). What it found beyond the
// receiver holds while the receiver's prototype is the one it saw and
// Shapes.epoch has not moved (the objects it looked through are watched).
class Found {
	public static inline var OWN = 0; // a data property: slots[slot]
	public static inline var GETTER = 1; // an accessor: slots[slot]'s getter
	public static inline var FIELD = 2; // a typed class's field: layout's slot
	public static inline var PROTO = 3; // a data property of holder: its slots[slot]
	public static inline var INHERITED_GETTER = 4; // an accessor of holder
	public static inline var ABSENT = 5; // nowhere: undefined
	public static inline var SET = 6; // a write of a writable data property: slots[slot]
	public static inline var FIELD_SET = 7; // a write of a typed class's field
	public static inline var ADD = 8; // a new property: next, its value appended

	public final kind:Int;
	public final shape:Shape;
	public final slot:Int;
	public final proto:Null<JsObject>;
	public final holder:Null<JsObject>;
	public final epoch:Int;
	public final next:Null<Shape>;

	public function new(kind, shape, slot, proto, holder, next) {
		this.kind = kind;
		this.shape = shape;
		this.slot = slot;
		this.proto = proto;
		this.holder = holder;
		this.next = next;
		epoch = Shapes.epoch;
	}
}

// A property's site in the program (`o.name`, `o.name = v`, `o.name(...)`):
// its key, the record compiled code checks itself (an own property's
// slot by shape: a read's own data property, a write's writable one), and
// the stub's (Sites: at most FOUND, by the receiver's shape).
class Site {
	public final key:String;
	public var shape:Shape = Shapes.none;
	public var slot = 0;
	public final found:Array<Found> = [];

	public function new(key:String) this.key = key;
}

class Sites {
	static inline var FOUND = 4;

	// a receiver's shape for a site, else null (null, undefined, a symbol: the runtime's way)
	static function shapeOf(o:Dynamic):Null<Shape> {
		if (Std.isOfType(o, JsObject)) return (o : JsObject).shape;
		if (Std.isOfType(o, String)) return Shapes.string;
		if (Std.isOfType(o, Float) || Std.isOfType(o, Int)) return Shapes.number;
		if (Std.isOfType(o, Bool)) return Shapes.boolean;
		return null;
	}

	static function protoOf(o:Dynamic, s:Shape):JsObject
		return s == Shapes.string ? Builtins.StringProto : s == Shapes.number ? Builtins.NumberProto : s == Shapes.boolean ? Builtins.BooleanProto : (o : JsObject).proto;

	public static function get(o:Dynamic, site:Site):Dynamic {
		var s = shapeOf(o);
		if (s == null) return Lib.get(o, site.key);
		for (f in site.found) if (f.shape == s) {
			switch f.kind {
				case Found.OWN: return (o : JsObject).slots[f.slot];
				case Found.GETTER: return getter((o : JsObject).slots[f.slot], o);
				case Found.FIELD:
					var obj:JsObject = o;
					return obj.layout.get(obj, f.slot);
				case _ if (f.epoch == Shapes.epoch && f.proto == protoOf(o, s)):
					switch f.kind {
						case Found.PROTO: return f.holder.slots[f.slot];
						case Found.INHERITED_GETTER: return getter(f.holder.slots[f.slot], o);
						case Found.ABSENT: return Lib.undef();
						case _:
					}
				case _:
			}
		}
		return fill(o, s, site);
	}

	static function getter(acc:Accessor, receiver:Dynamic):Dynamic return acc.getter == null ? Lib.undef() : Lib.call(acc.getter, receiver, []);

	static function record(site:Site, f:Found):Void {
		var i = site.found.length;
		while (i-- > 0) if (site.found[i].shape == f.shape) site.found.splice(i, 1);
		if (site.found.length >= FOUND) site.found.shift();
		site.found.push(f);
	}

	// (own properties of its own kind: an array's length, a function's name,
	// length and prototype, a string's length; elements are never a site's)
	static function exotic(o:Dynamic, key:String):Bool
		return Std.isOfType(o, JsArray) ? key == "length" : Std.isOfType(o, JsFunction) ? key == "name" || key == "length" || key == "prototype" : Std.isOfType(o, String) && key == "length";

	static function fill(o:Dynamic, s:Shape, site:Site):Dynamic {
		var key = site.key;
		if (s.dict || exotic(o, key) || Lib.index(key) >= 0) return Lib.getKey(o, key, o);
		if (Std.isOfType(o, JsObject)) {
			var obj:JsObject = o;
			var i = s.slotOf(key);
			if (i >= 0) {
				var accessor = s.attrs[i] & Attr.ACCESSOR != 0;
				record(site, new Found(accessor ? Found.GETTER : Found.OWN, s, i, null, null, null));
				if (!accessor) {
					site.shape = s;
					site.slot = i;
					return obj.slots[i];
				}
				return getter(obj.slots[i], o);
			}
			if (obj.layout != null && obj.layout.index.exists(key)) {
				var j = obj.layout.index.get(key);
				record(site, new Found(Found.FIELD, s, j, null, null, null));
				return obj.layout.get(obj, j);
			}
		}
		var proto = protoOf(o, s);
		var h = proto;
		while (h != null) {
			if (exotic(h, key) || h.layout != null && h.layout.index.exists(key)) return Lib.getKey(o, key, o);
			var j = h.shape.slotOf(key);
			if (j >= 0) {
				Shapes.watch(proto, h);
				var accessor = h.shape.attrs[j] & Attr.ACCESSOR != 0;
				record(site, new Found(accessor ? Found.INHERITED_GETTER : Found.PROTO, s, j, proto, h, null));
				return accessor ? getter(h.slots[j], o) : h.slots[j];
			}
			h = h.proto;
		}
		Shapes.watch(proto, null);
		record(site, new Found(Found.ABSENT, s, 0, proto, null, null));
		return Lib.undef();
	}

	public static function put(o:Dynamic, site:Site, v:Dynamic):Dynamic {
		if (!Std.isOfType(o, JsObject)) return Lib.put(o, site.key, v);
		var obj:JsObject = o;
		var s = obj.shape;
		for (f in site.found) if (f.shape == s) {
			switch f.kind {
				case Found.SET:
					obj.slots[f.slot] = v;
					return v;
				case Found.FIELD_SET:
					obj.layout.set(obj, f.slot, v);
					return v;
				case Found.ADD if (f.epoch == Shapes.epoch && f.proto == obj.proto && obj.extensible):
					if (obj.slots == null) obj.slots = [];
					obj.slots.push(v);
					obj.shape = f.next;
					if (obj.watched) Shapes.epoch++;
					return v;
				case _:
			}
		}
		return fillPut(obj, s, site, v);
	}

	static function fillPut(obj:JsObject, s:Shape, site:Site, v:Dynamic):Dynamic {
		var key = site.key;
		if (s.dict || exotic(obj, key) || Lib.index(key) >= 0) return Lib.put(obj, key, v);
		var i = s.slotOf(key);
		if (i >= 0) {
			if (s.attrs[i] & (Attr.READONLY | Attr.ACCESSOR) != 0) return Lib.put(obj, key, v);
			record(site, new Found(Found.SET, s, i, null, null, null));
			site.shape = s;
			site.slot = i;
			obj.slots[i] = v;
			return v;
		}
		if (obj.layout != null) {
			if (obj.layout.index.exists(key)) {
				var j = obj.layout.index.get(key);
				record(site, new Found(Found.FIELD_SET, s, j, null, null, null));
				obj.layout.set(obj, j, v);
				return v;
			}
			return Lib.put(obj, key, v);
		}
		// (a new property: nothing on the chain takes the write, a setter or a read-only one)
		if (!obj.extensible || Lib.inherited(obj.proto, key) != null || Std.isOfType(v, Accessor)) return Lib.put(obj, key, v);
		var h = obj.proto;
		while (h != null) {
			if (exotic(h, key) || h.layout != null) return Lib.put(obj, key, v);
			h = h.proto;
		}
		var next = s.with(key, 0, Shapes.KEYS, false);
		if (next == null) return Lib.put(obj, key, v);
		Shapes.watch(obj.proto, null);
		record(site, new Found(Found.ADD, s, i, obj.proto, null, next));
		obj.add(key, v, 0, Shapes.KEYS, false);
		return v;
	}

	public static function call(o:Dynamic, site:Site, args:Array<Dynamic>):Dynamic {
		var f = get(o, site);
		if (!Std.isOfType(f, JsFunction)) return Lib.error("TypeError", (Lib.isObject(o) ? Lib.describe(o) : Seed.typeOf(o)) + "." + site.key + " is not a function");
		return Lib.call(f, o, args);
	}
}
