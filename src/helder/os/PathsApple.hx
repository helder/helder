package helder.os;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.objc.*;
import hxmc.unsafe.*;

// NSFileManager's directories of the user's domain (an iOS app's are its
// container's), and its temporaryDirectory; the bundle's id.
@:hxmc.unsafe(gc)
class PathsApple {
	// (NSSearchPathDirectory: documents 9, caches 13, application support 14)
	public static function dir(which:Int):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		// (Foundation loaded: a bare executable may have none of its classes yet)
		var fm = Msg.id(@:privateAccess PermissionsApple.load("Foundation", "NSFileManager"), ObjC.sel("defaultManager"));
		var url = which == 0 ? Msg.id(fm, ObjC.sel("temporaryDirectory")) : Msg.id(Msg.idIntInt(fm, ObjC.sel("URLsForDirectory:inDomains:"), which, 1),
			ObjC.sel("lastObject"));
		var path = url.isNull() ? null : ObjC.string(Msg.id(url, ObjC.sel("path")));
		Runtime.objc_autoreleasePoolPop(pool);
		return path;
	}

	public static function bundleId():Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var id = ObjC.string(Msg.id(Msg.id(@:privateAccess PermissionsApple.load("Foundation", "NSBundle"), ObjC.sel("mainBundle")), ObjC.sel("bundleIdentifier")));
		Runtime.objc_autoreleasePoolPop(pool);
		return id;
	}
}
#else
class PathsApple {
	public static function dir(which:Int):Null<String>
		return null;

	public static function bundleId():Null<String>
		return null;
}
#end
