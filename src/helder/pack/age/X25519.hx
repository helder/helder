package helder.pack.age;

import haxe.io.Bytes;
import haxe.ds.Vector;

// X25519 (RFC 7748): the Montgomery ladder over Curve25519, for age's
// recipients (Age). A field element is 16 limbs of 16 bits held in Floats
// (doubles: a product of two limbs is 32 bits and a row of 16 of them,
// times 38, stays under 2^53, exact), as TweetNaCl's JavaScript port does,
// since Int is 32 bits; carries by floor division. The swaps are by masks,
// every scalar takes the same 255 steps.
class X25519 {
	static final A24 = gf([0xdb41, 1]);
	public static final BASE = {
		var b = ChaCha20Poly1305.zeros(32);
		b.set(0, 9);
		b;
	};

	// X25519(k, u): 32 bytes each (k clamped, u's top bit ignored)
	public static function scalarMult(k:Bytes, u:Bytes):Bytes {
		if (k.length != 32 || u.length != 32) throw "X25519 takes 32-byte scalars and points";
		var z = Bytes.alloc(32);
		z.blit(0, k, 0, 32);
		z.set(31, (k.get(31) & 127) | 64);
		z.set(0, z.get(0) & 248);
		var x = unpack(u);
		var a = gf(), b = copy(x), c = gf(), d = gf(), e = gf(), f = gf();
		a[0] = 1;
		d[0] = 1;
		var i = 254;
		while (i >= 0) {
			var r = (z.get(i >> 3) >> (i & 7)) & 1;
			sel(a, b, r);
			sel(c, d, r);
			add(e, a, c);
			sub(a, a, c);
			add(c, b, d);
			sub(b, b, d);
			mul(d, e, e);
			mul(f, a, a);
			mul(a, c, a);
			mul(c, b, e);
			add(e, a, c);
			sub(a, a, c);
			mul(b, a, a);
			sub(c, d, f);
			mul(a, c, A24);
			add(a, a, d);
			mul(c, c, a);
			mul(a, d, f);
			mul(d, b, x);
			mul(b, e, e);
			sel(a, b, r);
			sel(c, d, r);
			i--;
		}
		inv(c, c);
		mul(a, a, c);
		return pack(a);
	}

	// the public key of a secret one: X25519(k, 9)
	public static inline function publicKey(k:Bytes):Bytes
		return scalarMult(k, BASE);

	// ---- the field, modulo 2^255 - 19

	static function gf(?init:Array<Int>):Vector<Float> {
		var r = new Vector<Float>(16, 0.0);
		if (init != null) for (i in 0...init.length) r[i] = init[i];
		return r;
	}

	static function copy(a:Vector<Float>):Vector<Float> {
		var r = new Vector<Float>(16, 0.0);
		for (i in 0...16) r[i] = a[i];
		return r;
	}

	static function unpack(n:Bytes):Vector<Float> {
		var o = gf();
		for (i in 0...16) o[i] = n.get(2 * i) + (n.get(2 * i + 1) << 8);
		o[15] = Std.int(o[15]) & 0x7fff;
		return o;
	}

	// (each limb back to 0..65535, the carry out of the top one times 38 into the bottom)
	static function carry(o:Vector<Float>) {
		var c = 1.0;
		for (i in 0...16) {
			var v = o[i] + c + 65535;
			c = Math.ffloor(v / 65536);
			o[i] = v - c * 65536;
		}
		o[0] += 38 * (c - 1);
	}

	// (p and q swapped when b is 1)
	static function sel(p:Vector<Float>, q:Vector<Float>, b:Int) {
		var m = -b;
		for (i in 0...16) {
			var pi = Std.int(p[i]), qi = Std.int(q[i]);
			var t = m & (pi ^ qi);
			p[i] = pi ^ t;
			q[i] = qi ^ t;
		}
	}

	static function add(o:Vector<Float>, a:Vector<Float>, b:Vector<Float>)
		for (i in 0...16) o[i] = a[i] + b[i];

	static function sub(o:Vector<Float>, a:Vector<Float>, b:Vector<Float>)
		for (i in 0...16) o[i] = a[i] - b[i];

	// (the product's 31 limbs: one scratch row, reused; mul is not reentrant)
	static final T = new Vector<Float>(31, 0.0);

	static function mul(o:Vector<Float>, a:Vector<Float>, b:Vector<Float>) {
		var t = T;
		for (i in 0...31) t[i] = 0.0;
		for (i in 0...16) {
			var ai = a[i];
			for (j in 0...16) t[i + j] += ai * b[j];
		}
		for (i in 0...15) t[i] += 38 * t[i + 16];
		for (i in 0...16) o[i] = t[i];
		carry(o);
		carry(o);
	}

	// (a^(p - 2))
	static function inv(o:Vector<Float>, i:Vector<Float>) {
		var c = copy(i);
		var a = 253;
		while (a >= 0) {
			mul(c, c, c);
			if (a != 2 && a != 4) mul(c, c, i);
			a--;
		}
		for (k in 0...16) o[k] = c[k];
	}

	// (the canonical form, below p, little-endian)
	static function pack(n:Vector<Float>):Bytes {
		var t = copy(n), m = gf();
		carry(t);
		carry(t);
		carry(t);
		for (_ in 0...2) {
			m[0] = t[0] - 0xffed;
			for (i in 1...15) {
				m[i] = t[i] - 0xffff - ((Std.int(m[i - 1]) >> 16) & 1);
				m[i - 1] = Std.int(m[i - 1]) & 0xffff;
			}
			m[15] = t[15] - 0x7fff - ((Std.int(m[14]) >> 16) & 1);
			var b = (Std.int(m[15]) >> 16) & 1;
			m[14] = Std.int(m[14]) & 0xffff;
			sel(t, m, 1 - b);
		}
		var o = Bytes.alloc(32);
		for (i in 0...16) {
			var v = Std.int(t[i]);
			o.set(2 * i, v & 0xff);
			o.set(2 * i + 1, (v >> 8) & 0xff);
		}
		return o;
	}
}
