package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Shapes;

// Built-ins' methods compiled code calls directly on a receiver of a known
// type (lower.Expressions' direct calls), the members being frozen
// (Builtins.freeze): where the receiver is plain, of its built-in
// prototype with nothing of its own, what the method does, without its
// lookup or its list of arguments.
@:access(helder.typescript.js.Collections)
class Direct {
	public static function plainMap(o:Dynamic, isSet:Bool):Bool {
		if (!Std.isOfType(o, JsMap)) return false;
		var m:JsMap = o;
		return m.isSet == isSet && !m.weak && m.proto == (isSet ? Builtins.SetProto : Builtins.MapProto) && m.shape == Shapes.object;
	}

	public static function mapGet(m:JsMap, k:Dynamic):Dynamic {
		var i = Collections.mapIndex(m, k);
		return i < 0 ? Lib.undef() : m.values[i];
	}

	public static function mapHas(m:JsMap, k:Dynamic):Bool return Collections.mapIndex(m, k) >= 0;

	public static function mapSet(m:JsMap, k:Dynamic, v:Dynamic):Dynamic return Collections.mapPut(m, k, v);

	public static function mapDelete(m:JsMap, k:Dynamic):Bool return Collections.mapDelete(m, k);

	public static function mapNext(m:JsMap, i:Int):Int {
		while (i < m.keys.length) {
			if (m.active[i]) return i;
			i++;
		}
		return -1;
	}

	// (Array.prototype.push of one value, as its own fast way: an extensible
	// array whose elements run to its length; else -1, pushed the runtime's way)
	public static function arrayPush(a:JsArray, v:Dynamic):Float {
		if (!a.extensible || Builtins.arrayMethodsChanged) return -1;
		if (a.nums != null && Lib.isNumber(v)) {
			a.nums.push(v);
			return a.length = a.nums.length;
		}
		var items = a.items;
		if (items.length != a.length) return -1;
		items.push(v);
		return a.length = items.length;
	}

	// (Array.prototype.includes: SameValueZero, a hole is undefined)
	public static function arrayIncludes(a:JsArray, v:Dynamic):Bool {
		if (a.nums != null) {
			if (!Lib.isNumber(v)) return false;
			var x:Float = v;
			for (n in a.nums) if (n == x || x != x && n != n) return true;
			return false;
		}
		var items = a.items;
		for (e in items) if (Lib.same(e, Lib.hole) ? Lib.same(v, Lib.undef()) : Lib.sameValueZero(e, v)) return true;
		return items.length < a.length && Lib.same(v, Lib.undef());
	}

	// (Array.prototype.indexOf: strict equality, holes skipped)
	public static function arrayIndexOf(a:JsArray, v:Dynamic):Float {
		if (a.nums != null) {
			if (!Lib.isNumber(v)) return -1;
			var x:Float = v;
			for (i in 0...a.nums.length) if (a.nums[i] == x) return i;
			return -1;
		}
		var items = a.items;
		for (i in 0...items.length) if (!Lib.same(items[i], Lib.hole) && Seed.strictEq(items[i], v)) return i;
		return -1;
	}
}
