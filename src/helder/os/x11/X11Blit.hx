package helder.os.x11;

import helder.os.x11.Xlib;
import hxmc.unsafe.*;

// A frame's pixels into an X11 window (Blit): an XImage over memory the
// server reads (MIT-SHM, where the display is this machine's and the
// server has the extension: XShmPutImage, no copy through the socket),
// else XPutImage; the frame's RGBA turned to the visual's BGRX (24-bit
// TrueColor, 32 bits a pixel) where it changed
@:hxmc.unsafe(gc)
class X11Blit {
	final display:Ptr;
	final window:Int64;
	final gc:Ptr;
	final shared:Bool;
	var image:Ptr<XImage> = Ptr.nil();
	var data = Ptr.nil();
	var width = 0;
	var height = 0;
	// (XShmSegmentInfo: shmseg, shmid, shmaddr, readOnly)
	final info:Ptr;

	public function new(s:Surface) {
		display = s.display;
		window = s.handle.toI64();
		gc = Xlib.XCreateGC(display, window, 0, Ptr.nil());
		info = LibC.malloc(32);
		Mem.zero(info, 32);
		var name = Sys.getEnv("DISPLAY");
		shared = name != null && StringTools.startsWith(name, ":") && Sys.getEnv("HELDER_NO_SHM") == null
			&& Xext.XShmQueryExtension(display) != 0;
	}

	function resize(w:Int, h:Int) {
		if (w == width && h == height && !image.isNull()) return;
		free();
		width = w;
		height = h;
		var screen = Xlib.XDefaultScreen(display), visual = Xlib.XDefaultVisual(display, screen), depth = Xlib.XDefaultDepth(display, screen);
		if (shared) {
			image = Xext.XShmCreateImage(display, visual, depth, 2, Ptr.nil(), info, w, h);
			var id = Shm.shmget(0, (image.value.bytes_per_line * h : Int64), 0x200 | 0x180);
			if (id >= 0) {
				Mem.setI32(info, 8, id);
				data = Shm.shmat(id, Ptr.nil(), 0);
				Mem.setPtr(info, 16, data);
				Mem.setPtr(image, 16, data);
				Xext.XShmAttach(display, info);
				Xlib.XSync(display, 0);
				// (gone when the last detaches: this process's or the server's)
				Shm.shmctl(id, 0, Ptr.nil());
				return;
			}
			Mem.setPtr(image, 16, Ptr.nil());
			Xlib.XDestroyImage(image);
		}
		data = LibC.malloc((4 * w * h : Int64));
		image = Xlib.XCreateImage(display, visual, depth, 2, 0, data, w, h, 32, 4 * w);
	}

	function free() {
		if (image.isNull()) return;
		if (shared) {
			Xext.XShmDetach(display, info);
			Shm.shmdt(data);
		} else LibC.free(data);
		// (the data is ours, not the image's)
		Mem.setPtr(image, 16, Ptr.nil());
		Xlib.XDestroyImage(image);
		image = Ptr.nil();
		data = Ptr.nil();
	}

	public function present(px:Ptr, w:Int, h:Int, rects:Null<Array<Int>>) {
		resize(w, h);
		var stride = image.value.bytes_per_line;
		inline function put(x0:Int, y0:Int, x1:Int, y1:Int) {
			if (x0 < 0) x0 = 0;
			if (y0 < 0) y0 = 0;
			if (x1 > w) x1 = w;
			if (y1 > h) y1 = h;
			if (x1 <= x0 || y1 <= y0) return;
			for (y in y0...y1)
				Swizzle.bgra(data.add(y * stride + 4 * x0), px.add(4 * (y * w + x0)), x1 - x0);
			if (shared) Xext.XShmPutImage(display, window, gc, image, x0, y0, x0, y0, x1 - x0, y1 - y0, 0)
			else Xlib.XPutImage(display, window, gc, image, x0, y0, x0, y0, x1 - x0, y1 - y0);
		}
		if (rects == null) put(0, 0, w, h) else {
			var i = 0;
			while (i + 3 < rects.length) {
				put(rects[i], rects[i + 1], rects[i + 2], rects[i + 3]);
				i += 4;
			}
		}
		// (the server done with the memory before the next frame writes it)
		Xlib.XSync(display, 0);
	}

	public function dispose() {
		free();
		Xlib.XFreeGC(display, gc);
		LibC.free(info);
	}
}

// libXext.so.6: MIT-SHM's calls
@:hxmc.c @:hxmc.lib("libXext.so.6") extern class Xext {
	static function XShmQueryExtension(d:Ptr):Int;
	static function XShmCreateImage(d:Ptr, visual:Ptr, depth:Int, format:Int, data:Ptr, info:Ptr, width:Int, height:Int):Ptr<XImage>;
	static function XShmAttach(d:Ptr, info:Ptr):Int;
	static function XShmDetach(d:Ptr, info:Ptr):Int;
	static function XShmPutImage(d:Ptr, drawable:Int64, gc:Ptr, image:Ptr<XImage>, sx:Int, sy:Int, dx:Int, dy:Int, w:Int, h:Int, sendEvent:Int):Int;
}

// System V shared memory (IPC_PRIVATE, IPC_CREAT | 0600; IPC_RMID)
@:hxmc.c @:hxmc.lib("libc.so.6") extern class Shm {
	static function shmget(key:Int, size:Int64, flags:Int):Int;
	static function shmat(id:Int, addr:Ptr, flags:Int):Ptr;
	static function shmdt(addr:Ptr):Int;
	static function shmctl(id:Int, cmd:Int, buf:Ptr):Int;
}
