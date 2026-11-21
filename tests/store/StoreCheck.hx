import helder.store.Purchases;

// helder.store in an app bundle with no StoreKit configuration (the store
// lane on a Mac, tests/pack/ios.sh on the simulator): the framework found
// and loaded, products of an id no store sells an empty list, owned()
// answered, each line printed; the last "store: ok".
class StoreCheck {
	static function main() {
		helder.async.Async.run(_ -> {
			Sys.println('store: available ${Purchases.available()}');
			try {
				Sys.println('store: products ${Purchases.products(["x"]).length}');
				Sys.println('store: owned ${Purchases.owned().length}');
				Sys.println("store: ok");
			} catch (e:Dynamic) Sys.println('store: failed $e');
		});
	}
}
