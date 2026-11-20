package helder.os.android;

import helder.os.Biometrics.BiometricKind;
import hxmc.unsafe.*;

// The framework's BiometricPrompt (android.hardware.biometrics, API 28;
// no androidx): the reason its title, the system's cancel its negative
// button, answered through org.hxmc.Biometric on the main thread. What
// there is: BiometricManager's canAuthenticate (an enrolled biometric the
// prompt takes: BIOMETRIC_WEAK from API 30), then the system's features.
@:hxmc.android @:helder.android.dex("Biometric") @:helder.android.permission("USE_BIOMETRIC")
@:hxmc.unsafe(gc)
class AndroidBiometrics {
	static final pending = new Map<Int, Bool->Void>();
	static var nextId = 1;
	static var cls = Ptr.nil();

	public static function kind():BiometricKind {
		var k = None;
		MainThread.run(() -> k = try kindNow() catch (e:Dynamic) None);
		return k;
	}

	static function kindNow():BiometricKind {
		if (Activity.activity.isNull()) return None;
		var manager = Jni.service("biometric"), bm = Jni.cls("android.hardware.biometrics.BiometricManager");
		if (manager.isNull()) return None;
		var can = AndroidPermissions.sdk() >= 30 ? Jni.int(manager, Jni.method(bm, "canAuthenticate", "(I)I"), 0xff) : Jni.int(manager,
			Jni.method(bm, "canAuthenticate", "()I"));
		if (can != 0) return None;
		var pm = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageManager", "()Landroid/content/pm/PackageManager;"));
		var has = Jni.method(Jni.cls("android.content.pm.PackageManager"), "hasSystemFeature", "(Ljava/lang/String;)Z");
		return Jni.bool(pm, has, Jni.string("android.hardware.fingerprint").toI64()) ? Fingerprint : Jni.bool(pm, has,
			Jni.string("android.hardware.biometrics.face").toI64()) ? Face : Other;
	}

	@:coroutine public static function verify(reason:String):Bool {
		if (kind() == None) return false;
		return helder.os.Await.answer(done -> MainThread.post(() -> {
			try {
				if (cls.isNull()) {
					cls = Jni.cls("org.hxmc.Biometric");
					Jni.registerNatives(cls, [{name: "done", sig: "(II)V", fn: Callback.addr(answered)}]);
				}
				var id = nextId++;
				var callback = Jni.global(Jni.newObject(cls, Jni.method(cls, "<init>", "(I)V"), id));
				pending.set(id, ok -> {
					Jni.deleteGlobal(callback);
					done(ok);
				});
				var context = Jni.cls("android.content.Context"), cs = "Ljava/lang/CharSequence;";
				var executor = Jni.obj(Jni.activity, Jni.method(context, "getMainExecutor", "()Ljava/util/concurrent/Executor;"));
				var builder = Jni.cls("android.hardware.biometrics.BiometricPrompt$Builder"), b = "Landroid/hardware/biometrics/BiometricPrompt$Builder;";
				var p = Jni.newObject(builder, Jni.method(builder, "<init>", "(Landroid/content/Context;)V"), Jni.activity.toI64());
				Jni.obj(p, Jni.method(builder, "setTitle", '($cs)$b'), Jni.string(reason).toI64());
				// (@android:string/cancel)
				var cancel = Jni.obj(Jni.activity, Jni.method(context, "getString", "(I)Ljava/lang/String;"), 0x01040000);
				Jni.obj(p, Jni.method(builder, "setNegativeButton", '(${cs}Ljava/util/concurrent/Executor;Landroid/content/DialogInterface$$OnClickListener;)$b'),
					cancel.toI64(), executor.toI64(), callback.toI64());
				var prompt = Jni.obj(p, Jni.method(builder, "build", "()Landroid/hardware/biometrics/BiometricPrompt;"));
				var signal = Jni.cls("android.os.CancellationSignal");
				Jni.call(prompt, Jni.method(Jni.cls("android.hardware.biometrics.BiometricPrompt"), "authenticate",
					"(Landroid/os/CancellationSignal;Ljava/util/concurrent/Executor;Landroid/hardware/biometrics/BiometricPrompt$AuthenticationCallback;)V"),
					Jni.newObject(signal, Jni.method(signal, "<init>", "()V")).toI64(), executor.toI64(), callback.toI64());
			} catch (e:Dynamic) {
				Sys.println("helder.os: Biometrics.verify: " + Std.string(e));
				done(false);
			}
		}));
	}

	@:hxmc.callback static function answered(env:Ptr, c:Ptr, id:Int, ok:Int):Void {
		var f = pending.get(id);
		pending.remove(id);
		if (f != null) f(ok == 1);
	}
}
