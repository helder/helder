package helder.os.android;

import haxe.io.Bytes;
import helder.os.Permissions.Permission;
import hxmc.unsafe.*;

// The system's camera app (MediaStore.ACTION_IMAGE_CAPTURE) started for
// its result through org.hxmc.Request, the photo written where EXTRA_OUTPUT
// says: a file of the app's cache served by org.hxmc.Files
// (content://<package>.hxmc.files<path>, write-granted to the camera app
// while it is taken), then read on a thread of its own. The camera app
// needs no permission, unless the manifest has CAMERA (the program asks
// for it elsewhere): then it is asked for first, and the photo is not
// taken without it.
@:hxmc.android @:helder.android.dex("Request", "Files")
@:hxmc.unsafe(gc)
class Camera {
	@:coroutine public static function take(front:Bool):Null<Bytes> {
		var declared = false;
		MainThread.run(() -> declared = try AndroidPermissions.declared("android.permission.CAMERA") catch (_:Dynamic) false);
		if (declared && AndroidPermissions.request(Permission.Camera) != Granted) return null;
		var dir = Paths.dir("cache");
		if (dir == null) return null;
		var path = dir + "/hxmc-camera-" + StringTools.hex(Std.random(0x7fffffff)) + ".jpg";
		var taken:Bool = helder.os.Await.answer(done -> MainThread.post(() -> {
			try {
				var uri = Share.serve(path, true);
				AndroidRequest.start(i -> {
					Jni.obj(i, Jni.method(Jni.cls("android.content.Intent"), "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"),
						Jni.string("intent").toI64(), capture(uri, front).toI64());
				}, (code, _) -> {
					Share.serve(path, false);
					done(code == -1);
				});
			} catch (e:Dynamic) {
				Sys.println("helder.os: Photos.take: " + Std.string(e));
				done(false);
			}
		}));
		var photo:Null<Bytes> = taken ? helder.os.Await.answer(done -> sys.thread.Thread.create(() -> done(try sys.io.File.getBytes(path) catch (_:Dynamic) null))) : null;
		try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
		return photo == null || photo.length == 0 ? null : photo;
	}

	static function capture(uri:Ptr, front:Bool):Ptr {
		var cls = Jni.cls("android.content.Intent");
		var i = Jni.newObject(cls, Jni.method(cls, "<init>", "(Ljava/lang/String;)V"), Jni.string("android.media.action.IMAGE_CAPTURE").toI64());
		Jni.obj(i, Jni.method(cls, "putExtra", "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;"), Jni.string("output").toI64(), uri.toI64());
		// (the grant goes with the ClipData: FLAG_GRANT_READ_URI_PERMISSION | FLAG_GRANT_WRITE_URI_PERMISSION)
		var clip = Jni.cls("android.content.ClipData");
		Jni.call(i, Jni.method(cls, "setClipData", "(Landroid/content/ClipData;)V"),
			Jni.staticObj(clip, Jni.staticMethod(clip, "newRawUri", "(Ljava/lang/CharSequence;Landroid/net/Uri;)Landroid/content/ClipData;"), Jni.string("").toI64(),
				uri.toI64()).toI64());
		Jni.obj(i, Jni.method(cls, "addFlags", "(I)Landroid/content/Intent;"), 3);
		// (no standard extra: the ones camera apps read)
		if (front) {
			var int = Jni.method(cls, "putExtra", "(Ljava/lang/String;I)Landroid/content/Intent;");
			Jni.obj(i, int, Jni.string("android.intent.extras.CAMERA_FACING").toI64(), 1);
			Jni.obj(i, int, Jni.string("android.intent.extras.LENS_FACING_FRONT").toI64(), 1);
			Jni.obj(i, Jni.method(cls, "putExtra", "(Ljava/lang/String;Z)Landroid/content/Intent;"), Jni.string("android.intent.extra.USE_FRONT_CAMERA").toI64(), 1);
		}
		return i;
	}
}
