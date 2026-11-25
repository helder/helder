import helder.gfx.shader.Vec4;
import helder.gfx.*;
import helder.os.*;

// A -D helder.soft window on Wayland (tests/os/wayland.sh): frames of the
// CPU's back end shown by helder.os.Blit (wl_shm buffers on the window's
// wl_surface), the compositor's screenshot (weston-screenshooter) then
// holding the window's colour where the window is.
class SoftWaylandCheck {
	static function main() {
		var w = new Window("SoftWaylandCheck", 160, 120);
		var device = Device.create(w.surface);
		var pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 0, 1, 1)}]};
		var frames = 0, start = haxe.Timer.stamp(), ok = false, tries = 0, last = 0.0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			enc.beginPass(pass);
			enc.endPass();
			device.endFrame();
			var now = haxe.Timer.stamp();
			if (++frames < 10 || now - start < 1 || now - last < 0.25) return;
			// (the compositor's output may not hold the window yet: looked at
			// again, frames presented meanwhile, up to 8 times)
			last = now;
			ok = check(device.width * device.height, ++tries);
			if (ok || tries == 8) App.quit();
		}, e -> if (e.kind == Close) App.quit());
		device.dispose();
		w.close();
		Sys.exit(ok ? 0 : 1);
	}

	// (the compositor's output: at least the window's pixels magenta)
	static function check(pixels:Int, tries:Int):Bool {
		var dir = haxe.io.Path.join([Sys.getEnv("XDG_RUNTIME_DIR") ?? "/tmp", "soft-shot"]);
		sys.FileSystem.createDirectory(dir);
		for (f in sys.FileSystem.readDirectory(dir))
			sys.FileSystem.deleteFile(haxe.io.Path.join([dir, f]));
		var cwd = Sys.getCwd();
		Sys.setCwd(dir);
		var code = Sys.command("timeout", ["10", "weston-screenshooter"]);
		Sys.setCwd(cwd);
		var shots = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f];
		if (code != 0 || shots.length == 0) {
			Sys.println("SoftWaylandCheck: FAIL: no screenshot");
			return false;
		}
		var png = Png.decode(sys.io.File.getBytes(haxe.io.Path.join([dir, shots[0]])));
		var magenta = 0;
		for (i in 0...png.width * png.height)
			if (png.rgba.get(4 * i) == 255 && png.rgba.get(4 * i + 1) == 0 && png.rgba.get(4 * i + 2) == 255) magenta++;
		var ok = magenta >= pixels;
		if (!ok && tries < 8) return false;
		Sys.println('SoftWaylandCheck: ${ok ? "ok" : "FAIL"}: $magenta magenta pixels on the ${png.width}x${png.height} screen, the window has $pixels (screenshot $tries)');
		return ok;
	}
}
