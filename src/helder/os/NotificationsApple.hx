package helder.os;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.objc.*;
import hxmc.objc.Block;
import hxmc.unsafe.*;
#end

// UNUserNotificationCenter's: a request of the id, its trigger a time
// interval (after) or the calendar's moment (at), none for now; a delegate
// (a class made at run time) showing them while the app is in front too,
// and handing a tap to Notifications.open. None for a program outside an
// app bundle.
@:hxmc.unsafe(gc)
class NotificationsApple {
	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
	static var delegate = Ptr.nil();

	public static function schedule(id:String, title:String, body:String, seconds:Float, at:Null<Date>):Bool {
		var center = listen();
		if (center.isNull()) return false;
		var pool = Runtime.objc_autoreleasePoolPush();
		function str(s:String):Ptr
			return Msg.id(ObjC.str(s), ObjC.sel("autorelease"));
		var content = Msg.id(Msg.id(ObjC.cls("UNMutableNotificationContent"), ObjC.sel("new")), ObjC.sel("autorelease"));
		Msg.vPtr(content, ObjC.sel("setTitle:"), str(title));
		Msg.vPtr(content, ObjC.sel("setBody:"), str(body));
		Msg.vPtr(content, ObjC.sel("setSound:"), Msg.id(ObjC.cls("UNNotificationSound"), ObjC.sel("defaultSound")));
		var trigger = Ptr.nil();
		if (at != null && seconds > 0) {
			// (year, month, day, hour, minute, second)
			var date = Msg.idFloat(ObjC.cls("NSDate"), ObjC.sel("dateWithTimeIntervalSince1970:"), at.getTime() / 1000);
			var parts = Msg.idIntPtr(Msg.id(ObjC.cls("NSCalendar"), ObjC.sel("currentCalendar")), ObjC.sel("components:fromDate:"), 4 | 8 | 16 | 32 | 64 | 128, date);
			trigger = Msg.idPtrBool(ObjC.cls("UNCalendarNotificationTrigger"), ObjC.sel("triggerWithDateMatchingComponents:repeats:"), parts, false);
		} else if (seconds > 0)
			trigger = Msg.idFloatBool(ObjC.cls("UNTimeIntervalNotificationTrigger"), ObjC.sel("triggerWithTimeInterval:repeats:"), seconds, false);
		var request = Msg.idPtrPtrPtr(ObjC.cls("UNNotificationRequest"), ObjC.sel("requestWithIdentifier:content:trigger:"), str(id), content, trigger);
		Msg.vPtrPtr(center, ObjC.sel("addNotificationRequest:withCompletionHandler:"), request, Ptr.nil());
		Runtime.objc_autoreleasePoolPop(pool);
		return true;
	}

	public static function cancel(id:String) {
		var center = listen();
		if (center.isNull()) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		var ids = Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), Msg.id(ObjC.str(id), ObjC.sel("autorelease")));
		Msg.vPtr(center, ObjC.sel("removePendingNotificationRequestsWithIdentifiers:"), ids);
		Msg.vPtr(center, ObjC.sel("removeDeliveredNotificationsWithIdentifiers:"), ids);
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// the center, its delegate set (nil: no app bundle)
	public static function listen():Ptr {
		var center = @:privateAccess PermissionsApple.notifications();
		if (center.isNull() || !delegate.isNull()) return center;
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcNotificationDelegate"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("userNotificationCenter:willPresentNotification:withCompletionHandler:"), Callback.addr(present), Mem.cstr("v@:@@@"));
		Runtime.class_addMethod(cls, ObjC.sel("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:"), Callback.addr(response),
			Mem.cstr("v@:@@@"));
		Runtime.objc_registerClassPair(cls);
		delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(center, ObjC.sel("setDelegate:"), delegate);
		return center;
	}

	// (in front: a banner, the list, the sound)
	@:hxmc.callback static function present(self:Ptr, cmd:Ptr, center:Ptr, notification:Ptr, done:Ptr):Void {
		var f:haxe.Int64->Void = (cast done : Block<haxe.Int64->Void>);
		f(16 | 8 | 2);
	}

	@:hxmc.callback static function response(self:Ptr, cmd:Ptr, center:Ptr, r:Ptr, done:Ptr):Void {
		var id = ObjC.string(Msg.id(Msg.id(Msg.id(r, ObjC.sel("notification")), ObjC.sel("request")), ObjC.sel("identifier")));
		var f:Void->Void = (cast done : Block<Void->Void>);
		f();
		if (id != null) Notifications.open(id);
	}
	#else
	public static function schedule(id:String, title:String, body:String, seconds:Float, at:Null<Date>):Bool
		return false;

	public static function cancel(id:String) {}

	public static function listen() {}
	#end
}
