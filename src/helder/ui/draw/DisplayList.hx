package helder.ui.draw;

import helder.os.Edges;
import helder.gfx.Color;
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
// them allocating nothing, the recording before kept until it is done, so
// that a node's entry is copied from it where nothing in it changed (copy)
// and compared with it where something did (diff: a window's damage).
class DisplayList implements TextureCanvas {
	// the canvas it is replayed onto (Ui.paint's: Renderer.of finds the renderer behind it)
	public var target:Null<Canvas> = null;

	// (the calls: opcodes and their ints, their floats; how many of each are this frame's)
	var ints:Array<Int> = [];
	var floats:Array<Float> = [];
	var ni = 0;
	var nf = 0;
	// (what they take: by index, each resource's version)
	var resources:Array<Null<Any>> = [];
	var versions:Array<Int> = [];
	var nr = 0;
	// (the recording before this one (begin), kept until it is done: what
	// its clean nodes recorded copied from it (copy), what changed told by
	// comparing with it (diff))
	var oldInts:Array<Int> = [];
	var oldFloats:Array<Float> = [];
	var oldResources:Array<Null<Any>> = [];
	var oldVersions:Array<Int> = [];
	var oldNi = 0;
	var oldNr = 0;
	// (where what is recorded now lands in the list's coordinates: the
	// translations and transforms recorded, 6 each saved)
	var ma = 1.0;
	var mb = 0.0;
	var mc = 0.0;
	var md = 1.0;
	var me = 0.0;
	var mf = 0.0;
	final matrices:Array<Float> = [];
	// (diff's: the children met, the old ones' entries, the boxes that differ)
	final kids:Array<Node> = [];
	final oldKids:Array<Node> = [];
	final oldAt:Array<Int> = [];
	final boxes:Array<Float> = [];

	public function new() {}

	// the calls recorded so far; of them, the layers held and what is
	// drawn anew each frame (passes, GPU textures)
	public var length(default, null) = 0;
	public var layers(default, null) = 0;
	public var live(default, null) = 0;
	// (the nodes' system layers in it: LayerSlot)
	public var slots(default, null) = 0;
	// (the images' resources: their versions told, stale)
	final images:Array<Int> = [];

	// its recording's number: another at each begin and clear (Renderer.passKey)
	public var take(default, null) = 0;

	static var takes = 0;

	// forgets the calls and their resources, its arrays kept
	public function clear() {
		take = ++takes;
		oldTake = -1;
		for (i in 0...nr)
			resources[i] = null;
		ni = nf = nr = length = layers = live = slots = 0;
		images.resize(0);
		done();
		unturn();
	}

	// begins a recording, the one before kept until done
	public function begin() {
		oldTake = take;
		take = ++takes;
		var i = oldInts, f = oldFloats, r = oldResources, v = oldVersions;
		oldInts = ints;
		oldFloats = floats;
		oldResources = resources;
		oldVersions = versions;
		oldNi = ni;
		oldNr = nr;
		ints = i;
		floats = f;
		resources = r;
		versions = v;
		ni = nf = nr = length = layers = live = slots = 0;
		images.resize(0);
		unturn();
	}

	// the recording before let go
	public function done() {
		for (i in 0...oldNr)
			oldResources[i] = null;
		oldNi = oldNr = 0;
		oldTake = -1;
	}

	// (the recording before's take: what a span of it was recorded in)
	var oldTake = -1;

	// Where it records now: a span's start or end (its ints', floats' and
	// resources' counts; take: the recording's), what a painter keeps of
	// what it recorded to copy it into the next recording (copySpan).
	public inline function markInts():Int
		return ni;

	public inline function markFloats():Int
		return nf;

	public inline function markResources():Int
		return nr;

	// A span of the recording before this one (take: the one it was recorded
	// in; its ints, floats and resources from...to) copied in, what its calls
	// take renumbered: a painter's unchanged part drawn again without
	// painting it (Chromium's subsequences). Only drawing calls and clips:
	// false, nothing copied, where it holds what a copy must keep track of
	// (a node's entry, a layer, an image, a pass, a texture, a transform or
	// a translation, the culls), or the recording before isn't take's.
	public function copySpan(take:Int, i0:Int, i1:Int, f0:Int, f1:Int, r0:Int, r1:Int):Bool {
		if (take != oldTake || i1 > oldNi || r1 > oldNr || i0 > i1) return false;
		var o = oldInts, i = i0;
		while (i < i1) {
			var op:Op = o[i];
			switch op {
				case RECT | SHADOW | INSET_SHADOW | PATH | TEXT | TEXT_SHADOW | PUSH_CLIP | POP_CLIP | PUSH_OPACITY | PUSH_GROUP | POP_OPACITY:
				case _:
					return false;
			}
			i += size(op);
		}
		var w = oldFloats, dr = nr - r0;
		for (j in f0...f1)
			float(w[j]);
		for (j in r0...r1) {
			if (nr == resources.length) {
				resources.push(oldResources[j]);
				versions.push(oldVersions[j]);
			} else {
				resources[nr] = oldResources[j];
				versions[nr] = oldVersions[j];
			}
			nr++;
		}
		i = i0;
		while (i < i1) {
			var op:Op = o[i], ki = size(op), r = refs(op);
			int(op);
			for (j in 1...ki) {
				var x = o[i + j];
				int(r >> j & 1 != 0 && x >= 0 ? x + dr : x);
			}
			if ((op : Int) <= (PASS : Int)) length++;
			i += ki;
		}
		return true;
	}

	inline function unturn() {
		ma = md = 1;
		mb = mc = me = mf = 0;
		matrices.resize(0);
	}

	// whether an image drawn changed since it was recorded (Image.version)
	public function stale():Bool {
		for (k in images) {
			var img:Image = cast resources[k];
			if (img.version != versions[k]) return true;
		}
		return false;
	}

	// a node's drawing begins (its first entry: flags FIRST, ENTERING;
	// HIDDEN: under visibility hidden), under what is seen (x0, y0, x1, y1:
	// the walk's); what is recorded until end(at) is its (at: the index it returns)
	public function node(n:Node, flags:Int, x0:Float, y0:Float, x1:Float, y1:Float):Int {
		var at = ni;
		int(NODE);
		int(res(n));
		int(flags);
		int(0);
		int(0);
		int(nf);
		int(0);
		box(0, 0, 0, 0);
		box(x0, y0, x1, y1);
		return at;
	}

	// where the next entry goes; the entry there if it is n's (-1: none)
	public inline function mark():Int
		return ni;

	public inline function entry(at:Int, n:Node):Int
		return at < ni && ints[at] == NODE && resources[ints[at + 1]] == n ? at : -1;

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
		ints[at + 6] = nr;
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
		me += ma * dx + mc * dy;
		mf += mb * dx + md * dy;
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
		var m = matrices;
		m.push(ma);
		m.push(mb);
		m.push(mc);
		m.push(md);
		m.push(me);
		m.push(mf);
		var na = ma * a + mc * b, nb = mb * a + md * b, nc = ma * c + mc * d, nd = mb * c + md * d;
		me += ma * e + mc * f;
		mf += mb * e + md * f;
		ma = na;
		mb = nb;
		mc = nc;
		md = nd;
	}

	public function popTransform() {
		op(POP_TRANSFORM);
		var m = matrices, k = m.length - 6;
		if (k < 0) return;
		ma = m[k];
		mb = m[k + 1];
		mc = m[k + 2];
		md = m[k + 3];
		me = m[k + 4];
		mf = m[k + 5];
		m.resize(k);
	}

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

	// a canvas never draws a list's layers (Renderer.layer's tiles), nor keeps a frame
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

	public function mover(m:helder.ui.Mover):Bool
		return false;

	public function leave() {}

	public function slot(s:helder.ui.LayerSlot, x:Float, y:Float, w:Float, h:Float) {
		op(SLOT);
		int(res(s));
		box(x, y, w, h);
		slots++;
	}

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
					i += 7;
					f += 8;
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
				case SLOT:
					if (g != null) g.slot(get(n[i + 1]), v[f], v[f + 1], v[f + 2], v[f + 3]);
					i += 2;
					f += 4;
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

	// the old recording's range of its entry at copied in as it is: its
	// calls, its resources, its nodes' entries placed anew (Node.entry, in
	// the recording tick), the layers it holds this one's (in layer); not
	// (false) where it was recorded under another rect seen (x0, y0, x1, y1:
	// what it culled would differ), hidden otherwise, before its first
	// paint, or is not to be copied
	public function copy(at:Int, x0:Float, y0:Float, x1:Float, y1:Float, hidden:Bool, tick:Int, layer:Layer):Bool {
		var o = oldInts, w = oldFloats, k = o[at + 2], f = o[at + 5];
		if (k & NOCOPY != 0 || (k & HIDDEN != 0) != hidden || w[f + 4] != x0 || w[f + 5] != y0 || w[f + 6] != x1 || w[f + 7] != y1) return false;
		// (a first paint's entry, the node drawn since: recorded again, culled, it records nothing)
		if (k & FIRST != 0 && @:privateAccess (cast oldResources[o[at + 1]] : Node).drawn) return false;
		var i1 = o[at + 3], f1 = o[at + 4], r0 = o[at + 1], r1 = o[at + 6];
		var di = ni - at, df = nf - f, dr = nr - r0;
		for (j in f...f1)
			float(w[j]);
		for (j in r0...r1) {
			if (nr == resources.length) {
				resources.push(oldResources[j]);
				versions.push(oldVersions[j]);
			} else {
				resources[nr] = oldResources[j];
				versions[nr] = oldVersions[j];
			}
			nr++;
		}
		var i = at;
		while (i < i1) {
			var op:Op = o[i], ki = size(op), r = refs(op), base = ni;
			int(op);
			for (j in 1...ki) {
				var x = o[i + j];
				int(r >> j & 1 != 0 && x >= 0 ? x + dr : x);
			}
			switch op {
				case NODE:
					ints[base + 3] += di;
					ints[base + 4] += df;
					ints[base + 5] += df;
					ints[base + 6] += dr;
					var n:Node = cast resources[ints[base + 1]];
					@:privateAccess {
						n.paintedAt = tick;
						n.entry = base;
					}
				case LAYER:
					@:privateAccess (cast resources[ints[base + 1]] : Layer).parent = layer;
					layers++;
				case IMAGE:
					if (ints[base + 1] >= 0) images.push(ints[base + 1]);
				case PASS | GPU_TEXTURE:
					live++;
				case SLOT:
					slots++;
				case _:
			}
			if ((op : Int) <= (PASS : Int)) length++;
			i += ki;
		}
		return true;
	}

	// what the range of the entry at (-1: the whole list) changed from the
	// old recording's of old (-1: the whole of it; none for a new entry),
	// added to d where the list records now (its translations and
	// transforms): where its own calls are the same but for their numbers
	// and resources, the boxes of those that differ (live: its paths
	// drawn anew, as they may have changed in place); else its old and new
	// bounds (none: all of d). Its children's entries are theirs to compare
	// (Ui.paintNode), but for those taken out (their old bounds) and those
	// drawn in another order (its bounds); tick: the recording's
	public function diff(at:Int, old:Int, d:Damage, tick:Int, live:Bool) {
		var n = ints, o = oldInts, v = floats, w = oldFloats;
		if (old < 0 && at >= 0) return bounds(n, v, at, d);
		var a = at < 0 ? 0 : at + 7, a1 = at < 0 ? ni : n[at + 3], fa = at < 0 ? 0 : n[at + 5] + 8;
		var b = old < 0 ? 0 : old + 7, b1 = old < 0 ? oldNi : o[old + 3], fb = old < 0 ? 0 : o[old + 5] + 8;
		kids.resize(0);
		oldKids.resize(0);
		oldAt.resize(0);
		boxes.resize(0);
		var whole = false, depth = 0, sx = 0.0, sy = 0.0, tx = 0.0, ty = 0.0;
		while (true) {
			while (a < a1 && n[a] == NODE) {
				kids.push(cast resources[n[a + 1]]);
				fa = n[a + 4];
				a = n[a + 3];
			}
			while (b < b1 && o[b] == NODE) {
				oldKids.push(cast oldResources[o[b + 1]]);
				oldAt.push(b);
				fb = o[b + 4];
				b = o[b + 3];
			}
			if (a >= a1 || b >= b1) {
				whole = a < a1 || b < b1;
				break;
			}
			var op:Op = n[a];
			if (op != o[b]) {
				whole = true;
				break;
			}
			var ki = size(op), kf = fsize(op), r = refs(op), differs = live && op == PATH;
			for (k in 1...ki) {
				var x = n[a + k], y = o[b + k];
				if (r >> k & 1 == 0) {
					if (x != y) differs = true;
				} else if ((x < 0) != (y < 0) || x >= 0 && (resources[x] != oldResources[y] || versions[x] != oldVersions[y])) differs = true;
			}
			for (k in 0...kf)
				if (v[fa + k] != w[fb + k]) differs = true;
			if (differs) {
				var grow = op == SHADOW ? 2 * Math.max(v[fa + 5], w[fb + 5]) + 2 : 2.0;
				if (depth > 0 || !(op == RECT || op == SHADOW || op == INSET_SHADOW || op == IMAGE || op == GPU_TEXTURE)) {
					whole = true;
					break;
				}
				boxes.push(v[fa] + sx - grow);
				boxes.push(v[fa + 1] + sy - grow);
				boxes.push(v[fa] + v[fa + 2] + sx + grow);
				boxes.push(v[fa + 1] + v[fa + 3] + sy + grow);
				boxes.push(w[fb] + tx - grow);
				boxes.push(w[fb + 1] + ty - grow);
				boxes.push(w[fb] + w[fb + 2] + tx + grow);
				boxes.push(w[fb + 1] + w[fb + 3] + ty + grow);
			}
			switch op {
				case TRANSLATE:
					sx += v[fa];
					sy += v[fa + 1];
					tx += w[fb];
					ty += w[fb + 1];
				case PUSH_TRANSFORM:
					depth++;
				case POP_TRANSFORM:
					depth--;
				case _:
			}
			a += ki;
			b += ki;
			fa += kf;
			fb += kf;
		}
		// (the children: those taken out, their old bounds; those kept in the order they were)
		if (!whole && !sameKids()) {
			var last = -1;
			for (i in 0...oldKids.length) @:privateAccess {
				var k = oldKids[i];
				if (k.paintedAt == tick && k.entry > at && k.entry < a1) {
					if (k.entry < last) {
						whole = true;
						break;
					}
					last = k.entry;
				} else bounds(o, w, oldAt[i], d);
			}
		}
		if (!whole) {
			var i = 0;
			while (i < boxes.length) {
				place(d, boxes[i], boxes[i + 1], boxes[i + 2], boxes[i + 3]);
				i += 4;
			}
		} else if (at < 0) d.everything() else {
			bounds(o, w, old, d);
			bounds(n, v, at, d);
		}
	}

	inline function sameKids():Bool {
		var same = kids.length == oldKids.length;
		if (same)
			for (i in 0...kids.length)
				if (kids[i] != oldKids[i]) same = false;
		return same;
	}

	// (an entry's bounds, of ints and floats, where it drew something: its
	// test's box; none, or not where it draws: all)
	function bounds(n:Array<Int>, v:Array<Float>, at:Int, d:Damage) {
		var k = n[at + 2], f = n[at + 5];
		if (k & NONE != 0 || n[at + 3] == at + 7) return;
		if (k & TEST == 0 || k & LOOSE != 0) return d.everything();
		place(d, v[f + 1], v[f + 3], v[f], v[f + 2]);
	}

	// (a box where the list records now, its corners' bounds)
	function place(d:Damage, x0:Float, y0:Float, x1:Float, y1:Float) {
		var ax = ma * x0 + mc * y0, bx = ma * x1 + mc * y0, cx = ma * x0 + mc * y1, dx = ma * x1 + mc * y1;
		var ay = mb * x0 + md * y0, by = mb * x1 + md * y0, cy = mb * x0 + md * y1, dy = mb * x1 + md * y1;
		d.add(Math.min(Math.min(ax, bx), Math.min(cx, dx)) + me, Math.min(Math.min(ay, by), Math.min(cy, dy)) + mf,
			Math.max(Math.max(ax, bx), Math.max(cx, dx)) + me, Math.max(Math.max(ay, by), Math.max(cy, dy)) + mf);
	}

	// whether it records what o does: the same calls, numbers and resources
	public function same(o:DisplayList):Bool {
		if (ni != o.ni || nf != o.nf || nr != o.nr) return false;
		for (i in 0...ni)
			if (ints[i] != o.ints[i]) return false;
		for (i in 0...nf)
			if (floats[i] != o.floats[i]) return false;
		for (i in 0...nr)
			if (resources[i] != o.resources[i] || versions[i] != o.versions[i]) return false;
		return true;
	}

	// the bounds of what it draws (x0, y0, x1, y1 into out, grown by 2 for
	// anti-aliasing), its translations followed; false: a call it cannot
	// bound (text, a path, under a transform)
	public function extent(out:Array<Float>):Bool {
		var i = 0, f = 0, n = ints, v = floats, tx = 0.0, ty = 0.0;
		var x0 = Math.POSITIVE_INFINITY, y0 = x0, x1 = Math.NEGATIVE_INFINITY, y1 = x1;
		while (i < ni) {
			var op:Op = n[i];
			switch op {
				case TRANSLATE:
					tx += v[f];
					ty += v[f + 1];
				case RECT | IMAGE | INSET_SHADOW | GPU_TEXTURE | SHADOW:
					var g = op == SHADOW ? 2 * v[f + 5] + 2 : 2.0;
					x0 = Math.min(x0, v[f] + tx - g);
					y0 = Math.min(y0, v[f + 1] + ty - g);
					x1 = Math.max(x1, v[f] + v[f + 2] + tx + g);
					y1 = Math.max(y1, v[f + 1] + v[f + 3] + ty + g);
				case PUSH_CLIP | POP_CLIP | PUSH_OPACITY | POP_OPACITY | PUSH_GROUP:
				case _:
					return false;
			}
			i += size(op);
			f += fsize(op);
		}
		out[0] = x0;
		out[1] = y0;
		out[2] = x1;
		out[3] = y1;
		return true;
	}

	// (an op's ints with its code, its floats, which of its ints are resources' indices: a bit each)
	static function size(op:Op):Int
		return switch op {
			case NODE: 7;
			case RECT: 6;
			case TEXT | TEXT_SHADOW: 5;
			case SHADOW | PATH | GPU_TEXTURE: 4;
			case INSET_SHADOW | IMAGE | LAYER: 3;
			case PUSH_CLIP | BARS | FLIGHT | PASS | SLOT: 2;
			case _: 1;
		}

	static function fsize(op:Op):Int
		return switch op {
			case NODE: 8;
			case INSET_SHADOW | IMAGE: 9;
			case RECT | SHADOW | PUSH_TRANSFORM | CULL_SET: 6;
			case PUSH_CLIP | PUSH_GROUP | GPU_TEXTURE: 5;
			case TEXT_SHADOW | CULL_CLIP | SLOT: 4;
			case TEXT: 3;
			case TRANSLATE | CULL_SHIFT | SHIFT_POINT | BARS: 2;
			case PUSH_OPACITY: 1;
			case _: 0;
		}

	static function refs(op:Op):Int
		return switch op {
			case NODE | LAYER | BARS | FLIGHT | PASS | PUSH_CLIP | SLOT: 1 << 1;
			case RECT: 1 << 3 | 1 << 4;
			case SHADOW: 1 << 2 | 1 << 3;
			case INSET_SHADOW: 1 << 2;
			case PATH: 1 << 1 | 1 << 2 | 1 << 3;
			case IMAGE: 1 << 1 | 1 << 2;
			case TEXT | TEXT_SHADOW: 1 << 1 | 1 << 4;
			case GPU_TEXTURE: 1 << 3;
			case _: 0;
		}

	// (a node's entry: a test, the first paint's, nothing drawn; recorded
	// hidden, not to be copied (what it records reads more than its nodes:
	// Ui.paintNode), its bounds not where it draws (a sticky node's))
	public static inline var TEST = 1;
	public static inline var FIRST = 2;
	public static inline var ENTERING = 4;
	public static inline var NONE = 8;
	public static inline var HIDDEN = 16;
	public static inline var NOCOPY = 32;
	public static inline var LOOSE = 64;

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
	var SLOT = 29;
}
