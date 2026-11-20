package helder.os.android;

import helder.os.Permissions.Permission;
import helder.os.Permissions.PermissionStatus;
import hxmc.unsafe.*;

// The activity's runtime permissions: granted (checkSelfPermission), else
// denied once asked and the system would not ask again
// (shouldShowRequestPermissionRationale false: remembered in the app's
// preferences that it asked), else prompt; asked through org.hxmc.Request.
// Notifications need no asking before Android 13 (granted, unless the
// user turned them off).
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidPermissions {
	public static function status(p:Permission):PermissionStatus {
		var s = Unsupported;
		MainThread.run(() -> s = statusNow(p));
		return s;
	}

	@:coroutine public static function request(p:Permission):PermissionStatus {
		var s = status(p);
		if (s != Prompt) return s;
		return ask(manifest(p, sdk())) ? Granted : Denied;
	}

	// the system's dialog for these permissions (android.permission.*): whether one was granted
	@:coroutine @:allow(helder.os) static function ask(names:Array<String>):Bool {
		var grants:Array<Int> = Await.answer(done -> MainThread.post(() -> {
			try {
				AndroidRequest.start(i -> {
					var key = Jni.string("permissions");
					Jni.obj(i, Jni.method(Jni.cls("android.content.Intent"), "putExtra", "(Ljava/lang/String;[Ljava/lang/String;)Landroid/content/Intent;"),
						key.toI64(), Jni.strings(names).toI64());
				}, (_, data) -> done(Jni.ints(data)));
				asked(names);
			} catch (e:Dynamic) {
				Sys.println("helder.os: Permissions.request: " + Std.string(e));
				done([]);
			}
		}));
		return grants.contains(0);
	}

	@:allow(helder.os) static inline function sdk():Int
		return Mem.getI32(Activity.activity, 48);

	// the manifest's permissions of p on this system (none: nothing to ask)
	static function manifest(p:Permission, sdk:Int):Array<String>
		return [
			for (n in helder.pack.android.Glue.permissions(p))
				if ((n != "READ_MEDIA_IMAGES" || sdk >= 33) && (n != "READ_EXTERNAL_STORAGE" || sdk < 33) && (n != "POST_NOTIFICATIONS" || sdk >= 33))
					"android.permission." + n
		];

	@:allow(helder.os) static function statusNow(p:Permission):PermissionStatus {
		if (Activity.activity.isNull()) return Unsupported;
		var names = manifest(p, sdk());
		if (names.length == 0) {
			if (p != Notify) return Unsupported;
			var manager = Jni.service("notification");
			return manager.isNull() || Jni.bool(manager, Jni.method(Jni.cls("android.app.NotificationManager"), "areNotificationsEnabled", "()Z")) ? Granted : Denied;
		}
		var context = Jni.cls("android.content.Context"), activity = Jni.cls("android.app.Activity");
		var check = Jni.method(context, "checkSelfPermission", "(Ljava/lang/String;)I");
		for (n in names) {
			var s = Jni.string(n);
			var granted = Jni.int(Jni.activity, check, s.toI64()) == 0;
			Jni.deleteLocal(s);
			if (granted) return Granted;
		}
		var s = Jni.string(names[0]);
		var again = Jni.bool(Jni.activity, Jni.method(activity, "shouldShowRequestPermissionRationale", "(Ljava/lang/String;)Z"), s.toI64());
		var before = Jni.bool(preferences(), Jni.method(Jni.cls("android.content.SharedPreferences"), "getBoolean", "(Ljava/lang/String;Z)Z"), s.toI64(), 0);
		Jni.deleteLocal(s);
		return before && !again ? Denied : Prompt;
	}

	// (the main thread) whether the app's manifest asks for that permission (android.permission.*)
	@:allow(helder.os) static function declared(name:String):Bool {
		var pm = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageManager", "()Landroid/content/pm/PackageManager;"));
		var pkg = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageName", "()Ljava/lang/String;"));
		// (PackageManager.GET_PERMISSIONS)
		var info = Jni.obj(pm, Jni.method(Jni.cls("android.content.pm.PackageManager"), "getPackageInfo", "(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;"),
			pkg.toI64(), 4096);
		var all = Jni.JniEnv.GetObjectField(Jni.env, info, Jni.field(Jni.cls("android.content.pm.PackageInfo"), "requestedPermissions", "[Ljava/lang/String;"));
		if (all.isNull()) return false;
		for (i in 0...Jni.JniEnv.GetArrayLength(Jni.env, all))
			if (Jni.fromString(Jni.JniEnv.GetObjectArrayElement(Jni.env, all, i)) == name) return true;
		return false;
	}

	static function preferences():Ptr {
		var name = Jni.string("hxmc.permissions");
		var p = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getSharedPreferences", "(Ljava/lang/String;I)Landroid/content/SharedPreferences;"),
			name.toI64(), 0);
		Jni.deleteLocal(name);
		return p;
	}

	static function asked(names:Array<String>) {
		var editor = Jni.obj(preferences(), Jni.method(Jni.cls("android.content.SharedPreferences"), "edit", "()Landroid/content/SharedPreferences$Editor;"));
		var cls = Jni.cls("android.content.SharedPreferences$Editor");
		var put = Jni.method(cls, "putBoolean", "(Ljava/lang/String;Z)Landroid/content/SharedPreferences$Editor;");
		for (n in names) {
			var s = Jni.string(n);
			Jni.deleteLocal(Jni.obj(editor, put, s.toI64(), 1));
			Jni.deleteLocal(s);
		}
		Jni.call(editor, Jni.method(cls, "apply", "()V"));
	}
}
