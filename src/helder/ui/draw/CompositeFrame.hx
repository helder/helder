package helder.ui.draw;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.ui.Node;

// What the compositor draws a frame from (Compositor): the program's last
// frame walked whole once more (Ui.paint's last walk, Renderer.composite),
// each quad tagged with the scroller whose content it is (moved by that
// one's scroll and those around it), the one its clip is in, and a
// scrollbar's thumb (moved along its track); a tiled scroller's tiles kept
// as tiles, all of those drawn over what its layer was recorded over, cut
// to its clip where they fall at the compositor's offsets. What moves on
// its own (helder.ui.Mover: a layer's transform and opacity under a
// transition, a spring or a tween; a sticky node) is drawn at its opacity's
// 1 and tagged too: its quads turned by its transform's change, in the
// target's pixels, and faded by its opacity, as sampled at the time drawn;
// a fading one of more than one thing is a group (a render target of the
// frame's own, Renderer.pushGroup) whose one quad is faded; a scroller
// inside one leaves it as drawn. An overlay scrollbar's thumb is
// drawn shown and faded as the program's would. Filled on the program's
// thread, then read by the compositor's only (two, in turn).
@:allow(helder.ui.draw)
class CompositeFrame {
	public static inline var STRIDE = 224;
	static inline var GROUP = 16;
	static inline var MOVER = 12;
	// the quads, an instance each, their runs' textures (Renderer's QuadBatch, not uploaded)
	final batch = new QuadBatch(STRIDE, 256, true);
	final textures:Array<Null<Texture>> = [];
	// per quad: the frame its content is in, its clip's, the thumb it is ((frame << 1) | y; -1: none)
	final content:Array<Int> = [];
	final clip:Array<Int> = [];
	final thumb:Array<Int> = [];
	// per quad: the mover it is in, its clip's (-1: none), a thumb's fade
	// (its colour's alpha as drawn shown, 256: an opacity of its own; 0: none)
	final mover:Array<Int> = [];
	final clipMover:Array<Int> = [];
	final fade:Array<Int> = [];
	// (a thumb's quads' edges before the grid: its quad, x0, y0, x1, y1, in device pixels)
	final thumbEdges:Array<Float> = [];
	// the movers: each its parent mover, its sticky scroller's frame (-1:
	// none), whether a scroller inside it keeps it as drawn, the transform
	// around it (the target's pixels from the scaled ones), the scale, the
	// canvas's translation (MOVER floats); per mover sampled (compose's):
	// the transform's change in the target's pixels and the opacity, from
	// those around it too (7 floats)
	final movers:Array<helder.ui.Mover> = [];
	final moverData:Array<Float> = [];
	final moved:Array<Float> = [];
	// (each scroller frame's overlay bars: when it last moved (Ui.barMoved's), -1e9: none); whether its bars are overlay ones
	final barAt:Array<Float> = [];
	public var overlay(default, null) = false;
	// the scrollers' frames: their nodes, the frame around each (-1: none),
	// their offsets as drawn, their thumbs (per axis: track's start and
	// length, thumb's length, range, start)
	final nodes:Array<Node> = [];
	final parents:Array<Int> = [];
	final offsets:Array<Float> = [];
	final bars:Array<Float> = [];
	// the tiles: per group, where its quads go (the quad before which),
	// its frame and its clip's, its clip (x0, y0, x1, y1, its corners'
	// radii), its tiles' raster origin and translation as drawn (rx, ry,
	// tx, ty), its opacity (GROUP floats); its tiles (i, j, texture), from tileAt
	final groups:Array<Int> = [];
	final groupData:Array<Float> = [];
	final tileAt:Array<Int> = [];
	final tiles:Array<Int> = [];
	final tileTextures:Array<Texture> = [];
	// the frame's size (device pixels), scale, background; whether it snaps
	public var width(default, null) = 0;
	public var height(default, null) = 0;
	public var scale(default, null) = 1.0;
	public var background(default, null) = 0;
	var snap = true;
	// the renderer's: pipeline, its slots, the corners and indices, the
	// atlas, a blank texture, the sampler
	var pipeline:Null<Pipeline> = null;
	var atlasSlot = 0;
	var imageSlot = 0;
	var corners:Null<Buffer> = null;
	var indices:Null<Buffer> = null;
	var atlas:Null<Texture> = null;
	var blank:Null<Texture> = null;
	var sampler:Null<Sampler> = null;
	// (whether it was filled: a frame drew it)
	public var ready(default, null) = false;
	// (the compositor's: the ring of instance buffers it is drawn from, their size)
	var buffers:Array<Buffer> = [];
	var capacity = 0;

	public function new() {}

	function clear() {
		batch.clear();
		textures.resize(0);
		textures.push(null);
		content.resize(0);
		clip.resize(0);
		thumb.resize(0);
		mover.resize(0);
		clipMover.resize(0);
		fade.resize(0);
		thumbEdges.resize(0);
		movers.resize(0);
		moverData.resize(0);
		barAt.resize(0);
		overlay = false;
		nodes.resize(0);
		parents.resize(0);
		offsets.resize(0);
		bars.resize(0);
		groups.resize(0);
		groupData.resize(0);
		tileAt.resize(0);
		tiles.resize(0);
		tileTextures.resize(0);
		ready = false;
	}

	// (scroller n's frame, made the first time: its offsets now, its thumbs)
	function frameOf(n:Node, parent:Int):Int {
		var i = nodes.indexOf(n);
		if (i >= 0) return i;
		nodes.push(n);
		parents.push(parent);
		offsets.push(n.scrollX);
		offsets.push(n.scrollY);
		var u = n.ui, m = u == null || !u.overlayBars ? null : @:privateAccess u.barMoved.get(n);
		if (u != null && u.overlayBars) overlay = true;
		barAt.push(m == null ? -1e9 : m[2]);
		for (x in [true, false]) {
			var t = @:privateAccess Scrolling.thumb(n, x);
			if (t == null) {
				for (_ in 0...5)
					bars.push(0);
				continue;
			}
			var tr = @:privateAccess Scrolling.track(n, x);
			bars.push(tr[0]);
			bars.push(tr[1]);
			bars.push(x ? t[2] : t[3]);
			bars.push(@:privateAccess Scrolling.maxScroll(n, x));
			bars.push(@:privateAccess Scrolling.scrollStart(n, x));
		}
		return nodes.length - 1;
	}

	// (mover m drawn inside mover parent, its sticky scroller's frame f, under the renderer's state then)
	function addMover(m:helder.ui.Mover, parent:Int, f:Int, flat:Bool, a:Float, b:Float, c:Float, d:Float, e:Float, ff:Float, s:Float,
			tx:Float, ty:Float):Int {
		movers.push(m);
		for (v in [parent, f, 0, flat ? 1 : a, flat ? 0 : b, flat ? 0 : c, flat ? 1 : d, flat ? 0 : e, flat ? 0 : ff, s, tx, ty])
			moverData.push(v);
		return movers.length - 1;
	}

	inline function moverParent(m:Int):Int
		return Std.int(moverData[m * MOVER]);

	inline function freeze(m:Int)
		moverData[m * MOVER + 2] = 1;

	// whether something in it moves on its own until after t (a mover, an overlay bar fading)
	public function moves(t:Float):Bool {
		for (i in 0...movers.length)
			if (moverData[i * MOVER + 2] == 0 && movers[i].until > t) return true;
		return false;
	}

	// whether a mover moves with a scroll
	public function sticks():Bool {
		for (i in 0...movers.length)
			if (moverData[i * MOVER + 2] == 0 && moverData[i * MOVER + 1] >= 0) return true;
		return false;
	}

	// (each mover sampled at t, the scrollers at now: into moved)
	function sample(now:Array<Float>, t:Float) {
		moved.resize(movers.length * 7);
		var m1 = one, k = moverData;
		for (j in 0...movers.length) {
			var o = j * MOVER, q = j * 7, mv = movers[j];
			var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0, al = 1.0;
			if (k[o + 2] != 0) al = mv.opacity else {
				var fr = Std.int(k[o + 1]);
				al = mv.sample(t, fr >= 0 ? now[2 * fr] : 0, fr >= 0 ? now[2 * fr + 1] : 0, m1);
				var m0 = mv.drawn;
				// (K = m1 m0⁻¹, in the UI's points; D = R A K A⁻¹ R⁻¹ in the target's
				// pixels, A the scale after the canvas's translation, R the transform around it)
				set(ta, m1.a, m1.b, m1.c, m1.d, m1.e, m1.f);
				if (m0 != null) {
					set(tb, m0.a, m0.b, m0.c, m0.d, m0.e, m0.f);
					invert(tb);
					mul(ta, ta, tb);
				}
				var s = k[o + 9];
				set(tb, s, 0, 0, s, s * k[o + 10], s * k[o + 11]);
				mul(tc, tb, ta);
				invert(tb);
				mul(tc, tc, tb);
				set(tb, k[o + 3], k[o + 4], k[o + 5], k[o + 6], k[o + 7], k[o + 8]);
				mul(tc, tb, tc);
				invert(tb);
				mul(tc, tc, tb);
				a = tc[0];
				b = tc[1];
				c = tc[2];
				d = tc[3];
				e = tc[4];
				f = tc[5];
			}
			var p = Std.int(k[o]);
			if (p >= 0) {
				// (the parent's after its own)
				var r = p * 7, pa = moved[r], pb = moved[r + 1], pc = moved[r + 2], pd = moved[r + 3];
				var na = pa * a + pc * b, nb = pb * a + pd * b, nc = pa * c + pc * d, nd = pb * c + pd * d;
				var ne = pa * e + pc * f + moved[r + 4], nf = pb * e + pd * f + moved[r + 5];
				a = na;
				b = nb;
				c = nc;
				d = nd;
				e = ne;
				f = nf;
				al *= moved[r + 6];
			}
			moved[q] = a;
			moved[q + 1] = b;
			moved[q + 2] = c;
			moved[q + 3] = d;
			moved[q + 4] = e;
			moved[q + 5] = f;
			moved[q + 6] = al;
		}
	}

	final one = new helder.canvas.Matrix();
	final ta:Array<Float> = [1, 0, 0, 1, 0, 0];
	final tb:Array<Float> = [1, 0, 0, 1, 0, 0];
	final tc:Array<Float> = [1, 0, 0, 1, 0, 0];

	static inline function set(r:Array<Float>, a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		r[0] = a;
		r[1] = b;
		r[2] = c;
		r[3] = d;
		r[4] = e;
		r[5] = f;
	}

	// (r = x after y)
	static function mul(r:Array<Float>, x:Array<Float>, y:Array<Float>) {
		var a = x[0] * y[0] + x[2] * y[1], b = x[1] * y[0] + x[3] * y[1], c = x[0] * y[2] + x[2] * y[3], d = x[1] * y[2] + x[3] * y[3];
		var e = x[0] * y[4] + x[2] * y[5] + x[4], f = x[1] * y[4] + x[3] * y[5] + x[5];
		set(r, a, b, c, d, e, f);
	}

	static function invert(r:Array<Float>) {
		var det = r[0] * r[3] - r[1] * r[2];
		if (det == 0) return;
		var a = r[3] / det, b = -r[1] / det, c = -r[2] / det, d = r[0] / det;
		var e = -(a * r[4] + c * r[5]), f = -(b * r[4] + d * r[5]);
		set(r, a, b, c, d, e, f);
	}

	// (the offset of scroller frame f at the compositor's, in points: its
	// own and those around it, less as drawn; content moves the other way)
	inline function shift(f:Int, now:Array<Float>, x:Bool):Float {
		var d = 0.0;
		while (f >= 0) {
			d += offsets[2 * f + (x ? 0 : 1)] - now[2 * f + (x ? 0 : 1)];
			f = parents[f];
		}
		return d;
	}

	// (where frame f's thumb along x starts at its offset v, as Scrolling.thumb does, unstretched)
	inline function thumbAt(f:Int, x:Bool, v:Float):Float {
		var o = f * 10 + (x ? 0 : 5), max = bars[o + 3];
		var k = max > 0 ? (v - bars[o + 4]) / max : 0;
		return bars[o] + (bars[o + 1] - bars[o + 2]) * Math.max(0, Math.min(1, k));
	}

	// how many quads compose may write at most
	public function quads():Int
		return batch.count + Std.int(tiles.length / 2);

	// the quads at the compositor's offsets (now: per frame, x then y) and
	// time t into out from 0, their runs into runTextures and runs (first
	// quad, count); shown: per frame, how far its overlay bars show (null:
	// as drawn). The quads' count
	public function compose(now:Array<Float>, t:Float, shown:Null<Array<Float>>, out:Bytes, runTextures:Array<Null<Texture>>, runs:Array<Int>):Int {
		runTextures.resize(0);
		runs.resize(0);
		outTextures = runTextures;
		outRuns = runs;
		runTexture = null;
		runFirst = k = 0;
		if (movers.length > 0) sample(now, t);
		var te = 0;
		var s = scale, n = batch.count, src = batch.bytes, g = 0, mv = moved;
		// (each quad's run texture, by the template's runs)
		var r = 0, rEnd = batch.draws() > 0 ? batch.runs[1] + batch.runs[2] : 0;
		for (i in 0...n + 1) {
			// (the tiles before quad i)
			while (g < groups.length && groups[g] == i) {
				tileGroup(g, now, out);
				g++;
			}
			if (i == n) break;
			while (r < batch.draws() - 1 && i >= batch.runs[r * 3 + 1] + batch.runs[r * 3 + 2])
				r++;
			var f = content[i], c = clip[i], b = thumb[i], m = mover[i], o = k * STRIDE;
			// (faded out: not drawn)
			var alpha = m >= 0 ? mv[m * 7 + 6] : 1.0, fd = fade[i];
			if (fd > 0 && b >= 0 && shown != null) {
				var v = shown[b >> 1];
				alpha *= fd == 256 ? v : (v < 1 ? Math.fround(fd * v) : fd) / fd;
			}
			if (alpha <= 0) continue;
			run(textures[batch.runs[r * 3]]);
			if (o + STRIDE > out.length) break;
			out.blit(o, src, i * STRIDE, STRIDE);
			if (alpha != 1) {
				for (j in 0...4)
					out.setFloat(o + 80 + j * 4, out.getFloat(o + 80 + j * 4) * alpha);
				// (a glyph's are its blend's ratios, not a colour)
				if (out.getFloat(o + 144) != 1) for (j in 0...4)
					out.setFloat(o + 96 + j * 4, out.getFloat(o + 96 + j * 4) * alpha);
			}
			// (on the pixel grid as drawn, and moved only by scrolls: kept on it)
			var grid = snap && src.getFloat(i * STRIDE + 192) != -1e9;
			if (m >= 0) {
				var q = m * 7;
				if (mv[q] != 1 || mv[q + 1] != 0 || mv[q + 2] != 0 || mv[q + 3] != 1) {
					turn(out, o, mv, q);
					grid = false;
				} else if (mv[q + 4] != 0 || mv[q + 5] != 0) {
					move(out, o, mv[q + 4], mv[q + 5]);
					grid = false;
				}
			}
			var cm = clipMover[i];
			if (cm >= 0) turnClip(out, o, mv, cm * 7);
			var dx = f >= 0 ? shift(f, now, true) * s : 0.0, dy = f >= 0 ? shift(f, now, false) * s : 0.0;
			if (b >= 0) {
				var tf = b >> 1, tx = b & 1 == 0;
				var d = (thumbAt(tf, tx, now[2 * tf + (tx ? 0 : 1)]) - thumbAt(tf, tx, offsets[2 * tf + (tx ? 0 : 1)])) * s;
				if (tx) dx += d else dy += d;
			}
			if (grid) {
				// (a thumb's edges each on the grid where they fall, as the program's: its length may change by a pixel)
				while (te < thumbEdges.length && thumbEdges[te] < i)
					te += 5;
				if (b >= 0 && te < thumbEdges.length && thumbEdges[te] == i) {
					var tx = b & 1 == 0, d = tx ? dx : dy, e = thumbEdges;
					along(out, o, tx, Math.fround(e[te + (tx ? 1 : 2)] + d), Math.fround(e[te + (tx ? 3 : 4)] + d));
					if (tx) dx = 0 else dy = 0;
				}
				dx = Math.fround(dx);
				dy = Math.fround(dy);
			}
			if (dx != 0 || dy != 0) move(out, o, dx, dy);
			if (c >= 0) {
				var cx = snap ? Math.fround(shift(c, now, true) * s) : shift(c, now, true) * s;
				var cy = snap ? Math.fround(shift(c, now, false) * s) : shift(c, now, false) * s;
				if (cx != 0 || cy != 0) moveClip(out, o, cx, cy);
			}
			k++;
		}
		if (k > runFirst) {
			runTextures.push(runTexture);
			runs.push(runFirst);
			runs.push(k - runFirst);
		}
		return k;
	}

	// (an unturned quad's edges along x (else y) at e0, e1: its corners, half size and centre there)
	function along(b:Bytes, o:Int, x:Bool, e0:Float, e1:Float) {
		var m = 1.0, w = width, h = height, k = x ? 0 : 4;
		var a = e0 - m, z = e1 + m;
		for (c in 0...3) {
			var p = o + c * 16, v = c == (x ? 1 : 2) ? z : a;
			if (x) {
				b.setFloat(p, v / w * 2 - 1);
				b.setFloat(p + 8, v);
			} else {
				b.setFloat(p + 4, 1 - v / h * 2);
				b.setFloat(p + 12, v);
			}
		}
		var half = (e1 - e0) / 2, centre = (e0 + e1) / 2, i = Math.ffloor(centre);
		b.setFloat(o + 64 + k, half);
		b.setFloat(o + 72 + k, half + m);
		b.setFloat(o + 192 + k, i);
		b.setFloat(o + 200 + k, centre - i);
	}

	// (a quad's corners by the change d at q, in the target's pixels: no
	// longer on the grid; a glyph read filtered, as under a turning transform)
	function turn(b:Bytes, o:Int, d:Array<Float>, q:Int) {
		var w = width, h = height, a = d[q], bb = d[q + 1], c = d[q + 2], dd = d[q + 3], e = d[q + 4], f = d[q + 5];
		for (k in 0...3) {
			var p = o + k * 16, x = b.getFloat(p + 8), y = b.getFloat(p + 12);
			var X = a * x + c * y + e, Y = bb * x + dd * y + f;
			b.setFloat(p, X / w * 2 - 1);
			b.setFloat(p + 4, 1 - Y / h * 2);
			b.setFloat(p + 8, X);
			b.setFloat(p + 12, Y);
		}
		b.setFloat(o + 192, -1e9);
		b.setFloat(o + 196, 0);
		b.setFloat(o + 200, 0);
		b.setFloat(o + 204, 0);
		if (b.getFloat(o + 144) == 1) b.setFloat(o + 152, 1);
	}

	// (a clip pushed inside a mover: its corners' bounds after the change at q, as pushClip bounds a turned one)
	function turnClip(b:Bytes, o:Int, d:Array<Float>, q:Int) {
		var a = d[q], bb = d[q + 1], c = d[q + 2], dd = d[q + 3], e = d[q + 4], f = d[q + 5];
		if (a == 1 && bb == 0 && c == 0 && dd == 1 && e == 0 && f == 0) return;
		var x0 = b.getFloat(o + 160), y0 = b.getFloat(o + 164), x1 = b.getFloat(o + 168), y1 = b.getFloat(o + 172);
		if (x0 < -1e8 || x1 > 1e8 || y0 < -1e8 || y1 > 1e8) return;
		var ax = a * x0 + c * y0, bx = a * x1 + c * y0, cx = a * x0 + c * y1, dx = a * x1 + c * y1;
		var ay = bb * x0 + dd * y0, by = bb * x1 + dd * y0, cy = bb * x0 + dd * y1, dy = bb * x1 + dd * y1;
		b.setFloat(o + 160, Math.min(Math.min(ax, bx), Math.min(cx, dx)) + e);
		b.setFloat(o + 164, Math.min(Math.min(ay, by), Math.min(cy, dy)) + f);
		b.setFloat(o + 168, Math.max(Math.max(ax, bx), Math.max(cx, dx)) + e);
		b.setFloat(o + 172, Math.max(Math.max(ay, by), Math.max(cy, dy)) + f);
	}

	// (compose's: the quads written, the run open, where the runs go)
	var k = 0;
	var runTexture:Null<Texture> = null;
	var runFirst = 0;
	var outTextures:Array<Null<Texture>> = [];
	var outRuns:Array<Int> = [];

	// (the next quad's texture: a run of its own where it changes)
	function run(t:Null<Texture>) {
		if (k > runFirst && t != runTexture) {
			outTextures.push(runTexture);
			outRuns.push(runFirst);
			outRuns.push(k - runFirst);
			runFirst = k;
		}
		runTexture = t;
	}

	// (a quad's corners, centre moved by dx, dy device pixels)
	function move(b:Bytes, o:Int, dx:Float, dy:Float) {
		var w = width, h = height;
		for (c in 0...3) {
			var p = o + c * 16;
			b.setFloat(p, b.getFloat(p) + dx / w * 2);
			b.setFloat(p + 4, b.getFloat(p + 4) - dy / h * 2);
			b.setFloat(p + 8, b.getFloat(p + 8) + dx);
			b.setFloat(p + 12, b.getFloat(p + 12) + dy);
		}
		var ix = b.getFloat(o + 192);
		if (ix == -1e9) return;
		var cx = ix + b.getFloat(o + 200) + dx, cy = b.getFloat(o + 196) + b.getFloat(o + 204) + dy;
		var fx = Math.ffloor(cx), fy = Math.ffloor(cy);
		b.setFloat(o + 192, fx);
		b.setFloat(o + 196, fy);
		b.setFloat(o + 200, cx - fx);
		b.setFloat(o + 204, cy - fy);
	}

	function moveClip(b:Bytes, o:Int, dx:Float, dy:Float) {
		b.setFloat(o + 160, b.getFloat(o + 160) + dx);
		b.setFloat(o + 164, b.getFloat(o + 164) + dy);
		b.setFloat(o + 168, b.getFloat(o + 168) + dx);
		b.setFloat(o + 172, b.getFloat(o + 172) + dy);
	}

	// (group g's tiles where they fall now, cut to its clip and the frame, as Renderer.drawTiles cuts them)
	function tileGroup(g:Int, now:Array<Float>, out:Bytes) {
		var d = groupData, o = g * GROUP, f = Std.int(d[o]), c = Std.int(d[o + 1]), s = scale, T = Renderer.TILE;
		var cdx = c >= 0 ? shift(c, now, true) * s : 0.0, cdy = c >= 0 ? shift(c, now, false) * s : 0.0;
		if (snap) {
			cdx = Math.fround(cdx);
			cdy = Math.fround(cdy);
		}
		var cx0 = Math.max(d[o + 2] + cdx, 0), cy0 = Math.max(d[o + 3] + cdy, 0);
		var cx1 = Math.min(d[o + 4] + cdx, width), cy1 = Math.min(d[o + 5] + cdy, height);
		var rx = d[o + 10], ry = d[o + 11], tx = d[o + 12] + shift(f, now, true), ty = d[o + 13] + shift(f, now, false), alpha = d[o + 14];
		var fx = (tx - rx) * s, fy = (ty - ry) * s;
		if (snap) {
			fx = Math.fround(fx);
			fy = Math.fround(fy);
		}
		var first = tileAt[g], last = g + 1 < tileAt.length ? tileAt[g + 1] : Std.int(tiles.length / 2);
		for (t in first...last) {
			var x0 = tiles[2 * t] * T + fx, y0 = tiles[2 * t + 1] * T + fy;
			var qx0 = Math.max(x0, cx0), qy0 = Math.max(y0, cy0), qx1 = Math.min(x0 + T, cx1), qy1 = Math.min(y0 + T, cy1);
			if (qx1 <= qx0 || qy1 <= qy0 || k * STRIDE + STRIDE > out.length) continue;
			run(tileTextures[t]);
			tile(out, k * STRIDE, qx0, qy0, qx1, qy1, (qx0 - x0) / T, (qy0 - y0) / T, (qx1 - x0) / T, (qy1 - y0) / T, alpha, cx0, cy0, cx1, cy1, d, o + 6);
			k++;
		}
	}

	// (a tile's quad as Renderer.quad writes it for drawTiles: flat, a GPU
	// texture, a pixel's margin, white at alpha, under the clip)
	function tile(b:Bytes, o:Int, x0:Float, y0:Float, x1:Float, y1:Float, u0:Float, v0:Float, u1:Float, v1:Float, alpha:Float, c0:Float, c1:Float,
			c2:Float, c3:Float, radii:Array<Float>, at:Int) {
		var m = 1.0, w = width, h = height;
		var ax = x0 - m, ay = y0 - m, bx = x1 + m, by = y1 + m;
		var hx = (x1 - x0) / 2, hy = (y1 - y0) / 2;
		var mu = (u1 - u0) * m / (x1 - x0), mv = (v1 - v0) * m / (y1 - y0);
		inline function corner(at:Int, X:Float, Y:Float) {
			b.setFloat(at, X / w * 2 - 1);
			b.setFloat(at + 4, 1 - Y / h * 2);
			b.setFloat(at + 8, X);
			b.setFloat(at + 12, Y);
		}
		corner(o, ax, ay);
		corner(o + 16, bx, ay);
		corner(o + 32, ax, by);
		b.setFloat(o + 48, u0 - mu);
		b.setFloat(o + 52, v0 - mv);
		b.setFloat(o + 56, u1 + mu);
		b.setFloat(o + 60, v1 + mv);
		b.setFloat(o + 64, hx);
		b.setFloat(o + 68, hy);
		b.setFloat(o + 72, hx + m);
		b.setFloat(o + 76, hy + m);
		for (i in 0...3)
			b.setFloat(o + 80 + i * 4, alpha);
		b.setFloat(o + 92, alpha);
		for (i in 0...4)
			b.setFloat(o + 96 + i * 4, 0);
		b.setFloat(o + 112, 0);
		b.setFloat(o + 116, 0);
		b.setFloat(o + 120, 0);
		b.setFloat(o + 124, 0);
		b.setFloat(o + 128, -1e9);
		b.setFloat(o + 132, -1e9);
		b.setFloat(o + 136, 1e9);
		b.setFloat(o + 140, 1e9);
		b.setFloat(o + 144, 2);
		b.setFloat(o + 148, 0);
		b.setFloat(o + 152, 0);
		b.setFloat(o + 156, 0);
		b.setFloat(o + 160, c0);
		b.setFloat(o + 164, c1);
		b.setFloat(o + 168, c2);
		b.setFloat(o + 172, c3);
		for (i in 0...4)
			b.setFloat(o + 176 + i * 4, radii[at + i]);
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
}
