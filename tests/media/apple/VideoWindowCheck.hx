import SystemLayersWindowCheck.Capture;
import helder.media.ui.VideoNode;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import sys.io.File;

// A <video> in a real window (the window lane, macOS): in a scroller, a
// popup over part of it, shown both ways (VideoNode: drawn by helder, the
// default; the system's AVSampleBufferDisplayLayer in a slot, asked
// for), each run its own process: seeked to a
// frame, played (its time moving), paused (its picture still), the
// scroller moved. Drawn: helder's frames read back (helder.ui.UiWindow.capture): the
// frame shown, the popup over it, another frame once played, the same
// while paused, moved and cut by the scroller. The system's layer:
// rendering, no error, placed at the node's box in the window and moved
// with the scroller, inside the scroller's clip. Where the window server's
// captures have pixels (CGWindowListCreateImage; a background run on macOS
// 27 gets none), quads.mp4's flat quadrants' centres in the picture as
// fitted, at the capture's own pixels a point, beside controls of a known
// sRGB colour: helder's drawing against the source, the system's layer's
// numbers printed, not required (a virtual Mac's window server showed
// them some 30 levels off; to measure on hardware); the captures as PNGs
// in bin/media/video-window (CI's artifact video-window-macos). helder's
// own frame read back (drawn) checked the same way, and kept as a PNG.
//   VideoWindowCheck: the runs, compared
//   VideoWindowCheck --run drawn|layer dir: one run, its captures into dir
@:hxmc.unsafe(gc)
class VideoWindowCheck {
	static var width = 400;
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('VideoWindowCheck: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var a = Sys.args(), r = a.indexOf("--run");
		if (r >= 0) {
			scene(a[r + 1], a[r + 2]);
			Sys.exit(failed > 0 ? 1 : 0);
		}
		var dir = Sys.getEnv("TMPDIR") + "/video-window-" + Std.random(1 << 30), self = Sys.programPath();
		for (mode in MODES) {
			sys.FileSystem.createDirectory('$dir/$mode');
			var p = new sys.io.Process(self, ["--run", mode, '$dir/$mode']);
			var out = p.stdout.readAll().toString(), code = p.exitCode();
			p.close();
			Sys.print(out);
			check('the $mode run', code == 0, 'exit $code');
		}
		// (the window server's pixels, where captures have them: each way the same picture)
		var shots = [for (m in MODES) m => shot('$dir/$m')];
		if (!Lambda.exists(shots, s -> s == null)) {
			var points = [for (v in File.getContent('$dir/drawn/points.txt').split(" ")) Std.parseFloat(v)];
			for (m in MODES) {
				var c = shots[m];
				Sys.println('VideoWindowCheck: $m: the capture ${c.width}x${c.height} pixels with its title bar, ${c.scale} a point (the window\'s scale ${c.window})');
				var q = quadrants(c, points), controls = [for (k in [8, 12]) at(c, (points[k] + points[k + 2]) / 2, (points[k + 1] + points[k + 3]) / 2)];
				Sys.println('VideoWindowCheck: $m: red, green, blue, grey at ${[for (p in q.at) p.join(",")].join(" ")} (pixels): ${q.colours.join(" ")}; '
					+ 'controls (51,153,230): drawn ${controls[0].colour}, a CALayer ${controls[1].colour}');
			}
			for (m in MODES) png('$m-window', true, shots[m].bytes, shots[m].width);
			var drawn = quadrants(shots["drawn"], points).colours, off = 0;
			for (i in 0...4) for (c in 0...3) off = Std.int(Math.max(off, Math.abs(drawn[i][c] - SOURCE[i][c])));
			check('drawn: the quadrants\' colours (the window server\'s pixels)', off <= 3, 'at most $off levels off the source ${SOURCE.join(" ")}');
			// (the system's layer: reported, not required, until measured on hardware)
			var l = quadrants(shots["layer"], points).colours, worst = 0;
			for (i in 0...4) for (c in 0...3) worst = Std.int(Math.max(worst, Math.abs(drawn[i][c] - l[i][c])));
			Sys.println('VideoWindowCheck: the system\'s layer against helder\'s drawing: at most $worst levels apart (not required)');
			for (m in [601, 709])
				for (full in [false, true])
					Sys.println('VideoWindowCheck: BT.601 video range read as $m ${full ? "full" : "video"} range: ${[for (c in SOURCE) reread(c, m, full)].join(" ")}');
		} else
			Sys.println("VideoWindowCheck: no window server's capture here: the ways not compared");
		Sys.println("VideoWindowCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// the ways: drawn by helder (the default), the system's layer (asked for)
	static final MODES = ["drawn", "layer"];

	// (the captures as PNGs, where CI keeps them: ci.yml's desktop-macos)
	static final OUT = "bin/media/video-window";

	static function png(name:String, bgra:Bool, b:haxe.io.Bytes, w:Int) {
		var h = Std.int(b.length / (w * 4)), rgba = haxe.io.Bytes.alloc(w * h * 4);
		for (i in 0...w * h) {
			rgba.set(i * 4, b.get(i * 4 + (bgra ? 2 : 0)));
			rgba.set(i * 4 + 1, b.get(i * 4 + 1));
			rgba.set(i * 4 + 2, b.get(i * 4 + (bgra ? 0 : 2)));
			rgba.set(i * 4 + 3, 255);
		}
		sys.FileSystem.createDirectory(OUT);
		File.saveBytes('$OUT/$name.png', helder.image.PngEncoder.encode(rgba, w, h, true));
	}

	// (a run's seeked capture, BGRA, and its pixels a point; null: none)
	static function shot(dir:String):Null<{bytes:haxe.io.Bytes, width:Int, scale:Float, height:Int, window:Float}> {
		if (!sys.FileSystem.exists('$dir/seeked.raw')) return null;
		var b = File.getBytes('$dir/seeked.raw'), size = File.getContent('$dir/seeked.size').split(" ");
		return blank(b) ? null : {bytes: b, width: Std.parseInt(size[0]), scale: Std.parseFloat(size[1]), height: Std.parseInt(size[2]), window: Std.parseFloat(size[3])};
	}

	// (the capture's pixel at x, y points)
	static function at(c:{bytes:haxe.io.Bytes, width:Int, scale:Float, height:Int, window:Float}, x:Float, y:Float):{at:Array<Int>, colour:Array<Int>} {
		var px = Std.int(x * c.scale), py = Std.int(y * c.scale), i = 4 * (py * c.width + px);
		return {at: [px, py], colour: [c.bytes.get(i + 2), c.bytes.get(i + 1), c.bytes.get(i)]};
	}

	// (quads.mp4's quadrants' centres in the picture fitted to the node's
	// box (contained, 64 by 48), away from the square moving through its
	// middle)
	static function quadrants(c:{bytes:haxe.io.Bytes, width:Int, scale:Float, height:Int, window:Float}, points:Array<Float>):{at:Array<Array<Int>>, colours:Array<Array<Int>>} {
		var w = points[2] - points[0], h = points[3] - points[1], k = Math.min(w / 64, h / 48);
		var x0 = points[0] + (w - 64 * k) / 2, y0 = points[1] + (h - 48 * k) / 2;
		var found = [for (q in [[16, 12], [48, 12], [16, 36], [48, 36]]) at(c, x0 + (q[0] + 0.5) * k, y0 + (q[1] + 0.5) * k)];
		return {at: [for (f in found) f.at], colours: [for (f in found) f.colour]};
	}

	// (quads.mp4's colours as ffmpeg decodes them; the controls, sRGB's
	// (51, 153, 230) drawn by helder and as a CALayer of its own, tell a
	// colour management of the window server's from a conversion of the
	// video's; what each reading of the source's Y'CbCr would show printed,
	// BT.601's encoding read as 601 or 709, video or full range)
	static final SOURCE = [[254, 0, 0], [0, 255, 1], [0, 0, 255], [128, 128, 128]];

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
		var w = new helder.ui.UiWindow("VideoWindowCheck", 400, 300);
		w.root.style.set({background: 0xFFF4F4F4, paddingTop: 30, paddingLeft: 20});
		var list = new Node();
		list.style.set({overflow: Scroll, width: 240, height: 240, rowGap: 2, background: 0xFFFFFFFF});
		var video = new VideoNode();
		video.layer = mode != "drawn";
		video.style.set({width: 192, height: 144, flexShrink: 0});
		for (i in 0...30) {
			var row = new Node();
			row.style.set({height: 20, flexShrink: 0, background: i % 2 == 0 ? 0xFFEFF6FF : 0xFFFFFFFF});
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
		@:privateAccess layered.systemLayer = new LayerSlot(@:privateAccess SystemLayersWindowCheck.solidLayer(0.2, 0.6, 0.9));
		w.root.append(swatch);
		w.root.append(layered);
		video.open("tests/media/apple/quads.mp4");
		video.muted = true;
		var step = 0, start = 0.0, seekAt = 0.0, k = 1.0, shots = new Map<String, haxe.io.Bytes>(), placed:Array<Float> = [];
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
					seekAt = haxe.Timer.stamp();
				// (the seek's frame decoded and shown: waited for, 5 s at most; twenty
				// frames after it were too few on a loaded machine, CI's or a build's)
				case 30 if ((p.shown == null || p.shown.time != 0.4) && haxe.Timer.stamp() - seekAt < 5):
					step = 29;
				case 30:
					Sys.println('VideoWindowCheck: $mode: the seek shown after ${Math.round((haxe.Timer.stamp() - seekAt) * 1000)} ms');
					k = w.device.width / 400;
					width = w.device.width;
					vbox = box(video);
					pbox = box(popup);
					lbox = box(list);
					var f = p.shown;
					check('$mode: seeked to the frame at 0.4', f != null && f.time == 0.4, f == null ? "none" : '${f.time}');
					check('$mode: ${mode != "drawn" ? "the system\'s layer" : "drawn"}', (@:privateAccess video.systemLayer != null) == (mode != "drawn"));
					if (mode != "drawn") placed = layer(video);
					inline function points(n:Node):Array<Float>
						return [n.absX, n.absY, n.absX + n.width, n.absY + n.height];
					File.saveContent('$dir/points.txt', points(video).concat(points(popup)).concat(points(swatch)).concat(points(layered)).join(" "));
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
					if (mode != "drawn") {
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
		png("drawn-helder", false, seeked, width);
		// (helder's own frame: the quadrants' centres in the picture as fitted, device pixels)
		var w = video[2] - video[0], h = video[3] - video[1], k = Math.min(w / 64, h / 48);
		var x0 = video[0] + (w - 64 * k) / 2, y0 = video[1] + (h - 48 * k) / 2, off = 0;
		var got = [for (q in [[16, 12], [48, 12], [16, 36], [48, 36]]) pixel(seeked, Std.int(x0 + (q[0] + 0.5) * k), Std.int(y0 + (q[1] + 0.5) * k))];
		for (i in 0...4) for (c in 0...3) off = Std.int(Math.max(off, Math.abs(got[i][c] - SOURCE[i][c])));
		check('drawn: the quadrants\' colours (helder\'s frame read back)', off <= 3, '${got.join(" ")}, at most $off levels off');
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
			var status = helder.os.apple.objc.Msg.i(l, helder.os.apple.objc.ObjC.sel("status")).toInt();
			var error = helder.os.apple.objc.Msg.id(l, helder.os.apple.objc.ObjC.sel("error"));
			check('layer: rendering, no error', status == 1 && error.isNull(), 'status $status');
			var b = helder.os.apple.objc.Msg.rect(l, helder.os.apple.objc.ObjC.sel("bounds"));
			var r = helder.os.apple.objc.Msg.rectRectPtr(l, helder.os.apple.objc.ObjC.sel("convertRect:toLayer:"), b, hxmc.unsafe.Ptr.nil());
			var clip = helder.os.apple.objc.Msg.id(l, helder.os.apple.objc.ObjC.sel("superlayer"));
			var cb = helder.os.apple.objc.Msg.rect(clip, helder.os.apple.objc.ObjC.sel("bounds"));
			var c = helder.os.apple.objc.Msg.rectRectPtr(clip, helder.os.apple.objc.ObjC.sel("convertRect:toLayer:"), cb, hxmc.unsafe.Ptr.nil());
			[r.origin.x, r.origin.y, r.size.width, r.size.height, 0.0, c.origin.y, c.size.height];
		});
	}

	static function capture(w:helder.ui.UiWindow, dir:String, name:String) {
		w.device.settle();
		Sys.sleep(0.15);
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.apple.objc.Msg.i(helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window")), helder.os.apple.objc.ObjC.sel("windowNumber")).toInt());
		var img = Capture.window(id);
		if (img == null) return;
		// (the content at the capture's own scale: its pixels a point, the window 400 by 300 points; the title bar above cut)
		var scale = img.width / 400, h = Math.round(300 * scale), row = img.width * 4, top = img.height - h;
		if (top < 0) return;
		var out = haxe.io.Bytes.alloc(row * h);
		out.blit(0, img.pixels, top * row, row * h);
		File.saveBytes('$dir/$name.raw', out);
		File.saveContent('$dir/$name.size', '${img.width} $scale ${img.height} ${w.window.scale}');
	}
}
