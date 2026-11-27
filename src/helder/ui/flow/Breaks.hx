package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.box.BoxStyle;
import helder.ui.flow.Fragmentation.Deferred;
import helder.ui.flow.Fragmentation.Resume;

// A fragmentainer's breaks (CSS Fragmentation 3 §4), as LayoutNG chooses
// them: a first pass (the probe) lays out from the incoming token,
// noting each break opportunity that fits with its appeal, until one
// past the end; a forced break ends it there and then. Else the latest of
// the best appeal is the break, and a second pass (the target) lays out
// again up to it. Appeals: perfect; orphans or widows short; an avoid
// (break-before, break-after, break-inside on a box around it); last
// resort, the first opportunity past the end, when nothing fits.
class Breaks implements Fragmentation.Fragmentainer {
	public var size(default, null):Float;
	final incoming:Null<BreakToken>;
	final points:Array<Point> = [];
	final tops = new ObjectMap<Box, Float>();
	var past:Null<Point> = null;
	var target:Null<Point> = null;
	var taken:Null<Point> = null;
	var halted = false;
	// (the absolutely positioned boxes deferred in this pass, and the floats carried)
	public var deferred(default, null):Array<Deferred> = [];
	final carries = new ObjectMap<Box, BreakToken>();
	// (where the content laid out ends, its margins aside; where the floats placed so far end)
	var reach = 0.0;
	var floor = 0.0;

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

	// (progress even with no content before it here: the box's height fills the fragmentainer)
	public function after(box:Box, bottom:Float, ?forced:Bool):Bool
		return offer({box: box, child: null, line: BreakToken.PAST, from: null, bottom: Math.max(bottom, 2 * EPSILON), appeal: inside(box, PERFECT),
			forced: forced ? "page" : null, keep: false});

	public function defer(d:Deferred)
		deferred.push(d);

	public function monolithic(box:Box, top:Float):Bool {
		tops.set(box, top);
		return offer({box: box, child: null, line: BreakToken.MONO, from: null, bottom: size, appeal: inside(box, LAST), forced: null, keep: false});
	}

	public function overflowing(box:Box, at:InlineBreak, top:Float):Bool
		return offer({box: box, child: null, line: BreakToken.LINE, from: at, bottom: size, appeal: inside(box, LAST), forced: null, keep: false,
			shift: size - top});

	public function rows():Fragmentation.FragmentRows
		return new Rows();

	public function sub(size:Float, from:Null<BreakToken>):Fragmentation.Fragmentainer
		return new Breaks(size, from);

	public function push(float:Box)
		carry(float, new BreakToken(new haxe.ds.ObjectMap(), null, null));

	public function avoids(b:Box):Bool
		return Breaks.avoidsInside(b);

	public function forcesBefore(b:Box):Bool
		return Breaks.forcedBefore(b);

	public function parallel(box:Box, child:Box):Null<Fragmentation.Fragmentainer> {
		var r = resume(box);
		if (r != null && r.parallel != null) {
			var t = r.parallel.get(child);
			return t == null ? null : new Breaks(size, t);
		}
		return new Breaks(size, null);
	}

	public function carry(float:Box, token:BreakToken)
		carries.set(float, token);

	public function uncarry(float:Box)
		carries.remove(float);

	public function carrying(box:Box):Bool {
		for (f in carries.keys()) {
			var a = f.parent;
			while (a != null && a != box) a = a.parent;
			if (a == box) return true;
		}
		return false;
	}

	public function carried(host:Box):Array<{box:Box, token:BreakToken}> {
		var out = [];
		if (incoming == null) return out;
		for (f => t in incoming.floats) {
			var a = f.parent;
			while (a != null && resume(a) == null) a = a.parent;
			if (a == host) out.push({box: f, token: t});
		}
		return out;
	}

	public function split(box:Box, tokens:ObjectMap<Box, BreakToken>, bottom:Float, ?tall:Bool):Bool
		return offer({box: box, child: null, line: BreakToken.SPLIT, from: null, parallel: tokens, bottom: bottom,
			appeal: tall && box.parent != null ? inside(box.parent, PERFECT) : inside(box, PERFECT), forced: null, keep: false});

	public function floated(bottom:Float) {
		if (bottom > floor) floor = bottom;
		placed(bottom);
	}

	public function between(box:Box, before:Null<Box>, after:Box, bottom:Float):Bool {
		if (before == null) return leading({box: box, child: after, line: -1, from: null, bottom: bottom, appeal: LAST, forced: null, keep: true});
		// (before a float, out of flow: its own break-before (not its content's), its page name making no break)
		var a = ending(before), b = after.floating ? value(after, "before") : starting(after);
		var forced = Breaks.forced(a) ? a : Breaks.forced(b) ? b : null;
		// (named pages, Paged Media 3 §5.1: siblings of different page names, a page break between; a flex, grid
		// or table container's items' make none)
		if (forced == null && !after.floating && container(box) && ending(before, true) != starting(after, true)) forced = "page";
		var appeal = a == "avoid" || a == "avoid-page" || b == "avoid" || b == "avoid-page" ? AVOID : PERFECT;
		return offer({box: box, child: after, line: -1, from: null, bottom: bottom, appeal: inside(box, appeal), forced: forced, keep: false});
	}

	public function inLines(box:Box, first:Int, line:Int, count:Int, bottom:Float, at:InlineBreak):Bool {
		if (line == first) return leading({box: box, child: null, line: line, from: at, bottom: bottom, appeal: LAST, forced: null, keep: true});
		var orphans = box.style.rare.orphans, widows = box.style.rare.widows;
		var appeal = line - first < orphans || count - line < widows ? ORPHANS : PERFECT;
		return offer({box: box, child: null, line: line, from: at, bottom: bottom, appeal: inside(box, appeal), forced: null, keep: false});
	}

	// (before a box's first content here: a break only when it starts past
	// the end, a last resort; what is pushed keeps its own margins, only the
	// one past the end is dropped, as Chromium has it, unless they are a
	// page's worth themselves)
	function leading(p:Point):Bool {
		if (target != null) return offer(p);
		if (p.bottom < floor) p.bottom = floor;
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
		// (the floats before it end there too; nothing before it here: a break there would make no
		// progress, a forced one at the start none)
		if (p.bottom < floor) p.bottom = floor;
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
		floor = 0;
		deferred.resize(0);
		carries.clear();
		tops.clear();
		return true;
	}

	// Where the next fragmentainer resumes; null: the content ended here.
	public function token():Null<BreakToken> {
		var p = taken;
		// (the content ended here but a float goes on: the boxes around it resumed past their content)
		if (p == null) {
			if (!carries.iterator().hasNext()) return null;
			var resumes = new ObjectMap<Box, Resume>(), floats = new ObjectMap<Box, BreakToken>();
			// (its parent past its content, the boxes around that resumed at it)
			for (f => t in carries) {
				floats.set(f, t);
				var b = f.parent;
				if (b == null || resumes.exists(b)) continue;
				resumes.set(b, {child: null, line: BreakToken.PAST, from: null, consumed: consumed(b, size), forced: false});
				while (b.parent != null && !resumes.exists(b.parent)) {
					resumes.set(b.parent, {child: b, line: -1, from: null, consumed: consumed(b.parent, size), forced: false});
					b = b.parent;
				}
			}
			return new BreakToken(resumes, null, null, floats);
		}
		var resumes = new ObjectMap<Box, Resume>();
		// (a pushed box's margin kept, unless it alone would push it past the end again)
		var top = tops.get(p.box);
		var forced = p.forced != null || p.keep && (top == null || p.bottom - top < size);
		// (past a box's content: it and the boxes around it to the fragmentainer's end)
		var end = p.line == BreakToken.PAST ? size : p.bottom;
		resumes.set(p.box, {child: p.child, line: p.line, from: p.from, parallel: p.parallel, consumed: consumed(p.box, end), forced: forced, shift: p.shift});
		var b = p.box;
		while (b.parent != null) {
			resumes.set(b.parent, {child: b, line: -1, from: null, consumed: consumed(b.parent, end), forced: forced});
			b = b.parent;
		}
		var side = p.forced == "left" || p.forced == "verso" ? "left" : p.forced == "right" || p.forced == "recto" ? "right" : null;
		var floats = new ObjectMap<Box, BreakToken>();
		for (f => t in carries) floats.set(f, t);
		return new BreakToken(resumes, side, p.child != null ? first(p.child) : named(p.box), floats);
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

	// A box's used page name (its page property, auto its parent's; null: none).
	public static function named(b:Null<Box>):Null<String> {
		while (b != null) {
			var v = b.style.rare.page;
			if (v != "" && v != "auto") return v;
			b = b.parent;
		}
		return null;
	}

	// The page name a box starts with: its first in-flow block descendant's, inward through block containers
	// (a flex, grid or table container's items don't give it theirs).
	public static function first(b:Box):Null<String> {
		if (!container(b)) return named(b);
		var c = b.first;
		while (c != null && (c.floating || c.absolute || !c.blockLevel)) c = c.next;
		return c == null ? named(b) : first(c);
	}

	static function last(b:Box):Null<String> {
		if (!container(b)) return named(b);
		var c = b.last;
		while (c != null && (c.floating || c.absolute || !c.blockLevel)) c = previous(c);
		return c == null ? named(b) : last(c);
	}

	static inline function container(b:Box):Bool {
		var inner = b.style.inner;
		return b.kind != TableWrapper && inner != BoxStyle.FLEX && inner != BoxStyle.GRID && inner != BoxStyle.TABLE;
	}

	// (break-after of a box, else of its last in-flow child, inward: a forced one wins, then avoid; break-before the same from its first;
	// pages: the page names there instead)
	static function ending(b:Box, ?pages:Bool):String {
		if (pages) return last(b) ?? "";
		var v = value(b, "after");
		if (forced(v)) return v;
		var c = b.last;
		while (c != null && (c.floating || c.absolute || !c.blockLevel)) c = previous(c);
		if (c == null) return v;
		var inner = ending(c);
		return forced(inner) || v == "auto" ? inner : v;
	}

	static function starting(b:Box, ?pages:Bool):String {
		if (pages) return first(b) ?? "";
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

	// Whether a box forces a break before it (break-before, page-break-before).
	static function forcedBefore(b:Box):Bool
		return forced(value(b, "before"));

	// Whether a box avoids a break inside it (break-inside, page-break-inside).
	static function avoidsInside(b:Box):Bool {
		var v = value(b, "inside");
		return v == "avoid" || v == "avoid-page";
	}

	// (break-before, break-after, break-inside, or CSS 2's page-break-* when it's auto)
	static function value(b:Box, which:String):String {
		var r = b.style.rare;
		var v = which == "before" ? r.breakBefore : which == "after" ? r.breakAfter : r.breakInside;
		if (v != "" && v != "auto") return v;
		var legacy = which == "before" ? r.pageBreakBefore : which == "after" ? r.pageBreakAfter : r.pageBreakInside;
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
	from:Null<InlineBreak>,
	?parallel:ObjectMap<Box, BreakToken>,
	bottom:Float,
	appeal:Int,
	forced:Null<String>,
	keep:Bool,
	?shift:Float
}
