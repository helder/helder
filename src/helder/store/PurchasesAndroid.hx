package helder.store;

import haxe.io.Bytes;
import helder.store.Purchases;
#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import helder.os.android.Jni;
import helder.os.android.MainThread;
import helder.os.android.Native.JniFast;
import hxmc.NativeThread;
import hxmc.unsafe.*;
#end

// (amount: the price's number, from Play's micros)
typedef PlayPrice = {price:String, amount:Float, currency:String, ?period:String}
typedef PlayOffer = {?id:String, token:String, phases:Array<PlayPrice>}
typedef PlayProduct = {id:String, type:String, name:String, description:String, ?once:PlayPrice, offers:Array<PlayOffer>}

// Google Play Billing (9.x) on Android, through helder's Maven libraries
// (helder.pack.android: put in by use, shrunk to the keep list below). One
// BillingClient for the app, made at the first use of Purchases, with
// pending purchases and the library's own reconnection; its listeners are
// java.lang.reflect.Proxy instances of Glue's org.hxmc.Handler, called on
// billing's thread (PlayBillingLibrary, attached), read on the activity's
// main thread (Jni's), answered on the caller's loop. Play has no consumable
// kind of its own: a one-time product is a nonConsumable, and the app's
// consume (consumeAsync) or finish (acknowledgePurchase) decides. A purchase
// is verified against the app's license key (Play Console's base64 RSA key:
// -D helder.play.license-key, or package.json's "helder": {"android":
// {"licenseKey"}}), never otherwise; a server checks its token with Play's
// Developer API either way.
#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
@:helder.android.maven("com.android.billingclient:billing", "
	-keep public class com.android.billingclient.api.BillingClient { public *; }
	-keep public class com.android.billingclient.api.BillingClient$Builder { public *; }
	-keep public interface com.android.billingclient.api.BillingClientStateListener { *; }
	-keep public interface com.android.billingclient.api.PurchasesUpdatedListener { *; }
	-keep public interface com.android.billingclient.api.ProductDetailsResponseListener { *; }
	-keep public interface com.android.billingclient.api.PurchasesResponseListener { *; }
	-keep public interface com.android.billingclient.api.AcknowledgePurchaseResponseListener { *; }
	-keep public interface com.android.billingclient.api.ConsumeResponseListener { *; }
	-keep public class com.android.billingclient.api.BillingResult { public *; }
	-keep public class com.android.billingclient.api.ProductDetails { public *; }
	-keep public class com.android.billingclient.api.ProductDetails$* { public *; }
	-keep public class com.android.billingclient.api.QueryProductDetailsResult { public *; }
	-keep public class com.android.billingclient.api.QueryProductDetailsParams { public *; }
	-keep public class com.android.billingclient.api.QueryProductDetailsParams$* { public *; }
	-keep public class com.android.billingclient.api.QueryPurchasesParams { public *; }
	-keep public class com.android.billingclient.api.QueryPurchasesParams$* { public *; }
	-keep public class com.android.billingclient.api.BillingFlowParams { public *; }
	-keep public class com.android.billingclient.api.BillingFlowParams$* { public *; }
	-keep public class com.android.billingclient.api.PendingPurchasesParams { public *; }
	-keep public class com.android.billingclient.api.PendingPurchasesParams$* { public *; }
	-keep public class com.android.billingclient.api.Purchase { public *; }
	-keep public class com.android.billingclient.api.AcknowledgePurchaseParams { public *; }
	-keep public class com.android.billingclient.api.AcknowledgePurchaseParams$* { public *; }
	-keep public class com.android.billingclient.api.ConsumeParams { public *; }
	-keep public class com.android.billingclient.api.ConsumeParams$* { public *; }
")
@:helder.android.dex("Handler")
@:hxmc.unsafe(gc)
#end
class PurchasesAndroid {
	// (DER of SHA-1's DigestInfo, before the digest: Play signs with SHA1withRSA)
	static final SHA1_INFO = Bytes.ofHex("3021300906052b0e03021a05000414");

	// Play's product as helder's, with the offer purchase() buys: a
	// subscription's base plan (no offer id), else its first offer (Play
	// lists those the user can take), priced by its last phase, the one
	// that recurs; null: none to sell
	public static function product(d:PlayProduct):Null<{product:Product, offer:Null<String>}> {
		var subs = d.type == "subs";
		var offer = subs ? (Lambda.find(d.offers, o -> o.id == null) ?? (d.offers.length > 0 ? d.offers[0] : null)) : null;
		var p = !subs ? d.once : offer != null && offer.phases.length > 0 ? offer.phases[offer.phases.length - 1] : null;
		if (p == null) return null;
		var o:Product = {
			id: d.id,
			kind: subs ? Subscription : NonConsumable,
			title: d.name,
			description: d.description,
			price: p.price,
			amount: p.amount,
			currency: p.currency
		};
		if (subs && p.period != null) o.period = p.period;
		return {product: o, offer: offer?.token};
	}

	// a purchase's JSON (Purchase.getOriginalJson) as helder's: its order id,
	// or the token when it has none; its first product (one per purchase
	// with Play's flow; quantity is the count bought); verified when key (the
	// license key) is given and the signature is Play's of it
	public static function of(json:String, signature:String, key:Null<String>):Purchase {
		var j:Dynamic = haxe.Json.parse(json);
		var token:String = j.purchaseToken ?? "", order:Null<String> = j.orderId;
		var ids:Null<Array<String>> = j.productIds, single:Null<String> = j.productId;
		var time:Null<Float> = j.purchaseTime, quantity:Null<Int> = j.quantity;
		return {
			id: order != null && order != "" ? order : token,
			product: ids != null && ids.length > 0 ? ids[0] : single ?? "",
			date: time ?? 0,
			quantity: quantity ?? 1,
			verified: key != null && key != "" && verify(key, json, signature),
			signed: token
		};
	}

	// data's SHA1withRSA signature (base64) checked against key, a base64
	// X.509 SubjectPublicKeyInfo
	public static function verify(key:String, data:String, signature:String):Bool
		return try {
			var der = haxe.crypto.Base64.decode(~/\s/g.replace(key, ""));
			var info = helder.pack.android.Der.children(der, helder.pack.android.Der.read(der, 0));
			var nums = helder.pack.android.Der.children(der, helder.pack.android.Der.read(der, info[1].start + 1));
			function bytes(i:Int)
				return der.sub(nums[i].start, nums[i].end - nums[i].start);
			var m = helder.pack.apple.Rsa.power(bytes(0), bytes(1), haxe.crypto.Base64.decode(~/\s/g.replace(signature, "")));
			m != null && m.compare(helder.pack.apple.Rsa.padding(SHA1_INFO, haxe.crypto.Sha1.make(Bytes.ofString(data)), m.length)) == 0;
		} catch (_:Dynamic) false;

	// BillingResponseCode's name
	public static function code(c:Int):String
		return switch c {
			case -3: "SERVICE_TIMEOUT";
			case -2: "FEATURE_NOT_SUPPORTED";
			case -1: "SERVICE_DISCONNECTED";
			case 0: "OK";
			case 1: "USER_CANCELED";
			case 2: "SERVICE_UNAVAILABLE";
			case 3: "BILLING_UNAVAILABLE";
			case 4: "ITEM_UNAVAILABLE";
			case 5: "DEVELOPER_ERROR";
			case 6: "ERROR";
			case 7: "ITEM_ALREADY_OWNED";
			case 8: "ITEM_NOT_OWNED";
			case 12: "NETWORK_ERROR";
			case _: 'response $c';
		}

	#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	static inline var API = "com/android/billingclient/api/";
	static inline var UPDATES = 0;
	static inline var STATE = 1;
	static final KEY:Null<String> = haxe.macro.Compiler.getDefine("helder.play.license-key");

	// (the main thread's, but loop: the program's, where onPurchase is called)
	static var loop:Null<helder.async.Loop> = null;
	static var client = Ptr.nil();
	static var state = Ptr.nil();
	static var ready = false;
	static var unavailable:Null<String> = null;
	static var service:Null<Bool> = null;
	static final waiting:Array<Null<String>->Void> = [];
	static final listeners = new Map<Int, (String, Ptr) -> Void>();
	static var next = 2;
	// (the purchase() waiting for onPurchasesUpdated: its result code and purchases)
	static var buying:Null<(Ptr, Array<Bought>) -> Void> = null;
	static final cache = new Map<String, {details:Ptr, offer:Null<String>, type:String}>();
	static final acknowledged = new Map<String, Bool>();

	// Play's billing service on the device (the Play Store), and no
	// BILLING_UNAVAILABLE from it yet: whether the account can pay is known
	// only once connected
	public static function available():Bool {
		start();
		var ok = false;
		MainThread.run(() -> ok = unavailable == null && (try resolves() catch (_:Dynamic) false));
		return ok;
	}

	@:coroutine public static function products(ids:Array<String>):Array<Product>
		return ask(answer -> query(ids, "inapp", answer, a -> query(ids, "subs", answer, b -> {
			var all = a.concat(b);
			answer({value: [for (id in ids) for (p in all) if (p.id == id) p]});
		})));

	@:coroutine public static function purchase(id:String, account:String):PurchaseResult
		return ask(answer -> find(id, answer, d -> {
			if (buying != null) return answer({error: "purchases: a purchase is in progress"});
			function done(r:Ptr, bought:Array<Bought>) {
				var c = result(r);
				if (c == 1) return answer({value: {state: Cancelled}});
				// (r a local reference: gone once this call returns)
				var error = c == 0 ? null : failure(r);
				if (c == 7) return purchases(d.type, answer, all -> {
					var p = Lambda.find(all, b -> b.purchase.product == id && b.state == 1);
					answer(p == null ? {error: error} : {value: {state: Purchased, purchase: p.purchase}});
				});
				if (c != 0) return answer({error: error});
				var p = Lambda.find(bought, b -> b.purchase.product == id) ?? (bought.length > 0 ? bought[0] : null);
				for (b in bought)
					if (b != p && b.state == 1) deliver(b.purchase);
				answer(p == null ? {error: "purchases: no purchase came"} : p.state == 1 ? {value: {state: Purchased, purchase: p.purchase}} : {value: {state: Pending}});
			}
			var r = Jni.obj(client, method("BillingClient", "launchBillingFlow", '(Landroid/app/Activity;L${API}BillingFlowParams;)L${API}BillingResult;'), Jni.activity.toI64(),
				flow(d.details, d.offer, account).toI64());
			if (result(r) != 0) done(r, []) else buying = done;
		}));

	static function flow(details:Ptr, offer:Null<String>, account:String):Ptr {
		var c = "BillingFlowParams$ProductDetailsParams";
		var pp = newBuilder(c);
		with(pp, c, "setProductDetails", 'L${API}ProductDetails;', details);
		if (offer != null) with(pp, c, "setOfferToken", "Ljava/lang/String;", Jni.string(offer));
		var fb = newBuilder("BillingFlowParams");
		with(fb, "BillingFlowParams", "setProductDetailsParamsList", "Ljava/util/List;", list([build(pp, c)]));
		if (account != "") with(fb, "BillingFlowParams", "setObfuscatedAccountId", "Ljava/lang/String;", Jni.string(account));
		return build(fb, "BillingFlowParams");
	}

	@:coroutine public static function owned():Array<Purchase>
		return ask(answer -> all(answer, bought -> answer({value: [for (b in bought) if (b.state == 1) b.purchase]})));

	@:coroutine public static function finish(p:Purchase)
		ask(answer -> {
			if (acknowledged.get(p.signed) == true) return answer({});
			var b = newBuilder("AcknowledgePurchaseParams");
			with(b, "AcknowledgePurchaseParams", "setPurchaseToken", "Ljava/lang/String;", Jni.string(p.signed));
			Jni.call(client, method("BillingClient", "acknowledgePurchase", '(L${API}AcknowledgePurchaseParams;L${API}AcknowledgePurchaseResponseListener;)V'),
				build(b, "AcknowledgePurchaseParams").toI64(), once("AcknowledgePurchaseResponseListener", answer, args -> {
					var r = arg(args, 0);
					if (result(r) != 0) return answer({error: failure(r)});
					acknowledged.set(p.signed, true);
					answer({});
				}).toI64());
		});

	@:coroutine public static function consume(p:Purchase)
		ask(answer -> {
			var b = newBuilder("ConsumeParams");
			with(b, "ConsumeParams", "setPurchaseToken", "Ljava/lang/String;", Jni.string(p.signed));
			Jni.call(client, method("BillingClient", "consumeAsync", '(L${API}ConsumeParams;L${API}ConsumeResponseListener;)V'), build(b, "ConsumeParams").toI64(),
				once("ConsumeResponseListener", answer, args -> {
					var r = arg(args, 0);
					answer(result(r) == 0 ? {} : {error: failure(r)});
				}).toI64());
		});

	// (Play's closest to AppStore.sync: the purchases asked for again, those
	// not yet acknowledged given to onPurchase)
	@:coroutine public static function restore()
		ask(answer -> unfinished(answer, () -> answer({})));

	// (the first use: the client made and connected, the purchases left
	// unfinished given to onPurchase, as StoreKit's updates give them)
	static function start() {
		if (loop != null) return;
		loop = helder.async.Loop.current();
		MainThread.post(() -> {
			function ignore(r:Answer)
				if (r.error != null) Sys.println('helder.store: ${r.error}');
			connect(e -> if (e == null) unfinished(ignore, () -> {}));
		});
	}

	static function unfinished(answer:Answer->Void, then:() -> Void)
		all(answer, bought -> {
			for (b in bought)
				if (b.state == 1 && acknowledged.get(b.purchase.signed) != true) deliver(b.purchase);
			then();
		});

	static function deliver(p:Purchase)
		loop.post(() -> Purchases.update(p));

	// (the main thread: f once connected, its answer on the caller's loop;
	// a Java exception, or a Haxe one, its error)
	@:coroutine static function ask(f:(Answer->Void)->Void):Dynamic {
		start();
		var r:Answer = @:privateAccess helder.os.Await.answer(done -> MainThread.post(() -> {
			var answered = false;
			function answer(r:Answer)
				if (!answered) {
					answered = true;
					done(r);
				}
			try connect(e -> if (e != null) answer({error: e}) else try f(answer) catch (x:Dynamic) answer({error: Std.string(x)})) catch (e:Dynamic) answer({error: Std.string(e)});
		}));
		if (r.error != null) throw r.error;
		return r.value;
	}

	static function connect(then:Null<String>->Void) {
		if (unavailable != null) return then(unavailable);
		if (ready && Jni.bool(client, method("BillingClient", "isReady", "()Z"))) return then(null);
		waiting.push(then);
		if (waiting.length > 1) return;
		try {
			if (client.isNull()) make();
			Jni.call(client, method("BillingClient", "startConnection", '(L${API}BillingClientStateListener;)V'), state.toI64());
		} catch (e:Dynamic) settle('purchases: $e');
	}

	static function settle(error:Null<String>) {
		var all = waiting.copy();
		waiting.resize(0);
		for (f in all)
			f(error);
	}

	static function make() {
		var handler = Jni.cls("org.hxmc.Handler");
		Jni.registerNatives(handler, [
			{name: "call", sig: "(ILjava/lang/String;[Ljava/lang/Object;)Ljava/lang/Object;", fn: Callback.addr(callEntry)}
		]);
		listeners.set(STATE, (name, args) -> switch name {
			case "onBillingSetupFinished":
				var r = arg(args, 0), c = result(r);
				ready = c == 0;
				var error = c == 0 ? null : failure(r);
				if (c == 3) unavailable = error;
				settle(error);
			case _:
				ready = false;
				settle("purchases: SERVICE_DISCONNECTED");
		});
		listeners.set(UPDATES, (_, args) -> {
			var r = arg(args, 0), bought = [for (p in items(arg(args, 1))) read(p)];
			var f = buying;
			buying = null;
			if (f != null) return f(r, bought);
			if (result(r) == 0) for (b in bought)
				if (b.state == 1) deliver(b.purchase);
		});
		var bc = cls("BillingClient"), b = 'L${API}BillingClient$$Builder;';
		var builder = Jni.staticObj(bc, Jni.staticMethod(bc, "newBuilder", '(Landroid/content/Context;)$b'), Jni.activity.toI64());
		with(builder, "BillingClient", "setListener", 'L${API}PurchasesUpdatedListener;', proxy("PurchasesUpdatedListener", UPDATES));
		var pending = newBuilder("PendingPurchasesParams");
		Jni.obj(pending, method("PendingPurchasesParams$Builder", "enableOneTimeProducts", '()L${API}PendingPurchasesParams$$Builder;'));
		with(builder, "BillingClient", "enablePendingPurchases", 'L${API}PendingPurchasesParams;', build(pending, "PendingPurchasesParams"));
		Jni.obj(builder, method("BillingClient$Builder", "enableAutoServiceReconnection", '()$b'));
		client = Jni.global(build(builder, "BillingClient"));
		state = proxy("BillingClientStateListener", STATE);
	}

	// (the Play Store's billing service, as BillingClient binds it: the
	// library's manifest asks to see it)
	static function resolves():Bool {
		if (service != null) return service;
		var intent = Jni.cls("android.content.Intent");
		var i = Jni.newObject(intent, Jni.method(intent, "<init>", "(Ljava/lang/String;)V"), Jni.string("com.android.vending.billing.InAppBillingService.BIND").toI64());
		Jni.obj(i, Jni.method(intent, "setPackage", "(Ljava/lang/String;)Landroid/content/Intent;"), Jni.string("com.android.vending").toI64());
		var pm = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageManager", "()Landroid/content/pm/PackageManager;"));
		var found = Jni.obj(pm, Jni.method(Jni.cls("android.content.pm.PackageManager"), "queryIntentServices", "(Landroid/content/Intent;I)Ljava/util/List;"), i.toI64(), 0);
		return service = items(found).length > 0;
	}

	// (the product's details: remembered, else asked of both types)
	static function find(id:String, answer:Answer->Void, then:{details:Ptr, offer:Null<String>, type:String}->Void) {
		var d = cache.get(id);
		if (d != null) return then(d);
		query([id], "inapp", answer, _ -> query([id], "subs", answer, _ -> {
			var d = cache.get(id);
			d == null ? answer({error: 'purchases: no product $id'}) : then(d);
		}));
	}

	static function query(ids:Array<String>, type:String, answer:Answer->Void, then:Array<Product>->Void) {
		if (ids.length == 0) return then([]);
		Jni.call(client, method("BillingClient", "queryProductDetailsAsync", '(L${API}QueryProductDetailsParams;L${API}ProductDetailsResponseListener;)V'),
			params(ids, type).toI64(), once("ProductDetailsResponseListener", answer, args -> {
				var r = arg(args, 0);
				if (result(r) != 0) return answer({error: failure(r)});
				var found = Jni.obj(arg(args, 1), method("QueryProductDetailsResult", "getProductDetailsList", "()Ljava/util/List;"));
				var out = [];
				for (d in items(found)) {
					var p = product(details(d));
					if (p == null) continue;
					var old = cache.get(p.product.id);
					if (old != null) Jni.deleteGlobal(old.details);
					cache.set(p.product.id, {details: Jni.global(d), offer: p.offer, type: type});
					out.push(p.product);
				}
				then(out);
			}).toI64());
	}

	static function params(ids:Array<String>, type:String):Ptr {
		var c = "QueryProductDetailsParams$Product";
		var products = list([for (id in ids) {
			var b = newBuilder(c);
			with(b, c, "setProductId", "Ljava/lang/String;", Jni.string(id));
			with(b, c, "setProductType", "Ljava/lang/String;", Jni.string(type));
			build(b, c);
		}]);
		var q = newBuilder("QueryProductDetailsParams");
		with(q, "QueryProductDetailsParams", "setProductList", "Ljava/util/List;", products);
		return build(q, "QueryProductDetailsParams");
	}

	static function all(answer:Answer->Void, then:Array<Bought>->Void)
		purchases("inapp", answer, a -> purchases("subs", answer, b -> then(a.concat(b))));

	static function purchases(type:String, answer:Answer->Void, then:Array<Bought>->Void) {
		Jni.call(client, method("BillingClient", "queryPurchasesAsync", '(L${API}QueryPurchasesParams;L${API}PurchasesResponseListener;)V'), ofType(type).toI64(), once("PurchasesResponseListener", answer, args -> {
				var r = arg(args, 0);
				if (result(r) != 0) return answer({error: failure(r)});
				then([for (p in items(arg(args, 1))) read(p)]);
			}).toI64());
	}

	static function ofType(type:String):Ptr {
		var q = newBuilder("QueryPurchasesParams");
		with(q, "QueryPurchasesParams", "setProductType", "Ljava/lang/String;", Jni.string(type));
		return build(q, "QueryPurchasesParams");
	}

	// (a Purchase: its state, 1 purchased and 2 pending, Purchase.PurchaseState's)
	static function read(p:Ptr):Bought {
		var c = "Purchase";
		var purchase = of(text(p, c, "getOriginalJson") ?? "{}", text(p, c, "getSignature") ?? "", KEY);
		if (Jni.bool(p, method(c, "isAcknowledged", "()Z"))) acknowledged.set(purchase.signed, true);
		return {purchase: purchase, state: Jni.int(p, method(c, "getPurchaseState", "()I"))};
	}

	static function details(d:Ptr):PlayProduct {
		var c = "ProductDetails";
		var once = Jni.obj(d, method(c, "getOneTimePurchaseOfferDetails", '()L${API}ProductDetails$$OneTimePurchaseOfferDetails;'));
		var offers = Jni.obj(d, method(c, "getSubscriptionOfferDetails", "()Ljava/util/List;"));
		var o:PlayProduct = {
			id: text(d, c, "getProductId") ?? "",
			type: text(d, c, "getProductType") ?? "",
			name: text(d, c, "getName") ?? "",
			description: text(d, c, "getDescription") ?? "",
			offers: [for (s in items(offers)) offer(s)]
		};
		if (!once.isNull()) o.once = price(once, "ProductDetails$OneTimePurchaseOfferDetails");
		return o;
	}

	static function offer(s:Ptr):PlayOffer {
		var c = "ProductDetails$SubscriptionOfferDetails";
		var phases = Jni.obj(s, method(c, "getPricingPhases", '()L${API}ProductDetails$$PricingPhases;'));
		var o:PlayOffer = {
			token: text(s, c, "getOfferToken") ?? "",
			phases: [
				for (p in items(Jni.obj(phases, method("ProductDetails$PricingPhases", "getPricingPhaseList", "()Ljava/util/List;"))))
					price(p, "ProductDetails$PricingPhase")
			]
		};
		var id = text(s, c, "getOfferId");
		if (id != null) o.id = id;
		return o;
	}

	static function price(p:Ptr, c:String):PlayPrice {
		var micros = Jni.long(p, method(c, "getPriceAmountMicros", "()J"));
		var o:PlayPrice = {
			price: text(p, c, "getFormattedPrice") ?? "",
			amount: haxe.Int64.toInt(micros / 1000000) + haxe.Int64.toInt(micros % 1000000) / 1e6,
			currency: text(p, c, "getPriceCurrencyCode") ?? ""
		};
		if (c == "ProductDetails$PricingPhase") o.period = text(p, c, "getBillingPeriod");
		return o;
	}

	static function result(r:Ptr):Int
		return Jni.int(r, method("BillingResult", "getResponseCode", "()I"));

	static function failure(r:Ptr):String {
		var c = result(r), message = text(r, "BillingResult", "getDebugMessage") ?? "";
		return 'purchases: ${code(c)}' + (message == "" ? "" : ' ($message)');
	}

	static function cls(name:String):Ptr
		return Jni.cls("com.android.billingclient.api." + name);

	static function method(c:String, name:String, sig:String):Ptr
		return Jni.method(cls(c), name, sig);

	static function text(o:Ptr, c:String, name:String):Null<String> {
		var s = Jni.obj(o, method(c, name, "()Ljava/lang/String;"));
		return s.isNull() ? null : Jni.fromString(s);
	}

	// (a builder of the library's: c.newBuilder(), a setter's call, build())
	static function newBuilder(c:String):Ptr
		return Jni.staticObj(cls(c), Jni.staticMethod(cls(c), "newBuilder", '()L$API$c$$Builder;'));

	static function with(b:Ptr, c:String, name:String, sig:String, v:Ptr)
		Jni.obj(b, method(c + "$Builder", name, '($sig)L$API$c$$Builder;'), v.toI64());

	static function build(b:Ptr, c:String):Ptr
		return Jni.obj(b, method(c + "$Builder", "build", '()L$API$c;'));

	static function items(l:Ptr):Array<Ptr> {
		if (l.isNull()) return [];
		var c = Jni.cls("java.util.List"), get = Jni.method(c, "get", "(I)Ljava/lang/Object;");
		return [for (i in 0...Jni.int(l, Jni.method(c, "size", "()I"))) Jni.obj(l, get, i)];
	}

	static function list(a:Array<Ptr>):Ptr {
		var c = Jni.cls("java.util.ArrayList");
		var l = Jni.newObject(c, Jni.method(c, "<init>", "()V")), add = Jni.method(c, "add", "(Ljava/lang/Object;)Z");
		for (o in a)
			Jni.bool(l, add, o.toI64());
		return l;
	}

	static function arg(args:Ptr, i:Int):Ptr
		return JniEnv.GetObjectArrayElement(Jni.env, args, i);

	// (a Proxy of the interface, its calls to listeners' id: a global reference)
	static function proxy(iface:String, id:Int):Ptr {
		var i = cls(iface), classes = Jni.cls("java.lang.Class"), handler = Jni.cls("org.hxmc.Handler");
		var h = Jni.newObject(handler, Jni.method(handler, "<init>", "(I)V"), id);
		var loader = Jni.obj(i, Jni.method(classes, "getClassLoader", "()Ljava/lang/ClassLoader;"));
		var types = JniEnv.NewObjectArray(Jni.env, 1, classes, i);
		var proxies = Jni.cls("java.lang.reflect.Proxy");
		return Jni.global(Jni.staticObj(proxies,
			Jni.staticMethod(proxies, "newProxyInstance", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;"),
			loader.toI64(), types.toI64(), h.toI64()));
	}

	// (a listener called once: its proxy let go after; what it throws, the answer's error)
	static function once(iface:String, answer:Answer->Void, f:Ptr->Void):Ptr {
		var id = next++, p = proxy(iface, id);
		listeners.set(id, (_, args) -> {
			listeners.remove(id);
			Jni.deleteGlobal(p);
			try f(args) catch (e:Dynamic) answer({error: Std.string(e)});
		});
		return p;
	}

	@:hxmc.callback @:hxmc.noGc static function callEntry(env:Ptr, c:Ptr, id:Int, name:Ptr, args:Ptr):Ptr {
		NativeThread.attach();
		return JniFast.call3(Callback.addr(call), env, Ptr.ofI64(id), name, args);
	}

	// (billing's thread: the call kept and read on the main thread, whose
	// JNIEnv Jni's helpers use; its listeners return nothing)
	@:hxmc.callback static function call(env:Ptr, idp:Ptr, name:Ptr, args:Ptr):Ptr {
		var id = idp.toI64().toInt();
		var n = JniEnv.NewGlobalRef(env, name), a = args.isNull() ? Ptr.nil() : JniEnv.NewGlobalRef(env, args);
		MainThread.post(() -> {
			var f = listeners.get(id), name = Jni.fromString(n);
			Jni.deleteGlobal(n);
			try {
				if (f != null) f(name, a);
			} catch (e:Dynamic) Sys.println('helder.store: $name: $e');
			if (!a.isNull()) Jni.deleteGlobal(a);
		});
		return Ptr.nil();
	}
	#end
}

#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
private typedef Answer = {?value:Dynamic, ?error:String}
private typedef Bought = {purchase:Purchase, state:Int}
#end
