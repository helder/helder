package helder.ui.draw;

import helder.gfx.Texture;
import helder.image.Image;
import helder.ui.*;
import helder.ui.Paint;
import helder.ui.Stroke;

// A layer's painting recorded (Ui.paint records each layer of the tree
// into one: Layer): each Canvas call an opcode and its numbers in flat
// arrays (ints: opcodes, colours, alignments, border styles, textures,
// resources' indices; floats: the rest), what a call takes by reference
// (paragraphs, images, paths, paints, strokes, corners, edges, colour
// arrays) in a table of resources by index, each with its version (an
// image's), so that an image changed since is told (stale). Replayed
// (replay), a canvas is given the same calls in the same order as painting
// into it directly; a GPU texture's only where it draws them
// (TextureCanvas), and a texture's pass (pass, Renderer.beforePass while a
// list records) in its place, so that a list kept from an earlier frame
// still runs its passes, in order. Besides the calls, what a walk (Walk)
// needs to give a canvas no more than a direct paint would from a list
// recorded over more than is seen: each node's test against what is seen
// and where its drawing ends (node), how what is seen changes (cull*), and
// the entries its host draws live: the layers it holds (layer), a
// scroller's scrollbars (bars), the matched elements flying (flight,
// flights). Replayed without a walk, those are passed over. The arrays
// are kept between frames (clear): a list recorded again records into
// them allocating nothing.
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

	// the calls recorded so far; of them, the layers held and what is
	// drawn anew each frame (passes, GPU textures)
	public var length(default, null) = 0;
	public var layers(default, null) = 0;
	public var live(default, null) = 0;
	// (the images' resources: their versions told, stale)
	final images:Array<Int> = [];

	// forgets the calls and their resources, its arrays kept
	public function clear() {
		for (i in 0...nr)
			resources[i] = null;
		ni = nf = nr = length = layers = live = 0;
		images.resize(0);
	}

	// whether an image drawn changed since it was recorded (Image.version)
	public function stale():Bool {
		for (k in images) {
			var img:Image = cast resources[k];
			if (img.version != versions[k]) return true;
		}
		return false;
	}

	// a node's drawing begins (its first entry: flags FIRST, ENTERING);
	// what is recorded until end(at) is its (at: the index it returns)
	public function node(n:Node, flags:Int):Int {
		var at = ni;
		int(NODE);
		int(res(n));
		int(flags);
		int(0);
		int(0);
		int(nf);
		box(0, 0, 0, 0);
		return at;
	}

	// the node's test: drawn only if its ink, widened, meets what is seen (Walk.culls)
	public function test(at:Int, ax1:Float, ax0:Float, ay1:Float, ay0:Float) {
		var f = ints[at + 5];
		ints[at + 2] |= TEST;
		floats[f] = ax1;
		floats[f + 1] = ax0;
		floats[f + 2] = ay1;
		floats[f + 3] = ay0;
	}

	public inline function flag(at:Int, flags:Int)
		ints[at + 2] |= flags;

	public function end(at:Int) {
		ints[at + 3] = ni;
		ints[at + 4] = nf;
	}

	public function cullSave()
		int(CULL_SAVE);

	public function cullRestore()
		int(CULL_RESTORE);

	public function cullAll()
		int(CULL_ALL);

	// (what is seen moved back by dx, dy: a translation by them; ptx, pty moved by them)
	public function cullShift(dx:Float, dy:Float) {
		int(CULL_SHIFT);
		float(dx);
		float(dy);
	}

	// (ptx, pty alone moved)
	public function shiftPoint(dx:Float, dy:Float) {
		int(SHIFT_POINT);
		float(dx);
		float(dy);
	}

	public function cullClip(x0:Float, y0:Float, x1:Float, y1:Float) {
		int(CULL_CLIP);
		box(x0, y0, x1, y1);
	}

	// (what is seen and ptx, pty set: a flight's)
	public function cullSet(x0:Float, y0:Float, x1:Float, y1:Float, px:Float, py:Float) {
		int(CULL_SET);
		box(x0, y0, x1, y1);
		float(px);
		float(py);
	}

	// a layer held, drawn where it is when walked (hidden: under visibility hidden where it was recorded)
	public function layer(l:Layer, hidden:Bool) {
		int(LAYER);
		int(res(l));
		int(hidden ? 1 : 0);
		layers++;
	}

	public function bars(n:Node, nw:Float, nh:Float) {
		int(BARS);
		int(res(n));
		float(nw);
		float(nh);
	}

	public function flight(n:Node) {
		int(FLIGHT);
		int(res(n));
	}

	public function flights()
		int(FLIGHTS);

	// a pass recorded before the frame's (Renderer.beforePass: f an Encoder->Void,
	// opaque here, as helder.gfx's encoder is not on every target this runs on)
	public function pass(f:Any) {
		op(PASS);
		int(res(f));
		live++;
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
		if (img != null) images.push(nr);
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
		live++;
		op(GPU_TEXTURE);
		int(t.id());
		int(id);
		int(res(corners));
		box(x, y, w, h);
		float(radius);
	}

	// a canvas never draws a list's layers (Renderer.layer's tiles)
	public function layerTiles(l:Layer):Bool
		return false;

	// gives c the calls recorded, in order (a GPU texture's only if it draws
	// them: a TextureCanvas); w: the walk it is in (what is seen, its host)
	public function replay(c:Canvas, ?w:Walk) {
		var g = Std.downcast(c, TextureCanvas);
		var i = 0, f = 0, n = ints, v = floats;
		while (i < ni) {
			switch (n[i] : Op) {
				case NODE:
					if (w != null) {
						var k = n[i + 2], node:Node = get(n[i + 1]);
						if (k & FIRST != 0 && w.mark) w.host.first(node, k & ENTERING != 0);
						if (k & NONE != 0 || k & TEST != 0 && w.culls(v[f], v[f + 1], v[f + 2], v[f + 3])) {
							f = n[i + 4];
							i = n[i + 3];
							continue;
						}
						if (w.mark) @:privateAccess node.drawnAt = w.frame;
					}
					i += 6;
					f += 4;
				case CULL_SAVE:
					if (w != null) w.save();
					i += 1;
				case CULL_RESTORE:
					if (w != null) w.restore();
					i += 1;
				case CULL_ALL:
					if (w != null) w.all();
					i += 1;
				case CULL_SHIFT:
					if (w != null) w.shift(v[f], v[f + 1]);
					i += 1;
					f += 2;
				case SHIFT_POINT:
					if (w != null) {
						w.ptx += v[f];
						w.pty += v[f + 1];
					}
					i += 1;
					f += 2;
				case CULL_CLIP:
					if (w != null) w.clip(v[f], v[f + 1], v[f + 2], v[f + 3]);
					i += 1;
					f += 4;
				case CULL_SET:
					if (w != null) {
						w.set(v[f], v[f + 1], v[f + 2], v[f + 3]);
						w.ptx = v[f + 4];
						w.pty = v[f + 5];
					}
					i += 1;
					f += 6;
				case LAYER:
					if (w != null) {
						var l:Layer = get(n[i + 1]);
						l.hiddenIn = n[i + 2] == 1;
						w.host.layer(l, c, w);
					}
					i += 3;
				case BARS:
					if (w != null) w.host.bars(get(n[i + 1]), v[f], v[f + 1], c, w);
					i += 2;
					f += 2;
				case FLIGHT:
					if (w != null && w.mark) w.host.flight(get(n[i + 1]), w.ptx, w.pty);
					i += 2;
				case FLIGHTS:
					if (w != null) w.host.flights(c, w);
					i += 1;
				case PASS:
					if (g != null) g.pass(get(n[i + 1]));
					i += 2;
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

	// (a node's entry: a test, the first paint's, nothing drawn)
	public static inline var TEST = 1;
	public static inline var FIRST = 2;
	public static inline var ENTERING = 4;
	public static inline var NONE = 8;

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
	var PASS = 16;
	var NODE = 17;
	var CULL_SAVE = 18;
	var CULL_RESTORE = 19;
	var CULL_ALL = 20;
	var CULL_SHIFT = 21;
	var SHIFT_POINT = 22;
	var CULL_CLIP = 23;
	var CULL_SET = 24;
	var LAYER = 25;
	var BARS = 26;
	var FLIGHT = 27;
	var FLIGHTS = 28;
}
