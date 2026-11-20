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
		if (Platform.os() == Platform.WASI) return helder.os.web.WebServices.device();
		if (Platform.os() == Platform.MACOS) return DeviceApple.info();
		if (Platform.os() == Platform.WINDOWS) return DeviceDesktop.windows();
		if (Platform.target() >= 9) return helder.os.android.AndroidDevice.info();
		return DeviceDesktop.linux();
		#else
		return {model: "", manufacturer: "", os: "", osVersion: "", kind: Web};
		#end
	}
}
