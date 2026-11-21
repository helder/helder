#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
import helder.os.android.Jni;
import helder.os.android.MainThread;
import helder.os.android.Native.JniFast;
import hxmc.NativeThread;
import hxmc.unsafe.*;
#end

// Google Play Billing through helder's Maven libraries (tests/pack/billing.sh,
// CI's emulator): the library and its tree fetched, shrunk to this keep
// list (the API an app calls) and translated by helder.pack.android
// (Libraries, Jvm); here a BillingClient built (PendingPurchasesParams,
// a PurchasesUpdatedListener), startConnection with a
// BillingClientStateListener, its callback's response code printed. Both
// listeners are java.lang.reflect.Proxy instances of Glue's org.hxmc.Handler,
// called on billing's own thread (PlayBillingLibrary), a Haxe thread once
// attached.
// An emulator without the Play Store answers BILLING_UNAVAILABLE (3) or
// SERVICE_UNAVAILABLE (-1)/disconnected; one with it, OK (0) or an error.
@:helder.android.maven("com.android.billingclient:billing", "
	-keep public class com.android.billingclient.api.BillingClient { public *; }
	-keep public class com.android.billingclient.api.BillingClient$Builder { public *; }
	-keep public class com.android.billingclient.api.BillingClient$ProductType { public *; }
	-keep public class com.android.billingclient.api.BillingClient$BillingResponseCode { public *; }
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
	-keep public class com.android.billingclient.api.Purchase$* { public *; }
	-keep public class com.android.billingclient.api.AcknowledgePurchaseParams { public *; }
	-keep public class com.android.billingclient.api.AcknowledgePurchaseParams$* { public *; }
	-keep public class com.android.billingclient.api.ConsumeParams { public *; }
	-keep public class com.android.billingclient.api.ConsumeParams$* { public *; }
")
@:helder.android.dex("Handler")
@:hxmc.unsafe(gc)
class BillingCheck {
	static var done = false;

	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.link();
		Sys.println("billing: started");
		MainThread.post(start);
		var t0 = haxe.Timer.stamp();
		while (!done && haxe.Timer.stamp() - t0 < 60)
			MainThread.wait(0.5);
		Sys.println(done ? "billing: done" : "billing: no callback in 60 s");
		#else
		Sys.println("billing: Android only");
		#end
	}

	#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	static inline var API = "com/android/billingclient/api/";

	static function start() {
		var handler = Jni.cls("org.hxmc.Handler");
		Jni.registerNatives(handler, [{name: "call", sig: "(ILjava/lang/String;[Ljava/lang/Object;)Ljava/lang/Object;", fn: Callback.addr(callEntry)}]);
		var bc = Jni.cls("com.android.billingclient.api.BillingClient"), bb = Jni.cls("com.android.billingclient.api.BillingClient$Builder");
		var builderSig = 'L${API}BillingClient$$Builder;';
		var builder = Jni.staticObj(bc, Jni.staticMethod(bc, "newBuilder", '(Landroid/content/Context;)$builderSig'), Jni.activity.toI64());
		Jni.obj(builder, Jni.method(bb, "setListener", '(L${API}PurchasesUpdatedListener;)$builderSig'), proxy("com.android.billingclient.api.PurchasesUpdatedListener", 1).toI64());
		var pp = Jni.cls("com.android.billingclient.api.PendingPurchasesParams"), ppb = Jni.cls("com.android.billingclient.api.PendingPurchasesParams$Builder");
		var ppSig = 'L${API}PendingPurchasesParams$$Builder;';
		var p = Jni.staticObj(pp, Jni.staticMethod(pp, "newBuilder", '()$ppSig'));
		Jni.obj(p, Jni.method(ppb, "enableOneTimeProducts", '()$ppSig'));
		var params = Jni.obj(p, Jni.method(ppb, "build", '()L${API}PendingPurchasesParams;'));
		Jni.obj(builder, Jni.method(bb, "enablePendingPurchases", '(L${API}PendingPurchasesParams;)$builderSig'), params.toI64());
		var client = Jni.global(Jni.obj(builder, Jni.method(bb, "build", '()L${API}BillingClient;')));
		Sys.println("billing: client built, ready " + Jni.bool(client, Jni.method(bc, "isReady", "()Z")));
		Jni.call(client, Jni.method(bc, "startConnection", '(L${API}BillingClientStateListener;)V'), proxy("com.android.billingclient.api.BillingClientStateListener", 2).toI64());
		Sys.println("billing: startConnection called");
	}

	// a Proxy of the interface, its calls to org.hxmc.Handler(id)
	static function proxy(iface:String, id:Int):Ptr {
		var i = Jni.cls(iface), classes = Jni.cls("java.lang.Class"), handler = Jni.cls("org.hxmc.Handler");
		var h = Jni.newObject(handler, Jni.method(handler, "<init>", "(I)V"), id);
		var loader = Jni.obj(i, Jni.method(classes, "getClassLoader", "()Ljava/lang/ClassLoader;"));
		var list = JniEnv.NewObjectArray(Jni.env, 1, classes, i);
		var proxies = Jni.cls("java.lang.reflect.Proxy");
		return Jni.global(Jni.staticObj(proxies,
			Jni.staticMethod(proxies, "newProxyInstance", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;"),
			loader.toI64(), list.toI64(), h.toI64()));
	}

	@:hxmc.callback @:hxmc.noGc static function callEntry(env:Ptr, c:Ptr, id:Int, name:Ptr, args:Ptr):Ptr {
		NativeThread.attach();
		return JniFast.call3(Callback.addr(call), env, Ptr.ofI64(id), name, args);
	}

	// (billing's thread: the call's name and arguments kept, then read on the
	// main thread, whose JNIEnv Jni's helpers use; its listeners return nothing)
	@:hxmc.callback static function call(env:Ptr, idp:Ptr, name:Ptr, args:Ptr):Ptr {
		var id = idp.toI64().toInt();
		var n = JniEnv.NewGlobalRef(env, name), a = args.isNull() ? Ptr.nil() : JniEnv.NewGlobalRef(env, args);
		MainThread.post(() -> listener(id, Jni.fromString(n), a));
		return Ptr.nil();
	}

	static function listener(id:Int, name:String, args:Ptr) {
		switch name {
			case "onBillingSetupFinished":
				var r = JniEnv.GetObjectArrayElement(Jni.env, args, 0), br = Jni.cls("com.android.billingclient.api.BillingResult");
				var code = Jni.int(r, Jni.method(br, "getResponseCode", "()I"));
				var message = Jni.fromString(Jni.obj(r, Jni.method(br, "getDebugMessage", "()Ljava/lang/String;")));
				Sys.println('billing: onBillingSetupFinished $code ($message)');
				done = true;
				MainThread.wake();
			case "onBillingServiceDisconnected":
				Sys.println("billing: onBillingServiceDisconnected");
				done = true;
				MainThread.wake();
			case _:
				Sys.println('billing: listener $id: $name');
		}
	}
	#end
}
