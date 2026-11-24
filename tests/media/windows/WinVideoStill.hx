import haxe.io.Bytes;
import helder.asset.Asset;
import helder.media.MemorySource;
import helder.media.ui.MediaTags.*;
import helder.media.ui.VideoNode;
import helder.os.OsThread;
import helder.os.win32.User32;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import hxmc.unsafe.*;

// A <Video> on Windows (the window lane on a Windows host): quads.mp4's
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
//   WinVideoStill drawn|layer [dir]
@:hxmc.unsafe(gc)
class WinVideoStill implements Markup {
	static inline var FRAMES = 6;
	static inline var LEVELS = 8;
	static final SOURCE = [[254, 0, 0], [0, 255, 1], [0, 0, 255], [128, 128, 128]];

	static function say(s:String)
		Sys.println("WinVideoStill: " + s);

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
			if (p == null || !p.loaded) {
				if (p != null && p.error != null) {
					say('FAIL: ${p.error}');
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
		UiWindow.run(<Surface title="WinVideoStill" width={400} height={360} background="#333333">
			<view grow={1} padding-top={40} padding-left={40} overflow="scroll" background={unit ? "#222222" : null}>
				<Video src={new MemorySource(Asset.embed("tests/media/apple/quads.mp4"))} width={320} height={240} layer={layer} muted={true} loop={true}
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
		if (layer) layers(n, w);
		if (px == null) {
			say("FAIL: no capture");
			Sys.exit(1);
		}
		if (dir != null) sys.io.File.saveBytes('$dir/still-${layer ? "layer" : "drawn"}.rgba', px);
		// (the window's own background beside the box: whether the capture has the window at all)
		var bg = (20 * width + 20) * 4;
		say('the background at 20,20: ${px.get(bg)} ${px.get(bg + 1)} ${px.get(bg + 2)} (the window\'s 51 51 51)');
		var x = n.absX * k, y = n.absY * k, bw = n.width * k, bh = n.height * k;
		var s = Math.min(bw / 64, bh / 48), x0 = x + (bw - 64 * s) / 2, y0 = y + (bh - 48 * s) / 2, worst = 0, got = [];
		for (i => q in [[16, 12], [48, 12], [16, 36], [48, 36]]) {
			var at = (Math.round(y0 + (q[1] + 0.5) * s) * width + Math.round(x0 + (q[0] + 0.5) * s)) * 4;
			var c = [px.get(at), px.get(at + 1), px.get(at + 2)];
			for (j in 0...3) worst = Std.int(Math.max(worst, Math.abs(c[j] - SOURCE[i][j])));
			got.push(c.join(" "));
		}
		var ok = worst <= LEVELS && time == 0.2;
		if (layer && onLayer && !ok) probes(n, w, x, y, x0, y0, s, width, height);
		say('${ok ? "ok" : "FAIL"}: ${unit ? "layer in a scroller of its own" : layer ? "layer" : "drawn"}: the frame at $time $how, the quadrants ${got.join(", ")}, at most $worst levels off the source ($LEVELS)');
		Sys.exit(ok ? 0 : 1);
	}

	// (a black layer still: captured again with the surface also at the top
	// of the window's root, the slot's visual unscaled, a colour of
	// DcLayers' own in the slot: which shows says where the frame is lost)
	static function probes(n:VideoNode, w:UiWindow, x:Float, y:Float, x0:Float, y0:Float, s:Float, width:Int, height:Int) {
		var sl = @:privateAccess n.sample, wl = sl == null ? null : @:privateAccess sl.windows;
		if (wl == null) return;
		var before = helder.media.ui.WinLayer.log.length;
		for (mode in [1, 2, 3]) {
			wl.probe(mode, x, y);
			Sys.sleep(0.4);
			var px = capture(w.window, width, height);
			var at = (Math.round(y0 + 12.5 * s) * width + Math.round(x0 + 16.5 * s)) * 4, c = (Math.round(y + 5) * width + Math.round(x + 5)) * 4;
			var what = ["", "the surface also on top of the root", "the slot visual unscaled", "a solid green in the slot"][mode];
			var q = px == null ? "no capture" : px.get(at) + " " + px.get(at + 1) + " " + px.get(at + 2);
			var corner = px == null ? "" : px.get(c) + " " + px.get(c + 1) + " " + px.get(c + 2);
			say('probe $mode: $what: the top left quadrant $q, the box corner $corner');
			wl.probe(0, x, y);
		}
		for (l in helder.media.ui.WinLayer.log.slice(before)) say('layer: $l');
	}

	// (the layer run's diagnostics: WinLayer's calls and state, DcLayers'
	// state, the slot's plane as the split placed it)
	static function layers(n:VideoNode, w:UiWindow) {
		w.device.settle();
		for (l in helder.media.ui.WinLayer.log) say('layer: $l');
		var s = @:privateAccess n.sample, wl = s == null ? null : @:privateAccess s.windows;
		say('layer: ${wl == null ? "no WinLayer" : wl.state()}');
		var c = w.compositor, d = c == null ? null : Std.downcast(c.layers, helder.ui.draw.DcLayers);
		if (d == null) {
			say("layer: no DcLayers");
			return;
		}
		say('layer: DcLayers frames ${d.frames}, single ${d.single}, fell ${d.fell}, stack shown ${@:privateAccess d.stackShown}, hidden ${@:privateAccess d.hide}, broken ${@:privateAccess d.broken}');
		say('layer: the units ${[for (u in @:privateAccess d.units) u.kind].join(",")} (4: a system layer), the scrollers not units of their own: ${d.reasons.join("; ")}');
		// (the stack bottom to top: each plane's kind (0 the window's, 1 what is over a unit, 2 a scroller, 3 a mover, 4 a system layer), its quads, its place)
		say('layer: the order ${[for (p in @:privateAccess d.order) p == null ? "-" : '${p.kind}:${p.quads.length}q@${Math.round(p.ox)},${Math.round(p.oy)} ${p.pw}x${p.ph}'].join(" | ")}');
		for (p in @:privateAccess d.kept)
			if (p.kind == helder.ui.draw.LayerPlane.SLOT)
				say('layer: a slot plane, ours ${wl != null && p.slot == wl.slot}, shown ${p.slot != null && p.slot.shown}, attached ${p.attached}, index ${p.index}, clip ${p.cx0},${p.cy0}..${p.cx1},${p.cy1}');
		say('layer: the node at ${n.absX},${n.absY} ${n.width}x${n.height}, its box ${@:privateAccess n.box}');
	}

	// (the client area's pixels as RGBA, on the main thread: PrintWindow,
	// which composes the window's DirectComposition content, else the
	// screen's where the window is: WinLayersWindow's)
	static function capture(w:helder.os.Window, width:Int, height:Int):Null<Bytes> {
		var hwnd = w.surface.handle;
		return OsThread.get(() -> {
			var rgba:Null<Bytes> = null;
			Arena.scoped(a -> {
				var screen = User32.GetDC(Ptr.nil());
				var dc = Gdi32.CreateCompatibleDC(screen);
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
					var ok = User32.PrintWindow(hwnd, dc, WM.PW_CLIENTONLY | WM.PW_RENDERFULLCONTENT) != 0;
					Gdi32.GdiFlush();
					// (no fallback to the screen's pixels: on CI's runner they are black everywhere)
					if (!ok) Sys.println("WinVideoStill: PrintWindow failed: no capture");
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
				User32.ReleaseDC(Ptr.nil(), screen);
			});
			rgba;
		});
	}
}
