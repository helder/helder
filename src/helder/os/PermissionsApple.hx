package helder.os;

import helder.os.Permissions.Permission;
import helder.os.Permissions.PermissionStatus;
#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.audio.CoreAudio.Dispatch;
import helder.os.audio.CoreAudio.DispatchWait;
import helder.os.objc.*;
import hxmc.objc.Block;
import hxmc.unsafe.*;
#end

// iOS's and macOS's permissions, each its framework's (loaded when first
// asked): AVCaptureDevice's (camera, microphone), PHPhotoLibrary's (read
// and write), CLLocationManager's (when in use: its delegate a class made
// at run time), UNUserNotificationCenter's (alerts, sounds, badges; none
// for a program outside an app bundle). Their answers come on the
// frameworks' queues (hxmc's blocks attach the thread).
@:hxmc.unsafe(gc)
class PermissionsApple {
	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
	public static function status(p:Permission):PermissionStatus {
		var pool = Runtime.objc_autoreleasePoolPush();
		var s = switch p {
			case Camera | Microphone:
				av(Msg.iPtr(load("AVFoundation", "AVCaptureDevice"), ObjC.sel("authorizationStatusForMediaType:"), media(p)));
			case Photos:
				photos(Msg.iInt(load("Photos", "PHPhotoLibrary"), ObjC.sel("authorizationStatusForAccessLevel:"), 2));
			case Location:
				location();
			case Notifications:
				var center = notifications();
				if (center.isNull()) Unsupported else {
					var done = Dispatch.dispatch_semaphore_create(0), state = -1;
					var answer:Block<Ptr->Void> = settings -> {
						state = Msg.i(settings, ObjC.sel("authorizationStatus")).toInt();
						Dispatch.dispatch_semaphore_signal(done);
					};
					Msg.vPtr(center, ObjC.sel("getNotificationSettingsWithCompletionHandler:"), cast answer);
					DispatchWait.dispatch_semaphore_wait(done, Dispatch.dispatch_time(0, 2000000000));
					// (notDetermined 0, denied 1, authorized 2, provisional 3, ephemeral 4)
					state < 0 ? Unsupported : state == 0 ? Prompt : state == 1 ? Denied : Granted;
				}
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return s;
	}

	@:coroutine public static function request(p:Permission):PermissionStatus {
		var s = status(p);
		if (s != Prompt) return s;
		return Await.answer(done -> {
			var pool = Runtime.objc_autoreleasePoolPush();
			switch p {
				case Camera | Microphone:
					var answer:Block<Bool->Void> = granted -> done(granted ? Granted : Denied);
					Msg.vPtrPtr(load("AVFoundation", "AVCaptureDevice"), ObjC.sel("requestAccessForMediaType:completionHandler:"), media(p), cast answer);
				case Photos:
					var answer:Block<haxe.Int64->Void> = state -> done(photos(state));
					Msg.vIntPtr(load("Photos", "PHPhotoLibrary"), ObjC.sel("requestAuthorizationForAccessLevel:handler:"), 2, cast answer);
				case Location:
					located = done;
					Msg.v(manager(), ObjC.sel("requestWhenInUseAuthorization"));
				case Notifications:
					var answer:Block<(Bool, Ptr) -> Void> = (granted, _) -> done(granted ? Granted : Denied);
					Msg.vIntPtr(notifications(), ObjC.sel("requestAuthorizationWithOptions:completionHandler:"), 7, cast answer);
			}
			Runtime.objc_autoreleasePoolPop(pool);
		});
	}

	// a framework's class, the framework loaded first
	@:allow(helder.os) static function load(framework:String, cls:String):Ptr {
		Arena.scoped(a -> Posix.dlopen(a.cstring('/System/Library/Frameworks/$framework.framework/$framework'), 1));
		return Arena.scopedValue(a -> Runtime.objc_getClass(a.cstring(cls)));
	}

	static function media(p:Permission):Ptr
		return Mem.getPtr(Posix.dlsym(Ptr.ofI64(-2), p == Camera ? Mem.cstr("AVMediaTypeVideo") : Mem.cstr("AVMediaTypeAudio")), 0);

	// (AVAuthorizationStatus: notDetermined 0, restricted 1, denied 2, authorized 3)
	static function av(s:haxe.Int64):PermissionStatus
		return s == 0 ? Prompt : s == 3 ? Granted : Denied;

	// (PHAuthorizationStatus: as AVAuthorizationStatus's, and limited 4)
	static function photos(s:haxe.Int64):PermissionStatus
		return s == 0 ? Prompt : s >= 3 ? Granted : Denied;

	static function notifications():Ptr {
		var bundle = Msg.id(Msg.id(ObjC.cls("NSBundle"), ObjC.sel("mainBundle")), ObjC.sel("bundleIdentifier"));
		if (bundle.isNull()) return Ptr.nil();
		return Msg.id(load("UserNotifications", "UNUserNotificationCenter"), ObjC.sel("currentNotificationCenter"));
	}

	// ---- location: a manager kept, its delegate told of each change

	static var located:Null<PermissionStatus->Void>;
	static var locations = Ptr.nil();

	static function manager():Ptr {
		if (!locations.isNull()) return locations;
		var cls = load("CoreLocation", "CLLocationManager");
		var d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcLocationDelegate"), 0);
		Runtime.class_addMethod(d, ObjC.sel("locationManagerDidChangeAuthorization:"), Callback.addr(changed), Mem.cstr("v@:@"));
		Runtime.objc_registerClassPair(d);
		locations = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(locations, ObjC.sel("setDelegate:"), Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init")));
		return locations;
	}

	// (CLAuthorizationStatus: notDetermined 0, restricted 1, denied 2, always 3, when in use 4; services off: denied)
	static function location():PermissionStatus {
		if (!Msg.b(load("CoreLocation", "CLLocationManager"), ObjC.sel("locationServicesEnabled"))) return Denied;
		var s = Msg.i(manager(), ObjC.sel("authorizationStatus"));
		return s == 0 ? Prompt : s >= 3 ? Granted : Denied;
	}

	@:hxmc.callback static function changed(self:Ptr, cmd:Ptr, m:Ptr):Void {
		var s = Msg.i(m, ObjC.sel("authorizationStatus"));
		var f = located;
		if (s == 0 || f == null) return;
		located = null;
		f(s >= 3 ? Granted : Denied);
	}
	#else
	public static function status(p:Permission):PermissionStatus
		return Unsupported;

	#end
}
