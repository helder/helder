package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract DeviceKind(String) to String {
	var Phone = "phone";
	var Tablet = "tablet";
	var Desktop = "desktop";
	var Web = "web";
}

typedef DeviceDetails = {
	var model:String;
	var manufacturer:String;
	var os:String;
	var osVersion:String;
	var kind:DeviceKind;
}

// What the app runs on: the model ("iPhone16,1", "Pixel 4a", "Mac14,2"),
// its maker, the system ("iOS", "Android", "macOS", "Windows", "Linux"; the
// web: the browser's platform) and its version (Linux: the distribution's
// name and version), and the kind of device. "" where the system does
// not tell.
class DeviceInfo {
	@:typescript public static function get():DeviceDetails {
		#if (target.name == "hxmc")
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) return helder.os.web.WebServices.device(); #end
		#if (!helder.os || helder.os == "macos" || helder.os == "ios") if (Platform.os() == Platform.MACOS) return helder.os.apple.Device.info(); #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == Platform.WINDOWS) return helder.os.windows.Device.details(); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return helder.os.android.Device.info(); #end
		#if (!helder.os || helder.os == "linux") return helder.os.linux.Device.details(); #else throw "unreachable"; #end
		#else
		return {model: "", manufacturer: "", os: "", osVersion: "", kind: Web};
		#end
	}
}
