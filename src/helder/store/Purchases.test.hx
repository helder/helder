package helder.store;

import helder.test.Test;

// The prebuilt HelderStore libraries are StoreShim.swift's: its hash is
// the one build.sh recorded (edited without building again, this fails);
// the shim's JSON read into the types; no store here (Linux, wasm32-wasi,
// a program outside an app bundle); purchases that came before onPurchase
// given when it is set; Play's products and purchases read
// (helder.store.android.AndroidPurchases), a purchase's signature checked against a license key
// (a key made for this test, not an app's).
final KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAowdv/CyGoaAh8g5y3GJWLn2boMyeA+eo1GXGLI4bGN3LiWS8/p4ZL/XPAmUJCbwCDmV2vzE+LRjdqzUXzFTu8RGfuTBH27D3KvUbrtjzS5G3TV6s3G811+YN4x9ONQdby7cnqA+GN6rwk9n+DUdfnGh6PMoS2R3zAmGA3eu5abzTg++5HgMpyf2Z0Q2L+7guggfx27eC5eA4R7VnC8wAF0JJ4pRUfLy48SQSmMigAZnhXuzQ3EpRpqcUORn2iXkVrS8FZChxFERgzH/k6ZyY/3RfLgaveDPpg3cV6+9i/uj993JCQkOyfNcRopZGhSY5/SGPkSiYG9fia9E4TSlg9wIDAQAB";
final SIGNATURE = "Dw9tS4EohV6MbjYqZddSmnpQsjsL3SDd7ocH3OTrvZpTvJl0x0ZBUhT/8tPfZiy+ZGj8PUNGRJ70/Vg4BgGZPiobYDCToN8huZzq7/MyDQ2X3pFnDwJyp2pscAqlPA+y0HfwpQ2pu+o0k180iA8ca6W0fVKZ53zFHpcbOYRgYSC17PyoqE5b7zJNuz/aliK5AyVrpbwGzaE2AvXOBIns+M3ElnNZq/xGTgR8DJ8ap2wp1phFI1X7ul6tYnq+EjJhdJ/N69uTxjzhMHjII2zQ3ylGZKi6ZqmlpeE590zJcyOfrHcoQ/twXPoJ6OJ1iBVmTV2CJKGlVfFv/K9YZzmkgA==";
final JSON = '{"orderId":"GPA.3312-5551-0623-12345","packageName":"org.helder.billingcheck","productId":"coins","purchaseTime":1763700000000,"purchaseState":0,"purchaseToken":"abcdefghijklmnop.AO-J1Oy","quantity":3,"acknowledged":false}';

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
		test("a Play product: one-time, a subscription's base plan", () -> {
			final once = helder.store.android.AndroidPurchases.product({id: "coins", type: "inapp", name: "Coins", description: "100", once: {price: "€0,99", amount: 0.99, currency: "EUR"}, offers: []});
			equals(once.product.kind, NonConsumable);
			equals(once.product.price, "€0,99");
			equals(once.offer, null);
			final trial = {price: "Free", amount: 0.0, currency: "EUR", period: "P1W"}, month = {price: "€2,99", amount: 2.99, currency: "EUR", period: "P1M"};
			final subs = helder.store.android.AndroidPurchases.product({id: "plus", type: "subs", name: "Plus", description: "", offers: [{id: "intro", token: "t1", phases: [trial, month]}, {token: "t2", phases: [month]}]});
			equals(subs.product.kind, Subscription);
			equals(subs.offer, "t2");
			equals(subs.product.amount, 2.99);
			equals(subs.product.period, "P1M");
			equals(helder.store.android.AndroidPurchases.product({id: "plus", type: "subs", name: "Plus", description: "", offers: [{id: "intro", token: "t1", phases: [trial, month]}]}).offer, "t1");
			equals(helder.store.android.AndroidPurchases.product({id: "x", type: "subs", name: "", description: "", offers: []}), null);
		});
		test("a Play purchase, verified by the license key", () -> {
			final p = helder.store.android.AndroidPurchases.of(JSON, SIGNATURE, KEY);
			equals(p.id, "GPA.3312-5551-0623-12345");
			equals(p.product, "coins");
			equals(p.date, 1763700000000.0);
			equals(p.quantity, 3);
			equals(p.signed, "abcdefghijklmnop.AO-J1Oy");
			equals(p.expires, null);
			assert(p.verified);
			equals(helder.store.android.AndroidPurchases.of(JSON, SIGNATURE, null).verified, false);
			equals(helder.store.android.AndroidPurchases.of(StringTools.replace(JSON, '"quantity":3', '"quantity":4'), SIGNATURE, KEY).verified, false);
			equals(helder.store.android.AndroidPurchases.of(JSON, SIGNATURE, "not a key").verified, false);
			final test = helder.store.android.AndroidPurchases.of('{"productIds":["pro"],"purchaseTime":1,"purchaseToken":"tok"}', "", null);
			equals([test.id, test.product, Std.string(test.quantity)], ["tok", "pro", "1"]);
			equals(helder.store.android.AndroidPurchases.code(7), "ITEM_ALREADY_OWNED");
		});
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
