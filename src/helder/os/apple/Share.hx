package helder.os.apple;

import helder.os.Await;
import helder.os.App;
#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
import helder.os.apple.objc.*;
import hxmc.Platform;
import hxmc.objc.Block;
import hxmc.unsafe.*;
#end

// The share sheet on Apple's systems: iOS's UIActivityViewController over
// the app's window (on an iPad a popover at its centre; saving an image
// only with Info.plist's NSPhotoLibraryAddUsageDescription, which it
// needs), whether the user shared; macOS's NSSharingServicePicker at the
// first window's centre, whether a service was chosen.
@:hxmc.unsafe(gc)
class Share {
	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
	@:coroutine public static function share(text:Null<String>, url:Null<String>, files:Array<String>):Bool {
		var items = Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("new"));
		var pool = Runtime.objc_autoreleasePoolPush();
		function add(o:Ptr)
			if (!o.isNull()) Msg.vPtr(items, ObjC.sel("addObject:"), o);
		if (text != null && text != "") add(Msg.id(ObjC.str(text), ObjC.sel("autorelease")));
		if (url != null && url != "") add(Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("URLWithString:"), Msg.id(ObjC.str(url), ObjC.sel("autorelease"))));
		for (f in files)
			add(Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), Msg.id(ObjC.str(sys.FileSystem.fullPath(f)), ObjC.sel("autorelease"))));
		Runtime.objc_autoreleasePoolPop(pool);
		var shared:Bool = Await.answer(done -> Platform.apple() >= 1 ? ios(items, done) : mac(items, done));
		ObjC.release(items);
		return shared;
	}

	// (UIKit's: the main thread's, OsThread; the answer from there too, which Await takes from any thread)
	static function ios(items:Ptr, done:Bool->Void)
		helder.os.OsThread.run(() -> iosNow(items, done));

	static function iosNow(items:Ptr, done:Bool->Void) {
		var host = helder.os.apple.IosWindow.controllerNow();
		if (host.isNull()) return done(false);
		var pool = Runtime.objc_autoreleasePoolPush();
		var vc = Msg.id(Msg.idPtrPtr(Msg.id(ObjC.cls("UIActivityViewController"), ObjC.sel("alloc")), ObjC.sel("initWithActivityItems:applicationActivities:"),
			items, Ptr.nil()), ObjC.sel("autorelease"));
		var key = ObjC.str("NSPhotoLibraryAddUsageDescription");
		if (Msg.idPtr(Msg.id(ObjC.cls("NSBundle"), ObjC.sel("mainBundle")), ObjC.sel("objectForInfoDictionaryKey:"), key).isNull()) {
			var save = Mem.getPtr(Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("UIActivityTypeSaveToCameraRoll")), 0);
			Msg.vPtr(vc, ObjC.sel("setExcludedActivityTypes:"), Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), save));
		}
		ObjC.release(key);
		var finished:Block<(Ptr, Bool, Ptr, Ptr) -> Void> = (_, completed, _, _) -> done(completed);
		Msg.vPtr(vc, ObjC.sel("setCompletionWithItemsHandler:"), cast finished);
		var top = host;
		while (true) {
			var p = Msg.id(top, ObjC.sel("presentedViewController"));
			if (p.isNull()) break;
			top = p;
		}
		var popover = Msg.id(vc, ObjC.sel("popoverPresentationController"));
		if (!popover.isNull()) {
			var view = Msg.id(top, ObjC.sel("view")), b = Msg.rect(view, ObjC.sel("bounds"));
			Msg.vPtr(popover, ObjC.sel("setSourceView:"), view);
			Arena.scoped(a -> {
				var r = a.make(CGRect);
				r.value.origin.x = b.size.width / 2;
				r.value.origin.y = b.size.height / 2;
				r.value.size.width = 0;
				r.value.size.height = 0;
				Msg.vRect(popover, ObjC.sel("setSourceRect:"), r.value);
			});
			Msg.vInt(popover, ObjC.sel("setPermittedArrowDirections:"), 0);
		}
		Msg.vPtrBoolPtr(top, ObjC.sel("presentViewController:animated:completion:"), vc, true, Ptr.nil());
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// (the picker and its delegate kept while it is shown: its delegate is weak)
	static var picker = Ptr.nil();
	static var delegate = Ptr.nil();
	static var chosen:Null<Bool->Void>;

	static function mac(items:Ptr, done:Bool->Void) {
		helder.os.OsThread.run(() -> {
			var w = App.windows[0];
			if (w == null) return done(false);
			var view = w.surface.handle;
			if (delegate.isNull()) {
				var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcShareDelegate"), 0);
				Runtime.class_addMethod(cls, ObjC.sel("sharingServicePicker:didChooseSharingService:"), Callback.addr(didChoose), Mem.cstr("v@:@@"));
				Runtime.objc_registerClassPair(cls);
				delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
			}
			ObjC.release(picker);
			picker = Msg.idPtr(Msg.id(ObjC.cls("NSSharingServicePicker"), ObjC.sel("alloc")), ObjC.sel("initWithItems:"), items);
			Msg.vPtr(picker, ObjC.sel("setDelegate:"), delegate);
			chosen = done;
			var b = Msg.rect(view, ObjC.sel("bounds"));
			Arena.scoped(a -> {
				var r = a.make(CGRect);
				r.value.origin.x = b.size.width / 2;
				r.value.origin.y = b.size.height / 2;
				r.value.size.width = 1;
				r.value.size.height = 1;
				// (NSRectEdgeMinY)
				Msg.vRectPtrInt(picker, ObjC.sel("showRelativeToRect:ofView:preferredEdge:"), r.value, view, 1);
			});
		});
	}

	@:hxmc.callback static function didChoose(self:Ptr, cmd:Ptr, p:Ptr, service:Ptr):Void {
		var f = chosen;
		chosen = null;
		if (f != null) f(!service.isNull());
	}
	#end
}
