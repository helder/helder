package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Shapes;
import helder.typescript.js.Symbols.JsSymbol;

// The JavaScript object model: property access through prototype chains,
// calls and construction, classes, and conversions. Built-in objects are set
// up in Builtins. Host Haxe arrays are argument lists; JS arrays are JsArrays.
class Lib {
	public static var hole:Dynamic = new Hole();
	// (an own property lookup that found nothing)
	static var absent:Dynamic = new Hole();
	// (Lib.iterate: the iterator is done)
	public static var finished:Dynamic = new Hole();
	public static inline function undef():Dynamic return Seed.undefinedValue;

	// (by reference: undefined, the hole, absent and finished are objects of
	// their own, so this is what == with one of them means, without Dynamic's comparison)
	public static inline function same(a:Dynamic, b:Dynamic):Bool return (cast a : Hole) == (cast b : Hole);

	public static function error(name:String, message:String):Dynamic throw Builtins.makeError(name, message);

	public static function isObject(v:Dynamic):Bool return Std.isOfType(v, JsObject);

	public static function isCallable(v:Dynamic):Bool return Std.isOfType(v, JsFunction) && (v : JsFunction).kind < JsFunction.BASE;

	public static function isConstructor(v:Dynamic):Bool {
		if (!Std.isOfType(v, JsFunction)) return false;
		var f:JsFunction = cast v;
		return f.kind != JsFunction.METHOD;
	}

	// (a boxed Int is a Float to Std.isOfType)
	public static function isNumber(v:Dynamic):Bool return Std.isOfType(v, Float);

	public static function arg(args:Array<Dynamic>, i:Int):Dynamic return i < args.length ? args[i] : undef();

	public static function key(v:Dynamic):String {
		if (Std.isOfType(v, String)) return v;
		if (Std.isOfType(v, JsSymbol)) return (v : JsSymbol).key;
		if (isObject(v)) {
			v = toPrimitive(v, "string");
			if (Std.isOfType(v, JsSymbol)) return (v : JsSymbol).key;
		}
		return Seed.text(v);
	}

	// (an array index is a canonical integer below 2^32 - 1: digits, no leading zero)
	public static function index(k:String):Float {
		var n = k.length;
		if (n == 0 || n > 10) return -1;
		var c = StringTools.fastCodeAt(k, 0);
		if (c < 48 || c > 57 || c == 48 && n > 1) return -1;
		var v = 0.0;
		for (i in 0...n) {
			c = StringTools.fastCodeAt(k, i);
			if (c < 48 || c > 57) return -1;
			v = v * 10 + (c - 48);
		}
		return v < 4294967295.0 ? v : -1;
	}

	// (an integral number usable as an array index, else -1)
	static inline function numericIndex(k:Dynamic):Float {
		var n:Float = k;
		return n >= 0 && n < 4294967295.0 && Math.ffloor(n) == n ? n : -1;
	}

	public static function describe(v:Dynamic):String {
		if (same(v, undef())) return "undefined";
		if (v == null) return "null";
		if (Std.isOfType(v, String)) return '"' + v + '"';
		if (Std.isOfType(v, JsFunction)) return (v : JsFunction).name == "" ? "function" : (v : JsFunction).name;
		if (isObject(v)) return "#<" + className(v) + ">";
		return Seed.text(v);
	}

	static function className(o:JsObject):String {
		var c = getKey(o, "constructor", o);
		return Std.isOfType(c, JsFunction) && (c : JsFunction).name != "" ? (c : JsFunction).name : "Object";
	}

	static function protoOf(v:Dynamic):JsObject {
		if (isObject(v)) return (v : JsObject).proto;
		if (Std.isOfType(v, String)) return Builtins.StringProto;
		if (Std.isOfType(v, Bool)) return Builtins.BooleanProto;
		if (Std.isOfType(v, JsSymbol)) return Builtins.SymbolProto;
		if (isNumber(v)) return Builtins.NumberProto;
		return null;
	}

	public static function protoFrom(newTarget:Dynamic, fallback:JsObject):JsObject {
		if (!isObject(newTarget)) return fallback;
		var p = get(newTarget, "prototype");
		return isObject(p) ? p : fallback;
	}

	// Properties.
	public static function get(o:Dynamic, k:Dynamic):Dynamic {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot read properties of " + Seed.text(o) + " (reading '" + key(k) + "')");
		if (isNumber(k) && isObject(o)) {
			var obj:JsObject = o;
			if (obj.form == Form.ARRAY) {
				var a:JsArray = cast o;
				var i = numericIndex(k);
				if (a.nums != null) {
					if (i >= 0 && i < a.nums.length) return a.nums[Std.int(i)];
				}
				else if (i >= 0 && i < a.items.length) {
					var v = a.items[Std.int(i)];
					if (!same(v, hole)) return v;
				}
			}
			else if (obj.form == Form.TYPED) return TypedArrays.elementGet(cast o, numericIndex(k));
		}
		return getKey(o, key(k), o);
	}

	// o.name, a name the compiler knows is one (never a symbol or a number)
	public static function getNamed(o:Dynamic, name:String):Dynamic {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot read properties of " + Seed.text(o) + " (reading '" + name + "')");
		return getKey(o, name, o);
	}

	public static function getKey(o:Dynamic, name:String, receiver:Dynamic):Dynamic {
		var obj:JsObject;
		if (isObject(o)) obj = o;
		else if (Std.isOfType(o, String)) {
			var s:String = o;
			if (name == "length") return s.length;
			var i = index(name);
			if (i >= 0 && i < s.length) return s.charAt(Std.int(i));
			obj = Builtins.StringProto;
		}
		else obj = protoOf(o);
		while (obj != null) {
			if (obj.bits & JsObject.PROXY != 0) return Exotics.read(obj, name, receiver);
			var v = ownGet(obj, name, receiver);
			if (!same(v, absent)) return v;
			obj = obj.proto;
		}
		return undef();
	}

	static function ownGet(obj:JsObject, name:String, receiver:Dynamic):Dynamic {
		// (a property of its shape: never an element, an array's length, a function's own until written)
		var s = obj.shape.slotOf(name);
		if (s >= 0) {
			var v = obj.slots[s];
			if (obj.shape.attrs[s] & Attr.ACCESSOR == 0) return v;
			var acc:Accessor = v;
			return acc.getter == null ? undef() : call(acc.getter, receiver, []);
		}
		if (obj.layout != null) {
			var i = obj.layout.index.get(name);
			if (i != null) return obj.layout.get(obj, i);
		}
		switch (obj.form) {
			case Form.ARRAY:
				var a:JsArray = cast obj;
				if (name == "length") return a.length;
				var i = index(name);
				if (a.nums != null) {
					if (i >= 0 && i < a.nums.length) return a.nums[Std.int(i)];
				}
				else if (i >= 0 && i < a.items.length) {
					var v = a.items[Std.int(i)];
					return same(v, hole) ? absent : v;
				}
			case Form.TYPED:
				var i = index(name);
				if (i >= 0) {
					var t:TypedArrays.JsTypedArray = cast obj;
					return TypedArrays.elementGet(t, i);
				}
			case Form.FUNCTION:
				return functionOwn(cast obj, name);
			case _:
		}
		return absent;
	}

	// (a function's name, length and lazily created prototype)
	static function functionOwn(f:JsFunction, name:String):Dynamic {
		if (f.deletedSpecial != null && f.deletedSpecial.exists(name)) return absent;
		return switch (name) {
			case "name": f.name;
			case "length": f.rest ? f.arity - 1 : f.arity;
			case "prototype" if (f.kind == JsFunction.PLAIN && f.native == null):
				var p = new JsObject(Builtins.ObjectProto);
				p.setOwn("constructor", f, Attr.HIDDEN);
				f.setOwn("prototype", p, Attr.HIDDEN | Attr.LOCKED);
				p;
			case _: absent;
		};
	}

	public static function hasOwnKey(o:Dynamic, name:String):Bool {
		if (Std.isOfType(o, String)) {
			var s:String = o;
			var i = index(name);
			return name == "length" || i >= 0 && i < s.length;
		}
		if (!isObject(o)) return false;
		var obj:JsObject = o;
		if (obj.bits & JsObject.PROXY != 0) return !same(Exotics.own(obj, name), undef());
		if (obj.form == Form.ARRAY) {
			var a:JsArray = cast obj;
			if (name == "length") return true;
			var i = index(name);
			if (a.nums != null) {
				if (i >= 0 && i < a.nums.length) return true;
			}
			else if (i >= 0 && i < a.items.length) return !same(a.items[Std.int(i)], hole);
		}
		else if (obj.form == Form.TYPED) {
			var i = index(name);
			if (i >= 0) return i < (cast obj : TypedArrays.JsTypedArray).length();
		}
		if (obj.hasOwn(name)) return true;
		if (obj.form == Form.FUNCTION) return functionOwn(cast obj, name) != absent;
		return false;
	}

	// The `in` operator.
	public static function has(o:Dynamic, k:Dynamic):Bool {
		if (!isObject(o)) return error("TypeError", "Cannot use 'in' operator to search for '" + key(k) + "' in " + Seed.text(o));
		var name = key(k);
		var obj:JsObject = o;
		while (obj != null) {
			if (obj.bits & JsObject.PROXY != 0) return Exotics.contains(obj, name);
			if (hasOwnKey(obj, name)) return true;
			obj = obj.proto;
		}
		return false;
	}

	public static function put(o:Dynamic, k:Dynamic, v:Dynamic):Dynamic {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot set properties of " + Seed.text(o) + " (setting '" + key(k) + "')");
		if (isNumber(k) && isObject(o)) {
			var obj:JsObject = o;
			if (obj.form == Form.ARRAY) {
				var a:JsArray = cast o;
				var i = numericIndex(k);
				if (a.nums != null && isNumber(v)) {
					if (i >= 0 && i < a.nums.length) {
						a.nums[Std.int(i)] = v;
						return v;
					}
				}
				else if (i >= 0 && i < a.items.length && !same(a.items[Std.int(i)], hole)) {
					a.items[Std.int(i)] = v;
					return v;
				}
			}
			else if (obj.form == Form.TYPED) {
				TypedArrays.elementSet(cast o, numericIndex(k), v);
				return v;
			}
		}
		setKey(o, key(k), v, o, true);
		return v;
	}

	// o.name = v, a name the compiler knows is one
	public static function putNamed(o:Dynamic, name:String, v:Dynamic):Dynamic {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot set properties of " + Seed.text(o) + " (setting '" + name + "')");
		setKey(o, name, v, o);
		return v;
	}

	// (keyed: by a computed name, Shapes.KEYED; strict: a refused write
	// throws, else it is false: Reflect.set's, a proxy's target's)
	static function setKey(o:Dynamic, name:String, v:Dynamic, receiver:Dynamic, keyed = false, strict = true):Bool {
		if (!isObject(o)) {
			// (a primitive: only an inherited setter can accept the write)
			var acc = findAccessor(protoOf(o), name);
			if (acc != null && acc.setter != null) {
				call(acc.setter, receiver, [v]);
				return true;
			}
			return refuse(strict, "Cannot create property '" + name + "' on " + Seed.typeOf(o) + " '" + Seed.text(o) + "'");
		}
		var obj:JsObject = o;
		if (obj.bits & JsObject.PROXY != 0) return Exotics.write(obj, name, v, receiver) || refuse(strict, null, () -> Exotics.fail("set", name));
		if (obj.form == Form.ARRAY) {
			var a:JsArray = cast obj;
			if (name == "length") {
				setLength(a, v);
				return true;
			}
			var i = index(name);
			if (i >= 0 && !obj.hasOwn(name) && inherited(obj.proto, name) == null) {
				if (!obj.extensible && !hasOwnKey(obj, name)) return refuse(strict, "Cannot add property " + name + ", object is not extensible");
				setIndex(a, i, v);
				return true;
			}
		}
		else if (obj.form == Form.TYPED) {
			var i = index(name);
			if (i >= 0) {
				TypedArrays.elementSet(cast obj, i, v);
				return true;
			}
		}
		if (obj.hasOwn(name)) {
			var current = obj.getOwn(name);
			if (Std.isOfType(current, Accessor)) {
				var acc:Accessor = current;
				if (acc.setter == null) return refuse(strict, readOnlyText(name, obj));
				call(acc.setter, receiver, [v]);
				return true;
			}
			if (obj.attr(name) & (Attr.READONLY | Attr.FROZEN) != 0) return refuse(strict, readOnlyText(name, obj));
			if (!same(receiver, obj)) return setOn(receiver, name, v, strict);
			obj.writeOwn(name, v);
			return true;
		}
		if (obj.form == Form.FUNCTION && functionOwn(cast obj, name) != absent && name != "prototype") return refuse(strict, readOnlyText(name, obj));
		// (a proxy above it before any object that has the property: the proxy's [[Set]])
		if (Exotics.made) {
			var p = obj.proto;
			while (p != null && p.bits & JsObject.PROXY == 0 && !p.hasOwn(name)) p = p.proto;
			if (p != null && p.bits & JsObject.PROXY != 0) return Exotics.write(p, name, v, receiver) || refuse(strict, null, () -> Exotics.fail("set", name));
		}
		var found = inherited(obj.proto, name);
		if (found != null) {
			if (Std.isOfType(found, Accessor)) {
				var acc:Accessor = found;
				if (acc.setter == null) return refuse(strict, readOnlyText(name, obj));
				call(acc.setter, receiver, [v]);
				return true;
			}
			return refuse(strict, readOnlyText(name, obj));
		}
		if (!same(receiver, obj)) return setOn(receiver, name, v, strict);
		if (!obj.extensible) return refuse(strict, "Cannot add property " + name + ", object is not extensible");
		if (keyed && !obj.locked && !Std.isOfType(obj, JsArray)) obj.add(name, v, Std.isOfType(v, Accessor) ? Attr.ACCESSOR : 0, Shapes.KEYED, true);
		else obj.setOwn(name, v);
		return true;
	}

	// (a data write for another receiver than the object written through,
	// OrdinarySetWithOwnDescriptor's: its own property's value, or a new one)
	static function setOn(receiver:Dynamic, name:String, v:Dynamic, strict:Bool):Bool {
		if (!isObject(receiver)) return refuse(strict, "Cannot create property '" + name + "' on " + Seed.typeOf(receiver) + " '" + Seed.text(receiver) + "'");
		var r:JsObject = receiver;
		var current = Objects.descriptor(r, name);
		var d = new JsObject(Builtins.ObjectProto);
		d.setOwn("value", v);
		if (!same(current, undef())) {
			if (has(current, "get") || has(current, "set") || !Seed.truth(get(current, "writable"))) return refuse(strict, readOnlyText(name, r));
		}
		else {
			d.setOwn("writable", true);
			d.setOwn("enumerable", true);
			d.setOwn("configurable", true);
		}
		return Objects.defineResult(r, name, d) || refuse(strict, "Cannot redefine property: " + Symbols.functionName(name));
	}

	// (a refused write: thrown where strict, else false; text made only when thrown)
	static function refuse(strict:Bool, text:Null<String>, ?thrown:() -> Dynamic):Bool {
		if (!strict) return false;
		if (thrown != null) thrown();
		error("TypeError", text);
		return false;
	}

	// [[Set]] as Reflect.set and a proxy's target take it: whether it was done
	public static function setResult(o:Dynamic, name:String, v:Dynamic, receiver:Dynamic):Bool return setKey(o, name, v, receiver, false, false);

	static function readOnlyText(name:String, obj:JsObject):String return "Cannot assign to read only property '" + name + "' of " + (obj.form == Form.FUNCTION ? "function" : "object") + " '" + describe(obj) + "'";

	// (an inherited accessor or read-only data property that governs a write; null when a plain write may proceed)
	public static function inherited(obj:JsObject, name:String):Dynamic {
		while (obj != null) {
			if (obj.hasOwn(name)) {
				var v = obj.getOwn(name);
				if (Std.isOfType(v, Accessor)) return v;
				return obj.attr(name) & Attr.READONLY != 0 ? v : null;
			}
			obj = obj.proto;
		}
		return null;
	}

	static function findAccessor(obj:JsObject, name:String):Accessor {
		while (obj != null) {
			if (obj.hasOwn(name)) {
				var v = obj.getOwn(name);
				return Std.isOfType(v, Accessor) ? v : null;
			}
			obj = obj.proto;
		}
		return null;
	}

	public static function setIndex(a:JsArray, i:Float, v:Dynamic):Void {
		if (a.nums != null && isNumber(v) && i <= a.nums.length) {
			if (i == a.nums.length) {
				a.nums.push(v);
				a.length = a.nums.length;
			}
			else a.nums[Std.int(i)] = v;
			return;
		}
		var n = a.items.length;
		if (i < n) {
			a.items[Std.int(i)] = v;
		}
		else if (i < n * 2 + 64 && i < 16777216) {
			// (an element kept as a property before: only with properties beyond the elements)
			if (a.shape.size() > 0) {
				var name = Seed.numberText(i);
				if (a.hasOwn(name)) a.removeOwn(name);
			}
			while (a.items.length < i) a.items.push(hole);
			a.items.push(v);
		}
		else a.setOwn(Seed.numberText(i), v);
		if (i >= a.length) a.length = i + 1;
	}

	public static function setLength(a:JsArray, v:Dynamic):Void {
		var len = Seed.numeric(v);
		if (Math.isNaN(len) || len < 0 || len > 4294967295.0 || Math.ffloor(len) != len) {
			error("RangeError", "Invalid array length");
			return;
		}
		if (a.nums != null && len <= a.nums.length) a.nums.resize(Std.int(len));
		else if (len < a.items.length) a.items.resize(Std.int(len));
		if (a.names != null) for (n in a.names.copy()) if (index(n) >= len) a.removeOwn(n);
		a.length = len;
	}

	public static function remove(o:Dynamic, k:Dynamic):Bool {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot convert undefined or null to object");
		if (!isObject(o)) return true;
		return removeKey(o, key(k), true);
	}

	// [[Delete]] as Reflect.deleteProperty and a proxy's target take it: whether it was done
	public static function removeResult(o:JsObject, name:String):Bool return removeKey(o, name, false);

	static function removeKey(obj:JsObject, name:String, strict:Bool):Bool {
		if (obj.bits & JsObject.PROXY != 0) return Exotics.remove(obj, name) || refuse(strict, null, () -> Exotics.fail("deleteProperty", name));
		if (obj.form == Form.ARRAY) {
			var a:JsArray = cast obj;
			var i = index(name);
			if (i >= 0 && i < a.items.length) {
				a.items[Std.int(i)] = hole;
				return true;
			}
			if (name == "length") return refuse(strict, "Cannot delete property 'length' of [object Array]");
		}
		else if (obj.form == Form.TYPED) {
			var i = index(name);
			if (i >= 0 && i < (cast obj : TypedArrays.JsTypedArray).length()) return refuse(strict, "Cannot delete property '" + name + "' of " + describe(obj));
			if (i >= 0) return true;
		}
		if (obj.attr(name) & Attr.LOCKED != 0) return refuse(strict, "Cannot delete property '" + name + "' of " + describe(obj));
		if (obj.form == Form.FUNCTION && (name == "name" || name == "length")) {
			var f:JsFunction = cast obj;
			if (f.deletedSpecial == null) f.deletedSpecial = [];
			f.deletedSpecial.set(name, true);
		}
		obj.removeOwn(name);
		return true;
	}

	// Own string keys: integer indices ascending, then others in insertion order.
	public static function ownKeys(o:Dynamic, enumerableOnly:Bool):Array<String> {
		if (o == null || same(o, undef())) return error("TypeError", "Cannot convert undefined or null to object");
		if (Std.isOfType(o, String)) {
			var s:String = o;
			return [for (i in 0...s.length) Std.string(i)];
		}
		if (!isObject(o)) return [];
		var obj:JsObject = o;
		if (obj.bits & JsObject.PROXY != 0) return [
			for (k in Exotics.keys(obj))
				if (!Symbols.isSymbolKey(k) && (!enumerableOnly || enumerableOwn(obj, k))) k
		];
		var out:Array<String> = [];
		if (obj.form == Form.ARRAY) {
			var a:JsArray = cast obj;
			if (a.nums != null) for (i in 0...a.nums.length) out.push(Std.string(i));
			else for (i in 0...a.items.length) if (!same(a.items[i], hole)) out.push(Std.string(i));
		}
		else if (obj.form == Form.TYPED) for (i in 0...(cast obj : TypedArrays.JsTypedArray).length()) out.push(Std.string(i));
		var own = obj.ownNames();
		if (own == null) return out;
		var numeric:Array<String> = [];
		var other:Array<String> = [];
		for (n in own) {
			if (enumerableOnly && obj.attr(n) & Attr.HIDDEN != 0) continue;
			if (Symbols.isSymbolKey(n)) continue;
			if (index(n) >= 0) numeric.push(n); else other.push(n);
		}
		numeric.sort((x, y) -> {
			var a = index(x), b = index(y);
			return a < b ? -1 : a > b ? 1 : 0;});
		return out.concat(numeric).concat(other);
	}

	public static function keys(o:Dynamic):Array<String> return ownKeys(o, true);

	public static function defineOwn(o:JsObject, name:String, v:Dynamic, attribute:Int = 0):Void {
		if (Std.isOfType(o, JsArray)) {
			var i = index(name);
			if (i >= 0 && attribute == 0) {
				setIndex(cast o, i, v);
				return;
			}
		}
		o.setOwn(name, v, attribute);
	}

	// Calls and construction.
	// (the arguments after `lead` slots the caller fills: one array, sized once)
	static function positional(f:JsFunction, args:Array<Dynamic>, lead:Int):Array<Dynamic> {
		var fixed = f.rest ? f.arity - 1 : f.arity;
		var passed:Array<Dynamic> = [];
		passed.resize(lead + fixed + (f.rest ? 1 : 0));
		for (i in 0...fixed) passed[lead + i] = i < args.length ? args[i] : undef();
		if (f.rest) passed[lead + fixed] = array(args.slice(fixed));
		return passed;
	}

	// (a compiled function's impl takes `this` and its parameters, each a
	// value of the runtime's: at up to four, it is called as the closure it
	// is (JsFunction.impl0...4, made when the function is), the arguments it
	// is not given undefined, those beyond it dropped; a built-in reading at
	// most three by their places, by its fixed entry)
	public static function call(f:Dynamic, thisArg:Dynamic, args:Array<Dynamic>):Dynamic {
		if (!Std.isOfType(f, JsFunction)) return error("TypeError", describe(f) + " is not a function");
		var fn:JsFunction = f;
		if (fn.native != null) return fn.native(thisArg, args, undef());
		if (fn.kind >= JsFunction.BASE) return error("TypeError", "Class constructor " + fn.name + " cannot be invoked without 'new'");
		if (!fn.rest) switch fn.arity {
			case 0: return fn.impl0(thisArg);
			case 1: return fn.impl1(thisArg, arg(args, 0));
			case 2: return fn.impl2(thisArg, arg(args, 0), arg(args, 1));
			case 3: return fn.impl3(thisArg, arg(args, 0), arg(args, 1), arg(args, 2));
			case 4: return fn.impl4(thisArg, arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3));
			case _:
		}
		var passed = positional(fn, args, 1);
		passed[0] = thisArg;
		return Reflect.callMethod(null, fn.impl, passed);
	}

	// a call of up to three arguments: no list where the function is compiled code or a fixed built-in
	public static function call0(f:Dynamic, thisArg:Dynamic):Dynamic {
		var fn:JsFunction = Std.isOfType(f, JsFunction) ? f : null;
		if (fn != null && fn.fixed != null) return fn.fixed(thisArg, undef(), undef(), undef());
		if (fn == null || fn.native != null || fn.kind >= JsFunction.BASE || fn.rest || fn.arity > 4) return call(f, thisArg, []);
		return switch fn.arity {
			case 0: fn.impl0(thisArg);
			case 1: fn.impl1(thisArg, undef());
			case 2: fn.impl2(thisArg, undef(), undef());
			case 3: fn.impl3(thisArg, undef(), undef(), undef());
			case _: fn.impl4(thisArg, undef(), undef(), undef(), undef());
		}
	}

	public static function call1(f:Dynamic, thisArg:Dynamic, a:Dynamic):Dynamic {
		var fn:JsFunction = Std.isOfType(f, JsFunction) ? f : null;
		if (fn != null && fn.fixed != null) return fn.fixed(thisArg, a, undef(), undef());
		if (fn == null || fn.native != null || fn.kind >= JsFunction.BASE || fn.rest || fn.arity > 4) return call(f, thisArg, [a]);
		return switch fn.arity {
			case 0: fn.impl0(thisArg);
			case 1: fn.impl1(thisArg, a);
			case 2: fn.impl2(thisArg, a, undef());
			case 3: fn.impl3(thisArg, a, undef(), undef());
			case _: fn.impl4(thisArg, a, undef(), undef(), undef());
		}
	}

	public static function call2(f:Dynamic, thisArg:Dynamic, a:Dynamic, b:Dynamic):Dynamic {
		var fn:JsFunction = Std.isOfType(f, JsFunction) ? f : null;
		if (fn != null && fn.fixed != null) return fn.fixed(thisArg, a, b, undef());
		if (fn == null || fn.native != null || fn.kind >= JsFunction.BASE || fn.rest || fn.arity > 4) return call(f, thisArg, [a, b]);
		return switch fn.arity {
			case 0: fn.impl0(thisArg);
			case 1: fn.impl1(thisArg, a);
			case 2: fn.impl2(thisArg, a, b);
			case 3: fn.impl3(thisArg, a, b, undef());
			case _: fn.impl4(thisArg, a, b, undef(), undef());
		}
	}

	public static function call3(f:Dynamic, thisArg:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic {
		var fn:JsFunction = Std.isOfType(f, JsFunction) ? f : null;
		if (fn != null && fn.fixed != null) return fn.fixed(thisArg, a, b, c);
		if (fn == null || fn.native != null || fn.kind >= JsFunction.BASE || fn.rest || fn.arity > 4) return call(f, thisArg, [a, b, c]);
		return switch fn.arity {
			case 0: fn.impl0(thisArg);
			case 1: fn.impl1(thisArg, a);
			case 2: fn.impl2(thisArg, a, b);
			case 3: fn.impl3(thisArg, a, b, c);
			case _: fn.impl4(thisArg, a, b, c, undef());
		}
	}

	public static function callMethod(o:Dynamic, k:Dynamic, args:Array<Dynamic>):Dynamic {
		var f = get(o, k);
		if (!Std.isOfType(f, JsFunction)) return error("TypeError", (isObject(o) ? describe(o) : Seed.typeOf(o)) + "." + key(k) + " is not a function");
		return call(f, o, args);
	}

	public static function callNamed(o:Dynamic, name:String, args:Array<Dynamic>):Dynamic {
		var f = getNamed(o, name);
		if (!Std.isOfType(f, JsFunction)) return error("TypeError", (isObject(o) ? describe(o) : Seed.typeOf(o)) + "." + name + " is not a function");
		return call(f, o, args);
	}

	public static function construct(f:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic {
		if (!isConstructor(f)) return error("TypeError", describe(f) + " is not a constructor");
		if (!isConstructor(newTarget)) return error("TypeError", "newTarget is not a constructor");
		var fn:JsFunction = f;
		if (fn.native != null) return fn.native(undef(), args, newTarget);
		var passed = positional(fn, args, fn.kind == JsFunction.PLAIN ? 1 : 2);
		switch (fn.kind) {
			case JsFunction.PLAIN:
				var obj = new JsObject(protoFrom(newTarget, Builtins.ObjectProto));
				passed[0] = obj;
				var r = Reflect.callMethod(null, fn.impl, passed);
				return isObject(r) ? r : obj;
			case JsFunction.BASE:
				var obj = allocate(newTarget, protoFrom(newTarget, Builtins.ObjectProto));
				initFields(fn, obj);
				passed[0] = obj;
				passed[1] = newTarget;
				var r = Reflect.callMethod(null, fn.impl, passed);
				return isObject(r) ? r : obj;
			case _:
				passed[0] = undef();
				passed[1] = newTarget;
				var r = Reflect.callMethod(null, fn.impl, passed);
				if (!isObject(r)) return error("ReferenceError", "Must call super constructor in derived class before accessing 'this' or returning from derived constructor");
				return r;
		}
	}

	// a class's new instance: the typed class's nearest newTarget (itself or
	// a superclass) lays it out, else it is a plain object
	public static function allocate(newTarget:Dynamic, proto:JsObject):JsObject {
		var f:Dynamic = newTarget;
		while (Std.isOfType(f, JsFunction)) {
			var fn:JsFunction = f;
			// (a proxy of a class: its target's instances)
			if (fn.bits & JsObject.PROXY != 0) {
				f = Exotics.target(fn);
				continue;
			}
			if (fn.alloc != null) {
				var obj = fn.alloc(proto);
				obj.setLayout(fn.instanceLayout);
				return obj;
			}
			f = fn.parent;
		}
		return new JsObject(proto);
	}

	// super(...) in a derived class constructor: the parent builds `this`, then this class's fields are set.
	public static function superConstruct(cls:Dynamic, args:Array<Dynamic>, newTarget:Dynamic):Dynamic {
		var fn:JsFunction = cls;
		if (!isConstructor(fn.parent)) return error("TypeError", "Super constructor " + Seed.text(fn.parent) + " of anonymous class is not a constructor");
		var obj = construct(fn.parent, args, newTarget);
		initFields(fn, obj);
		return obj;
	}

	static function initFields(fn:JsFunction, obj:Dynamic):Void if (fn.fields != null) Reflect.callMethod(null, fn.fields, [obj]);

	// A compiled function or arrow (kind METHOD) as a value.
	public static function makeFunction(impl:Dynamic, arity:Int, rest:Bool, kind:Int, name:String):Dynamic {
		var f = new JsFunction(Builtins.FunctionProto, kind, name, arity);
		f.impl = impl;
		f.rest = rest;
		if (!rest) switch arity {
			case 0: f.impl0 = impl;
			case 1: f.impl1 = impl;
			case 2: f.impl2 = impl;
			case 3: f.impl3 = impl;
			case 4: f.impl4 = impl;
			case _:
		}
		return f;
	}

	// A class: its constructor function and prototype object. parent is hole without extends.
	public static function makeClass(name:String, parent:Dynamic, impl:Dynamic, arity:Int, rest:Bool, fields:Dynamic):Dynamic {
		var derived = !same(parent, hole);
		var protoParent = Builtins.ObjectProto;
		var ctorProto = Builtins.FunctionProto;
		if (derived) {
			if (parent == null) protoParent = null;
			else {
				if (!isConstructor(parent)) return error("TypeError", "Class extends value " + describe(parent) + " is not a constructor or null");
				var pp = get(parent, "prototype");
				if (pp != null && !isObject(pp)) return error("TypeError", "Class extends value does not have valid prototype property " + Seed.text(pp));
				protoParent = pp;
				ctorProto = parent;
			}
		}
		var c = new JsFunction(ctorProto, derived ? JsFunction.DERIVED : JsFunction.BASE, name, arity);
		c.impl = impl;
		c.rest = rest;
		c.fields = fields;
		c.parent = derived ? parent : null;
		var proto = new JsObject(protoParent);
		proto.setOwn("constructor", c, Attr.HIDDEN);
		c.setOwn("prototype", proto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		return c;
	}

	// Methods (kind 0), getters (1) and setters (2) on a prototype, class or object literal.
	public static function defineMethod(target:Dynamic, k:Dynamic, fn:Dynamic, kind:Int, enumerable:Bool):Void {
		var obj:JsObject = target;
		var name = key(k);
		var attribute = enumerable ? 0 : Attr.HIDDEN;
		if (Std.isOfType(fn, JsFunction)) {
			var f:JsFunction = fn;
			f.name = (kind == 1 ? "get " : kind == 2 ? "set " : "") + Symbols.functionName(name);
		}
		if (kind == 0) {
			obj.setOwn(name, fn, attribute);
			return;
		}
		var current = obj.hasOwn(name) ? obj.getOwn(name) : null;
		var acc = Std.isOfType(current, Accessor) ? (current : Accessor) : new Accessor(null, null);
		if (kind == 1) acc.getter = fn; else acc.setter = fn;
		obj.setOwn(name, acc, attribute);
	}

	// Class fields and object literal properties: own data properties, defined (setters are not called).
	public static function defineField(target:Dynamic, k:Dynamic, v:Dynamic):Void {
		var obj:JsObject = target;
		var name = key(k);
		if (Std.isOfType(v, JsFunction) && (v : JsFunction).name == "" && (v : JsFunction).native == null) (v : JsFunction).name = Symbols.functionName(name);
		defineOwn(obj, name, v);
	}

	public static function setPrototype(o:Dynamic, proto:Dynamic):Void {
		if (!isObject(o) || proto != null && !isObject(proto)) return;
		if (!setPrototypeResult(o, proto)) error("TypeError", Exotics.is(o) ? "'setPrototypeOf' on proxy: trap returned falsish" : (o : JsObject).extensible ? "Cyclic __proto__ value" : describe(o) + " is not extensible");
	}

	// [[SetPrototypeOf]]: whether it was done (not where it is not extensible, or would make a cycle)
	public static function setPrototypeResult(o:JsObject, proto:Dynamic):Bool {
		if (o.bits & JsObject.PROXY != 0) return Exotics.setProto(o, proto);
		if (proto == o.proto) return true;
		if (!o.extensible) return false;
		var p:JsObject = proto;
		while (p != null && p.bits & JsObject.PROXY == 0) {
			if (p == o) return false;
			p = p.proto;
		}
		o.reproto(proto);
		return true;
	}

	// [[GetPrototypeOf]]
	public static function prototypeOf(o:JsObject):JsObject return o.bits & JsObject.PROXY != 0 ? Exotics.protoOf(o) : o.proto;

	// (an own property enumerable: a proxy's by its descriptor)
	public static function enumerableOwn(o:JsObject, k:String):Bool {
		if (o.bits & JsObject.PROXY == 0) return o.attr(k) & Attr.HIDDEN == 0;
		var d = Exotics.own(o, k);
		return !same(d, undef()) && Seed.truth(get(d, "enumerable"));
	}

	// Private class elements: own properties of their brand's key
	// ("\x00#name@class"), never listed (Attr.PRIVATE).
	static function privateName(brand:String):String return brand.substr(1).split("@")[0];

	static function privateSlot(o:Dynamic, brand:String):Int {
		if (!isObject(o)) return -1;
		var s = (o : JsObject).shape, i = s.slotOf(brand);
		return i >= 0 && s.attrs[i] & Attr.PRIVATE != 0 ? i : -1;
	}

	public static function privateGet(o:Dynamic, brand:String):Dynamic {
		var i = privateSlot(o, brand);
		if (i < 0) return error("TypeError", "Cannot read private member " + privateName(brand) + " from an object whose class did not declare it");
		var obj:JsObject = o;
		var v = obj.slots[i];
		if (obj.shape.attrs[i] & Attr.ACCESSOR != 0) {
			var acc:Accessor = v;
			return acc.getter == null ? error("TypeError", "'" + privateName(brand) + "' was defined without a getter") : call(acc.getter, o, []);
		}
		return v;
	}

	public static function privateSet(o:Dynamic, brand:String, v:Dynamic):Dynamic {
		var i = privateSlot(o, brand);
		if (i < 0) return error("TypeError", "Cannot write private member " + privateName(brand) + " to an object whose class did not declare it");
		var obj:JsObject = o;
		var a = obj.shape.attrs[i];
		if (a & Attr.ACCESSOR != 0) {
			var acc:Accessor = obj.slots[i];
			if (acc.setter == null) return error("TypeError", "'" + privateName(brand) + "' was defined without a setter");
			call(acc.setter, o, [v]);
			return v;
		}
		if (a & Attr.READONLY != 0) return error("TypeError", "Private method is not writable");
		obj.slots[i] = v;
		return v;
	}

	public static function privateDefine(o:Dynamic, brand:String, v:Dynamic, kind:Int):Void {
		var obj:JsObject = o;
		var i = privateSlot(o, brand);
		if (kind == 0 || kind == 3) {
			if (i >= 0 && kind == 0) error("TypeError", "Cannot initialize " + privateName(brand) + " twice on the same object");
			if (i >= 0) obj.slots[i] = v;
			else obj.add(brand, v, kind == 3 ? Attr.PRIVATE | Attr.READONLY : Attr.PRIVATE, Shapes.KEYS, false);
			return;
		}
		var current = i >= 0 ? obj.slots[i] : null;
		var acc = Std.isOfType(current, Accessor) ? (current : Accessor) : new Accessor(null, null);
		if (kind == 1) acc.getter = v; else acc.setter = v;
		if (i < 0) obj.add(brand, acc, Attr.PRIVATE | Attr.ACCESSOR, Shapes.KEYS, false);
		else obj.slots[i] = acc;
	}

	public static function privateHas(o:Dynamic, brand:String):Bool {
		if (!isObject(o)) return error("TypeError", "Cannot use 'in' operator to search for '" + privateName(brand) + "' in " + Seed.text(o));
		return privateSlot(o, brand) >= 0;
	}

	// super.x and super.m(...): lookups start above the method's home object.
	public static function superGet(home:Dynamic, thisArg:Dynamic, k:Dynamic):Dynamic {
		var h:JsObject = home;
		return h.proto == null ? undef() : getKey(h.proto, key(k), thisArg);
	}

	public static function superSet(home:Dynamic, thisArg:Dynamic, k:Dynamic, v:Dynamic):Dynamic {
		var h:JsObject = home;
		var name = key(k);
		var acc = findAccessor(h.proto, name);
		if (acc != null) {
			if (acc.setter != null) call(acc.setter, thisArg, [v]);
			return v;
		}
		setKey(thisArg, name, v, thisArg);
		return v;
	}

	public static function instanceOf(v:Dynamic, c:Dynamic):Bool {
		if (!isObject(c)) return error("TypeError", "Right-hand side of 'instanceof' is not " + (isObject(c) ? "callable" : "an object"));
		var custom = getKey(c, Symbols.hasInstance, c);
		if (!same(custom, undef()) && custom != null) return Seed.truth(call(custom, c, [v]));
		if (!Std.isOfType(c, JsFunction)) return error("TypeError", "Right-hand side of 'instanceof' is not callable");
		var f:JsFunction = c;
		if (f.native != null && f.hasOwn(Builtins.boundTarget)) return instanceOf(v, f.getOwn(Builtins.boundTarget));
		if (!isObject(v)) return false;
		var p = get(c, "prototype");
		if (!isObject(p)) return error("TypeError", "Function has non-object prototype '" + Seed.text(p) + "' in instanceof check");
		var o:JsObject = prototypeOf(v);
		while (o != null) {
			if (o == p) return true;
			o = prototypeOf(o);
		}
		return false;
	}

	// Conversions.
	public static function toPrimitive(o:Dynamic, hint:String):Dynamic {
		if (!isObject(o)) return o;
		var exotic = getKey(o, Symbols.toPrimitive, o);
		if (!same(exotic, undef()) && exotic != null) {
			var r = call(exotic, o, [hint]);
			if (!isObject(r)) return r;
			return error("TypeError", "Cannot convert object to primitive value");
		}
		var order = hint == "string" ? ["toString", "valueOf"] : ["valueOf", "toString"];
		for (m in order) {
			var f = getKey(o, m, o);
			if (isCallable(f)) {
				var r = call(f, o, []);
				if (!isObject(r)) return r;
			}
		}
		return error("TypeError", "Cannot convert object to primitive value");
	}

	public static function toObject(v:Dynamic):JsObject {
		if (v == null || same(v, undef())) return error("TypeError", "Cannot convert undefined or null to object");
		return isObject(v) ? v : Objects.wrap(v);
	}

	// Arrays, objects and iteration.
	public static function array(items:Array<Dynamic>):Dynamic {
		var a = new JsArray(Builtins.ArrayProto);
		a.items = items;
		a.length = items.length;
		return a;
	}

	static var stepShape:Shape = null;

	// an iterator's result, {value, done}: its shape made once
	public static function iterResult(value:Dynamic, done:Bool):Dynamic {
		var o = new JsObject(Builtins.ObjectProto);
		if (stepShape == null) stepShape = Shapes.literal(["value", "done"]);
		o.shape = stepShape;
		o.slots = [value, done];
		return o;
	}

	public static function object(keys:Array<Dynamic>, values:Array<Dynamic>):Dynamic {
		var o = new JsObject(Builtins.ObjectProto);
		for (i in 0...keys.length) defineOwn(o, key(keys[i]), values[i]);
		return o;
	}

	public static function iterator(o:Dynamic):Dynamic {
		var method = o == null || same(o, undef()) ? undef() : getKey(o, Symbols.iterator, o);
		if (!isCallable(method)) return error("TypeError", (isObject(o) ? "object" : Seed.text(o)) + " is not iterable");
		var it = call(method, o, []);
		if (!isObject(it)) return error("TypeError", "Result of the Symbol.iterator method is not an object");
		return it;
	}

	public static function next(it:Dynamic):Dynamic {
		if (Std.isOfType(it, JsIterator)) return Builtins.iteratorNext(it);
		var r = callMethod(it, "next", []);
		if (!isObject(r)) return error("TypeError", "Iterator result " + Seed.text(r) + " is not an object");
		return r;
	}

	// The next value of an iterator, or `finished`.
	public static function iterate(it:Dynamic):Dynamic {
		if (Std.isOfType(it, JsIterator)) {
			var i:JsIterator = it;
			if (i.finished) return finished;
			var v = Builtins.iteratorStep(i);
			if (same(v, finished)) i.finished = true;
			return v;
		}
		var r = next(it);
		return Seed.truth(get(r, "done")) ? finished : get(r, "value");
	}

	// Destructuring: the next value (undefined once done), and the rest as an array.
	public static function step(it:Dynamic):Dynamic {
		var v = iterate(it);
		return same(v, finished) ? undef() : v;
	}

	// IteratorClose: an iterator left before its end (a for-of left by a
	// break, return or throw; a pattern that took what it needed) told by its
	// return method; after a throw that error stands, not return's
	public static function close(it:Dynamic, threw:Bool):Void {
		// (the built-in iterators have no return)
		if (it == null || same(it, undef()) || Std.isOfType(it, JsIterator)) return;
		if (!threw) {
			closeNow(it);
			return;
		}
		try closeNow(it) catch (_:Dynamic) {}
	}

	static function closeNow(it:Dynamic):Void {
		var method = get(it, "return");
		if (method == null || same(method, undef())) return;
		var r = call(method, it, []);
		if (!isObject(r)) error("TypeError", "Iterator result " + Seed.text(r) + " is not an object");
	}

	public static function restArray(it:Dynamic):Dynamic {
		var values = [];
		while (true) {
			var v = iterate(it);
			if (same(v, finished)) break;
			values.push(v);
		}
		return array(values);
	}

	// (an array iterated as Array.prototype's iterator does, by index: its
	// prototype's, frozen, and no iterator of its own)
	public static function arrayIteration(a:JsArray):Bool
		return a.proto == Builtins.ArrayProto && !Builtins.arrayIterationChanged && (a.shape == Shapes.array || !a.hasOwn(Symbols.iterator));

	public static function toList(o:Dynamic):Array<Dynamic> {
		if (Std.isOfType(o, JsArray) && arrayIteration(o)) {
			var a:JsArray = cast o;
			var out = [for (v in a.elements()) same(v, hole) ? undef() : v];
			while (out.length < a.length) out.push(get(a, out.length));
			return out;
		}
		var it = iterator(o);
		var values = [];
		while (true) {
			var v = iterate(it);
			if (same(v, finished)) break;
			values.push(v);
		}
		return values;
	}

	// for-in: enumerable string keys of the object and its prototypes, each once.
	public static function forInKeys(o:Dynamic):Dynamic {
		if (o == null || same(o, undef())) return array([]);
		var obj = toObject(o);
		var seen:Map<String, Bool> = [];
		var out:Array<Dynamic> = [];
		while (obj != null) {
			var proxy = obj.bits & JsObject.PROXY != 0;
			// (a proxy's keys, then its prototype, then which keys are enumerable: V8's order)
			var keys = Objects.ownPropertyKeys(obj), next = prototypeOf(obj);
			for (k in keys) {
				if (Symbols.isSymbolKey(k) || seen.exists(k)) continue;
				seen.set(k, true);
				if (proxy ? enumerableOwn(obj, k) : obj.attr(k) & Attr.HIDDEN == 0 && hasOwnKey(obj, k) && !(obj.form == Form.ARRAY && k == "length") && !(obj.form == Form.FUNCTION && !obj.hasOwn(k))) out.push(k);
			}
			obj = next;
		}
		return array(out);
	}

	public static function requireObject(o:Dynamic):Void if (o == null || same(o, undef())) error("TypeError", "Cannot destructure '" + Seed.text(o) + "' as it is " + Seed.text(o) + ".");

	public static function objectRest(o:Dynamic, used:Array<Dynamic>):Dynamic {
		var excluded = [for (k in used) key(k)];
		var r = new JsObject(Builtins.ObjectProto);
		for (k in keys(o)) if (excluded.indexOf(k) < 0) r.setOwn(k, get(o, k));
		return r;
	}

	// (object spread: own enumerable properties; null and undefined add nothing)
	public static function assignSpread(target:Dynamic, source:Dynamic):Void {
		if (source == null || same(source, undef())) return;
		// (an empty object given an ordinary one's plain properties: its shape and their values)
		if (Std.isOfType(target, JsObject) && Std.isOfType(source, JsObject)) {
			var t:JsObject = target, s:JsObject = source;
			if (t.shape == Shapes.object && t.extensible && s.layout == null && s.shape.root == Shapes.object && s.shape.plain && s.slots != null) {
				t.shape = s.shape;
				t.slots = s.slots.copy();
				return;
			}
			// (an object type's instance of nothing beyond its slots: its names' shape)
			if (t.shape == Shapes.object && t.extensible && s.layout != null && s.layout.plain && s.shape == s.layout.root && s.layout.ordinary() != null) {
				var l = s.layout;
				t.shape = l.ordinary();
				t.slots = [for (i in 0...l.names.length) l.get(s, i)];
				return;
			}
		}
		// (a proxy's, CopyDataProperties': each key's descriptor, then its value)
		if (Exotics.is(source)) {
			for (k in Exotics.keys(source)) if (enumerableOwn(source, k)) defineOwn(target, k, getKey(source, k, source));
			return;
		}
		for (k in keys(source)) defineOwn(target, k, get(source, k));
	}

	public static function appendAll(list:Array<Dynamic>, source:Dynamic):Void for (v in toList(source)) list.push(v);

	public static function relation(a:Dynamic, b:Dynamic, op:String):Bool {
		a = toPrimitive(a, "number");
		b = toPrimitive(b, "number");
		if (Std.isOfType(a, String) && Std.isOfType(b, String)) {
			var c = compareStrings(a, b);
			return op == "<" ? c < 0 : op == "<=" ? c <= 0 : op == ">" ? c > 0 : c >= 0;
		}
		var x = Seed.numeric(a), y = Seed.numeric(b);
		return op == "<" ? x < y : op == "<=" ? x <= y : op == ">" ? x > y : x >= y;
	}

	public static function compareStrings(a:String, b:String):Int {
		var n = a.length < b.length ? a.length : b.length;
		for (i in 0...n) {
			var x = StringTools.fastCodeAt(a, i), y = StringTools.fastCodeAt(b, i);
			if (x < y) return -1;
			if (x > y) return 1;
		}
		return a.length < b.length ? -1 : a.length > b.length ? 1 : 0;
	}

	public static function toIntegerOrInfinity(v:Dynamic):Float {
		var n = Seed.numeric(v);
		return Math.isNaN(n) || n == 0 ? 0 : !Math.isFinite(n) ? n : n < 0 ? Math.fceil(n) : Math.ffloor(n);
	}

	public static function toUint32(v:Dynamic):Float {
		var n = toIntegerOrInfinity(v);
		if (!Math.isFinite(n)) return 0;
		n = n % 4294967296.0;
		return n < 0 ? n + 4294967296.0 : n;
	}

	public static function toInt32(v:Dynamic):Int {
		var n = toUint32(v);
		return Std.int(n >= 2147483648.0 ? n - 4294967296.0 : n);
	}

	public static function sameValueZero(a:Dynamic, b:Dynamic):Bool return Seed.strictEq(a, b) || isNumber(a) && isNumber(b) && Math.isNaN(a) && Math.isNaN(b);

	public static function sameValue(a:Dynamic, b:Dynamic):Bool {
		if (isNumber(a) && isNumber(b)) {
			var x:Float = a, y:Float = b;
			if (Math.isNaN(x)) return Math.isNaN(y);
			if (x == 0 && y == 0) return 1 / x == 1 / y;
			return x == y;
		}
		return Seed.strictEq(a, b);
	}
}
