package helder.os;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.DeviceInfo.DeviceDetails;
import helder.os.objc.*;
import hxmc.Platform;
import hxmc.unsafe.*;

// iOS: hw.machine (iPhone16,1; the simulator's own model from its
// SIMULATOR_MODEL_IDENTIFIER), UIDevice's system and idiom. macOS: hw.model
// (Mac14,2), kern.osproductversion.
@:hxmc.unsafe(gc)
class DeviceApple {
	public static function info():DeviceDetails {
		if (Platform.apple() < 1) return {model: sysctl("hw.model") ?? "Mac", manufacturer: "Apple", os: "macOS", osVersion: sysctl("kern.osproductversion") ?? "",
			kind: Desktop};
		var pool = Runtime.objc_autoreleasePoolPush();
		var device = Msg.id(ObjC.cls("UIDevice"), ObjC.sel("currentDevice"));
		// (UIUserInterfaceIdiom: phone 0, pad 1, tv 2, carPlay 3, mac 5)
		var idiom = Msg.i(device, ObjC.sel("userInterfaceIdiom")).toInt();
		var d:DeviceDetails = {
			model: Sys.getEnv("SIMULATOR_MODEL_IDENTIFIER") ?? sysctl("hw.machine") ?? "",
			manufacturer: "Apple",
			os: ObjC.string(Msg.id(device, ObjC.sel("systemName"))) ?? "iOS",
			osVersion: ObjC.string(Msg.id(device, ObjC.sel("systemVersion"))) ?? "",
			kind: idiom == 1 ? Tablet : idiom == 5 ? Desktop : Phone
		};
		Runtime.objc_autoreleasePoolPop(pool);
		return d;
	}

	static function sysctl(name:String):Null<String>
		return Arena.scopedValue(a -> {
			var n = a.cstring(name), size:Ptr<Int64> = a.alloc(8);
			if (Ctl.sysctlbyname(n, Ptr.nil(), size, Ptr.nil(), 0) != 0 || size.value <= 0) null else {
				var buf = a.alloc(size.value.toInt() + 1);
				Ctl.sysctlbyname(n, buf, size, Ptr.nil(), 0) != 0 ? null : (cast buf : CString).toString();
			}
		});
}

@:hxmc.c private extern class Ctl {
	static function sysctlbyname(name:Ptr, old:Ptr, size:Ptr, newp:Ptr, newSize:Int64):Int;
}
#else
class DeviceApple {
	public static function info():helder.os.DeviceInfo.DeviceDetails
		return {model: "", manufacturer: "Apple", os: "macOS", osVersion: "", kind: Desktop};
}
#end
