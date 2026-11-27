package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Strings.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// Built-in objects: prototypes, constructors and their methods.
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Strings)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Builtins {
	public static var ObjectProto:JsObject;
	public static var FunctionProto:JsObject;
	public static var ArrayProto:JsObject;
	public static var StringProto:JsObject;
	public static var NumberProto:JsObject;
	public static var BooleanProto:JsObject;
	public static var SymbolProto:JsObject;
	public static var ErrorProto:JsObject;
	public static var IteratorProto:JsObject;
	public static var ArrayIteratorProto:JsObject;
	public static var MapIteratorProto:JsObject;
	public static var SetIteratorProto:JsObject;
	public static var StringIteratorProto:JsObject;
	public static var MapProto:JsObject;
	public static var SetProto:JsObject;
	public static var globals:Map<String, Dynamic> = null;
	public static var arrayIterationChanged = false;
	// (Array.prototype's push or pop replaced or deleted: Seed.libPushNumber's guard)
	public static var arrayMethodsChanged = false;
	static var watching = false;

	public static function arrayProtoChanged(k:String):Void {
		if (!watching) return;
		if (k == "push" || k == "pop") arrayMethodsChanged = true;
		if (k == Symbols.iterator) arrayIterationChanged = true;
	}
	public static var boundTarget = "\x00@target";
	static var errors:Map<String, JsFunction> = [];
	static var ready = false;
	static var asyncExpected = false;
	static var asyncDone = 0;
	public static function checkAsyncTest():Void {
		if (asyncExpected && asyncDone != 1) error("Test262Error", "$DONE was not called exactly once");
	}

	public static function nativeFunction(name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic, constructor = false):JsFunction return native(name, arity, fn, constructor);

	static function native(name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic, constructor = false):JsFunction {
		var f = new JsFunction(FunctionProto, constructor ? JsFunction.PLAIN : JsFunction.METHOD, name, arity);
		f.native = fn;
		return f;
	}

	static function method(target:JsObject, name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic):Void
		target.setOwn(name, native(Symbols.functionName(name), arity, fn), Attr.HIDDEN);

	// a method reading at most three arguments, each by its place: its fixed
	// entry (JsFunction.fixed, what Lib.call0...3 call: no list), the list's form made from it
	static function fixed(target:JsObject, name:String, arity:Int, fn:(Dynamic, Dynamic, Dynamic, Dynamic) -> Dynamic):Void {
		var f = native(Symbols.functionName(name), arity, (t, a, _) -> fn(t, arg(a, 0), arg(a, 1), arg(a, 2)));
		f.fixed = fn;
		target.setOwn(name, f, Attr.HIDDEN);
	}

	static function getter(target:JsObject, name:String, fn:Dynamic->Dynamic):Void
		target.setOwn(name, new Accessor(native("get " + Symbols.functionName(name), 0, (t, _, _) -> fn(t)), null), Attr.HIDDEN);

	static function constant(target:JsObject, name:String, v:Dynamic):Void target.setOwn(name, v, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);

	static function constructor(name:String, arity:Int, proto:JsObject, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic):JsFunction {
		var c = native(name, arity, fn, true);
		c.setOwn("prototype", proto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		proto.setOwn("constructor", c, Attr.HIDDEN);
		globals.set(name, c);
		return c;
	}

	static function callback(f:Dynamic):Dynamic {
		if (!isCallable(f)) error("TypeError", Seed.text(f) + " is not a function");
		return f;
	}

	public static function init():Void {
		if (ready) return;
		ready = true;
		globals = [];
		ObjectProto = new JsObject(null);
		FunctionProto = new JsFunction(ObjectProto, JsFunction.METHOD, "", 0);
		(cast FunctionProto : JsFunction).native = (_, _, _) -> undef();
		ArrayProto = new JsArray(ObjectProto);
		// (its own shape: its writes are watched, so no site writes it from a record)
		ArrayProto.shape = ArrayProto.shape.dictionary();
		StringProto = new JsObject(ObjectProto);
		NumberProto = new JsObject(ObjectProto);
		BooleanProto = new JsObject(ObjectProto);
		SymbolProto = new JsObject(ObjectProto);
		ErrorProto = new JsObject(ObjectProto);
		IteratorProto = new JsObject(ObjectProto);
		ArrayIteratorProto = new JsObject(IteratorProto);
		MapIteratorProto = new JsObject(IteratorProto);
		SetIteratorProto = new JsObject(IteratorProto);
		StringIteratorProto = new JsObject(IteratorProto);
		MapProto = new JsObject(ObjectProto);
		SetProto = new JsObject(ObjectProto);
		setupObject();
		setupFunction();
		setupArray();
		setupString();
		setupNumber();
		setupBoolean();
		setupSymbol();
		setupErrors();
		setupIterators();
		setupCollections();
		setupGlobals();
		Numbers.setup();
		Async.setup();
		freeze();
		watching = true;
	}

	// The built-ins' members frozen (Attr.FROZEN), those of Object, Array,
	// String, Number, Boolean, Symbol, Map, Set, WeakMap, WeakSet, Promise,
	// RegExp, Date, JSON, Math, Reflect and the typed arrays, their
	// constructors and prototypes: compiled code calls them as they are
	// (lower.Expressions' iteration loops), and a write to one throws.
	// Members a later installer adds are frozen after it.
	static final frozen = ["Object", "Array", "String", "Number", "Boolean", "Symbol", "Map", "Set", "WeakMap", "WeakSet", "Promise", "RegExp", "Date", "JSON", "Math",
		"Reflect", "ArrayBuffer", "DataView", "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float16Array",
		"Float32Array", "Float64Array"];

	static function freeze():Void {
		function members(o:JsObject) {
			var names = o.ownNames();
			if (names != null) for (k in names.copy()) {
				var a = o.attr(k);
				if (a & Attr.FROZEN == 0) o.setOwn(k, o.getOwn(k), a | Attr.FROZEN | Attr.LOCKED);
			}
		}
		for (name in frozen) {
			var g:Dynamic = globals.get(name);
			if (!Std.isOfType(g, JsObject)) continue;
			var o:JsObject = g;
			members(o);
			if (!Std.isOfType(o, JsFunction) || !o.hasOwn("prototype")) continue;
			var p:JsObject = o.getOwn("prototype");
			while (p != null && p != ObjectProto) {
				members(p);
				p = p.proto;
			}
		}
		members(ObjectProto);
	}

	// The built-ins a program installs when it uses them (the frontend calls
	// these, helder.typescript.lower.Features): what it does not install is
	// code nothing reaches, which hxmc leaves out.
	static var installed:Map<String, Bool> = [];

	static function once(group:String):Bool {
		if (installed.exists(group)) return false;
		installed.set(group, true);
		return true;
	}

	public static function installRegExp() if (once("RegExp")) {
		Regex.setup();
		RegexEscapes.setup();
		createRegExp = Regex.create;
		freeze();
		publish();
	}

	public static function installNormalize() if (once("normalize")) normalizeString = Normalization.normalize;

	// (\p{...}'s tables: a program whose patterns name a property)
	public static function installRegExpProperties() if (once("RegExp properties")) {
		installRegExp();
		Regex.properties = UnicodeProperties.lookup;
	}

	public static function installDate() if (once("Date")) {
		Dates.setup();
		freeze();
		publish();
	}

	public static function installBuffers() if (once("buffers")) {
		Buffers.setup();
		freeze();
		publish();
	}

	public static function installTypedArrays() if (once("typed arrays")) {
		TypedArrays.install();
		freeze();
		publish();
	}

	public static function installJson() if (once("JSON")) {
		Json.setup();
		freeze();
		publish();
	}

	public static function installIteratorHelpers() if (once("Iterator")) {
		Iterators.setup();
		freeze();
		publish();
	}

	public static function installPromise() if (once("Promise")) {
		Promises.setup();
		freeze();
		publish();
	}

	public static function installFromAsync() if (once("fromAsync")) {
		installPromise();
		AsyncArray.setup();
		freeze();
	}

	public static function installSetMethods() if (once("Set methods")) {
		Sets.setup();
		freeze();
	}

	public static function installUri() if (once("URI")) {
		globals.set("encodeURIComponent", native("encodeURIComponent", 1, (_, a, _) -> encodeUri(Seed.text(arg(a, 0)), "-_.!~*'()")));
		globals.set("encodeURI", native("encodeURI", 1, (_, a, _) -> encodeUri(Seed.text(arg(a, 0)), "-_.!~*'();/?:@&=+$,#")));
		globals.set("decodeURIComponent", native("decodeURIComponent", 1, (_, a, _) -> decodeUri(Seed.text(arg(a, 0)), "")));
		globals.set("decodeURI", native("decodeURI", 1, (_, a, _) -> decodeUri(Seed.text(arg(a, 0)), ";/?:@&=+$,#")));
		freeze();
		publish();
	}

	public static function installProxy() if (once("Proxy")) {
		Proxies.setup();
		freeze();
		publish();
	}

	public static function installReflect() if (once("Reflect")) {
		Globals.setupReflect();
		freeze();
		publish();
	}

	public static function installStructuredClone() if (once("structuredClone")) {
		globals.set("structuredClone", native("structuredClone", 1, (_, a, _) -> clone(arg(a, 0), new haxe.ds.ObjectMap())));
		freeze();
		publish();
	}

	// everything, for a program the frontend cannot see through (globalThis by a computed name)
	public static function installAll() {
		installRegExp();
		installRegExpProperties();
		installNormalize();
		installDate();
		installBuffers();
		installTypedArrays();
		installJson();
		installIteratorHelpers();
		installPromise();
		installFromAsync();
		installSetMethods();
		installUri();
		installStructuredClone();
		installProxy();
		installReflect();
	}

	// an installer's new globals, also as globalThis's properties
	static function publish() {
		var g:JsObject = globals.get("globalThis");
		for (name => v in globals) if (name != "globalThis" && !g.hasOwn(name)) g.setOwn(name, v, Attr.HIDDEN);
	}

	// (set by their installers: the string methods that need them reach them through these)
	static var createRegExp:(String, String) -> Dynamic = null;
	static var normalizeString:(String, String) -> String = null;

	public static function global(name:String):Dynamic {
		if (globals.exists(name)) return globals.get(name);
		return error("ReferenceError", name + " is not defined");
	}

	// Function
	static function setupFunction():Void {
		var p = FunctionProto;
		var poison = native("", 0, (_, _, _) -> error("TypeError", "Restricted function property"));
		poison.setOwn("name", "", Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		poison.setOwn("length", 0, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		poison.extensible = false;
		for (name in ["caller", "arguments"]) p.setOwn(name, new Accessor(poison, poison), Attr.HIDDEN);
		method(p, "call", 1, (t, a, _) -> call(t, arg(a, 0), a.slice(1)));
		fixed(p, "apply", 2, (t, a0:Dynamic, a1:Dynamic, _) -> call(t, a0, a1 == null || a1 == undef() ? [] : arrayLikeList(a1)));
		method(p, "bind", 1, (t, a, _) -> {
			var target:JsFunction = callback(t);
			var self = arg(a, 0);
			var bound = a.slice(1);
			var f:JsFunction = null;
			f = native("bound " + target.name, Std.int(Math.max(0, (target.rest ? target.arity - 1 : target.arity) - bound.length)), (_, more, nt) -> nt == undef() ? call(target, self, bound.concat(more)) : construct(target, bound.concat(more), nt == f ? target : nt), isConstructor(target));
			f.setOwn(boundTarget, target, Attr.HIDDEN);
			return f;
		});
		fixed(p, "toString", 0, (t, _, _, _) -> {
			if (!Std.isOfType(t, JsFunction)) error("TypeError", "Function.prototype.toString requires that 'this' be a Function");
			var f:JsFunction = cast t;
			return (f.kind >= JsFunction.BASE ? "class " + f.name + " { }" : "function " + f.name + "() { [native code] }");});
		fixed(p, Symbols.hasInstance, 1, (t, a0:Dynamic, _, _) -> {
			if (!Std.isOfType(t, JsFunction)) return false;
			var p = get(t, "prototype");
			var v = a0;
			if (!isObject(v) || !isObject(p)) return false;
			var o = prototypeOf(v);
			while (o != null) {
				if (o == p) return true;
				o = prototypeOf(o);
			}
			return false;});
		var c = constructor("Function", 1, p, (_, _, _) -> error("EvalError", "Code generation from strings is not supported"));
	}

	// Number, Boolean, Symbol
	static function setupNumber():Void {
		var p = NumberProto;
		p.setOwn("\x00@primitive", 0.0, Attr.HIDDEN);
		var c = constructor("Number", 1, p, (_, a, nt) -> {
			var v:Float = a.length == 0 ? 0 : Seed.numeric(isObject(a[0]) ? toPrimitive(a[0], "number") : a[0]);
			if (nt == undef()) return (v : Dynamic);
			var o = wrap(v);
			o.proto = protoFrom(nt, NumberProto);
			return o;});
		fixed(c, "isNaN", 1, (_, a0:Dynamic, _, _) -> isNumber(a0) && Math.isNaN(a0));
		fixed(c, "isFinite", 1, (_, a0:Dynamic, _, _) -> isNumber(a0) && Math.isFinite(a0));
		fixed(c, "isInteger", 1, (_, a0:Dynamic, _, _) -> {
			var v = a0;
			return isNumber(v) && Math.isFinite(v) && Math.ffloor(v) == v;});
		fixed(c, "isSafeInteger", 1, (_, a0:Dynamic, _, _) -> {
			var v = a0;
			return isNumber(v) && Math.isFinite(v) && Math.ffloor(v) == v && Math.abs(v) <= 9007199254740991.0;});
		constant(c, "NaN", Math.NaN);
		constant(c, "POSITIVE_INFINITY", Math.POSITIVE_INFINITY);
		constant(c, "NEGATIVE_INFINITY", Math.NEGATIVE_INFINITY);
		constant(c, "MAX_SAFE_INTEGER", 9007199254740991.0);
		constant(c, "MIN_SAFE_INTEGER", -9007199254740991.0);
		constant(c, "EPSILON", 2.220446049250313e-16);
		constant(c, "MAX_VALUE", 1.7976931348623157e308);
		constant(c, "MIN_VALUE", 5e-324);
		fixed(p, "valueOf", 0, (t, _, _, _) -> primitive(t, "number"));
	}

	static function setupBoolean():Void {
		var p = BooleanProto;
		p.setOwn("\x00@primitive", false, Attr.HIDDEN);
		constructor("Boolean", 1, p, (_, a, nt) -> {
			var v = Seed.truth(arg(a, 0));
			if (nt == undef()) return (v : Dynamic);
			var o = wrap(v);
			o.proto = protoFrom(nt, BooleanProto);
			return o;});
		fixed(p, "toString", 0, (t, _, _, _) -> primitive(t, "boolean") ? "true" : "false");
		fixed(p, "valueOf", 0, (t, _, _, _) -> primitive(t, "boolean"));
	}

	static function setupSymbol():Void {
		var p = SymbolProto;
		var c = constructor("Symbol", 0, p, (_, a, nt) -> {
			if (nt != undef()) error("TypeError", "Symbol is not a constructor");
			return Symbols.create(arg(a, 0) == undef() ? undef() : Seed.text(arg(a, 0)));});
		for (name in ["iterator", "asyncIterator", "hasInstance", "toPrimitive", "toStringTag", "isConcatSpreadable", "match", "matchAll", "replace", "search", "split", "species", "unscopables", "dispose", "asyncDispose"]) constant(c, name, Symbols.wellKnown(name));
		fixed(c, "for", 1, (_, a0:Dynamic, _, _) -> Symbols.symbolFor(Seed.text(a0)));
		fixed(c, "keyFor", 1, (_, a0:Dynamic, _, _) -> {
			var s = a0;
			if (!Std.isOfType(s, Symbols.JsSymbol)) error("TypeError", Seed.text(s) + " is not a symbol");
			for (k => v in Symbols.registry) if (v == s) return k;
			return undef();});
		fixed(p, "toString", 0, (t, _, _, _) -> Symbols.text(primitive(t, "symbol")));
		fixed(p, "valueOf", 0, (t, _, _, _) -> primitive(t, "symbol"));
		getter(p, "description", t -> (primitive(t, "symbol") : Symbols.JsSymbol).description);
		p.setOwn(Symbols.toStringTag, "Symbol", Attr.HIDDEN | Attr.READONLY);
		fixed(p, Symbols.toPrimitive, 1, (t, _, _, _) -> primitive(t, "symbol"));
	}

	// Errors
	public static function makeError(name:String, message:String):Dynamic {
		if (!ready) init();
		var c = errors.exists(name) ? errors.get(name) : errors.get("Error");
		return construct(c, [message], c);
	}

	static function setupErrors():Void {
		var base:JsFunction = null;
		// (each error's own stack, written when first read: Frames)
		var stack = new Accessor(native("stack", 0, (t, _, _) -> stackText(t)), native("stack", 1, (t, v, _) -> {
			(t : JsObject).setOwn("stack", arg(v, 0), Attr.HIDDEN);
			return undef();}));
		for (name in ["Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError", "URIError", "EvalError", "AggregateError", "Test262Error"]) {
			var p = name == "Error" ? ErrorProto : new JsObject(ErrorProto);
			p.setOwn("name", name, Attr.HIDDEN);
			p.setOwn("message", "", Attr.HIDDEN);
			var aggregate = name == "AggregateError";
			var c:JsFunction = null;
			c = constructor(name, aggregate ? 2 : 1, p, (_, a, nt) -> {
				var o = new JsError(protoFrom(nt == undef() ? c : nt, p));
				o.frames = Frames.capture();
				o.site = Frames.site;
				o.awaits = Async.awaits();
				var message = arg(a, aggregate ? 1 : 0);
				if (message != undef()) o.setOwn("message", Seed.text(message), Attr.HIDDEN);
				var options = arg(a, aggregate ? 2 : 1);
				if (isObject(options) && has(options, "cause")) o.setOwn("cause", get(options, "cause"), Attr.HIDDEN);
				if (aggregate) o.setOwn("errors", array(toList(arg(a, 0))), Attr.HIDDEN);
				o.setOwn("stack", stack, Attr.HIDDEN);
				return o;
			});
			if (name == "Error") {
				base = c;
				fixed(c, "isError", 1, (_, a0:Dynamic, _, _) -> Std.isOfType(a0, JsError));
				c.setOwn("stackTraceLimit", (Frames.MAX : Float), 0);
				// (constructorOpt, the frames above a function left out, is not: the stack is from here)
				fixed(c, "captureStackTrace", 1, (_, a0:Dynamic, _, _) -> {
					var o = a0;
					if (!isObject(o)) error("TypeError", "Invalid argument");
					put(o, "stack", errorText(o) + Frames.text(Frames.capture(), Frames.site, Async.awaits(), stackTraceLimit()));
					return undef();});
				fixed(p, "toString", 0, (t, _, _, _) -> {
					if (!isObject(t)) error("TypeError", "Error.prototype.toString called on non-object");
					return errorText(t);});
			}
			else c.proto = base;
			errors.set(name, c);
		}
	}

	// an error's stack: its text as it is when first read, then where it was made
	static function stackText(t:Dynamic):Dynamic {
		if (!Std.isOfType(t, JsError)) return undef();
		var e:JsError = t;
		if (e.stack == null) {
			e.stack = errorText(e) + Frames.text(e.frames, e.site, e.awaits, stackTraceLimit());
			e.frames = null;
			e.awaits = null;
		}
		return e.stack;
	}

	// (Error.stackTraceLimit, when the stack is written)
	static function stackTraceLimit():Int {
		var v = get(errors.get("Error"), "stackTraceLimit");
		return Std.isOfType(v, Float) && v > 0 ? (v > 1000 ? 1000 : Std.int(v)) : 0;
	}

	// what an uncaught error prints: its stack, else (a value thrown that is
	// no error) the value and where it was thrown
	public static function uncaughtText(e:Dynamic, ?thrown:haxe.io.Bytes):String {
		if (Std.isOfType(e, JsError)) {
			var s = get(e, "stack");
			return Std.isOfType(s, String) ? s : errorText(e);
		}
		return Inspect.inspect(e) + (thrown == null ? "" : Frames.text(thrown, Frames.site, null, stackTraceLimit()));
	}

	public static function errorText(t:Dynamic):String {
		var name = get(t, "name");
		var message = get(t, "message");
		var n = name == undef() ? "Error" : Seed.text(name);
		var m = message == undef() ? "" : Seed.text(message);
		return n == "" ? m : m == "" ? n : n + ": " + m;
	}

	// Iterators
	static function setupIterators():Void {
		fixed(IteratorProto, Symbols.iterator, 0, (t, _, _, _) -> t);
		for (p in [ArrayIteratorProto, MapIteratorProto, SetIteratorProto, StringIteratorProto])
			fixed(p, "next", 0, (t, _, _, _) -> {
				if (!Std.isOfType(t, JsIterator)) error("TypeError", "next method called on incompatible receiver " + Seed.text(t));
				return iteratorNext(t);});
		ArrayIteratorProto.setOwn(Symbols.toStringTag, "Array Iterator", Attr.HIDDEN | Attr.READONLY);
		MapIteratorProto.setOwn(Symbols.toStringTag, "Map Iterator", Attr.HIDDEN | Attr.READONLY);
		SetIteratorProto.setOwn(Symbols.toStringTag, "Set Iterator", Attr.HIDDEN | Attr.READONLY);
		StringIteratorProto.setOwn(Symbols.toStringTag, "String Iterator", Attr.HIDDEN | Attr.READONLY);
	}

	public static function iteratorNext(it:JsIterator):Dynamic {
		var v = it.finished ? finished : iteratorStep(it);
		if (v == finished) {
			it.finished = true;
			return iterResult(undef(), true);
		}
		return iterResult(v, false);
	}

	public static function iteratorStep(it:JsIterator):Dynamic {
		var target:Dynamic = it.target;
		if (Std.isOfType(target, JsMap)) {
			var m:JsMap = target;
			while (it.index < m.keys.length) {
				var i = Std.int(it.index++);
				if (!m.active[i]) continue;
				return it.kind == "keys" ? m.keys[i] : it.kind == "entries" ? array([m.keys[i], m.values[i]]) : m.values[i];
			}
			return finished;
		}
		if (Std.isOfType(target, String)) {
			var s:String = target;
			if (it.index >= s.length) return finished;
			var i = Std.int(it.index++);
			var c = s.charCodeAt(i);
			// (iteration combines a valid surrogate pair, unlike indexed access)
			if (c >= 0xd800 && c <= 0xdbff && it.index < s.length) {
				var low = s.charCodeAt(i + 1);
				if (low >= 0xdc00 && low <= 0xdfff) {
					it.index++;
					return s.substr(i, 2);
				}
			}
			return s.charAt(i);
		}
		if (it.index >= lengthOf(target)) return finished;
		var i = it.index++;
		return it.kind == "keys" ? i : it.kind == "entries" ? array([i, get(target, i)]) : get(target, i);
	}
}
