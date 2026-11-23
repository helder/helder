package helder.os;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.Location.GeoPosition;
import helder.os.Permissions.Permission;
import helder.os.objc.*;
import hxmc.unsafe.*;

// CLLocationManager (CoreLocation, loaded when first asked), its delegate a
// class made at run time, on the main thread's run loop: requestLocation
// for one fix, startUpdatingLocation while a watch lasts. Precise false
// asks for three kilometres (kCLLocationAccuracyThreeKilometers), which
// the system answers from Wi-Fi and cells.
@:hxmc.unsafe(gc)
class LocationApple {
	static var manager = Ptr.nil();
	static var once:Array<Null<GeoPosition>->Void> = [];
	static final watches = new Map<Int, GeoPosition->Void>();
	static var nextId = 1;

	@:coroutine public static function current(precise:Bool):Null<GeoPosition> {
		if (!bundled() || PermissionsApple.request(Permission.Location) != Granted) return null;
		return Await.answer(done -> {
			once.push(done);
			Msg.v(located(precise), ObjC.sel("requestLocation"));
		});
	}

	// (macOS asks for an app bundle's only: a bare executable's request is never answered)
	public static function bundled():Bool
		return hxmc.Platform.apple() >= 1 || PathsApple.bundleId() != null;

	public static function start(precise:Bool, f:GeoPosition->Void):Int {
		return helder.os.OsThread.get(() -> {
			var id = nextId++;
			watches.set(id, f);
			Msg.v(located(precise), ObjC.sel("startUpdatingLocation"));
			return id;
		});
	}

	public static function stop(id:Int) {
		helder.os.OsThread.run(() -> {
			watches.remove(id);
			if (!watches.keys().hasNext() && !manager.isNull()) Msg.v(manager, ObjC.sel("stopUpdatingLocation"));
		});
	}

	static function located(precise:Bool):Ptr {
		if (manager.isNull()) {
			var cls = @:privateAccess PermissionsApple.load("CoreLocation", "CLLocationManager");
			var d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcLocator"), 0);
			Runtime.class_addMethod(d, ObjC.sel("locationManager:didUpdateLocations:"), Callback.addr(updated), Mem.cstr("v@:@@"));
			Runtime.class_addMethod(d, ObjC.sel("locationManager:didFailWithError:"), Callback.addr(failed), Mem.cstr("v@:@@"));
			Runtime.objc_registerClassPair(d);
			manager = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
			Msg.vPtr(manager, ObjC.sel("setDelegate:"), Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init")));
		}
		Msg.vFloat(manager, ObjC.sel("setDesiredAccuracy:"), precise ? -1 : 3000);
		return manager;
	}

	@:hxmc.callback static function updated(self:Ptr, cmd:Ptr, m:Ptr, locations:Ptr):Void {
		var l = Msg.id(locations, ObjC.sel("lastObject"));
		if (l.isNull()) return;
		var c = Msg.point(l, ObjC.sel("coordinate"));
		var vertical = Msg.f(l, ObjC.sel("verticalAccuracy")), course = Msg.f(l, ObjC.sel("course")), speed = Msg.f(l, ObjC.sel("speed"));
		var p:GeoPosition = {
			latitude: c.x,
			longitude: c.y,
			accuracy: Msg.f(l, ObjC.sel("horizontalAccuracy")),
			altitude: vertical > 0 ? Msg.f(l, ObjC.sel("altitude")) : null,
			heading: course >= 0 ? course : null,
			speed: speed >= 0 ? speed : null,
			time: Msg.f(Msg.id(l, ObjC.sel("timestamp")), ObjC.sel("timeIntervalSince1970")) * 1000
		};
		answer(p);
		for (f in [for (f in watches) f])
			f(p);
	}

	// (kCLErrorLocationUnknown and the others: the one fix asked for is null)
	@:hxmc.callback static function failed(self:Ptr, cmd:Ptr, m:Ptr, error:Ptr):Void
		answer(null);

	static function answer(p:Null<GeoPosition>) {
		var waiting = once;
		once = [];
		for (f in waiting)
			f(p);
	}
}
#else
class LocationApple {}
#end
