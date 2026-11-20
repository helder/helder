package helder.os;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract BiometricKind(String) to String {
	var None = "none";
	var Face = "face";
	var Fingerprint = "fingerprint";
	var Other = "other";
}

// The device's biometrics: what verify would use (None where there is none
// or none is enrolled), and whether the user is verified by it, the
// system's prompt showing the reason. iOS's Face ID needs helder.json's
// usage string "faceid"; Android's USE_BIOMETRIC is added to the manifest.
class Biometrics {
	@:typescript public static function kind():BiometricKind {
		#if (target.name == "hxmc" && !helder.headless)
		if (Platform.os() == Platform.MACOS) return BiometricsApple.kind();
		if (Platform.target() >= 9) return helder.os.android.AndroidBiometrics.kind();
		#end
		return None;
	}

	@:typescript @:helder.ios.usage("faceid") @:coroutine public static function verify(reason:String):Bool {
		// (a coroutine's branches are not folded: each target's own, chosen here)
		#if helder.headless
		return false;
		#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		return BiometricsApple.verify(reason);
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return helder.os.android.AndroidBiometrics.verify(reason);
		#else
		return false;
		#end
	}
}
