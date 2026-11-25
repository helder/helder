package helder.ui;

import helder.os.Mods;
import helder.os.ScrollPhase;
import helder.ui.gesture.TouchScroll;

// The compositor's copy of the program's scrollers (Layers' step 4b): what
// the program's last frame had of them (ScrollShot), as nodes of its own on
// which the program's own physics run (ScrollHost: Trackpad, Stretch,
// TouchScroll, ScrollGlide), moved by the input the main thread hands it as
// it reads it (input) and ticked each vsync (step), so that scrolling keeps
// the display's pace while the program is busy.
//
// A gesture is the compositor's or the program's from its first step. One
// whose first step lands under a node that may claim it (ScrollShot's
// gate: a slider, a canvas, a pointer, wheel or gesture handler) asks the
// program and waits (Ladybird's WheelEventListenerGate): let through, the
// compositor runs it from its start, and the rest of it never asks; kept,
// it is the program's. Each event the program then takes is marked
// (Event.routed: the compositor's, a question, waiting on one), so that it
// does what it does with it but the scroll. The offsets go back to it
// after the fact (drain), its next frame drawn from them; an offset it set
// itself (scrollTo, a layout clamping it) wins over the compositor's.
//
// Not thread safe by itself: the compositor calls it under its lock; a
// test calls it in turn with an injected clock (step's time).
@:allow(helder.ui)
@:access(helder.ui.Scrolling)
@:access(helder.ui.Trackpad)
@:access(helder.ui.gesture.Gesture)
@:access(helder.ui.gesture.TouchScroll)
class ScrollMirror extends ScrollHost {
	// what an event is to the program (Event.routed)
	public static inline var PROGRAM = 0;
	public static inline var TAKEN = 1;
	public static inline var ASK = 2;
	public static inline var PENDING = 3;

	// the window's points to its pixels and size, as the program's last frame had them
	public var scale(default, null) = 1.0;
	public var width(default, null) = 0.0;
	public var height(default, null) = 0.0;
	// whether anything moves (a glide, a spring, a fling): steps go on
	public var moving(get, never):Bool;
	// a trace of the input it took (tests: what came, what it was routed to)
	public var onInput:Null<(i:ScrollInput, route:Int) -> Void> = null;

	final byNode = new haxe.ds.ObjectMap<Node, MirrorNode>();
	final order:Array<MirrorNode> = [];
	final steps:Array<Float->Bool> = [];
	final touch:TouchScroll;
	var time = 0.0;
	var keys = -1;
	var focus:Null<MirrorNode> = null;
	var focusNone = false;
	var adopted = 0;
	var frames = false;
	// the inputs for the next step, in order; kept for reuse
	final queue:Array<ScrollInput> = [];
	final pool:Array<ScrollInput> = [];
	// the gestures: the wheel's, a trackpad's, the first finger's, a thumb's drag
	var ids = 0;
	final wheel = new Gate();
	final pad = new Gate();
	final finger = new Gate();
	var fingerId = -1;
	var lastWheel = -1e9;
	var pointerX = 0.0;
	var pointerY = 0.0;
	var drag:Null<MirrorNode> = null;
	var dragX = false;
	var dragFrom = 0.0;
	var dragScroll = 0.0;
	var dragging = false;

	public function new() {
		super();
		touch = @:privateAccess new TouchScroll(this);
	}

	function get_moving():Bool
		return steps.length > 0 || touch.gliding || queue.length > 0;

	override function clock():Float
		return time;

	override function animate(step:Float->Bool)
		steps.push(step);

	override public function requestFrame()
		frames = true;

	override function has(n:Node):Bool
		return Std.isOfType(n, MirrorNode) && (cast n : MirrorNode).alive == adopted;

	// the topmost node under a point (the window's points): the last entry
	// whose box, clip and scrollers around it hold it, each in its content's
	// coordinates at the mirror's offsets
	override function hit(x:Float, y:Float):Null<Node> {
		var i = order.length;
		while (--i >= 0) {
			var m = order[i];
			if (inside(m, x, y)) return m.kind == ScrollShot.COVER && m.scroller == null ? null : m;
		}
		return null;
	}

	function inside(m:MirrorNode, x:Float, y:Float):Bool {
		var s = m.scroller, ox = 0.0, oy = 0.0;
		while (s != null) {
			ox += s.scrollX;
			oy += s.scrollY;
			s = s.scroller;
		}
		var px = x + ox, py = y + oy;
		if (px < m.bx || py < m.by || px >= m.bx + m.bw || py >= m.by + m.bh) return false;
		if (px < m.cx0 || py < m.cy0 || px >= m.cx1 || py >= m.cy1) return false;
		// (within each scroller's view around it, in that one's own coordinates)
		var a = m.scroller;
		while (a != null) {
			px -= a.scrollX;
			py -= a.scrollY;
			if (px < a.vx || py < a.vy || px >= a.vx + a.vw || py >= a.vy + a.vh) return false;
			if (px < a.cx0 || py < a.cy0 || px >= a.cx1 || py >= a.cy1) return false;
			a = a.scroller;
		}
		return true;
	}

	// ---- the program's last frame

	// what the program's frame had (taken on its thread: ScrollShot.take)
	public function adopt(shot:ScrollShot) {
		adopted++;
		scale = shot.scale;
		width = shot.width;
		height = shot.height;
		elastic = shot.elastic;
		kinetic = shot.kinetic;
		stretch = shot.stretch;
		scrollDuration = shot.scrollDuration;
		keys = shot.keys;
		order.resize(0);
		for (i in 0...shot.count) {
			var e = shot.entries[i], n = e.node;
			if (n == null) continue;
			// (a scroller again, or for the first time: the program's offsets taken)
			var m = byNode.get(n), fresh = m == null || e.kind == ScrollShot.SCROLLER && m.kind != ScrollShot.SCROLLER;
			if (m == null) {
				m = new MirrorNode(n);
				byNode.set(n, m);
			} else if (m.kind == ScrollShot.SCROLLER && e.kind != ScrollShot.SCROLLER) letGo(m);
			m.alive = adopted;
			m.kind = e.kind;
			m.async = e.async;
			m.bx = e.x;
			m.by = e.y;
			m.bw = e.w;
			m.bh = e.h;
			m.cx0 = e.cx0;
			m.cy0 = e.cy0;
			m.cx1 = e.cx1;
			m.cy1 = e.cy1;
			m.scroller = e.up >= 0 ? order[e.up] : null;
			m.outer = e.outer >= 0 ? order[e.outer] : null;
			m.claims = e.claims | (m.outer != null ? m.outer.claims : 0);
			@:privateAccess m.parent = m.scroller;
			order.push(m);
			if (e.kind != ScrollShot.SCROLLER) continue;
			m.vx = e.vx;
			m.vy = e.vy;
			m.vw = e.vw;
			m.vh = e.vh;
			m.shape(e);
			for (k in 0...14)
				m.bars[k] = e.bars[k];
			// (the program's own offset, or the first: taken; else the compositor's, back within the range unless held past it)
			if (e.own || fresh) {
				if (!fresh && (m.scrollX != e.scrollX || m.scrollY != e.scrollY)) halt(m);
				m.scrollX = m.sentX = e.scrollX;
				m.scrollY = m.sentY = e.scrollY;
			} else if (!trackpad.holds(m) && @:privateAccess stretcher.node != m) Scrolling.clamp(m);
		}
		// (the scrollers gone: let go)
		var gone = [for (n => m in byNode) if (m.alive != adopted) n];
		for (n in gone) {
			var m = byNode.get(n);
			byNode.remove(n);
			if (m.kind == ScrollShot.SCROLLER) letGo(m) else halt(m);
			if (wheelLatch == m) wheelLatch = null;
			if (drag == m) drag = null;
		}
		focus = shot.focus >= 0 ? order[shot.focus] : null;
		focusNone = shot.focus == -2;
	}

	// (a scroller no more (gone, or a range gone: a gate or a cover, which
	// the shot gives no offsets): its motion stopped, the program told it is
	// let go if it was held or moving (Ui.mirrored: back within its range),
	// its offsets the program's from then on. Its last offsets kept, a
	// folder that fits after one scrolled was drawn at that one's by the
	// compositor's frames, not the program's)
	function letGo(m:MirrorNode) {
		halt(m);
		if (m.sentHeld || m.sentMoving) released.push(m);
		m.sentHeld = m.sentMoving = false;
	}

	// (the scrollers let go while held or moving, for the next drain)
	final released:Array<MirrorNode> = [];

	// (n's own motion stopped: the program moved it, or it left)
	function halt(m:MirrorNode) {
		if (trackpad.node == m) trackpad.reset();
		if (@:privateAccess stretcher.node == m) @:privateAccess stretcher.reset();
		var g = glides.get(m);
		if (g != null) {
			g.stop();
			glides.remove(m);
		}
	}

	// ---- input

	// an input, as the main thread reads it (ScrollInput: UiEvents.route
	// fills one from a window's event): queued for the next step when it is
	// the compositor's; what it is to the program (PROGRAM, TAKEN, ASK,
	// PENDING), its gesture in i.gesture. The mirror keeps i.
	public function input(i:ScrollInput):Int {
		var r = route(i);
		if (onInput != null) onInput(i, r);
		return r;
	}

	// a fresh input to fill (input takes it)
	public function event(kind:ScrollInput.ScrollInputKind):ScrollInput
		return take(kind, 0, 0);

	function route(i:ScrollInput):Int {
		i.gesture = 0;
		switch i.kind {
			case Wheel:
				var phased = (elastic || kinetic) && (i.phase != 0 || i.momentum != 0) && i.mods & Mods.CONTROL == 0;
				i.time = phased ? eventTime(i.time) : -1;
				if (phased) {
					// (a gesture: from its Began, or a move without one, until the next)
					if (i.phase == ScrollPhase.Began || i.phase == ScrollPhase.Changed && pad.state == Gate.NONE) open(pad, i.x, i.y, ScrollShot.WHEEL);
					return pass(pad, i, i.dx != 0 || i.dy != 0 || i.phase == ScrollPhase.Ended || i.phase == ScrollPhase.Cancelled
						|| i.momentum == ScrollPhase.Ended);
				}
				// (a wheel's: its notches until it rests half a second, as its latch)
				var now = Ui.now();
				if (wheel.state == Gate.NONE || now - lastWheel >= ScrollHost.WHEEL_LATCH) open(wheel, i.x, i.y, ScrollShot.WHEEL);
				lastWheel = now;
				return pass(wheel, i, true);
			case Down:
				i.time = eventTime(i.time);
				// (a new touch stops a glide, whoever's it is; the first finger's may scroll)
				if (fingerId < 0) {
					fingerId = i.id;
					open(finger, i.x, i.y, ScrollShot.DRAG);
					return pass(finger, i, true);
				}
				i.stopOnly = true;
				queue.push(i);
				return PROGRAM;
			case Move | Up | Cancel:
				if (i.id != fingerId) {
					pool.push(i);
					return PROGRAM;
				}
				i.time = eventTime(i.time);
				if (i.kind != Move) fingerId = -1;
				var r = pass(finger, i, false);
				if (i.kind != Move) finger.done();
				return r;
			case MouseDown:
				pointerX = i.x;
				pointerY = i.y;
				if (i.key != 1 || dragging || thumbAt(i.x, i.y) == null) {
					pool.push(i);
					return PROGRAM;
				}
				dragging = true;
				i.kind = Press;
				queue.push(i);
				return TAKEN;
			case MouseMove:
				pointerX = i.x;
				pointerY = i.y;
				if (!dragging) {
					pool.push(i);
					return PROGRAM;
				}
				i.kind = Drag;
				queue.push(i);
				return TAKEN;
			case MouseUp:
				pointerX = i.x;
				pointerY = i.y;
				if (!dragging || i.key != 1) {
					pool.push(i);
					return PROGRAM;
				}
				dragging = false;
				i.kind = Release;
				queue.push(i);
				return TAKEN;
			case Key:
				var bit = ScrollShot.keyBit(i.key, i.mods);
				var from:Null<Node> = focus != null ? focus : focusNone ? null : hit(pointerX, pointerY);
				if (bit == 0 || keys == -1 || keys & bit != 0 || from == null || !keyScrolls(from, i.key, i.mods)) {
					pool.push(i);
					return PROGRAM;
				}
				i.node = from;
				queue.push(i);
				return TAKEN;
			case _:
				pool.push(i);
				return PROGRAM;
		}
	}

	// (a gesture beginning at x, y: the compositor's where a scroller it may
	// scroll is under it, a question where a node there may claim it, else the program's)
	function open(g:Gate, x:Float, y:Float, claim:Int) {
		for (i in g.waiting)
			pool.push(i);
		g.waiting.resize(0);
		g.id = ++ids;
		g.asked = false;
		var m:Null<MirrorNode> = cast hit(x, y);
		if (m == null) {
			g.state = Gate.PROGRAM;
			return;
		}
		var s = m.kind == ScrollShot.SCROLLER ? m : m.scroller, any = false;
		while (s != null) {
			if (!s.async) {
				g.state = Gate.PROGRAM;
				return;
			}
			any = true;
			s = s.scroller;
		}
		g.state = !any ? Gate.PROGRAM : m.claims & claim != 0 ? Gate.ASKING : Gate.FREE;
	}

	// (an input of g's: queued, held while g asks (the first that tells, the
	// question), or left to the program)
	function pass(g:Gate, i:ScrollInput, tells:Bool):Int {
		i.gesture = g.id;
		switch g.state {
			case Gate.FREE:
				queue.push(i);
				return TAKEN;
			case Gate.ASKING:
				g.waiting.push(i);
				if (!g.asked && tells) {
					g.asked = true;
					return ASK;
				}
				return PENDING;
			case _:
				// (the program's touch: the compositor's glide stopped by it still)
				if (i.kind == Down) {
					i.stopOnly = true;
					queue.push(i);
				} else
					pool.push(i);
				return g.state == Gate.PROGRAM ? PROGRAM : PENDING;
		}
	}

	// the program's answer to gesture id's question: let through (the
	// compositor runs it from its start) or kept (the program's)
	public function answer(id:Int, through:Bool) {
		for (g in [wheel, pad, finger])
			if (g.id == id && g.state == Gate.ASKING) {
				g.state = through ? Gate.FREE : Gate.PROGRAM;
				for (i in g.waiting)
					if (through) queue.push(i) else pool.push(i);
				g.waiting.resize(0);
			}
	}

	function take(kind:ScrollInput.ScrollInputKind, x:Float, y:Float):ScrollInput {
		var i = pool.length > 0 ? pool.pop() : new ScrollInput();
		i.kind = kind;
		i.x = x;
		i.y = y;
		i.dx = i.dy = 0;
		i.eased = i.stopOnly = false;
		i.mods = i.phase = i.momentum = i.key = i.gesture = 0;
		i.id = -1;
		i.time = 0;
		i.node = null;
		return i;
	}

	// (whether the keys would scroll from n, as Scrolling.keyScroll)
	function keyScrolls(n:Node, key:Int, mods:Int):Bool {
		var x = key == Key.LEFT || key == Key.RIGHT;
		var back = key == Key.UP || key == Key.LEFT || key == Key.PAGE_UP || key == Key.HOME || key == Key.SPACE && mods & Mods.SHIFT != 0;
		var p:Null<Node> = n;
		while (p != null) {
			if (p.style.overflow == Scroll && Scrolling.canScroll(p, back ? -1 : 1, x)) return true;
			p = p.parent;
		}
		return false;
	}

	// (the scroller whose thumb or track is under x, y, its axis in dragX)
	function thumbAt(x:Float, y:Float):Null<MirrorNode> {
		var i = order.length;
		while (--i >= 0) {
			var m = order[i];
			if (m.kind != ScrollShot.SCROLLER || !inside(m, x, y)) continue;
			for (k in 0...2) {
				var b = m.bars, o = k * 7;
				if (b[o] == 0) continue;
				var s = m.scroller, ox = 0.0, oy = 0.0;
				while (s != null) {
					ox += s.scrollX;
					oy += s.scrollY;
					s = s.scroller;
				}
				var along = k == 0 ? x + ox : y + oy, across = k == 0 ? y + oy : x + ox, inset = b[o + 5];
				if (across < b[o + 3] - inset || across > b[o + 3] + b[o + 4] + inset || along < b[o + 1] || along > b[o + 1] + b[o + 2]) continue;
				dragX = k == 0;
				return m;
			}
		}
		return null;
	}

	// ---- the frames

	// a vsync at time t (Ui.now's clock): the inputs since the last run, in
	// their order, then the glides and springs ticked, then a touch's glide
	// (as the program's turn: its events, Clock.tick, Ui.update); whether
	// anything moves still
	public function step(t:Float):Bool {
		time = t;
		frames = false;
		var i = 0;
		while (i < queue.length)
			run(queue[i++]);
		for (x in queue)
			pool.push(x);
		queue.resize(0);
		var k = 0;
		while (k < steps.length)
			if (steps[k](t)) k++ else steps.splice(k, 1);
		if (touch.gliding) touch.glide(t * 1000);
		return moving;
	}

	function run(i:ScrollInput) {
		switch i.kind {
			case Wheel:
				wheelNow(i.x, i.y, i.dx, i.dy, i.eased, i.mods, i.phase, i.momentum, i.time >= 0 ? i.time : time);
			case Down:
				touch.stop();
				if (i.stopOnly) return;
				if (touch.join(i.id, helder.os.PointerType.Touch, 1)) touch.down(i.id, i.x, i.y, i.time);
			case Move:
				touch.move(i.id, i.x, i.y, i.time);
			case Up | Cancel:
				touch.up(i.id, i.time, i.kind == Cancel);
			case Press:
				var m = thumbAt(i.x, i.y);
				if (m == null) return;
				var b = m.bars, o = dragX ? 0 : 7, along = dragX ? i.x : i.y;
				var s = m.scroller;
				while (s != null) {
					along += dragX ? s.scrollX : s.scrollY;
					s = s.scroller;
				}
				var start = thumbStart(m, dragX), len = b[o + 6];
				if (along >= start && along <= start + len) {
					drag = m;
					dragFrom = dragX ? i.x : i.y;
					dragScroll = dragX ? m.scrollX : m.scrollY;
				} else {
					var page = Scrolling.viewSize(m, dragX) * (along < start ? -1 : 1);
					Scrolling.setScroll(this, m, dragX, (dragX ? m.scrollX : m.scrollY) + page);
				}
			case Drag:
				var m = drag;
				if (m == null) return;
				var b = m.bars, o = dragX ? 0 : 7, track = b[o + 2], len = b[o + 6], max = Scrolling.maxScroll(m, dragX);
				Scrolling.setScroll(this, m, dragX, dragScroll + ((dragX ? i.x : i.y) - dragFrom) * (track > len ? max / (track - len) : 0));
			case Release:
				drag = null;
			case Key:
				Scrolling.keyScrollFrom(this, i.node, i.key, i.mods);
			case MouseDown | MouseMove | MouseUp:
		}
	}

	// (an event's own time (ms, the system's clock) on Ui.now's clock, as Ui.eventTime has it)
	var eventLag = 0.0;

	function eventTime(ms:Float):Float {
		if (ms <= 0) return Ui.now();
		var lag = Ui.now() - ms / 1000;
		if (Math.abs(lag - eventLag) > 1 || (lag < eventLag && fingerId < 0)) eventLag = lag;
		return ms / 1000 + eventLag;
	}

	// (where m's thumb starts along its axis: Scrolling.thumb's, unstretched)
	static function thumbStart(m:MirrorNode, x:Bool):Float {
		var b = m.bars, o = x ? 0 : 7, max = Scrolling.maxScroll(m, x);
		var f = max > 0 ? ((x ? m.scrollX : m.scrollY) - Scrolling.scrollStart(m, x)) / max : 0;
		return b[o + 1] + (b[o + 2] - b[o + 6]) * Math.max(0, Math.min(1, f));
	}

	// ---- back to the program

	// the offsets moved since the last drain, each to f (the program's node,
	// its offsets, whether a gesture holds it past its ends, whether it still moves)
	public function drain(f:(n:Node, x:Float, y:Float, held:Bool, moving:Bool) -> Void) {
		// (let go: held no more, where the program has it)
		for (m in released)
			f(m.real, m.real.scrollX, m.real.scrollY, false, false);
		released.resize(0);
		for (m in order) {
			if (m.kind != ScrollShot.SCROLLER) continue;
			var moves = trackpad.holds(m) || glides.exists(m) && glides.get(m).gliding || touch.gliding && wheelNode == m;
			if (m.scrollX == m.sentX && m.scrollY == m.sentY && moves == m.sentMoving) continue;
			m.sentX = m.scrollX;
			m.sentY = m.scrollY;
			m.sentMoving = moves;
			m.sentHeld = trackpad.holds(m);
			f(m.real, m.scrollX, m.scrollY, m.sentHeld, moves);
		}
	}

	// n placed at x, y by the platform's own scroll view (iOS's: IosScroll),
	// its physics not the mirror's: as if sent, the program told by the view
	public function place(n:Node, x:Float, y:Float) {
		var m = byNode.get(n);
		if (m == null) return;
		m.scrollX = m.sentX = x;
		m.scrollY = m.sentY = y;
	}

	// the mirror's offsets of the program's node n (null: none, or no scroller of its)
	public function offsets(n:Node):Null<{x:Float, y:Float}> {
		var m = byNode.get(n);
		return m == null || m.kind != ScrollShot.SCROLLER ? null : {x: m.scrollX, y: m.scrollY};
	}

	// the scrollers, in paint order, with their offsets now (the compositor's frame)
	public function each(f:(n:Node, x:Float, y:Float) -> Void)
		for (m in order)
			if (m.kind == ScrollShot.SCROLLER) f(m.real, m.scrollX, m.scrollY);
}

// (a node of the mirror: an entry of the program's shot; its parent the
// scroller around it, so that the physics' walks find the scrollers)
@:allow(helder.ui)
private class MirrorNode extends Node {
	public final real:Node;
	public var alive = 0;
	public var kind = 0;
	public var async = true;
	public var claims = 0;
	public var scroller:Null<MirrorNode> = null;
	public var outer:Null<MirrorNode> = null;
	public var bx = 0.0;
	public var by = 0.0;
	public var bw = 0.0;
	public var bh = 0.0;
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	public var vx = 0.0;
	public var vy = 0.0;
	public var vw = 0.0;
	public var vh = 0.0;
	public final bars:Array<Float> = [for (_ in 0...14) 0.0];
	// (what the program was last given)
	public var sentX = 0.0;
	public var sentY = 0.0;
	public var sentMoving = false;
	public var sentHeld = false;
	var rtlNow = false;

	public function new(real:Node) {
		super("mirror");
		this.real = real;
	}

	// (its range and axes as Scrolling measures them: the view its size, no insets)
	public function shape(e:ScrollShot.ShotEntry) {
		width = e.viewW;
		height = e.viewH;
		absX = e.vx;
		absY = e.vy;
		contentWidth = e.viewW + e.maxX;
		contentHeight = e.viewH + e.maxY;
		style.overflowX = e.scrollsX ? Overflow.Scroll : Overflow.Hidden;
		style.overflowY = e.scrollsY ? Overflow.Scroll : Overflow.Hidden;
		if (e.rtl != rtlNow) {
			rtlNow = e.rtl;
			style.dir = e.rtl ? Dir.Rtl : null;
		}
	}
}

// (a gesture's gate: none yet, the compositor's, asking the program (its
// inputs held until the answer), the program's)
private class Gate {
	public static inline var NONE = 0;
	public static inline var FREE = 1;
	public static inline var ASKING = 2;
	public static inline var PROGRAM = 3;

	public var id = 0;
	public var state = NONE;
	public var asked = false;
	public final waiting:Array<ScrollInput> = [];

	public function new() {}

	public function done() {
		state = NONE;
	}
}

