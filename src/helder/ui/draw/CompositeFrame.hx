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
// to its clip where they fall at the compositor's offsets. Filled on the
// program's thread, then read by the compositor's only (two, in turn).
@:allow(helder.ui.draw)
class CompositeFrame {
	public static inline var STRIDE = 224;
	static inline var GROUP = 16;
	// the quads, an instance each, their runs' textures (Renderer's QuadBatch, not uploaded)
	final batch = new QuadBatch(STRIDE, 256, true);
	final textures:Array<Null<Texture>> = [];
	// per quad: the frame its content is in, its clip's, the thumb it is ((frame << 1) | y; -1: none)
	final content:Array<Int> = [];
	final clip:Array<Int> = [];
	final thumb:Array<Int> = [];
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

	// the quads at the compositor's offsets (now: per frame, x then y) into
	// out from 0, their runs into runTextures and runs (first quad, count):
	// the quads' count
	public function compose(now:Array<Float>, out:Bytes, runTextures:Array<Null<Texture>>, runs:Array<Int>):Int {
		runTextures.resize(0);
		runs.resize(0);
		outTextures = runTextures;
		outRuns = runs;
		runTexture = null;
		runFirst = k = 0;
		var s = scale, n = batch.count, src = batch.bytes, g = 0;
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
			run(textures[batch.runs[r * 3]]);
			if (k * STRIDE + STRIDE > out.length) break;
			out.blit(k * STRIDE, src, i * STRIDE, STRIDE);
			var f = content[i], c = clip[i], b = thumb[i];
			var dx = f >= 0 ? shift(f, now, true) * s : 0.0, dy = f >= 0 ? shift(f, now, false) * s : 0.0;
			if (b >= 0) {
				var tf = b >> 1, tx = b & 1 == 0;
				var d = (thumbAt(tf, tx, now[2 * tf + (tx ? 0 : 1)]) - thumbAt(tf, tx, offsets[2 * tf + (tx ? 0 : 1)])) * s;
				if (tx) dx += d else dy += d;
			}
			if (snap) {
				dx = Math.fround(dx);
				dy = Math.fround(dy);
			}
			if (dx != 0 || dy != 0) move(out, k * STRIDE, dx, dy);
			if (c >= 0) {
				var cx = snap ? Math.fround(shift(c, now, true) * s) : shift(c, now, true) * s;
				var cy = snap ? Math.fround(shift(c, now, false) * s) : shift(c, now, false) * s;
				if (cx != 0 || cy != 0) moveClip(out, k * STRIDE, cx, cy);
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
