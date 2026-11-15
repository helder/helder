package helder.pack.age;

import haxe.io.Bytes;
import helder.test.Test;

// Bech32 against BIP 173's valid and invalid strings (but the one over 90
// characters: age has no limit), then an age identity's back and forth
function tests() {
	test("BIP 173: the valid strings decode, and encode back", () -> {
		for (s in [
			"A12UEL5L", "a12uel5l", "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
			"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w", "?1ezyfcl"
		]) {
			var d = Bech32.decode(s);
			equals(Bech32.encode(d.hrp, d.data), s.toLowerCase(), s);
		}
		// (its 5-bit data is not whole bytes: its checksum alone)
		equals(Bech32.decode("11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j").hrp, "1");
	});
	test("BIP 173: the invalid strings are refused", () -> {
		for (s in [
			" 1nwldj5", String.fromCharCode(0x7f) + "1axkwrx", String.fromCharCode(0x80) + "1eym55h", "pzry9x0s0muk", "1pzry9x0s0muk", "x1b4n0q5v", "li1dgmt3",
			"de1lg7wt" + String.fromCharCode(0xff), "A1G7SGD8", "10a06t8", "1qzzfhee", "A12uEL5L"
		])
			throws(() -> Bech32.decode(s), s);
	});
	test("an age identity: its 32 bytes and back", () -> {
		var d = Bech32.decode("AGE-SECRET-KEY-1EGTZVFFV20835NWYV6270LXYVK2VKNX2MMDKWYKLMGR48UAWX40Q2P2LM0");
		equals(d.hrp, "age-secret-key-");
		equals(d.data.length, 32);
		equals(Bech32.encode("age-secret-key-", d.data).toUpperCase(), "AGE-SECRET-KEY-1EGTZVFFV20835NWYV6270LXYVK2VKNX2MMDKWYKLMGR48UAWX40Q2P2LM0");
	});
}
