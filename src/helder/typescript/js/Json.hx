package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Shapes;
import helder.typescript.js.Sites;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;

// JSON.parse (key order kept, revivers) and JSON.stringify (replacers, indentation, toJSON).
class Json {
	// (a site of the runtime's own: toJSON is absent from most objects' shapes)
	public static final toJSONSite = new Site("toJSON");
	// (the powers of ten a decimal of at most 15 digits divides by exactly)
	static final tens = [for (k in 0...16) Math.pow(10, k)];
	// (the shapes recent objects ended with: a parse's next object of the same keys reads its keys against one)
	static inline var RECENT = 8;

	public static function setup():Void {
		var json = new JsObject(Builtins.ObjectProto);
		json.setOwn(Symbols.toStringTag, "JSON", Attr.HIDDEN | Attr.READONLY);
		json.setOwn("parse", Builtins.nativeFunction("parse", 2, (_, a, _) -> {
			var value = new Json(Seed.text(arg(a, 0))).document();
			var reviver = arg(a, 1);
			if (!isCallable(reviver)) return value;
			var root = object([""], [value]);
			return revive(root, "", reviver);
		}), Attr.HIDDEN);
		json.setOwn("stringify", Builtins.nativeFunction("stringify", 3, (_, a, _) -> stringify(arg(a, 0), arg(a, 1), arg(a, 2))), Attr.HIDDEN);
		RawJson.setup(json);
		Builtins.globals.set("JSON", json);
	}

	static function revive(holder:Dynamic, k:String, reviver:Dynamic):Dynamic {
		var v = get(holder, k);
		if (isObject(v)) {
			var names:Array<String> = Std.isOfType(v, JsArray) ? [for (i in 0...Std.int((v : JsArray).length)) Std.string(i)] : keys(v);
			for (name in names) {
				var r = revive(v, name, reviver);
				if (r == undef()) remove(v, name); else defineOwn(v, name, r);
			}
		}
		return call(reviver, holder, [k, v]);
	}

	var s:String;
	var i = 0;
	final recent:Array<Shape> = [];

	function new(s:String) this.s = s;

	inline function code(k:Int):Int return k < s.length ? StringTools.fastCodeAt(s, k) : -1;

	function fail():Dynamic {
		return error("SyntaxError", i >= s.length ? "Unexpected end of JSON input" : "Unexpected token '" + s.charAt(i) + "', \"" + (s.length > 30 ? s.substr(0, 30) + "\"... " : s + "\" ") + "is not valid JSON");
	}

	function space() while (i < s.length) {
		var c = StringTools.fastCodeAt(s, i);
		if (c == 32 || c == 9 || c == 10 || c == 13) i++; else break;
	}

	function document():Dynamic {
		space();
		var v = value();
		space();
		if (i < s.length) fail();
		return v;
	}

	function value():Dynamic {
		if (i >= s.length) return fail();
		return switch StringTools.fastCodeAt(s, i) {
			case "{".code: parseObject();
			case "[".code: parseArray();
			case "\"".code: string();
			case "t".code if (s.substr(i, 4) == "true"):
				i += 4;
				true;
			case "f".code if (s.substr(i, 5) == "false"):
				i += 5;
				false;
			case "n".code if (s.substr(i, 4) == "null"):
				i += 4;
				null;
			case "-".code | "0".code | "1".code | "2".code | "3".code | "4".code | "5".code | "6".code | "7".code | "8".code | "9".code: number();
			case _: fail();
		}
	}

	// (an object's keys read against a recent shape's while they are its: no
	// string made for them, and the object given that shape at once)
	function parseObject():Dynamic {
		i++;
		space();
		if (code(i) == "}".code) {
			i++;
			return new JsObject(Builtins.ObjectProto);
		}
		var keys:Array<String> = [], values:Array<Dynamic> = [];
		var guess:Shape = null, known = 0;
		while (true) {
			space();
			if (code(i) != "\"".code) fail();
			var n = keys.length;
			var k:String = null;
			if (n == 0) {
				for (r in recent) if (r.size() > 0 && read(r.keys[0])) {
					guess = r;
					k = r.keys[0];
					break;
				}
			}
			else if (guess != null && known == n && n < guess.size() && read(guess.keys[n])) k = guess.keys[n];
			if (k != null) known++; else k = string();
			keys.push(k);
			space();
			if (code(i) != ":".code) fail();
			i++;
			space();
			values.push(value());
			space();
			var d = code(i++);
			if (d == "}".code) break;
			if (d != ",".code) {
				i--;
				fail();
			}
		}
		var o = new JsObject(Builtins.ObjectProto);
		var shape = guess != null && known == keys.length && keys.length == guess.size() ? guess : shapeOf(keys);
		if (shape == null) {
			for (j in 0...keys.length) defineOwn(o, keys[j], values[j]);
			return o;
		}
		o.shape = shape;
		o.slots = values;
		if (shape != guess) {
			if (recent.length >= RECENT) recent.pop();
			recent.unshift(shape);
		}
		return o;
	}

	// (a key at i, the string k exactly, without an escape: i past it)
	function read(k:String):Bool {
		var n = k.length, j = i + 1;
		if (j + n >= s.length || StringTools.fastCodeAt(s, j + n) != "\"".code) return false;
		for (x in 0...n) {
			var c = StringTools.fastCodeAt(s, j + x);
			if (c != StringTools.fastCodeAt(k, x) || c == "\\".code) return false;
		}
		i = j + n + 1;
		return true;
	}

	// (an ordinary object's shape of these keys in order, else null: an
	// index, __proto__ or a key twice, which defineOwn places)
	static function shapeOf(keys:Array<String>):Null<Shape> {
		var shape = Shapes.object;
		for (k in keys) {
			if (k == "__proto__" || index(k) >= 0 || shape.slotOf(k) >= 0) return null;
			shape = shape.with(k, 0, Shapes.KEYS, true);
			if (shape == null) return null;
		}
		return shape;
	}

	// (numbers while every element is one: a number array's nums)
	function parseArray():Dynamic {
		i++;
		space();
		if (code(i) == "]".code) {
			i++;
			return array([]);
		}
		var nums:Array<Float> = [], items:Array<Dynamic> = null;
		while (true) {
			space();
			// (Dynamic said: inferred, v is typed by nums.push's use, a Float)
			var v:Dynamic = value();
			if (items == null && isNumber(v)) nums.push(v);
			else {
				if (items == null) items = [for (x in nums) (x : Dynamic)];
				items.push(v);
			}
			space();
			var d = code(i++);
			if (d == "]".code) break;
			if (d != ",".code) {
				i--;
				fail();
			}
		}
		return items == null ? Seed.libNumberArray(nums) : array(items);
	}

	// (a decimal of at most 15 digits without an exponent: its digits as an
	// integer, divided by a power of ten, both exact, so rounded once)
	function number():Float {
		var start = i;
		var negative = code(i) == "-".code;
		if (negative) i++;
		var m = 0.0, count = 0, fraction = 0;
		if (code(i) == "0".code) {
			i++;
			count++;
		}
		else {
			while (i < s.length && code(i) >= 48 && code(i) <= 57) {
				m = m * 10 + (StringTools.fastCodeAt(s, i++) - 48);
				count++;
			}
			if (count == 0) return fail();
		}
		if (code(i) == ".".code) {
			i++;
			while (i < s.length && code(i) >= 48 && code(i) <= 57) {
				m = m * 10 + (StringTools.fastCodeAt(s, i++) - 48);
				fraction++;
			}
			if (fraction == 0) return fail();
			count += fraction;
		}
		var exponent = code(i) == "e".code || code(i) == "E".code;
		if (exponent) {
			i++;
			if (code(i) == "+".code || code(i) == "-".code) i++;
			if (digits() == 0) return fail();
		}
		if (exponent || count > 15) return Std.parseFloat(s.substring(start, i));
		var v = fraction == 0 ? m : m / tens[fraction];
		return negative ? -v : v;
	}

	function digits():Int {
		var n = 0;
		while (i < s.length && code(i) >= 48 && code(i) <= 57) {
			i++;
			n++;
		}
		return n;
	}

	// (the text between the quotes as it is, without an escape; else in runs between them)
	function string():String {
		i++;
		var start = i;
		while (i < s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c == "\"".code) return s.substring(start, i++);
			if (c == "\\".code || c < 32) break;
			i++;
		}
		var b = new StringBuf();
		b.addSub(s, start, i - start);
		while (true) {
			if (i >= s.length) fail();
			var run = i;
			while (i < s.length) {
				var c = StringTools.fastCodeAt(s, i);
				if (c == "\"".code || c == "\\".code || c < 32) break;
				i++;
			}
			if (i > run) b.addSub(s, run, i - run);
			if (i >= s.length) fail();
			var c = StringTools.fastCodeAt(s, i++);
			if (c == "\"".code) return b.toString();
			if (c < 32) {
				i--;
				fail();
			}
			var e = code(i++);
			switch (e) {
				case "\"".code: b.addChar(34);
				case "\\".code: b.addChar(92);
				case "/".code: b.addChar(47);
				case "b".code: b.addChar(8);
				case "f".code: b.addChar(12);
				case "n".code: b.addChar(10);
				case "r".code: b.addChar(13);
				case "t".code: b.addChar(9);
				case "u".code:
					var value = 0;
					for (j in 0...4) {
						var c = code(i + j);
						var d = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
						if (d < 0) {
							i--;
							fail();
						}
						value = value * 16 + d;
					}
					b.addChar(value);
					i += 4;
				case _:
					i--;
					fail();
			}
		}
	}

	public static function quote(s:String):String {
		var b = new StringBuf();
		quoted(b, s);
		return b.toString();
	}

	// (hxmc's quoting is JSON.stringify's but for a lone surrogate, which it leaves as it is)
	public static function quoted(b:StringBuf, s:String):Void {
		var surrogate = false;
		for (j in 0...s.length) {
			var c = StringTools.fastCodeAt(s, j);
			if (c >= 0xd800 && c <= 0xdfff) {
				surrogate = true;
				break;
			}
		}
		if (!surrogate) {
			b.addJsonString(s);
			return;
		}
		b.addChar("\"".code);
		for (j in 0...s.length) {
			var c = StringTools.fastCodeAt(s, j);
			switch (c) {
				case 34: b.add("\\\"");
				case 92: b.add("\\\\");
				case 8: b.add("\\b");
				case 12: b.add("\\f");
				case 10: b.add("\\n");
				case 13: b.add("\\r");
				case 9: b.add("\\t");
				case _:
					var lone = c >= 0xd800 && c <= 0xdfff && !(c <= 0xdbff && j + 1 < s.length && s.charCodeAt(j + 1) >= 0xdc00 && s.charCodeAt(j + 1) <= 0xdfff) && !(c >= 0xdc00 && j > 0 && s.charCodeAt(j - 1) >= 0xd800 && s.charCodeAt(j - 1) <= 0xdbff);
					if (c < 32 || lone) b.add("\\u" + StringTools.hex(c, 4).toLowerCase()); else b.addChar(c);
			}
		}
		b.addChar("\"".code);
	}

	static function stringify(value:Dynamic, replacer:Dynamic, spaceArg:Dynamic):Dynamic {
		var replacerFn = isCallable(replacer) ? replacer : null;
		var allowed:Array<String> = null;
		if (replacerFn == null && Std.isOfType(replacer, JsArray)) {
			allowed = [];
			for (v in toList(replacer)) {
				var item:Dynamic = null;
				if (Std.isOfType(v, String)) item = v; else if (isNumber(v)) item = Seed.numberText(v); else if (isObject(v) && (v : JsObject).hasOwn("\x00@primitive")) item = Seed.text(v);
				if (item != null && allowed.indexOf(item) < 0) allowed.push(item);
			}
		}
		if (isObject(spaceArg) && (spaceArg : JsObject).hasOwn("\x00@primitive")) spaceArg = (spaceArg : JsObject).getOwn("\x00@primitive");
		var gap = "";
		if (isNumber(spaceArg)) {
			var n = Std.int(Math.min(10, Math.max(0, toIntegerOrInfinity(spaceArg))));
			gap = StringTools.lpad("", " ", n);
		}
		else if (Std.isOfType(spaceArg, String)) gap = (spaceArg : String).substr(0, 10);
		var w = new JsonWriter(gap, replacerFn, allowed);
		var holder:Dynamic = replacerFn == null ? null : object([""], [value]);
		return w.write(w.prepare(holder, "", 0, value), "") ? w.b.toString() : undef();
	}
}

// JSON.stringify's text in one builder: elements and properties read
// directly where an array or an object is plain (elements, fields),
// each value as SerializeJSONProperty takes it.
class JsonWriter {
	public final b = new StringBuf();
	final gap:String;
	final replacer:Dynamic;
	final allowed:Null<Array<String>>;
	final stack:Array<Dynamic> = [];

	public function new(gap:String, replacer:Dynamic, allowed:Null<Array<String>>) {
		this.gap = gap;
		this.replacer = replacer;
		this.allowed = allowed;
	}

	// the value for key of holder (an element's: null, its index), as
	// toJSON, the replacer and a wrapper's primitive make it; an index's text
	// made only for them
	// (toJSON an object's alone, as SerializeJSONProperty has it: a string's or a number's is not called)
	public function prepare(holder:Dynamic, key:Null<String>, index:Float, v:Dynamic):Dynamic {
		var object = isObject(v);
		if (object) {
			var toJSON = Sites.get(v, Json.toJSONSite);
			if (isCallable(toJSON)) v = call(toJSON, v, [key != null ? key : Seed.numberText(index)]);
		}
		if (replacer != null) v = call(replacer, holder, [key != null ? key : Seed.numberText(index), v]);
		else if (!object) return v;
		if (isObject(v) && !(v : JsObject).shape.plain && (v : JsObject).hasOwn("\x00@primitive")) v = (v : JsObject).getOwn("\x00@primitive");
		return v;
	}

	// (what write writes: not undefined, a function or a symbol)
	static function writable(v:Dynamic):Bool
		return Std.isOfType(v, String) || isNumber(v) || v == null || Std.isOfType(v, Bool) || isObject(v) && !isCallable(v);

	// v's text written, else false and nothing written
	public function write(v:Dynamic, indent:String):Bool {
		if (Std.isOfType(v, String)) Json.quoted(b, v);
		else if (isNumber(v)) {
			var n:Float = v;
			b.add(Math.isFinite(n) ? Seed.numberText(n) : "null");
		}
		else if (v == null) b.add("null");
		else if (Std.isOfType(v, Bool)) b.add(v ? "true" : "false");
		else if (Std.isOfType(v, RawJson.JsRawJson)) b.add((v : RawJson.JsRawJson).raw);
		else if (!isObject(v) || isCallable(v)) return false;
		else {
			for (o in stack) if (same(o, v)) error("TypeError", "Converting circular structure to JSON");
			stack.push(v);
			var inner = gap == "" ? "" : indent + gap;
			if (Exotics.isArray(v)) elements(v, indent, inner); else fields(v, indent, inner);
			stack.pop();
		}
		return true;
	}

	inline function line(indent:String):Void if (gap != "") {
		b.addChar(10);
		b.add(indent);
	}

	function elements(v:Dynamic, indent:String, inner:String):Void {
		var n = Arrays.lengthOf(v);
		if (n == 0) {
			b.add("[]");
			return;
		}
		// (a plain array's elements as they are; a hole, or one past them, by get)
		var a:JsArray = Std.isOfType(v, JsArray) && (v : JsArray).shape == Shapes.array ? v : null;
		b.addChar("[".code);
		var j:Float = 0;
		while (j < n) {
			if (j > 0) b.addChar(",".code);
			line(inner);
			var k = Std.int(j);
			var e:Dynamic = a == null ? hole : a.nums != null ? (k < a.nums.length ? a.nums[k] : hole) : k < a.items.length ? a.items[k] : hole;
			if (same(e, hole)) e = get(v, Seed.numberText(j));
			if (!write(prepare(v, null, j, e), inner)) b.add("null");
			j++;
		}
		line(indent);
		b.addChar("]".code);
	}

	// (a property written unless it is not JSON: whether none was before the next)
	function field(o:JsObject, key:String, e:Dynamic, first:Bool, inner:String):Bool {
		var item = prepare(o, key, 0, e);
		if (!writable(item)) return first;
		b.addChar(first ? "{".code : ",".code);
		line(inner);
		Json.quoted(b, key);
		b.add(gap == "" ? ":" : ": ");
		write(item, inner);
		return false;
	}

	function fields(v:Dynamic, indent:String, inner:String):Void {
		var o:JsObject = v;
		var first = true;
		var shape = o.shape, layout = o.layout;
		if (allowed != null || o.bits & JsObject.PROXY != 0 || o.form != Form.PLAIN) for (k in (allowed != null ? allowed : keys(o))) first = field(o, k, get(o, k), first, inner);
		// (a plain object's properties by its shape's slots while it has that shape; its keys in their order, no index among them)
		else if (layout == null && !shape.dict && shape.plain && !shape.indexed()) {
			for (j in 0...shape.size()) first = field(o, shape.keys[j], o.shape == shape ? o.slots[j] : get(o, shape.keys[j]), first, inner);
		}
		// (an object type's or typed class's fields by its layout, without own properties of its own)
		else if (layout != null && shape == layout.root && !layout.indexed()) {
			for (j in 0...layout.names.length) first = field(o, layout.names[j], o.shape == shape ? layout.get(o, j) : get(o, layout.names[j]), first, inner);
		}
		else for (k in keys(o)) first = field(o, k, get(o, k), first, inner);
		if (first) b.add("{}");
		else {
			line(indent);
			b.addChar("}".code);
		}
	}
}
