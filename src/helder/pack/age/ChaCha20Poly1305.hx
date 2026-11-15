package helder.pack.age;

import haxe.io.Bytes;
import haxe.ds.Vector;

// ChaCha20-Poly1305 (RFC 8439), the AEAD of age's stanzas and payload
// (Age): ChaCha20's 20 rounds on 32-bit Ints (their sums wrap), Poly1305 in
// 17 limbs of 8 bits (TweetNaCl's: a product row stays under 2^29), the
// tag compared in constant time.
class ChaCha20Poly1305 {
	public static inline var TAG = 16;

	// the ciphertext and its tag (key: 32 bytes, nonce: 12)
	public static function seal(key:Bytes, nonce:Bytes, plaintext:Bytes, ?aad:Bytes):Bytes {
		var out = Bytes.alloc(plaintext.length + TAG);
		var ct = ChaCha20.xor(key, nonce, 1, plaintext);
		out.blit(0, ct, 0, ct.length);
		out.blit(ct.length, tag(key, nonce, ct, aad), 0, TAG);
		return out;
	}

	// the plaintext, or null when the tag is not the ciphertext's
	public static function open(key:Bytes, nonce:Bytes, sealed:Bytes, ?aad:Bytes):Null<Bytes> {
		if (sealed.length < TAG) return null;
		var ct = sealed.sub(0, sealed.length - TAG);
		if (!equal(tag(key, nonce, ct, aad), sealed.sub(ct.length, TAG))) return null;
		return ChaCha20.xor(key, nonce, 1, ct);
	}

	static function tag(key:Bytes, nonce:Bytes, ct:Bytes, aad:Null<Bytes>):Bytes {
		var otk = ChaCha20.block(key, nonce, 0).sub(0, 32);
		aad = aad ?? Bytes.alloc(0);
		var pad = (n:Int) -> (16 - n % 16) % 16;
		var m = zeros(aad.length + pad(aad.length) + ct.length + pad(ct.length) + 16);
		m.blit(0, aad, 0, aad.length);
		var at = aad.length + pad(aad.length);
		m.blit(at, ct, 0, ct.length);
		at += ct.length + pad(ct.length);
		m.setInt32(at, aad.length);
		m.setInt32(at + 8, ct.length);
		return Poly1305.mac(otk, m);
	}

	// (n zero bytes: Bytes.alloc does not promise them)
	public static function zeros(n:Int):Bytes {
		var b = Bytes.alloc(n);
		b.fill(0, n, 0);
		return b;
	}

	public static function equal(a:Bytes, b:Bytes):Bool {
		if (a.length != b.length) return false;
		var d = 0;
		for (i in 0...a.length) d |= a.get(i) ^ b.get(i);
		return d == 0;
	}
}

class ChaCha20 {
	// the 64-byte block of a counter (key: 32 bytes, nonce: 12)
	public static function block(key:Bytes, nonce:Bytes, counter:Int):Bytes {
		if (key.length != 32 || nonce.length != 12) throw "ChaCha20 takes a 32-byte key and a 12-byte nonce";
		var s = new Vector<Int>(16);
		s[0] = 0x61707865;
		s[1] = 0x3320646e;
		s[2] = 0x79622d32;
		s[3] = 0x6b206574;
		for (i in 0...8) s[4 + i] = key.getInt32(4 * i);
		s[12] = counter;
		for (i in 0...3) s[13 + i] = nonce.getInt32(4 * i);
		var x = new Vector<Int>(16);
		for (i in 0...16) x[i] = s[i];
		for (_ in 0...10) {
			quarter(x, 0, 4, 8, 12);
			quarter(x, 1, 5, 9, 13);
			quarter(x, 2, 6, 10, 14);
			quarter(x, 3, 7, 11, 15);
			quarter(x, 0, 5, 10, 15);
			quarter(x, 1, 6, 11, 12);
			quarter(x, 2, 7, 8, 13);
			quarter(x, 3, 4, 9, 14);
		}
		var out = Bytes.alloc(64);
		for (i in 0...16) out.setInt32(4 * i, x[i] + s[i]);
		return out;
	}

	// data XORed with the key stream from a counter on
	public static function xor(key:Bytes, nonce:Bytes, counter:Int, data:Bytes):Bytes {
		var out = Bytes.alloc(data.length);
		var at = 0;
		while (at < data.length) {
			var ks = block(key, nonce, counter++);
			var n = data.length - at < 64 ? data.length - at : 64;
			for (i in 0...n) out.set(at + i, data.get(at + i) ^ ks.get(i));
			at += n;
		}
		return out;
	}

	static inline function rotl(v:Int, n:Int):Int
		return (v << n) | (v >>> (32 - n));

	static inline function quarter(x:Vector<Int>, a:Int, b:Int, c:Int, d:Int) {
		x[a] = x[a] + x[b];
		x[d] = rotl(x[d] ^ x[a], 16);
		x[c] = x[c] + x[d];
		x[b] = rotl(x[b] ^ x[c], 12);
		x[a] = x[a] + x[b];
		x[d] = rotl(x[d] ^ x[a], 8);
		x[c] = x[c] + x[d];
		x[b] = rotl(x[b] ^ x[c], 7);
	}
}

class Poly1305 {
	static final MINUS_P = [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 252];

	// the 16-byte tag of a message by a one-time key (32 bytes: r, s)
	public static function mac(key:Bytes, m:Bytes):Bytes {
		var r = new Vector<Int>(17, 0), h = new Vector<Int>(17, 0), c = new Vector<Int>(17, 0), x = new Vector<Int>(17, 0);
		for (j in 0...16) r[j] = key.get(j);
		for (j in [3, 7, 11, 15]) r[j] &= 15;
		for (j in [4, 8, 12]) r[j] &= 252;
		var at = 0, n = m.length;
		while (n > 0) {
			for (j in 0...17) c[j] = 0;
			var j = 0;
			while (j < 16 && j < n) {
				c[j] = m.get(at + j);
				j++;
			}
			c[j] = 1;
			at += j;
			n -= j;
			add(h, c);
			for (i in 0...17) {
				var s = 0;
				for (k in 0...17) s += h[k] * (k <= i ? r[i - k] : 320 * r[i + 17 - k]);
				x[i] = s;
			}
			for (i in 0...17) h[i] = x[i];
			var u = 0;
			for (k in 0...16) {
				u += h[k];
				h[k] = u & 255;
				u >>>= 8;
			}
			u += h[16];
			h[16] = u & 3;
			u = 5 * (u >>> 2);
			for (k in 0...16) {
				u += h[k];
				h[k] = u & 255;
				u >>>= 8;
			}
			u += h[16];
			h[16] = u;
		}
		var g = new Vector<Int>(17);
		for (j in 0...17) g[j] = h[j];
		var mp = new Vector<Int>(17);
		for (j in 0...17) mp[j] = MINUS_P[j];
		add(h, mp);
		var s = -(h[16] >>> 7);
		for (j in 0...17) h[j] ^= s & (g[j] ^ h[j]);
		for (j in 0...16) c[j] = key.get(j + 16);
		c[16] = 0;
		add(h, c);
		var out = Bytes.alloc(16);
		for (j in 0...16) out.set(j, h[j]);
		return out;
	}

	static function add(h:Vector<Int>, c:Vector<Int>) {
		var u = 0;
		for (j in 0...17) {
			u += h[j] + c[j];
			h[j] = u & 255;
			u >>>= 8;
		}
	}
}
