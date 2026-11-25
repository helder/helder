package viewer;

// The viewer's milestones for its benchmark (HELDER_VIEWER_TIMING=<file>,
// apps/viewer/tests/bench/finder.mjs): a line each, "<ms> <frame> <what>",
// the ms Sys.time's (no epoch: start's line adds the epoch's ms, Date's),
// the frame the one presented that shows it (counted from the window's
// first). What it marks: start <epoch ms> (main), run (the window asked
// for), made (the window and its device made), window (the first frame
// presented), go <dir> (a folder asked for: the command line, a hand-over,
// back, forward), rows <n> (the first frame showing its entries, or that it
// has none), batch <n> [done] merged in <ms> (a listing's batch come, its
// sort into what is shown), all <n> (the first with all of them read),
// thumbs (the first with the visible tiles' thumbnails made), open <file> and image (the
// first frame showing it full size). The driver's commands come as handed
// over paths (Instance): viewer:back, viewer:forward, viewer:close, only
// while it is on.
class Timing {
	#if (hxmc.target == "wasm32-wasi")
	public static final on = false;
	#else
	public static final on = (Sys.getEnv("HELDER_VIEWER_TIMING") ?? "") != "";
	#end

	static var frames = 0;
	static var nav:Null<{dir:String, rows:Bool, all:Bool}> = null;
	static var opened = false;

	public static function mark(what:String) {
		#if (hxmc.target != "wasm32-wasi")
		if (!on) return;
		try {
			var f = sys.io.File.append(Sys.getEnv("HELDER_VIEWER_TIMING"));
			f.writeString('${Math.round(Sys.time() * 10000) / 10} $frames $what\n');
			f.close();
		} catch (_:Dynamic) {}
		#end
	}

	// a folder asked for (Browser.load)
	public static function going(dir:String) {
		if (!on) return;
		mark('go $dir');
		nav = {dir: dir, rows: false, all: false};
	}

	// a file asked for full size (Explorer.view)
	public static function opening(path:String) {
		if (!on) return;
		mark('open $path');
		opened = true;
	}

	// a frame presented: what it shows marked once (the window's onFrame)
	public static function frame(x:Explorer) {
		frames++;
		if (frames == 1) mark("window");
		var b = x.browser, n = nav;
		if (n != null && b.dir.value == n.dir) {
			// (not the last folder's, kept on screen until the new one's first batch: Browser.stale)
			if (!n.rows && !b.stale && (b.items.value.length > 0 || !b.reading.value)) {
				n.rows = true;
				mark('rows ${b.items.value.length}');
			}
			if (n.rows && !n.all && !b.reading.value) {
				n.all = true;
				mark('all ${b.total.value}');
			}
			if (n.all && Tiles.waiting == 0) {
				nav = null;
				mark("thumbs");
			}
		}
		// (a PDF shown once its first page is drawn, not once its pages' sizes are read)
		var doc = x.viewer.pdf.peek();
		if (opened && x.full.value && x.viewer.state.peek() == Shown && (doc == null || doc.image(0) != null)) {
			opened = false;
			mark("image");
		}
	}

	// a driver's command handed over (true: it was one)
	public static function command(x:Explorer, what:String):Bool {
		if (!on) return false;
		switch what {
			case "viewer:back": x.browser.goBack();
			case "viewer:forward": x.browser.goForward();
			case "viewer:close": x.close();
			case _: return false;
		}
		return true;
	}
}
