package helder.ui.draw;

#if (hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.Texture;

// A layer of a window's split (LayerSplit): what it is (the window's, what
// is over a unit, a scroller's content, a mover, a node's system layer),
// its key; a scroller's clip and its corners' radii; its quads this frame
// and their bounds; its buffer's size and where it is in the frame's
// pixels; what it drew last (its quads in its pixels and their runs), what
// changed since (damage, a history of its draws: what a buffer drawn some
// draws ago misses, its quads cut to that: cut). The system's layers
// extend it (CaLayers', ScLayers').
@:hxmc.unsafe(gc)
class LayerPlane {
	public static inline var BASE = 0;
	public static inline var OVER = 1;
	public static inline var SCROLL = 2;
	public static inline var MOVER = 3;
	public static inline var SLOT = 4;

	public final kind:Int;
	public final key:Dynamic;
	public var index = -1;
	// (a scroller's: its clip in the frame's pixels; its offsets as drawn, the UI's scale)
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	public var drawnX = 0.0;
	public var drawnY = 0.0;
	// (a scroller's ranges: per axis its least offset and how far it scrolls, points)
	public final ranges = [0.0, 0.0, 0.0, 0.0];
	public var scale = 1.0;
	public var cs = 1.0;
	// (a system layer's: its slot, the unit it is in (-1: one of its own); a scroller's: those in it)
	public var slot:Null<helder.ui.LayerSlot> = null;
	public var attached = -1;
	public final slots:Array<LayerPlane> = [];
	public var follow:Array<LayerPlane> = [];
	// (a scroller's clip's corners' radii)
	public final radii = [0.0, 0.0, 0.0, 0.0];
	public final quads:Array<Int> = [];
	// (what its quads cover, in the frame's pixels: x0, y0, x1, y1 each)
	public final rects:Array<Float> = [];
	// (a scroller's content's place as geometry set it, points)
	public var geomX = 0.0;
	public var geomY = 0.0;
	var x0 = 0.0;
	var y0 = 0.0;
	var x1 = 0.0;
	var y1 = 0.0;
	public var pw = 0;
	public var ph = 0;
	public var ox = 0.0;
	public var oy = 0.0;
	public var bytes = Bytes.alloc(0);
	public var len = 0;
	public final runs:Array<Int> = [];
	public final runTextures:Array<Null<Texture>> = [];
	var last = Bytes.alloc(0);
	var lastLen = -1;
	final lastRuns:Array<Int> = [];
	final lastTextures:Array<Null<Texture>> = [];
	var lastW = 0;
	var lastH = 0;
	// (each quad's texture now and as drawn last)
	final quadTextures:Array<Null<Texture>> = [];
	final lastQuadTextures:Array<Null<Texture>> = [];
	// what of its pixels changed since it was last drawn (local), all of it
	// where it was not drawn before, changed size or most of it changed
	public final damage = new Damage();
	// (the pixels its quads cover in all, overlaps counted: what drawing it whole costs)
	public var cover(default, null) = 0.0;
	// (per draw, newest last, its rectangles (null: all of it), so that a
	// buffer drawn some draws ago is brought up to date: buffer age)
	final history:Array<Null<Array<Float>>> = [];
	// its draws so far: what a buffer drawn now holds
	public var serial(default, null) = 0;
	// (since's: the rectangles a buffer misses, its quads cut to them (the
	// rectangles cleared first, then each quad that meets one, its region
	// that one), their runs)
	final since = new Damage();
	public var cutBytes = Bytes.alloc(0);
	public var cutLen = 0;
	public var clears = 0;
	public final cutRuns:Array<Int> = [];
	public final cutTextures:Array<Null<Texture>> = [];

	public function new(kind:Int, key:Dynamic) {
		this.kind = kind;
		this.key = key;
	}

	// (whether v is a number the system takes: a NaN or an infinity in a
	// layer's geometry (a layout gone wrong) is an exception Core
	// Animation throws, and nothing a SurfaceControl should be handed)
	public static inline function fine(v:Float):Bool
		return v == v && v > -1e15 && v < 1e15;

	public function begin() {
		quads.resize(0);
		rects.resize(0);
		x0 = y0 = 1e300;
		x1 = y1 = -1e300;
	}

	public function add(w:Int, out:Bytes) {
		quads.push(w);
		var q = w * CompositeFrame.STRIDE;
		var ax = out.getFloat(q + 8), ay = out.getFloat(q + 12), bx = out.getFloat(q + 24), by = out.getFloat(q + 28);
		var cx = out.getFloat(q + 40), cy = out.getFloat(q + 44), dx = bx + cx - ax, dy = by + cy - ay;
		// (a quad of a layout gone wrong: drawn as the GPU draws it, nothing, bounding nothing)
		if (!fine(ax) || !fine(ay) || !fine(bx) || !fine(by) || !fine(cx) || !fine(cy)) return;
		if (kind == OVER || kind == BASE) {
			// (less the pixel each is grown by, inside its clip)
			rects.push(Math.max(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + 1, out.getFloat(q + 160)));
			rects.push(Math.max(Math.min(Math.min(ay, by), Math.min(cy, dy)) + 1, out.getFloat(q + 164)));
			rects.push(Math.min(Math.max(Math.max(ax, bx), Math.max(cx, dx)) - 1, out.getFloat(q + 168)));
			rects.push(Math.min(Math.max(Math.max(ay, by), Math.max(cy, dy)) - 1, out.getFloat(q + 172)));
		}
		x0 = Math.min(x0, Math.min(Math.min(ax, bx), Math.min(cx, dx)));
		y0 = Math.min(y0, Math.min(Math.min(ay, by), Math.min(cy, dy)));
		x1 = Math.max(x1, Math.max(Math.max(ax, bx), Math.max(cx, dx)));
		y1 = Math.max(y1, Math.max(Math.max(ay, by), Math.max(cy, dy)));
	}

	public function place(x:Float, y:Float, w:Int, h:Int) {
		ox = x;
		oy = y;
		pw = w;
		ph = h;
	}

	// (its drawable around its quads, on whole pixels: grown by 64 at a
	// time, kept while they fit in half of it, so that it is seldom made again)
	public function fit() {
		if (quads.length == 0 || x1 < x0 || y1 < y0) return;
		var x0 = x0, y0 = y0, x1 = x1, y1 = y1;
		// (a scroller's content: only what its clip shows at an offset in its
		// range, not all its quads cover (its tiles' columns, 512 pixels wide:
		// a 1080 pixel list's layer was 1600 wide))
		if (kind == SCROLL) {
			var s = scale, r = ranges;
			x0 = Math.max(x0, cx0 + (r[0] - drawnX) * s - 1);
			x1 = Math.min(x1, cx1 + (r[0] + r[1] - drawnX) * s + 1);
			y0 = Math.max(y0, cy0 + (r[2] - drawnY) * s - 1);
			y1 = Math.min(y1, cy1 + (r[2] + r[3] - drawnY) * s + 1);
			if (x1 <= x0 || y1 <= y0) return;
		}
		var nx = Math.ffloor(x0), ny = Math.ffloor(y0);
		var w = Std.int(Math.min(8192, Math.fceil(x1) - nx)), h = Std.int(Math.min(8192, Math.fceil(y1) - ny));
		inline function grown(v:Int):Int
			return Std.int(Math.min(8192, Math.ceil(v / 64) * 64));
		if (w > pw || w * 2 < pw) pw = grown(w);
		if (h > ph || h * 2 < ph) ph = grown(h);
		ox = nx;
		oy = ny;
	}

	// (its quads in its pixels, its runs; whether to draw them: other than drawn last, or sampling what was drawn into since)
	public function local(out:Bytes, textures:Array<Null<Texture>>, fresh:Null<Array<Texture>>):Bool {
		var S = CompositeFrame.STRIDE, n = quads.length * S;
		if (bytes.length < n) bytes = Bytes.alloc(n * 2);
		runs.resize(0);
		runTextures.resize(0);
		var w = pw, h = ph, k = 0;
		cover = 0;
		for (j in 0...quads.length) {
			var q = quads[j], o = j * S, t = textures[q];
			bytes.blit(o, out, q * S, S);
			for (c in 0...3) {
				var p = o + c * 16, X = bytes.getFloat(p + 8) - ox, Y = bytes.getFloat(p + 12) - oy;
				bytes.setFloat(p, X / w * 2 - 1);
				bytes.setFloat(p + 4, 1 - Y / h * 2);
				bytes.setFloat(p + 8, X);
				bytes.setFloat(p + 12, Y);
			}
			for (a in [160, 168, 208, 216]) {
				bytes.setFloat(o + a, bytes.getFloat(o + a) - ox);
				bytes.setFloat(o + a + 4, bytes.getFloat(o + a + 4) - oy);
			}
			if (bytes.getFloat(o + 192) != -1e9) {
				bytes.setFloat(o + 192, bytes.getFloat(o + 192) - ox);
				bytes.setFloat(o + 196, bytes.getFloat(o + 196) - oy);
			}
			quadTextures[j] = t;
			var ex = bytes.getFloat(o + 24) - bytes.getFloat(o + 8), ey = bytes.getFloat(o + 28) - bytes.getFloat(o + 12);
			var fx = bytes.getFloat(o + 40) - bytes.getFloat(o + 8), fy = bytes.getFloat(o + 44) - bytes.getFloat(o + 12);
			var a = Math.abs(ex * fy - ey * fx);
			if (fine(a)) cover += Math.min(a, w * h);
			if (runs.length == 0 || runTextures[runTextures.length - 1] != t) {
				runs.push(j);
				runs.push(1);
				runTextures.push(t);
			} else
				runs[runs.length - 1]++;
		}
		len = n;
		var same = n == lastLen && w == lastW && h == lastH && runs.length == lastRuns.length;
		if (same) {
			var i = 0;
			while (i < n) {
				if (last.getInt32(i) != bytes.getInt32(i)) {
					same = false;
					break;
				}
				i += 4;
			}
		}
		if (same) for (i in 0...runs.length)
			if (runs[i] != lastRuns[i] || i % 2 == 0 && runTextures[i >> 1] != lastTextures[i >> 1]) same = false;
		if (same && fresh != null) for (t in runTextures)
			if (t != null && fresh.indexOf(t) >= 0) same = false;
		if (same && !again) return false;
		again = false;
		changed(n, w, h, fresh);
		if (last.length < n) last = Bytes.alloc(bytes.length);
		last.blit(0, bytes, 0, n);
		lastLen = n;
		lastW = w;
		lastH = h;
		lastRuns.resize(0);
		for (v in runs)
			lastRuns.push(v);
		lastTextures.resize(0);
		for (t in runTextures)
			lastTextures.push(t);
		lastQuadTextures.resize(quads.length);
		for (j in 0...quads.length)
			lastQuadTextures[j] = quadTextures[j];
		return true;
	}

	static inline var AGE = 4;

	// (the quads now against those drawn last: the same from the start and
	// from the end, the rest's old and new bounds damaged; one that samples
	// what was drawn into since too; all of it on a new size, a first draw,
	// or past 40% of its pixels, where cutting draws more than drawing whole)
	function changed(n:Int, w:Int, h:Int, fresh:Null<Array<Texture>>) {
		var d = damage, S = CompositeFrame.STRIDE;
		d.clear();
		if (lastLen < 0 || w != lastW || h != lastH) d.everything() else {
			var nq = Std.int(n / S), lq = Std.int(lastLen / S), m = Std.int(Math.min(nq, lq));
			inline function same(a:Int, b:Int):Bool {
				var ok = quadTextures[a] == lastQuadTextures[b], i = 0, oa = a * S, ob = b * S;
				while (ok && i < S) {
					if (bytes.getInt32(oa + i) != last.getInt32(ob + i)) ok = false;
					i += 4;
				}
				return ok;
			}
			var head = 0;
			while (head < m && same(head, head))
				head++;
			var tail = 0;
			while (tail < m - head && same(nq - 1 - tail, lq - 1 - tail))
				tail++;
			for (j in head...nq - tail)
				bound(d, bytes, j * S, w, h);
			for (j in head...lq - tail)
				bound(d, last, j * S, w, h);
			if (fresh != null) for (j in 0...nq)
				if (quadTextures[j] != null && fresh.indexOf(quadTextures[j]) >= 0) bound(d, bytes, j * S, w, h);
			if (d.area() > 0.4 * w * h) d.everything();
		}
		history.push(d.all ? null : [for (i in 0...d.count) for (v in [d.x0(i), d.y0(i), d.x1(i), d.y1(i)]) v]);
		if (history.length > AGE) history.shift();
		serial++;
	}

	// (a quad's bounds at o in b, in its pixels, whole ones, within its clip and the buffer)
	static function bound(d:Damage, b:Bytes, o:Int, w:Int, h:Int) {
		var ax = b.getFloat(o + 8), ay = b.getFloat(o + 12), bx = b.getFloat(o + 24), by = b.getFloat(o + 28);
		var cx = b.getFloat(o + 40), cy = b.getFloat(o + 44), dx = bx + cx - ax, dy = by + cy - ay;
		var x0 = Math.max(Math.min(Math.min(ax, bx), Math.min(cx, dx)), Math.max(0, b.getFloat(o + 160)));
		var y0 = Math.max(Math.min(Math.min(ay, by), Math.min(cy, dy)), Math.max(0, b.getFloat(o + 164)));
		var x1 = Math.min(Math.max(Math.max(ax, bx), Math.max(cx, dx)), Math.min(w, b.getFloat(o + 168)));
		var y1 = Math.min(Math.max(Math.max(ay, by), Math.max(cy, dy)), Math.min(h, b.getFloat(o + 172)));
		if (fine(x0) && fine(y0) && fine(x1) && fine(y1)) d.add(Math.ffloor(x0), Math.ffloor(y0), Math.fceil(x1), Math.fceil(y1));
	}

	// what a buffer drawn at draw `at` (-1: never) misses of what it should
	// show now, its quads cut to it (cutBytes...: background is the colour
	// its rectangles are cleared to, 0xAARRGGBB); false: draw it whole
	public function cut(at:Int, background:Int):Bool {
		var k = serial - at, d = since;
		if (at < 0 || k > history.length || whole()) return false;
		d.clear();
		for (e in history.slice(history.length - k)) {
			if (e == null) return false;
			var i = 0;
			while (i < e.length) {
				d.add(e[i], e[i + 1], e[i + 2], e[i + 3]);
				i += 4;
			}
		}
		if (d.area() > 0.4 * pw * ph) return false;
		var S = CompositeFrame.STRIDE, nq = quads.length, room = (d.count * (nq + 1)) * S;
		if (cutBytes.length < room) cutBytes = Bytes.alloc(room * 2);
		var c = cutBytes, o = 0;
		clears = d.count;
		for (i in 0...d.count) {
			rect(c, o, d.x0(i), d.y0(i), d.x1(i), d.y1(i), pw, ph, background);
			o += S;
		}
		cutRuns.resize(0);
		cutTextures.resize(0);
		var q = 0;
		for (i in 0...d.count) {
			var rx0 = d.x0(i), ry0 = d.y0(i), rx1 = d.x1(i), ry1 = d.y1(i);
			for (j in 0...nq) {
				var b = j * S;
				var ax = bytes.getFloat(b + 8), ay = bytes.getFloat(b + 12), bx = bytes.getFloat(b + 24), by = bytes.getFloat(b + 28);
				var cx = bytes.getFloat(b + 40), cy = bytes.getFloat(b + 44), dx = bx + cx - ax, dy = by + cy - ay;
				if (Math.min(Math.min(ax, bx), Math.min(cx, dx)) >= rx1 || Math.max(Math.max(ax, bx), Math.max(cx, dx)) <= rx0
					|| Math.min(Math.min(ay, by), Math.min(cy, dy)) >= ry1 || Math.max(Math.max(ay, by), Math.max(cy, dy)) <= ry0)
					continue;
				c.blit(o, bytes, b, S);
				// (its fragments outside the rectangle left as they are: UiShader's region)
				c.setFloat(o + 208, Math.max(c.getFloat(o + 208), rx0));
				c.setFloat(o + 212, Math.max(c.getFloat(o + 212), ry0));
				c.setFloat(o + 216, Math.min(c.getFloat(o + 216), rx1));
				c.setFloat(o + 220, Math.min(c.getFloat(o + 220), ry1));
				var t = quadTextures[j];
				if (cutRuns.length == 0 || cutTextures[cutTextures.length - 1] != t) {
					cutRuns.push(q);
					cutRuns.push(1);
					cutTextures.push(t);
				} else
					cutRuns[cutRuns.length - 1]++;
				q++;
				o += S;
			}
		}
		cutLen = o;
		return true;
	}

	// (HELDER_DAMAGE=full: drawn whole, read once it is set)
	static var full:Null<Bool> = null;

	static function whole():Bool {
		if (full == null) full = Sys.getEnv("HELDER_DAMAGE") == "full";
		return full;
	}

	// (the pixels cut's rectangles cover)
	public function cutArea():Float
		return since.area();

	// (UiShader's quad of colour (0xAARRGGBB, premultiplied as drawn)
	// exactly over x0, y0, x1, y1 of a w x h target: whole pixels, no edge
	// grown, drawn without blending, so that it clears them)
	public static function rect(b:Bytes, o:Int, x0:Float, y0:Float, x1:Float, y1:Float, w:Int, h:Int, color:Int) {
		b.fill(o, CompositeFrame.STRIDE, 0);
		inline function corner(at:Int, x:Float, y:Float) {
			b.setFloat(o + at, x / w * 2 - 1);
			b.setFloat(o + at + 4, 1 - y / h * 2);
			b.setFloat(o + at + 8, x);
			b.setFloat(o + at + 12, y);
		}
		corner(0, x0, y0);
		corner(16, x1, y0);
		corner(32, x0, y1);
		var hw = (x1 - x0) / 2, hh = (y1 - y0) / 2, a = (color >>> 24) / 255;
		b.setFloat(o + 64, hw);
		b.setFloat(o + 68, hh);
		b.setFloat(o + 72, hw);
		b.setFloat(o + 76, hh);
		b.setFloat(o + 80, (color >> 16 & 0xFF) / 255 * a);
		b.setFloat(o + 84, (color >> 8 & 0xFF) / 255 * a);
		b.setFloat(o + 88, (color & 0xFF) / 255 * a);
		b.setFloat(o + 92, a);
		b.setFloat(o + 160, x0);
		b.setFloat(o + 164, y0);
		b.setFloat(o + 168, x1);
		b.setFloat(o + 172, y1);
		var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, ix = Math.ffloor(cx), iy = Math.ffloor(cy);
		b.setFloat(o + 192, ix);
		b.setFloat(o + 196, iy);
		b.setFloat(o + 200, cx - ix);
		b.setFloat(o + 204, cy - iy);
		b.setFloat(o + 208, -1e9);
		b.setFloat(o + 212, -1e9);
		b.setFloat(o + 216, 1e9);
		b.setFloat(o + 220, 1e9);
	}

	// (drawn again next frame: its drawable not drawn, or drawn by another)
	public function invalidate()
		lastLen = -1;

	// (not drawn this frame, though it changed: drawn next frame, only what
	// its buffer misses, this frame's change kept in its history)
	public function retry()
		again = true;

	var again = false;

	// (the window's: drawn onto by the textured compositor meanwhile)
	public function reset()
		lastLen = -1;

	// (its system layers let go: what removes and releases them, run after
	// anything that still names them)
	public function free():Void->Void
		return () -> {};
}
#end
