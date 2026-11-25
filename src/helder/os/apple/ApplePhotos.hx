package helder.os.apple;

import helder.os.Photos;
import helder.os.OsThread;
import helder.os.Await;
#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import haxe.io.Bytes;
import helder.os.apple.objc.*;
import hxmc.Platform;
import hxmc.objc.Block;
import hxmc.unsafe.*;

// iOS's PHPickerViewController (PhotosUI, loaded when first asked) over the
// app's window, images only, its delegate a class made at run time; each
// result's image data loaded (on the provider's queue: hxmc's blocks
// attach it), in the order picked. macOS: the open panel (Photos.dialog).
@:hxmc.unsafe(gc)
class ApplePhotos {
	static var delegate = Ptr.nil();
	static var picked:Null<Array<Bytes>->Void>;

	@:coroutine public static function pick(max:Int):Array<Bytes>
		return Await.answer(done -> Platform.apple() >= 1 ? ios(max, done) : done(Photos.dialog()));

	// (UIKit's: the main thread's, OsThread; the answer from any thread, as its loads end)
	static function ios(max:Int, done:Array<Bytes>->Void)
		OsThread.run(() -> iosNow(max, done));

	static function iosNow(max:Int, done:Array<Bytes>->Void) {
		var host = helder.os.apple.IosWindow.controllerNow();
		if (host.isNull()) return done([]);
		var pool = Runtime.objc_autoreleasePoolPush();
		var picker = @:privateAccess Permissions.load("PhotosUI", "PHPickerViewController");
		var config = Msg.id(Msg.id(Msg.id(ObjC.cls("PHPickerConfiguration"), ObjC.sel("alloc")), ObjC.sel("init")), ObjC.sel("autorelease"));
		Msg.vInt(config, ObjC.sel("setSelectionLimit:"), max);
		Msg.vPtr(config, ObjC.sel("setFilter:"), Msg.id(ObjC.cls("PHPickerFilter"), ObjC.sel("imagesFilter")));
		var vc = Msg.id(Msg.idPtr(Msg.id(picker, ObjC.sel("alloc")), ObjC.sel("initWithConfiguration:"), config), ObjC.sel("autorelease"));
		if (delegate.isNull()) {
			var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcPhotosDelegate"), 0);
			Runtime.class_addMethod(cls, ObjC.sel("picker:didFinishPicking:"), Callback.addr(finished), Mem.cstr("v@:@@"));
			Runtime.objc_registerClassPair(cls);
			delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		}
		Msg.vPtr(vc, ObjC.sel("setDelegate:"), delegate);
		picked = done;
		var top = host;
		while (true) {
			var p = Msg.id(top, ObjC.sel("presentedViewController"));
			if (p.isNull()) break;
			top = p;
		}
		Msg.vPtrBoolPtr(top, ObjC.sel("presentViewController:animated:completion:"), vc, true, Ptr.nil());
		Runtime.objc_autoreleasePoolPop(pool);
	}

	@:hxmc.callback static function finished(self:Ptr, cmd:Ptr, picker:Ptr, results:Ptr):Void {
		Msg.vBoolPtr(picker, ObjC.sel("dismissViewControllerAnimated:completion:"), true, Ptr.nil());
		var done = picked;
		picked = null;
		if (done == null) return;
		var n = Msg.i(results, ObjC.sel("count")).toInt();
		if (n == 0) return done([]);
		var all:Array<Null<Bytes>> = [for (_ in 0...n) null], left = n, lock = new sys.thread.Mutex();
		var type = ObjC.str("public.image");
		for (i in 0...n) {
			var provider = Msg.id(Msg.idInt(results, ObjC.sel("objectAtIndex:"), i), ObjC.sel("itemProvider"));
			var loaded:Block<(Ptr, Ptr) -> Void> = (data, _) -> {
				var b:Null<Bytes> = null;
				if (!data.isNull()) {
					var len = Msg.i(data, ObjC.sel("length")).toInt();
					b = Bytes.alloc(len);
					BytesPtr.copyIn(b, 0, Msg.id(data, ObjC.sel("bytes")), len);
				}
				lock.acquire();
				all[i] = b;
				var last = --left == 0;
				lock.release();
				if (last) done([for (x in all) if (x != null) x]);
			};
			Msg.idPtrPtr(provider, ObjC.sel("loadDataRepresentationForTypeIdentifier:completionHandler:"), type, cast loaded);
		}
		ObjC.release(type);
	}
}
#else
class ApplePhotos {}
#end
