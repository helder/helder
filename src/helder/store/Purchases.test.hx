package helder.store;

import helder.test.Test;

// The prebuilt HelderStore libraries are StoreShim.swift's: its hash is
// the one build.sh recorded (edited without building again, this fails);
// the shim's JSON read into the types; no store here (Linux, wasm32-wasi,
// a program outside an app bundle); purchases that came before onPurchase
// given when it is set.
function tests() {
	describe("Purchases", () -> {
		test("the prebuilt libraries are StoreShim.swift's", () -> {
			final dir = "src/helder/store/apple";
			final source = StringTools.replace(sys.io.File.getContent('$dir/StoreShim.swift'), "\r", "");
			equals(haxe.crypto.Sha256.encode(source), StringTools.trim(sys.io.File.getContent('$dir/StoreShim.sha256')));
		});
		test("a product and a purchase read from the shim's JSON", () -> {
			final p = Purchases.product(haxe.Json.parse('{"id":"pro","kind":"subscription","title":"Pro","description":"All of it","price":"€5,00","amount":5,"currency":"EUR","period":"P1M"}'));
			equals(p.kind, Subscription);
			equals(p.amount, 5.0);
			equals(p.period, "P1M");
			final t = Purchases.of(haxe.Json.parse('{"id":"2000000123","product":"pro","date":1763700000000,"quantity":1,"expires":null,"revoked":null,"verified":true,"signed":"a.b.c"}'));
			equals(t.id, "2000000123");
			equals(t.date, 1763700000000.0);
			equals(t.expires, null);
			assert(t.verified);
		});
		test("none available here", () -> equals(Purchases.available(), false));
		test("purchases before onPurchase given when it is set", () -> {
			final p = Purchases.of({id: "1", product: "coins", date: 0, quantity: 3, verified: true, signed: ""});
			Purchases.update(p);
			final got = [];
			Purchases.onPurchase = p -> got.push(p.product);
			Purchases.update(p);
			Purchases.onPurchase = null;
			equals(got, ["coins", "coins"]);
		});
	});
}
