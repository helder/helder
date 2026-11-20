package helder.os.android;

import helder.os.Location.GeoPosition;
import helder.os.Permissions.Permission;
import hxmc.unsafe.*;

// LocationManager's fixes, from the best provider enabled that the app may
// use (gps when precise and ACCESS_FINE_LOCATION is granted, else network):
// getCurrentLocation (API 30; its own timeout gives null), else the last
// known one if under a minute old, else requestSingleUpdate; a watch's by
// requestLocationUpdates (each second at most). Their answers come to
// org.hxmc.Locator's native on the main thread. Precise false asks for
// ACCESS_COARSE_LOCATION alone.
@:hxmc.android @:helder.android.dex("Locator") @:helder.android.permission("ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION")
@:hxmc.unsafe(gc)
class AndroidLocation {
	static final listeners = new Map<Int, {listener:Ptr, done:Null<GeoPosition>->Void, repeat:Bool}>();
	static var nextId = 1;
	static var cls = Ptr.nil();

	@:coroutine public static function current(precise:Bool):Null<GeoPosition> {
		if (!allowed(precise)) return null;
		return helder.os.Await.answer(done -> MainThread.post(() -> start(precise, false, done)));
	}

	// whether the app may, asked first while it was not yet
	@:coroutine public static function allowed(precise:Bool):Bool {
		var s = AndroidPermissions.status(Permission.Location);
		if (s != Prompt) return s == Granted;
		var coarse = "android.permission.ACCESS_COARSE_LOCATION";
		return AndroidPermissions.ask(precise ? ["android.permission.ACCESS_FINE_LOCATION", coarse] : [coarse]);
	}

	// (the main thread) a fix, or each one until stopped: the watch's id (0: none started)
	public static function start(precise:Bool, repeat:Bool, done:Null<GeoPosition>->Void):Int {
		try {
			if (Activity.activity.isNull()) throw "no activity";
			if (cls.isNull()) {
				cls = Jni.cls("org.hxmc.Locator");
				Jni.registerNatives(cls, [{name: "located", sig: "(ILjava/lang/Object;)V", fn: Callback.addr(located)}]);
			}
			var manager = Jni.service("location"), lm = Jni.cls("android.location.LocationManager");
			var provider = best(manager, lm, precise);
			if (provider == null) {
				done(null);
				return 0;
			}
			var id = nextId++, name = Jni.string(provider);
			var listener = Jni.global(Jni.newObject(cls, Jni.method(cls, "<init>", "(I)V"), id));
			listeners.set(id, {listener: listener, done: done, repeat: repeat});
			var looper = Jni.cls("android.os.Looper");
			var main = Jni.staticObj(looper, Jni.staticMethod(looper, "getMainLooper", "()Landroid/os/Looper;"));
			if (repeat)
				Jni.call5(manager, Jni.method(lm, "requestLocationUpdates", "(Ljava/lang/String;JFLandroid/location/LocationListener;Landroid/os/Looper;)V"),
					name.toI64(), 1000, Jni.f(0), listener.toI64(), main.toI64())
			else if (AndroidPermissions.sdk() >= 30) {
				var executor = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getMainExecutor", "()Ljava/util/concurrent/Executor;"));
				Jni.call(manager, Jni.method(lm, "getCurrentLocation", "(Ljava/lang/String;Landroid/os/CancellationSignal;Ljava/util/concurrent/Executor;Ljava/util/function/Consumer;)V"),
					name.toI64(), 0, executor.toI64(), listener.toI64());
			} else {
				var last = Jni.obj(manager, Jni.method(lm, "getLastKnownLocation", "(Ljava/lang/String;)Landroid/location/Location;"), name.toI64());
				var age = last.isNull() ? 1e9 : Date.now().getTime() - ms(Jni.long(last, Jni.method(Jni.cls("android.location.Location"), "getTime", "()J")));
				if (age < 60000) {
					listeners.remove(id);
					Jni.deleteGlobal(listener);
					done(position(last));
					return 0;
				}
				Jni.call(manager, Jni.method(lm, "requestSingleUpdate", "(Ljava/lang/String;Landroid/location/LocationListener;Landroid/os/Looper;)V"), name.toI64(),
					listener.toI64(), main.toI64());
			}
			return id;
		} catch (e:Dynamic) {
			Sys.println("helder.os: Location: " + Std.string(e));
			done(null);
			return 0;
		}
	}

	// (the main thread) a watch's updates ended
	public static function stop(id:Int) {
		var l = listeners.get(id);
		if (l == null) return;
		listeners.remove(id);
		try
			Jni.call(Jni.service("location"), Jni.method(Jni.cls("android.location.LocationManager"), "removeUpdates", "(Landroid/location/LocationListener;)V"),
				l.listener.toI64())
		catch (e:Dynamic) {}
		Jni.deleteGlobal(l.listener);
	}

	static function best(manager:Ptr, lm:Ptr, precise:Bool):Null<String> {
		var fine = Jni.string("android.permission.ACCESS_FINE_LOCATION");
		var granted = Jni.int(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "checkSelfPermission", "(Ljava/lang/String;)I"), fine.toI64()) == 0;
		var enabled = Jni.method(lm, "isProviderEnabled", "(Ljava/lang/String;)Z");
		var order = granted ? (precise ? ["gps", "network"] : ["network", "gps"]) : ["network"];
		for (p in order)
			if (Jni.bool(manager, enabled, Jni.string(p).toI64())) return p;
		return null;
	}

	@:hxmc.callback static function located(env:Ptr, c:Ptr, id:Int, location:Ptr):Void {
		var l = listeners.get(id);
		if (l == null) return;
		if (!l.repeat) {
			listeners.remove(id);
			Jni.deleteGlobal(l.listener);
		}
		var p = try location.isNull() ? null : position(location) catch (e:Dynamic) null;
		try l.done(p) catch (e:Dynamic) Sys.println("helder.os: Location: " + Std.string(e));
	}

	static function position(l:Ptr):GeoPosition {
		var c = Jni.cls("android.location.Location");
		inline function has(name:String):Bool
			return Jni.bool(l, Jni.method(c, name, "()Z"));
		inline function float(name:String):Float
			return Jni.float(l, Jni.method(c, name, "()F"));
		return {
			latitude: Jni.double(l, Jni.method(c, "getLatitude", "()D")),
			longitude: Jni.double(l, Jni.method(c, "getLongitude", "()D")),
			accuracy: has("hasAccuracy") ? float("getAccuracy") : 0,
			altitude: has("hasAltitude") ? Jni.double(l, Jni.method(c, "getAltitude", "()D")) : null,
			heading: has("hasBearing") ? float("getBearing") : null,
			speed: has("hasSpeed") ? float("getSpeed") : null,
			time: ms(Jni.long(l, Jni.method(c, "getTime", "()J")))
		};
	}

	static function ms(t:haxe.Int64):Float
		return haxe.Int64.toInt(t / 1000) * 1000.0 + haxe.Int64.toInt(t % 1000);
}
