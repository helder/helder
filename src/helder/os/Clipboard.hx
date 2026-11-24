package helder.os;

#if (!helder.os || helder.os == "macos")
import helder.os.cocoa.CocoaWindow;
#end
#if (!helder.os || helder.os == "ios")
import helder.os.uikit.UIKitWindow;
#end
#if (!helder.os || helder.os == "web")
import helder.os.web.CanvasWindow;
#end
#if (!helder.os || helder.os == "windows")
import helder.os.win32.Win32Window;
#end
#if (!helder.os || helder.os == "linux")
import helder.os.x11.X11Window;
import helder.os.wayland.WaylandWindow;
#end
import hxmc.Platform;

// The system clipboard's text. write puts text there; read hands it to a
// callback (null: no text there), at once on Windows and macOS, after a
// round trip of events on X11; iOS: UIPasteboard (the CLIPBOARD selection's owner converts
// it) and in the browser (the paste event of the key press that asked, or
// navigator.clipboard.readText). The window is the one asking: on X11 it
// owns the selection while its text is the clipboard's. Android reads the
// focused activity's ClipboardManager.
// (each system's arm under its #if: helder.os, helder.compiler.Os)
class Clipboard {
	public static function write(window:Window, text:String) {
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) UIKitWindow.writeClipboard(text) else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) CocoaWindow.writeClipboard(text) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) (cast @:privateAccess window.native : Win32Window).writeClipboard(text) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) CanvasWindow.writeClipboard(text) else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) helder.os.android.AndroidClipboard.write(text) else #end
		#if (helder.headless && helder.os == "linux")
		held = text;
		#elseif (!helder.os || helder.os == "linux")
		if (Std.isOfType(@:privateAccess window.native, WaylandWindow)) (cast @:privateAccess window.native : WaylandWindow).writeClipboard(text) else
			(cast @:privateAccess window.native : X11Window).writeClipboard(text);
		#else {} #end
	}

	public static function read(window:Window, callback:Null<String>->Void) {
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) callback(UIKitWindow.readClipboard()) else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) callback(CocoaWindow.readClipboard()) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) callback((cast @:privateAccess window.native : Win32Window).readClipboard()) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) CanvasWindow.readClipboard(callback) else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) callback(helder.os.android.AndroidClipboard.read()) else #end
		#if (helder.headless && helder.os == "linux")
		callback(held);
		#elseif (!helder.os || helder.os == "linux")
		if (Std.isOfType(@:privateAccess window.native, WaylandWindow)) (cast @:privateAccess window.native : WaylandWindow).readClipboard(callback) else
			(cast @:privateAccess window.native : X11Window).readClipboard(callback);
		#else {} #end
	}

	#if (helder.headless && helder.os == "linux")
	// (a headless run's, on Linux: no display's selection, the program's own)
	static var held:Null<String> = null;
	#end
}
