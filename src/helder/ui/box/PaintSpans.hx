package helder.ui.box;

import helder.ui.draw.DisplayList;

// What a paint recorded of each stacking context into a display list (a
// span of the list's calls: Chromium's subsequences), kept for the next
// paint: a context the next paint order copied from this one, nothing in
// it restyled since, in the same area and the same scrolls, is copied from
// the list's recording before (DisplayList.copySpan) instead of painted
// again. Flat contexts alone (their steps all in the state they start in:
// no clip or layer of their own), so a copy leaves the painter's state as
// painting would. A span none of whose steps were culled holds them all:
// copied in another area or at other scrolls too (what is in a scroller
// is drawn in its own coordinates, its scroll a translation before it),
// as a window is resized and a list scrolled. A view keeps one;
// BoxPainter fills it.
class PaintSpans {
	// (the paint's: its order's number, its area, its scroll offsets' sum, its list and its take; by context
	// record its span, the list's ints, floats and resources from...to and whether no step was culled, 7 a
	// record, -1 none; the paint before's the same, what this one copies from)
	var order = -1;
	var area = [0.0, 0.0, 0.0, 0.0];
	var scroll = 0.0;
	var list:Null<DisplayList> = null;
	var take = -1;
	var spans:Array<Int> = [];
	var lastOrder = -1;
	var lastArea = [0.0, 0.0, 0.0, 0.0];
	var lastScroll = 0.0;
	var lastList:Null<DisplayList> = null;
	var lastTake = -1;
	var lastSpans:Array<Int> = [];
	// a paint restyled since (a colour, a background): nothing copied by the next
	public var fresh = false;
	// how many contexts the last paint copied, and recorded a span for
	public var copied(default, null) = 0;
	public var recorded(default, null) = 0;

	// (spans neither kept nor copied, anywhere: a check's, the same frame painted whole)
	public static var off = false;

	public function new() {}

	// (a paint of o begins into l: what the one before kept is what this one copies from)
	@:allow(helder.ui.box.BoxPainter) function begin(o:PaintOrder, l:DisplayList, a:Null<Array<Float>>, s:Float) {
		var t = lastSpans;
		lastSpans = spans;
		spans = t;
		var ta = lastArea;
		lastArea = area;
		area = ta;
		lastOrder = order;
		lastScroll = scroll;
		lastList = list;
		lastTake = take;
		order = o.id;
		for (k in 0...4) area[k] = a == null ? Math.NaN : a[k];
		scroll = s;
		list = l;
		take = l.take;
		spans.resize(STRIDE * o.contexts);
		for (k in 0...spans.length) spans[k] = -1;
		copied = recorded = 0;
	}

	// (the record of the paint before that context r of o was: -1 where none can be copied)
	@:allow(helder.ui.box.BoxPainter) function before(o:PaintOrder, r:Int):Int {
		if (fresh || lastList != list) return -1;
		var q = o.id == lastOrder ? r : o.basis == lastOrder ? o.ctxFrom[r] : -1;
		if (q < 0 || STRIDE * q >= lastSpans.length || lastSpans[STRIDE * q] < 0) return -1;
		if (lastSpans[STRIDE * q + 6] == 1) return q;
		// (some of its steps culled: in the same area at the same scrolls alone)
		if (lastScroll != scroll) return -1;
		for (k in 0...4) if (lastArea[k] != area[k] && !(lastArea[k] != lastArea[k] && area[k] != area[k])) return -1;
		return q;
	}

	static inline var STRIDE = 7;

	// (r's span of the paint before, q's, copied into the list: whether it was)
	@:allow(helder.ui.box.BoxPainter) function copy(r:Int, q:Int):Bool {
		var l = list, s = lastSpans, k = STRIDE * q;
		var i0 = l.markInts(), f0 = l.markFloats(), r0 = l.markResources();
		if (!l.copySpan(lastTake, s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4], s[k + 5])) return false;
		keep(r, i0, f0, r0, s[k + 6] == 1);
		copied++;
		return true;
	}

	// (r's span: from the marks given to where the list records now)
	@:allow(helder.ui.box.BoxPainter) function keep(r:Int, i0:Int, f0:Int, r0:Int, whole:Bool) {
		var l = list, k = STRIDE * r;
		spans[k] = i0;
		spans[k + 1] = l.markInts();
		spans[k + 2] = f0;
		spans[k + 3] = l.markFloats();
		spans[k + 4] = r0;
		spans[k + 5] = l.markResources();
		spans[k + 6] = whole ? 1 : 0;
	}

	@:allow(helder.ui.box.BoxPainter) inline function mark()
		recorded++;

	// (a paint that recorded no spans: none kept, none copied by the next)
	@:allow(helder.ui.box.BoxPainter) function none() {
		order = -1;
		list = null;
		spans.resize(0);
	}
}
