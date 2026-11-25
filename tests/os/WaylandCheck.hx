import helder.os.*;
import helder.os.linux.wayland.WaylandWindow;
import helder.ui.UiWindow;
import hxmc.unsafe.*;

// helder.os on Wayland (`bun run test wayland`: under a headless weston,
// tests/os/wayland.sh): the back end chosen by WAYLAND_DISPLAY, a window
// configured by the compositor, GL's frames through EGL on its wl_surface
// read back (its background's colour), the buffer at the compositor's
// scale (weston --scale=2: twice the points), helder's own decorations
// where the compositor draws none, the title, fullscreen asked and
// configured (the output's size), the clipboard's text, text-input-v3's
// requests where the compositor has it, closed.
//   WaylandCheck [scale]
class WaylandCheck {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('WaylandCheck: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var scale = Sys.args().length > 0 ? Std.parseInt(Sys.args()[0]) : 1;
		check("Wayland chosen (WAYLAND_DISPLAY=" + Sys.getEnv("WAYLAND_DISPLAY") + ")", WaylandWindow.active());
		var w = new UiWindow({title: "WaylandCheck", width: 320, height: 200});
		w.background = helder.gfx.Color.rgb(0x2050A0);
		var native:WaylandWindow = @:privateAccess w.window.native;
		check("the surface: a wl_egl_window on the wl_display", w.window.surface.kind == Wayland && !w.window.surface.handle.isNull());
		check("configured by the compositor", @:privateAccess native.configured);
		Sys.println('WaylandCheck: decorations: ${@:privateAccess native.drawsBar ? "helder's (no xdg-decoration, or client-side asked)" : "the compositor's"}');
		var frames = 0, resized = 0, start = haxe.Timer.stamp(), pixels:Null<haxe.io.Bytes> = null, phase = 0;
		w.window.title = "WaylandCheck ✓";
		w.onFrame = () -> {
			frames++;
			if (phase == 0 && frames == 3) {
				// (the buffer: the points at the scale)
				check('the buffer at scale $scale', w.window.width == 320 * scale && w.window.height == 200 * scale && w.window.scale == scale,
					'${w.window.width}x${w.window.height} at ${w.window.scale}');
				pixels = haxe.io.Bytes.alloc(w.device.width * w.device.height * 4);
				w.capture = pixels;
				phase = 1;
			} else if (phase == 1 && frames == 4) {
				var i = ((w.device.height >> 1) * w.device.width + (w.device.width >> 1)) * 4;
				check("GL's frame through EGL: the background", Math.abs(pixels.get(i) - 0x20) <= 2 && Math.abs(pixels.get(i + 1) - 0x50) <= 2
					&& Math.abs(pixels.get(i + 2) - 0xA0) <= 2, '${pixels.get(i)},${pixels.get(i + 1)},${pixels.get(i + 2)}');
				Clipboard.write(w.window, "wayland ✓");
				var read:Null<String> = null;
				Clipboard.read(w.window, t -> read = t);
				check("the clipboard: its own text", read == "wayland ✓", read);
				// (text-input-v3 where the compositor has it: enabled, its state sent, no protocol error)
				var ti:Null<helder.os.linux.wayland.WaylandTextInput> = @:privateAccess WaylandWindow.textInput;
				if (ti == null) Sys.println("WaylandCheck: no zwp_text_input_manager_v3 here: text-input-v3 not checked under this compositor (WaylandTextInput.test.hx is)");
				else {
					w.window.startTextInput(20, 30, 1, 16);
					w.window.textContext("héllo", 2, 2);
					w.window.stopTextInput();
					var d = @:privateAccess WaylandWindow.display;
					helder.os.linux.wayland.WaylandClient.wl_display_roundtrip(d);
					check("text-input-v3: enabled, its state, disabled: no protocol error", helder.os.linux.wayland.WaylandClient.wl_display_get_error(d) == 0);
				}
				w.window.fullscreen = true;
				phase = 2;
				start = haxe.Timer.stamp();
			} else if (phase == 2 && (w.window.width > 320 * scale || haxe.Timer.stamp() - start > 3)) {
				check("fullscreen: the output's size", w.window.fullscreen && w.window.width > 320 * scale, '${w.window.width}x${w.window.height}');
				w.window.fullscreen = false;
				phase = 3;
				start = haxe.Timer.stamp();
			} else if (phase == 3 && (w.window.width == 320 * scale || haxe.Timer.stamp() - start > 3)) {
				check("fullscreen left: the size before", !w.window.fullscreen && w.window.width == 320 * scale, '${w.window.width}x${w.window.height}');
				w.close();
			}
			if (haxe.Timer.stamp() - start > 10) {
				check("in time", false, "phase " + phase);
				w.close();
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('WaylandCheck: ${failed == 0 ? "ok" : failed + " failed"}');
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
