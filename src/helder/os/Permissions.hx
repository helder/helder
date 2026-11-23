package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract Permission(String) to String {
	var Camera = "camera";
	var Microphone = "microphone";
	var PhotoLibrary = "photos";
	var Location = "location";
	var Notify = "notifications";
}

enum abstract PermissionStatus(String) to String {
	var Granted = "granted";
	var Denied = "denied";
	var Prompt = "prompt";
	var Unsupported = "unsupported";
}

class Permissions {
	// whether the app may use p: Prompt when asking would show the system's dialog
	@:typescript public static function status(p:Permission):PermissionStatus {
		#if (target.name == "hxmc" && !helder.headless)
		#if (!helder.os || helder.os == "web") if (Platform.os() == Platform.WASI) return helder.os.web.WebServices.status(p); #end
		#if (!helder.os || helder.os == "macos" || helder.os == "ios") if (Platform.os() == Platform.MACOS) return PermissionsApple.status(p); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return helder.os.android.AndroidPermissions.status(p); #end
		#end
		return p == Notify ? Granted : Unsupported;
	}

	// the system's dialog where status is Prompt, its answer; otherwise the
	// status. What is asked for is declared by the build (Android's
	// manifest, iOS's usage strings: helder.json's ios.usage)
	@:typescript @:helder.permission @:coroutine public static function request(p:Permission):PermissionStatus {
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return status(p);
		#elseif (hxmc.target == "wasm32-wasi")
		return helder.os.web.WebServices.request(p);
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return PermissionsApple.request(p);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidPermissions.request(p);
		#else
		return status(p);
		#end
	}
}
