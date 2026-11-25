package helder.os.linux.wayland;

import helder.os.linux.wayland.WaylandClient;
import helder.os.linux.wayland.protocol.WaylandProtocol;
import hxmc.unsafe.*;

// A frame's pixels into a Wayland window (Blit): two wl_shm buffers of
// one memfd, the one the compositor released written whole (ARGB8888: the
// frame's RGBA turned), attached, damaged where the frame changed,
// committed. The window's wl_surface is its Surface's handle in a
// -D helder.soft build (no wl_egl_window)
@:hxmc.unsafe(gc)
class WaylandBlit {
	final display:Ptr;
	final surface:WlSurface;
	var fd = -1;
	var map = Ptr.nil();
	var size = 0;
	var width = 0;
	var height = 0;
	final buffers:Array<WlBuffer> = [];
	final busy = [false, false];
	final listeners:Array<Int> = [];
	var next = 0;

	public function new(s:Surface) {
		display = s.display;
		surface = s.handle;
	}

	function resize(w:Int, h:Int) {
		if (w == width && h == height && fd >= 0) return;
		free();
		width = w;
		height = h;
		size = 4 * w * h;
		fd = WlLibc.memfd_create(Mem.cstr("helder-frame"), 1);
		if (fd < 0 || WlLibc.ftruncate(fd, 2 * size) != 0) throw "helder.os: no shared memory for a frame";
		map = WlLibc.mmap(Ptr.nil(), 2 * size, 3, 1, fd, 0);
		var pool = WaylandWindow.sharedMemory().createPool(fd, 2 * size);
		for (i in 0...2) {
			var b = pool.createBuffer(i * size, w, h, 4 * w, 0);
			var e = new WlBufferEvents();
			e.release = () -> busy[i] = false;
			listeners.push(b.listen(e));
			buffers.push(b);
			busy[i] = false;
		}
		pool.destroy();
	}

	function free() {
		for (l in listeners)
			Proxy.forget(l);
		for (b in buffers)
			b.destroy();
		listeners.resize(0);
		buffers.resize(0);
		if (fd >= 0) {
			WlLibc.munmap(map, 2 * size);
			Posix.close(fd);
		}
		fd = -1;
	}

	public function present(px:Ptr, w:Int, h:Int, rects:Null<Array<Int>>) {
		resize(w, h);
		// (both still the compositor's: its releases read first)
		var tries = 0;
		while (busy[0] && busy[1] && tries++ < 100 && WaylandClient.wl_display_roundtrip(display) >= 0) {}
		var i = busy[next] ? 1 - next : next;
		next = 1 - i;
		helder.os.Swizzle.bgra(map.add(i * size), px, w * h);
		busy[i] = true;
		surface.attach(buffers[i], 0, 0);
		if (rects == null) surface.damageBuffer(0, 0, w, h) else {
			var k = 0;
			while (k + 3 < rects.length) {
				surface.damageBuffer(rects[k], rects[k + 1], rects[k + 2] - rects[k], rects[k + 3] - rects[k + 1]);
				k += 4;
			}
		}
		surface.commit();
		WaylandClient.wl_display_flush(display);
	}

	public function dispose()
		free();
}
