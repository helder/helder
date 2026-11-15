package helder.pack.age;

import haxe.io.Bytes;
import helder.pack.age.ChaCha20Poly1305;
import helder.test.Test;

// ChaCha20, Poly1305 and their AEAD (ChaCha20Poly1305) against RFC 8439's
// vectors: 2.3.2 (the block), 2.4.2 (the cipher), 2.5.2 (the MAC), 2.8.2
// (the AEAD, opened back, and refused with a bit flipped)
function tests() {
	final sunscreen = Bytes.ofString("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
	final key = Bytes.ofHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f");

	test("RFC 8439 2.3.2: the block function", () -> {
		equals(ChaCha20.block(key, Bytes.ofHex("000000090000004a00000000"), 1).toHex(),
			"10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e");
	});
	test("RFC 8439 2.4.2: the cipher, from counter 1", () -> {
		equals(ChaCha20.xor(key, Bytes.ofHex("000000000000004a00000000"), 1, sunscreen).toHex(),
			"6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d");
	});
	test("RFC 8439 2.5.2: Poly1305", () -> {
		equals(Poly1305.mac(Bytes.ofHex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"), Bytes.ofString("Cryptographic Forum Research Group")).toHex(),
			"a8061dc1305136c6c22b8baf0c0127a9");
	});
	test("RFC 8439 2.8.2: the AEAD, opened back, a flipped bit refused", () -> {
		var k = Bytes.ofHex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
		var nonce = Bytes.ofHex("070000004041424344454647"), aad = Bytes.ofHex("50515253c0c1c2c3c4c5c6c7");
		var sealed = ChaCha20Poly1305.seal(k, nonce, sunscreen, aad);
		equals(sealed.toHex(),
			"d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116"
			+ "1ae10b594f09e26a7e902ecbd0600691");
		equals(ChaCha20Poly1305.open(k, nonce, sealed, aad).toString(), sunscreen.toString());
		sealed.set(5, sealed.get(5) ^ 1);
		equals(ChaCha20Poly1305.open(k, nonce, sealed, aad), null);
		equals(ChaCha20Poly1305.open(k, nonce, Bytes.alloc(10), aad), null);
	});
}
