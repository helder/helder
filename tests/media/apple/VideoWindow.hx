import SystemLayersWindow.Capture;
import helder.media.ui.VideoNode;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// A <Video> in a real window (the window lane, macOS): in a scroller, a
// popup over part of it, shown both ways (VideoNode: drawn by helder, and
// the system's AVSampleBufferDisplayLayer in a slot), each run its own
// process: seeked to a frame, played (its time moving), paused (its
// picture still), the scroller moved. Drawn: helder's frames read back
// (UiWindow.capture): the frame shown, the popup over it, another frame
// once played, the same while paused, moved and cut by the scroller. The
// system's layer: rendering, no error, placed at the node's box in the
// window and moved with the scroller, inside the scroller's clip. Where
// the window server's captures have pixels (CGWindowListCreateImage; a
// background run on macOS 27 gets none), both ways are compared there,
// on quads.mp4's flat colours (testsrc's edges are where the system's
// scaling and chroma's filters differ from helder's), beside controls of
// a known sRGB colour.
//   VideoWindow: both runs, compared
//   VideoWindow --run drawn|layer dir: one run, its captures into dir
@:hxmc.unsafe(gc)
class VideoWindow {
	static var width = 400;
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('VideoWindow: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var a = Sys.args(), r = a.indexOf("--run");
		if (r >= 0) {
			scene(a[r + 1], a[r + 2]);
			Sys.exit(failed > 0 ? 1 : 0);
		}
		var dir = Sys.getEnv("TMPDIR") + "/video-window-" + Std.random(1 << 30), self = Sys.programPath();
		for (mode in ["drawn", "layer"]) {
			sys.FileSystem.createDirectory('$dir/$mode');
			var p = new sys.io.Process(self, ["--run", mode, '$dir/$mode']);
			var out = p.stdout.readAll().toString(), code = p.exitCode();
			p.close();
			Sys.print(out);
			check('the $mode run', code == 0, 'exit $code');
		}
		// (the window server's pixels, where captures have them: both ways the same picture)
		var a = '$dir/drawn/seeked.raw', b = '$dir/layer/seeked.raw';
		if (sys.FileSystem.exists(a) && sys.FileSystem.exists(b) && !blank(File.getBytes(a))) {
			var box = [for (v in File.getContent('$dir/drawn/boxes.txt').split(" ")) Std.parseInt(v)];
			width = box[8];
			var da = File.getBytes(a), db = File.getBytes(b), video = box.slice(0, 4), popup = box.slice(4, 8);
			compare(da, db, video, popup, box.slice(9, 13), box.slice(13, 17));
		} else
			Sys.println("VideoWindow: no window server's capture here: the two ways not compared");
		Sys.println("VideoWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// (the window server's pixels both ways, BGRA: quads.mp4's flat
	// quadrants, red, green, blue and grey, where scaling and chroma's
	// filters do not reach; the controls, sRGB's (51, 153, 230) drawn by
	// helder and as a CALayer of its own, tell a colour management of the
	// window server's own from a conversion of the video's; on a difference
	// what each reading of the source's Y'CbCr would show, BT.601's
	// encoding read as 601 or 709, video or full range)
	static final SOURCE = [[254, 0, 0], [0, 255, 1], [0, 0, 255], [128, 128, 128]];

	static function compare(a:haxe.io.Bytes, b:haxe.io.Bytes, video:Array<Int>, popup:Array<Int>, drawnSwatch:Array<Int>, layerSwatch:Array<Int>) {
		inline function rgb(x:haxe.io.Bytes, px:Int, py:Int):Array<Int> {
			var i = 4 * (py * width + px);
			return [x.get(i + 2), x.get(i + 1), x.get(i)];
		}
		var w = video[2] - video[0], h = video[3] - video[1];
		var at = [for (f in [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]) [video[0] + Std.int(f[0] * w), video[1] + Std.int(f[1] * h)]];
		var drawn = [for (p in at) rgb(a, p[0], p[1])], layer = [for (p in at) rgb(b, p[0], p[1])];
		var mid = (x:haxe.io.Bytes, s:Array<Int>) -> rgb(x, (s[0] + s[2]) >> 1, (s[1] + s[3]) >> 1);
		var worst = 0, off = 0;
		for (i in 0...4)
			for (c in 0...3) {
				worst = Std.int(Math.max(worst, Math.abs(drawn[i][c] - layer[i][c])));
				off = Std.int(Math.max(off, Math.abs(drawn[i][c] - SOURCE[i][c])));
			}
		var controls = [mid(a, drawnSwatch), mid(a, layerSwatch), mid(b, drawnSwatch), mid(b, layerSwatch)];
		Sys.println('VideoWindow: red, green, blue, grey: the source ${SOURCE.join(" ")}; drawn ${drawn.join(" ")}; the system\'s layer ${layer.join(" ")}; '
			+ 'controls (51,153,230): ${controls.join(" ")}');
		check('drawn: the quadrants\' colours (the window server\'s pixels)', off <= 3, 'at most $off levels off');
		check('the system\'s layer shows what helder draws (the window server\'s pixels)', worst <= 4, 'at most $worst levels apart');
		if (worst > 4)
			for (m in [601, 709])
				for (full in [false, true])
					Sys.println('VideoWindow: BT.601 video range read as $m ${full ? "full" : "video"} range: ${[for (c in SOURCE) reread(c, m, full)].join(" ")}');
	}

	// (an sRGB colour encoded as BT.601 video range, decoded as m and range says)
	static function reread(c:Array<Int>, m:Int, full:Bool):Array<Int> {
		var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
		var y = 16 + 219 * (0.299 * r + 0.587 * g + 0.114 * b), cb = 128 + 224 * (b - (0.299 * r + 0.587 * g + 0.114 * b)) / 1.772,
			cr = 128 + 224 * (r - (0.299 * r + 0.587 * g + 0.114 * b)) / 1.402;
		var kr = m == 709 ? 0.2126 : 0.299, kb = m == 709 ? 0.0722 : 0.114, kg = 1 - kr - kb;
		var yy = full ? y / 255 : (y - 16) / 219, u = full ? (cb - 128) / 255 : (cb - 128) / 224, v = full ? (cr - 128) / 255 : (cr - 128) / 224;
		return [yy + 2 * (1 - kr) * v, yy - 2 * kb * (1 - kb) / kg * u - 2 * kr * (1 - kr) / kg * v, yy + 2 * (1 - kb) * u].map(x -> Std.int(Math.max(0,
			Math.min(255, Math.round(x * 255)))));
	}

	static function blank(b:haxe.io.Bytes):Bool {
		var i = 0;
		while (i < b.length) {
			if (b.get(i) != 0 || b.get(i + 1) != 0 || b.get(i + 2) != 0) return false;
			i += 4;
		}
		return true;
	}

	static function pixel(b:haxe.io.Bytes, x:Int, y:Int):Array<Int> {
		var i = 4 * (y * width + x);
		return [b.get(i), b.get(i + 1), b.get(i + 2)];
	}

	static function near(a:Array<Int>, b:Array<Int>, k:Int):Bool
		return Math.abs(a[0] - b[0]) <= k && Math.abs(a[1] - b[1]) <= k && Math.abs(a[2] - b[2]) <= k;

	static function each(r:Array<Int>, out:Array<Int>, f:(Int, Int) -> Void)
		for (y in r[1] + 2...r[3] - 2) for (x in r[0] + 2...r[2] - 2)
			if (!(x >= out[0] - 2 && x < out[2] + 2 && y >= out[1] - 2 && y < out[3] + 2)) f(x, y);

	// (the largest minus the least green in the box, out left out)
	static function spread(b:haxe.io.Bytes, r:Array<Int>, out:Array<Int>):Int {
		var lo = 255, hi = 0;
		each(r, out, (x, y) -> {
			var g = pixel(b, x, y)[1];
			if (g < lo) lo = g;
			if (g > hi) hi = g;
		});
		return hi - lo;
	}

	// (the share of the box's pixels that differ by more than 8 levels)
	static function differ(a:haxe.io.Bytes, b:haxe.io.Bytes, r:Array<Int>, out:Array<Int>):Float {
		var n = 0, d = 0;
		each(r, out, (x, y) -> {
			n++;
			if (!near(pixel(a, x, y), pixel(b, x, y), 8)) d++;
		});
		return n == 0 ? 0 : d / n;
	}

	static function scene(mode:String, dir:String) {
		var w = new UiWindow("VideoWindow", 400, 300);
		w.root.style.set({background: 0xFFF4F4F4, paddingTop: 30, paddingLeft: 20});
		var list = new Node();
		list.style.set({overflow: Scroll, width: 240, height: 240, rowGap: 2, background: 0xFFFFFFFF});
		var video = new VideoNode();
		video.layer = mode == "layer";
		video.style.set({width: 192, height: 144, shrink: 0});
		for (i in 0...30) {
			var row = new Node();
			row.style.set({height: 20, shrink: 0, background: i % 2 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF});
			list.append(row);
			if (i == 2) list.append(video);
		}
		w.root.append(list);
		var popup = new Node();
		popup.style.set({position: Absolute, left: 180, top: 210, width: 60, height: 40, background: 0xFF6A3AB0});
		w.ui.overlay.append(popup);
		// (the controls: sRGB's (51, 153, 230) drawn by helder, and a CALayer of it in a slot)
		var swatch = new Node(), layered = new Node();
		swatch.style.set({position: Absolute, left: 290, top: 40, width: 40, height: 40, background: 0xFF3399E6});
		layered.style.set({position: Absolute, left: 340, top: 40, width: 40, height: 40});
		@:privateAccess layered.systemLayer = new LayerSlot(@:privateAccess SystemLayersWindow.solidLayer(0.2, 0.6, 0.9));
		w.root.append(swatch);
		w.root.append(layered);
		video.open("tests/media/apple/quads.mp4");
		video.muted = true;
		var step = 0, start = 0.0, k = 1.0, shots = new Map<String, haxe.io.Bytes>(), placed:Array<Float> = [];
		var vbox = [], pbox = [], lbox = [];
		inline function box(n:Node):Array<Int>
			return [n.absX, n.absY, n.absX + n.width, n.absY + n.height].map(v -> Math.round(v * k));
		// (helder's frame read back at the next frame: w.capture)
		function shoot(name:String) {
			w.capture = haxe.io.Bytes.alloc(Std.int(w.device.width) * Std.int(w.device.height) * 4);
			shots.set(name, w.capture);
			capture(w, dir, name);
		}
		App.run(() -> {
			step++;
			var p = video.player;
			switch step {
				case 10 if (p == null || !p.loaded):
					step = 9;
				case 10:
					video.seek(0.45);
				case 30:
					k = w.device.width / 400;
					width = w.device.width;
					vbox = box(video);
					pbox = box(popup);
					lbox = box(list);
					File.saveContent('$dir/boxes.txt', vbox.concat(pbox).concat([width]).concat(box(swatch)).concat(box(layered)).join(" "));
					var f = p.shown;
					check('$mode: seeked to the frame at 0.4', f != null && f.time == 0.4, f == null ? "none" : '${f.time}');
					check('$mode: ${mode == "layer" ? "the system\'s layer" : "drawn"}', (@:privateAccess video.systemLayer != null) == (mode == "layer"));
					if (mode == "layer") placed = layer(video);
					shoot("seeked");
				case 32:
					video.play();
					start = haxe.Timer.stamp();
				case 33 if (haxe.Timer.stamp() - start < 0.4):
					step = 32;
				case 33:
					check('$mode: played on', video.time.peek() > 0.6, '${Math.round(video.time.peek() * 100) / 100}');
					shoot("played");
				case 35:
					video.pause();
				case 40:
					shoot("paused");
				case 50:
					shoot("paused2");
				case 52:
					list.scrollY = 110;
					w.ui.requestFrame();
				case 60:
					shoot("scrolled");
					if (mode == "layer") {
						var moved = layer(video), dy = Math.abs(moved[1] - placed[1]);
						check('layer: moved with the scroller', Math.abs(dy - 110) < 1.5 && moved[0] == placed[0], '$placed to $moved');
						// (macOS's y up: the clip the scroller's box, the layer past its top)
						var h = w.window.height / k, top = h - lbox[1] / k, bottom = h - lbox[3] / k;
						check('layer: in the scroller\'s clip, cut by its edge', Math.abs(moved[5] - bottom) < 1 && Math.abs(moved[5] + moved[6] - top) < 1
							&& moved[1] + moved[3] > top, '$moved, the list from $bottom to $top');
					}
				case 62:
					if (mode == "drawn") drawn(shots, vbox, pbox, lbox, Math.round(110 * k));
					video.dispose();
					w.close();
					return;
				case _:
			}
			if (w.needsFrame() || step < 62) w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}

	// helder's frames read back (RGBA): the picture, the popup, playing and pausing, scrolling
	static function drawn(shots:Map<String, haxe.io.Bytes>, video:Array<Int>, popup:Array<Int>, list:Array<Int>, shift:Int) {
		var seeked = shots["seeked"];
		check('drawn: the frame shown, not the background', spread(seeked, video, popup) > 40, '${spread(seeked, video, popup)}');
		check('drawn: the popup over it', near(pixel(seeked, popup[0] + 4, popup[1] + 4), [0x6A, 0x3A, 0xB0], 2), '${pixel(seeked, popup[0] + 4, popup[1] + 4)}');
		check('drawn: played, another frame', differ(seeked, shots["played"], video, popup) > 0.01);
		check('drawn: paused, the same frame', differ(shots["paused"], shots["paused2"], video, popup) < 0.002, '${differ(shots["paused"], shots["paused2"], video, popup)}');
		var scrolled = shots["scrolled"], moved = [video[0], list[1], video[2], video[3] - shift];
		check('drawn: scrolled with the list', spread(scrolled, moved, [0, 0, 0, 0]) > 40);
		var x = (video[0] + video[2]) >> 1;
		check('drawn: cut by the list\'s edge', near(pixel(scrolled, x, list[1] - 3), pixel(seeked, x, list[1] - 3), 1), '${pixel(scrolled, x, list[1] - 3)}');
	}

	// (the system's layer: its status, rendering; its frame and its clip's in the
	// window's content, points: x, y, w, h, the clip's top and how much of the
	// layer is below it)
	static function layer(video:VideoNode):Array<Float> {
		var sample = @:privateAccess video.sample, l:hxmc.unsafe.Ptr = @:privateAccess sample.layer;
		return OsThread.get(() -> {
			var status = helder.os.objc.Msg.i(l, helder.os.objc.ObjC.sel("status")).toInt();
			var error = helder.os.objc.Msg.id(l, helder.os.objc.ObjC.sel("error"));
			check('layer: rendering, no error', status == 1 && error.isNull(), 'status $status');
			var b = helder.os.objc.Msg.rect(l, helder.os.objc.ObjC.sel("bounds"));
			var r = helder.os.objc.Msg.rectRectPtr(l, helder.os.objc.ObjC.sel("convertRect:toLayer:"), b, hxmc.unsafe.Ptr.nil());
			var clip = helder.os.objc.Msg.id(l, helder.os.objc.ObjC.sel("superlayer"));
			var cb = helder.os.objc.Msg.rect(clip, helder.os.objc.ObjC.sel("bounds"));
			var c = helder.os.objc.Msg.rectRectPtr(clip, helder.os.objc.ObjC.sel("convertRect:toLayer:"), cb, hxmc.unsafe.Ptr.nil());
			[r.origin.x, r.origin.y, r.size.width, r.size.height, 0.0, c.origin.y, c.size.height];
		});
	}

	static function capture(w:UiWindow, dir:String, name:String) {
		w.device.settle();
		Sys.sleep(0.15);
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.objc.Msg.i(helder.os.objc.Msg.id(view, helder.os.objc.ObjC.sel("window")), helder.os.objc.ObjC.sel("windowNumber")).toInt());
		var img = Capture.window(id);
		if (img == null) return;
		var h = Std.int(w.window.height), row = img.width * 4, top = img.height - h;
		var out = haxe.io.Bytes.alloc(row * h);
		out.blit(0, img.pixels, top * row, row * h);
		File.saveBytes('$dir/$name.raw', out);
	}
}
