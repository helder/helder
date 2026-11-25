package helder.os.android;

import hxmc.unsafe.*;

// The deep link the activity was started or brought back with (a VIEW
// intent's data: org.hxmc.Main sets the activity's intent to a new one),
// for App.onOpen, read once: its data taken off the intent. An app with
// links (-D helder.links) checks on each resume.
@:hxmc.android
@:hxmc.unsafe(gc)
class Links {
	public static function check() {
		var url:Null<String> = null;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var cls = Jni.cls("android.content.Intent");
			var intent = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getIntent", "()Landroid/content/Intent;"));
			if (intent.isNull()) return;
			if (Jni.fromString(Jni.obj(intent, Jni.method(cls, "getAction", "()Ljava/lang/String;"))) != "android.intent.action.VIEW") return;
			var data = Jni.obj(intent, Jni.method(cls, "getDataString", "()Ljava/lang/String;"));
			if (data.isNull()) return;
			url = Jni.fromString(data);
			Jni.deleteLocal(Jni.obj(intent, Jni.method(cls, "setData", "(Landroid/net/Uri;)Landroid/content/Intent;"), 0));
		});
		if (url != null) App.open([url]);
	}
}
