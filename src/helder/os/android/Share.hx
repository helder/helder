package helder.os.android;

import hxmc.unsafe.*;

// The share sheet: ACTION_SEND (ACTION_SEND_MULTIPLE for files) in the
// system's chooser, its text the text and the URL; files as
// content://<package>.hxmc.files<path> of org.hxmc.Files (its allowed:
// this share's alone), read granted through the intent's ClipData. True
// once shown: the chooser tells no more.
@:hxmc.android @:helder.android.dex("Files")
@:hxmc.unsafe(gc)
class Share {
	public static function share(text:Null<String>, url:Null<String>, files:Array<String>):Bool {
		var shown = false;
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var intent = Jni.cls("android.content.Intent"), uri = Jni.cls("android.net.Uri");
			var i = Jni.newObject(intent, Jni.method(intent, "<init>", "(Ljava/lang/String;)V"),
				Jni.string(files.length > 1 ? "android.intent.action.SEND_MULTIPLE" : "android.intent.action.SEND").toI64());
			var putString = Jni.method(intent, "putExtra", "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;");
			var body = [for (s in [text, url]) if (s != null && s != "") s].join("\n");
			if (body != "") Jni.obj(i, putString, Jni.string("android.intent.extra.TEXT").toI64(), Jni.string(body).toI64());
			var type = files.length == 0 ? "text/plain" : mime(files);
			Jni.obj(i, Jni.method(intent, "setType", "(Ljava/lang/String;)Landroid/content/Intent;"), Jni.string(type).toI64());
			if (files.length > 0) {
				Jni.call(allowed(), Jni.method(Jni.cls("java.util.Set"), "clear", "()V"));
				var clipCls = Jni.cls("android.content.ClipData");
				var uris = [for (f in files) serve(sys.FileSystem.fullPath(f), true)];
				var stream = Jni.string("android.intent.extra.STREAM");
				if (uris.length == 1)
					Jni.obj(i, Jni.method(intent, "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"), stream.toI64(), uris[0].toI64());
				else {
					var list = Jni.cls("java.util.ArrayList");
					var l = Jni.newObject(list, Jni.method(list, "<init>", "()V"));
					for (u in uris)
						Jni.bool(l, Jni.method(list, "add", "(Ljava/lang/Object;)Z"), u.toI64());
					Jni.obj(i, Jni.method(intent, "putParcelableArrayListExtra", "(Ljava/lang/String;Ljava/util/ArrayList;)Landroid/content/Intent;"), stream.toI64(),
						l.toI64());
				}
				// (the grant goes with the ClipData, and the chooser hands it on)
				var clip = Jni.staticObj(clipCls, Jni.staticMethod(clipCls, "newRawUri", "(Ljava/lang/CharSequence;Landroid/net/Uri;)Landroid/content/ClipData;"),
					Jni.string("").toI64(), uris[0].toI64());
				var item = Jni.cls("android.content.ClipData$Item");
				for (u in uris.slice(1))
					Jni.call(clip, Jni.method(clipCls, "addItem", "(Landroid/content/ClipData$Item;)V"),
						Jni.newObject(item, Jni.method(item, "<init>", "(Landroid/net/Uri;)V"), u.toI64()).toI64());
				Jni.call(i, Jni.method(intent, "setClipData", "(Landroid/content/ClipData;)V"), clip.toI64());
				Jni.obj(i, Jni.method(intent, "addFlags", "(I)Landroid/content/Intent;"), 1); // FLAG_GRANT_READ_URI_PERMISSION
			}
			var chooser = Jni.staticObj(intent, Jni.staticMethod(intent, "createChooser", "(Landroid/content/Intent;Ljava/lang/CharSequence;)Landroid/content/Intent;"),
				i.toI64(), 0);
			Jni.call(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "startActivity", "(Landroid/content/Intent;)V"), chooser.toI64());
			shown = true;
		});
		return shown;
	}

	// (the main thread) org.hxmc.Files' allowed paths
	static function allowed():Ptr {
		var provider = Jni.cls("org.hxmc.Files");
		return Jni.JniEnv.GetStaticObjectField(Jni.env, provider, Jni.staticField(provider, "allowed", "Ljava/util/Set;"));
	}

	// (the main thread) a file's content URI of org.hxmc.Files, served while allowed (else no longer)
	@:allow(helder.os) static function serve(path:String, allow:Bool):Ptr {
		var set = Jni.cls("java.util.Set");
		Jni.bool(allowed(), Jni.method(set, allow ? "add" : "remove", "(Ljava/lang/Object;)Z"), Jni.string(path).toI64());
		if (!allow) return Ptr.nil();
		var authority = Jni.fromString(Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getPackageName", "()Ljava/lang/String;")))
			+ helder.pack.android.Apk.FILES;
		var builder = Jni.cls("android.net.Uri$Builder");
		var b = Jni.newObject(builder, Jni.method(builder, "<init>", "()V"));
		for (part in [["scheme", "content"], ["authority", authority], ["path", path]])
			Jni.obj(b, Jni.method(builder, part[0], "(Ljava/lang/String;)Landroid/net/Uri$Builder;"), Jni.string(part[1]).toI64());
		return Jni.obj(b, Jni.method(builder, "build", "()Landroid/net/Uri;"));
	}

	// the files' type: theirs when they share it, image/* for images, else */*
	static function mime(files:Array<String>):String {
		var types = [for (f in files) @:privateAccess helder.os.Share.mime(f)];
		if (Lambda.foreach(types, t -> t == types[0]) && types[0] != null) return types[0];
		return Lambda.foreach(types, t -> t != null && StringTools.startsWith(t, "image/")) ? "image/*" : "*/*";
	}
}
