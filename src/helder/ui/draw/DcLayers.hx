package helder.ui.draw;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.d3d11.D3D11;
import helder.gfx.d3d11.D3D11Backend;
import helder.gfx.d3d11.DComp;
import helder.os.win32.Com;
import hxmc.unsafe.*;

// The system's compositor on Windows (Layers' step 5): a window's layers
// handed to DirectComposition, split as LayerSplit splits them. The
// window's swap chain is made for composition (D3D11Backend.compose,
// asked before its device is made), the content of a visual under the
// window's target (DcRoot, made under the window's child windows: an EDIT
// stays over what is drawn, as before, and is moved as before); over it, a
// stack of visuals: the window's layer, each unit's (a scroller's content
// inside a visual clipping to its clip; a mover, its 2D transform and
// opacity an effect group's), each
// node's system layer (LayerSlot: a visual, in its clip), what is over
// each. Each layer's pixels are an IDCompositionSurface drawn by Direct3D
// 11 (BeginDraw's texture, at its offset in it: frameOnto), whose updates
// land with the commit and which keeps what it showed, so a layer drawn
// again is drawn only in the rectangle around what changed since it was
// last (LayerPlane.cut, one rectangle: a surface's update is one, its
// pixels undefined until drawn). A scroll moves its content's visual and a
// mover's transform and opacity are its visual's, so neither draws. A
// rounded scroller stays drawn (rounds false): a rectangle clip's corners
// are not UiShader's coverage (up to 119 levels off at 54 corner pixels on
// CI's runner). A frame that changes anything is one commit. Nothing
// paces it as a swap chain's present would (the program's frames present
// nothing: 700 a second on CI's runner), so each frame is shown on its own
// composition: one that comes before the composition showing the last
// waits until then, once (its statistics' next estimate at the last frame;
// a high-resolution timer, Sleep's tick being 15.6 ms; DwmFlush without
// one), and one that comes after waits for nothing. One that changes
// nothing commits nothing. A frame
// split into the window's layer alone (a scene over the window: single) is
// drawn onto the window's swap chain and presented as before, the stack
// taken out of the tree once that frame is queued. Off where the window
// has no composition (no DirectComposition, HELDER_SYSTEM_LAYERS=0); while
// running, where the system misbehaves (no commit processed for 1.5 s,
// =stall: none reported; a call failed, the device lost), off for good:
// every visual but the window's out of the tree in one commit, the
// layers let go, the next frame the window's own. Frames read back never
// use these.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.Node)
class DcLayers extends LayerSplit {
	// (before the window's device: whether its swap chain is made for composition)
	public static function asked():Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && Sys.getEnv("HELDER_ASYNC_SCROLL") != "0" && helder.os.OsThread.wanted();

	public static function wanted(device:Device):Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && device.backend == D3D11 && device.surface.kind == Win32 && backendOf(device).composition != null;

	static inline function backendOf(device:Device):D3D11Backend
		return cast @:privateAccess device.impl;

	final device:Device;
	final dc:DcRoot;
	@:allow(helder.ui.draw.DcPlane) final dev:Ptr;
	@:allow(helder.ui.draw.DcPlane) var stack = Ptr.nil();
	var stackShown = false;
	// (the stack out of the tree once the window's own frame is queued: single, a frame read back)
	var hide = false;
	// (what is in the stack now, in order)
	final shownOrder:Array<Ptr> = [];
	@:allow(helder.ui.draw.DcPlane) final got:Ptr<Ptr>;
	@:allow(helder.ui.draw.DcPlane) final floats:Ptr<Float32>;
	final ints:Ptr<Int32>;
	final stats:Ptr<Int32>;
	final commands = new Commands();
	var ring = 0;
	final clearQuad = Bytes.alloc(CompositeFrame.STRIDE);
	@:allow(helder.ui.draw.DcPlane) var d3d:Null<D3D11Backend> = null;
	// (the display's period; the commits made and the composition time of the last)
	var period = 1 / 60;
	var commits = 0;
	var committedAt = -1.0;
	var broken = false;

	// (HELDER_SYSTEM_LAYERS=stall: no commit reported processed, as a
	// misbehaving system's; tests the fallback)
	static final stall = Sys.getEnv("HELDER_SYSTEM_LAYERS") == "stall";

	public function new(device:Device) {
		super(new DcPlane(LayerPlane.BASE, null));
		this.device = device;
		(cast base : DcPlane).owner = this;
		dc = backendOf(device).composition;
		dev = dc.device;
		got = LibC.malloc(16);
		floats = LibC.malloc(32);
		ints = LibC.malloc(32);
		stats = LibC.malloc(64);
		rounds = false;
	}

	override function plane(kind:Int, key:Dynamic):LayerPlane {
		var p = new DcPlane(kind, key);
		p.owner = this;
		return p;
	}

	override public function quiet(r:Replay, on:Bool)
		(cast r.impl : D3D11Backend).quiet = on;

	override public function bytes():Float {
		var b = 0.0;
		for (p in all())
			b += (cast p : DcPlane).memory();
		return b;
	}

	function all():Array<LayerPlane>
		return [base].concat([for (p in kept) p]).concat([for (p in overs) p]);

	// (seconds on the render thread in all: showing, drawing, waiting for
	// the last commit, for DWM's next composition: tests)
	@:noCompletion public final timing = [0.0, 0.0, 0.0, 0.0];
	// layers drawn in part, and the pixels drawn in all (tests)
	@:noCompletion public var cutTotal(default, null) = 0;
	@:noCompletion public var pixelsTotal(default, null) = 0.0;
	// (the window's layer's last rectangle drawn in part: x0, y0, x1, y1: tests)
	@:noCompletion public var lastCut(default, null):Array<Int> = [];

	override public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null || broken) return;
		var began = haxe.Timer.stamp();
		d3d = cast r.impl;
		if (stack.isNull() && !makeStack()) return;
		compose(f, now, t, shown, drawn);
		var changes = 0, b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0, toDraw:Array<DcPlane> = [];
		if (!stackShown) {
			stackShown = true;
			if (IDCompositionVisual.AddVisual(dc.root, stack, 1, dc.window) < 0) {
				fail("AddVisual");
				return;
			}
			changes++;
		}
		for (q in order) {
			if (q == null) continue;
			var p:DcPlane = cast q;
			if (p.kind == LayerPlane.SLOT) {
				if (p.makeSlot()) changes++;
				continue;
			}
			if (p.kind == LayerPlane.BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != LayerPlane.BASE) continue;
			if (p.make()) changes++;
			for (s in p.slots)
				if ((cast s : DcPlane).makeSlot()) changes++;
			if (p.local(out, quadTextures, fresh)) toDraw.push(p);
		}
		changes += geometry(f, now);
		// (an EDIT and a web view are windows of their own: moved on the main thread as before)
		for (m in moves)
			helder.os.OsThread.post(m);
		changes += restack();
		for (g in gone)
			g();
		changes += gone.length;
		gone.resize(0);
		for (p in toDraw) {
			var t0 = haxe.Timer.stamp();
			var cut = p.surface() && p.drawnAt >= 0 && p.cut(p.drawnAt, p.kind == LayerPlane.BASE ? f.background : 0, true);
			var len = cut ? p.cutLen : p.len + CompositeFrame.STRIDE;
			if (p.content.isNull() || at + len > f.capacity) {
				p.invalidate();
				continue;
			}
			if (!draw(r, f, p, b, at, cut)) {
				if (!broken) p.invalidate();
				continue;
			}
			timing[1] += haxe.Timer.stamp() - t0;
			at += len;
			drawnTotal++;
			quadsTotal += cut ? Std.int(p.cutLen / CompositeFrame.STRIDE) - p.clears : p.quads.length;
			if (cut) cutTotal++;
			pixelsTotal += cut ? p.cutArea() : p.pw * p.ph;
			p.drawnAt = p.serial;
			changes++;
		}
		if (broken) return;
		// (the program's frames too: they present nothing that would wait)
		var turn = changes > 0 || drawn;
		if (turn) pace();
		if (changes > 0) {
			// (one in flight: the last one processed first, or long enough)
			var t0 = haxe.Timer.stamp(), until = t0 + period * 2;
			while (!processed() && haxe.Timer.stamp() < until)
				Sys.sleep(0.0005);
			timing[2] += haxe.Timer.stamp() - t0;
			stalled();
			if (broken) return;
			var hr = IDCompositionDevice.Commit(dev);
			if (hr < 0) {
				fail('Commit (HRESULT 0x${StringTools.hex(hr, 8)})');
				return;
			}
			commits++;
			committedAt = clock();
		}
		if (turn) turned();
		frames++;
		timing[0] += haxe.Timer.stamp() - began;
		if (single) suspend();
	}

	// (the stack, made the first time)
	function makeStack():Bool {
		stack = visual();
		if (stack.isNull()) {
			fail("no visual");
			return false;
		}
		return true;
	}

	@:allow(helder.ui.draw.DcPlane) function visual():Ptr
		return IDCompositionDevice.CreateVisual(dev, got) < 0 ? Ptr.nil() : got.value;

	// (DirectComposition's clock now, its period: the frame statistics; the
	// time of the last batch of commands it processed)
	function clock():Float {
		if (IDCompositionDevice.GetFrameStatistics(dev, stats) < 0) return haxe.Timer.stamp();
		var s = stats, freq = big(6);
		if (s[3] > 0 && s[2] > 0) period = s[3] / s[2];
		return freq > 0 ? big(4) / freq : haxe.Timer.stamp();
	}

	// (the composition that shows the last frame, DirectComposition's clock;
	// the timer that waits for it)
	var turnAt = -1.0;
	var timer = Ptr.nil();
	var timed = false;

	// (a frame before the composition that shows the last: waited until then,
	// once; after it, none)
	function pace() {
		if (turnAt < 0) return;
		var t0 = haxe.Timer.stamp(), wait = turnAt - clock();
		if (wait <= 0.0002) return;
		// (an estimate gone wrong: a period at most)
		if (wait > period * 1.5) wait = period;
		if (!timed) {
			timed = true;
			// (CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS)
			timer = WaitTimer.CreateWaitableTimerExW(Ptr.nil(), Ptr.nil(), 2, 0x1F0003);
		}
		var due = ints.offset(6);
		due[0] = -Math.round(wait * 1e7);
		due[1] = -1;
		if (timer.isNull() || WaitTimer.SetWaitableTimer(timer, due, 0, Ptr.nil(), Ptr.nil(), 0) == 0 || WaitTimer.WaitForSingleObjectEx(timer, 100, 0) != 0) {
			// (DWM's next composition: the one showing the last frame, it being still to come)
			if (Dwm.DwmFlush() < 0) Sys.sleep(wait);
		}
		timing[3] += haxe.Timer.stamp() - t0;
	}

	// (a frame shown: the next not before the composition that shows it, the next its statistics estimate, else a period from now)
	function turned() {
		var now = clock(), freq = big(6), next = freq > 0 ? big(8) / freq : -1.0;
		turnAt = next > now && next - now <= period * 1.5 ? next : now + period;
	}

	function processed():Bool {
		if (commits == 0) return true;
		if (stall || IDCompositionDevice.GetFrameStatistics(dev, stats) < 0) return false;
		var freq = big(6);
		return freq > 0 && big(0) / freq >= committedAt;
	}

	// (a LARGE_INTEGER of the statistics at int i, as a Float)
	inline function big(i:Int):Float {
		var lo = stats[i];
		return stats[i + 1] * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
	}

	// (a system whose commits are never processed (a compositor that stalls)
	// shows nothing of them: off once none was for STALL seconds while one waited)
	function stalled() {
		var t = haxe.Timer.stamp();
		if (processed()) progress = t else if (progress < 0) progress = t else if (t - progress > STALL) fail('no commit processed in $STALL s');
	}

	var progress = -1.0;

	static inline var STALL = 1.5;

	// (the layers in their order in the stack, a scroller's clip's inside it: the changes)
	function restack():Int {
		var want:Array<Ptr> = [];
		for (q in order) {
			var p:DcPlane = cast q;
			if (p == null || !p.made() || p.kind != LayerPlane.BASE && p.kind != LayerPlane.SLOT && p.quads.length == 0) continue;
			want.push(p.top());
			p.restackInner();
		}
		var same = want.length == shownOrder.length;
		if (same) for (i in 0...want.length)
			if (want[i] != shownOrder[i]) same = false;
		if (same) return 0;
		IDCompositionVisual.RemoveAllVisuals(stack);
		var below = Ptr.nil();
		for (v in want) {
			IDCompositionVisual.AddVisual(stack, v, 1, below);
			below = v;
		}
		shownOrder.resize(0);
		for (v in want)
			shownOrder.push(v);
		return 1;
	}

	// (where the layers go now, in pixels: a scroller's content by its
	// offset, a mover's by its transform and opacity sampled, a system layer
	// by its scroller's and its mover's: the changes)
	function geometry(f:CompositeFrame, now:Array<Float>):Int {
		var s = f.scale, n = 0;
		for (q in units) {
			var u:DcPlane = cast q;
			if (u.kind == LayerPlane.SLOT) {
				n += slotAt(f, u, null, now);
				continue;
			}
			if (u.quads.length == 0) continue;
			if (u.kind == LayerPlane.SCROLL) {
				var k = u.index, dx = (f.offsets[2 * k] - now[2 * k]) * s, dy = (f.offsets[2 * k + 1] - now[2 * k + 1]) * s;
				n += u.clipTo(u.clip, u.cx0, u.cy0, u.cx1, u.cy1, u.radii);
				n += u.offset(u.ox + dx, u.oy + dy);
				for (sp in u.slots)
					n += slotAt(f, cast sp, u, now);
			} else {
				var m = f.heldMoved, k = u.index * 7, a = m[k], b = m[k + 1], c = m[k + 2], d = m[k + 3];
				n += u.transform(a, b, c, d, a * u.ox + c * u.oy + m[k + 4], b * u.ox + d * u.oy + m[k + 5], m[k + 6]);
			}
		}
		for (q in order)
			if (q != null && q.kind == LayerPlane.OVER && q.quads.length > 0) n += (cast q : DcPlane).offset(q.ox, q.oy);
		return n;
	}

	// (system layer p where it is now: at its box as drawn, moved by its
	// scroller's offsets and its mover's change as sampled, cut to its clip
	// (its scroller's, in: the unit it is in) and to its box)
	function slotAt(f:CompositeFrame, p:DcPlane, in_:Null<DcPlane>, now:Array<Float>):Int {
		var d = f.slotData, o = p.index * CompositeFrame.SLOT, s = f.scale;
		var fr = Std.int(d[o + 2]), c = Std.int(d[o + 3]), m = Std.int(d[o + 4]);
		var ax = d[o + 6], ay = d[o + 7], bx = d[o + 8], qy = d[o + 11], alpha = 1.0;
		if (m >= 0) {
			var mv = f.moved, k = m * 7, by = d[o + 9], qx = d[o + 10];
			var nax = mv[k] * ax + mv[k + 2] * ay + mv[k + 4], nay = mv[k + 1] * ax + mv[k + 3] * ay + mv[k + 5];
			var nbx = mv[k] * bx + mv[k + 2] * by + mv[k + 4], nqy = mv[k + 1] * qx + mv[k + 3] * qy + mv[k + 5];
			ax = nax;
			ay = nay;
			bx = nbx;
			qy = nqy;
			alpha = mv[k + 6];
		}
		var dx = fr >= 0 ? Math.fround(f.shift(fr, now, true) * s) : 0.0, dy = fr >= 0 ? Math.fround(f.shift(fr, now, false) * s) : 0.0;
		var w = bx - ax, h = qy - ay;
		if (!(w > 0) || !(h > 0) || !LayerPlane.fine(w) || !LayerPlane.fine(h)) return 0;
		var n = 0, x = Math.round(ax + dx), y = Math.round(ay + dy);
		if (in_ == null) {
			var cx0 = p.cx0, cy0 = p.cy0, cx1 = p.cx1, cy1 = p.cy1;
			if (c >= 0) {
				var ex = Math.fround(f.shift(c, now, true) * s), ey = Math.fround(f.shift(c, now, false) * s);
				cx0 += ex;
				cy0 += ey;
				cx1 += ex;
				cy1 += ey;
			}
			n += p.clipTo(p.clip, cx0, cy0, cx1, cy1, p.radii);
		}
		return n + p.placeSlot(x, y, Math.round(w), Math.round(h), alpha);
	}

	// (quads into p's surface at buffer b's offset at: all of it over a
	// clear rectangle (never a clear of the texture, an atlas of the
	// system's); cut, only the rectangle that changed since it was drawn,
	// cleared without blending, then what meets it, the rest as it was)
	function draw(r:Replay, f:CompositeFrame, p:DcPlane, b:Buffer, at:Int, cut:Bool):Bool {
		var c = commands, S = CompositeFrame.STRIDE, rect = ints;
		var x0 = 0, y0 = 0;
		if (cut) {
			x0 = Std.int(p.cutBytes.getFloat(8));
			y0 = Std.int(p.cutBytes.getFloat(12));
			rect[0] = x0;
			rect[1] = y0;
			rect[2] = Std.int(p.cutBytes.getFloat(24));
			rect[3] = Std.int(p.cutBytes.getFloat(44));
			if (p.kind == LayerPlane.BASE) lastCut = [rect[0], rect[1], rect[2], rect[3]];
		}
		var offset:Ptr<Int32> = ints.offset(4);
		var hr = IDCompositionSurface.BeginDraw(p.content, cut ? rect : Ptr.nil(), IID.ID3D11Texture2D, got, offset);
		if (hr < 0) {
			fail('BeginDraw (HRESULT 0x${StringTools.hex(hr, 8)})');
			return false;
		}
		var tex = got.value, gpu = d3d;
		gpu.frameOnto(tex, offset[0] - x0, offset[1] - y0, p.pw, p.ph);
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		var ok = r.began;
		if (ok) {
			c.begin(Replay.WRITE_BUFFER);
			c.int(b.id());
			c.int(at);
			if (cut) c.bytes(p.cutBytes, 0, p.cutLen) else {
				LayerPlane.rect(clearQuad, 0, 0, 0, p.pw, p.ph, p.pw, p.ph, p.kind == LayerPlane.BASE ? f.background : 0);
				c.bytes(clearQuad, 0, S);
			}
			c.end();
			if (!cut) {
				c.begin(Replay.WRITE_BUFFER);
				c.int(b.id());
				c.int(at + S);
				c.bytes(p.bytes, 0, p.len);
				c.end();
			}
			c.begin(Replay.BEGIN_PASS);
			c.int(1);
			c.int(cast LoadOp.Load);
			for (_ in 0...4)
				c.float(0);
			c.int(0);
			c.int(0);
			c.int(Replay.NONE);
			c.int(0);
			c.end();
			three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
			three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
			three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
			var clears = cut ? p.clears : 1;
			three(Replay.SET_PIPELINE, f.clearPipeline.id(), -1, -1, 1);
			three(Replay.SET_TEXTURE, f.imageSlot, f.blank.id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(clears);
			c.int(0);
			c.int(0);
			c.end();
			var from = at + clears * S, runs = cut ? p.cutRuns : p.runs, textures = cut ? p.cutTextures : p.runTextures, k = 0;
			three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
			while (k < runs.length) {
				var t = textures[k >> 1];
				three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
				three(Replay.SET_VERTEX_BUFFER, 1, b.id(), from + runs[k] * S, 3);
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
		}
		c.begin(Replay.END_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		gpu.frameOnto(Ptr.nil(), 0, 0, 0, 0);
		Com.release(tex);
		hr = IDCompositionSurface.EndDraw(p.content);
		if (hr < 0) {
			fail('EndDraw (HRESULT 0x${StringTools.hex(hr, 8)})');
			return false;
		}
		return ok;
	}

	inline function three(op:Int, a:Int, b:Int, d:Int, n:Int) {
		var c = commands;
		c.begin(op);
		c.int(a);
		if (n > 1) c.int(b);
		if (n > 2) c.int(d);
		c.end();
	}

	// (off for good, the window's own frames from the next, which the
	// program is asked for: what is on the layers may never have shown)
	function fail(why:String) {
		if (broken) return;
		broken = true;
		off = true;
		single = true;
		fell = why;
		redraw = true;
		hide = true;
		Sys.println("helder.ui: system layers off: " + why);
	}

	// a visual for a node's LayerSlot (its owner sets its content), placed
	// by the frames; nil where there are no system layers (any thread: made on the render thread)
	public function visualFor():Ptr {
		var v = Ptr.nil();
		device.inOrder(_ -> if (!broken) v = visual());
		device.settle();
		return v;
	}

	// (a visualFor() of one colour, 0xRRGGBB, of any size: a pixel's surface stretched: tests)
	@:noCompletion public function solid(rgb:Int):Ptr {
		var v = Ptr.nil();
		device.inOrder(r -> {
			if (broken) return;
			var inner = visual();
			if (inner.isNull() || IDCompositionDevice.CreateSurface(dev, 1, 1, D3D.FORMAT_R8G8B8A8_UNORM, D3D.ALPHA_MODE_PREMULTIPLIED, got) < 0) return;
			var s = got.value, offset:Ptr<Int32> = ints.offset(4);
			if (IDCompositionSurface.BeginDraw(s, Ptr.nil(), IID.ID3D11Texture2D, got, offset) < 0) return;
			var tex = got.value;
			(cast r.impl : D3D11Backend).writeTexel(tex, offset[0], offset[1], 0xFF000000 | ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF));
			Com.release(tex);
			IDCompositionSurface.EndDraw(s);
			IDCompositionVisual.SetContent(inner, s);
			Com.release(s);
			// (nearest, hard edges: the pixel's colour over all of it)
			IDCompositionVisual.SetBitmapInterpolationMode(inner, 0);
			IDCompositionVisual.SetBorderMode(inner, 1);
			var m = floats;
			m[0] = 16384;
			m[1] = 0;
			m[2] = 0;
			m[3] = 16384;
			m[4] = 0;
			m[5] = 0;
			IDCompositionVisual.SetTransform(inner, m);
			v = visual();
			if (!v.isNull()) IDCompositionVisual.AddVisual(v, inner, 1, Ptr.nil());
		});
		device.settle();
		return v;
	}

	override public function suspend() {
		hide = true;
		base.reset();
	}

	override public function windowShown() {
		redraw = false;
		if (!hide || stack.isNull()) return;
		hide = false;
		if (broken) {
			drop();
			return;
		}
		if (stackShown) {
			stackShown = false;
			IDCompositionVisual.RemoveVisual(dc.root, stack);
			IDCompositionDevice.Commit(dev);
		}
	}

	// (off for good: the root's children but the window's own visual gone in
	// one commit, every layer and slot with them, whatever the stack held;
	// the layers' visuals and surfaces let go)
	function drop() {
		stackShown = false;
		IDCompositionVisual.RemoveAllVisuals(dc.root);
		IDCompositionVisual.AddVisual(dc.root, dc.window, 1, Ptr.nil());
		var hr = IDCompositionDevice.Commit(dev);
		freeAll();
		kept.clear();
		overs.clear();
		gone.resize(0);
		shownOrder.resize(0);
		Com.release(stack);
		stack = Ptr.nil();
		Sys.println('helder.ui: system layers off: the window\'s own frame shown, the layers taken out of the tree (commit 0x${StringTools.hex(hr, 8)})');
	}

	// (each layer let go, the system layers' first: a box is taken out of its
	// scroller's clip, which must not be let go before)
	function freeAll() {
		var ps = all();
		for (p in ps.filter(p -> p.kind == LayerPlane.SLOT).concat(ps.filter(p -> p.kind != LayerPlane.SLOT)))
			(cast p : DcPlane).free()();
	}

	override public function dispose() {
		freeAll();
		kept.clear();
		overs.clear();
		if (!stack.isNull()) {
			if (stackShown) IDCompositionVisual.RemoveVisual(dc.root, stack);
			IDCompositionDevice.Commit(dev);
			Com.release(stack);
		}
		stack = Ptr.nil();
		if (!timer.isNull()) hxmc.unsafe.Win32.CloseHandle(timer);
		timer = Ptr.nil();
		LibC.free(got);
		LibC.free(floats);
		LibC.free(ints);
		LibC.free(stats);
	}
}

// (a layer as DirectComposition's: its visual and its surface; a
// scroller's and a system layer's clip (a visual of no content, its clip
// in the window's pixels, rounded: a rectangle clip), a system layer's box
// (a visual cut to it, the slot's in it); a mover's effect (its opacity); what was set)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.DcLayers)
private class DcPlane extends LayerPlane {
	public var owner:DcLayers;
	public var visual = Ptr.nil();
	public var content = Ptr.nil();
	public var clip = Ptr.nil();
	var box = Ptr.nil();
	// (the visual a system layer's box is in: its own clip, or its
	// scroller's; a visual has one parent, and one added to another while it
	// is in the first is not added: a slot that was its scroller's and is
	// then a unit of its own stayed in the scroller's clip, out of the tree)
	var boxIn = Ptr.nil();
	var effect = Ptr.nil();
	var rounded = Ptr.nil();
	var surfW = 0;
	var surfH = 0;
	// (the draw its surface holds: LayerPlane.serial, -1 none)
	public var drawnAt = -1;
	final set:Array<Float> = [for (_ in 0...16) -1e300];
	final innerOrder:Array<Ptr> = [];

	public function made():Bool
		return !visual.isNull() || !clip.isNull() || !box.isNull();

	// (what goes in the stack: a clip, else the layer)
	public function top():Ptr
		return !clip.isNull() ? clip : kind == LayerPlane.SLOT ? box : visual;

	// (its visual, a scroller's clip, a mover's effect, made the first time: whether made now)
	public function make():Bool {
		if (!visual.isNull()) return false;
		var o = owner;
		visual = o.visual();
		if (kind == LayerPlane.SCROLL) {
			clip = o.visual();
			if (!clip.isNull()) IDCompositionVisual.AddVisual(clip, visual, 1, Ptr.nil());
		}
		if (kind == LayerPlane.MOVER && IDCompositionDevice.CreateEffectGroup(o.dev, o.got) >= 0) {
			effect = o.got.value;
			IDCompositionVisual.SetEffect(visual, effect);
		}
		return true;
	}

	// (its surface of its size now, made again on another: whether it holds anything)
	public function surface():Bool {
		if (visual.isNull()) return false;
		if (content.isNull() || surfW != pw || surfH != ph) {
			var o = owner;
			if (IDCompositionDevice.CreateSurface(o.dev, pw, ph, D3D.FORMAT_R8G8B8A8_UNORM, D3D.ALPHA_MODE_PREMULTIPLIED, o.got) < 0) {
				o.fail('CreateSurface $pw x $ph');
				return false;
			}
			Com.release(content);
			content = o.got.value;
			surfW = pw;
			surfH = ph;
			drawnAt = -1;
			IDCompositionVisual.SetContent(visual, content);
			return false;
		}
		return true;
	}

	// (a system layer in its clip: a clip of its own made the first time, or
	// its scroller's; its box, the node's visual in it)
	public function makeSlot():Bool {
		var o = owner, n = false;
		if (box.isNull()) {
			box = o.visual();
			if (box.isNull()) return false;
			IDCompositionVisual.AddVisual(box, slot.handle, 1, Ptr.nil());
			n = true;
		}
		if (attached < 0 && clip.isNull()) {
			clip = o.visual();
			n = true;
		}
		if (attached < 0 && !clip.isNull() && boxIn != clip) {
			moveBox(clip, Ptr.nil());
			n = true;
		}
		return n;
	}

	// (the box out of the visual it is in, into to, above below (nil: under all))
	public function moveBox(to:Ptr, below:Ptr) {
		if (!boxIn.isNull()) IDCompositionVisual.RemoveVisual(boxIn, box);
		boxIn = Ptr.nil();
		if (!to.isNull() && IDCompositionVisual.AddVisual(to, box, 1, below) >= 0) boxIn = to;
	}

	// (a scroller's clip: its content, then the system layers in it, in order)
	public function restackInner() {
		if (kind != LayerPlane.SCROLL || clip.isNull()) return;
		var want = [visual].concat([for (s in slots) if (!(cast s : DcPlane).box.isNull()) (cast s : DcPlane).box]);
		var same = want.length == innerOrder.length;
		if (same) for (i in 0...want.length)
			if (want[i] != innerOrder[i]) same = false;
		if (same) return;
		IDCompositionVisual.RemoveAllVisuals(clip);
		// (the boxes that were in it: in none now)
		for (q in slots) {
			var d:DcPlane = cast q;
			if (d.boxIn == clip) d.boxIn = Ptr.nil();
		}
		var below = Ptr.nil();
		for (v in want) {
			var d = v == visual ? null : Lambda.find(slots, q -> (cast q : DcPlane).box == v);
			if (d != null) (cast d : DcPlane).moveBox(clip, below) else IDCompositionVisual.AddVisual(clip, v, 1, below);
			below = v;
		}
		innerOrder.resize(0);
		for (v in want)
			innerOrder.push(v);
	}

	// (visual v clipped to x0, y0, x1, y1 in the window's pixels (it is at
	// 0, 0), its corners' radii r (top left, top right, bottom right, bottom left))
	public function clipTo(v:Ptr, x0:Float, y0:Float, x1:Float, y1:Float, r:Array<Float>):Int {
		if (v.isNull() || !LayerPlane.fine(x0) || !LayerPlane.fine(y0) || !LayerPlane.fine(x1) || !LayerPlane.fine(y1)) return 0;
		var round = r[0] > 1e-3 || r[1] > 1e-3 || r[2] > 1e-3 || r[3] > 1e-3;
		if (set[6] == x0 && set[7] == y0 && set[8] == x1 && set[9] == y1 && set[12] == r[0] && set[13] == r[1] && set[14] == r[2] && set[15] == r[3]) return 0;
		set[6] = x0;
		set[7] = y0;
		set[8] = x1;
		set[9] = y1;
		for (j in 0...4)
			set[12 + j] = r[j];
		if (!round) {
			var f = owner.floats;
			f[0] = x0;
			f[1] = y0;
			f[2] = x1;
			f[3] = y1;
			IDCompositionVisual.SetClip(v, f);
			return 1;
		}
		var o = owner;
		if (rounded.isNull()) {
			if (IDCompositionDevice.CreateRectangleClip(o.dev, o.got) < 0) return 0;
			rounded = o.got.value;
			IDCompositionVisual.SetClipObject(v, rounded);
		}
		var c = rounded;
		IDCompositionRectangleClip.SetLeft(c, x0);
		IDCompositionRectangleClip.SetTop(c, y0);
		IDCompositionRectangleClip.SetRight(c, x1);
		IDCompositionRectangleClip.SetBottom(c, y1);
		IDCompositionRectangleClip.SetTopLeftRadiusX(c, r[0]);
		IDCompositionRectangleClip.SetTopLeftRadiusY(c, r[0]);
		IDCompositionRectangleClip.SetTopRightRadiusX(c, r[1]);
		IDCompositionRectangleClip.SetTopRightRadiusY(c, r[1]);
		IDCompositionRectangleClip.SetBottomRightRadiusX(c, r[2]);
		IDCompositionRectangleClip.SetBottomRightRadiusY(c, r[2]);
		IDCompositionRectangleClip.SetBottomLeftRadiusX(c, r[3]);
		IDCompositionRectangleClip.SetBottomLeftRadiusY(c, r[3]);
		return 1;
	}

	// (its visual at x, y pixels, whole ones: its pixels the frame's)
	public function offset(x:Float, y:Float):Int {
		if (visual.isNull() || !LayerPlane.fine(x) || !LayerPlane.fine(y)) return 0;
		var x = Math.round(x), y = Math.round(y);
		if (set[0] == x && set[1] == y) return 0;
		set[0] = x;
		set[1] = y;
		IDCompositionVisual.SetOffsetX(visual, x);
		IDCompositionVisual.SetOffsetY(visual, y);
		return 1;
	}

	// (a mover's: its pixels by the 2D transform a, b, c, d, e, f (x' = a x
	// + c y + e, y' = b x + d y + f), of opacity alpha)
	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float, alpha:Float):Int {
		if (visual.isNull()) return 0;
		for (v in [a, b, c, d, e, f])
			if (!LayerPlane.fine(v)) return 0;
		var n = 0;
		if (set[0] != a || set[1] != b || set[2] != c || set[3] != d || set[4] != e || set[5] != f) {
			for (j => v in [a, b, c, d, e, f])
				set[j] = v;
			var m = owner.floats;
			m[0] = a;
			m[1] = b;
			m[2] = c;
			m[3] = d;
			m[4] = e;
			m[5] = f;
			IDCompositionVisual.SetTransform(visual, m);
			n++;
		}
		if (set[10] != alpha && LayerPlane.fine(alpha) && !effect.isNull()) {
			set[10] = alpha;
			IDCompositionEffectGroup.SetOpacity(effect, alpha);
			n++;
		}
		return n;
	}

	// (a system layer at x, y, w x h pixels: its box clips the node's visual
	// to it, the node's at its corner; of opacity alpha)
	public function placeSlot(x:Float, y:Float, w:Float, h:Float, alpha:Float):Int {
		if (box.isNull()) return 0;
		var on = slot.shown ? 1 : 0;
		if (set[0] == x && set[1] == y && set[2] == w && set[3] == h && set[4] == alpha && set[5] == on) return 0;
		set[0] = x;
		set[1] = y;
		set[2] = w;
		set[3] = h;
		set[4] = alpha;
		set[5] = on;
		var f = owner.floats;
		f[0] = x;
		f[1] = y;
		f[2] = on == 1 ? x + w : x;
		f[3] = on == 1 ? y + h : y;
		IDCompositionVisual.SetClip(box, f);
		IDCompositionVisual.SetOffsetX(slot.handle, x);
		IDCompositionVisual.SetOffsetY(slot.handle, y);
		if (LayerPlane.fine(alpha)) {
			var o = owner;
			if (effect.isNull() && alpha < 1 && IDCompositionDevice.CreateEffectGroup(o.dev, o.got) >= 0) {
				effect = o.got.value;
				IDCompositionVisual.SetEffect(box, effect);
			}
			if (!effect.isNull()) IDCompositionEffectGroup.SetOpacity(effect, alpha);
		}
		return 1;
	}

	public function memory():Float
		return content.isNull() ? 0 : surfW * surfH * 4.0;

	override public function free():Void->Void {
		// (the box out of a scroller's clip it is in, which outlives it)
		var outer = boxIn != clip ? boxIn : Ptr.nil();
		boxIn = Ptr.nil();
		var all = [content, visual, clip, box, effect, rounded], sl = kind == LayerPlane.SLOT ? slot.handle : Ptr.nil();
		var parent = clip.isNull() ? box : clip;
		content = visual = clip = box = effect = rounded = Ptr.nil();
		return () -> {
			// (the node's visual out of its box: its owner's still)
			if (!sl.isNull() && !all[3].isNull()) IDCompositionVisual.RemoveVisual(all[3], sl);
			if (!outer.isNull() && !all[3].isNull()) IDCompositionVisual.RemoveVisual(outer, all[3]);
			if (!parent.isNull()) IDCompositionVisual.RemoveAllVisuals(parent);
			for (o in all)
				Com.release(o);
		}
	}
}
#end
