package helder.os.web;

import helder.os.Location.GeoPosition;
import hxmc.unsafe.*;

// navigator.geolocation (src/helder/os/imports.mjs): getCurrentPosition
// and watchPosition, which ask for the permission themselves; a fix's
// values kept by the page until read here (location_value).
@:hxmc.unsafe(gc)
class WebLocation {
	#if (hxmc.target == "wasm32-wasi")
	static final pending = new Map<Int, Int->Void>();
	static final watches = new Map<Int, GeoPosition->Void>();
	static var next = 1;

	@:coroutine public static function current(precise:Bool):Null<GeoPosition> {
		var ok:Int = helder.os.Await.answer(done -> {
			var id = next++;
			pending.set(id, done);
			Geo.location_current(precise ? 1 : 0, Callback.addr(answered), id);
		});
		return ok == 1 ? position() : null;
	}

	public static function watch(precise:Bool, f:GeoPosition->Void):Int {
		var id = next++;
		watches.set(id, f);
		Geo.location_watch(precise ? 1 : 0, Callback.addr(moved), id);
		return id;
	}

	public static function stop(id:Int) {
		watches.remove(id);
		Geo.location_stop(id);
	}

	// (latitude, longitude, accuracy, altitude, heading, speed, time: NaN where unknown)
	static function position():GeoPosition {
		inline function known(k:Int):Null<Float> {
			var v = Geo.location_value(k);
			return Math.isNaN(v) ? null : v;
		}
		return {
			latitude: Geo.location_value(0),
			longitude: Geo.location_value(1),
			accuracy: Geo.location_value(2),
			altitude: known(3),
			heading: known(4),
			speed: known(5),
			time: Geo.location_value(6)
		};
	}

	@:hxmc.callback static function answered(id:Int, ok:Int):Int {
		var f = pending.get(id);
		pending.remove(id);
		if (f != null) f(ok);
		return 0;
	}

	@:hxmc.callback static function moved(id:Int, ok:Int):Int {
		var f = watches.get(id);
		if (f != null && ok == 1) f(position());
		return 0;
	}
	#end
}

#if (hxmc.target == "wasm32-wasi")
@:hxmc.c @:hxmc.lib("hxmc_os") private extern class Geo {
	// done(id, 1 a fix, 0 none: denied, unavailable, timed out)
	static function location_current(precise:Int, done:Ptr, id:Int):Void;
	// moved(id, 1) at each fix until stopped
	static function location_watch(precise:Int, moved:Ptr, id:Int):Void;
	static function location_stop(id:Int):Void;
	// the last fix's values
	static function location_value(k:Int):Float;
}
#end
