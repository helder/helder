import haxe.io.Bytes;
import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.VideoNode;
import helder.os.OsThread;
import helder.os.windows.User32;
import helder.ui.Clock;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import hxmc.unsafe.*;

// A <video> on Windows (the window lane on a Windows host): quads.mp4's
// flat quadrants in a box in a scroller, drawn by helder or (layer) on its
// system layer (a swap chain in DirectComposition's slot: WinLayer),
// played until six frames were shown, sought to 0.25 s and paused; the
// frame at 0.2 shown for ten frames, then the window's pixels (PrintWindow,
// which composes DirectComposition's content) read at the quadrants'
// centres against the source's colours as ffmpeg decodes them: within 8
// levels both ways (helder's conversion on the GPU, WinLayer's on the CPU,
// DWM showing its values as they are). Where the layer did not show it
// (no system layers), said and checked as drawn. PrintWindow is DWM's
// composition of the window as it draws it for a capture, not the
// display's: a real display (not CI's runner) settles the layer's pixels.
//   WinVideoStillCheck drawn|layer [dir]
@:hxmc.unsafe(gc)
class WinVideoStillCheck implements Markup {
	static inline var FRAMES = 6;
	static inline var LEVELS = 8;
	static final SOURCE = [[254, 0, 0], [0, 255, 1], [0, 0, 255], [128, 128, 128]];

	static function say(s:String)
		Sys.println("WinVideoStillCheck: " + s);

	static function main() {
		// (layer-unit: the scroller drawing a background of its own, a unit
		// of the layers, the video's slot in it; layer: the scroller drawing
		// nothing, the slot a unit of its own)
		var args = Sys.args(), unit = args[0] == "layer-unit", layer = args[0] == "layer" || unit, dir = args.length > 1 ? args[1] : null;
		var node:Null<VideoNode> = null, shown = 0, last = -1.0, phase = 0, at = 0.0, ticks = 0, start = haxe.Timer.stamp();
		function onLayer(n:VideoNode):Bool {
			var s = @:privateAccess n.sample;
			return s != null && s.showing;
		}
		function wants(n:VideoNode):Bool
			return layer && @:privateAccess n.ui.layered;
		function step(_:Float):Bool {
			var n = node, now = haxe.Timer.stamp();
			var p = n == null ? null : n.player;
			if (now - start > 60) {
				say("FAIL: timed out");
				Sys.exit(1);
			}
			if (p == null || !p.loaded()) {
				if (p != null && p.error() != null) {
					say('FAIL: ${p.error()}');
					Sys.exit(1);
				}
				return true;
			}
			var f = p.shown;
			switch phase {
				case 0:
					n.play();
					at = now;
					phase = 1;
				case 1:
					if (f != null && f.time != last) {
						last = f.time;
						shown++;
					}
					if (shown >= FRAMES && (!wants(n) || onLayer(n) || now - at > 10) || now - at > 30) {
						say('played: $shown frames shown in ${Math.round((now - at) * 10) / 10} s, on the system layer ${onLayer(n)}');
						n.pause();
						n.seek(0.25);
						phase = 2;
						ticks = 0;
						at = now;
					}
				case 2:
					if (f != null && f.time == 0.2 && (!wants(n) || onLayer(n) || now - at > 10)) ticks++ else ticks = 0;
					if (ticks >= 10 || now - at > 30) {
						phase = 3;
						Clock.after(0.3, () -> done(n, f == null ? -1 : f.time, onLayer(n), layer, dir, unit));
					}
				case _:
			}
			n.ui.requestFrame();
			return true;
		}
		UiWindow.run(<Surface title="WinVideoStillCheck" width={400} height={360} background="#333333">
			<view flexGrow={1} paddingTop={40} paddingLeft={40} overflow="scroll" background={unit ? "#222222" : null}>
				<video src={new MemorySource(Asset.embed("tests/media/apple/quads.mp4"))} width={320} height={240} layer={layer} muted={true} loop={true}
					onError={e -> say('error $e')} ref={v -> {
						node = v;
						Clock.addFor(v, step);
					}}/>
				<view height={400}/>
			</view>
		</Surface>);
	}

	// (the still read: the box in pixels, the quadrants' centres of the
	// picture contained in it (64 x 48))
	static function done(n:VideoNode, time:Float, onLayer:Bool, layer:Bool, dir:Null<String>, unit:Bool) {
		var w = @:privateAccess UiWindow.open[0], k = n.ui.scale;
		var width = w.device.width, height = w.device.height;
		var px = capture(w.window, width, height);
		var how = onLayer ? "on the system layer" : "drawn by helder";
		if (layer && !onLayer) say('note: the system layer did not show it (layered ${@:privateAccess n.ui.layered}): drawn by helder');
		if (px == null) {
			say("FAIL: no capture");
			Sys.exit(1);
		}
		if (dir != null) sys.io.File.saveBytes('$dir/still-${layer ? "layer" : "drawn"}.rgba', px);
		// (the window's own background beside the box: whether the capture has the window at all)
		var bg = (20 * width + 20) * 4;
		// (the window's background beside the box: the markup's string,
		// "#333333", parsed (UiWindow.colour), shown on both reads; in
		// layer-unit's scroller, its own #222222 there)
		var back:Int = w.background, shows = unit ? 0xFF222222 : back, want = [shows >> 16 & 0xFF, shows >> 8 & 0xFF, shows & 0xFF];
		function off(px:Bytes):Int
			return Std.int(Math.max(Math.abs(px.get(bg) - want[0]), Math.max(Math.abs(px.get(bg + 1) - want[1]), Math.abs(px.get(bg + 2) - want[2]))));
		var x = n.absX * k, y = n.absY * k, bw = n.width * k, bh = n.height * k;
		var s = Math.min(bw / 64, bh / 48), x0 = x + (bw - 64 * s) / 2, y0 = y + (bh - 48 * s) / 2;
		// (the quadrants' centres of a capture: the largest difference from the source, the colours read)
		function read(px:Bytes):{worst:Int, got:String} {
			var worst = 0, got = [];
			for (i => q in [[16, 12], [48, 12], [16, 36], [48, 36]]) {
				var at = (Math.round(y0 + (q[1] + 0.5) * s) * width + Math.round(x0 + (q[0] + 0.5) * s)) * 4;
				var c = [px.get(at), px.get(at + 1), px.get(at + 2)];
				for (j in 0...3) worst = Std.int(Math.max(worst, Math.abs(c[j] - SOURCE[i][j])));
				got.push(c.join(" "));
			}
			return {worst: worst, got: got.join(", ")};
		}
		var printed = read(px), shown = capture(w.window, width, height, true);
		var onScreen = shown == null ? {worst: 255, got: "none"} : read(shown);
		var backOk = back == 0xFF333333 && off(px) <= LEVELS && shown != null && off(shown) <= LEVELS;
		say('${backOk ? "ok" : "FAIL"}: the background at 20,20: PrintWindow ${px.get(bg)} ${px.get(bg + 1)} ${px.get(bg + 2)}, the screen ${shown == null ? "none" : shown.get(bg) + " " + shown.get(bg + 1) + " " + shown.get(bg + 2)} (the window\'s 0x${StringTools.hex(back, 8)}, the markup\'s 0xFF333333; shown there 0x${StringTools.hex(shows, 8)})');
		var name = unit ? "layer in a scroller of its own" : layer ? "layer" : "drawn";
		var ok = printed.worst <= LEVELS && onScreen.worst <= LEVELS && time == 0.2 && backOk;
		say('${ok ? "ok" : "FAIL"}: $name: the frame at $time $how; PrintWindow\'s quadrants ${printed.got} (at most ${printed.worst} off); the screen\'s ${onScreen.got} (at most ${onScreen.worst} off; the source within $LEVELS)');
		Sys.exit(ok ? 0 : 1);
	}

	// (the client area's pixels as RGBA, on the main thread: PrintWindow,
	// which composes the window's DirectComposition content, else the
	// screen's where the window is: WinLayersWindowCheck's)
	static function capture(w:helder.os.Window, width:Int, height:Int, screen = false):Null<Bytes> {
		var hwnd = w.surface.handle;
		return OsThread.get(() -> {
			var rgba:Null<Bytes> = null;
			Arena.scoped(a -> {
				var desk = User32.GetDC(Ptr.nil());
				var dc = Gdi32.CreateCompatibleDC(desk);
				var info = a.make(BITMAPINFOHEADER);
				info.value.biSize = 40;
				info.value.biWidth = width;
				info.value.biHeight = -height;
				info.value.biPlanes = 1;
				info.value.biBitCount = 32;
				var bits:Ptr<Ptr> = a.alloc(8);
				var bmp = Gdi32.CreateDIBSection(dc, info, 0, bits, Ptr.nil(), 0);
				if (!bmp.isNull()) {
					var old = Gdi32.SelectObject(dc, bmp);
					var px:Ptr<UInt8> = bits.value;
					var ok = false;
					if (screen) {
						// (the display's pixels where the window is: what DWM shows, the window brought to the front first)
						User32.SetForegroundWindow(hwnd);
						var p = a.make(POINT);
						User32.ClientToScreen(hwnd, p);
						ok = Gdi32.BitBlt(dc, 0, 0, width, height, desk, p.value.x, p.value.y, WM.SRCCOPY) != 0;
					} else
						ok = User32.PrintWindow(hwnd, dc, WM.PW_CLIENTONLY | WM.PW_RENDERFULLCONTENT) != 0;
					Gdi32.GdiFlush();
					if (!ok) Sys.println('WinVideoStillCheck: ${screen ? "the screen" : "PrintWindow"}: no capture');
					if (ok) {
						var out = Bytes.alloc(width * height * 4);
						for (i in 0...width * height) {
							out.set(4 * i, px[4 * i + 2]);
							out.set(4 * i + 1, px[4 * i + 1]);
							out.set(4 * i + 2, px[4 * i]);
							out.set(4 * i + 3, 255);
						}
						rgba = out;
					}
					Gdi32.SelectObject(dc, old);
					Gdi32.DeleteObject(bmp);
				}
				Gdi32.DeleteDC(dc);
				User32.ReleaseDC(Ptr.nil(), desk);
			});
			rgba;
		});
	}
}
