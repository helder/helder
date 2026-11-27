package helder.ui.box;

import haxe.ds.ObjectMap;
import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Blend.Blender;
import helder.canvas.Filter;
import helder.canvas.GlyphText;
import helder.canvas.Mask;
import helder.canvas.Matrix;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;
import helder.canvas.ShapedRun;
import helder.canvas.Stroke;
import helder.gfx.Color;
import helder.image.Image;
import helder.os.Edges;
import helder.ui.Corners;
import helder.ui.draw.RunParagraph;

// helder.canvas's Painter on a helder.ui Canvas (what Ui.paint records, the
// GPU Renderer draws), so that BoxPainter, the engine's one painter, draws
// into a window: rectangles, rounded ones and their borders (a ring of two)
// as the Canvas's rect; glyph runs as text (GlyphText: each run a
// RunParagraph, which the Renderer draws from its glyph atlas); images as
// images. What the Canvas has no call for (gradients and patterns, other
// paths, strokes, shadows' blurs) is drawn on the CPU at the window's scale,
// within what is seen, and drawn as an image. Clips are rectangles, rounded
// ones with their radii (another path's its bounds); layers groups;
// transforms pushed, each save's undone at its restore.
class UiPainter implements Painter implements GlyphText implements ShadowPainter {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var matrix(get, never):Matrix;
	public var canvas:helder.ui.Canvas;
	// the window's pixels a unit (the CPU's drawings' resolution)
	public var pixels = 1.0;
	// what is seen (x0, y0, x1, y1, untransformed): the CPU's drawings cut to it
	public final view:Array<Float> = [0, 0, 0, 0];
	// the CPU's drawings and their pixels this paint (a test's, a bench's)
	public var rasters(default, null) = 0;
	public var rasterPixels(default, null) = 0;

	final m = new Matrix();
	// (per save: the transform then, 6 each, and how many pushes were made before it)
	final saved:Array<Float> = [];
	final marks:Array<Int> = [];
	// (what was pushed onto the canvas, in order: CLIP, GROUP, TRANSFORM)
	final pushed:Array<Int> = [];
	// (the images made of bitmaps, kept while they are drawn in each paint)
	var images = new ObjectMap<Bitmap, Image>();
	var drawn = new ObjectMap<Bitmap, Image>();
	// (the CPU's drawings by what they draw, kept while drawn in each paint: a repaint draws none again)
	var rastered = new Map<String, Image>();
	var redrawn = new Map<String, Image>();

	static inline var CLIP = 0;
	static inline var GROUP = 1;
	static inline var TRANSFORM = 2;

	public function new(canvas:helder.ui.Canvas, width:Int, height:Int) {
		this.canvas = canvas;
		this.width = width;
		this.height = height;
	}

	// A paint begins: on canvas, in the window's pixels a unit, what is seen
	public function begin(canvas:helder.ui.Canvas, width:Int, height:Int, scale:Float, x0:Float, y0:Float, x1:Float, y1:Float) {
		this.canvas = canvas;
		this.width = width;
		this.height = height;
		pixels = scale;
		view[0] = x0;
		view[1] = y0;
		view[2] = x1;
		view[3] = y1;
		m.identity();
		rasters = rasterPixels = 0;
	}

	// ... and ends: what was pushed popped, the images not drawn let go
	public function end() {
		restoreToCount(0);
		var was = images;
		images = drawn;
		drawn = was;
		drawn.clear();
		var r = rastered;
		rastered = redrawn;
		redrawn = r;
		redrawn.clear();
		// (the numbers given out let go now and then: never given again, a kept key never meets another bitmap)
		if (nextId - idsFrom > 4096) {
			ids = new ObjectMap();
			idsFrom = nextId;
		}
	}

	inline function get_matrix():Matrix
		return m;

	public function save() {
		for (v in [m.a, m.b, m.c, m.d, m.e, m.f]) saved.push(v);
		marks.push(pushed.length);
	}

	public function saveLayer(alpha:Float = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter) {
		save();
		if (alpha >= 1) return;
		// (under a transform its bounds are unknown here: all of it)
		if (m.isIdentity()) canvas.pushGroup(alpha, view[0], view[1], view[2] - view[0], view[3] - view[1]);
		else canvas.pushGroup(alpha, -1e6, -1e6, 2e6, 2e6);
		pushed.push(GROUP);
	}

	public function restore() {
		if (marks.length == 0) return;
		var to = marks.pop();
		while (pushed.length > to) switch pushed.pop() {
			case CLIP: canvas.popClip();
			case GROUP: canvas.popOpacity();
			case _: canvas.popTransform();
		}
		var n = saved.length - 6;
		m.set(saved[n], saved[n + 1], saved[n + 2], saved[n + 3], saved[n + 4], saved[n + 5]);
		saved.resize(n);
	}

	public function restoreToCount(count:Int)
		while (marks.length > count) restore();

	public function translate(x:Float, y:Float)
		transform(1, 0, 0, 1, x, y);

	public function scale(x:Float, y:Float)
		transform(x, 0, 0, y, 0, 0);

	public function rotate(angle:Float) {
		var c = Math.cos(angle), s = Math.sin(angle);
		transform(c, s, -s, c, 0, 0);
	}

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		if (a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0) return;
		canvas.pushTransform(a, b, c, d, e, f);
		pushed.push(TRANSFORM);
		m.transform(a, b, c, d, e, f);
	}

	// (the canvas's transforms are pushed: the one that takes the current to the one asked for)
	public function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		var inv = new Matrix();
		if (!m.invertInto(inv)) return;
		inv.transform(a, b, c, d, e, f);
		transform(inv.a, inv.b, inv.c, inv.d, inv.e, inv.f);
	}

	public function resetTransform()
		setTransform(1, 0, 0, 1, 0, 0);

	public function clip(path:Path, evenOdd:Bool = false) {
		var r = shape(path, 0);
		if (r != null && r.next < 0) canvas.pushClip(r.x, r.y, r.w, r.h, r.radius, r.corners);
		else {
			var b = bounds(path);
			canvas.pushClip(b[0], b[1], b[2] - b[0], b[3] - b[1], 0);
		}
		pushed.push(CLIP);
	}

	public function fill(path:Path, paint:Paint, evenOdd:Bool = false) {
		if (path.verbCount == 0) return;
		if (paint.shader == null && paint.blend == null) {
			var color = colorOf(paint);
			if (color.a == 0) return;
			var r = shape(path, 0);
			if (r != null && r.next < 0) {
				canvas.rect(r.x, r.y, r.w, r.h, r.radius, color, 0, Color.TRANSPARENT, r.corners);
				return;
			}
			// (a ring: a box's border, every side one colour)
			if (r != null && evenOdd) {
				var i = shape(path, r.next);
				if (i != null && i.next < 0 && i.x >= r.x && i.y >= r.y && i.x + i.w <= r.x + r.w && i.y + i.h <= r.y + r.h) {
					var sides = new Edges(i.y - r.y, r.x + r.w - i.x - i.w, r.y + r.h - i.y - i.h, i.x - r.x);
					var most = Math.max(Math.max(sides.top, sides.right), Math.max(sides.bottom, sides.left));
					canvas.rect(r.x, r.y, r.w, r.h, r.radius, Color.TRANSPARENT, most, color, r.corners, sides);
					return;
				}
			}
		}
		var b = bounds(path);
		raster(b[0], b[1], b[2], b[3], c -> c.fill(path, paint, evenOdd), keyOf(path) + (evenOdd ? "e" : "n") + keyOfPaint(paint));
	}

	public function stroke(path:Path, style:Stroke, paint:Paint) {
		if (path.verbCount == 0) return;
		var b = bounds(path), e = style.width * 2 + 1;
		var d = style.dash == null ? "" : Std.string(style.dash);
		raster(b[0] - e, b[1] - e, b[2] + e, b[3] + e, c -> c.stroke(path, style, paint),
			keyOf(path) + 's${style.width} ${style.join} ${style.cap} ${style.miterLimit} $d' + keyOfPaint(paint));
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {}

	public function clear(color:Color = 0)
		if (color.a > 0) canvas.rect(view[0], view[1], view[2] - view[0], view[3] - view[1], 0, color, 0, Color.TRANSPARENT);

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth:Bool = true) {
		if (img.width <= 0 || img.height <= 0 || dw <= 0 || dh <= 0) return;
		var i = drawn.get(img);
		if (i == null) {
			i = images.get(img) ?? img.toImage();
			drawn.set(img, i);
		}
		var faded = paint.alpha < 1;
		if (faded) canvas.pushOpacity(paint.alpha);
		canvas.image(i, dx, dy, dw, dh, sx / img.width, sy / img.height, (sx + sw) / img.width, (sy + sh) / img.height, 0);
		if (faded) canvas.popOpacity();
	}

	// (a run of one face: a paragraph of one line, its glyphs as placed)
	public function glyphText(run:ShapedRun, paint:Paint, ?stroke:Stroke):Bool {
		if (stroke != null || paint.shader != null || run.scaleX != 1) return false;
		var n = run.count;
		if (n == 0) return true;
		var color = colorOf(paint);
		if (color.a == 0) return true;
		var x0 = run.xs[0], base = run.ys[0], right = x0;
		for (k in 0...n) if (run.xs[k] > right) right = run.xs[k];
		var w = right - x0 + run.size;
		var p = new RunParagraph(w, run.size, w, 0, run.size, [{top: 0, baseline: 0, width: w, height: run.size, start: 0, end: n}]);
		var oblique = run.skew != 0;
		for (k in 0...n) {
			p.faces.push(run.face);
			p.ids.push(run.ids[k]);
			p.xs.push(run.xs[k] - x0);
			p.dys.push(run.ys[k] - base);
			p.sizes.push(run.size);
			p.obliques.push(oblique);
			p.spans.push(-1);
		}
		canvas.text(p, x0, base, w, Left, color);
		return true;
	}

	// (shadows: the Canvas's, blurred on the GPU; its corners circular, of the radii across)
	public function outerShadow(x:Float, y:Float, w:Float, h:Float, radii:Null<Array<Float>>, color:Int, blur:Float, dx:Float, dy:Float, spread:Float):Bool {
		var c = corners(radii);
		canvas.shadow(x, y, w, h, c == null ? 0 : c.topLeft, color, blur, c, [dx, dy, spread]);
		return true;
	}

	public function innerShadow(x:Float, y:Float, w:Float, h:Float, radii:Null<Array<Float>>, color:Int, blur:Float, dx:Float, dy:Float, spread:Float):Bool {
		var c = corners(radii);
		canvas.insetShadow(x, y, w, h, c == null ? 0 : c.topLeft, color, blur, dx, dy, spread, c);
		return true;
	}

	static function corners(r:Null<Array<Float>>):Null<Corners>
		return r == null ? null : new Corners(r[0], r[2], r[4], r[6]);

	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int)
		throw "UiPainter: no pixels to read";

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride:Int = -1)
		throw "UiPainter: no pixels to write";

	public function snapshot():Bitmap
		throw "UiPainter: no pixels to read";

	// (a shadow's blur and the like: drawn on the CPU, then drawn here as an image)
	public function offscreen(width:Int, height:Int):Painter
		return new helder.canvas.Canvas(width, height);

	static inline function colorOf(p:Paint):Color {
		var c = p.color;
		return p.alpha >= 1 ? c : (Math.round(c.a * p.alpha) << 24) | ((c : Int) & 0xFFFFFF);
	}

	// (drawn on the CPU over x0, y0, x1, y1 in the window's pixels, cut to
	// what is seen where nothing is transformed, then drawn as an image)
	function raster(x0:Float, y0:Float, x1:Float, y1:Float, draw:helder.canvas.Canvas->Void, key:String) {
		if (m.isIdentity()) {
			x0 = Math.max(x0, view[0]);
			y0 = Math.max(y0, view[1]);
			x1 = Math.min(x1, view[2]);
			y1 = Math.min(y1, view[3]);
		}
		var k = pixels, px0 = Math.floor(x0 * k), py0 = Math.floor(y0 * k);
		var w = Std.int(Math.ceil(x1 * k) - px0), h = Std.int(Math.ceil(y1 * k) - py0);
		if (w <= 0 || h <= 0 || w * h > 4096 * 4096) return;
		var m = this.m;
		key += ' $k $px0 $py0 $w $h ${m.a} ${m.b} ${m.c} ${m.d} ${m.e} ${m.f}';
		var img = redrawn.get(key) ?? rastered.get(key);
		if (img == null) {
			var c = new helder.canvas.Canvas(w, h);
			c.setTransform(k, 0, 0, k, -px0, -py0);
			draw(c);
			rasters++;
			rasterPixels += w * h;
			img = c.snapshot().toImage();
		}
		redrawn.set(key, img);
		canvas.image(img, px0 / k, py0 / k, w / k, h / k, 0, 0, 1, 1, 0);
	}

	// (what a path draws, as a key: its verbs and points)
	static function keyOf(p:Path):String {
		var b = new StringBuf();
		for (i in 0...p.verbCount) b.addChar(48 + p.verbs[i]);
		for (i in 0...p.pointCount * 2) {
			b.addChar(32);
			b.add(Math.round(p.points[i] * 64));
		}
		return b.toString();
	}

	// (what a paint draws with, as a key: its colour, a gradient's geometry and stops; another shader none: drawn each time)
	function keyOfPaint(p:Paint):String {
		var b = new StringBuf();
		b.add('|${p.color} ${p.alpha} ${p.blend != null}');
		var sh = p.shader;
		if (sh == null) return b.toString();
		inline function matrix(m:Matrix)
			b.add(' ${m.a} ${m.b} ${m.c} ${m.d} ${m.e} ${m.f}');
		if (Std.isOfType(sh, helder.canvas.Gradient)) {
			var g:helder.canvas.Gradient = cast sh;
			if (Std.isOfType(sh, helder.canvas.Gradient.LinearGradient)) {
				var l:helder.canvas.Gradient.LinearGradient = cast sh;
				b.add(' L${l.x0} ${l.y0} ${l.x1} ${l.y1}');
			} else if (Std.isOfType(sh, helder.canvas.Gradient.RadialGradient)) {
				var r:helder.canvas.Gradient.RadialGradient = cast sh;
				b.add(' R${r.x0} ${r.y0} ${r.r0} ${r.x1} ${r.y1} ${r.r1}');
			} else if (Std.isOfType(sh, helder.canvas.Gradient.ConicGradient)) {
				var c:helder.canvas.Gradient.ConicGradient = cast sh;
				b.add(' C${c.start} ${c.x} ${c.y}');
			} else return b.toString() + ' ?${Std.random(1 << 30)}';
			matrix(g.matrix);
			b.add(' ${g.spread} ${g.premultiplied}');
			for (i in 0...g.stopCount) b.add(' ${g.stopOffset(i)}:${g.stopColor(i)}');
		} else if (Std.isOfType(sh, helder.canvas.Pattern)) {
			var t:helder.canvas.Pattern = cast sh;
			b.add(' P${idOf(t.bitmap)} ${t.repeatX} ${t.repeatY} ${t.smooth} ${t.clamp}');
			matrix(t.matrix);
		} else return b.toString() + ' ?${Std.random(1 << 30)}';
		return b.toString();
	}

	// (a bitmap's number while it is drawn in each paint: a pattern's key)
	var ids = new ObjectMap<Bitmap, Int>();
	var nextId = 0;
	var idsFrom = 0;

	function idOf(b:Bitmap):Int {
		var id = ids.get(b);
		if (id == null) ids.set(b, id = nextId++);
		return id;
	}

	// (what a path's points cover: x0, y0, x1, y1)
	static function bounds(p:Path):Array<Float> {
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		var pts = p.points;
		var i = 0;
		while (i < p.pointCount * 2) {
			var x = pts[i], y = pts[i + 1];
			if (x < x0) x0 = x;
			if (x > x1) x1 = x;
			if (y < y0) y0 = y;
			if (y > y1) y1 = y;
			i += 2;
		}
		return x0 > x1 ? [0, 0, 0, 0] : [x0, y0, x1, y1];
	}

	// (the subpath from verb `from` as a rectangle, its corners rounded: every
	// point on its bounds' sides, its lines along them, its curves from one
	// side to the next; null: another shape. A circle is a square rounded by
	// half its side.)
	static function shape(p:Path, from:Int):Null<Shape> {
		var verbs = p.verbs, pts = p.points, n = p.verbCount;
		if (from >= n || verbs[from] != Path.MOVE) return null;
		// (the subpath's verbs and its first point)
		var pi = 0;
		for (v in 0...from) pi += points(verbs[v]);
		var end = from + 1;
		while (end < n && verbs[end] != Path.MOVE) end++;
		var start = pi, count = 0;
		for (v in from...end) count += points(verbs[v]);
		if (count < 4) return null;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (k in 0...count) {
			var x = pts[(start + k) * 2], y = pts[(start + k) * 2 + 1];
			if (x < x0) x0 = x;
			if (x > x1) x1 = x;
			if (y < y0) y0 = y;
			if (y > y1) y1 = y;
		}
		if (x1 - x0 <= 0 || y1 - y0 <= 0) return null;
		var e = 1e-3 * Math.max(1, Math.max(x1 - x0, y1 - y0));
		// (each point's sides: 1 left, 2 top, 4 right, 8 bottom)
		inline function side(x:Float, y:Float):Int
			return (Math.abs(x - x0) <= e ? 1 : 0) | (Math.abs(y - y0) <= e ? 2 : 0) | (Math.abs(x - x1) <= e ? 4 : 0) | (Math.abs(y - y1) <= e ? 8 : 0);
		var tl = Math.POSITIVE_INFINITY, tr = Math.POSITIVE_INFINITY, br = Math.POSITIVE_INFINITY, bl = Math.POSITIVE_INFINITY;
		var at = start, px = pts[start * 2], py = pts[start * 2 + 1];
		for (v in from...end) {
			var k = points(verbs[v]);
			for (j in 0...k) {
				var x = pts[(at + j) * 2], y = pts[(at + j) * 2 + 1], s = side(x, y);
				if (s == 0) return null;
				// (the corners' radii from where the sides' lines end, not from curves' control points)
				if (j < k - 1) continue;
				if (s & 2 != 0) {
					tl = Math.min(tl, x - x0);
					tr = Math.min(tr, x1 - x);
				}
				if (s & 8 != 0) {
					bl = Math.min(bl, x - x0);
					br = Math.min(br, x1 - x);
				}
			}
			switch verbs[v] {
				case Path.LINE:
					var x = pts[at * 2], y = pts[at * 2 + 1];
					if (Math.abs(x - px) > e && Math.abs(y - py) > e) return null;
					px = x;
					py = y;
				case Path.CUBIC | Path.QUAD:
					var x = pts[(at + k - 1) * 2], y = pts[(at + k - 1) * 2 + 1];
					// (a corner's curve: from one side to another, not along one)
					if (side(px, py) & side(x, y) != 0) return null;
					px = x;
					py = y;
				case _:
			}
			at += k;
		}
		// (the close: back along a side)
		var sx = pts[start * 2], sy = pts[start * 2 + 1];
		if (Math.abs(sx - px) > e && Math.abs(sy - py) > e) return null;
		inline function fin(v:Float):Float
			return v == Math.POSITIVE_INFINITY ? 0 : v;
		var c = new Corners(fin(tl), fin(tr), fin(br), fin(bl));
		var same = c.topLeft == c.topRight && c.topLeft == c.bottomRight && c.topLeft == c.bottomLeft;
		return {
			x: x0,
			y: y0,
			w: x1 - x0,
			h: y1 - y0,
			radius: same ? c.topLeft : Math.max(Math.max(c.topLeft, c.topRight), Math.max(c.bottomRight, c.bottomLeft)),
			corners: same ? null : c,
			next: end < n ? end : -1
		};
	}

	static inline function points(verb:Int):Int
		return switch verb {
			case Path.MOVE | Path.LINE: 1;
			case Path.QUAD: 2;
			case Path.CUBIC: 3;
			case _: 0;
		}
}

private typedef Shape = {x:Float, y:Float, w:Float, h:Float, radius:Float, corners:Null<Corners>, next:Int};
