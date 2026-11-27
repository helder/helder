package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.flow.Fragmentation.Resume;

// A fragmentainer's breaks (CSS Fragmentation 3 §4), as LayoutNG chooses
// them: a first pass (the probe) lays out from the incoming token,
// noting each break opportunity that fits with its appeal, until one
// past the end; a forced break ends it there and then. Else the latest of
// the best appeal is the break, and a second pass (the target) lays out
// again up to it. Appeals: perfect; orphans or widows short; an avoid
// (break-before, break-after, break-inside on a box around it); last
// resort, the first opportunity past the end, when nothing fits.
class Breaks implements Fragmentation {
	public var size(default, null):Float;
	final incoming:Null<BreakToken>;
	final points:Array<Point> = [];
	final tops = new ObjectMap<Box, Float>();
	var past:Null<Point> = null;
	var target:Null<Point> = null;
	var taken:Null<Point> = null;
	var halted = false;
	// (where the content laid out ends, its margins aside)
	var reach = 0.0;

	public function new(size:Float, incoming:Null<BreakToken>) {
		this.size = size;
		this.incoming = incoming;
	}

	public var stopped(get, never):Bool;

	inline function get_stopped():Bool
		return halted;

	public function resume(box:Box):Null<Resume>
		return incoming == null ? null : incoming.resumes.get(box);

	public function enter(box:Box, top:Float)
		tops.set(box, top);

	public function placed(bottom:Float)
		if (bottom > reach) reach = bottom;

	public function between(box:Box, before:Null<Box>, after:Box, bottom:Float):Bool {
		if (before == null) return leading({box: box, child: after, line: -1, bottom: bottom, appeal: LAST, forced: null, keep: true});
		var a = ending(before), b = starting(after);
		var forced = Breaks.forced(a) ? a : Breaks.forced(b) ? b : null;
		var appeal = a == "avoid" || a == "avoid-page" || b == "avoid" || b == "avoid-page" ? AVOID : PERFECT;
		return offer({box: box, child: after, line: -1, bottom: bottom, appeal: inside(box, appeal), forced: forced, keep: false});
	}

	public function inLines(box:Box, first:Int, line:Int, count:Int, bottom:Float):Bool {
		if (line == first) return leading({box: box, child: null, line: line, bottom: bottom, appeal: LAST, forced: null, keep: true});
		var orphans = box.style.number("orphans", 2), widows = box.style.number("widows", 2);
		var appeal = line - first < orphans || count - line < widows ? ORPHANS : PERFECT;
		return offer({box: box, child: null, line: line, bottom: bottom, appeal: inside(box, appeal), forced: null, keep: false});
	}

	// (before a box's first content here: a break only when it starts past
	// the end, a last resort; what is pushed keeps its own margins, only the
	// one past the end is dropped, as Chromium has it, unless they are a
	// page's worth themselves)
	function leading(p:Point):Bool {
		if (target != null) return offer(p);
		if (p.bottom <= size + EPSILON || p.bottom <= EPSILON) return false;
		past ??= p;
		halted = true;
		return false;
	}

	function offer(p:Point):Bool {
		if (target != null) {
			if (p.box != target.box || p.child != target.child || p.line != target.line) return false;
			taken = p;
			halted = true;
			return true;
		}
		// (nothing before it here: a break there would make no progress, a forced one at the start none)
		if (p.bottom <= EPSILON) return false;
		if (p.bottom > size + EPSILON) {
			past ??= p;
			halted = true;
			return false;
		}
		if (p.forced != null) {
			taken = p;
			halted = true;
			return true;
		}
		points.push(p);
		return false;
	}

	// After the probe: whether to lay out again up to the break chosen;
	// false: the probe's layout is the fragmentainer's.
	public function decide():Bool {
		if (taken != null) return false;
		if (!halted && reach <= size + EPSILON) return false;
		var best:Null<Point> = null;
		for (p in points) if (best == null || p.appeal >= best.appeal) best = p;
		best ??= past;
		if (best == null) return false;
		target = best;
		halted = false;
		tops.clear();
		return true;
	}

	// Where the next fragmentainer resumes; null: the content ended here.
	public function token():Null<BreakToken> {
		var p = taken;
		if (p == null) return null;
		var resumes = new ObjectMap<Box, Resume>();
		// (a pushed box's margin kept, unless it alone would push it past the end again)
		var top = tops.get(p.box);
		var forced = p.forced != null || p.keep && (top == null || p.bottom - top < size);
		resumes.set(p.box, {child: p.child, line: p.line, consumed: consumed(p.box, p.bottom), forced: forced});
		var b = p.box;
		while (b.parent != null) {
			resumes.set(b.parent, {child: b, line: -1, consumed: consumed(b.parent, p.bottom), forced: forced});
			b = b.parent;
		}
		var side = p.forced == "left" || p.forced == "verso" ? "left" : p.forced == "right" || p.forced == "recto" ? "right" : null;
		return new BreakToken(resumes, side);
	}

	// (the block size a box's content took up to the break, in this fragmentainer and the ones before)
	function consumed(box:Box, bottom:Float):Float {
		var top = tops.get(box);
		var before = resume(box);
		return (top == null ? 0 : Math.max(0, bottom - top)) + (before == null ? 0 : before.consumed);
	}

	// (a break's appeal inside box and the boxes around it, break-inside:
	// an avoid among them makes it AVOID at best, and each one more it
	// breaks inside a little less, as Chromium prefers the break fewest
	// avoids have to give)
	static function inside(box:Box, appeal:Int):Int {
		var avoids = 0, b = box;
		while (b != null) {
			var v = value(b, "inside");
			if (v == "avoid" || v == "avoid-page") avoids++;
			b = b.parent;
		}
		var rank = (avoids > 0 && appeal > AVOID ? AVOID : appeal) * NESTING;
		return rank - (avoids < NESTING ? avoids : NESTING - 1);
	}

	static inline var NESTING = 16;

	// (break-after of a box, else of its last in-flow child, inward: a forced one wins, then avoid; break-before the same from its first)
	static function ending(b:Box):String {
		var v = value(b, "after");
		if (forced(v)) return v;
		var c = b.last;
		while (c != null && (c.floating || c.absolute || !c.blockLevel)) c = previous(c);
		if (c == null) return v;
		var inner = ending(c);
		return forced(inner) || v == "auto" ? inner : v;
	}

	static function starting(b:Box):String {
		var v = value(b, "before");
		if (forced(v)) return v;
		var c = b.first;
		while (c != null && (c.floating || c.absolute || !c.blockLevel)) c = c.next;
		if (c == null) return v;
		var inner = starting(c);
		return forced(inner) || v == "auto" ? inner : v;
	}

	static function previous(c:Box):Null<Box> {
		var p = c.parent.first;
		if (p == c) return null;
		while (p.next != c) p = p.next;
		return p;
	}

	// (break-before, break-after, break-inside, or CSS 2's page-break-* when it's auto)
	static function value(b:Box, which:String):String {
		var v = b.style.keyword('break-$which');
		if (v != "" && v != "auto") return v;
		var legacy = b.style.keyword('page-break-$which');
		return legacy == "always" ? "page" : legacy == "" ? "auto" : legacy;
	}

	static inline function forced(v:Null<String>):Bool
		return v == "page" || v == "always" || v == "left" || v == "right" || v == "recto" || v == "verso";

	static inline var EPSILON = 0.01;

	public static inline var PERFECT = 3;
	public static inline var ORPHANS = 2;
	public static inline var AVOID = 1;
	public static inline var LAST = 0;
}

private typedef Point = {
	box:Box,
	child:Null<Box>,
	line:Int,
	bottom:Float,
	appeal:Int,
	forced:Null<String>,
	keep:Bool
}
