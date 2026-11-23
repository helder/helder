package helder.ui.draw;

import helder.gfx.Texture;
import helder.image.Image;
import helder.ui.*;
import helder.ui.Paint;
import helder.ui.Stroke;

// A frame's painting recorded (Ui.paint records the tree into one, then
// replays it onto the window's Renderer): each Canvas call an opcode and
// its numbers in flat arrays (ints: opcodes, colours, alignments, border
// styles, textures, resources' indices; floats: the rest), what a call takes
// by reference (paragraphs, images, paths, paints, strokes, corners, edges,
// colour arrays) in a table of resources by index, each with its version
// (an image's), so that what changed from one frame's to the next can be
// told. Replayed (replay), a canvas is given the same calls in the same
// order as painting into it directly; a GPU texture's only where it draws
// them (TextureCanvas). A texture's pass is not one of its calls: it goes
// to the renderer behind it (Renderer.of) as it is recorded, all of them
// before the frame's, in the order painted, as they would painting
// directly. The arrays are kept between frames (clear): a steady frame
// records into them allocating nothing.
class DisplayList implements TextureCanvas {
	// the canvas it is replayed onto (Ui.paint's: Renderer.of finds the renderer behind it)
	public var target:Null<Canvas> = null;

	// (the calls: opcodes and their ints, their floats; how many of each are this frame's)
	final ints:Array<Int> = [];
	final floats:Array<Float> = [];
	var ni = 0;
	var nf = 0;
	// (what they take: by index, each resource's version)
	final resources:Array<Null<Any>> = [];
	final versions:Array<Int> = [];
	var nr = 0;

	public function new() {}

	// the calls recorded so far
	public var length(default, null) = 0;

	// forgets the calls and their resources, its arrays kept
	public function clear() {
		for (i in 0...nr)
			resources[i] = null;
		ni = nf = nr = length = 0;
	}

	public function translate(dx:Float, dy:Float) {
		op(TRANSLATE);
		float(dx);
		float(dy);
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		op(PUSH_CLIP);
		int(res(corners));
		box(x, y, w, h);
		float(radius);
	}

	public function popClip()
		op(POP_CLIP);

	public function pushOpacity(alpha:Float) {
		op(PUSH_OPACITY);
		float(alpha);
	}

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float) {
		op(PUSH_GROUP);
		float(alpha);
		box(x, y, w, h);
	}

	public function popOpacity()
		op(POP_OPACITY);

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		op(PUSH_TRANSFORM);
		float(a);
		float(b);
		float(c);
		float(d);
		float(e);
		float(f);
	}

	public function popTransform()
		op(POP_TRANSFORM);

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
			style:BorderStyle = Solid) {
		op(RECT);
		int(fill);
		int(border);
		int(res(corners));
		int(res(sides));
		int(cast style);
		box(x, y, w, h);
		float(radius);
		float(borderWidth);
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {
		op(SHADOW);
		int(color);
		int(res(corners));
		int(res(offset));
		box(x, y, w, h);
		float(radius);
		float(blur);
	}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners) {
		op(INSET_SHADOW);
		int(color);
		int(res(corners));
		box(x, y, w, h);
		float(radius);
		float(blur);
		float(dx);
		float(dy);
		float(spread);
	}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {
		op(PATH);
		int(res(p));
		int(res(fill));
		int(res(stroke));
	}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {
		op(IMAGE);
		int(res(img, img == null ? 0 : img.version));
		int(res(corners));
		box(x, y, w, h);
		float(u0);
		float(v0);
		float(u1);
		float(v1);
		float(radius);
	}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {
		op(TEXT);
		int(res(p));
		int(cast align);
		int(color);
		int(res(colors));
		float(x);
		float(y);
		float(width);
	}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {
		op(TEXT_SHADOW);
		int(res(p));
		int(cast align);
		int(color);
		int(res(colors));
		float(x);
		float(y);
		float(width);
		float(blur);
	}

	public function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners) {
		op(GPU_TEXTURE);
		int(t.id());
		int(id);
		int(res(corners));
		box(x, y, w, h);
		float(radius);
	}

	// gives c the calls recorded, in order (a GPU texture's only if it draws
	// them: a TextureCanvas)
	public function replay(c:Canvas) {
		var g = Std.downcast(c, TextureCanvas);
		var i = 0, f = 0, n = ints, v = floats;
		while (i < ni) {
			switch (n[i] : Op) {
				case TRANSLATE:
					c.translate(v[f], v[f + 1]);
					i += 1;
					f += 2;
				case PUSH_CLIP:
					c.pushClip(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], get(n[i + 1]));
					i += 2;
					f += 5;
				case POP_CLIP:
					c.popClip();
					i += 1;
				case PUSH_OPACITY:
					c.pushOpacity(v[f]);
					i += 1;
					f += 1;
				case PUSH_GROUP:
					c.pushGroup(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4]);
					i += 1;
					f += 5;
				case POP_OPACITY:
					c.popOpacity();
					i += 1;
				case PUSH_TRANSFORM:
					c.pushTransform(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], v[f + 5]);
					i += 1;
					f += 6;
				case POP_TRANSFORM:
					c.popTransform();
					i += 1;
				case RECT:
					c.rect(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], n[i + 1], v[f + 5], n[i + 2], get(n[i + 3]), get(n[i + 4]), cast n[i + 5]);
					i += 6;
					f += 6;
				case SHADOW:
					c.shadow(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], n[i + 1], v[f + 5], get(n[i + 2]), get(n[i + 3]));
					i += 4;
					f += 6;
				case INSET_SHADOW:
					c.insetShadow(v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], n[i + 1], v[f + 5], v[f + 6], v[f + 7], v[f + 8], get(n[i + 2]));
					i += 3;
					f += 9;
				case PATH:
					c.path(get(n[i + 1]), get(n[i + 2]), get(n[i + 3]));
					i += 4;
				case IMAGE:
					c.image(get(n[i + 1]), v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], v[f + 5], v[f + 6], v[f + 7], v[f + 8], get(n[i + 2]));
					i += 3;
					f += 9;
				case TEXT:
					c.text(get(n[i + 1]), v[f], v[f + 1], v[f + 2], cast n[i + 2], n[i + 3], get(n[i + 4]));
					i += 5;
					f += 3;
				case TEXT_SHADOW:
					c.textShadow(get(n[i + 1]), v[f], v[f + 1], v[f + 2], cast n[i + 2], n[i + 3], v[f + 3], get(n[i + 4]));
					i += 5;
					f += 4;
				case GPU_TEXTURE:
					if (g != null) g.gpuTexture(cast n[i + 1], n[i + 2], v[f], v[f + 1], v[f + 2], v[f + 3], v[f + 4], get(n[i + 3]));
					i += 4;
					f += 5;
				case _:
					throw "Bad display list";
			}
		}
	}

	inline function op(code:Op) {
		int(code);
		length++;
	}

	inline function int(x:Int) {
		if (ni == ints.length) ints.push(x) else ints[ni] = x;
		ni++;
	}

	inline function float(x:Float) {
		if (nf == floats.length) floats.push(x) else floats[nf] = x;
		nf++;
	}

	inline function box(x:Float, y:Float, w:Float, h:Float) {
		float(x);
		float(y);
		float(w);
		float(h);
	}

	// (a resource's index: -1 for none)
	function res(r:Null<Any>, version = 0):Int {
		if (r == null) return -1;
		if (nr == resources.length) {
			resources.push(r);
			versions.push(version);
		} else {
			resources[nr] = r;
			versions[nr] = version;
		}
		return nr++;
	}

	inline function get<T>(i:Int):T
		return i < 0 ? null : cast resources[i];
}

private enum abstract Op(Int) from Int to Int {
	var TRANSLATE = 0;
	var PUSH_CLIP = 1;
	var POP_CLIP = 2;
	var PUSH_OPACITY = 3;
	var PUSH_GROUP = 4;
	var POP_OPACITY = 5;
	var PUSH_TRANSFORM = 6;
	var POP_TRANSFORM = 7;
	var RECT = 8;
	var SHADOW = 9;
	var INSET_SHADOW = 10;
	var PATH = 11;
	var IMAGE = 12;
	var TEXT = 13;
	var TEXT_SHADOW = 14;
	var GPU_TEXTURE = 15;
}
