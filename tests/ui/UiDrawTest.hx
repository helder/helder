import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// The sample UI (Sample.hx) drawn headless by helder.ui.draw and compared
// with draw.png (GfxTest's rule: a pixel matches within TOLERANCE, at most
// MAX_OFF of them may not), on the target's GPU API (bun run test ui-draw;
// Linux: Mesa's llvmpipe on an EGL pbuffer):
//   UiDrawTest <golden.png> <out.png> [--bless | --dump | --window | --smoke]
// (--dump prints the laid-out tree; --window draws it in a UiWindow, X11
// under Xvfb on Linux, and compares the frame read back before its present;
// --smoke, for the machines without DejaVu Sans (Windows, macOS: CI's
// gfx-windows and gfx-macos): no golden image, but the system font found
// is printed and the card's paragraph must have drawn text)
class UiDrawTest {
	static inline var W = 480;
	static inline var H = 320;
	static inline var TOLERANCE = 3;
	static inline var MAX_OFF = 0.003;

	static function dump(n:Node, ind:String) {
		var extra = Std.isOfType(n, TextNode) ? ' "' + (cast n : TextNode).text.substr(0, 24) + '"' : "";
		Sys.println(ind + n.tag + " " + n.absX + "," + n.absY + " " + n.width + "x" + n.height + extra);
		for (c in n.children)
			dump(c, ind + "  ");
	}

	static var smoke = false;

	static function main() {
		var args = Sys.args();
		var golden = args[0], out = args[1], bless = args[2] == "--bless";
		if (args[2] == "--smoke") smoke = true;
		#if !(helder.soft && helder.headless)
		if (args[2] == "--window") {
			window(golden, out);
			return;
		}
		#end
		var ui = new Ui(new DrawText(), W, H);
		Sample.build(ui.root);
		var pixels = Bytes.alloc(W * H * 4);
		var t0 = haxe.Timer.stamp();
		ui.update();
		var t1 = haxe.Timer.stamp();
		if (args[2] == "--dump") dump(ui.root, "");
		var f = new DrawFrame(W, H);
		f.draw(ui, pixels);
		f.dispose();
		Sys.println('UiDrawTest ($f): layout ${Math.round((t1 - t0) * 1000)} ms, frame ${Math.round((haxe.Timer.stamp() - t1) * 1000)} ms');
		sys.io.File.saveBytes(out, Png.encode(pixels, W, H));
		if (bless) {
			sys.io.File.saveBytes(golden, Png.encode(pixels, W, H));
			Sys.println('UiDrawTest: blessed $golden');
			Sys.exit(0);
		}
		if (smoke) {
			var face = (cast ui.text : DrawText).face(ui.root.font());
			// the card's paragraph: dark text on white
			var dark = 0;
			for (y in 110...190)
				for (x in 170...450) {
					var o = 4 * (y * W + x);
					if (pixels.get(o) + pixels.get(o + 1) + pixels.get(o + 2) < 3 * 128) dark++;
				}
			var ok = dark > 400;
			Sys.println('UiDrawTest: smoke: the font ${face.family} ${face.subfamily}, $dark dark pixels in the paragraph: ' + (ok ? "ok" : "FAIL"));
			Sys.println('UiDrawTest: smoke: the system\'s appearance ' + (App.prefersDark() ? "dark" : "light"));
			Sys.exit(ok ? 0 : 1);
		}
		Sys.exit(compare(pixels, golden) && runs(ui) ? 0 : 1);
	}

	// a paragraph's glyph runs, as a document writer takes them: the face's
	// file, each glyph's source text (a ligature's two characters on it), placed as aligned
	static function runs(ui:Ui):Bool {
		var p = ui.text.layout("Hi, fine", ui.root.font(), Math.NaN);
		var rs = p.runs(p.width + 40, Center);
		var text = [for (r in rs) r.text.join("")].join(""), count = 0;
		for (r in rs)
			count += r.glyphs.length;
		var ok = rs.length >= 1 && text == "Hi, fine" && rs[0].font.data.length > 0 && rs[0].x[0] >= 20 && rs[0].y[0] > 0 && rs[0].size == ui.root.font().size;
		Sys.println('UiDrawTest: glyph runs ' + (ok ? "ok" : "FAIL") + ' (${rs.length} runs, $count glyphs for "$text", ${rs.length > 0 ? rs[0].font.family : ""})');
		return ok;
	}

	#if !(helder.soft && helder.headless)
	static function window(golden:String, out:String) {
		var w = new UiWindow("UiDrawTest", W, H);
		Sample.build(w.root);
		var pixels = Bytes.alloc(W * H * 4);
		var frames = 0;
		w.onFrame = () -> {
			frames++;
			// (frames 2 and 3 asked for: with nothing changed the window draws no more)
			if (frames < 3) w.ui.requestFrame();
			if (frames == 2) w.capture = pixels;
		};
		// UiWindow.run's loop, counting the turns with nothing to draw: each
		// sleeps (App.wait) until an event or 50 ms; closed after half a second idle
		var idle = 0, since = 0.0;
		App.run(() -> {
			if (w.needsFrame()) {
				w.frame();
				since = haxe.Timer.stamp();
			} else {
				idle++;
				App.wait(0.05);
				if (haxe.Timer.stamp() - since > 0.5) {
					#if (helder.soft && helder.os == "linux")
					shown(w, pixels);
					#end
					w.close();
				}
			}
		}, e -> w.handle(e));
		sys.io.File.saveBytes(out, Png.encode(pixels, W, H));
		var slept = frames == 3 && idle > 2 && idle < 40;
		Sys.println('UiDrawTest: window: $frames frames, then $idle turns idle, scale ${w.scale}' + (slept ? "" : " (FAIL: 3 frames and the loop asleep expected)"));
		Sys.exit(compare(pixels, golden) && slept && !failedShown ? 0 : 1);
	}
	#end

	#if (helder.soft && helder.os == "linux")
	// (-D helder.soft on X11: the window's pixels, as helder.os.Blit put them, the frame's)
	@:hxmc.unsafe(gc) static function shown(w:UiWindow, frame:Bytes) {
		var s = w.window.surface;
		if (s.kind != X11) return;
		var img = helder.os.linux.x11.Xlib.XGetImage(s.display, s.handle.toI64(), 0, 0, W, H, (-1 : hxmc.unsafe.Int64), 2);
		var differ = 0;
		for (y in 0...H) {
			var row = img.value.data.add(y * img.value.bytes_per_line);
			for (x in 0...W)
				for (k in 0...3)
					if (row[4 * x + 2 - k] != frame.get(4 * (y * W + x) + k)) differ++;
		}
		helder.os.linux.x11.Xlib.XDestroyImage(img);
		if (differ > 0) failedShown = true;
		Sys.println('UiDrawTest: window, X11 pixels: ' + (differ == 0 ? "ok (the frame's)" : 'FAIL ($differ channels differ from the frame)'));
	}
	#end

	static var failedShown = false;

	static function compare(pixels:Bytes, golden:String):Bool {
		var g = Png.decode(sys.io.File.getBytes(golden));
		if (g.width != W || g.height != H) {
			Sys.println('UiDrawTest: FAIL: the golden image is ${g.width}x${g.height}');
			return false;
		}
		var d = ImageDiff.of(pixels, g.rgba, W, H, TOLERANCE);
		var ok = d.within(MAX_OFF);
		Sys.println('UiDrawTest: ' + (ok ? "ok" : "FAIL") + ' ($d)');
		return ok;
	}
}
