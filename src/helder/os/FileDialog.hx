package helder.os;

import hxmc.Platform;

// The system's own dialog to pick a file to open, modal over a window:
// Windows' IFileOpenDialog (COM), macOS's NSOpenPanel, Linux's
// xdg-desktop-portal FileChooser over the session bus (the desktop's
// dialog: GTK's, KDE's). The path picked; null when cancelled or when the
// system has none to show (no portal, the browser, phones: the caller's own
// picker then: available says beforehand where it is known).
@:hxmc.unsafe(gc)
class FileDialog {
	public static function pick(window:Window, title:String, filters:Array<{name:String, extensions:Array<String>}>):Null<String>
		// (a headless run: the script's answer, helder.headless)
		return #if helder.headless helder.os.headless.Headless.run.fileDialog(title) #else if (Platform.apple() >= 1 || Platform.os() == 3 || Platform.target() >= 9) null else
			#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) helder.os.windows.FileOpenDialog.open(window.surface.handle, title, filters) else #end
			#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) helder.os.apple.OpenPanel.open(title, filters) else #end
			#if (!helder.os || helder.os == "linux") portal(window, title, filters) #else null #end #end;

	#if (!helder.os || helder.os == "linux")
	// (POSIX's calls behind a constant condition: Platform.os(), the other branches not linked)
	static function portal(window:Window, title:String, filters:Array<{name:String, extensions:Array<String>}>):Null<String> {
		var bus = helder.os.linux.DBus.session();
		if (bus == null) return null;
		var parent = "x11:" + StringTools.hex(window.surface.handle.toI64().toInt());
		var path = helder.os.linux.Portal.openFile(bus, parent, title, filters);
		bus.close();
		return path;
	}
	#end

	// whether a dialog can be shown (Linux: a portal on the session bus)
	public static function available():Bool
		return #if helder.headless true #else if (Platform.apple() >= 1 || Platform.os() == 3 || Platform.target() >= 9) false else if (Platform.os() == 1 || Platform.os() == 2) true else #if (!helder.os || helder.os == "linux") portalUp() #else false #end #end;

	#if (!helder.os || helder.os == "linux")
	static function portalUp():Bool {
		var bus = helder.os.linux.DBus.session();
		if (bus == null) return false;
		var r = bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", [helder.os.linux.Portal.DESTINATION], 2);
		bus.close();
		return r != null && r.body[0] == true;
	}
	#end
}
