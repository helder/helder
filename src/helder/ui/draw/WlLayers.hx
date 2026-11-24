package helder.ui.draw;

#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
import haxe.Timer;
import helder.gfx.*;
import helder.gfx.gl.GLBackend;
import helder.os.wayland.Proxy;
import helder.os.wayland.WaylandClient;
import helder.os.wayland.WaylandWindow;
import helder.os.wayland.protocol.LinuxDmabufV1Protocol;
import helder.os.wayland.protocol.PresentationTimeProtocol;
import helder.os.wayland.protocol.SinglePixelBufferV1Protocol;
import helder.os.wayland.protocol.ViewporterProtocol;
import helder.os.wayland.protocol.WaylandProtocol;
import hxmc.unsafe.*;

// The system's compositor on Wayland (Layers' step 5): a window's layers
// handed to the compositor as wl_subsurfaces of the window's wl_surface,
// split as LayerSplit splits them: the window's layer, each unit's (a
// scroller's content cropped to its clip by its wp_viewport: a subsurface
// is not clipped by its parent), each node's system layer (LayerSlot: a
// wl_surface of its owner's buffers, desynchronized, cropped by us), what
// is over each, stacked over the window's own surface, none taking input
// (an empty input region: the pointer and touches are the window's). Each
// has buffers of its own drawn by GL into a texture: a dma-buf of it
// (EGL_MESA_image_dma_buf_export, zwp_linux_dmabuf_v1's create, its answer
// waited for) where the compositor takes it, else the texture read back
// into wl_shm memory; drawn again only where its quads, size or what they
// sample changed, and then only the rectangle that changed since that
// buffer was drawn (LayerPlane.cut: our buffers' age; damage_buffer). A
// layer of one square quad of one colour is a single-pixel buffer
// stretched by its viewport, drawn by nothing. A scroll moves its
// content's crop and a mover's translation its subsurface, so neither
// draws. Subsurfaces sit on whole points (set_position's, the viewport's
// destination): clips on that grid, buffers placed on it, movers rounded
// to it as they move; one that turns, scales or fades stays drawn (unfit:
// no transform, no opacity here), as rounded scrollers do (rounds). A
// frame that changes anything is one commit of the window's surface, each
// layer's state cached until it (synchronized subsurfaces); the next waits
// for that one's frame callback (the compositor's turn; two periods at
// most: a headless weston presents two refreshes after a commit, so
// waiting for wp_presentation's halves the rate), whose feedback gives the
// display's period. A frame split into the window's layer alone is
// drawn onto the window's own EGL surface as before, the layers unmapped
// in that same commit; so are a new window's first frame and the first
// after a scale change (the surface's own buffer, under the stack, at its
// scale). Off without wl_subcompositor or wp_viewporter, and with
// HELDER_SYSTEM_LAYERS=0; while running, off for good where nothing
// committed was shown within 1.5 s (=stall: none counted; a hidden
// window's commits, never shown, are not that once one was), a buffer
// could not be made or the connection broke: the layers unmapped with the
// window's next frame, then let go. Frames read back never use these.
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.CompositeFrame)
@:access(helder.ui.Node)
@:access(helder.os.wayland.WaylandWindow)
class WlLayers extends LayerSplit {
	public static function wanted(device:Device):Bool
		return Sys.getEnv("HELDER_SYSTEM_LAYERS") != "0" && device.backend == GL && device.surface.kind == Wayland
			&& !WaylandWindow.subcompositor.isNull() && !WaylandWindow.viewporter.isNull() && WaylandWindow.of(device.surface) != null;

	final device:Device;
	final window:WaylandWindow;
	final display:Ptr;
	final queue:Ptr;
	// (wrappers on our queue: what they make is ours, its events the render thread's)
	final wrappers:Array<Ptr> = [];
	final compositor:WlCompositor;
	final subcompositor:WlSubcompositor;
	final viewporter:WpViewporter;
	final shm:WlShm;
	final pixel:WpSinglePixelBufferManagerV1;
	final dmabuf:ZwpLinuxDmabufV1;
	final presentation:WpPresentation;
	final parent:WlSurface;
	final empty:WlRegion;
	var gl:Null<GLBackend> = null;
	final commands = new Commands();
	var ring = 0;
	// (wl_shm's format of GL's RGBA bytes, else ARGB8888's, swapped; dma-bufs while the compositor takes ours)
	var shmFormat = 0;
	var dmabufs = false;
	// (the window's scale: pixels a point, the grid in pixels; the scale its own surface's buffer has)
	var k = 1.0;
	// (the window's background opaque: the base layer's opaque region)
	var opaque = true;
	var scale120 = 0;
	var primedAt = 0;
	var primedW = 0;
	var primedH = 0;
	// (the commit in flight, waiting for its presentation; whether any was; the display's period)
	var inFlight = false;
	var frame:Null<{proxy:Ptr, listener:Int}> = null;
	var feedback:Null<{proxy:Ptr, listener:Int}> = null;
	var shownAny = false;
	var firstCommit = -1.0;
	var period = 1 / 60;
	var broken = false;
	var hide = false;
	// (what the stack's order was set to)
	final shownOrder:Array<Ptr> = [];
	// (the nodes' system layers' surfaces, by handle: their viewports ours, the size of their owners' buffers)
	final slotsBy = new Map<String, WlSlot>();
	// (the slots' subsurfaces synchronized for this frame's commit: desynchronized after it)
	final resync:Array<WlSlot> = [];

	static inline var ABGR8888 = 0x34324241;
	static inline var STALL = 1.5;

	// (HELDER_SYSTEM_LAYERS=stall: no commit counted shown, as a
	// misbehaving compositor's; tests the fallback)
	static final stall = Sys.getEnv("HELDER_SYSTEM_LAYERS") == "stall";

	public function new(device:Device) {
		super(new WlPlane(LayerPlane.BASE, null));
		this.device = device;
		(cast base : WlPlane).owner = this;
		window = WaylandWindow.of(device.surface);
		display = WaylandWindow.display;
		var q = WaylandClient.wl_display_create_queue(display), ws = wrappers;
		queue = q;
		compositor = wrap(WaylandWindow.compositor, q, ws);
		subcompositor = wrap(WaylandWindow.subcompositor, q, ws);
		viewporter = wrap(WaylandWindow.viewporter, q, ws);
		shm = wrap(WaylandWindow.shm, q, ws);
		pixel = wrap(WaylandWindow.singlePixel, q, ws);
		dmabuf = wrap(WaylandWindow.dmabuf, q, ws);
		presentation = wrap(WaylandWindow.presentation, q, ws);
		parent = wrap(window.wlSurface, q, ws);
		empty = compositor.createRegion();
		shmFormat = WaylandWindow.shmFormats.contains(ABGR8888) ? ABGR8888 : 0;
		dmabufs = !dmabuf.isNull() && Sys.getEnv("HELDER_NO_DMABUF") != "1";
		rounds = false;
		priming = true;
	}

	static function wrap(p:Ptr, q:Ptr, into:Array<Ptr>):Ptr {
		if (p.isNull()) return p;
		var w = WaylandClient.wl_proxy_create_wrapper(p);
		WaylandClient.wl_proxy_set_queue(w, q);
		into.push(w);
		return w;
	}

	override function plane(kind:Int, key:Dynamic):LayerPlane {
		var p = new WlPlane(kind, key);
		p.owner = this;
		p.grid = Std.int(grid);
		return p;
	}

	override public function quiet(r:Replay, on:Bool)
		(cast r.impl : GLBackend).quiet = on;

	override public function bytes():Float {
		var b = 0.0;
		for (p in all())
			b += (cast p : WlPlane).memory();
		return b;
	}

	function all():Array<LayerPlane>
		return [base].concat([for (p in kept) p]).concat([for (p in overs) p]);

	// (seconds on the render thread in all: showing, drawing, waiting for a
	// buffer, for the last commit's presentation: tests)
	@:noCompletion public final timing = [0.0, 0.0, 0.0, 0.0];
	// layers drawn in part, the pixels drawn in all; layers of one colour; buffers that are dma-bufs (tests)
	@:noCompletion public var cutTotal(default, null) = 0;
	@:noCompletion public var pixelsTotal(default, null) = 0.0;
	@:noCompletion public var solidTotal(default, null) = 0;
	@:noCompletion public var dmabufTotal(default, null) = 0;
	@:noCompletion public var shmTotal(default, null) = 0;

	override public function show(r:Replay, f:CompositeFrame, now:Array<Float>, t:Float, shown:Null<Array<Float>>, drawn:Bool, moves:Array<Void->Void>) {
		if (f.buffers.length == 0 || f.pipeline == null || broken) return;
		var began = Timer.stamp();
		gl = cast r.impl;
		var s = window.scale120;
		if (s != scale120) rescaled(s);
		// (the window's own buffer of another scale or size under the stack:
		// a commit of ours would give it this scale, the shell would place
		// the window by that size; its own frame first)
		if (s != primedAt || f.width != primedW || f.height != primedH) {
			priming = true;
			redraw = true;
			return;
		}
		compose(f, now, t, shown, drawn);
		if (unfitted(f)) compose(f, now, t, shown, drawn);
		opaque = f.background >>> 24 == 255;
		dispatch(0);
		var changes = 0, b = f.buffers[ring = (ring + 1) % f.buffers.length], at = 0, toDraw:Array<WlPlane> = [];
		for (q in order) {
			if (q == null || q.kind == LayerPlane.SLOT) continue;
			var p:WlPlane = cast q;
			if (p.kind == LayerPlane.BASE) p.place(0, 0, f.width, f.height) else p.fit();
			if (p.quads.length == 0 && p.kind != LayerPlane.BASE) {
				if (p.unmap()) changes++;
				continue;
			}
			if (p.make()) changes++;
			if (p.local(out, quadTextures, fresh)) toDraw.push(p) else if (p.remap()) changes++;
		}
		for (p in toDraw) {
			var t0 = Timer.stamp();
			if (p.kind != LayerPlane.BASE && p.solid()) {
				solidTotal++;
				changes++;
				continue;
			}
			var buf = p.next();
			if (broken) return;
			if (buf == null) {
				p.retry();
				continue;
			}
			var shmBuf = buf.texture == 0;
			var cut = p.cut(shmBuf ? Std.int(Math.min(buf.at, p.texAt)) : buf.at, p.kind == LayerPlane.BASE ? f.background : 0, shmBuf);
			var len = cut ? p.cutLen : p.len;
			if (at + len > f.capacity || !draw(r, f, shmBuf ? p.texture : buf.texture, p, b, at, cut, shmBuf ? buf : null)) {
				p.invalidate();
				continue;
			}
			timing[1] += Timer.stamp() - t0;
			at += len;
			drawnTotal++;
			quadsTotal += cut ? Std.int(p.cutLen / CompositeFrame.STRIDE) - p.clears : p.quads.length;
			if (cut) cutTotal++;
			pixelsTotal += cut ? p.cutArea() : p.pw * p.ph;
			buf.at = p.serial;
			if (shmBuf) p.texAt = p.serial;
			p.attach(buf, cut);
			changes++;
		}
		changes += geometry(f, now);
		changes += restack();
		for (g in gone)
			g();
		changes += gone.length;
		gone.resize(0);
		for (m in moves)
			helder.os.OsThread.post(m);
		for (q in order)
			if (q != null) (cast q : WlPlane).commit();
		if (changes > 0) {
			// (one in flight: the last one presented first, or long enough)
			var t0 = Timer.stamp(), until = t0 + period * 2;
			while (inFlight && Timer.stamp() < until)
				dispatch(Std.int(Math.max(1, (until - Timer.stamp()) * 1000)));
			timing[3] += Timer.stamp() - t0;
			stalled();
			if (broken) return;
			commit();
		}
		frames++;
		timing[0] += Timer.stamp() - began;
		if (single) suspend();
	}

	// (the window's surface committed, the layers' cached state with it, its presentation asked for)
	function commit() {
		inFlight = true;
		if (firstCommit < 0) firstCommit = Timer.stamp();
		// (the next frame's turn: its frame callback, the compositor's time to draw the next)
		answered(frame);
		var cb = parent.frame(), ce = new WlCallbackEvents();
		ce.done = _ -> {
			if (stall) return;
			inFlight = false;
			shownAny = true;
			answered(frame);
		};
		frame = {proxy: cb, listener: cb.listen(ce)};
		// (its presentation: the display's period)
		if (!presentation.isNull()) {
			answered(feedback);
			var fb = presentation.feedback(parent), fe = new WpPresentationFeedbackEvents();
			fe.presented = (sh, sl, ns, refresh, qh, ql, flags) -> {
				if (stall) return;
				shownAny = true;
				if (refresh > 1000000 && refresh < 100000000) period = refresh / 1e9;
				answered(feedback);
			};
			fe.discarded = () -> answered(feedback);
			feedback = {proxy: fb, listener: fb.listen(fe)};
		}
		parent.commit();
		for (s in resync)
			if (!s.sub.isNull()) s.sub.setDesync();
		resync.resize(0);
		WaylandClient.wl_display_flush(display);
	}

	// (a frame callback or presentation feedback let go: answered, or not waited for any more)
	function answered(w:Null<{proxy:Ptr, listener:Int}>) {
		if (w == null) return;
		Proxy.forget(w.listener);
		WaylandClient.wl_proxy_destroy(w.proxy);
		if (w == frame) frame = null;
		if (w == feedback) feedback = null;
	}

	// (our queue's events: what was read, and what the socket has within ms)
	function dispatch(ms:Int) {
		var d = display, q = queue;
		while (WaylandClient.wl_display_prepare_read_queue(d, q) != 0)
			WaylandClient.wl_display_dispatch_queue_pending(d, q);
		WaylandClient.wl_display_flush(d);
		if (WaylandWindow.readable(WaylandClient.wl_display_get_fd(d), ms)) WaylandClient.wl_display_read_events(d) else WaylandClient.wl_display_cancel_read(d);
		WaylandClient.wl_display_dispatch_queue_pending(d, q);
		if (WaylandClient.wl_display_get_error(d) != 0) fail("the Wayland connection broke");
	}

	// (nothing committed ever shown (its frame callback, its presentation)
	// within STALL seconds: a compositor that never shows them. Once one
	// was, a commit not shown is a hidden window's)
	function stalled() {
		if (!shownAny && firstCommit >= 0 && Timer.stamp() - firstCommit > STALL) fail('nothing committed shown in $STALL s');
	}

	// (the window's scale now: the grid, every layer drawn again, split again)
	function rescaled(s:Int) {
		scale120 = s;
		k = s / 120;
		var a = s, b = 120;
		while (b != 0) {
			var c = a % b;
			a = b;
			b = c;
		}
		grid = s / a;
		for (p in all()) {
			p.grid = Std.int(grid);
			p.invalidate();
		}
		split = -1;
	}

	// (a unit's mover whose transform is not a translation, or that fades:
	// a subsurface has neither; its layer drawn as the rest is from now:
	// whether f is split again)
	function unfitted(f:CompositeFrame):Bool {
		var any = false, m = f.heldMoved;
		for (u in units)
			if (u.kind == LayerPlane.MOVER) {
				var q = u.index * 7;
				if (Math.abs(m[q] - 1) > 1e-6 || Math.abs(m[q + 1]) > 1e-6 || Math.abs(m[q + 2]) > 1e-6 || Math.abs(m[q + 3] - 1) > 1e-6
					|| Math.abs(m[q + 6] - 1) > 1e-6) {
					unfit.set(u.key, true);
					any = true;
				}
			}
		if (any) split = -1;
		return any;
	}

	// (where the layers go now, in pixels: a scroller's content's crop by
	// its offset, a mover by its translation sampled, a system layer by its
	// scroller's and its mover's: the changes)
	function geometry(f:CompositeFrame, now:Array<Float>):Int {
		var s = f.scale, n = 0;
		for (q in units) {
			var u:WlPlane = cast q;
			if (u.kind == LayerPlane.SLOT) {
				n += slotAt(f, u, null, now);
				continue;
			}
			if (u.quads.length == 0) continue;
			if (u.kind == LayerPlane.SCROLL) {
				var j = u.index, dx = Math.fround((f.offsets[2 * j] - now[2 * j]) * s), dy = Math.fround((f.offsets[2 * j + 1] - now[2 * j + 1]) * s);
				n += u.crop(u.cx0, u.cy0, u.cx1, u.cy1, u.ox + dx, u.oy + dy);
				for (sp in u.slots)
					n += slotAt(f, cast sp, u, now);
			} else {
				var m = f.heldMoved, j = u.index * 7;
				n += u.crop(-1e9, -1e9, 1e9, 1e9, u.ox + m[j + 4], u.oy + m[j + 5]);
			}
		}
		for (q in order)
			if (q != null && (q.kind == LayerPlane.OVER || q.kind == LayerPlane.BASE) && q.quads.length > 0)
				n += (cast q : WlPlane).crop(-1e9, -1e9, 1e9, 1e9, q.ox, q.oy);
		return n;
	}

	// (system layer p where it is now: at its box as drawn, moved by its
	// scroller's offsets and its mover's change as sampled, cut to its clip
	// (its scroller's, in: the unit it is in) and to the window; square, of
	// no opacity of its own: a subsurface has neither)
	function slotAt(f:CompositeFrame, p:WlPlane, in_:Null<WlPlane>, now:Array<Float>):Int {
		var d = f.slotData, o = p.index * CompositeFrame.SLOT, s = f.scale;
		var fr = Std.int(d[o + 2]), c = Std.int(d[o + 3]), m = Std.int(d[o + 4]);
		var ax = d[o + 6], ay = d[o + 7], bx = d[o + 8], by = d[o + 9], qx = d[o + 10], qy = d[o + 11];
		if (m >= 0) {
			var mv = f.moved, j = m * 7;
			var nax = mv[j] * ax + mv[j + 2] * ay + mv[j + 4], nay = mv[j + 1] * ax + mv[j + 3] * ay + mv[j + 5];
			var nbx = mv[j] * bx + mv[j + 2] * by + mv[j + 4], nqy = mv[j + 1] * qx + mv[j + 3] * qy + mv[j + 5];
			ax = nax;
			ay = nay;
			bx = nbx;
			qy = nqy;
		}
		var dx = fr >= 0 ? Math.fround(f.shift(fr, now, true) * s) : 0.0, dy = fr >= 0 ? Math.fround(f.shift(fr, now, false) * s) : 0.0;
		var cx0 = p.cx0, cy0 = p.cy0, cx1 = p.cx1, cy1 = p.cy1;
		if (in_ != null) {
			cx0 = in_.cx0;
			cy0 = in_.cy0;
			cx1 = in_.cx1;
			cy1 = in_.cy1;
		} else if (c >= 0) {
			var ex = Math.fround(f.shift(c, now, true) * s), ey = Math.fround(f.shift(c, now, false) * s);
			cx0 += ex;
			cy0 += ey;
			cx1 += ex;
			cy1 += ey;
		}
		var w = bx - ax, h = qy - ay;
		if (!(w > 0) || !(h > 0) || !LayerPlane.fine(w) || !LayerPlane.fine(h) || !LayerPlane.fine(ax + dx) || !LayerPlane.fine(ay + dy)) return 0;
		var sl = slotOf(p.slot.handle);
		return sl.place(ax + dx, ay + dy, w, h, Math.max(cx0, 0), Math.max(cy0, 0), Math.min(cx1, f.width), Math.min(cy1, f.height), p.slot.shown);
	}

	// (the layers in their order over the window's surface, a scroller's
	// system layers over its content: whether set again)
	function restack():Int {
		var want:Array<WlSurface> = [];
		for (q in order) {
			var p:WlPlane = cast q;
			if (p == null) continue;
			if (p.kind == LayerPlane.SLOT) {
				var sl = slotOf(p.slot.handle);
				if (!sl.sub.isNull()) want.push(sl.surface);
				continue;
			}
			if (p.sub.isNull() || p.quads.length == 0 && p.kind != LayerPlane.BASE) continue;
			want.push(p.surface);
			for (sp in p.slots) {
				var sl = slotOf(sp.slot.handle);
				if (!sl.sub.isNull()) want.push(sl.surface);
			}
		}
		var same = want.length == shownOrder.length;
		if (same) for (i in 0...want.length)
			if ((want[i] : Ptr) != shownOrder[i]) same = false;
		if (same) return 0;
		var below:WlSurface = window.wlSurface;
		for (w in want) {
			subOf(w).placeAbove(below);
			below = w;
		}
		shownOrder.resize(0);
		for (w in want)
			shownOrder.push(w);
		return 1;
	}

	// (the subsurface of one of the stack's surfaces)
	function subOf(s:WlSurface):WlSubsurface {
		for (p in all())
			if ((cast p : WlPlane).surface == s) return (cast p : WlPlane).sub;
		return slotOf(s).sub;
	}

	// (the record of a node's system layer's surface, made the first time)
	function slotOf(h:Ptr):WlSlot {
		var key = Std.string(h.toI64());
		lock.acquire();
		var s = slotsBy.get(key);
		if (s == null) slotsBy.set(key, s = new WlSlot(this, h));
		lock.release();
		return s;
	}

	// (quads drawn into texture (a dma-buf's own, or the layer's whose
	// pixels are read into into's memory) at buffer b's offset at: all of
	// them over it cleared; cut, only the rectangles that changed, cleared
	// without blending, then what meets them, the rest as it was)
	function draw(r:Replay, f:CompositeFrame, texture:Int, p:WlPlane, b:Buffer, at:Int, cut:Bool, into:Null<WlBuf>):Bool {
		var c = commands, gl = this.gl;
		gl.frameInto(texture);
		c.clear();
		c.begin(Replay.BEGIN_FRAME);
		c.end();
		r.run(c, false);
		c.clear();
		if (!r.began) {
			gl.frameInto(0);
			return false;
		}
		c.begin(Replay.WRITE_BUFFER);
		c.int(b.id());
		c.int(at);
		if (cut) c.bytes(p.cutBytes, 0, p.cutLen) else c.bytes(p.bytes, 0, p.len);
		c.end();
		var bg = f.background, opaque = p.kind == LayerPlane.BASE;
		c.begin(Replay.BEGIN_PASS);
		c.int(1);
		c.int(cast(cut ? LoadOp.Load : LoadOp.Clear));
		CompositeFrame.clearTo(c, opaque ? bg : 0);
		c.int(0);
		c.int(0);
		c.int(Replay.NONE);
		c.int(0);
		c.end();
		three(Replay.SET_VERTEX_BUFFER, 0, f.corners.id(), 0, 3);
		three(Replay.SET_INDEX_BUFFER, f.indices.id(), cast IndexFormat.UInt32, 0, 3);
		three(Replay.SET_TEXTURE, f.atlasSlot, f.atlas.id(), f.sampler.id(), 3);
		var k = 0, runs = cut ? p.cutRuns : p.runs, textures = cut ? p.cutTextures : p.runTextures, from = at;
		if (cut) {
			three(Replay.SET_PIPELINE, f.clearPipeline.id(), -1, -1, 1);
			three(Replay.SET_TEXTURE, f.imageSlot, f.blank.id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), at, 3);
			c.begin(Replay.DRAW_INDEXED);
			c.int(6);
			c.int(p.clears);
			c.int(0);
			c.int(0);
			c.end();
			from += p.clears * CompositeFrame.STRIDE;
		}
		three(Replay.SET_PIPELINE, f.pipeline.id(), -1, -1, 1);
		while (k < runs.length) {
			var t = textures[k >> 1];
			three(Replay.SET_TEXTURE, f.imageSlot, (t == null ? f.blank : t).id(), f.sampler.id(), 3);
			three(Replay.SET_VERTEX_BUFFER, 1, b.id(), from + runs[k] * CompositeFrame.STRIDE, 3);
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
		if (into != null) {
			// (the rectangle it changed, cut's one, else all of it)
			var x0 = 0, y0 = 0, x1 = p.pw, y1 = p.ph;
			if (cut) {
				x0 = Std.int(p.cutBytes.getFloat(8));
				y0 = Std.int(p.cutBytes.getFloat(12));
				x1 = Std.int(p.cutBytes.getFloat(24));
				y1 = Std.int(p.cutBytes.getFloat(44));
			}
			if (x1 > x0 && y1 > y0) {
				gl.readInto(x0, y0, x1 - x0, y1 - y0, into.memory, p.pw * 4);
				if (shmFormat != ABGR8888) into.swap(x0, y0, x1, y1, p.pw);
			}
		}
		gl.frameInto(0);
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

	// (off for good, the window's own frames from the next, which the
	// program is asked for: the layers unmapped with that frame, then let go)
	function fail(why:String) {
		if (broken) return;
		broken = true;
		off = true;
		single = true;
		fell = why;
		redraw = true;
		Sys.println("helder.ui: system layers off: " + why);
		suspend();
	}

	// a wl_surface for a node's LayerSlot (a video's: its owner attaches
	// its buffers and commits them, which show at once; content tells
	// their size), placed, cropped and stacked by the frames (its subsurface
	// and viewport ours); nil where there are no system layers (any thread)
	public function surface():Ptr {
		if (broken) return Ptr.nil();
		var s = compositor.createSurface();
		s.setInputRegion(empty);
		slotOf(s).made = true;
		return s;
	}

	// the size in pixels of the buffers a surface()'s owner attaches (0:
	// one stretched to the slot's box, its crop not needed: a colour's)
	public function content(handle:Ptr, w:Int, h:Int) {
		var s = slotOf(handle);
		lock.acquire();
		s.bufferW = w;
		s.bufferH = h;
		lock.release();
	}

	// a surface() its node no longer has let go, destroyed (a frame after the node lost it)
	public function letGo(handle:Ptr) {
		var key = Std.string(handle.toI64());
		lock.acquire();
		var s = slotsBy.get(key);
		slotsBy.remove(key);
		lock.release();
		if (s != null) device.inOrder(_ -> s.dispose());
	}

	// (a surface() of one colour, 0xRRGGBB: a single-pixel buffer, else one of wl_shm: tests)
	@:noCompletion public function solid(rgb:Int):Ptr {
		var s:WlSurface = surface();
		if (s.isNull()) return s;
		var r = rgb >> 16 & 0xFF, g = rgb >> 8 & 0xFF, b = rgb & 0xFF;
		inline function u32(c:Int):Int
			return c << 24 | c << 16 | c << 8 | c;
		var buffer:WlBuffer = pixel.isNull() ? WlBuf.pixelOf(this, 0xFF000000 | rgb) : pixel.createU32RgbaBuffer(u32(r), u32(g), u32(b), -1);
		slotOf(s).pixel = buffer;
		s.attach(buffer, 0, 0);
		s.commit();
		WaylandClient.wl_display_flush(display);
		return s;
	}

	// (the layers unmapped with the window's next frame, drawn whole when shown again)
	override public function suspend() {
		hide = true;
		for (p in all())
			(cast p : WlPlane).unmap();
		lock.acquire();
		var ss = [for (s in slotsBy) s];
		lock.release();
		for (s in ss)
			s.hide();
		shownOrder.resize(0);
		for (p in all())
			p.invalidate();
	}

	override public function windowShown() {
		priming = false;
		redraw = false;
		primedAt = window.scale120;
		primedW = device.surface.width;
		primedH = device.surface.height;
		if (!hide) return;
		hide = false;
		if (broken && !dropped) drop();
	}

	// (off for good: every layer's surface, buffer and slot let go)
	var dropped = false;

	function drop() {
		dropped = true;
		for (p in all())
			(cast p : WlPlane).free()();
		kept.clear();
		overs.clear();
		gone.resize(0);
		WaylandClient.wl_display_flush(display);
		Sys.println("helder.ui: system layers off: the window's own frame shown, the layers let go");
	}

	override public function dispose() {
		for (p in all())
			(cast p : WlPlane).free()();
		kept.clear();
		overs.clear();
		for (s in [for (s in slotsBy) s])
			s.dispose();
		slotsBy.clear();
		answered(frame);
		answered(feedback);
		empty.destroy();
		for (w in wrappers)
			WaylandClient.wl_proxy_wrapper_destroy(w);
		wrappers.resize(0);
		WaylandClient.wl_display_flush(display);
		// (the queue kept: an event still coming for a proxy of an owner's
		// on a queue destroyed is libwayland's abort)
	}
}

// (a layer as a subsurface: its wl_surface, wl_subsurface and viewport;
// its buffers, the one attached; the plane's own texture, read back into
// a wl_shm buffer's memory; one colour's buffer; what was set)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.WlLayers)
@:access(helder.ui.draw.LayerSplit)
@:access(helder.os.wayland.WaylandWindow)
private class WlPlane extends LayerPlane {
	public var owner:WlLayers;
	public var surface:WlSurface = Ptr.nil();
	public var sub:WlSubsurface = Ptr.nil();
	var view:WpViewport = Ptr.nil();
	final buffers:Array<WlBuf> = [];
	var bufW = 0;
	var bufH = 0;
	public var texture = 0;
	// (the draw its texture holds, -1 none: a wl_shm buffer's draw brings it up to date too)
	public var texAt = -1;
	var shown:Null<WlBuf> = null;
	var mapped = false;
	var dirty = false;
	// (a layer of one colour: its buffer, its colour, its rectangle in its pixels)
	var pixel:WlBuffer = Ptr.nil();
	var color = "";
	var solidNow = false;
	final rect = [0, 0, 0, 0];
	// (position x, y; destination w, h (points); source x, y, w, h (pixels); the base's opaque size)
	final set:Array<Float> = [for (_ in 0...10) -1e300];

	// (its surface, subsurface (synchronized) and viewport, made the first time: whether made now)
	public function make():Bool {
		if (!surface.isNull()) return false;
		var o = owner;
		surface = o.compositor.createSurface();
		surface.setInputRegion(o.empty);
		view = o.viewporter.getViewport(surface);
		sub = o.subcompositor.getSubsurface(surface, o.window.wlSurface);
		for (i in 0...set.length)
			set[i] = -1e300;
		dirty = true;
		return true;
	}

	// (one quad of one colour, square, covering whole points: a single-pixel
	// buffer of it, stretched; false: drawn)
	public function solid():Bool {
		solidNow = false;
		var o = owner, S = CompositeFrame.STRIDE, b = bytes;
		if (o.pixel.isNull() || quads.length != 1) return false;
		// (mode 0, no blur, no corner, no border, unturned, its clip square)
		for (at in [144, 148, 112, 116, 120, 124, 128, 132, 136, 140, 176, 180, 184, 188])
			if (b.getFloat(at) != 0) return false;
		if (b.getFloat(192) == -1e9) return false;
		var cx = b.getFloat(192) + b.getFloat(200), cy = b.getFloat(196) + b.getFloat(204), hw = b.getFloat(64), hh = b.getFloat(68);
		var x0 = Math.max(cx - hw, b.getFloat(160)), y0 = Math.max(cy - hh, b.getFloat(164));
		var x1 = Math.min(cx + hw, b.getFloat(168)), y1 = Math.min(cy + hh, b.getFloat(172));
		var g = grid;
		inline function on(v:Float):Bool
			return Math.abs(v - Math.fround(v)) < 1e-4 && Math.round(v + ox) % g == 0 && Math.round(v + oy) % g == 0;
		if (!(x1 > x0) || !(y1 > y0) || !on(x0) || !on(y0) || !on(x1) || !on(y1)) return false;
		var r = b.getFloat(80), gr = b.getFloat(84), bl = b.getFloat(88), a = b.getFloat(92);
		inline function u32(v:Float):Int {
			var c = Std.int(Math.min(255, Math.max(0, Math.round(v * 255))));
			return c << 24 | c << 16 | c << 8 | c;
		}
		var key = '$r $gr $bl $a';
		if (key != color || pixel.isNull()) {
			if (!pixel.isNull()) pixel.destroy();
			pixel = o.pixel.createU32RgbaBuffer(u32(r), u32(gr), u32(bl), u32(a));
			color = key;
			surface.attach(pixel, 0, 0);
			damageAll();
		} else if (!mapped || shown != null) {
			surface.attach(pixel, 0, 0);
			damageAll();
		}
		shown = null;
		solidNow = mapped = dirty = true;
		rect[0] = Math.round(x0);
		rect[1] = Math.round(y0);
		rect[2] = Math.round(x1);
		rect[3] = Math.round(y1);
		return true;
	}

	function damageAll()
		if (WaylandClient.wl_proxy_get_version(surface) >= 4) surface.damageBuffer(0, 0, 0x7FFFFFFF, 0x7FFFFFFF) else surface.damage(0, 0, 0x7FFFFFFF, 0x7FFFFFFF);

	// (buffer b drawn and attached; cut: only its first rectangles changed)
	public function attach(b:WlBuf, cut:Bool) {
		solidNow = false;
		surface.attach(b.buffer, 0, 0);
		if (cut && WaylandClient.wl_proxy_get_version(surface) >= 4) {
			for (i in 0...clears) {
				var o = i * CompositeFrame.STRIDE;
				var x0 = Std.int(cutBytes.getFloat(o + 8)), y0 = Std.int(cutBytes.getFloat(o + 12));
				surface.damageBuffer(x0, y0, Std.int(cutBytes.getFloat(o + 24)) - x0, Std.int(cutBytes.getFloat(o + 44)) - y0);
			}
		} else
			damageAll();
		b.busy = true;
		shown = b;
		mapped = dirty = true;
	}

	// (nothing to show: its buffer off the surface, kept to show again: whether it was on)
	public function unmap():Bool {
		if (!mapped || surface.isNull()) return false;
		mapped = false;
		surface.attach(Ptr.nil(), 0, 0);
		dirty = true;
		return true;
	}

	// (unchanged, shown again where it was not: the buffer it had, or its colour's)
	public function remap():Bool {
		if (mapped || surface.isNull()) return false;
		if (solidNow && !pixel.isNull()) surface.attach(pixel, 0, 0) else if (shown != null) {
			surface.attach(shown.buffer, 0, 0);
			shown.busy = true;
		} else {
			invalidate();
			return false;
		}
		damageAll();
		mapped = dirty = true;
		return true;
	}

	// (its state cached for the window's commit)
	public function commit() {
		if (!dirty || surface.isNull()) return;
		dirty = false;
		surface.commit();
	}

	// (its content, a buffer at x, y in the frame's pixels (a colour's at its
	// rectangle in it), cut to x0, y0, x1, y1: its subsurface there, on whole
	// points, its viewport's crop and destination; nothing left: unmapped)
	public function crop(x0:Float, y0:Float, x1:Float, y1:Float, x:Float, y:Float):Int {
		if (surface.isNull() || !LayerPlane.fine(x) || !LayerPlane.fine(y)) return 0;
		var g = grid, k = owner.k;
		// (on the grid: a buffer moved (a mover's) to the nearest, its edges inside it)
		var gx = Math.fround(x / g) * g, gy = Math.fround(y / g) * g;
		var bx0 = gx, by0 = gy, bx1 = gx + pw, by1 = gy + ph;
		if (solidNow) {
			bx0 += rect[0];
			by0 += rect[1];
			bx1 = gx + rect[2];
			by1 = gy + rect[3];
		}
		if (kind == LayerPlane.SCROLL) {
			// (a scroll's offset on whole pixels: its edges may not fall on the grid)
			bx0 = x;
			by0 = y;
			bx1 = x + (solidNow ? rect[2] : pw);
			by1 = y + (solidNow ? rect[3] : ph);
			if (solidNow) {
				bx0 += rect[0];
				by0 += rect[1];
			}
		}
		var vx0 = Math.max(x0, Math.fceil(bx0 / g) * g), vy0 = Math.max(y0, Math.fceil(by0 / g) * g);
		var vx1 = Math.min(x1, Math.ffloor(bx1 / g) * g), vy1 = Math.min(y1, Math.ffloor(by1 / g) * g);
		if (vx1 <= vx0 || vy1 <= vy0) return unmap() ? 1 : 0;
		var n = mapped ? 0 : (remap() ? 1 : 0);
		var px = Math.round(vx0 / k), py = Math.round(vy0 / k), dw = Math.round((vx1 - vx0) / k), dh = Math.round((vy1 - vy0) / k);
		if (set[0] != px || set[1] != py) {
			set[0] = px;
			set[1] = py;
			sub.setPosition(px, py);
			n++;
		}
		if (set[2] != dw || set[3] != dh) {
			set[2] = dw;
			set[3] = dh;
			view.setDestination(dw < 1 ? 1 : dw, dh < 1 ? 1 : dh);
			dirty = true;
			n++;
		}
		// (a buffer's part shown: the source, in its pixels; a colour's: none, the whole pixel stretched)
		var sx = solidNow ? -1.0 : vx0 - bx0, sy = solidNow ? -1.0 : vy0 - by0, sw = solidNow ? -1.0 : vx1 - vx0, sh = solidNow ? -1.0 : vy1 - vy0;
		if (!solidNow && sx == 0 && sy == 0 && sw == pw && sh == ph) sx = sy = sw = sh = -1;
		if (set[4] != sx || set[5] != sy || set[6] != sw || set[7] != sh) {
			set[4] = sx;
			set[5] = sy;
			set[6] = sw;
			set[7] = sh;
			view.setSource(sx, sy, sw, sh);
			dirty = true;
			n++;
		}
		if (kind == LayerPlane.BASE && (set[8] != dw || set[9] != dh)) {
			set[8] = dw;
			set[9] = dh;
			var r = owner.compositor.createRegion();
			if (owner.opaque) r.add(0, 0, dw, dh);
			surface.setOpaqueRegion(r);
			r.destroy();
			dirty = true;
		}
		return n;
	}

	// (its buffer's size: what it has while its quads fit and fill half of it)
	override public function fit() {
		super.fit();
		if (kind == LayerPlane.BASE || quads.length == 0) return;
		if (bufW >= pw && bufH >= ph && bufW * bufH <= 2 * pw * ph && bufW % grid == 0 && bufH % grid == 0) {
			pw = bufW;
			ph = bufH;
		}
	}

	// (a buffer to draw into: of its size now (those of another let go), one
	// the compositor let go of, else a new one, up to two (one shown, one
	// drawn: the last commit is presented before the next), three for a
	// small one; null while none is let go within a display period: drawn
	// next frame. Off once one waited 1.5 s, or none could be made)
	public function next():Null<WlBuf> {
		var o = owner, gl = o.gl;
		if (pw != bufW || ph != bufH) {
			for (b in buffers)
				b.free(gl);
			buffers.resize(0);
			if (texture != 0) gl.destroyTexture(texture);
			texture = 0;
			shown = null;
			bufW = pw;
			bufH = ph;
		}
		var t0 = Timer.stamp(), until = t0 + o.period;
		while (true) {
			for (b in buffers)
				if (!b.busy) {
					waiting = -1;
					o.timing[2] += Timer.stamp() - t0;
					return b;
				}
			if (buffers.length < (pw * ph * 4 <= o.device.width * o.device.height ? 3 : 2)) {
				var b = WlBuf.make(o, gl, pw, ph);
				if (b == null) {
					o.fail('no buffer of $pw x $ph');
					return null;
				}
				if (b.texture == 0 && texture == 0) {
					texture = gl.createTexture({width: pw, height: ph, renderTarget: true});
					texAt = -1;
				}
				buffers.push(b);
				waiting = -1;
				return b;
			}
			if (Timer.stamp() > until) break;
			o.dispatch(1);
		}
		var t = Timer.stamp();
		o.timing[2] += t - t0;
		if (waiting < 0) waiting = t0 else if (t - waiting > 1.5) o.fail("buffers never released");
		return null;
	}

	var waiting = -1.0;

	public function memory():Float
		return (buffers.length + (texture != 0 ? 1 : 0)) * bufW * bufH * 4.0;

	override public function free():Void->Void {
		var o = owner, s = surface, u = sub, v = view, bs = buffers.copy(), t = texture, px = pixel;
		var sl = kind == LayerPlane.SLOT && slot != null ? o.slotOf(slot.handle) : null;
		surface = Ptr.nil();
		sub = Ptr.nil();
		view = Ptr.nil();
		pixel = Ptr.nil();
		buffers.resize(0);
		texture = 0;
		shown = null;
		mapped = false;
		return () -> {
			// (a node's system layer no longer in the frame: out of the stack, its surface its owner's)
			if (sl != null) sl.hide();
			if (!u.isNull()) u.destroy();
			if (!v.isNull()) v.destroy();
			if (!s.isNull()) s.destroy();
			if (!px.isNull()) px.destroy();
			for (b in bs)
				b.free(o.gl);
			if (t != 0 && o.gl != null) o.gl.destroyTexture(t);
		}
	}
}

// (a buffer of a layer's: a wl_buffer of a dma-buf of its own texture, or
// of wl_shm memory the layer's texture is read into; whether the
// compositor holds it; the draw of its layer it holds)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.WlLayers)
@:access(helder.os.wayland.WaylandWindow)
private class WlBuf {
	public var buffer:WlBuffer = Ptr.nil();
	public var texture = 0;
	public var memory = Ptr.nil();
	var size = 0;
	var listener = 0;
	public var busy = false;
	public var at = -1;

	function new() {}

	public static function make(o:WlLayers, gl:GLBackend, w:Int, h:Int):Null<WlBuf> {
		var b = o.dmabufs ? dmabuf(o, gl, w, h) : null;
		if (b == null) b = shm(o, w, h);
		if (b == null) return null;
		var e = new WlBufferEvents();
		e.release = () -> b.busy = false;
		b.listener = b.buffer.listen(e);
		return b;
	}

	// (a texture exported as a dma-buf, given to the compositor: null where
	// it does not take it, dma-bufs not tried again)
	static function dmabuf(o:WlLayers, gl:GLBackend, w:Int, h:Int):Null<WlBuf> {
		var s = gl.createShared(w, h);
		if (s == null) {
			o.dmabufs = false;
			return null;
		}
		// ("dmabuf:pid:fd:fourcc:stride:offset:modifier hi:modifier lo")
		var f = [for (x in s.handle.split(":").slice(1)) Std.parseInt(x) ?? 0];
		var got:WlBuffer = Ptr.nil(), answered = false;
		if (WaylandWindow.dmabufFormats.contains('${f[2]}:${f[5]}:${f[6]}')) {
			var params = o.dmabuf.createParams(), e = new ZwpLinuxBufferParamsV1Events();
			e.created = b -> {
				got = b;
				answered = true;
			};
			e.failed = () -> answered = true;
			var l = params.listen(e);
			params.add(f[1], 0, f[4], f[3], f[5], f[6]);
			params.create(w, h, f[2], 0);
			var until = Timer.stamp() + 0.5;
			while (!answered && Timer.stamp() < until)
				o.dispatch(5);
			Proxy.forget(l);
			params.destroy();
		}
		if (got.isNull()) {
			Sys.println('helder.ui: Wayland layers: the compositor took no dma-buf (fourcc ${StringTools.hex(f[2], 8)}, modifier ${f[5]}:${f[6]}): wl_shm');
			gl.destroyTexture(s.id);
			o.dmabufs = false;
			return null;
		}
		var b = new WlBuf();
		b.buffer = got;
		b.texture = s.id;
		o.dmabufTotal++;
		return b;
	}

	// (w x h pixels of wl_shm memory, mapped: the layer's texture read into it)
	static function shm(o:WlLayers, w:Int, h:Int):Null<WlBuf> {
		var stride = w * 4, size = stride * h;
		var fd = WlLibc.memfd_create(Mem.cstr("helder-layer"), 1); // MFD_CLOEXEC
		if (fd < 0) return null;
		if (WlLibc.ftruncate(fd, size) != 0) {
			Posix.close(fd);
			return null;
		}
		var m = WlLibc.mmap(Ptr.nil(), size, 3, 1, fd, 0); // PROT_READ|WRITE, MAP_SHARED
		if (m.toI64() == -1) {
			Posix.close(fd);
			return null;
		}
		var pool = o.shm.createPool(fd, size);
		var b = new WlBuf();
		b.buffer = pool.createBuffer(0, w, h, stride, o.shmFormat);
		pool.destroy();
		Posix.close(fd);
		b.memory = m;
		b.size = size;
		o.shmTotal++;
		return b;
	}

	// (one pixel of wl_shm, 0xAARRGGBB: a colour where there are no single-pixel buffers)
	public static function pixelOf(o:WlLayers, argb:Int):WlBuffer {
		var b = shm(o, 1, 1);
		if (b == null) return Ptr.nil();
		var p:Ptr<Int32> = cast b.memory;
		p[0] = o.shmFormat == WlLayers.ABGR8888 ? (argb & 0xFF00FF00) | (argb >> 16 & 0xFF) | (argb & 0xFF) << 16 : argb;
		return b.buffer;
	}

	// (RGBA's bytes as ARGB8888's, x0, y0 to x1, y1 of rows w wide: wl_shm's one format every compositor has)
	public function swap(x0:Int, y0:Int, x1:Int, y1:Int, w:Int) {
		var p:Ptr<Int32> = cast memory;
		for (y in y0...y1)
			for (x in x0...x1) {
				var i = y * w + x, v = p[i];
				p[i] = (v & 0xFF00FF00) | (v >> 16 & 0xFF) | (v & 0xFF) << 16;
			}
	}

	public function free(gl:Null<GLBackend>) {
		Proxy.forget(listener);
		if (!buffer.isNull()) buffer.destroy();
		buffer = Ptr.nil();
		if (!memory.isNull()) WlLibc.munmap(memory, size);
		memory = Ptr.nil();
		if (texture != 0 && gl != null) gl.destroyTexture(texture);
		texture = 0;
	}
}

// (a node's system layer's surface: its owner's buffers and their size;
// its viewport, ours, made once (a surface has one); its subsurface while
// it shows (none: hidden, a surface of no role shows nothing); what was set)
@:hxmc.unsafe(gc)
@:access(helder.ui.draw.WlLayers)
@:access(helder.ui.draw.LayerSplit)
@:access(helder.os.wayland.WaylandWindow)
private class WlSlot {
	final owner:WlLayers;
	public final surface:WlSurface;
	public var sub:WlSubsurface = Ptr.nil();
	var view:WpViewport = Ptr.nil();
	public var bufferW = 0;
	public var bufferH = 0;
	// (made by surface(), destroyed with it; solid()'s buffer)
	public var made = false;
	public var pixel:WlBuffer = Ptr.nil();
	final set:Array<Float> = [for (_ in 0...8) -1e300];

	public function new(owner:WlLayers, surface:WlSurface) {
		this.owner = owner;
		this.surface = surface;
	}

	// (at x, y, w x h in the frame's pixels, cut to x0, y0, x1, y1: its
	// subsurface there (made, synchronized for this frame's commit), its
	// viewport's crop of its buffer; nothing left or not shown: hidden)
	public function place(x:Float, y:Float, w:Float, h:Float, x0:Float, y0:Float, x1:Float, y1:Float, on:Bool):Int {
		var o = owner, k = o.k;
		var vx0 = Math.max(x0, x), vy0 = Math.max(y0, y), vx1 = Math.min(x1, x + w), vy1 = Math.min(y1, y + h);
		var px = Math.round(vx0 / k), py = Math.round(vy0 / k), dw = Math.round(vx1 / k) - px, dh = Math.round(vy1 / k) - py;
		if (!on || dw < 1 || dh < 1) return hide() ? 1 : 0;
		var n = 0;
		if (view.isNull()) view = o.viewporter.getViewport(surface);
		if (sub.isNull()) {
			sub = o.subcompositor.getSubsurface(surface, o.window.wlSurface);
			for (i in 0...set.length)
				set[i] = -1e300;
			o.shownOrder.resize(0);
			n++;
		}
		var changed = false;
		if (set[0] != px || set[1] != py) {
			set[0] = px;
			set[1] = py;
			sub.setPosition(px, py);
			n++;
		}
		o.lock.acquire();
		var bw = bufferW, bh = bufferH;
		o.lock.release();
		var sx = -1.0, sy = -1.0, sw = -1.0, sh = -1.0;
		if (bw > 0 && bh > 0) {
			// (the part of its buffer the box's part shown is, the buffer stretched over the box)
			sx = Math.max(0, (px * k - x) / w * bw);
			sy = Math.max(0, (py * k - y) / h * bh);
			sw = Math.min(bw - sx, dw * k / w * bw);
			sh = Math.min(bh - sy, dh * k / h * bh);
			if (sx == 0 && sy == 0 && sw == bw && sh == bh) sx = sy = sw = sh = -1;
		}
		if (set[2] != dw || set[3] != dh || set[4] != sx || set[5] != sy || set[6] != sw || set[7] != sh) {
			set[2] = dw;
			set[3] = dh;
			set[4] = sx;
			set[5] = sy;
			set[6] = sw;
			set[7] = sh;
			view.setDestination(dw, dh);
			view.setSource(sx, sy, sw, sh);
			changed = true;
			n++;
		}
		if (changed) {
			// (its own state with the window's commit: synchronized for it, desynchronized after)
			sub.setSync();
			surface.commit();
			o.resync.push(this);
		}
		return n;
	}

	// (out of the stack at once (a subsurface's destroy unmaps it), its owner's buffer kept: whether it showed)
	public function hide():Bool {
		if (sub.isNull()) return false;
		sub.destroy();
		sub = Ptr.nil();
		owner.shownOrder.resize(0);
		return true;
	}

	public function dispose() {
		hide();
		if (!view.isNull()) view.destroy();
		view = Ptr.nil();
		if (made) surface.destroy();
		made = false;
		if (!pixel.isNull()) pixel.destroy();
		pixel = Ptr.nil();
	}
}
#end
