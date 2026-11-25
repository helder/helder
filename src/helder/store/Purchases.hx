package helder.store;

// (Play has no consumable kind: a one-time product is a nonConsumable, and
// consume or finish decides)
enum abstract ProductKind(String) to String {
	var Consumable = "consumable";
	var NonConsumable = "nonConsumable";
	var Subscription = "subscription";
	var NonRenewing = "nonRenewing";
}

// price: the store's own text ("€4,99"); amount: its number; currency: its
// ISO 4217 code; period: a subscription's, ISO 8601 ("P1M")
typedef Product = {
	id:String,
	kind:ProductKind,
	title:String,
	description:String,
	price:String,
	amount:Float,
	currency:String,
	?period:String
}

// A purchase the store has made: StoreKit's transaction, Play's purchase.
// Times in ms since 1970 (expires, revoked: StoreKit's; Play gives neither
// on the device); verified: the store's signature checked on the device
// (StoreKit's JWS; Play's against the app's license key, false without
// one); signed: what a server verifies (the JWS; Play's purchase token)
typedef Purchase = {
	id:String,
	product:String,
	date:Float,
	quantity:Int,
	?expires:Float,
	?revoked:Float,
	verified:Bool,
	signed:String
}

enum abstract PurchaseState(String) to String {
	var Purchased = "purchased";
	var Pending = "pending";
	var Cancelled = "cancelled";
}

// pending: waiting on someone else (Ask to Buy, a bank), onPurchase gets it later
@:typescript.type('{state: "purchased"; purchase: Purchase} | {state: "pending"} | {state: "cancelled"}')
typedef PurchaseResult = {state:PurchaseState, ?purchase:Purchase}

// In-app purchases: the products the store sells the app, buying one, the
// purchases the user owns. StoreKit 2 on iOS 15 and macOS 12 and later (a
// framework of helder's, put into the app bundle when the program uses
// this class), Google Play Billing on Android (its library put into the
// APK the same way); elsewhere none is available and each call fails. Deliver
// what was bought, then finish it (consume a consumable): an unfinished
// purchase is given again, to onPurchase, at the next launch.
//
//   for (p in Purchases.owned()) unlock(p.product);
//   var r = Purchases.purchase("pro");
//   if (r.state == Purchased) { unlock("pro"); Purchases.finish(r.purchase); }
@:helder.apple.framework("HelderStore")
class Purchases {
	// purchases made outside purchase(): renewals, Ask to Buy, other
	// devices, refunds, one left unfinished; those that came before it was
	// set given when it is. Set it as the app starts: the store is listened
	// to from the first use of this class, and Apple asks for the launch
	@:typescript public static var onPurchase(default, set):Null<Purchase->Void> = null;

	static final early:Array<Purchase> = [];

	// whether this device can buy: on Android, Play's billing service is
	// there and has not answered BILLING_UNAVAILABLE (whether the account can
	// pay is known only once connected: true at first, false after)
	@:typescript public static function available():Bool {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return helder.store.apple.ApplePurchases.load();
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.store.android.AndroidPurchases.available();
		#else
		return false;
		#end
	}

	@:typescript @:coroutine public static function products(ids:Array<String>):Array<Product> {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return [for (p in helder.store.apple.ApplePurchases.products(ids.join("\n"))) product(p)];
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.store.android.AndroidPurchases.products(ids);
		#else
		throw none();
		#end
	}

	// account: who buys, a UUID of the app's (StoreKit's appAccountToken, Play's obfuscatedAccountId)
	@:typescript @:coroutine public static function purchase(id:String, ?options:{?account:String}):PurchaseResult {
		var account = options?.account ?? "";
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		var r = helder.store.apple.ApplePurchases.purchase(id, account);
		return r.code == 2 ? {state: Pending} : r.code == 3 ? {state: Cancelled} : {state: Purchased, purchase: of(haxe.Json.parse(r.text))};
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.store.android.AndroidPurchases.purchase(id, account);
		#else
		throw none();
		#end
	}

	// what the user owns now: non-consumables, active subscriptions
	@:typescript @:coroutine public static function owned():Array<Purchase> {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return [for (p in helder.store.apple.ApplePurchases.owned()) of(p)];
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.store.android.AndroidPurchases.owned();
		#else
		throw none();
		#end
	}

	// after delivering it (Play: acknowledged; Play refunds one left for 3 days)
	@:typescript @:coroutine public static function finish(p:Purchase):Void {
		var id = p.id;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		helder.store.apple.ApplePurchases.finish(id);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.store.android.AndroidPurchases.finish(p);
		#else
		throw none();
		#end
	}

	// a consumable's, after delivering it: it can be bought again (StoreKit: finished; Play: consumed)
	@:typescript @:coroutine public static function consume(p:Purchase):Void {
		var id = p.id;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		helder.store.apple.ApplePurchases.finish(id);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.store.android.AndroidPurchases.consume(p);
		#else
		throw none();
		#end
	}

	// the user's purchases fetched again from the store (StoreKit asks them
	// to sign in; Play's unfinished ones go to onPurchase): a Restore
	// button's; owned() after it
	@:typescript @:coroutine public static function restore():Void {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		helder.store.apple.ApplePurchases.sync();
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.store.android.AndroidPurchases.restore();
		#else
		throw none();
		#end
	}

	static function set_onPurchase(f:Null<Purchase->Void>) {
		onPurchase = f;
		available();
		if (f != null && early.length > 0) {
			var all = early.copy();
			early.resize(0);
			for (p in all) f(p);
		}
		return f;
	}

	@:allow(helder.store) static function update(p:Purchase) {
		var f = onPurchase;
		if (f == null) {
			early.push(p);
			return;
		}
		helder.async.Errors.guard(() -> {
			f(p);
			helder.view.graph.Graph.flush();
		}, "event");
	}

	static function none():String
		return "purchases: not available here";

	@:allow(helder.store) static function product(p:Dynamic):Product {
		var o:Product = {
			id: p.id,
			kind: p.kind,
			title: p.title,
			description: p.description,
			price: p.price,
			amount: p.amount,
			currency: p.currency
		};
		if (p.period != null) o.period = p.period;
		return o;
	}

	@:allow(helder.store) static function of(p:Dynamic):Purchase {
		var o:Purchase = {
			id: p.id,
			product: p.product,
			date: p.date,
			quantity: p.quantity,
			verified: p.verified,
			signed: p.signed
		};
		if (p.expires != null) o.expires = p.expires;
		if (p.revoked != null) o.revoked = p.revoked;
		return o;
	}
}
