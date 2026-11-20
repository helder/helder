package helder.os;

typedef GeoPosition = {
	var latitude:Float;
	var longitude:Float;
	// metres, the horizontal radius of confidence
	var accuracy:Float;
	// metres above sea level, degrees from north, metres a second: null where unknown
	var ?altitude:Float;
	var ?heading:Float;
	var ?speed:Float;
	// when it was measured: milliseconds since 1970
	var time:Float;
}

// Where the device is: one fix (current) or each new one until stopped
// (watch), while the app is in use. The permission is Permissions'
// Location, asked for by current and watch while it is Prompt; null (no
// fix) when it is denied or there is none. Precise false asks for
// coarse accuracy (Android's ACCESS_COARSE_LOCATION alone; a few
// kilometres on Apple's), which may answer sooner.
class Location {
	@:typescript @:helder.permission("location") @:coroutine public static function current(?options:{?precise:Bool}):Null<GeoPosition> {
		var precise = options?.precise ?? true;
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return null;
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebLocation.current(precise);
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return LocationApple.current(precise);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidLocation.current(precise);
		#else
		return null;
		#end
	}

	// f with each fix, on the app's loop, until the function returned is called
	@:typescript @:helder.permission("location") public static function watch(f:GeoPosition->Void, ?options:{?precise:Bool}):Void->Void {
		var precise = options?.precise ?? true;
		#if (!helder.headless && hxmc.target == "wasm32-wasi")
		var id = helder.os.web.WebLocation.watch(precise, f);
		return () -> helder.os.web.WebLocation.stop(id);
		#elseif (!helder.headless && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		var id = 0, stopped = false;
		helder.async.Async.launch(_ -> {
			if (LocationApple.bundled() && PermissionsApple.request(Permissions.Permission.Location) == Granted && !stopped)
				id = LocationApple.start(precise, f);
		});
		return () -> {
			stopped = true;
			if (id != 0) LocationApple.stop(id);
		};
		#elseif (!helder.headless && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
		var id = 0, stopped = false, loop = helder.async.Loop.current();
		helder.async.Async.launch(_ -> {
			if (helder.os.android.AndroidLocation.allowed(precise) && !stopped)
				helder.os.android.MainThread.run(() -> id = helder.os.android.AndroidLocation.start(precise, true, p -> if (p != null) loop.post(() -> if (!stopped) f(p))));
		});
		return () -> {
			stopped = true;
			var watch = id;
			if (watch != 0) helder.os.android.MainThread.post(() -> helder.os.android.AndroidLocation.stop(watch));
		};
		#else
		return () -> {};
		#end
	}
}
