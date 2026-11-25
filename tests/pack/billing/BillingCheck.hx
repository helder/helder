import helder.store.Purchases;
#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import helder.os.android.Jni;
import helder.store.android.AndroidPurchases as P;
#end

// helder.store's Google Play Billing on a device or emulator
// (tests/pack/billing.sh, CI's emulator): billing 9.1.0 and its tree put in
// by use (AndroidPurchases's keep list), the client built and connected,
// products of an id no store sells, owned(), each line printed; available()
// before and after. An emulator without the Play Store has no billing
// service: available false, the calls a short error (BILLING_UNAVAILABLE,
// SERVICE_UNAVAILABLE); one with it signed out, an error too; signed in, an
// empty list. Then, with no store: the library's ProductDetails and
// Purchase made from fixture JSON and read through AndroidPurchases's
// getters, the queries' and the billing flow's params built, a purchase's
// signature checked against a key made for this test ("billing: fixtures
// ok"). The program's thread turns its loop and the activity's commands in
// turn (no App here).
class BillingCheck {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.link();
		Sys.println("billing: started");
		var finished = false;
		helder.async.Async.launch(_ -> {
			Sys.println('billing: available ${Purchases.available()}');
			try Sys.println('billing: products ${Purchases.products(["x"]).length}') catch (e:Dynamic) Sys.println('billing: products failed $e');
			try Sys.println('billing: owned ${Purchases.owned().length}') catch (e:Dynamic) Sys.println('billing: owned failed $e');
			Sys.println('billing: available ${Purchases.available()}');
			Sys.println('billing: fixtures ${fixtures()}');
		}).onCompletion((_, e) -> {
			if (e != null) Sys.println('billing: failed $e');
			finished = true;
		});
		var loop = helder.async.Loop.current(), t0 = haxe.Timer.stamp();
		while (!finished && haxe.Timer.stamp() - t0 < 60) {
			loop.turn(0);
			helder.os.android.MainThread.wait(0.05);
		}
		Sys.println(finished ? "billing: done" : "billing: no answer in 60 s");
		#else
		Sys.println("billing: Android only");
		#end
	}

	#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	static final INAPP = '{"productId":"coins","type":"inapp","title":"Coins (Check)","name":"Coins","description":"100","skuDetailsToken":"t",'
		+ '"oneTimePurchaseOfferDetails":{"priceAmountMicros":990000,"priceCurrencyCode":"EUR","formattedPrice":"0.99 EUR","offerIdToken":"o"}}';
	static final SUBS = '{"productId":"plus","type":"subs","title":"Plus (Check)","name":"Plus","description":"","skuDetailsToken":"t","subscriptionOfferDetails":['
		+ '{"offerIdToken":"intro-token","basePlanId":"monthly","offerId":"intro","offerTags":[],"pricingPhases":['
		+ '{"priceAmountMicros":0,"priceCurrencyCode":"EUR","formattedPrice":"Free","billingPeriod":"P1W","recurrenceMode":2,"billingCycleCount":1},'
		+ '{"priceAmountMicros":2990000,"priceCurrencyCode":"EUR","formattedPrice":"2.99 EUR","billingPeriod":"P1M","recurrenceMode":1}]},'
		+ '{"offerIdToken":"base-token","basePlanId":"monthly","offerTags":[],"pricingPhases":['
		+ '{"priceAmountMicros":2990000,"priceCurrencyCode":"EUR","formattedPrice":"2.99 EUR","billingPeriod":"P1M","recurrenceMode":1}]}]}';
	static final KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAowdv/CyGoaAh8g5y3GJWLn2boMyeA+eo1GXGLI4bGN3LiWS8/p4ZL/XPAmUJCbwCDmV2vzE+LRjdqzUXzFTu8RGfuTBH27D3KvUbrtjzS5G3TV6s3G811+YN4x9ONQdby7cnqA+GN6rwk9n+DUdfnGh6PMoS2R3zAmGA3eu5abzTg++5HgMpyf2Z0Q2L+7guggfx27eC5eA4R7VnC8wAF0JJ4pRUfLy48SQSmMigAZnhXuzQ3EpRpqcUORn2iXkVrS8FZChxFERgzH/k6ZyY/3RfLgaveDPpg3cV6+9i/uj993JCQkOyfNcRopZGhSY5/SGPkSiYG9fia9E4TSlg9wIDAQAB";
	static final SIGNATURE = "Dw9tS4EohV6MbjYqZddSmnpQsjsL3SDd7ocH3OTrvZpTvJl0x0ZBUhT/8tPfZiy+ZGj8PUNGRJ70/Vg4BgGZPiobYDCToN8huZzq7/MyDQ2X3pFnDwJyp2pscAqlPA+y0HfwpQ2pu+o0k180iA8ca6W0fVKZ53zFHpcbOYRgYSC17PyoqE5b7zJNuz/aliK5AyVrpbwGzaE2AvXOBIns+M3ElnNZq/xGTgR8DJ8ap2wp1phFI1X7ul6tYnq+EjJhdJ/N69uTxjzhMHjII2zQ3ylGZKi6ZqmlpeE590zJcyOfrHcoQ/twXPoJ6OJ1iBVmTV2CJKGlVfFv/K9YZzmkgA==";
	static final JSON = '{"orderId":"GPA.3312-5551-0623-12345","packageName":"org.helder.billingcheck","productId":"coins","purchaseTime":1763700000000,"purchaseState":0,"purchaseToken":"abcdefghijklmnop.AO-J1Oy","quantity":3,"acknowledged":false}';

	// (on the main thread: what each read gave, "ok" when all agree)
	@:access(helder.store.android.AndroidPurchases) @:hxmc.unsafe(gc)
	static function fixtures():String {
		var said = [];
		helder.os.android.MainThread.run(() -> try {
			var pd = Jni.cls("com.android.billingclient.api.ProductDetails"), pc = Jni.cls("com.android.billingclient.api.Purchase");
			var made = [for (json in [INAPP, SUBS]) Jni.newObject(pd, Jni.method(pd, "<init>", "(Ljava/lang/String;)V"), Jni.string(json).toI64())];
			for (d in made) {
				var p = P.product(P.details(d));
				said.push('${p.product.id} ${p.product.kind} ${p.product.price} ${p.product.amount} ${p.product.period} ${p.offer}');
			}
			var b = P.read(Jni.newObject(pc, Jni.method(pc, "<init>", "(Ljava/lang/String;Ljava/lang/String;)V"), Jni.string(JSON).toI64(), Jni.string(SIGNATURE).toI64()));
			said.push('${b.purchase.id} ${b.purchase.product} ${b.purchase.quantity} ${b.state} ${P.of(JSON, SIGNATURE, KEY).verified}');
			P.params(["coins", "plus"], "inapp");
			P.ofType("subs");
			P.flow(made[1], "base-token", "00000000-0000-0000-0000-000000000000");
			said.push("params");
		} catch (e:Dynamic) said.push('failed $e'));
		var want = ["coins nonConsumable 0.99 EUR 0.99 null null", "plus subscription 2.99 EUR 2.99 P1M base-token", "GPA.3312-5551-0623-12345 coins 3 1 true", "params"];
		return said.join("; ") == want.join("; ") ? "ok" : 'wrong: ${said.join("; ")}';
	}
	#end
}
