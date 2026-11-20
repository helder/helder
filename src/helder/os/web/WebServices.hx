package helder.os.web;

import helder.os.Permissions.Permission;
import helder.os.Permissions.PermissionStatus;
import hxmc.unsafe.*;

// The browser's side of Share and Permissions (src/helder/os/imports.mjs):
// what a promise answers comes back through answered, by the asking id.
// Permissions' states are the page's, queried when its module starts
// (navigator.permissions, Notification.permission) and kept as they change.
@:hxmc.unsafe(gc)
class WebServices {
	#if (hxmc.target == "wasm32-wasi")
	static final pending = new Map<Int, Int->Void>();
	static var nextId = 1;

	@:coroutine static function ask(start:(id:Int, done:Ptr) -> Void):Int
		return helder.os.Await.answer(done -> {
			var id = nextId++;
			pending.set(id, done);
			start(id, Callback.addr(answered));
		});

	@:hxmc.callback static function answered(id:Int, value:Int):Int {
		var f = pending.get(id);
		pending.remove(id);
		if (f != null) f(value);
		return 0;
	}

	public static function status(p:Permission):PermissionStatus
		return of(Services.permission_status(code(p)));

	@:coroutine public static function request(p:Permission):PermissionStatus {
		var c = code(p);
		return of(ask((id, done) -> Services.permission_request(c, done, id)));
	}

	@:coroutine public static function share(text:Null<String>, url:Null<String>, files:Array<String>):Bool {
		for (f in files) {
			var data = try sys.io.File.getBytes(f) catch (_:Dynamic) continue;
			var name = haxe.io.Path.withoutDirectory(f), type = @:privateAccess helder.os.Share.mime(f) ?? "application/octet-stream";
			Arena.scoped(a -> Services.share_file(a.cstring(name), hxmc.ReadOnlySpan.ofBytes(data), data.length, a.cstring(type)));
		}
		var t = text ?? "", u = url ?? "";
		return ask((id, done) -> Arena.scoped(a -> Services.share(a.cstring(t), a.cstring(u), done, id))) == 1;
	}

	static function code(p:Permission):Int
		return switch p {
			case Camera: 0;
			case Microphone: 1;
			case Photos: 2;
			case Location: 3;
			case Notifications: 4;
		}

	static function of(v:Int):PermissionStatus
		return switch v {
			case 0: Granted;
			case 1: Denied;
			case 2: Prompt;
			case _: Unsupported;
		}
	#else
	public static function status(p:Permission):PermissionStatus
		return Unsupported;

	#end
}

#if (hxmc.target == "wasm32-wasi")
@:hxmc.c @:hxmc.lib("hxmc_os") private extern class Services {
	// a permission's state (0 granted, 1 denied, 2 prompt, 3 unsupported); asked for, done(id, state)
	static function permission_status(p:Int):Int;
	static function permission_request(p:Int, done:Ptr, id:Int):Void;
	// a file for the next share (navigator.share's files, where canShare takes them), then the share: done(id, 1 shared, 0 not)
	@:hxmc.fast @:hxmc.len(data, n) static function share_file(name:CString, data:hxmc.ReadOnlySpan<UInt8>, n:Int, type:CString):Void;
	static function share(text:CString, url:CString, done:Ptr, id:Int):Void;
}
#end
