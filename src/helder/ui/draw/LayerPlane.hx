package helder.ui.draw;

#if (hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.Texture;

// A layer of a window's split (LayerSplit): what it is (the window's, what
// is over a unit, a scroller's content, a mover, a node's system layer),
// its key; a scroller's clip and its corners' radii; its quads this frame
// and their bounds; its buffer's size and where it is in the frame's
// pixels; what it drew last (its quads in its pixels and their runs). The
// system's layers extend it (CaLayers', ScLayers').
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
		if (same) return false;
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
		return true;
	}

	// (drawn again next frame: its drawable not drawn, or drawn by another)
	public function invalidate()
		lastLen = -1;

	// (the window's: drawn onto by the textured compositor meanwhile)
	public function reset()
		lastLen = -1;

	// (its system layers let go: what removes and releases them, run after
	// anything that still names them)
	public function free():Void->Void
		return () -> {};
}
#end
