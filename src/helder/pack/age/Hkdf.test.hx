package helder.pack.age;

import haxe.io.Bytes;
import helder.test.Test;

// HMAC-SHA256 against RFC 4231's test cases (1 to 4, 6 and 7: a key longer
// than a block), HKDF-SHA256 against RFC 5869's (A.1 to A.3)
function tests() {
	function rep(byte:Int, n:Int):Bytes {
		var b = Bytes.alloc(n);
		b.fill(0, n, byte);
		return b;
	}
	function seq(from:Int):Bytes {
		var b = Bytes.alloc(80);
		for (i in 0...80) b.set(i, from + i);
		return b;
	}
	function hmac(k:Bytes, m:Bytes):String
		return Hkdf.hmac(k, m).toHex();

	test("RFC 4231: HMAC-SHA256", () -> {
		equals(hmac(rep(0x0b, 20), Bytes.ofString("Hi There")), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
		equals(hmac(Bytes.ofString("Jefe"), Bytes.ofString("what do ya want for nothing?")), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
		equals(hmac(rep(0xaa, 20), rep(0xdd, 50)), "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe");
		equals(hmac(Bytes.ofHex("0102030405060708090a0b0c0d0e0f10111213141516171819"), rep(0xcd, 50)), "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b");
		equals(hmac(rep(0xaa, 131), Bytes.ofString("Test Using Larger Than Block-Size Key - Hash Key First")), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
		equals(hmac(rep(0xaa, 131), Bytes.ofString("This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.")),
			"9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2");
	});
	test("RFC 5869 A.1: HKDF-SHA256", () -> {
		var prk = Hkdf.extract(Bytes.ofHex("000102030405060708090a0b0c"), rep(0x0b, 22));
		equals(prk.toHex(), "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5");
		equals(Hkdf.expand(prk, Bytes.ofHex("f0f1f2f3f4f5f6f7f8f9"), 42).toHex(), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865");
	});
	test("RFC 5869 A.2: longer inputs and outputs", () -> {
		equals(Hkdf.extract(seq(0x60), seq(0)).toHex(), "06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244");
		equals(Hkdf.derive(seq(0), seq(0x60), seq(0xb0), 82).toHex(),
			"b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87");
	});
	test("RFC 5869 A.3: no salt, no info", () -> {
		equals(Hkdf.extract(null, rep(0x0b, 22)).toHex(), "19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04");
		equals(Hkdf.derive(rep(0x0b, 22), Bytes.alloc(0), Bytes.alloc(0), 42).toHex(), "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8");
	});
}
