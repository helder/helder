package helder.os;

#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import haxe.io.Bytes;
import helder.os.objc.*;
import hxmc.unsafe.*;

// iOS's UIImagePickerController over the app's window, its source the
// camera (none on the simulator: null at once), its delegate a class made
// at run time; the photo taken as UIImageJPEGRepresentation's JPEG
// (quality 0.9, the orientation in its EXIF).
@:hxmc.unsafe(gc)
class CameraApple {
	static var delegate = Ptr.nil();
	static var taken:Null<Null<Bytes>->Void>;

	@:coroutine public static function take(front:Bool):Null<Bytes>
		return Await.answer(done -> show(front, done));

	// (UIKit's: the main thread's, OsThread; the answer from there too, which Await takes from any thread)
	static function show(front:Bool, done:Null<Bytes>->Void)
		OsThread.run(() -> showNow(front, done));

	static function showNow(front:Bool, done:Null<Bytes>->Void) {
		var host = helder.os.uikit.UIKitWindow.controllerNow(), picker = ObjC.cls("UIImagePickerController");
		// (UIImagePickerControllerSourceTypeCamera 1; UIImagePickerControllerCameraDeviceFront 1)
		if (host.isNull() || !Msg.bInt(picker, ObjC.sel("isSourceTypeAvailable:"), 1)) return done(null);
		var pool = Runtime.objc_autoreleasePoolPush();
		var vc = Msg.id(Msg.id(Msg.id(picker, ObjC.sel("alloc")), ObjC.sel("init")), ObjC.sel("autorelease"));
		Msg.vInt(vc, ObjC.sel("setSourceType:"), 1);
		if (front && Msg.bInt(picker, ObjC.sel("isCameraDeviceAvailable:"), 1)) Msg.vInt(vc, ObjC.sel("setCameraDevice:"), 1);
		if (delegate.isNull()) {
			var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcCameraDelegate"), 0);
			Runtime.class_addMethod(cls, ObjC.sel("imagePickerController:didFinishPickingMediaWithInfo:"), Callback.addr(finished), Mem.cstr("v@:@@"));
			Runtime.class_addMethod(cls, ObjC.sel("imagePickerControllerDidCancel:"), Callback.addr(cancelled), Mem.cstr("v@:@"));
			Runtime.objc_registerClassPair(cls);
			delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		}
		Msg.vPtr(vc, ObjC.sel("setDelegate:"), delegate);
		taken = done;
		var top = host;
		while (true) {
			var p = Msg.id(top, ObjC.sel("presentedViewController"));
			if (p.isNull()) break;
			top = p;
		}
		Msg.vPtrBoolPtr(top, ObjC.sel("presentViewController:animated:completion:"), vc, true, Ptr.nil());
		Runtime.objc_autoreleasePoolPop(pool);
	}

	static function answer(picker:Ptr, photo:Null<Bytes>) {
		Msg.vBoolPtr(picker, ObjC.sel("dismissViewControllerAnimated:completion:"), true, Ptr.nil());
		var done = taken;
		taken = null;
		if (done != null) done(photo);
	}

	@:hxmc.callback static function finished(self:Ptr, cmd:Ptr, picker:Ptr, info:Ptr):Void {
		var key = Mem.getPtr(Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("UIImagePickerControllerOriginalImage")), 0);
		var image = Msg.idPtr(info, ObjC.sel("objectForKey:"), key);
		var jpeg = Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("UIImageJPEGRepresentation"));
		var data = image.isNull() || jpeg.isNull() ? Ptr.nil() : Jpeg.call(jpeg, image, 0.9);
		var photo:Null<Bytes> = null;
		if (!data.isNull()) {
			var len = Msg.i(data, ObjC.sel("length")).toInt();
			photo = Bytes.alloc(len);
			BytesPtr.copyIn(photo, 0, Msg.id(data, ObjC.sel("bytes")), len);
		}
		answer(picker, photo);
	}

	@:hxmc.callback static function cancelled(self:Ptr, cmd:Ptr, picker:Ptr):Void
		answer(picker, null);
}

@:hxmc.c private extern class Jpeg {
	@:hxmc.indirect static function call(f:Ptr, image:Ptr, quality:Float):Ptr;
}
#else
class CameraApple {}
#end
