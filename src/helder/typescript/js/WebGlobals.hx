package helder.typescript.js;

import haxe.crypto.Base64;
import haxe.io.Bytes;
import helder.pack.Entropy;
import helder.typescript.js.Buffers.JsBuffer;
import helder.typescript.js.Buffers.JsDataView;
import helder.typescript.js.Lib.*;
import helder.typescript.js.TypedArrays.JsTypedArray;
import helder.typescript.js.Values;

private class JsTextEncoder extends JsObject {}

private class JsTextDecoder extends JsObject {
	public final fatal:Bool;
	public final ignoreBOM:Bool;

	public function new(proto:JsObject, fatal:Bool, ignoreBOM:Bool) {
		super(proto);
		this.fatal = fatal;
		this.ignoreBOM = ignoreBOM;
	}
}

@:access(helder.typescript.js.Builtins)
@:access(helder.typescript.js.Strings)
class WebGlobals {
	public static function setup():Void {
		var encoder = new JsObject(Builtins.ObjectProto);
		Builtins.constructor("TextEncoder", 0, encoder, (_, _, nt) -> {
			if (nt == undef()) return error("TypeError", "TextEncoder requires 'new'");
			return new JsTextEncoder(protoFrom(nt, encoder));
		});
		encoder.setOwn(Symbols.toStringTag, "TextEncoder", Attr.HIDDEN | Attr.READONLY);
		Builtins.getter(encoder, "encoding", t -> {
			checkEncoder(t);
			return "utf-8";
		});
		Builtins.fixed(encoder, "encode", 0, (t, source, _, _) -> {
			checkEncoder(t);
			return TypedArrays.ofBytes(encode(source == undef() ? "" : Seed.text(source)));
		});
		Builtins.method(encoder, "encodeInto", 2, (t, a, _) -> {
			checkEncoder(t);
			if (a.length < 2) return error("TypeError", "TextEncoder.encodeInto requires a source and destination");
			var s = Seed.text(a[0]), dest = a[1];
			if (!Std.isOfType(dest, JsTypedArray) || (dest : JsTypedArray).kind != TypedArrays.UINT8)
				return error("TypeError", "TextEncoder.encodeInto requires a Uint8Array destination");
			return encodeInto(s, dest);
		});

		var decoder = new JsObject(Builtins.ObjectProto);
		Builtins.constructor("TextDecoder", 0, decoder, (_, a, nt) -> {
			if (nt == undef()) return error("TypeError", "TextDecoder requires 'new'");
			var label = arg(a, 0);
			var name = label == undef() ? "utf-8" : Seed.text(label);
			var opts = dictionary(arg(a, 1));
			var fatal = option(opts, "fatal"), ignoreBOM = option(opts, "ignoreBOM");
			var lo = 0, hi = name.length;
			while (lo < hi && asciiSpace(StringTools.fastCodeAt(name, lo))) lo++;
			while (hi > lo && asciiSpace(StringTools.fastCodeAt(name, hi - 1))) hi--;
			switch name.substring(lo, hi).toLowerCase() {
				case "utf-8" | "utf8" | "unicode-1-1-utf-8" | "unicode11utf8" | "unicode20utf8" | "x-unicode20utf8":
				case _: return error("RangeError", "TextDecoder only supports UTF-8");
			}
			return new JsTextDecoder(protoFrom(nt, decoder), fatal, ignoreBOM);
		});
		decoder.setOwn(Symbols.toStringTag, "TextDecoder", Attr.HIDDEN | Attr.READONLY);
		Builtins.getter(decoder, "encoding", t -> {
			checkDecoder(t);
			return "utf-8";
		});
		Builtins.getter(decoder, "fatal", t -> checkDecoder(t).fatal);
		Builtins.getter(decoder, "ignoreBOM", t -> checkDecoder(t).ignoreBOM);
		Builtins.fixed(decoder, "decode", 0, (t, source:Dynamic, opts, _) -> {
			var d = checkDecoder(t);
			if (source != undef() && !Std.isOfType(source, JsTypedArray) && !Std.isOfType(source, JsDataView) && !Std.isOfType(source, JsBuffer))
				return error("TypeError", "TextDecoder.decode requires an ArrayBuffer or a view");
			if (option(dictionary(opts), "stream")) return error("TypeError", "TextDecoder.decode does not support streaming");
			if (Std.isOfType(source, JsTypedArray) && (source : JsTypedArray).length() == 0) return "";
			if (Std.isOfType(source, JsDataView)) {
				var v:JsDataView = source;
				if (v.buffer.data == null || v.offset > v.buffer.length() || v.size >= 0 && v.offset + v.size > v.buffer.length()) return "";
			}
			var bytes = source == undef() ? null : TypedArrays.bytesOf(source);
			return bytes == null ? "" : decode(bytes, d.fatal, d.ignoreBOM);
		});

		var crypto = new JsObject(Builtins.ObjectProto);
		crypto.setOwn(Symbols.toStringTag, "Crypto", Attr.HIDDEN | Attr.READONLY);
		Builtins.fixed(crypto, "getRandomValues", 1, (t, dest, _, _) -> {
			if (t != crypto) return error("TypeError", "Incompatible Crypto receiver");
			return randomValues(dest);
		});
		Builtins.fixed(crypto, "randomUUID", 0, (t, _, _, _) -> {
			if (t != crypto) return error("TypeError", "Incompatible Crypto receiver");
			var b = Entropy.bytes(16);
			b.set(6, (b.get(6) & 0x0f) | 0x40);
			b.set(8, (b.get(8) & 0x3f) | 0x80);
			var h = b.toHex();
			return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" + h.substr(20);
		});
		Builtins.globals.set("crypto", crypto);

		// hxmc exposes its monotonic clock in seconds on native and WASI.
		var performance = new JsObject(Builtins.ObjectProto), origin = hxmc.GcStats.now();
		performance.setOwn(Symbols.toStringTag, "Performance", Attr.HIDDEN | Attr.READONLY);
		Builtins.fixed(performance, "now", 0, (t, _, _, _) -> {
			if (t != performance) return error("TypeError", "Incompatible Performance receiver");
			return (hxmc.GcStats.now() - origin) * 1000.0;
		});
		Builtins.globals.set("performance", performance);

		for (name in ["atob", "btoa"]) Builtins.globals.set(name, Builtins.native(name, 1, (_, a, _) -> {
			if (a.length == 0) return error("TypeError", name + " requires an argument");
			var s = Seed.text(a[0]);
			return name == "atob" ? fromBase64(s) : toBase64(s);
		}));
	}

	static function checkEncoder(t:Dynamic):Void {
		if (!Std.isOfType(t, JsTextEncoder)) error("TypeError", "Incompatible TextEncoder receiver");
	}

	static function checkDecoder(t:Dynamic):JsTextDecoder {
		if (!Std.isOfType(t, JsTextDecoder)) return error("TypeError", "Incompatible TextDecoder receiver");
		return t;
	}

	static function dictionary(v:Dynamic):Dynamic {
		if (v == null || v == undef()) return null;
		if (!isObject(v)) return error("TypeError", "Expected an options object");
		return v;
	}

	static function option(o:Dynamic, name:String):Bool return o != null && Seed.truth(get(o, name));

	static function encode(s:String):Bytes return Bytes.ofString(Strings.wellFormed(s, false));

	static function encodeInto(s:String, dest:JsTypedArray):JsObject {
		var read = 0, written = 0, capacity = dest.length();
		while (read < s.length && written < capacity) {
			var c = StringTools.fastCodeAt(s, read), units = 1;
			if (c >= 0xd800 && c <= 0xdbff && read + 1 < s.length) {
				var next = StringTools.fastCodeAt(s, read + 1);
				if (next >= 0xdc00 && next <= 0xdfff) units = 2;
			}
			var width = units == 2 ? 4 : c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
			if (width > capacity - written) break;
			read += units;
			written += width;
		}
		if (written > 0) dest.bytes().blit(dest.offset, encode(s.substr(0, read)), 0, written);
		var result = new JsObject(Builtins.ObjectProto);
		result.setOwn("read", (read : Float), 0);
		result.setOwn("written", (written : Float), 0);
		return result;
	}

	// Decode well-formed runs with Bytes. On an error the offending byte, if
	// any, starts the next sequence (a truncated but valid prefix is one error).
	static function decode(bytes:Bytes, fatal:Bool, ignoreBOM:Bool):String {
		var end = bytes.length, start = 0;
		if (!ignoreBOM && end >= 3 && bytes.get(0) == 0xef && bytes.get(1) == 0xbb && bytes.get(2) == 0xbf) start = 3;
		var i = start, out:StringBuf = null;
		while (i < end) {
			var at = i, b = bytes.get(i++);
			if (b < 0x80) continue;
			var needed = b < 0xc2 || b > 0xf4 ? 0 : b < 0xe0 ? 1 : b < 0xf0 ? 2 : 3;
			var lo = b == 0xe0 ? 0xa0 : b == 0xf0 ? 0x90 : 0x80;
			var hi = b == 0xed ? 0x9f : b == 0xf4 ? 0x8f : 0xbf;
			var left = needed;
			while (left > 0 && i < end) {
				var c = bytes.get(i);
				if (c < lo || c > hi) break;
				i++;
				left--;
				lo = 0x80;
				hi = 0xbf;
			}
			if (needed != 0 && left == 0) continue;
			if (fatal) return error("TypeError", "The encoded data is not valid UTF-8");
			if (out == null) out = new StringBuf();
			if (at > start) out.add(bytes.getString(start, at - start));
			out.addChar(0xfffd);
			start = i;
		}
		var tail = bytes.getString(start, end - start);
		if (out == null) return tail;
		out.add(tail);
		return out.toString();
	}

	static function randomValues(dest:Dynamic):Dynamic {
		if (!Std.isOfType(dest, JsTypedArray) || (dest : JsTypedArray).kind > TypedArrays.UINT32)
			return namedError("TypeMismatchError", "crypto.getRandomValues requires an integer typed array");
		var t:JsTypedArray = dest, length = t.length() * TypedArrays.WIDTHS[t.kind];
		if (length > 65536) return namedError("QuotaExceededError", "crypto.getRandomValues is limited to 65536 bytes");
		if (length > 0) t.bytes().blit(t.offset, Entropy.bytes(length), 0, length);
		return dest;
	}

	static function asciiSpace(c:Int):Bool return c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0c || c == 0x0d;

	static function fromBase64(s:String):String {
		var clean = new StringBuf();
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (!asciiSpace(c)) clean.addChar(c);
		}
		var input = clean.toString(), n = input.length;
		if (n > 0 && n % 4 == 0 && input.charCodeAt(n - 1) == 61) {
			n--;
			if (input.charCodeAt(n - 1) == 61) n--;
		}
		if (n % 4 == 1) return namedError("InvalidCharacterError", "Invalid base64 input");
		for (i in 0...n) {
			var c = StringTools.fastCodeAt(input, i);
			if (!(c >= 65 && c <= 90 || c >= 97 && c <= 122 || c >= 48 && c <= 57 || c == 43 || c == 47))
				return namedError("InvalidCharacterError", "Invalid base64 input");
		}
		var bytes = Base64.decode(input.substr(0, n), false), out = new StringBuf();
		for (i in 0...bytes.length) out.addChar(bytes.get(i));
		return out.toString();
	}

	static function toBase64(s:String):String {
		var bytes = Bytes.alloc(s.length);
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c > 255) return namedError("InvalidCharacterError", "btoa requires a Latin-1 string");
			bytes.set(i, c);
		}
		return Base64.encode(bytes);
	}

	static function namedError(name:String, message:String):Dynamic {
		var e:JsObject = Builtins.makeError("Error", message);
		e.setOwn("name", name, Attr.HIDDEN);
		throw e;
	}
}
