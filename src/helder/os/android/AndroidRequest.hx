package helder.os.android;

import hxmc.unsafe.*;
import helder.async.Errors;

// org.hxmc.Request (helder.pack.android.Glue): what NativeActivity cannot
// get, permissions' answers and an activity's result, through a
// transparent activity of its own, started on top and finished once
// answered. On the main thread: start puts the request's extras on its
// intent; done gets the answer (code 0 and the grants, an int[]; or the
// result's code and intent), while that call lasts.
@:hxmc.android @:helder.android.dex("Request")
@:hxmc.unsafe(gc)
class AndroidRequest {
	static final pending = new Map<Int, (code:Int, data:Ptr) -> Void>();
	static var nextId = 1;
	static var cls = Ptr.nil();

	public static function start(extras:Ptr->Void, done:(code:Int, data:Ptr) -> Void) {
		if (cls.isNull()) {
			cls = Jni.cls("org.hxmc.Request");
			Jni.registerNatives(cls, [{name: "result", sig: "(IILjava/lang/Object;)V", fn: Callback.addr(result)}]);
		}
		var id = nextId++, intent = Jni.cls("android.content.Intent");
		var i = Jni.newObject(intent, Jni.method(intent, "<init>", "(Landroid/content/Context;Ljava/lang/Class;)V"), Jni.activity.toI64(), cls.toI64());
		var key = Jni.string("id");
		Jni.obj(i, Jni.method(intent, "putExtra", "(Ljava/lang/String;I)Landroid/content/Intent;"), key.toI64(), id);
		extras(i);
		pending.set(id, done);
		try
			Jni.call(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "startActivity", "(Landroid/content/Intent;)V"), i.toI64())
		catch (e:haxe.Exception) {
			pending.remove(id);
			throw Errors.kept(e);
		}
	}

	@:hxmc.callback static function result(env:Ptr, c:Ptr, id:Int, code:Int, data:Ptr):Void {
		var f = pending.get(id);
		pending.remove(id);
		if (f != null) try f(code, data) catch (e:Dynamic) Sys.println("helder.os: a request's answer: " + Std.string(e));
	}
}
