package helder.ui.layers.web;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.ui.Node;
import hxmc.unsafe.*;

// The browser as the system's compositor (Layers' step 6): a window's
// frames split as helder.ui.layers.LayerSplit splits them, each layer but the window's a
// canvas of the page (src/helder/ui/imports.mjs's layers_apply), the
// window's the canvas itself. A top-level scroller's content is placed in
// its scroll view (web.Scroll's element), so that the browser moves it as
// it scrolls, at the screen's rate, while the program draws nothing or is
// busy; what is over it, and a layer that moves on its own (Mover) in
// the layer of scroll views over the canvas, stacked in paint order, its
// transform and opacity a Web Animation sampled from the program's
// (animate); a node's system layer (LayerSlot: a video's canvas of the
// page, helder.media's WebSample) at its box among them, cut by its clip.
// A frame the page reads back (host.gfx.readPixels) is drawn
// whole onto the canvas (priming), the page's layers left; a scroller
// with a sticky node in it stays drawn (fits). Each is drawn
// by the window's own device into the window's canvas, in tiles of the
// canvas's size at most (a long scroller's content: several), only those
// its changes meet, each read back as an ImageBitmap (createImageBitmap:
// the canvas as it is then; WebGPU and WebGL2 alike, one context), then
// the window's own layer last, which the canvas shows; the bitmaps go to
// the page with the layers' places, in one task, once all are read (a
// frame of the canvas's own may show a frame before them). The canvas
// has premultiplied alpha for it (transparent), its own layer opaque.
// Rounded scrollers stay drawn (rounds: a scroll view's corners are not
// UiShader's). Off with HELDER_SYSTEM_LAYERS=0; =flat puts it all on the
// window's layer (the tests' reference).
@:hxmc.unsafe(gc)
@:access(helder.ui.layers.CompositeFrame)
class Layers extends helder.ui.layers.LayerSplit {
	public static function wanted():Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0";

	// (before its device is made: the canvas's context of premultiplied alpha)
	public static function transparent(canvas:Int)
		WebLayerImports.layers_alpha(canvas);

	final device:Device;
	final canvas:Int;
	final commands = new Commands();
	var ring = 0;
	var ids = 0;
	var tile = Bytes.alloc(0);
	// (the scroll view of a scroller's node, web.Scroll's: null, none yet)
	public var viewOf:Node->Null<ScrollView> = _ -> null;
	// (whether the page shows layers of ours: hidden once a frame is single)
	var showing = false;
	@:noCompletion public final dropped:Array<Int> = [];

	public function new(device:Device) {
		super(new WebPlane(helder.ui.layers.LayerPlane.BASE, null, 0));
		this.device = device;
		canvas = device.surface.handle.toI64().toInt();
		rounds = false;
	}

	// (a scroller with a sticky node in it stays drawn: the browser would scroll the node away with its content)
	override function fits(f:helder.ui.layers.CompositeFrame, c:Int):Bool {
		for (m in 0...f.movers.length) {
			var fr = Std.int(f.moverData[m * helder.ui.layers.CompositeFrame.MOVER + 1]);
			while (fr >= 0 && f.parents[fr] >= 0)
				fr = f.parents[fr];
			if (fr == c) return false;
		}
		return true;
	}

	override function plane(kind:Int, key:Dynamic):helder.ui.layers.LayerPlane {
		var p = new WebPlane(kind, key, ++ids);
		p.owner = this;
		return p;
	}

	override public function show(r:Replay, f:helder.ui.layers.CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null) return;
		compose(f, now, t, shown, drawn);
		var W = f.width, H = f.height, s = f.scale, b = f.buffers[ring = (ring + 1) % f.buffers.length], snaps = 0;
		var buf = new StringBuf();
		buf.add('{"s":');
		buf.add(num(s));
		buf.add(',"l":[');
		var first = true, z = 0, waiting = false;
		for (q in order) {
			if (q == null || q.kind == helder.ui.layers.LayerPlane.BASE) continue;
			var p:WebPlane = cast q;
			z++;
			if (p.kind == helder.ui.layers.LayerPlane.SLOT) {
				if (!first) buf.add(',');
				first = false;
				slotOf(f, p, null, null, z, buf);
				continue;
			}
			p.fit();
			if (p.quads.length == 0) continue;
			var redraw = p.local(out, quadTextures, fresh);
			var tw = Std.int(Math.min(W, p.pw)), th = Std.int(Math.min(H, p.ph));
			if (tw <= 0 || th <= 0) continue;
			var cols = Std.int(Math.ceil(p.pw / tw)), rows = Std.int(Math.ceil(p.ph / th));
			var resized = tw != p.tw || th != p.th || cols * rows != p.drawn.length;
			if (resized) {
				p.tw = tw;
				p.th = th;
				p.drawn.resize(0);
				for (_ in 0...cols * rows)
					p.drawn.push(false);
			}
			if (!first) buf.add(',');
			first = false;
			// (a scroller's content in its scroll view: its place in the content, points)
			var v = p.kind == helder.ui.layers.LayerPlane.SCROLL ? viewOf(p.key) : null;
			// (its view made after this frame, web.Scroll's: placed in it at the next, which is asked for)
			if (p.kind == helder.ui.layers.LayerPlane.SCROLL && v == null) waiting = true;
			var x = p.ox / s, y = p.oy / s;
			if (v != null) {
				x += p.drawnX - v.x;
				y += p.drawnY - v.y;
			}
			buf.add('{"i":${p.id},"z":$z,"v":${v == null ? 0 : v.id},"x":${num(x)},"y":${num(y)},"w":${num(p.pw / s)},"h":${num(p.ph / s)},"tw":$tw,"th":$th,"c":$cols,"n":${cols * rows},');
			if (p.kind == helder.ui.layers.LayerPlane.MOVER) animate(f, p.index, t, buf);
			buf.add('"t":[');
			var any = false;
			for (k in 0...cols * rows) {
				var tx = (k % cols) * tw, ty = Std.int(k / cols) * th;
				var w = Std.int(Math.min(tw, p.pw - tx)), h = Std.int(Math.min(th, p.ph - ty));
				if (p.drawn[k] && !(redraw && meets(p.damage, tx, ty, tx + w, ty + h))) continue;
				// (each at the buffer's start: written in order with the draws before, which read what was there)
				var len = tileOf(p, tx, ty, W, H);
				if (len > f.capacity || !draw(r, f, b, 0, len, p, false)) {
					p.invalidate();
					continue;
				}
				drawnTotal++;
				quadsTotal += p.quads.length;
				p.drawn[k] = true;
				if (any) buf.add(',');
				any = true;
				buf.add('[$k,$w,$h,${WebLayerImports.layers_snap(canvas, w, h)}]');
				snaps++;
			}
			buf.add(']}');
			// (its system layers, over its content in its scroll view)
			for (sp in p.slots) {
				buf.add(',');
				slotOf(f, cast sp, p, v, z, buf);
			}
		}
		buf.add('],"r":[');
		for (g in gone)
			g();
		gone.resize(0);
		buf.add(dropped.join(','));
		buf.add(']}');
		var changed = snaps > 0 || dropped.length > 0;
		dropped.resize(0);
		// (the window's own layer last: what the canvas shows, drawn each
		// frame: the program's frame took the canvas's texture, WebGPU's, which
		// would show nothing else)
		var p:WebPlane = cast base;
		p.place(0, 0, W, H);
		p.local(out, quadTextures, fresh);
		var len = p.len;
		if (len <= f.capacity) {
			if (tile.length < len) tile = Bytes.alloc(len * 2);
			tile.blit(0, p.bytes, 0, len);
			draw(r, f, b, 0, len, p, true);
			drawnTotal++;
			quadsTotal += p.quads.length;
		}
		var json = buf.toString();
		if (changed || json != sent) {
			sent = json;
			showing = true;
			Arena.scoped(a -> WebLayerImports.layers_update(canvas, a.cstring(json)));
		}
		redraw = waiting;
		frames++;
	}

	var sent = "";

	// (a node's system layer: its box and its clip as drawn, points: the
	// window's, or in the content of in (a scroller's layer, its view v))
	function slotOf(f:helder.ui.layers.CompositeFrame, p:WebPlane, in_:Null<WebPlane>, v:Null<ScrollView>, z:Int, buf:StringBuf) {
		var d = f.slotData, o = p.index * helder.ui.layers.CompositeFrame.SLOT, s = f.scale;
		var dx = 0.0, dy = 0.0;
		if (in_ != null && v != null) {
			dx = in_.drawnX - v.x;
			dy = in_.drawnY - v.y;
		}
		var x = d[o + 6] / s + dx, y = d[o + 7] / s + dy, w = (d[o + 8] - d[o + 6]) / s, h = (d[o + 11] - d[o + 7]) / s;
		buf.add('{"i":${p.id},"z":$z,"s":${p.slot.handle.toI64().toInt()},"v":${v == null ? 0 : v.id},"on":${p.slot.shown ? 1 : 0},');
		buf.add('"x":${num(x)},"y":${num(y)},"w":${num(w)},"h":${num(h)},');
		buf.add('"c":[${num(p.cx0 / s + dx)},${num(p.cy0 / s + dy)},${num(p.cx1 / s + dx)},${num(p.cy1 / s + dy)}]}');
	}

	// (a layer that moves on its own: its transform (the frame's pixels) and
	// opacity from now as the program samples them, a frame's worth apart
	// until it rests, 2 s at most (the program's next frames send what
	// follows): the page's Web Animation, run by the browser while the
	// program is busy)
	function animate(f:helder.ui.layers.CompositeFrame, m:Int, t:Float, buf:StringBuf) {
		var until = f.movers[m].until, n = Std.int(Math.max(1, Math.min(120, Math.ceil((until - t) * 60) + 1)));
		buf.add('"m":[');
		for (i in 0...n) {
			f.sample(f.offsets, t + i / 60);
			for (q in 0...7) {
				if (i > 0 || q > 0) buf.add(',');
				buf.add(num(f.moved[m * 7 + q]));
			}
		}
		buf.add('],');
	}

	// (a frame read back, the page's readPixels': drawn whole onto the
	// canvas, as the reference draws it, the page's layers left as they are)
	override public function prepare()
		priming = WebLayerImports.layers_reading() != 0;

	// (a frame onto the window's layer alone: the page's layers hidden)
	override public function windowShown()
		if (!priming) hide();

	override public function suspend()
		if (!priming) hide();

	override public function dispose()
		hide();

	function hide() {
		if (!showing) return;
		showing = false;
		sent = "";
		for (q in order)
			if (q != null && q.kind != helder.ui.layers.LayerPlane.BASE) {
				(cast q : WebPlane).drawn.resize(0);
				q.invalidate();
			}
		base.invalidate();
		Arena.scoped(a -> WebLayerImports.layers_update(canvas, a.cstring('{"s":1,"l":[],"r":[]}')));
	}

	// (tile tx, ty of p's quads into tile, in a canvas of w x h: the canvas's top left; its bytes)
	function tileOf(p:WebPlane, tx:Int, ty:Int, w:Int, h:Int):Int {
		var S = helder.ui.layers.CompositeFrame.STRIDE, n = p.len;
		if (tile.length < n) tile = Bytes.alloc(n * 2);
		tile.blit(0, p.bytes, 0, n);
		var b = tile;
		for (j in 0...p.quads.length) {
			var o = j * S;
			for (c in 0...3) {
				var q = o + c * 16, X = b.getFloat(q + 8) - tx, Y = b.getFloat(q + 12) - ty;
				b.setFloat(q, X / w * 2 - 1);
				b.setFloat(q + 4, 1 - Y / h * 2);
				b.setFloat(q + 8, X);
				b.setFloat(q + 12, Y);
			}
			for (a in [160, 168, 208, 216]) {
				b.setFloat(o + a, b.getFloat(o + a) - tx);
				b.setFloat(o + a + 4, b.getFloat(o + a + 4) - ty);
			}
			if (b.getFloat(o + 192) != -1e9) {
				b.setFloat(o + 192, b.getFloat(o + 192) - tx);
				b.setFloat(o + 196, b.getFloat(o + 196) - ty);
			}
		}
		return n;
	}

	// (tile's len bytes drawn onto the window's canvas at buffer b's offset
	// at, over it cleared: clear, or the background where it is the window's)
	function draw(r:Replay, f:helder.ui.layers.CompositeFrame, b:Buffer, at:Int, len:Int, p:WebPlane, opaque:Bool):Bool {
		var c = commands;
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		if (!r.began) return false;
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(at);
		c.bytes(tile, 0, len);
		c.end();
		var bg = f.background;
		c.begin(Replay.BEGIN_PASS);
		c.int(1);
		c.int(cast LoadOp.Clear);
		c.float(opaque ? (bg >> 16 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg >> 8 & 0xFF) / 255 : 0);
		c.float(opaque ? (bg & 0xFF) / 255 : 0);
		c.float(opaque ? 1 : 0);
		c.int(0);
		c.int(0);
		c.int(Replay.NONE);
		c.int(0);
		c.end();
		three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
		three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
		three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
		three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
		var k = 0, runs = p.runs, textures = p.runTextures;
		while (k < runs.length) {
			var t = textures[k >> 1];
			three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at + runs[k] * helder.ui.layers.CompositeFrame.STRIDE, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(runs[k + 1]);
			c.int(0);
			c.int(0);
			c.end();
			k += 2;
		}
		c.begin(Replay.END_PASS);
		c.end();
		c.begin(Replay.END_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		return true;
	}

	inline function three(op:Int, a:Int, b:Int, d:Int, n:Int) {
		var c = commands;
		c.begin(op);
		c.int(a);
		if (n > 1) c.int(b);
		if (n > 2) c.int(d);
		c.end();
	}

	static function meets(d:helder.ui.draw.Damage, x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		if (d.all) return true;
		for (i in 0...d.count)
			if (d.x0(i) < x1 && d.x1(i) > x0 && d.y0(i) < y1 && d.y1(i) > y0) return true;
		return false;
	}

	static function num(v:Float):String {
		var r = Math.round(v * 1000) / 1000;
		return r == Math.ffloor(r) ? Std.string(Std.int(r)) : Std.string(r);
	}
}

// (a layer of the page's: its number there, its tiles drawn)
@:hxmc.unsafe(gc)
class WebPlane extends helder.ui.layers.LayerPlane {
	public final id:Int;
	public var tw = 0;
	public var th = 0;
	public final drawn:Array<Bool> = [];
	public var owner:Null<Layers> = null;

	public function new(kind:Int, key:Dynamic, id:Int) {
		super(kind, key);
		this.id = id;
	}

	// (let go: the page's removed with the next frame)
	override public function free():Void->Void
		return () -> if (owner != null) owner.dropped.push(id);
}

// The page's layers (src/helder/ui/imports.mjs): imports of "hxmc_ui".
@:hxmc.c @:hxmc.lib("hxmc_ui") extern class WebLayerImports {
	// the canvas's context of premultiplied alpha, asked before it is made
	static function layers_alpha(canvas:Int):Void;
	// whether the page waits to read the canvas's next frame (host.gfx.readPixels)
	static function layers_reading():Int;
	// the canvas's top left w x h as it is now, read into an ImageBitmap: its number in the next update
	static function layers_snap(canvas:Int, w:Int, h:Int):Int;
	// the layers' places and tiles (JSON), the bitmaps read since the last
	static function layers_update(canvas:Int, json:CString):Void;
	// a node's system layer: a canvas of the page, its number (LayerSlot's handle)
	static function layers_slot(canvas:Int):Int;
	// a frame (the browser's: a VideoFrame's handle; 0: none) shown on it
	static function layers_slot_frame(canvas:Int, slot:Int, frame:Int):Void;
	// how its frames fill it (helder.ui.ImageFit)
	static function layers_slot_fit(canvas:Int, slot:Int, fit:Int):Void;
	static function layers_slot_free(canvas:Int, slot:Int):Void;
}
