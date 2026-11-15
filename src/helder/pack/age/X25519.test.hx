package helder.pack.age;

import haxe.io.Bytes;
import helder.test.Test;

// X25519 (X25519) against RFC 7748's vectors: 5.2's two scalar
// multiplications and the iterated one (1 and 1,000 times), 6.1's
// Diffie-Hellman of Alice and Bob
function tests() {
	function x(k:String, u:String):String
		return X25519.scalarMult(Bytes.ofHex(k), Bytes.ofHex(u)).toHex();

	test("RFC 7748 5.2: the first vector", () -> {
		equals(x("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"),
			"c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");
	});
	test("RFC 7748 5.2: the second vector (u's top bit set: ignored)", () -> {
		equals(x("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d", "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"),
			"95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957");
	});
	test("RFC 7748 5.2: iterated once and 1,000 times", () -> {
		var k = X25519.BASE, u = X25519.BASE;
		for (i in 0...1000) {
			var r = X25519.scalarMult(k, u);
			u = k;
			k = r;
			if (i == 0) equals(k.toHex(), "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079");
		}
		equals(k.toHex(), "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51");
	});
	test("RFC 7748 6.1: Alice's and Bob's keys and their shared secret", () -> {
		var a = Bytes.ofHex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
		var b = Bytes.ofHex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
		var pa = X25519.publicKey(a), pb = X25519.publicKey(b);
		equals(pa.toHex(), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
		equals(pb.toHex(), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
		equals(X25519.scalarMult(a, pb).toHex(), "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");
		equals(X25519.scalarMult(b, pa).toHex(), "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");
	});
}
