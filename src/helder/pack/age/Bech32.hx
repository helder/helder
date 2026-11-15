package helder.pack.age;

import haxe.io.Bytes;

using StringTools;

// Bech32 (BIP 173; not Bech32m): age's keys, `age1...` and
// `AGE-SECRET-KEY-1...`. No length limit (age has none, BIP 173's is 90);
// one case per string, lowercase written (uppercase: the caller's).
class Bech32 {
	static inline var CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
	static final GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

	public static function encode(hrp:String, data:Bytes):String {
		hrp = hrp.toLowerCase();
		var five = convert([for (i in 0...data.length) data.get(i)], 8, 5, true);
		var values = expand(hrp).concat(five).concat([0, 0, 0, 0, 0, 0]);
		var pm = polymod(values) ^ 1;
		var b = new StringBuf();
		b.add(hrp);
		b.add("1");
		for (v in five) b.add(CHARSET.charAt(v));
		for (i in 0...6) b.add(CHARSET.charAt((pm >> (5 * (5 - i))) & 31));
		return b.toString();
	}

	// the human-readable part (lowercase) and the data; throws on a bad string
	public static function decode(s:String):{hrp:String, data:Bytes} {
		var lower = s.toLowerCase(), upper = s.toUpperCase();
		if (s != lower && s != upper) throw "mixed case";
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c < 33 || c > 126) throw "a character out of range";
		}
		s = lower;
		var sep = s.lastIndexOf("1");
		if (sep < 1 || sep + 7 > s.length) throw "no separator, or too short";
		var hrp = s.substr(0, sep), values = [];
		for (i in sep + 1...s.length) {
			var v = CHARSET.indexOf(s.charAt(i));
			if (v < 0) throw 'not a Bech32 character: ${s.charAt(i)}';
			values.push(v);
		}
		if (polymod(expand(hrp).concat(values)) != 1) throw "a bad checksum";
		var eight = convert(values.slice(0, values.length - 6), 5, 8, false);
		var out = Bytes.alloc(eight.length);
		for (i in 0...eight.length) out.set(i, eight[i]);
		return {hrp: hrp, data: out};
	}

	static function polymod(values:Array<Int>):Int {
		var chk = 1;
		for (v in values) {
			var top = chk >>> 25;
			chk = ((chk & 0x1ffffff) << 5) ^ v;
			for (i in 0...5) if ((top >> i) & 1 != 0) chk ^= GEN[i];
		}
		return chk;
	}

	static function expand(hrp:String):Array<Int> {
		var r = [for (i in 0...hrp.length) hrp.charCodeAt(i) >> 5];
		r.push(0);
		for (i in 0...hrp.length) r.push(hrp.charCodeAt(i) & 31);
		return r;
	}

	static function convert(data:Array<Int>, from:Int, to:Int, pad:Bool):Array<Int> {
		var acc = 0, bits = 0, out = [], max = (1 << to) - 1;
		for (v in data) {
			acc = (acc << from) | v;
			bits += from;
			while (bits >= to) {
				bits -= to;
				out.push((acc >> bits) & max);
			}
			acc &= (1 << bits) - 1;
		}
		if (pad) {
			if (bits > 0) out.push((acc << (to - bits)) & max);
		} else if (bits >= from || ((acc << (to - bits)) & max) != 0)
			throw "bad padding";
		return out;
	}
}
