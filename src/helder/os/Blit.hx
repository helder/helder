package helder.os;

import hxmc.unsafe.Ptr;

// A frame drawn on the CPU (RGBA8, premultiplied, rows top to bottom, w
// by h) shown in a window by the system's own path, no GPU API (helder.gfx's
// CPU back end, helder.ui's CPU canvas: -D helder.soft): X11 an XImage
// (MIT-SHM where the server shares memory), Wayland a wl_shm buffer, macOS
// a CGImage as the view's layer's contents, Windows StretchDIBits, the web
// putImageData; only the rectangles that changed (x0, y0, x1, y1 each;
// null: all of it) where the system takes them. Kept by surface.
@:hxmc.unsafe(gc)
class Blit {
	// (each surface's, made at its first frame: the program's thread may be another than the main one)
	#if (helder.os == "linux")
	static var x11:Null<haxe.ds.ObjectMap<Surface, helder.os.x11.X11Blit>> = null;
	static var wayland:Null<haxe.ds.ObjectMap<Surface, helder.os.wayland.WaylandBlit>> = null;
	#elseif (helder.os == "macos")
	static var cocoa:Null<haxe.ds.ObjectMap<Surface, helder.os.cocoa.CocoaBlit>> = null;
	#elseif (helder.os == "windows")
	static var win32:Null<haxe.ds.ObjectMap<Surface, helder.os.win32.Win32Blit>> = null;
	#end

	public static function present(s:Surface, px:Ptr, w:Int, h:Int, rects:Null<Array<Int>>) {
		made();
		#if (helder.os == "linux")
		if (s.kind == X11) {
			var b = x11.get(s);
			if (b == null) x11.set(s, b = new helder.os.x11.X11Blit(s));
			b.present(px, w, h, rects);
		} else if (s.kind == Wayland) {
			var b = wayland.get(s);
			if (b == null) wayland.set(s, b = new helder.os.wayland.WaylandBlit(s));
			b.present(px, w, h, rects);
		}
		#elseif (helder.os == "macos")
		if (s.kind != Cocoa) return;
		var b = cocoa.get(s);
		if (b == null) cocoa.set(s, b = new helder.os.cocoa.CocoaBlit(s));
		b.present(px, w, h, rects);
		#elseif (helder.os == "windows")
		if (s.kind != Win32) return;
		var b = win32.get(s);
		if (b == null) win32.set(s, b = new helder.os.win32.Win32Blit(s));
		b.present(px, w, h, rects);
		#elseif (helder.os == "web")
		if (s.kind == Canvas) helder.os.web.Dom.put_pixels(s.handle.toI64().toInt(), px, w, h);
		#end
		if (s.onPresent != null) s.onPresent();
	}

	// the last frame shown again where the system lost it (X11: an Expose;
	// Windows: WM_PAINT, WM_PRINTCLIENT into their DC): neither keeps a
	// window's pixels as a GPU's swap chain does
	public static function repaint(s:Surface, dc:Ptr) {
		#if (helder.os == "linux")
		made();
		var b = x11.get(s);
		if (b != null) b.repaint();
		#elseif (helder.os == "windows")
		made();
		var b = win32.get(s);
		if (b != null) b.paint(dc);
		#end
	}

	static function made() {
		#if (helder.os == "linux")
		if (x11 == null) x11 = new haxe.ds.ObjectMap();
		if (wayland == null) wayland = new haxe.ds.ObjectMap();
		#elseif (helder.os == "macos")
		if (cocoa == null) cocoa = new haxe.ds.ObjectMap();
		#elseif (helder.os == "windows")
		if (win32 == null) win32 = new haxe.ds.ObjectMap();
		#end
	}

	// the surface's memory let go (its window closing)
	public static function forget(s:Surface) {
		made();
		#if (helder.os == "linux")
		var b = x11.get(s);
		if (b != null) b.dispose();
		x11.remove(s);
		var b = wayland.get(s);
		if (b != null) b.dispose();
		wayland.remove(s);
		#elseif (helder.os == "macos")
		var b = cocoa.get(s);
		if (b != null) b.dispose();
		cocoa.remove(s);
		#elseif (helder.os == "windows")
		var b = win32.get(s);
		if (b != null) b.dispose();
		win32.remove(s);
		#end
	}
}
