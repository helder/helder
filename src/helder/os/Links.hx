package helder.os;

#if (!helder.os || helder.os == "android")
import helder.os.android.Jni;
#end
#if (!helder.os || helder.os == "macos" || helder.os == "ios")
import helder.os.objc.*;
#end
#if (!helder.os || helder.os == "web")
import helder.os.web.Dom;
#end
import hxmc.Platform;
import hxmc.unsafe.*;

// A web page opened from the app: a link, a checkout, a help page. inApp
// (the default) keeps the user in the app where the system has a browser
// for that: iOS's SFSafariViewController, presented over the app's window
// (Done takes it away; SafariServices loaded when first asked); elsewhere,
// and with inApp false, the system's browser: iOS's and macOS's openURL
// (UIApplication's, NSWorkspace's), Android's ACTION_VIEW intent (no
// Custom Tabs: that is a library, not the system's), the browser's new tab
// (window.open), Windows' shell (url.dll's FileProtocolHandler), Linux's
// xdg-open. false: not opened (not a URL the system takes).
//
//   Links.open(cart.checkoutUrl);                // in the app on iOS
//   Links.open("https://helder.build", false);   // the browser
@:hxmc.unsafe(gc)
class Links {
	// how many were asked for: for tests
	@:noCompletion public static var opened(default, null) = 0;

	public static function open(url:String, inApp = true):Bool {
		opened++;
		#if (!helder.os || helder.os == "macos" || helder.os == "ios") if (Platform.os() == Platform.MACOS) return apple(url, inApp && Platform.apple() >= 1); #end
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == Platform.WASI) {
			Arena.scoped(a -> Dom.open_url(a.cstring(url)));
			return true;
		}
		#end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return android(url); #end
		return try {
			if (Platform.os() == Platform.WINDOWS) new sys.io.Process("rundll32", ["url.dll,FileProtocolHandler", url]) else new sys.io.Process("xdg-open", [url]);
			true;
		} catch (e:Dynamic) false;
	}

	#if (!helder.os || helder.os == "macos" || helder.os == "ios")
	// (AppKit's and UIKit's: the main thread's, OsThread)
	static function apple(url:String, inApp:Bool):Bool
		return OsThread.get(() -> appleNow(url, inApp));

	static function appleNow(url:String, inApp:Bool):Bool {
		var pool = Runtime.objc_autoreleasePoolPush();
		var u = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("URLWithString:"), Msg.id(ObjC.str(url), ObjC.sel("autorelease")));
		var ok = !u.isNull();
		if (ok) {
			if (Platform.apple() == 0) ok = Msg.bPtr(Msg.id(ObjC.cls("NSWorkspace"), ObjC.sel("sharedWorkspace")), ObjC.sel("openURL:"), u);
			#if (!helder.os || helder.os == "ios")
			else {
				var host = helder.os.uikit.UIKitWindow.controllerNow();
				var safari = inApp && !host.isNull() ? safariClass() : Ptr.nil();
				// (SFSafariViewController takes http and https only)
				var web = StringTools.startsWith(url, "https://") || StringTools.startsWith(url, "http://");
				if (!safari.isNull() && web) {
					var vc = Msg.id(Msg.idPtr(Msg.id(safari, ObjC.sel("alloc")), ObjC.sel("initWithURL:"), u), ObjC.sel("autorelease"));
					// (over what is shown already: a sheet the app presented)
					var top = host;
					while (true) {
						var p = Msg.id(top, ObjC.sel("presentedViewController"));
						if (p.isNull()) break;
						top = p;
					}
					Msg.vPtrBoolPtr(top, ObjC.sel("presentViewController:animated:completion:"), vc, true, Ptr.nil());
				} else
					Msg.vPtrPtrPtr(Msg.id(ObjC.cls("UIApplication"), ObjC.sel("sharedApplication")), ObjC.sel("openURL:options:completionHandler:"), u,
						Msg.id(ObjC.cls("NSDictionary"), ObjC.sel("dictionary")), Ptr.nil());
			}
			#end
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return ok;
	}

	static var safariLoaded = false;

	// (SafariServices, loaded the first time: an app that never opens a page does not)
	static function safariClass():Ptr {
		if (!safariLoaded) {
			safariLoaded = true;
			Arena.scoped(a -> Posix.dlopen(a.cstring("/System/Library/Frameworks/SafariServices.framework/SafariServices"), 1));
		}
		return ObjC.cls("SFSafariViewController");
	}

	#end

	#if (!helder.os || helder.os == "android")
	// (the activity's startActivity of an ACTION_VIEW intent, on Java's main thread)
	static function android(url:String):Bool {
		helder.os.android.MainThread.post(() -> {
			if (helder.os.android.Activity.activity.isNull()) return;
			var uri = Jni.cls("android.net.Uri"), intent = Jni.cls("android.content.Intent");
			var u = Jni.staticObj(uri, Jni.staticMethod(uri, "parse", "(Ljava/lang/String;)Landroid/net/Uri;"), Jni.string(url).toI64());
			var i = Jni.newObject(intent, Jni.method(intent, "<init>", "(Ljava/lang/String;Landroid/net/Uri;)V"), Jni.string("android.intent.action.VIEW").toI64(),
				u.toI64());
			Jni.call(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "startActivity", "(Landroid/content/Intent;)V"), i.toI64());
			Jni.check();
		});
		return true;
	}
	#end
}
