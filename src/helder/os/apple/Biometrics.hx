package helder.os.apple;

import helder.os.Await;
#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.Biometrics.BiometricKind;
import helder.os.apple.objc.*;
import hxmc.objc.Block;
import hxmc.unsafe.*;

// LocalAuthentication's LAContext (loaded when first asked), policy
// LAPolicyDeviceOwnerAuthenticationWithBiometrics: canEvaluatePolicy and
// biometryType for what there is (none when nothing is enrolled),
// evaluatePolicy's reply (on its own queue: hxmc's blocks attach it).
@:hxmc.unsafe(gc)
class Biometrics {
	public static function kind():BiometricKind {
		var pool = Runtime.objc_autoreleasePoolPush();
		var ctx = Msg.id(Msg.id(Msg.id(@:privateAccess Permissions.load("LocalAuthentication", "LAContext"), ObjC.sel("alloc")), ObjC.sel("init")),
			ObjC.sel("autorelease"));
		var ok = Msg.bIntPtr(ctx, ObjC.sel("canEvaluatePolicy:error:"), 1, Ptr.nil());
		// (LABiometryType: none 0, touchID 1, faceID 2, opticID 4)
		var type = Msg.i(ctx, ObjC.sel("biometryType")).toInt();
		Runtime.objc_autoreleasePoolPop(pool);
		return !ok || type == 0 ? None : type == 1 ? Fingerprint : type == 2 ? Face : Other;
	}

	@:coroutine public static function verify(reason:String):Bool {
		if (kind() == None) return false;
		var ctx = Msg.id(Msg.id(@:privateAccess Permissions.load("LocalAuthentication", "LAContext"), ObjC.sel("alloc")), ObjC.sel("init"));
		var ok:Bool = Await.answer(done -> {
			var text = ObjC.str(reason);
			var reply:Block<(Bool, Ptr) -> Void> = (success, _) -> done(success);
			Msg.vIntPtrPtr(ctx, ObjC.sel("evaluatePolicy:localizedReason:reply:"), 1, text, cast reply);
			ObjC.release(text);
		});
		ObjC.release(ctx);
		return ok;
	}
}
#else
class Biometrics {
	public static function kind():helder.os.Biometrics.BiometricKind
		return None;
}
#end
