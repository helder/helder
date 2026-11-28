package helder.ui.draw;

import helder.os.Edges;
import haxe.io.Bytes;
import helder.gfx.Color;
import helder.gfx.Texture;
import helder.image.Image;
import helder.text.FontFile;
import helder.ui.*;
import helder.ui.Paint.PaintValue;
import helder.ui.draw.DrawText.DrawParagraph;

// A frame written as data (the studio's stills: FrameArchive): a canvas a
// Ui paints into (Ui.paint walks every layer onto it, so it sees the frame
// flat: the drawing calls alone, in order), each call an op and its
// numbers in column streams (FrameStreams), what it takes by reference as
// data: paths (their commands), paints (a colour, a gradient's stops),
// strokes, corners, edges, paragraphs (their lines and placed glyphs:
// RunParagraph's, each glyph's face a font by its file's hash), images (by
// the hash of their pixels: stored once, FrameArchive). What a pass draws
// on the GPU (a scene, a part shader, a video, sprites, glass) is its box
// (FrameOp.PLACEHOLDER: GpuPlaceholder's when read); a system layer, nothing.
//
//   var w = new FrameWriter();
//   ui.paint(w);
//   archive.add(name, key, ui.width, ui.height, w.frame());
class FrameWriter implements TextureCanvas {
	var out = new FrameStreams();
	// (this frame's fonts and images, by their index in it: its loop's too)
	final fonts:Array<FontFile> = [];
	// (a picture's as it was read: its pixels let go, a loop's hundreds not held)
	final images:Array<ImageRef> = [];
	// the passes drawn as placeholders (what a frame of data cannot show),
	// and those drawn as their pictures (read back from the GPU)
	public var passes(default, null) = 0;
	public var pictures(default, null) = 0;
	// the renderer whose frame it writes again (gpu): the GPU host what draws
	// on the GPU finds (Renderer.of), its pass done in that frame, its texture
	// read back (pixels) for its box to be its picture; null: a placeholder
	public var host(default, null):Null<Renderer> = null;
	public var pixels:Null<Texture->Null<Image>> = null;
	// (a loop after the still: its fps, the still's streams, its frames' records)
	var fps = 0;
	var still:Null<Bytes> = null;
	var stillPasses = 0;
	final loopFrames:Array<Array<FrameStreams.FrameRec>> = [];

	public function new() {}

	// what was painted: its streams, the fonts and images they name, its loop's frames
	public function frame():Frame {
		if (fps > 0) loopFrames.push(out.records());
		return {
			bytes: still ?? out.bytes(),
			fonts: [for (f in fonts) FrameArchive.fontRef(f)],
			images: images.copy(),
			// (a loop a pass draws in: none, played live)
			loop: fps > 0 && loopFrames.length > 0 && passes == stillPasses ? {fps: fps, frames: FrameLoop.encode(loopFrames)} : null
		};
	}

	// the still painted: what is painted next is its loop's first frame, at fps
	public function loop(fps:Int) {
		// (its frames drawn by no renderer unless given one again (gpu, each
		// frame's): a pass in them a placeholder, counted)
		host = null;
		pixels = null;
		stillPasses = passes;
		still = out.bytes();
		this.fps = fps;
		out = new FrameStreams(true);
	}

	// (a pass recorded into a list painted onto it)
	public function passed()
		passes++;

	// a loop's next frame (after loop's first)
	public function next() {
		loopFrames.push(out.records());
		out = new FrameStreams(true);
	}

	// (a pass's box drawn by a node that draws on the GPU: GpuPlaceholder's)
	public function placeholder(x:Float, y:Float, w:Float, h:Float) {
		passed();
		out.op(FrameOp.PLACEHOLDER);
		box(x, y, w, h);
	}

	public function translate(dx:Float, dy:Float) {
		out.op(FrameOp.TRANSLATE);
		out.float(0, dx);
		out.float(1, dy);
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		out.op(FrameOp.PUSH_CLIP);
		box(x, y, w, h);
		out.float(10, radius);
		this.corners(corners);
	}

	public function popClip()
		out.op(FrameOp.POP_CLIP);

	public function pushOpacity(alpha:Float) {
		out.op(FrameOp.PUSH_OPACITY);
		out.float(11, alpha);
	}

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float) {
		out.op(FrameOp.PUSH_GROUP);
		out.float(11, alpha);
		box(x, y, w, h);
	}

	public function popOpacity()
		out.op(FrameOp.POP_OPACITY);

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		out.op(FrameOp.PUSH_TRANSFORM);
		for (k => v in [a, b, c, d, e, f])
			out.float(20 + k, v);
	}

	public function popTransform()
		out.op(FrameOp.POP_TRANSFORM);

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
			style:BorderStyle = Solid) {
		out.op(FrameOp.RECT);
		box(x, y, w, h);
		out.float(10, radius);
		out.color(fill);
		out.float(12, borderWidth);
		out.color(border);
		this.corners(corners);
		edges(sides);
		out.uint((cast style : Int));
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		out.op(FrameOp.SHADOW);
		box(x, y, w, h);
		out.float(10, radius);
		out.color(color);
		out.float(13, blur);
		this.corners(corners);
		out.uint(offset == null ? 0 : offset.length + 1);
		if (offset != null)
			for (v in offset)
				out.float(14, v);
	}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners) {
		out.op(FrameOp.INSET_SHADOW);
		box(x, y, w, h);
		out.float(10, radius);
		out.color(color);
		out.float(13, blur);
		out.float(15, dx);
		out.float(16, dy);
		out.float(17, spread);
		this.corners(corners);
	}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		out.op(FrameOp.PATH);
		out.bool(p.evenOdd);
		out.uint(p.commands.length);
		for (k => v in p.commands)
			out.float(30 + (k & 7), v);
		paint(fill);
		out.bool(stroke != null);
		if (stroke == null) return;
		out.float(40, stroke.width);
		paint(stroke.paint);
		out.string(stroke.cap == null ? "" : (cast stroke.cap : String));
		out.string(stroke.join == null ? "" : (cast stroke.join : String));
		out.float(41, stroke.miterLimit ?? -1);
		out.uint(stroke.dashes == null ? 0 : stroke.dashes.length + 1);
		if (stroke.dashes != null)
			for (d in stroke.dashes)
				out.float(42, d);
		out.float(43, stroke.dashOffset ?? 0);
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners)
		drawn(img == null ? null : FrameArchive.imageRef(img), x, y, w, h, u0, v0, u1, v1, radius, corners);

	function drawn(r:Null<ImageRef>, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		out.op(FrameOp.IMAGE);
		out.uint(r == null ? 0 : refIndex(r) + 1);
		box(x, y, w, h);
		out.float(50, u0);
		out.float(51, v0);
		out.float(52, u1);
		out.float(53, v1);
		out.float(10, radius);
		this.corners(corners);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {
		out.op(FrameOp.TEXT);
		textCall(p, x, y, width, align, color, colors);
	}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {
		out.op(FrameOp.TEXT_SHADOW);
		textCall(p, x, y, width, align, color, colors);
		out.float(13, blur);
	}

	function textCall(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, colors:Null<Array<Color>>) {
		out.float(0, x);
		out.float(1, y);
		out.float(2, width);
		out.string((cast align : String));
		out.color(color);
		out.uint(colors == null ? 0 : colors.length + 1);
		if (colors != null)
			for (c in colors)
				out.color(c);
		paragraph(p);
	}

	// (what a pass draws: its box; read back, a placeholder)
	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners) {
		// (what it draws as data, given: kept as that)
		var f = datas.get(id), d = f == null ? null : f();
		if (d != null) {
			out.op(FrameOp.PASS_DATA);
			box(x, y, w, h);
			out.float(10, radius);
			this.corners(corners);
			d.write(out);
			return;
		}
		var img = pixels == null ? null : pixels(t);
		if (img == null) placeholder(x, y, w, h) else {
			pictures++;
			drawn(FrameArchive.pixelsRef(img, fps > 0), x, y, w, h, 0, 0, 1, 1, radius, corners);
		}
	}

	// (what a node that draws on the GPU draws, as data, by the id its
	// texture is drawn with: asked for as that texture is, null: its picture)
	final datas = new Map<Int, Void->Null<PassData>>();

	public function data(id:Int, f:Void->Null<PassData>)
		datas.set(id, f);

	// the writer a canvas paints into (a list recorded for it: its target's), or null
	public static function of(c:Null<Canvas>):Null<FrameWriter> {
		var at = c;
		while (true) {
			var l = Std.downcast(at, DisplayList);
			if (l == null || l.target == null) break;
			at = l.target;
		}
		return Std.downcast(at, FrameWriter);
	}

	// a pass's box its picture: what r drew in its last frame (painted
	// after it, before its next), the textures read back
	public function gpu(r:Renderer) {
		host = r;
		pixels = read(r.device);
	}

	// a device's textures read back (frameInto, readPixels: no frame on its way), each its pixels as an image
	public static function read(device:helder.gfx.Device):Texture->Null<Image>
		return t -> {
			device.frameInto(t);
			var enc = device.beginFrame();
			var img = enc == null ? null : {
				var w = device.width, h = device.height, px = Bytes.alloc(w * h * 4);
				device.readPixels(px);
				new Image(w, h, px);
			}
			device.endFrame();
			device.frameInto(null);
			img;
		}

	public function pass(f:Any) {}

	public function slot(s:LayerSlot, x:Float, y:Float, w:Float, h:Float) {}

	// (every layer replayed onto it, none kept: a frame of calls)
	public function layerTiles(l:Layer):Bool
		return false;

	public function keeps():Bool
		return false;

	public function damage(d:Damage) {}

	public function redraw(i:Int) {}

	public function composites():Bool
		return false;

	public function enter(n:Node, kind:Int):Bool
		return false;

	public function mover(m:Mover):Bool
		return false;

	public function leave() {}

	inline function box(x:Float, y:Float, w:Float, h:Float) {
		out.float(0, x);
		out.float(1, y);
		out.float(2, w);
		out.float(3, h);
	}

	function corners(c:Null<Corners>) {
		out.bool(c != null);
		if (c == null) return;
		out.float(60, c.topLeft);
		out.float(61, c.topRight);
		out.float(62, c.bottomRight);
		out.float(63, c.bottomLeft);
	}

	function edges(e:Null<Edges>) {
		out.bool(e != null);
		if (e == null) return;
		out.float(64, e.top);
		out.float(65, e.right);
		out.float(66, e.bottom);
		out.float(67, e.left);
	}

	// (none: 0; a colour: 1; a gradient: 2, its data)
	function paint(p:Null<Paint>) {
		if (p == null) {
			out.uint(0);
			return;
		}
		switch (p : PaintValue) {
			case Solid(c):
				out.uint(1);
				out.color(c);
			case Gradient(g):
				out.uint(2);
				gradient(out, g);
		}
	}

	@:access(helder.ui.Gradient)
	public static function gradient(out:FrameStreams, g:Gradient) {
		out.bool(g.linear);
		out.bool(g.repeating);
		out.float(70, g.angle);
		out.bool(g.corner != null);
		if (g.corner != null) {
			out.int(g.corner.x);
			out.int(g.corner.y);
		}
		out.bool(g.circle);
		out.string(g.size);
		out.string(g.sizeX ?? "\x00");
		out.string(g.sizeY ?? "\x00");
		out.string(g.atX);
		out.string(g.atY);
		out.uint(g.colors.length);
		for (c in g.colors)
			out.color(c);
		for (p in g.positions)
			out.string(p ?? "\x00");
	}

	// a paragraph's lines and glyphs as they are placed (the Renderer's own
	// reading of them: glyphs, placed); a text engine's but helder's: nothing
	function paragraph(p:Paragraph) {
		var dp = Std.downcast(p, DrawParagraph), rp = Std.downcast(p, RunParagraph);
		if (rp != null) rp.ready();
		out.float(80, p.width);
		out.float(81, p.height);
		out.float(82, p.minWidth);
		out.float(83, p.baseline);
		if (rp != null) {
			out.float(84, rp.size);
			out.uint(rp.lines.length);
			for (l in rp.lines) {
				line(l.top, l.baseline, l.width, l.height, l.end - l.start);
				for (i in l.start...l.end)
					glyph(rp.faces[i], rp.ids[i], rp.xs[i], rp.dys[i], rp.sizes[i], rp.obliques[i], rp.spans[i]);
			}
			return;
		}
		if (dp == null) {
			out.float(84, 0);
			out.uint(0);
			return;
		}
		var t = dp.layout;
		out.float(84, t.fonts.size);
		out.uint(t.lines.length);
		for (l in t.lines) {
			var shown = [
				for (i in l.glyphStart...l.glyphEnd) {
					var c = t.glyphChar(i);
					if (!(c == 32 || c == 10 || c == 9 || t.glyphHidden(i))) i;
				}
			];
			line(l.top, l.baseline, l.width, l.height, shown.length);
			for (i in shown) {
				var set = t.glyphFontSet(i);
				glyph(t.glyphFont(i), t.glyphId(i), t.glyphX(i) + t.glyphOffsetX(i), t.glyphOffsetY(i), set.size, set.oblique, t.glyphRun(i));
			}
		}
	}

	inline function line(top:Float, baseline:Float, width:Float, height:Float, n:Int) {
		out.float(85, top);
		out.float(86, baseline);
		out.float(87, width);
		out.float(88, height);
		out.uint(n);
	}

	inline function glyph(f:FontFile, id:Int, x:Float, dy:Float, size:Float, oblique:Bool, run:Int) {
		out.uint(index(fonts, f));
		out.uint(id);
		out.float(90, x);
		out.float(91, dy);
		out.float(92, size);
		out.bool(oblique);
		out.int(run);
	}

	// (the same pixels once: a still loop's frames one picture)
	function refIndex(r:ImageRef):Int {
		for (k in 0...images.length) {
			var i = images[k];
			if (i == r || i.hash == r.hash && i.kind == r.kind && i.width == r.width && i.height == r.height && i.color == r.color) return k;
		}
		images.push(r);
		return images.length - 1;
	}

	static function index<T>(list:Array<T>, x:T):Int {
		var k = list.indexOf(x);
		if (k >= 0) return k;
		list.push(x);
		return list.length - 1;
	}
}

// a frame written: its streams and the fonts and images they name by index
typedef Frame = {
	bytes:Bytes,
	fonts:Array<FontRef>,
	images:Array<ImageRef>,
	// (its loop: its fps, its frames as FrameLoop's deltas)
	?loop:Null<FrameLoopData>,
}

typedef FrameLoopData = {fps:Int, frames:Array<Bytes>};

// a font by reference: its file's hash, where it was read from (null: bytes
// given, data them), its face, its engine (Shaping's) and a variable one's
// instance (its normalized coordinates)
typedef FontRef = {
	hash:String,
	family:String,
	weight:Int,
	italic:Bool,
	path:Null<String>,
	index:Int,
	engine:Int,
	coords:Null<Array<Float>>,
	data:Null<Bytes>
};

// an image by its content's hash: its kind (FrameArchive's FILE, PIXELS,
// SVG), its size, an SVG's colour, the bytes (null: not readable, or stored)
typedef ImageRef = {hash:String, kind:Int, width:Int, height:Int, color:Int, data:Null<Bytes>};

// (a frame's ops)
class FrameOp {
	public static inline var TRANSLATE = 1;
	public static inline var PUSH_CLIP = 2;
	public static inline var POP_CLIP = 3;
	public static inline var PUSH_OPACITY = 4;
	public static inline var PUSH_GROUP = 5;
	public static inline var POP_OPACITY = 6;
	public static inline var PUSH_TRANSFORM = 7;
	public static inline var POP_TRANSFORM = 8;
	public static inline var RECT = 9;
	public static inline var SHADOW = 10;
	public static inline var INSET_SHADOW = 11;
	public static inline var PATH = 12;
	public static inline var IMAGE = 13;
	public static inline var TEXT = 14;
	public static inline var TEXT_SHADOW = 15;
	public static inline var PLACEHOLDER = 16;
	// (what a pass draws as data: PassData)
	public static inline var PASS_DATA = 17;
}
