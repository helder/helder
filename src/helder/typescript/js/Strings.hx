package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Builtins.*;
import helder.typescript.js.Objects.*;
import helder.typescript.js.Arrays.*;
import helder.typescript.js.Collections.*;
import helder.typescript.js.Globals.*;

// String's built-ins: String and its prototype's methods, localeCompare's collation.
@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Objects)
@:access(helder.typescript.js.Arrays)
@:access(helder.typescript.js.Collections)
@:access(helder.typescript.js.Globals)
class Strings {
	// String
	static function thisString(t:Dynamic):String {
		if (Std.isOfType(t, String)) return t;
		if (t == null || Lib.same(t, undef())) error("TypeError", "String.prototype method called on null or undefined");
		return Seed.text(isObject(t) ? toPrimitive(t, "string") : t);
	}

	static function setupString():Void {
		var p = StringProto;
		constant(p, "length", 0);
		p.setOwn("\x00@primitive", "", Attr.HIDDEN);
		var c = constructor("String", 1, p, (_, a, nt) -> {
			var v = a.length == 0 ? "" : Std.isOfType(a[0], Symbols.JsSymbol) && same(nt, undef()) ? Symbols.text(a[0]) : Seed.text(isObject(a[0]) ? toPrimitive(a[0], "string") : a[0]);
			if (same(nt, undef())) return (v : Dynamic);
			var o = wrap(v);
			o.proto = protoFrom(nt, StringProto);
			return o;
		});
		method(c, "fromCharCode", 1, (_, a, _) -> {
			var out = new StringBuf();
			for (v in a) out.addChar(toInt32(v) & 65535);
			return out.toString();});
		method(c, "fromCodePoint", 1, (_, a, _) -> {
			var out = new StringBuf();
			for (v in a) {
				var n = Seed.numeric(v);
				if (!Math.isFinite(n) || Math.ffloor(n) != n || n < 0 || n > 0x10ffff) error("RangeError", "Invalid code point " + Seed.text(v));
				var i = Std.int(n);
				if (i < 65536) out.addChar(i); else {
					i -= 65536;
					out.addChar(0xd800 + (i >> 10));
					out.addChar(0xdc00 + (i & 1023));
				}
			}
			return out.toString();});
		method(c, "raw", 1, (_, a, _) -> {
			var strings = get(arg(a, 0), "raw");
			var n = lengthOf(strings);
			var out = new StringBuf();
			var i:Float = 0;
			while (i < n) {
				out.add(Seed.text(get(strings, i)));
				if (i + 1 < n && i + 1 < a.length) out.add(Seed.text(a[Std.int(i + 1)]));
				i++;
			}
			return out.toString();});
		fixed(p, "toString", 0, (t, _, _, _) -> primitive(t, "string"));
		fixed(p, "valueOf", 0, (t, _, _, _) -> primitive(t, "string"));
		// (each method its own function, in String.prototype's order)
		function m(name:String, arity:Int, fn:(String, Array<Dynamic>) -> Dynamic) method(p, name, arity, (t, a, _) -> fn(thisString(t), a));
		// (one reading at most three arguments by their places: a fixed entry, Builtins.fixed)
		function m3(name:String, arity:Int, fn:(String, Dynamic, Dynamic, Dynamic) -> Dynamic) fixed(p, name, arity, (t, a0:Dynamic, a1:Dynamic, a2:Dynamic) -> fn(thisString(t), a0, a1, a2));
		m3("charAt", 1, (s, a0:Dynamic, _, _) -> {
			var i = toIntegerOrInfinity(a0);
			return i < 0 || i >= s.length ? "" : s.charAt(Std.int(i));});
		m3("at", 1, (s, a0:Dynamic, _, _) -> {
			var i = toIntegerOrInfinity(a0);
			if (i < 0) i += s.length;
			return i < 0 || i >= s.length ? undef() : s.charAt(Std.int(i));});
		m3("charCodeAt", 1, (s, a0:Dynamic, _, _) -> {
			var i = toIntegerOrInfinity(a0);
			return i < 0 || i >= s.length ? Math.NaN : StringTools.fastCodeAt(s, Std.int(i));});
		// (Dynamic returns throughout: a lambda returning undefined and an Int is typed Int, undefined read as 0)
		m3("codePointAt", 1, (s, a0:Dynamic, _, _) -> {
			var i = toIntegerOrInfinity(a0), n = s.length;
			if (i < 0 || i >= n) return undef();
			var c = StringTools.fastCodeAt(s, Std.int(i));
			if (c >= 0xd800 && c <= 0xdbff && i + 1 < n) {
				var d = StringTools.fastCodeAt(s, Std.int(i + 1));
				if (d >= 0xdc00 && d <= 0xdfff) return ((c - 0xd800) * 1024 + (d - 0xdc00) + 65536 : Dynamic);
			}
			return (c : Dynamic);});
		m3("slice", 2, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var n = s.length, second = a1;
			var start = relative(a0, n), end = same(second, undef()) ? n : relative(second, n);
			return s.substring(Std.int(start), Std.int(Math.max(start, end)));});
		m3("substring", 2, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var n = s.length, second = a1;
			var start = Math.max(0, Math.min(toIntegerOrInfinity(a0), n)), end = same(second, undef()) ? n : Math.max(0, Math.min(toIntegerOrInfinity(second), n));
			return s.substring(Std.int(Math.min(start, end)), Std.int(Math.max(start, end)));});
		m3("substr", 2, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var n = s.length, second = a1;
			var start = relative(a0, n);
			var length = same(second, undef()) ? n - start : Math.min(Math.max(toIntegerOrInfinity(second), 0), n - start);
			return length <= 0 ? "" : s.substr(Std.int(start), Std.int(length));});
		m("concat", 1, (s, a) -> {
			var b = new StringBuf();
			b.add(s);
			for (v in a) b.add(Seed.text(v));
			return b.toString();});
		m3("indexOf", 1, (s, a0:Dynamic, a1:Dynamic, _) -> s.indexOf(Seed.text(a0), from(s, a1)));
		m3("includes", 1, (s, a0:Dynamic, a1:Dynamic, _) -> s.indexOf(needle(a0, "includes"), from(s, a1)) >= 0);
		m3("startsWith", 1, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var needle = needle(a0, "startsWith");
			return s.substr(from(s, a1), needle.length) == needle;});
		m3("lastIndexOf", 1, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var n = s.length, num = Seed.numeric(a1);
			var pos = Math.isNaN(num) ? n : Std.int(Math.max(0, Math.min(toIntegerOrInfinity(num), n)));
			return s.lastIndexOf(Seed.text(a0), Std.int(pos));});
		m3("endsWith", 1, (s, a0:Dynamic, a1:Dynamic, _) -> {
			var needle = needle(a0, "endsWith"), second = a1;
			var end = same(second, undef()) ? s.length : from(s, second);
			return end >= needle.length && s.substr(end - needle.length, needle.length) == needle;});
		m3("toLowerCase", 0, (s, _, _, _) -> s.toLowerCase());
		m3("toUpperCase", 0, (s, _, _, _) -> s.toUpperCase());
		m3("toLocaleLowerCase", 0, (s, _, _, _) -> s.toLowerCase());
		m3("toLocaleUpperCase", 0, (s, _, _, _) -> s.toUpperCase());
		m3("trim", 0, (s, _, _, _) -> trim(s, true, true));
		m3("trimStart", 0, (s, _, _, _) -> trim(s, true, false));
		m3("trimEnd", 0, (s, _, _, _) -> trim(s, false, true));
		m3("trimLeft", 0, (s, _, _, _) -> trim(s, true, false));
		m3("trimRight", 0, (s, _, _, _) -> trim(s, false, true));
		m3("repeat", 1, (s, a0:Dynamic, _, _) -> {
			var first = a0;
			var count = toIntegerOrInfinity(first);
			if (count < 0 || !Math.isFinite(count)) error("RangeError", "Invalid count value: " + Seed.text(first));
			if (count * s.length > 536870888) error("RangeError", "Invalid string length");
			var b = new StringBuf();
			var i:Float = 0;
			while (i < count) {
				b.add(s);
				i++;
			}
			return b.toString();});
		m3("padStart", 1, (s, a0:Dynamic, a1:Dynamic, _) -> pad(s, a0, a1, true));
		m3("padEnd", 1, (s, a0:Dynamic, a1:Dynamic, _) -> pad(s, a0, a1, false));
		m3("split", 2, (s, a0:Dynamic, a1:Dynamic, _) -> split(s, a0, a1));
		m3("replace", 2, (s, a0:Dynamic, a1:Dynamic, _) -> replace(s, a0, a1, false));
		m3("replaceAll", 2, (s, a0:Dynamic, a1:Dynamic, _) -> replace(s, a0, a1, true));
		m3("localeCompare", 1, (s, a0:Dynamic, _, _) -> collate(s, Seed.text(a0)));
		m3("normalize", 0, (s, a0:Dynamic, _, _) -> {
			var first = a0;
			var form = same(first, undef()) ? "NFC" : Seed.text(first);
			if (["NFC", "NFD", "NFKC", "NFKD"].indexOf(form) < 0) return error("RangeError", "Invalid normalization form");
			return normalizeString(s, form);});
		m3("isWellFormed", 0, (s, _, _, _) -> wellFormed(s, true));
		m3("toWellFormed", 0, (s, _, _, _) -> wellFormed(s, false));
		m3("search", 1, (s, a0:Dynamic, _, _) -> matcher(s, a0, "search"));
		m3("match", 1, (s, a0:Dynamic, _, _) -> matcher(s, a0, "match"));
		m3("matchAll", 1, (s, a0:Dynamic, _, _) -> matcher(s, a0, "matchAll"));
		// (read-only: compiled code calls it itself on a string, Seed.stringCharCodeAt)
		p.setOwn("charCodeAt", p.getOwn("charCodeAt"), Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		fixed(p, Symbols.iterator, 0, (t, _, _, _) -> new JsIterator(StringIteratorProto, thisString(t), "values"));
	}

	// (a search's start: an integer from 0 to the length)
	static function from(s:String, v:Dynamic):Int return Std.int(Math.max(0, Math.min(toIntegerOrInfinity(v), s.length)));

	static function needle(v:Dynamic, name:String):String {
		if (Regex.isRegExp(v)) error("TypeError", "First argument to String.prototype." + name + " must not be a regular expression");
		return Seed.text(v);
	}

	static function trim(s:String, start:Bool, end:Bool):String {
		var i = 0, j = s.length;
		if (start) while (i < j && Seed.whitespace(StringTools.fastCodeAt(s, i))) i++;
		if (end) while (j > i && Seed.whitespace(StringTools.fastCodeAt(s, j - 1))) j--;
		return s.substring(i, j);
	}

	static function pad(s:String, first:Dynamic, second:Dynamic, start:Bool):String {
		var n = s.length;
		var target = toIntegerOrInfinity(first);
		var fill = Lib.same(second, undef()) ? " " : Seed.text(second);
		if (target <= n || fill == "") return s;
		if (target > 536870888) error("RangeError", "Invalid string length");
		var needed = Std.int(target - n);
		var padding = new StringBuf();
		if (fill.length == 1) for (_ in 0...needed) padding.addChar(StringTools.fastCodeAt(fill, 0));
		else while (padding.length < needed) padding.add(fill);
		var pad = fill.length == 1 ? padding.toString() : padding.toString().substr(0, needed);
		return start ? pad + s : s + pad;
	}

	static function wellFormed(s:String, test:Bool):Dynamic {
		var n = s.length;
		var b = new StringBuf();
		var ok = true;
		var i = 0;
		while (i < n) {
			var c = StringTools.fastCodeAt(s, i);
			if (c >= 0xd800 && c <= 0xdbff && i + 1 < n && StringTools.fastCodeAt(s, i + 1) >= 0xdc00 && StringTools.fastCodeAt(s, i + 1) <= 0xdfff) {
				b.addChar(c);
				b.addChar(StringTools.fastCodeAt(s, i + 1));
				i += 2;
				continue;
			}
			if (c >= 0xd800 && c <= 0xdfff) {
				ok = false;
				b.addChar(0xfffd);
			} else b.addChar(c);
			i++;
		}
		return test ? ok : b.toString();
	}

	static function split(s:String, first:Dynamic, second:Dynamic):Dynamic {
		var n = s.length;
		if (first != null && !Lib.same(first, undef())) {
			var splitter = getKey(first, "\x00@@split", first);
			if (!same(splitter, undef()) && splitter != null) return call(splitter, first, [s, second]);
		}
		var limit = Lib.same(second, undef()) ? 4294967295.0 : toUint32(second);
		var out:Array<Dynamic> = [];
		if (limit == 0) return array(out);
		if (Lib.same(first, undef())) return array([s]);
		var delimiter = Seed.text(first);
		if (delimiter == "") {
			var i = 0;
			while (i < n && out.length < limit) out.push(s.charAt(i++));
			return array(out);
		}
		var start = 0;
		while (out.length < limit) {
			var i = s.indexOf(delimiter, start);
			if (i < 0) {
				out.push(s.substr(start));
				break;
			}
			out.push(s.substring(start, i));
			start = i + delimiter.length;
		}
		return array(out);
	}

	static function replace(s:String, first:Dynamic, second:Dynamic, all:Bool):Dynamic {
		var n = s.length;
		if (!all && Regex.pristine(first)) return Regex.replace(first, s, second);
		if (first != null && !Lib.same(first, undef())) {
			if (all && Regex.isRegExp(first) && Seed.text(get(first, "flags")).indexOf("g") < 0) error("TypeError", "replaceAll must be called with a global RegExp");
			var replacer = getKey(first, "\x00@@replace", first);
			if (!same(replacer, undef()) && replacer != null) return call(replacer, first, [s, second]);
		}
		var search = Seed.text(first);
		var functional = isCallable(second);
		var replacement = functional ? "" : Seed.text(second);
		var b = new StringBuf();
		var start = 0;
		var pos = s.indexOf(search);
		while (pos >= 0) {
			b.add(s.substring(start, pos));
			b.add(functional ? Seed.text(call(second, undef(), [search, pos, s])) : Regex.expand(replacement, search, s, pos, [], null));
			start = pos + search.length;
			if (!all) break;
			if (search == "") {
				if (pos >= n) break;
				b.add(s.charAt(pos));
				start = pos + 1;
			}
			pos = s.indexOf(search, start);
		}
		b.add(s.substr(start));
		return b.toString();
	}

	static function matcher(s:String, first:Dynamic, name:String):Dynamic {
		var symbol = name == "search" ? "\x00@@search" : name == "match" ? "\x00@@match" : "\x00@@matchAll";
		if (first != null && !same(first, undef())) {
			if (name == "matchAll" && Regex.isRegExp(first) && Seed.text(get(first, "flags")).indexOf("g") < 0) error("TypeError", "String.prototype.matchAll called with a non-global RegExp argument");
			var m = getKey(first, symbol, first);
			if (!same(m, undef()) && m != null) return call(m, first, [s]);
		}
		var re = createRegExp(same(first, undef()) ? "" : Seed.text(first), name == "matchAll" ? "g" : "");
		return call(get(re, symbol), re, [s]);
	}

	// localeCompare: an approximation of ICU's root collation in three levels:
	// base characters (punctuation, then digits, then letters with Latin
	// accents folded), then accents, then case (lowercase first).
	static var accents = "ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇç";
	static var bases = "AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCc";
	// (the accented letters are all in U+00C0 to U+00FF: their bases by code unit)
	static var latin:Array<Int> = null;

	static function baseOf(c:Int):Int {
		if (c < 0xc0 || c > 0xff) return c;
		if (latin == null) {
			latin = [for (u in 0xc0...0x100) u];
			for (k in 0...accents.length) latin[StringTools.fastCodeAt(accents, k) - 0xc0] = StringTools.fastCodeAt(bases, k);
		}
		return latin[c - 0xc0];
	}

	static function lower(c:Int):Int {
		if (c < 128) return c >= 65 && c <= 90 ? c + 32 : c;
		return String.fromCharCode(c).toLowerCase().charCodeAt(0);
	}

	static function primary(c:Int):Int {
		var b = baseOf(c);
		if (b >= 65 && b <= 90) b += 32;
		if (b >= 97 && b <= 122) return 30000 + b;
		if (b >= 48 && b <= 57) return 20000 + b;
		if (b >= 0xc0) return 40000 + lower(b);
		return 10000 + b;
	}

	// (primary's of the ASCII code units)
	static var ascii:Array<Int> = null;

	public static function collate(a:String, b:String):Int {
		if (a == b) return 0;
		if (ascii == null) ascii = [for (c in 0...128) primary(c)];
		var n = a.length < b.length ? a.length : b.length;
		for (i in 0...n) {
			var x = StringTools.fastCodeAt(a, i), y = StringTools.fastCodeAt(b, i);
			if (x == y) continue;
			x = x < 128 ? ascii[x] : primary(x);
			y = y < 128 ? ascii[y] : primary(y);
			if (x != y) return x < y ? -1 : 1;
		}
		if (a.length != b.length) return a.length < b.length ? -1 : 1;
		for (i in 0...n) {
			var x = StringTools.fastCodeAt(a, i), y = StringTools.fastCodeAt(b, i);
			var ax = baseOf(x) != x, ay = baseOf(y) != y;
			if (ax != ay) return ax ? 1 : -1;
		}
		for (i in 0...n) {
			var x = StringTools.fastCodeAt(a, i), y = StringTools.fastCodeAt(b, i);
			if (x == y) continue;
			var lx = lower(x) == x, ly = lower(y) == y;
			if (lx != ly) return lx ? -1 : 1;
		}
		var c = compareStrings(a, b);
		return c < 0 ? -1 : c > 0 ? 1 : 0;
	}
}
