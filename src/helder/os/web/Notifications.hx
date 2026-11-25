package helder.os.web;

import hxmc.unsafe.*;

// The page's notifications (src/helder/os/imports.mjs): the Notification
// API's, shown by a timer while the page is open; a click focuses the page
// and comes back through clicked, by the id's key.
@:hxmc.unsafe(gc)
class Notifications {
	#if (hxmc.target == "wasm32-wasi")
	static final keys = new Map<String, Int>();
	static final ids = new Map<Int, String>();
	static var next = 1;

	public static function schedule(id:String, title:String, body:String, seconds:Float):Bool {
		var key = keys.get(id);
		if (key == null) {
			keys.set(id, key = next++);
			ids.set(key, id);
		}
		return Arena.scopedValue(a -> Notices.notify_schedule(key, a.cstring(title), a.cstring(body), seconds * 1000, Callback.addr(clicked))) == 1;
	}

	public static function cancel(id:String) {
		var key = keys.get(id);
		if (key != null) Notices.notify_cancel(key);
	}

	@:hxmc.callback static function clicked(key:Int):Int {
		var id = ids.get(key);
		if (id != null) helder.os.Notifications.open(id);
		return 0;
	}
	#else
	public static function schedule(id:String, title:String, body:String, seconds:Float):Bool
		return false;

	public static function cancel(id:String) {}
	#end
}

#if (hxmc.target == "wasm32-wasi")
@:hxmc.c @:hxmc.lib("hxmc_os") private extern class Notices {
	// a notification by its key after ms, clicked(key) when clicked; 0: no Notification API, or not granted
	static function notify_schedule(key:Int, title:CString, body:CString, ms:Float, clicked:Ptr):Int;
	static function notify_cancel(key:Int):Void;
}
#end
