package helder.ui.draw.soft;

import helder.gfx.soft.Chunks;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// UiShader's quads on the CPU: a quad's fields set as the Renderer sets an
// instance's (in target pixels), draw() finds the pixels it may touch and
// records it (QuadRecord), and paint() shades what was recorded, in order,
// by the fragment's own math (UiShapes: the same box, ellipse, dash and
// blur functions) composited over the target (premultiplied, source over,
// in the target's 8-bit values as a GPU blends into RGBA8): the frame's
// bands of rows at once (helder.jobs.Parallel), each band its records in
// the order drawn. Only the pixels near an edge are shaded: a run of pixels
// a rectangle covers whole, inside a clip that covers them whole, is its
// colour. Targets and textures are outside the collector's heap.
@:hxmc.unsafe(gc)
class Quads {
	// the target (RGBA8, tw by th) and where its pixels start in the frame's (a group's buffer: its origin)
	public var target = Ptr.nil();
	public var tw = 1;
	public var th = 1;
	public var ox = 0;
	public var oy = 0;
	// the frame's rectangle drawn into (x0, y0, x1, y1: a window's kept
	// frame, its damage drawn a rectangle at a time; else all of it)
	public var cutX0 = -0x3FFFFFFF;
	public var cutY0 = -0x3FFFFFFF;
	public var cutX1 = 0x3FFFFFFF;
	public var cutY1 = 0x3FFFFFFF;
	// what was drawn into it, in the frame's pixels (x0, y0, x1, y1: a group's, composited alone)
	public var drawnX0 = 0;
	public var drawnY0 = 0;
	public var drawnX1 = 0;
	public var drawnY1 = 0;

	// the quad: its mode (0 a rectangle, 1 a glyph, 2 an image, 3 a shadow, 4 an inset shadow)
	public var mode = 0;
	// (its centre's place, unturned: whole part and fraction; turned: its corners a, b, c)
	public var flat = true;
	public var cx = 0.0;
	public var cy = 0.0;
	public var fx = 0.0;
	public var fy = 0.0;
	public var ax = 0.0;
	public var ay = 0.0;
	public var bx = 0.0;
	public var by = 0.0;
	public var lx = 0.0;
	public var ly = 0.0;
	// (the quad's corners' bounds in target pixels)
	public var x0 = 0.0;
	public var y0 = 0.0;
	public var x1 = 0.0;
	public var y1 = 0.0;
	// its half size, and the corners' place from its centre (with the margin)
	public var hx = 0.0;
	public var hy = 0.0;
	public var ex = 0.0;
	public var ey = 0.0;
	// texture coordinates at the grown corners
	public var u0 = 0.0;
	public var v0 = 0.0;
	public var u1 = 0.0;
	public var v1 = 0.0;
	// the fill and border colours (premultiplied, 0..1)
	public var fr = 0.0;
	public var fg = 0.0;
	public var fb = 0.0;
	public var fa = 0.0;
	public var br = 0.0;
	public var bg = 0.0;
	public var bb = 0.0;
	public var ba = 0.0;
	public var r0 = 0.0;
	public var r1 = 0.0;
	public var r2 = 0.0;
	public var r3 = 0.0;
	public var w0 = 0.0;
	public var w1 = 0.0;
	public var w2 = 0.0;
	public var w3 = 0.0;
	public var blur = 0.0;
	// (mode 0: the border's style; mode 1: read filtered)
	public var style = 0.0;
	// (a glyph's blend: 1 + its contrast, 0 none; its gamma's ratios)
	public var contrast = 0.0;
	public var g0 = 0.0;
	public var g1 = 0.0;
	public var g2 = 0.0;
	public var g3 = 0.0;
	// the clip in target pixels, its corners' radii
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	public var cr0 = 0.0;
	public var cr1 = 0.0;
	public var cr2 = 0.0;
	public var cr3 = 0.0;
	// the texture read: the glyph atlas's coverage (R8) or an image's premultiplied RGBA
	public var tex = Ptr.nil();
	public var texW = 1;
	public var texH = 1;

	final bands:Bands;

	public function new(threads:Int)
		bands = new Bands(threads);

	// (the frame's rows: its bands)
	public function frame(height:Int)
		bands.rows(height);

	// a record of the target's, its pixels px0, py0 to px1, py1 (frame's)
	function record(kind:Int, px0:Int, py0:Int, px1:Int, py1:Int):QuadRecord {
		var r = bands.add(py0, py1);
		r.kind = kind;
		r.px0 = px0;
		r.py0 = py0;
		r.px1 = px1;
		r.py1 = py1;
		r.target = target;
		r.tw = tw;
		r.th = th;
		r.ox = ox;
		r.oy = oy;
		return r;
	}

	// records the quad, over every pixel it and the clip both reach
	public function draw() {
		// (the pixels whose centres the quad covers, as a GPU rasterizes it:
		// left and top edges in, right and bottom out; a turned one's tested each)
		var px0 = Std.int(Math.max(Math.max(Math.ceil(x0 - 0.5), Math.floor(cx0)), ox));
		var py0 = Std.int(Math.max(Math.max(Math.ceil(y0 - 0.5), Math.floor(cy0)), oy));
		var px1 = Std.int(Math.min(Math.min(Math.ceil(x1 - 0.5), Math.ceil(cx1)), ox + tw));
		var py1 = Std.int(Math.min(Math.min(Math.ceil(y1 - 0.5), Math.ceil(cy1)), oy + th));
		if (px0 < cutX0) px0 = cutX0;
		if (py0 < cutY0) py0 = cutY0;
		if (px1 > cutX1) px1 = cutX1;
		if (py1 > cutY1) py1 = cutY1;
		if (px1 <= px0 || py1 <= py0) return;
		if (px0 < drawnX0) drawnX0 = px0;
		if (py0 < drawnY0) drawnY0 = py0;
		if (px1 > drawnX1) drawnX1 = px1;
		if (py1 > drawnY1) drawnY1 = py1;
		var r = record(0, px0, py0, px1, py1);
		r.tex = tex;
		r.texW = texW;
		r.texH = texH;
		helder.ui.draw.soft.QuadBuild.store();
	}

	// a group's pixels (b, bw wide, its top left at gx, gy in the frame's)
	// over the target at alpha, what it drew alone (x0, y0, x1, y1), clipped:
	// UiShader's image quad read at its texels' centres, each texel as it is
	public function group(b:Ptr, bw:Int, gx:Int, gy:Int, alpha:Float, x0:Int, y0:Int, x1:Int, y1:Int) {
		var px0 = Std.int(Math.max(Math.max(x0, Math.floor(cx0)), ox)), py0 = Std.int(Math.max(Math.max(y0, Math.floor(cy0)), oy));
		var px1 = Std.int(Math.min(Math.min(x1, Math.ceil(cx1)), ox + tw)), py1 = Std.int(Math.min(Math.min(y1, Math.ceil(cy1)), oy + th));
		if (px0 < cutX0) px0 = cutX0;
		if (py0 < cutY0) py0 = cutY0;
		if (px1 > cutX1) px1 = cutX1;
		if (py1 > cutY1) py1 = cutY1;
		if (px1 <= px0 || py1 <= py0 || alpha <= 0) return;
		if (px0 < drawnX0) drawnX0 = px0;
		if (py0 < drawnY0) drawnY0 = py0;
		if (px1 > drawnX1) drawnX1 = px1;
		if (py1 > drawnY1) drawnY1 = py1;
		var r = record(1, px0, py0, px1, py1);
		r.tex = b;
		r.texW = bw;
		r.cx = gx;
		r.cy = gy;
		r.fa = alpha;
		r.cx0 = cx0;
		r.cy0 = cy0;
		r.cx1 = cx1;
		r.cy1 = cy1;
		r.cr0 = cr0;
		r.cr1 = cr1;
		r.cr2 = cr2;
		r.cr3 = cr3;
	}

	// the target's pixels x0, y0 to x1, y1 (frame's) set to word (its
	// record, which may be narrowed before it is painted: narrow)
	public function fill(x0:Int, y0:Int, x1:Int, y1:Int, word:Int):Ptr {
		if (x1 <= x0 || y1 <= y0) return Ptr.nil();
		var r = record(2, x0, y0, x1, y1);
		r.word = word;
		return r.ptr();
	}

	public static function narrow(fill:Ptr, x0:Int, y0:Int, x1:Int, y1:Int) {
		if (fill.isNull()) return;
		var r = new QuadRecord(fill);
		if (x1 <= x0 || y1 <= y0) x0 = x1 = y0 = y1 = 0;
		r.px0 = x0;
		r.py0 = y0;
		r.px1 = x1;
		r.py1 = y1;
	}

	// draws cut to the frame's rectangle x0, y0 to x1, y1 (none: all of it)
	public function cut(x0 = -0x3FFFFFFF, y0 = -0x3FFFFFFF, x1 = 0x3FFFFFFF, y1 = 0x3FFFFFFF) {
		cutX0 = x0;
		cutY0 = y0;
		cutX1 = x1;
		cutY1 = y1;
	}

	// what was recorded painted, the records let go
	public function paint()
		bands.paint();

	// memory for the frame's records' while they are recorded (a group's
	// buffer, an image's texels as they are when drawn), let go with them
	public function scratch(n:Int):Ptr
		return bands.scratch(n);

	public function dispose()
		bands.dispose();

	public static inline function q(v:Float):Int
		return QuadRecord.q(v);
}

// Quads' records binned by bands of the frame's rows, each band painted
// its records in order, the bands at once (a GC-free callback, Parallel's)
@:hxmc.unsafe(gc)
class Bands {
	public static inline var SHIFT = 4;

	// a band's records: chunks of 63 (Raster's bins: the first, the last, how many in the last)
	static inline var FIRST = 0;
	static inline var LAST = 8;
	static inline var COUNT = 16;
	static inline var BIN = 24;
	static inline var CHUNK = 512;
	static inline var ENTRIES = 63;

	final memory = new Chunks();
	final threads:Int;
	var bins = Ptr.nil();
	var count = 0;
	var size = 0;
	var pending = false;

	public function new(threads:Int)
		this.threads = threads;

	public function rows(height:Int) {
		var n = (height + (1 << SHIFT) - 1) >> SHIFT;
		if (n > size) {
			LibC.free(bins);
			bins = LibC.malloc(n * BIN);
			size = n;
			LibC.memset(bins, 0, n * BIN);
		}
		count = n;
	}

	public function add(y0:Int, y1:Int):QuadRecord {
		var r = new QuadRecord(memory.alloc(QuadRecord.RECORD));
		var b0 = y0 >> SHIFT, b1 = (y1 - 1) >> SHIFT;
		if (b0 < 0) b0 = 0;
		if (b1 >= count) b1 = count - 1;
		for (b in b0...b1 + 1)
			bin(bins.add(BIN * b), r.ptr());
		pending = true;
		return r;
	}

	function bin(b:Ptr, t:Ptr) {
		var last = Mem.getPtr(b, LAST), n = Mem.getI32(b, COUNT);
		if (last.isNull() || n == ENTRIES) {
			var c = memory.alloc(CHUNK);
			Mem.setPtr(c, 0, Ptr.nil());
			if (last.isNull()) Mem.setPtr(b, FIRST, c) else Mem.setPtr(last, 0, c);
			Mem.setPtr(b, LAST, c);
			last = c;
			n = 0;
		}
		Mem.setPtr(last, 8 + 8 * n, t);
		Mem.setI32(b, COUNT, n + 1);
	}

	public function scratch(n:Int):Ptr
		return memory.alloc(n);

	public function paint() {
		if (pending) helder.jobs.Parallel.run(BandCall.address(), bins, count, threads);
		pending = false;
		LibC.memset(bins, 0, size * BIN);
		memory.reset();
	}

	public function dispose() {
		memory.free();
		LibC.free(bins);
		bins = Ptr.nil();
		size = count = 0;
	}

	// (band i's records, in order, each copied where its band's state goes beside it)
	@:hxmc.callback @:hxmc.unsafe public static function band(bins:Ptr, i:Int):Int {
		var bin = bins.add(BIN * i);
		var chunk = Mem.getPtr(bin, FIRST), last = Mem.getPtr(bin, LAST), n = Mem.getI32(bin, COUNT);
		if (chunk.isNull()) return 0;
		var s = Mem.stack(QuadRecord.SIZE), b0 = i << SHIFT, b1 = b0 + (1 << SHIFT);
		while (!chunk.isNull()) {
			var k = chunk == last ? n : ENTRIES;
			for (j in 0...k) {
				LibC.memcpy(s, Mem.getPtr(chunk, 8 + 8 * j), QuadRecord.RECORD);
				new QuadRecord(s).paint(b0, b1);
			}
			chunk = Mem.getPtr(chunk, 0);
		}
		return 0;
	}
}

// (Bands.band's address)
@:hxmc.unsafe(gc)
private class BandCall {
	static var addr = Ptr.nil();

	public static function address():Ptr {
		if (addr.isNull()) addr = hxmc.unsafe.Callback.addr(Bands.band);
		return addr;
	}
}
