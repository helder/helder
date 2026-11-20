package helder.os.android;

import haxe.io.Bytes;
import hxmc.unsafe.*;

// The photo picker (MediaStore.ACTION_PICK_IMAGES from Android 13, else
// ACTION_GET_CONTENT of image/*), started for its result through
// org.hxmc.Request; on the main thread only the result's content URIs
// taken (global references), their bytes read through the ContentResolver
// on a thread of their own, attached to the VM, then given to the loop.
@:hxmc.android @:helder.android.dex("Request")
@:hxmc.unsafe(gc)
class AndroidPhotos {
	@:coroutine public static function pick(max:Int):Array<Bytes> {
		var uris:Array<Ptr> = helder.os.Await.answer(done -> MainThread.post(() -> {
			try {
				AndroidRequest.start(i -> {
					var key = Jni.string("intent");
					Jni.obj(i, Jni.method(Jni.cls("android.content.Intent"), "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"),
						key.toI64(), picker(max).toI64());
				}, (code, data) -> done(code == -1 ? taken(data, max) : []));
			} catch (e:Dynamic) {
				Sys.println("helder.os: Photos.pick: " + Std.string(e));
				done([]);
			}
		}));
		if (uris.length == 0) return [];
		var resolver = Ptr.nil();
		MainThread.run(() -> resolver = Jni.global(Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getContentResolver",
			"()Landroid/content/ContentResolver;"))));
		return helder.os.Await.answer(done -> sys.thread.Thread.create(() -> done(try attached(env -> read(env, resolver, uris)) catch (e:Dynamic) {
			Sys.println("helder.os: Photos.pick: " + Std.string(e));
			[];
		})));
	}

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

	// (the main thread: the result's URIs, its ClipData's, else its data; global references)
	static function taken(data:Ptr, max:Int):Array<Ptr> {
		if (data.isNull()) return [];
		var cls = Jni.cls("android.content.Intent"), clipCls = Jni.cls("android.content.ClipData");
		var uris = [];
		var clip = Jni.obj(data, Jni.method(cls, "getClipData", "()Landroid/content/ClipData;"));
		if (!clip.isNull()) {
			var item = Jni.cls("android.content.ClipData$Item");
			for (k in 0...Jni.int(clip, Jni.method(clipCls, "getItemCount", "()I")))
				if (uris.length < max)
					uris.push(Jni.global(Jni.obj(Jni.obj(clip, Jni.method(clipCls, "getItemAt", "(I)Landroid/content/ClipData$Item;"), k), Jni.method(item, "getUri",
						"()Landroid/net/Uri;"))));
		} else {
			var u = Jni.obj(data, Jni.method(cls, "getData", "()Landroid/net/Uri;"));
			if (!u.isNull()) uris.push(Jni.global(u));
		}
		return uris;
	}

	// (the reading thread: each URI's bytes, its references let go; one that fails left out)
	static function read(env:Ptr, resolver:Ptr, uris:Array<Ptr>):Array<Bytes> {
		var args:Ptr = LibC.malloc(16), out = [];
		function cls(name:String):Ptr
			return Arena.scopedValue(a -> Jni.JniEnv.FindClass(env, a.cstring(name)));
		function method(c:Ptr, name:String, sig:String):Ptr
			return Arena.scopedValue(a -> Jni.JniEnv.GetMethodID(env, c, a.cstring(name), a.cstring(sig)));
		function failed():Bool {
			if (Jni.JniEnv.ExceptionCheck(env) & 0xff == 0) return false;
			Jni.JniEnv.ExceptionClear(env);
			return true;
		}
		var open = method(cls("android/content/ContentResolver"), "openInputStream", "(Landroid/net/Uri;)Ljava/io/InputStream;");
		var stream = cls("java/io/InputStream"), readInto = method(stream, "read", "([B)I"), close = method(stream, "close", "()V");
		var chunk = Jni.JniEnv.NewByteArray(env, 65536), tmp = LibC.malloc(65536);
		for (u in uris) {
			Mem.setPtr(args, 0, u);
			var input = Jni.JniEnv.CallObjectMethodA(env, resolver, open, args);
			if (failed() || input.isNull()) {
				Jni.JniEnv.DeleteGlobalRef(env, u);
				continue;
			}
			var all = new haxe.io.BytesBuffer(), ok = true;
			while (true) {
				Mem.setPtr(args, 0, chunk);
				var got = Jni.JniEnv.CallIntMethodA(env, input, readInto, args);
				if (failed()) {
					ok = false;
					break;
				}
				if (got <= 0) break;
				Jni.JniEnv.GetByteArrayRegion(env, chunk, 0, got, tmp);
				var b = Bytes.alloc(got);
				BytesPtr.copyIn(b, 0, tmp, got);
				all.add(b);
			}
			Jni.JniEnv.CallVoidMethodA(env, input, close, args);
			failed();
			Jni.JniEnv.DeleteLocalRef(env, input);
			Jni.JniEnv.DeleteGlobalRef(env, u);
			if (ok) out.push(all.getBytes());
		}
		Jni.JniEnv.DeleteLocalRef(env, chunk);
		Jni.JniEnv.DeleteGlobalRef(env, resolver);
		LibC.free(tmp);
		LibC.free(args);
		return out;
	}

	// (f on this thread attached to the VM, detached after)
	static function attached<T>(f:Ptr->T):T {
		var vm = Mem.getPtr(Activity.activity, 8), out:Ptr<Ptr> = LibC.malloc(8);
		var ok = Jni.JavaVm.AttachCurrentThread(vm, out, Ptr.nil()) == 0;
		var env = out.value;
		LibC.free(out);
		if (!ok) throw "helder.os: Photos.pick: no VM for this thread";
		try {
			var r = f(env);
			Jni.JavaVm.DetachCurrentThread(vm);
			return r;
		} catch (e:Dynamic) {
			Jni.JavaVm.DetachCurrentThread(vm);
			throw e;
		}
	}
}
