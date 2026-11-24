package helder.os.win32;

import helder.os.win32.User32;
import hxmc.unsafe.*;

// A frame's pixels into a window (Blit): the frame kept as BGRA (a
// top-down DIB, turned where it changed), each changed rectangle copied out
// and drawn into the window's DC by StretchDIBits; the whole kept frame
// drawn again when Windows asks (paint: GDI keeps no window's pixels)
@:hxmc.unsafe(gc)
class Win32Blit {
	final hwnd:Ptr;
	final info:Ptr<BITMAPINFOHEADER>;
	var rows = Ptr.nil();
	var capacity = 0;
	var frame = Ptr.nil();
	var width = 0;
	var height = 0;

	public function new(s:Surface) {
		hwnd = s.handle;
		info = cast LibC.malloc(40);
		Mem.zero(info, 40);
	}

	public function present(px:Ptr, w:Int, h:Int, rects:Null<Array<Int>>) {
		if (w != width || h != height || frame.isNull()) {
			LibC.free(frame);
			frame = LibC.malloc((4 * w * h : hxmc.I64));
			width = w;
			height = h;
			rects = null;
		}
		var dc = User32.GetDC(hwnd);
		if (dc.isNull()) return;
		inline function put(x0:Int, y0:Int, x1:Int, y1:Int) {
			if (x0 < 0) x0 = 0;
			if (y0 < 0) y0 = 0;
			if (x1 > w) x1 = w;
			if (y1 > h) y1 = h;
			var rw = x1 - x0, rh = y1 - y0;
			if (rw > 0 && rh > 0) {
				if (4 * rw * rh > capacity) {
					LibC.free(rows);
					capacity = 4 * rw * rh;
					rows = LibC.malloc((capacity : hxmc.I64));
				}
				for (y in 0...rh) {
					helder.os.Swizzle.bgra(frame.add(4 * ((y0 + y) * w + x0)), px.add(4 * ((y0 + y) * w + x0)), rw);
					LibC.memcpy(rows.add(4 * rw * y), frame.add(4 * ((y0 + y) * w + x0)), (4 * rw : hxmc.I64));
				}
				info.value.biSize = 40;
				info.value.biWidth = rw;
				info.value.biHeight = -rh;
				info.value.biPlanes = 1;
				info.value.biBitCount = 32;
				// (DIB_RGB_COLORS, SRCCOPY)
				Gdi32.StretchDIBits(dc, x0, y0, rw, rh, 0, 0, rw, rh, rows, info, 0, 0x00CC0020);
			}
		}
		if (rects == null) put(0, 0, w, h) else {
			var k = 0;
			while (k + 3 < rects.length) {
				put(rects[k], rects[k + 1], rects[k + 2], rects[k + 3]);
				k += 4;
			}
		}
		Gdi32.GdiFlush();
		User32.ReleaseDC(hwnd, dc);
	}

	// the kept frame into a DC whole
	public function paint(dc:Ptr) {
		if (frame.isNull() || dc.isNull()) return;
		info.value.biSize = 40;
		info.value.biWidth = width;
		info.value.biHeight = -height;
		info.value.biPlanes = 1;
		info.value.biBitCount = 32;
		Gdi32.StretchDIBits(dc, 0, 0, width, height, 0, 0, width, height, frame, info, 0, 0x00CC0020);
	}

	public function dispose() {
		LibC.free(frame);
		LibC.free(rows);
		LibC.free(info);
	}
}

// (the compositor's next frame waited for: a present paced as a swap chain's)
@:hxmc.c @:hxmc.lib("dwmapi") extern class Dwm {
	static function DwmFlush():Int;
}
