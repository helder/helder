package helder.os.android;

import hxmc.unsafe.*;

// An alarm (AlarmManager: exact while idle where the app may, else
// inexact) aimed at org.hxmc.Alarm, which posts the notification in the
// channel "default"; its tap opens the app (org.hxmc.Main: brought back
// with a new intent) with the id as the intent's "hxmc.notification",
// read on resume and taken off.
@:hxmc.android @:helder.android.dex("Alarm", "Main") @:helder.android.permission("POST_NOTIFICATIONS", "SCHEDULE_EXACT_ALARM")
@:hxmc.unsafe(gc)
class AndroidNotifications {
	static var listening = false;

	public static function schedule(id:String, title:String, body:String, seconds:Float):Bool {
		var ok = false;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			channel();
			var am = Jni.service("alarm"), cls = Jni.cls("android.app.AlarmManager");
			var pi = alarm(id, intent -> {
				var put = Jni.method(Jni.cls("android.content.Intent"), "putExtra", "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;");
				for (kv in [["id", id], ["title", title], ["body", body]])
					Jni.deleteLocal(Jni.obj(intent, put, Jni.string(kv[0]).toI64(), Jni.string(kv[1]).toI64()));
			});
			var system = Jni.cls("java.lang.System");
			var now = Jni.JniEnv.CallStaticLongMethodA(Jni.env, system, Jni.staticMethod(system, "currentTimeMillis", "()J"), Ptr.nil());
			var at:haxe.Int64 = now + haxe.Int64.fromFloat(seconds * 1000);
			// (RTC_WAKEUP 0; exact alarms are the user's to allow from Android 12)
			var exact = Mem.getI32(Activity.activity, 48) < 31 || Jni.bool(am, Jni.method(cls, "canScheduleExactAlarms", "()Z"));
			Jni.call(am, Jni.method(cls, exact ? "setExactAndAllowWhileIdle" : "setAndAllowWhileIdle", "(IJLandroid/app/PendingIntent;)V"), 0, at, pi.toI64());
			ok = true;
		});
		return ok;
	}

	public static function cancel(id:String)
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			Jni.call(Jni.service("alarm"), Jni.method(Jni.cls("android.app.AlarmManager"), "cancel", "(Landroid/app/PendingIntent;)V"), alarm(id, _ -> {}).toI64());
			var tag = Jni.string(id);
			Jni.call(Jni.service("notification"), Jni.method(Jni.cls("android.app.NotificationManager"), "cancel", "(Ljava/lang/String;I)V"), tag.toI64(), 0);
		});

	// (one PendingIntent an id: its action the id's)
	static function alarm(id:String, extras:Ptr->Void):Ptr {
		var cls = Jni.cls("android.content.Intent");
		var i = Jni.newObject(cls, Jni.method(cls, "<init>", "(Landroid/content/Context;Ljava/lang/Class;)V"), Jni.activity.toI64(), Jni.cls("org.hxmc.Alarm").toI64());
		Jni.deleteLocal(Jni.obj(i, Jni.method(cls, "setAction", "(Ljava/lang/String;)Landroid/content/Intent;"), Jni.string("hxmc.notification:" + id).toI64()));
		extras(i);
		var pending = Jni.cls("android.app.PendingIntent");
		// (FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE)
		return Jni.staticObj(pending, Jni.staticMethod(pending, "getBroadcast", "(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;"),
			Jni.activity.toI64(), hash(id), i.toI64(), 0x0C000000);
	}

	// (Java's String.hashCode, as org.hxmc.Alarm's tap's request code)
	static function hash(s:String):Int {
		var h = 0;
		for (i in 0...s.length)
			h = 31 * h + StringTools.fastCodeAt(s, i);
		return h;
	}

	static function channel() {
		var cls = Jni.cls("android.app.NotificationChannel");
		var label = Jni.obj(Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getApplicationInfo", "()Landroid/content/pm/ApplicationInfo;")),
			Jni.method(Jni.cls("android.content.pm.ApplicationInfo"), "loadLabel", "(Landroid/content/pm/PackageManager;)Ljava/lang/CharSequence;"),
			Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageManager", "()Landroid/content/pm/PackageManager;")).toI64());
		// (IMPORTANCE_DEFAULT 3)
		var c = Jni.newObject(cls, Jni.method(cls, "<init>", "(Ljava/lang/String;Ljava/lang/CharSequence;I)V"), Jni.string("default").toI64(), label.toI64(), 3);
		Jni.call(Jni.service("notification"), Jni.method(Jni.cls("android.app.NotificationManager"), "createNotificationChannel", "(Landroid/app/NotificationChannel;)V"),
			c.toI64());
	}

	// a tap's id: the activity's intent read now and on each resume
	public static function listen() {
		if (!listening) {
			listening = true;
			AndroidWindow.resumed.push(check);
		}
		check();
	}

	static function check() {
		var id:Null<String> = null;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var cls = Jni.cls("android.content.Intent");
			var intent = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getIntent", "()Landroid/content/Intent;"));
			if (intent.isNull()) return;
			var key = Jni.string("hxmc.notification");
			var v = Jni.obj(intent, Jni.method(cls, "getStringExtra", "(Ljava/lang/String;)Ljava/lang/String;"), key.toI64());
			if (v.isNull()) return;
			id = Jni.fromString(v);
			Jni.call(intent, Jni.method(cls, "removeExtra", "(Ljava/lang/String;)V"), key.toI64());
		});
		if (id != null) Notifications.open(id);
	}
}
