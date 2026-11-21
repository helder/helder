package helder.store;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import hxmc.Platform;
import hxmc.objc.Block;
import hxmc.unsafe.*;

typedef Reply = Block<(Int, Ptr) -> Void>;

// HelderStore (apple/StoreShim.swift: StoreKit 2 behind C functions),
// opened from the bundle's Frameworks when first asked (iOS:
// HelderStore.framework, macOS: HelderStore.dylib): there when the build
// put it in (helder.pack.apple.Frameworks), loadable on iOS 15 and macOS
// 12 and later. Its answers come on StoreKit's threads
// (hxmc's blocks attach them), resumed on the caller's loop (Await).
@:hxmc.unsafe(gc)
class PurchasesApple {
	static var loaded:Null<Bool> = null;

	public static function load():Bool {
		if (loaded != null) return loaded;
		loaded = Shim.load(path()) == null;
		if (loaded) listen();
		return loaded;
	}

	static function path():String
		return Platform.apple() == 1 || Platform.apple() == 2 ? "@executable_path/Frameworks/HelderStore.framework/HelderStore" : "@executable_path/../Frameworks/HelderStore.dylib";

	static function listen() {
		var loop = helder.async.Loop.current();
		var reply:Reply = (code, text) -> {
			if (code != 0) return;
			var p = Purchases.of(haxe.Json.parse((cast text : CString).toString()));
			loop.post(() -> Purchases.update(p));
		};
		Shim.hsk_updates(cast reply);
	}

	@:coroutine public static function products(ids:String):Array<Dynamic>
		return haxe.Json.parse(call(r -> Arena.scoped(a -> Shim.hsk_products(a.cstring(ids), cast r))).text);

	// (code 0 purchased, its JSON; 2 pending, 3 cancelled)
	@:coroutine public static function purchase(id:String, account:String):{code:Int, text:String}
		return call(r -> Arena.scoped(a -> Shim.hsk_purchase(a.cstring(id), a.cstring(account), cast r)));

	@:coroutine public static function owned():Array<Dynamic>
		return haxe.Json.parse(call(r -> Shim.hsk_owned(cast r)).text);

	@:coroutine public static function finish(id:String)
		call(r -> Arena.scoped(a -> Shim.hsk_finish(a.cstring(id), cast r)));

	@:coroutine public static function sync()
		call(r -> Shim.hsk_sync(cast r));

	// (code 1, an error's message: thrown)
	@:coroutine static function call(start:Reply->Void):{code:Int, text:String} {
		if (!load()) throw "purchases: not available here";
		var r:{code:Int, text:String} = @:privateAccess helder.os.Await.answer(done -> {
			var reply:Reply = (code, text) -> done({code: code, text: text.isNull() ? "" : (cast text : CString).toString()});
			start(reply);
		});
		if (r.code == 1) throw 'purchases: ${r.text}';
		return r;
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
private class Shim {
	static function hsk_products(ids:Ptr, reply:Ptr):Void;
	static function hsk_purchase(id:Ptr, account:Ptr, reply:Ptr):Void;
	static function hsk_owned(reply:Ptr):Void;
	static function hsk_updates(reply:Ptr):Void;
	static function hsk_finish(id:Ptr, reply:Ptr):Void;
	static function hsk_sync(reply:Ptr):Void;
}
#else
class PurchasesApple {}
#end
