package helder.pack.age;

import haxe.io.Bytes;
import haxe.crypto.Sha256;

// HMAC-SHA256 (RFC 2104) and HKDF-SHA256 (RFC 5869) on haxe.crypto.Sha256,
// for age's keys (Age: the stanzas' wrapping key, the header's MAC key,
// the payload's key).
class Hkdf {
	public static function hmac(key:Bytes, message:Bytes):Bytes {
		if (key.length > 64) key = Sha256.make(key);
		var inner = Bytes.alloc(64 + message.length), outer = Bytes.alloc(64 + 32);
		for (i in 0...64) {
			var k = i < key.length ? key.get(i) : 0;
			inner.set(i, k ^ 0x36);
			outer.set(i, k ^ 0x5c);
		}
		inner.blit(64, message, 0, message.length);
		outer.blit(64, Sha256.make(inner), 0, 32);
		return Sha256.make(outer);
	}

	// HKDF's extract then expand: length bytes (at most 255 * 32)
	public static function derive(ikm:Bytes, salt:Null<Bytes>, info:Bytes, length:Int):Bytes
		return expand(extract(salt, ikm), info, length);

	public static function extract(salt:Null<Bytes>, ikm:Bytes):Bytes
		return hmac(salt == null || salt.length == 0 ? ChaCha20Poly1305.zeros(32) : salt, ikm);

	public static function expand(prk:Bytes, info:Bytes, length:Int):Bytes {
		if (length > 255 * 32) throw "HKDF-SHA256 expands to 8160 bytes at most";
		var out = Bytes.alloc(length), t = Bytes.alloc(0), at = 0, i = 1;
		while (at < length) {
			var m = Bytes.alloc(t.length + info.length + 1);
			m.blit(0, t, 0, t.length);
			m.blit(t.length, info, 0, info.length);
			m.set(m.length - 1, i++);
			t = hmac(prk, m);
			var n = length - at < 32 ? length - at : 32;
			out.blit(at, t, 0, n);
			at += n;
		}
		return out;
	}
}
