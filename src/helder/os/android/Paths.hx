package helder.os.android;

import hxmc.unsafe.*;

// The app's directories (helder.os.Paths): the Context's, absolute paths
// asked of Java on the main thread. getExternalFilesDir(DIRECTORY_DOCUMENTS)
// is the app's own on the shared storage (a file manager sees it; null
// while that storage is not mounted).
@:hxmc.android
@:hxmc.unsafe(gc)
class Paths {
	// (ANativeActivity.internalDataPath: getFilesDir's, no Java needed; helder.os.Store's too)
	public static function files():Null<String> {
		var a = Activity.activity;
		if (a.isNull()) return null;
		var p:CString = cast Mem.getPtr(a, 32);
		return p.isNull() ? null : p.toString();
	}

	// "cache" (getCacheDir) or "documents"
	public static function dir(which:String):Null<String> {
		var out:Null<String> = null;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var context = Jni.cls("android.content.Context");
			var f = which == "cache" ? Jni.obj(Jni.activity, Jni.method(context, "getCacheDir", "()Ljava/io/File;")) : Jni.obj(Jni.activity,
				Jni.method(context, "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;"), Jni.string("Documents").toI64());
			if (!f.isNull()) out = Jni.fromString(Jni.obj(f, Jni.method(Jni.cls("java.io.File"), "getAbsolutePath", "()Ljava/lang/String;")));
		});
		return out;
	}
}
