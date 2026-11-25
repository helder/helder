package helder.os.android;

import hxmc.unsafe.*;

@:hxmc.android
@:hxmc.unsafe(gc)
class Clipboard {
	public static function write(text:String) {
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var manager = Jni.service("clipboard");
			if (manager.isNull()) return;
			var clip = Jni.cls("android.content.ClipData");
			var data = Jni.staticObj(clip, Jni.staticMethod(clip, "newPlainText",
				"(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;"), 0, Jni.string(text).toI64());
			Jni.call(manager, Jni.method(Jni.cls("android.content.ClipboardManager"), "setPrimaryClip", "(Landroid/content/ClipData;)V"), data.toI64());
		});
	}

	public static function read():Null<String> {
		var text:Null<String> = null;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var manager = Jni.service("clipboard");
			if (manager.isNull()) return;
			var data = Jni.obj(manager, Jni.method(Jni.cls("android.content.ClipboardManager"), "getPrimaryClip", "()Landroid/content/ClipData;"));
			if (data.isNull()) return;
			var item = Jni.obj(data, Jni.method(Jni.cls("android.content.ClipData"), "getItemAt", "(I)Landroid/content/ClipData$Item;"), 0);
			var value = Jni.obj(item, Jni.method(Jni.cls("android.content.ClipData$Item"), "getText", "()Ljava/lang/CharSequence;"));
			if (!value.isNull()) text = Jni.text(value);
		});
		return text;
	}
}
