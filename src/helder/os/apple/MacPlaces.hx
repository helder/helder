package helder.os.apple;

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
import helder.os.Places;
import helder.os.Places.Place;
import helder.os.Places.Volume;
import helder.os.apple.objc.*;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class MacPlaces {
	public static function user():Array<Place> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var fm = manager(), result:Array<Place> = [];
		// (NSSearchPathDirectory, in Places' order; NSUserDomainMask)
		var dirs = [0, 12, 9, 15, 19, 17, 18];
		for (i in 0...dirs.length) {
			var path = i == 0 ? ObjC.string(Foundation.NSHomeDirectory()) : urlPath(Msg.id(
				Msg.idIntInt(fm, ObjC.sel("URLsForDirectory:inDomains:"), dirs[i], 1), ObjC.sel("firstObject")));
			if (path == null || !Places.directory(path)) continue;
			var p = ObjC.str(path);
			var name = ObjC.string(Msg.idPtr(fm, ObjC.sel("displayNameAtPath:"), p));
			ObjC.release(p);
			result.push({kind: Places.kinds[i], name: name ?? haxe.io.Path.withoutDirectory(path), path: path});
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return result;
	}

	public static function volumes():Array<Volume> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var fm = manager(), result:Array<Volume> = [];
		var keys = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("array"));
		var name = volumeKey("NSURLVolumeLocalizedNameKey"), removable = volumeKey("NSURLVolumeIsRemovableKey"),
			ejectable = volumeKey("NSURLVolumeIsEjectableKey"), local = volumeKey("NSURLVolumeIsLocalKey"),
			browsable = volumeKey("NSURLVolumeIsBrowsableKey"), total = volumeKey("NSURLVolumeTotalCapacityKey"),
			free = volumeKey("NSURLVolumeAvailableCapacityKey");
		for (key in [name, removable, ejectable, local, browsable, total, free])
			Msg.vPtr(keys, ObjC.sel("addObject:"), key);
		// (NSVolumeEnumerationSkipHiddenVolumes)
		var urls = Msg.idPtrInt(fm, ObjC.sel("mountedVolumeURLsIncludingResourceValuesForKeys:options:"), keys, 2);
		for (i in 0...Msg.i(urls, ObjC.sel("count")).toInt()) {
			var url = Msg.idInt(urls, ObjC.sel("objectAtIndex:"), i), path = urlPath(url);
			if (path == null) continue;
			var values = Msg.idPtrPtr(url, ObjC.sel("resourceValuesForKeys:error:"), keys, Ptr.nil());
			if (!Msg.b(value(values, browsable), ObjC.sel("boolValue"))) continue;
			var v:Volume = {
				name: ObjC.string(value(values, name)) ?? (path == "/" ? "Computer" : haxe.io.Path.withoutDirectory(path)),
				path: path,
				total: Msg.f(value(values, total), ObjC.sel("doubleValue")),
				free: Msg.f(value(values, free), ObjC.sel("doubleValue")),
				removable: Msg.b(value(values, removable), ObjC.sel("boolValue")) || Msg.b(value(values, ejectable), ObjC.sel("boolValue")),
				network: !Msg.b(value(values, local), ObjC.sel("boolValue")),
				root: path == "/"
			};
			if (v.root) result.unshift(v) else result.push(v);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return result;
	}

	@:allow(helder.os.apple.MacTrash) static function manager():Ptr
		return Msg.id(@:privateAccess helder.os.apple.Permissions.load("Foundation", "NSFileManager"), ObjC.sel("defaultManager"));

	@:allow(helder.os.apple.MacTrash) static inline function urlPath(url:Ptr):Null<String>
		return ObjC.string(Msg.id(url, ObjC.sel("path")));

	static inline function volumeKey(symbol:String):Ptr
		return Arena.scopedValue(a -> Mem.getPtr(Posix.dlsym(Ptr.ofI64(-2), a.cstring(symbol)), 0));

	static inline function value(values:Ptr, key:Ptr):Ptr
		return Msg.idPtr(values, ObjC.sel("objectForKey:"), key);
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/Foundation.framework/Foundation") private extern class Foundation {
	static function NSHomeDirectory():Ptr;
}
#end
