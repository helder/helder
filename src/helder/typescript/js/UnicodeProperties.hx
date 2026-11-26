package helder.typescript.js;

// The code points a \p{...} names, as ECMAScript resolves its name: a
// General_Category value or a binary property alone, else gc=, sc= or scx=
// (and their long names) with a value; RegexProperties' tables, read on
// first use. Ranges are inclusive pairs, sorted and disjoint.
class UnicodeProperties {
	static var data:Null<Map<String, String>> = null;
	static var aliases:Map<String, String>;
	static final decoded:Map<String, Array<Int>> = [];

	public static function lookup(name:String):Null<Array<Int>> {
		if (data == null) {
			data = table(RegexProperties.data());
			aliases = table(RegexProperties.aliases());
		}
		var eq = name.indexOf("=");
		var key = if (eq < 0) {
			var gc = "gc=" + name, alias = aliases.get(name);
			data.exists(gc) ? gc : data.exists(name) ? name : alias;
		} else {
			var value = name.substr(eq + 1);
			switch name.substr(0, eq) {
				case "General_Category" | "gc":
					var alias = aliases.get(value);
					data.exists("gc=" + value) ? "gc=" + value : alias != null && StringTools.startsWith(alias, "gc=") ? alias : null;
				case "Script" | "sc": script(value);
				case "Script_Extensions" | "scx":
					var sc = script(value);
					sc == null ? null : "scx" + sc.substr(2);
				case _: null;
			}
		}
		return key == null ? null : ranges(key);
	}

	static function script(value:String):Null<String>
		return data.exists("sc=" + value) ? "sc=" + value : aliases.get("sc=" + value);

	static function table(text:String):Map<String, String> {
		var out = new Map<String, String>();
		for (entry in text.split(";")) {
			var colon = entry.indexOf(":");
			out.set(entry.substr(0, colon), entry.substr(colon + 1));
		}
		return out;
	}

	static function ranges(key:String):Array<Int> {
		var done = decoded.get(key);
		if (done != null) return done;
		var value = data.get(key);
		var out = if (StringTools.startsWith(key, "scx=")) {
			// (only the scripts whose extensions differ from them have an entry)
			var sc = ranges("sc" + key.substr(3));
			value == null ? sc : xor(sc, decode(value.substr(1)));
		} else if (value == null) {
			[];
		} else if (StringTools.startsWith(value, "=")) {
			normalize([for (m in value.substr(1).split("|")) for (r in ranges("gc=" + m)) r]);
		} else if (StringTools.startsWith(value, "!")) {
			xor([0, 0x10ffff], ranges(value.substr(1)));
		} else decode(value);
		decoded.set(key, out);
		return out;
	}

	// (base-36 gaps from the previous range's end and lengths)
	static function decode(text:String):Array<Int> {
		var out = [], prev = -1, numbers = text.split(",");
		var k = 0;
		while (k < numbers.length) {
			var a = prev + 1 + base36(numbers[k]), z = a + base36(numbers[k + 1]);
			out.push(a);
			out.push(z);
			prev = z;
			k += 2;
		}
		return out;
	}

	static function base36(s:String):Int {
		var n = 0;
		for (k in 0...s.length) {
			var c = s.charCodeAt(k);
			n = n * 36 + (c <= "9".code ? c - "0".code : c - "a".code + 10);
		}
		return n;
	}

	// ranges sorted and merged
	public static function normalize(ranges:Array<Int>):Array<Int> {
		var pairs = [for (k in 0...(ranges.length >> 1)) {a: ranges[2 * k], z: ranges[2 * k + 1]}];
		pairs.sort((x, y) -> x.a - y.a);
		var out:Array<Int> = [];
		for (p in pairs) {
			if (out.length > 0 && out[out.length - 1] + 1 >= p.a) {
				if (p.z > out[out.length - 1]) out[out.length - 1] = p.z;
			} else {
				out.push(p.a);
				out.push(p.z);
			}
		}
		return out;
	}

	// the code points in one of two sets and not the other
	static function xor(a:Array<Int>, b:Array<Int>):Array<Int> {
		// (each range's bounds toggle membership; a bound both have cancels)
		var points = [for (r in [a, b]) for (k in 0...(r.length >> 1)) for (p in [r[2 * k], r[2 * k + 1] + 1]) p];
		points.sort((x, y) -> x - y);
		var kept = [];
		for (p in points) if (kept.length > 0 && kept[kept.length - 1] == p) kept.pop() else kept.push(p);
		return [for (k in 0...kept.length) k % 2 == 0 ? kept[k] : kept[k] - 1];
	}
}
