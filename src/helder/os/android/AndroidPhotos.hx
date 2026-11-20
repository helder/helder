package helder.os.android;

import haxe.io.Bytes;
import hxmc.unsafe.*;

// The photo picker (MediaStore.ACTION_PICK_IMAGES from Android 13, else
// ACTION_GET_CONTENT of image/*), started for its result through
// org.hxmc.Request; the content URIs it gives read through the
// ContentResolver, on the main thread.
@:hxmc.android @:helder.android.dex("Request")
@:hxmc.unsafe(gc)
class AndroidPhotos {
	@:coroutine public static function pick(max:Int):Array<Bytes>
		return helder.os.Await.answer(done -> MainThread.post(() -> {
			try {
				AndroidRequest.start(i -> {
					var key = Jni.string("intent");
					Jni.obj(i, Jni.method(Jni.cls("android.content.Intent"), "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"),
						key.toI64(), picker(max).toI64());
				}, (code, data) -> done(code == -1 ? read(data, max) : []));
			} catch (e:Dynamic) {
				Sys.println("helder.os: Photos.pick: " + Std.string(e));
				done([]);
			}
		}));

	static function picker(max:Int):Ptr {
		var cls = Jni.cls("android.content.Intent"), modern = Mem.getI32(Activity.activity, 48) >= 33;
		var i = Jni.newObject(cls, Jni.method(cls, "<init>", "(Ljava/lang/String;)V"),
			Jni.string(modern ? "android.provider.action.PICK_IMAGES" : "android.intent.action.GET_CONTENT").toI64());
		if (modern) {
			if (max > 1) {
				var store = Jni.cls("android.provider.MediaStore");
				var limit = Jni.staticInt(store, Jni.staticMethod(store, "getPickImagesMaxLimit", "()I"));
				Jni.obj(i, Jni.method(cls, "putExtra", "(Ljava/lang/String;I)Landroid/content/Intent;"), Jni.string("android.provider.extra.PICK_IMAGES_MAX").toI64(),
					max < limit ? max : limit);
			}
		} else {
			Jni.obj(i, Jni.method(cls, "setType", "(Ljava/lang/String;)Landroid/content/Intent;"), Jni.string("image/*").toI64());
			Jni.obj(i, Jni.method(cls, "addCategory", "(Ljava/lang/String;)Landroid/content/Intent;"), Jni.string("android.intent.category.OPENABLE").toI64());
			Jni.obj(i, Jni.method(cls, "putExtra", "(Ljava/lang/String;Z)Landroid/content/Intent;"), Jni.string("android.intent.extra.ALLOW_MULTIPLE").toI64(),
				max > 1 ? 1 : 0);
		}
		return i;
	}

	// (the result's URIs: its ClipData's, else its data)
	static function read(data:Ptr, max:Int):Array<Bytes> {
		if (data.isNull()) return [];
		var cls = Jni.cls("android.content.Intent"), clipCls = Jni.cls("android.content.ClipData");
		var uris = [];
		var clip = Jni.obj(data, Jni.method(cls, "getClipData", "()Landroid/content/ClipData;"));
		if (!clip.isNull()) {
			var item = Jni.cls("android.content.ClipData$Item");
			for (k in 0...Jni.int(clip, Jni.method(clipCls, "getItemCount", "()I")))
				uris.push(Jni.obj(Jni.obj(clip, Jni.method(clipCls, "getItemAt", "(I)Landroid/content/ClipData$Item;"), k), Jni.method(item, "getUri",
					"()Landroid/net/Uri;")));
		} else {
			var u = Jni.obj(data, Jni.method(cls, "getData", "()Landroid/net/Uri;"));
			if (!u.isNull()) uris.push(u);
		}
		var resolver = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getContentResolver", "()Landroid/content/ContentResolver;"));
		var open = Jni.method(Jni.cls("android.content.ContentResolver"), "openInputStream", "(Landroid/net/Uri;)Ljava/io/InputStream;");
		var stream = Jni.cls("java.io.InputStream"), readInto = Jni.method(stream, "read", "([B)I"), close = Jni.method(stream, "close", "()V");
		var out = [];
		for (u in uris.slice(0, max)) {
			var input = try Jni.obj(resolver, open, u.toI64()) catch (_:Dynamic) continue;
			var all = new haxe.io.BytesBuffer(), chunk = Jni.JniEnv.NewByteArray(Jni.env, 65536);
			Arena.scoped(a -> {
				var tmp = a.alloc(65536);
				while (true) {
					var got = Jni.int(input, readInto, chunk.toI64());
					if (got <= 0) break;
					Jni.JniEnv.GetByteArrayRegion(Jni.env, chunk, 0, got, tmp);
					var b = Bytes.alloc(got);
					BytesPtr.copyIn(b, 0, tmp, got);
					all.add(b);
				}
			});
			Jni.call(input, close);
			Jni.deleteLocal(chunk);
			Jni.deleteLocal(input);
			out.push(all.getBytes());
		}
		return out;
	}
}
