package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

// A proxy's target and handler (both null once revoked).
class ProxyParts {
	public var target:Null<JsObject>;
	public var handler:Null<JsObject>;

	public function new(target, handler) {
		this.target = target;
		this.handler = handler;
	}
}

// A proxy of an object that is no function, and of one that is (callable
// as its target is: its native runs the apply and construct traps). Each
// has a dictionary shape of its own, empty: no site records one, so every
// access takes the runtime's way, which finds the proxy by its bit
// (JsObject.PROXY) and runs its handler's trap.
class JsProxy extends JsObject {
	public final parts:ProxyParts;

	public function new(parts:ProxyParts) {
		super(null);
		this.parts = parts;
		shape = shape.dictionary();
		bits |= JsObject.PROXY;
	}

	override public function tag():String return parts.target == null ? "Object" : Proxies.isArray(this) ? "Array" : "Object";
}

class JsCallableProxy extends JsFunction {
	public final parts:ProxyParts;

	public function new(parts:ProxyParts) {
		var f:JsFunction = cast parts.target;
		super(Builtins.FunctionProto, f.kind, f.name, f.arity);
		this.parts = parts;
		shape = shape.dictionary();
		bits |= JsObject.PROXY;
		native = (t, a, nt) -> same(nt, undef()) ? Proxies.apply(this, t, a) : Proxies.create(this, a, nt);
	}
}

// The proxy's internal methods (ECMA-262 10.5): each its handler's trap
// where it has one, its result checked against the target's invariants,
// else the target's own.
@:access(helder.typescript.js.Builtins)
class Proxies {
	public static inline function is(o:Dynamic):Bool return Std.isOfType(o, JsObject) && (o : JsObject).bits & JsObject.PROXY != 0;

	static function parts(p:JsObject):ProxyParts return Std.isOfType(p, JsProxy) ? (cast p : JsProxy).parts : (cast p : JsCallableProxy).parts;

	public static function setup():Void {
		Exotics.read = read;
		Exotics.write = write;
		Exotics.contains = contains;
		Exotics.own = getOwnProperty;
		Exotics.define = defineOwnProperty;
		Exotics.remove = deleteProperty;
		Exotics.keys = ownKeys;
		Exotics.protoOf = getPrototypeOf;
		Exotics.setProto = setPrototypeOf;
		Exotics.extensibleOf = isExtensible;
		Exotics.prevent = preventExtensions;
		Exotics.arrayOf = isArray;
		Exotics.target = targetOf;
		var proxy = Builtins.nativeFunction("Proxy", 2, (_, a, nt) -> {
			if (same(nt, undef())) return error("TypeError", "Constructor Proxy requires 'new'");
			return make(arg(a, 0), arg(a, 1));
		});
		proxy.kind = JsFunction.BASE;
		Builtins.method(proxy, "revocable", 2, (_, a, _) -> {
			var p:JsObject = make(arg(a, 0), arg(a, 1));
			var r = new JsObject(Builtins.ObjectProto);
			r.setOwn("proxy", p);
			r.setOwn("revoke", Builtins.nativeFunction("", 0, (_, _, _) -> {
				var q = parts(p);
				q.target = null;
				q.handler = null;
				return undef();
			}));
			return r;
		});
		Builtins.globals.set("Proxy", proxy);
	}

	static function make(target:Dynamic, handler:Dynamic):Dynamic {
		if (!isObject(target) || !isObject(handler)) return error("TypeError", "Cannot create proxy with a non-object as target or handler");
		Exotics.made = true;
		var q = new ProxyParts(target, handler);
		return isCallable(target) || isConstructor(target) ? new JsCallableProxy(q) : new JsProxy(q);
	}

	// (the target and the handler's trap of that name, null without one; revoked: a TypeError)
	static function trap(p:JsObject, name:String):{target:JsObject, handler:JsObject, trap:Dynamic} {
		var q = parts(p);
		if (q.handler == null) return error("TypeError", "Cannot perform '" + name + "' on a proxy that has been revoked");
		var t = getKey(q.handler, name, q.handler);
		if (same(t, undef()) || t == null) t = null;
		else if (!isCallable(t)) error("TypeError", describe(t) + " is not a function");
		return {target: q.target, handler: q.handler, trap: t};
	}

	// (a key as the program sees it: a string, or the symbol)
	static function jsKey(k:String):Dynamic {
		if (!Symbols.isSymbolKey(k)) return k;
		var s = Symbols.fromKey(k);
		return s == null ? k : s;
	}

	static function name(k:String):String return Symbols.isSymbolKey(k) ? Symbols.functionName(k) : k;

	// ---- the target's properties, as descriptors (Objects.descriptor's objects)
	static function own(t:JsObject, k:String):Dynamic return Objects.descriptor(t, k);

	static function field(d:Dynamic, f:String):Dynamic return getKey(d, f, d);

	static function flag(d:Dynamic, f:String):Bool return Seed.truth(field(d, f));

	static inline function absent(d:Dynamic):Bool return same(d, undef());

	static function accessor(d:Dynamic):Bool return has(d, "get") || has(d, "set");

	static function frozenData(d:Dynamic):Bool return !absent(d) && !flag(d, "configurable") && !accessor(d) && !flag(d, "writable");

	// ---- the internal methods

	public static function getPrototypeOf(p:JsObject):JsObject {
		var h = trap(p, "getPrototypeOf");
		if (h.trap == null) return Lib.prototypeOf(h.target);
		var r = call(h.trap, h.handler, [h.target]);
		if (r != null && !isObject(r)) error("TypeError", "'getPrototypeOf' on proxy: trap returned neither object nor null");
		if (!isExtensible(h.target) && r != Lib.prototypeOf(h.target)) error("TypeError", "'getPrototypeOf' on proxy: proxy target is non-extensible but the trap did not return its actual prototype");
		return r;
	}

	public static function setPrototypeOf(p:JsObject, v:Dynamic):Bool {
		var h = trap(p, "setPrototypeOf");
		if (h.trap == null) return Lib.setPrototypeResult(h.target, v);
		if (!Seed.truth(call(h.trap, h.handler, [h.target, v]))) return false;
		if (!isExtensible(h.target) && v != Lib.prototypeOf(h.target)) error("TypeError", "'setPrototypeOf' on proxy: trap returned truish for setting a new prototype on the non-extensible proxy target");
		return true;
	}

	public static function isExtensible(p:JsObject):Bool {
		if (!is(p)) return p.extensible;
		var h = trap(p, "isExtensible");
		if (h.trap == null) return isExtensible(h.target);
		var r = Seed.truth(call(h.trap, h.handler, [h.target]));
		if (r != isExtensible(h.target)) error("TypeError", "'isExtensible' on proxy: trap result does not reflect extensibility of proxy target (which is '" + isExtensible(h.target) + "')");
		return r;
	}

	public static function preventExtensions(p:JsObject):Bool {
		if (!is(p)) {
			p.extensible = false;
			return true;
		}
		var h = trap(p, "preventExtensions");
		if (h.trap == null) return preventExtensions(h.target);
		var r = Seed.truth(call(h.trap, h.handler, [h.target]));
		if (r && isExtensible(h.target)) error("TypeError", "'preventExtensions' on proxy: trap returned truish but the proxy target is extensible");
		return r;
	}

	public static function getOwnProperty(p:JsObject, k:String):Dynamic {
		var h = trap(p, "getOwnPropertyDescriptor");
		if (h.trap == null) return own(h.target, k);
		var r = call(h.trap, h.handler, [h.target, jsKey(k)]);
		if (!isObject(r) && !absent(r)) error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined for property '" + name(k) + "'");
		var t = own(h.target, k);
		if (absent(r)) {
			if (absent(t)) return r;
			if (!flag(t, "configurable")) error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + name(k) + "' which is non-configurable in the proxy target");
			if (!isExtensible(h.target)) error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + name(k) + "' which exists in the non-extensible proxy target");
			return r;
		}
		// (the trap's descriptor completed, as ToPropertyDescriptor and CompletePropertyDescriptor make it)
		var d = complete(r);
		if (absent(t) && !isExtensible(h.target)) error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap returned descriptor for property '" + name(k) + "' that is incompatible with the existing property in the proxy target");
		if (!compatible(isExtensible(h.target), d, t)) error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap returned descriptor for property '" + name(k) + "' that is incompatible with the existing property in the proxy target");
		if (!flag(d, "configurable") && (absent(t) || flag(t, "configurable")))
			error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap reported non-configurability for property '" + name(k) + "' which is either non-existent or configurable in the proxy target");
		if (!flag(d, "configurable") && has(d, "writable") && !flag(d, "writable") && !absent(t) && flag(t, "writable"))
			error("TypeError", "'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and writable for property '" + name(k) + "' which is non-configurable, non-writable in the proxy target");
		return d;
	}

	static function complete(r:Dynamic):JsObject {
		var d = new JsObject(Builtins.ObjectProto);
		if (has(r, "get") || has(r, "set")) {
			var g = field(r, "get"), s = field(r, "set");
			if (!same(g, undef()) && !isCallable(g)) error("TypeError", "Getter must be a function: " + Seed.text(g));
			if (!same(s, undef()) && !isCallable(s)) error("TypeError", "Setter must be a function: " + Seed.text(s));
			if (has(r, "value") || has(r, "writable")) error("TypeError", "Invalid property descriptor. Cannot both specify accessors and a value or writable attribute");
			d.setOwn("get", g);
			d.setOwn("set", s);
		}
		else {
			d.setOwn("value", field(r, "value"));
			d.setOwn("writable", flag(r, "writable"));
		}
		d.setOwn("enumerable", flag(r, "enumerable"));
		d.setOwn("configurable", flag(r, "configurable"));
		return d;
	}

	// (IsCompatiblePropertyDescriptor: desc may describe current, a target's property or undefined)
	static function compatible(extensible:Bool, desc:Dynamic, current:Dynamic):Bool {
		if (absent(current)) return extensible;
		if (flag(current, "configurable")) return true;
		if (has(desc, "configurable") && flag(desc, "configurable")) return false;
		if (has(desc, "enumerable") && flag(desc, "enumerable") != flag(current, "enumerable")) return false;
		var generic = !accessor(desc) && !has(desc, "value") && !has(desc, "writable");
		if (generic) return true;
		if (accessor(current) != accessor(desc)) return false;
		if (accessor(current)) {
			if (has(desc, "get") && !sameValue(field(desc, "get"), field(current, "get"))) return false;
			if (has(desc, "set") && !sameValue(field(desc, "set"), field(current, "set"))) return false;
			return true;
		}
		if (!flag(current, "writable")) {
			if (has(desc, "writable") && flag(desc, "writable")) return false;
			if (has(desc, "value") && !sameValue(field(desc, "value"), field(current, "value"))) return false;
		}
		return true;
	}

	public static function defineOwnProperty(p:JsObject, k:String, desc:Dynamic):Bool {
		var h = trap(p, "defineProperty");
		if (h.trap == null) return Objects.defineResult(h.target, k, desc);
		if (!Seed.truth(call(h.trap, h.handler, [h.target, jsKey(k), desc]))) return false;
		var t = own(h.target, k);
		var unconfigurable = has(desc, "configurable") && !flag(desc, "configurable");
		if (absent(t)) {
			if (!isExtensible(h.target)) error("TypeError", "'defineProperty' on proxy: trap returned truish for adding property '" + name(k) + "'  to the non-extensible proxy target");
			if (unconfigurable) error("TypeError", "'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + name(k) + "' which is either non-existent or configurable in the proxy target");
			return true;
		}
		if (!compatible(isExtensible(h.target), desc, t)) error("TypeError", "'defineProperty' on proxy: trap returned truish for adding property '" + name(k) + "'  that is incompatible with the existing property in the proxy target");
		if (unconfigurable && flag(t, "configurable")) error("TypeError", "'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + name(k) + "' which is either non-existent or configurable in the proxy target");
		if (!accessor(t) && !flag(t, "configurable") && flag(t, "writable") && has(desc, "writable") && !flag(desc, "writable"))
			error("TypeError", "'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + name(k) + "' which cannot be non-writable, unless there exists a corresponding non-configurable, non-writable own property of the target object.");
		return true;
	}

	public static function contains(p:JsObject, k:String):Bool {
		var h = trap(p, "has");
		if (h.trap == null) return Lib.has(h.target, jsKey(k));
		var r = Seed.truth(call(h.trap, h.handler, [h.target, jsKey(k)]));
		if (!r) {
			var t = own(h.target, k);
			if (!absent(t)) {
				if (!flag(t, "configurable")) error("TypeError", "'has' on proxy: trap returned falsish for property '" + name(k) + "' which exists in the proxy target as non-configurable");
				if (!isExtensible(h.target)) error("TypeError", "'has' on proxy: trap returned falsish for property '" + name(k) + "' but the proxy target is not extensible");
			}
		}
		return r;
	}

	public static function read(p:JsObject, k:String, receiver:Dynamic):Dynamic {
		var h = trap(p, "get");
		if (h.trap == null) return getKey(h.target, k, receiver);
		var r = call(h.trap, h.handler, [h.target, jsKey(k), receiver]);
		var t = own(h.target, k);
		if (!absent(t) && !flag(t, "configurable")) {
			if (frozenData(t) && !sameValue(r, field(t, "value")))
				error("TypeError", "'get' on proxy: property '" + name(k) + "' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value (expected '" + Seed.text(field(t, "value")) + "' but got '" + Seed.text(r) + "')");
			if (accessor(t) && same(field(t, "get"), undef()) && !same(r, undef()))
				error("TypeError", "'get' on proxy: property '" + name(k) + "' is a non-configurable accessor property on the proxy target and does not have a getter function, but the trap did not return 'undefined' (got '" + Seed.text(r) + "')");
		}
		return r;
	}

	public static function write(p:JsObject, k:String, v:Dynamic, receiver:Dynamic):Bool {
		var h = trap(p, "set");
		if (h.trap == null) return Lib.setResult(h.target, k, v, receiver);
		if (!Seed.truth(call(h.trap, h.handler, [h.target, jsKey(k), v, receiver]))) return false;
		var t = own(h.target, k);
		if (!absent(t) && !flag(t, "configurable")) {
			if (frozenData(t) && !sameValue(v, field(t, "value")))
				error("TypeError", "'set' on proxy: trap returned truish for property '" + name(k) + "' which exists in the proxy target as a non-configurable and non-writable data property with a different value");
			if (accessor(t) && same(field(t, "set"), undef()))
				error("TypeError", "'set' on proxy: trap returned truish for property '" + name(k) + "' which exists in the proxy target as a non-configurable and non-writable accessor property without a setter");
		}
		return true;
	}

	public static function deleteProperty(p:JsObject, k:String):Bool {
		var h = trap(p, "deleteProperty");
		if (h.trap == null) return Lib.removeResult(h.target, k);
		if (!Seed.truth(call(h.trap, h.handler, [h.target, jsKey(k)]))) return false;
		var t = own(h.target, k);
		if (!absent(t)) {
			if (!flag(t, "configurable")) error("TypeError", "'deleteProperty' on proxy: trap returned truish for property '" + name(k) + "' which is non-configurable in the proxy target");
			if (!isExtensible(h.target)) error("TypeError", "'deleteProperty' on proxy: trap returned truish for property '" + name(k) + "' but the proxy target is non-extensible");
		}
		return true;
	}

	// its own keys (the runtime's: a symbol's by its key), in the trap's order
	public static function ownKeys(p:JsObject):Array<String> {
		var h = trap(p, "ownKeys");
		if (h.trap == null) return Objects.ownPropertyKeys(h.target);
		var r = call(h.trap, h.handler, [h.target]);
		if (!isObject(r)) error("TypeError", "CreateListFromArrayLike called on non-object");
		var keys:Array<String> = [], seen:Map<String, Bool> = [];
		var n = Arrays.lengthOf(r);
		var i:Float = 0;
		while (i < n) {
			var v = Lib.get(r, i++);
			if (!Std.isOfType(v, String) && !Std.isOfType(v, Symbols.JsSymbol)) error("TypeError", Seed.text(Inspect.inspect(v)) + " is not a valid property name");
			var k = key(v);
			if (seen.exists(k)) error("TypeError", "'ownKeys' on proxy: trap returned duplicate entries");
			seen.set(k, true);
			keys.push(k);
		}
		var extensible = isExtensible(h.target);
		var targetKeys = Objects.ownPropertyKeys(h.target);
		for (k in targetKeys) {
			var t = own(h.target, k);
			if (!absent(t) && !flag(t, "configurable") && !seen.exists(k)) error("TypeError", "'ownKeys' on proxy: trap result did not include '" + name(k) + "'");
		}
		if (!extensible) {
			for (k in targetKeys) if (!seen.exists(k)) error("TypeError", "'ownKeys' on proxy: trap result did not include '" + name(k) + "'");
			if (keys.length != targetKeys.length) error("TypeError", "'ownKeys' on proxy: trap returned extra keys but proxy target is non-extensible");
		}
		return keys;
	}

	public static function apply(p:JsObject, thisArg:Dynamic, args:Array<Dynamic>):Dynamic {
		var h = trap(p, "apply");
		if (h.trap == null) return Lib.call(h.target, thisArg, args);
		return Lib.call(h.trap, h.handler, [h.target, thisArg, array(args)]);
	}

	public static function create(p:JsObject, args:Array<Dynamic>, newTarget:Dynamic):Dynamic {
		var h = trap(p, "construct");
		if (!isConstructor(h.target)) return error("TypeError", describe(p) + " is not a constructor");
		if (h.trap == null) return Lib.construct(h.target, args, newTarget);
		var r = Lib.call(h.trap, h.handler, [h.target, array(args), newTarget]);
		if (!isObject(r)) error("TypeError", "proxy [[Construct]] must return an object");
		return r;
	}

	// IsArray: a proxy's is its target's
	public static function isArray(v:Dynamic):Bool {
		if (Std.isOfType(v, JsArray)) return true;
		if (!is(v)) return false;
		var q = parts(v);
		if (q.handler == null) return error("TypeError", "Cannot perform 'IsArray' on a proxy that has been revoked");
		return isArray(q.target);
	}

	// (what inspection shows of a proxy: its target, as node's does)
	public static function targetOf(p:JsObject):Null<JsObject> return parts(p).target;
}
