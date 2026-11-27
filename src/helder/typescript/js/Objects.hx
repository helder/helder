package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// Object's built-ins: Object and its prototype, property descriptors and integrity, the primitives' wrappers.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Objects {
	// Object
	static function setupObject():Void {
		var o = ObjectProto;
		fixed(o, "hasOwnProperty", 1, (t, a0:Dynamic, _, _) -> hasOwnKey(toObject(t), key(a0)));
		fixed(o, "isPrototypeOf", 1, (t, a0:Dynamic, _, _) -> {
			var v = a0;
			if (!isObject(v)) return false;
			var p = prototypeOf(v);
			while (p != null) {
				if (p == t) return true;
				p = prototypeOf(p);
			}
			return false;});
		fixed(o, "propertyIsEnumerable", 1, (t, a0:Dynamic, _, _) -> {
			var obj = toObject(t);
			var k = key(a0);
			return hasOwnKey(obj, k) && enumerableOwn(obj, k);});
		fixed(o, "toString", 0, (t, _, _, _) -> objectToString(t));
		fixed(o, "toLocaleString", 0, (t, _, _, _) -> callMethod(t, "toString", []));
		fixed(o, "valueOf", 0, (t, _, _, _) -> toObject(t));
		o.setOwn("__proto__", new Accessor(native("get __proto__", 0, (t, _, _) -> {
			return prototypeOf(toObject(t));}), native("set __proto__", 1, (t, a, _) -> {
				setPrototype(t, arg(a, 0));
				return undef();})), Attr.HIDDEN);
		var c = constructor("Object", 1, o, (t, a, nt) -> {
			var v = arg(a, 0);
			return v == null || v == undef() ? new JsObject(ObjectProto) : toObject(v);});
		fixed(c, "keys", 1, (_, a0:Dynamic, _, _) -> array([for (k in keys(toObject(a0))) k]));
		fixed(c, "values", 1, (_, a0:Dynamic, _, _) -> {
			var o = toObject(a0);
			return array([for (k in keys(o)) get(o, k)]);});
		fixed(c, "entries", 1, (_, a0:Dynamic, _, _) -> {
			var o = toObject(a0);
			return array([for (k in keys(o)) array([k, get(o, k)])]);});
		method(c, "assign", 2, (_, a, _) -> {
			var target = toObject(arg(a, 0));
			for (source in a.slice(1)) if (source != null && source != undef()) {
				var s = toObject(source);
				for (k in ownPropertyKeys(s)) if (enumerableOwn(s, k)) put(target, k, get(s, k));
			}
			return target;});
		fixed(c, "fromEntries", 1, (_, a0:Dynamic, _, _) -> {
			var o = new JsObject(ObjectProto);
			for (entry in toList(a0)) defineOwn(o, key(get(entry, 0)), get(entry, 1));
			return o;});
		fixed(c, "hasOwn", 2, (_, a0:Dynamic, a1:Dynamic, _) -> hasOwnKey(toObject(a0), key(a1)));
		fixed(c, "is", 2, (_, a0:Dynamic, a1:Dynamic, _) -> sameValue(a0, a1));
		fixed(c, "getPrototypeOf", 1, (_, a0:Dynamic, _, _) -> prototypeOf(toObject(a0)));
		fixed(c, "setPrototypeOf", 2, (_, a0:Dynamic, a1:Dynamic, _) -> {
			var o = a0;
			var p = a1;
			if (p != null && !isObject(p)) error("TypeError", "Object prototype may only be an Object or null: " + Seed.text(p));
			setPrototype(o, p);
			return o;});
		fixed(c, "create", 2, (_, a0:Dynamic, a1:Dynamic, _) -> {
			var p = a0;
			if (p != null && !isObject(p)) error("TypeError", "Object prototype may only be an Object or null: " + Seed.text(p));
			var o = new JsObject(p);
			if (a1 != undef()) defineProperties(o, a1);
			return o;});
		fixed(c, "defineProperty", 3, (_, a0:Dynamic, a1:Dynamic, a2:Dynamic) -> {
			var o = a0;
			if (!isObject(o)) error("TypeError", "Object.defineProperty called on non-object");
			defineProperty(o, key(a1), a2);
			return o;});
		fixed(c, "defineProperties", 2, (_, a0:Dynamic, a1:Dynamic, _) -> {
			var o = a0;
			if (!isObject(o)) error("TypeError", "Object.defineProperties called on non-object");
			defineProperties(o, a1);
			return o;});
		fixed(c, "getOwnPropertyNames", 1, (_, a0:Dynamic, _, _) -> {
			var o = toObject(a0);
			var names:Array<Dynamic> = [for (k in ownPropertyKeys(o)) if (!Symbols.isSymbolKey(k)) k];
			return array(names);});
		fixed(c, "getOwnPropertySymbols", 1, (_, a0:Dynamic, _, _) -> {
			var o = toObject(a0);
			var symbols:Array<Dynamic> = [for (k in ownPropertyKeys(o)) if (Symbols.isSymbolKey(k) && Symbols.fromKey(k) != null) Symbols.fromKey(k)];
			return array(symbols);});
		fixed(c, "getOwnPropertyDescriptor", 2, (_, a0:Dynamic, a1:Dynamic, _) -> descriptor(toObject(a0), key(a1)));
		fixed(c, "getOwnPropertyDescriptors", 1, (_, a0:Dynamic, _, _) -> {
			var o = toObject(a0);
			var r = new JsObject(ObjectProto);
			for (k in ownPropertyKeys(o)) r.setOwn(k, descriptor(o, k));
			return r;});
		fixed(c, "freeze", 1, (_, a0:Dynamic, _, _) -> {
			integrity(a0, true);
			return a0;});
		fixed(c, "seal", 1, (_, a0:Dynamic, _, _) -> {
			integrity(a0, false);
			return a0;});
		fixed(c, "preventExtensions", 1, (_, a0:Dynamic, _, _) -> {
			if (isObject(a0) && !Exotics.preventExtensions(a0)) error("TypeError", "'preventExtensions' on proxy: trap returned falsish");
			return a0;});
		fixed(c, "isFrozen", 1, (_, a0:Dynamic, _, _) -> testIntegrity(a0, true));
		fixed(c, "isSealed", 1, (_, a0:Dynamic, _, _) -> testIntegrity(a0, false));
		fixed(c, "isExtensible", 1, (_, a0:Dynamic, _, _) -> isObject(a0) && Exotics.isExtensible(a0));
		fixed(c, "groupBy", 2, (_, a0:Dynamic, a1:Dynamic, _) -> groupBy(a0, a1, false));
	}

	// GroupBy consumes one iterator value per callback and caches the next method.
	// Only callback/key failures close the iterator; iterator-step failures do not.
	static function groupBy(items:Dynamic, fn:Dynamic, isMap:Bool):Dynamic {
		if (items == null || items == undef()) return error("TypeError", "Grouping requires an iterable");
		var f = callback(fn), it = iterator(items), nextFn = get(it, "next");
		var result:JsObject = isMap ? new JsMap(MapProto, false) : new JsObject(null);
		var i:Float = 0;
		while (true) {
			if (i >= 9007199254740991.0) return groupCloseThrow(it, makeError("TypeError", "Too many grouped values"));
			var step = call(nextFn, it, []);
			if (!isObject(step)) return error("TypeError", "Iterator result must be an object");
			if (Seed.truth(get(step, "done"))) return result;
			var value = get(step, "value"), k:Dynamic;
			try {
				k = call(f, undef(), [value, i]);
				if (!isMap) k = key(k);
			}
			catch (e:Dynamic) return groupCloseThrow(it, e);
			var list:JsArray;
			if (isMap) {
				var map:JsMap = cast result;
				var j = mapIndex(map, k);
				if (j < 0) {
					mapPut(map, k, array([]));
					j = mapIndex(map, k);
				}
				list = map.values[j];
			} else {
				var name:String = k;
				if (!result.hasOwn(name)) result.setOwn(name, array([]));
				list = result.getOwn(name);
			}
			setIndex(list, list.length, value);
			i++;
		}
	}

	static function groupCloseThrow(it:Dynamic, reason:Dynamic):Dynamic {
		// The original throw wins over failures getting or calling return().
		try {
			var ret = get(it, "return");
			if (ret != null && ret != undef()) call(ret, it, []);
		}
		catch (_:Dynamic) {}
		throw reason;
	}

	public static function objectToString(t:Dynamic):String {
		if (t == undef()) return "[object Undefined]";
		if (t == null) return "[object Null]";
		var o = toObject(t);
		var tag = getKey(o, Symbols.toStringTag, o);
		if (Std.isOfType(tag, String)) return "[object " + tag + "]";
		if (o.hasOwn("\x00@primitive")) {
			var p = o.getOwn("\x00@primitive");
			return "[object " + (Std.isOfType(p, String) ? "String" : Std.isOfType(p, Bool) ? "Boolean" : "Number") + "]";
		}
		var t = o.tag();
		return "[object " + (t == "Map" || t == "Set" ? "Object" : t) + "]";
	}

	// All own keys (strings in order, then symbols), hidden ones included.
	public static function ownPropertyKeys(o:JsObject):Array<String> {
		if (o.bits & JsObject.PROXY != 0) return Exotics.keys(o);
		var symbols:Array<String> = [];
		var numeric:Array<String> = [];
		if (Std.isOfType(o, JsArray)) {
			var a:JsArray = cast o;
			if (a.nums != null) for (i in 0...a.nums.length) numeric.push(Std.string(i));
			else for (i in 0...a.items.length) if (!same(a.items[i], hole)) numeric.push(Std.string(i));
		}
		var dense = numeric.length;
		var other:Array<String> = [];
		if (o.ownNames() != null) for (n in o.ownNames()) if (Symbols.isSymbolKey(n)) symbols.push(n); else if (index(n) >= 0) numeric.push(n); else other.push(n);
		if (numeric.length > dense) numeric.sort((x, y) -> {
			var a = index(x), b = index(y);
			return a < b ? -1 : a > b ? 1 : 0;});
		var extra:Array<String> = [];
		if (Std.isOfType(o, JsArray)) extra.push("length");
		if (Std.isOfType(o, JsFunction)) {
			for (k in ["length", "name"]) if (!o.hasOwn(k) && hasOwnKey(o, k)) extra.push(k);
		}
		return numeric.concat(extra).concat(other).concat(symbols);
	}

	public static function descriptor(o:JsObject, k:String):Dynamic {
		if (o.bits & JsObject.PROXY != 0) return Exotics.own(o, k);
		if (!hasOwnKey(o, k)) return undef();
		var d = new JsObject(ObjectProto);
		var attribute = o.attr(k);
		var v:Dynamic = o.hasOwn(k) ? o.getOwn(k) : get(o, k);
		var virtual = !o.hasOwn(k);
		if (Std.isOfType(v, Accessor)) {
			var acc:Accessor = v;
			d.setOwn("get", acc.getter == null ? undef() : acc.getter);
			d.setOwn("set", acc.setter == null ? undef() : acc.setter);
		}
		else {
			d.setOwn("value", v);
			d.setOwn("writable", virtual ? (Std.isOfType(o, JsArray) && (k != "length" || (cast o : JsArray).lengthWritable) || k == "prototype") : attribute & (Attr.READONLY | Attr.FROZEN) == 0);
		}
		d.setOwn("enumerable", virtual ? (Std.isOfType(o, JsArray) && k != "length") : attribute & Attr.HIDDEN == 0);
		d.setOwn("configurable", virtual ? (Std.isOfType(o, JsFunction) && k != "prototype" || Std.isOfType(o, JsArray) && k != "length") : attribute & Attr.LOCKED == 0);
		return d;
	}

	static function defineProperties(o:JsObject, props:Dynamic):Void {
		var p = toObject(props);
		var entries = [for (k in ownPropertyKeys(p)) if (enumerableOwn(p, k)) {key: k, desc: propertyDescriptor(get(p, k))}];
		for (entry in entries) applyDescriptor(o, entry.key, entry.desc, true);
	}

	// ToPropertyDescriptor reads each present field once, in order, before
	// applying any part of the descriptor.
	static function propertyDescriptor(v:Dynamic):JsObject {
		if (!isObject(v)) return error("TypeError", "Property description must be an object: " + Seed.text(v));
		var d = new JsObject(ObjectProto);
		for (k in ["enumerable", "configurable", "value", "writable", "get", "set"]) if (has(v, k)) {
			var x:Dynamic = get(v, k);
			switch k {
				case "value": d.setOwn(k, x);
				case "get", "set":
					if (!same(x, undef()) && !isCallable(x)) error("TypeError", "Invalid descriptor " + k + "ter: " + Seed.text(x));
					d.setOwn(k, x);
				case _: d.setOwn(k, Seed.truth(x));
			}
		}
		if ((d.hasOwn("get") || d.hasOwn("set")) && (d.hasOwn("value") || d.hasOwn("writable")))
			error("TypeError", "Invalid property descriptor. Cannot both specify accessors and a value or writable attribute");
		return d;
	}

	public static function defineProperty(o:JsObject, k:String, desc:Dynamic):Void
		applyDescriptor(o, k, propertyDescriptor(desc), true);

	// [[DefineOwnProperty]] as Reflect.defineProperty and a proxy's target take it: whether it was done
	public static function defineResult(o:JsObject, k:String, desc:Dynamic):Bool
		return applyDescriptor(o, k, propertyDescriptor(desc), false);

	// CreateDataPropertyOrThrow: bypass setters and require all three attributes.
	public static function createDataProperty(o:JsObject, k:String, value:Dynamic):Void {
		var d = new JsObject(ObjectProto);
		d.setOwn("value", value);
		d.setOwn("writable", true);
		d.setOwn("enumerable", true);
		d.setOwn("configurable", true);
		applyDescriptor(o, k, d, true);
	}

	static function refused(strict:Bool, text:String):Bool {
		if (strict) error("TypeError", text);
		return false;
	}

	static function flag(d:JsObject, name:String, bit:Int, attribute:Int):Int {
		if (!d.hasOwn(name)) return attribute;
		return d.getOwn(name) ? attribute & ~bit : attribute | bit;
	}

	static function applyDescriptor(o:JsObject, k:String, d:JsObject, strict:Bool):Bool {
		if (o.bits & JsObject.PROXY != 0) {
			var ok = Exotics.define(o, k, d);
			if (!ok && strict) Exotics.fail("defineProperty", k);
			return ok;
		}
		var a:JsArray = o.form == Form.ARRAY ? cast o : null;
		var i = a == null ? -1 : index(k);
		if (a != null && k == "length") return defineLength(a, d, strict);
		if (o.form == Form.FUNCTION && !o.hasOwn(k) && hasOwnKey(o, k) && k != "prototype")
			o.setOwn(k, get(o, k), Attr.HIDDEN | Attr.READONLY);

		var shaped = o.hasOwn(k), exists = shaped || i >= 0 && hasOwnKey(o, k);
		var old = shaped ? o.attr(k) : exists ? 0 : Attr.HIDDEN | Attr.READONLY | Attr.LOCKED;
		var current = shaped ? o.getOwn(k) : exists ? get(o, i) : undef();
		var acc:Accessor = Std.isOfType(current, Accessor) ? current : null;
		var accessor = d.hasOwn("get") || d.hasOwn("set"), data = d.hasOwn("value") || d.hasOwn("writable");
		var attribute = flag(d, "enumerable", Attr.HIDDEN, old);
		attribute = flag(d, "configurable", Attr.LOCKED, attribute);
		attribute = flag(d, "writable", Attr.READONLY, attribute);

		if (old & Attr.FROZEN != 0 || exists && old & Attr.LOCKED != 0 && (
			(attribute ^ old) & (Attr.HIDDEN | Attr.LOCKED) != 0
			|| accessor && acc == null || data && acc != null
			|| acc != null && (d.hasOwn("get") && !sameValue(d.getOwn("get"), acc.getter == null ? undef() : acc.getter)
				|| d.hasOwn("set") && !sameValue(d.getOwn("set"), acc.setter == null ? undef() : acc.setter))
			|| acc == null && old & Attr.READONLY != 0 && (attribute & Attr.READONLY == 0
				|| d.hasOwn("value") && !sameValue(d.getOwn("value"), current))))
			return refused(strict, "Cannot redefine property: " + Symbols.functionName(k));
		if (!exists && !o.extensible) return refused(strict, "Cannot define property " + Symbols.functionName(k) + ", object is not extensible");
		if (i >= 0 && i >= a.length && !a.lengthWritable) return refused(strict, "Cannot extend array with a non-writable length");

		var value:Dynamic;
		if (accessor || acc != null && !data) {
			var g = d.hasOwn("get") ? d.getOwn("get") : acc == null ? null : acc.getter;
			var s = d.hasOwn("set") ? d.getOwn("set") : acc == null ? null : acc.setter;
			value = new Accessor(same(g, undef()) ? null : g, same(s, undef()) ? null : s);
			attribute &= ~Attr.READONLY;
		}
		else {
			value = d.hasOwn("value") ? d.getOwn("value") : acc != null ? undef() : current;
			if (acc != null && !d.hasOwn("writable")) attribute |= Attr.READONLY;
		}
		if (i >= 0) {
			if (!shaped && attribute == 0 && !accessor) {
				setIndex(a, i, value);
				return true;
			}
			if (exists && !shaped) a.items[Std.int(i)] = hole;
			if (i >= a.length) a.length = i + 1;
		}
		o.setOwn(k, value, attribute);
		return true;
	}

	static function defineLength(a:JsArray, d:JsObject, strict:Bool):Bool {
		var len = d.hasOwn("value") ? arrayLength(d.getOwn("value")) : a.length;
		var writable = d.hasOwn("writable") ? (d.getOwn("writable") : Bool) : a.lengthWritable;
		if (d.hasOwn("get") || d.hasOwn("set") || d.getOwn("configurable") == true || d.getOwn("enumerable") == true
			|| !a.lengthWritable && (writable || len != a.length))
			return refused(strict, "Cannot redefine property: length");
		var ok = resizeArray(a, len);
		if (!writable) a.lockLength();
		return ok || refused(strict, "Cannot truncate array with a non-configurable element");
	}

	static function integrity(v:Dynamic, freeze:Bool):Void {
		if (!isObject(v)) return;
		var o:JsObject = v;
		if (o.bits & JsObject.PROXY != 0) {
			// (SetIntegrityLevel's own way, through the traps)
			if (!Exotics.preventExtensions(o)) error("TypeError", "'preventExtensions' on proxy: trap returned falsish");
			for (k in Exotics.keys(o)) {
				var d = new JsObject(ObjectProto);
				d.setOwn("configurable", false);
				if (freeze) {
					var current = Exotics.own(o, k);
					if (same(current, undef())) continue;
					if (!has(current, "get") && !has(current, "set")) d.setOwn("writable", false);
				}
				defineProperty(o, k, d);
			}
			return;
		}
		if (Std.isOfType(o, JsArray)) {
			// (elements move to ordinary properties, which carry attributes)
			var a:JsArray = cast o;
			var items = a.items;
			a.items = [];
			for (i in 0...items.length) if (!same(items[i], hole)) a.setOwn(Std.string(i), items[i]);
			if (freeze) a.lockLength();
		}
		if (o.ownNames() != null) for (k in o.ownNames().copy()) {
			var attribute = o.attr(k) | Attr.LOCKED;
			if (freeze && !Std.isOfType(o.getOwn(k), Accessor)) attribute |= Attr.READONLY;
			o.setOwn(k, o.getOwn(k), attribute);
		}
		o.extensible = false;
	}

	static function testIntegrity(v:Dynamic, frozen:Bool):Bool {
		if (!isObject(v)) return true;
		var o:JsObject = v;
		if (o.bits & JsObject.PROXY != 0) {
			if (Exotics.isExtensible(o)) return false;
			for (k in Exotics.keys(o)) {
				var d = Exotics.own(o, k);
				if (same(d, undef())) continue;
				if (Seed.truth(get(d, "configurable"))) return false;
				if (frozen && !has(d, "get") && !has(d, "set") && Seed.truth(get(d, "writable"))) return false;
			}
			return true;
		}
		if (o.extensible) return false;
		if (Std.isOfType(o, JsArray)) {
			var a:JsArray = cast o;
			if ((a.nums != null ? a.nums.length > 0 : Lambda.exists(a.items, v -> !same(v, hole))) || frozen && a.lengthWritable) return false;
		}
		if (o.ownNames() != null) for (k in o.ownNames().copy()) {
			var attribute = o.attr(k);
			if (attribute & Attr.LOCKED == 0) return false;
			if (frozen && !Std.isOfType(o.getOwn(k), Accessor) && attribute & Attr.READONLY == 0) return false;
		}
		return true;
	}

	// Primitive wrapper objects (Object("x"), new Number(1)).
	public static function wrap(v:Dynamic):JsObject {
		var o = new JsObject(Std.isOfType(v, String) ? StringProto : Std.isOfType(v, Bool) ? BooleanProto : Std.isOfType(v, Symbols.JsSymbol) ? SymbolProto : NumberProto);
		o.setOwn("\x00@primitive", v, Attr.HIDDEN);
		if (Std.isOfType(v, String)) {
			var s:String = v;
			for (i in 0...s.length) o.setOwn(Std.string(i), s.charAt(i), Attr.READONLY | Attr.LOCKED);
			o.setOwn("length", s.length, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		}
		return o;
	}

	// (this value of a String/Number/Boolean method: the primitive, or a wrapper's)
	public static function primitive(t:Dynamic, type:String):Dynamic {
		if (isObject(t) && (t : JsObject).hasOwn("\x00@primitive")) t = (t : JsObject).getOwn("\x00@primitive");
		if (Seed.typeOf(t) != type) error("TypeError", type.charAt(0).toUpperCase() + type.substr(1) + ".prototype method called on incompatible receiver " + Seed.text(t));
		return t;
	}
}
