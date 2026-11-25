package helder.os.apple;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
import helder.os.apple.objc.*;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class MacTrash {
	public static function move(path:String):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var fm = MacPlaces.manager(), p = ObjC.str(path);
		var url = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), p);
		ObjC.release(p);
		var result = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8), error:Ptr<Ptr> = a.alloc(8);
			out.value = Ptr.nil();
			error.value = Ptr.nil();
			var ok = TrashMessage.send(fm, ObjC.sel("trashItemAtURL:resultingItemURL:error:"), url, out, error);
			return {
				ok: ok,
				path: ok ? MacPlaces.urlPath(out.value) : null,
				error: ok ? null : ObjC.string(Msg.id(error.value, ObjC.sel("localizedDescription")))
			};
		});
		Runtime.objc_autoreleasePoolPop(pool);
		if (!result.ok) throw "Trash: " + (result.error ?? path);
		return result.path;
	}
}

@:hxmc.c @:hxmc.lib("/usr/lib/libobjc.A.dylib") private extern class TrashMessage {
	@:native("objc_msgSend") static function send(self:Ptr, sel:Ptr, url:Ptr, result:Ptr<Ptr>, error:Ptr<Ptr>):Bool;
}
#end
