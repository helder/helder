package helder.ui.flow;

import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxStyle;
import helder.ui.box.Fragments;
import helder.ui.box.Len;

// Flow layout of block containers (CSS 2.1 §9.4.1, §10.3, §10.6, §8.3):
// widths and their auto margins (§10.3.3), shrink-to-fit for inline
// blocks, replaced sizes (§10.3.2, §10.6.2), heights, min and max sizes,
// box-sizing, percentages, margin collapsing (§8.3.1: siblings, parent
// and child, through empty boxes; none across a formatting context's
// root), relative offsets (§9.4.3), and lines (WordFlow, the inline
// layout's stand-in). Results are cached on the box by the constraint
// space they were laid out in.
class BlockFlow implements FormattingContext {
	final words:WordFlow;

	public function new()
		words = new WordFlow(this);

	public function layout(box:Box, space:Space):Int {
		// (the cache: the same containing block, the same fixed width: the same fragment)
		var key = Math.isNaN(space.fixedWidth) ? space.width : -1 - space.fixedWidth;
		// (not when its layout left absolutely positioned boxes outside it, nor beside floats: its place matters)
		var reusable = box.flags & Box.ESCAPES == 0 && (space.exclusions == null || space.exclusions.empty);
		if (reusable && box.cacheFragment >= 0 && box.cacheWidth == key && same(box.cacheHeight, space.height)) return box.cacheFragment;
		var f = box.kind == BlockReplaced || box.kind == InlineReplaced ? replaced(box, space) : container(box, space);
		box.cacheWidth = key;
		box.cacheHeight = space.height;
		box.cacheFragment = f;
		return f;
	}

	static inline function same(a:Float, b:Float):Bool
		return a == b || Math.isNaN(a) && Math.isNaN(b);

	// (a box laid out by its own context, or this one: replaced boxes have none)
	public function child(box:Box, space:Space):Int
		return box.context != null ? box.context.layout(box, space) : layout(box, space);

	// ---- block containers

	function container(box:Box, space:Space):Int {
		var s = box.style.model();
		var cb = space.width;
		var pl = res(s.padding[3], cb), pr = res(s.padding[1], cb), pt = res(s.padding[0], cb), pb = res(s.padding[2], cb);
		var ov = space.borders;
		var bl = ov != null ? ov[3] : s.border[3], br = ov != null ? ov[1] : s.border[1];
		var bt = ov != null ? ov[0] : s.border[0], bb = ov != null ? ov[2] : s.border[2];
		var bpx = pl + pr + bl + br, bpy = pt + pb + bt + bb;
		var mt = res(s.margin[0], cb), mb = res(s.margin[2], cb);
		var w = width(box, s, space, bpx);
		var root = formattingRoot(box);
		var heightSpec = size(s.height, space.height, s.borderBox, bpy);
		var pctBase = heightSpec;
		if (!Math.isNaN(pctBase)) pctBase = clampHeight(s, space.height, bpy, pctBase);
		var frags = space.fragments;
		var frag = frags.add(Fragments.BOX, box, w + bpx, 0);
		// (where it is in its formatting context: its border box's left and top, its content box's)
		var bx = space.left + box.marginLeft, by = space.top;
		var cx = bx + bl + pl, cy = by + bt + pt;
		var ex = root || space.exclusions == null ? new Exclusions() : space.exclusions;
		// (absolutely positioned descendants wait for their containing block: the nearest positioned box, else the root)
		var owner = box.parent == null || s.positioned;
		var positioned = owner ? new Positioned() : space.positioned ?? new Positioned();
		var fixed = box.parent == null ? new Positioned() : space.fixed ?? positioned;
		var escaped = space.positioned != null ? space.positioned.boxes.length : 0;
		var escapedFixed = space.fixed != null ? space.fixed.boxes.length : 0;
		inline function childSpace(width:Float):Space {
			var cs = space.child(width, pctBase);
			cs.exclusions = ex;
			cs.positioned = positioned;
			cs.fixed = fixed;
			cs.left = cx;
			return cs;
		}
		function absolute(b:Box, x:Float, y:Float)
			(b.style.position == "fixed" ? fixed : positioned).add(b, frag, x, y);
		// (a float at y or below in its formatting context, beside the floats there)
		function float(b:Box, top:Float) {
			var fs = childSpace(w);
			fs.exclusions = null;
			var f = child(b, fs);
			var m = b.style.model();
			var fmt = res(m.margin[0], w), fmb = res(m.margin[2], w);
			var clr = b.style.keyword("clear");
			if (clr == "left" || clr == "right" || clr == "both") top = Math.max(top, ex.clear(clr));
			var at = ex.place(b.style.keyword("float") == "left", b.marginLeft + frags.width(f) + b.marginRight, fmt + frags.height(f) + fmb, top, cx, cx + w);
			var off = offset(b, w, pctBase);
			frags.adopt(frag, f, at.x + b.marginLeft - bx + off.x, at.y + fmt - by + off.y);
		}
		var topCollapses = !root && bt == 0 && pt == 0;
		var autoHeight = Math.isNaN(heightSpec);
		var bottomCollapses = !root && bb == 0 && pb == 0 && autoHeight;
		var topPos = mt > 0 ? mt : 0.0, topNeg = mt < 0 ? mt : 0.0;
		var pos = 0.0, neg = 0.0, y = 0.0;
		var atTop = topCollapses, empty = true, baseline = Math.NaN;
		var lines = box.first != null && !hasInFlowBlock(box) && !onlyOutOfFlow(box);
		if (lines) {
			var ls = childSpace(w);
			ls.lineWidth = (ly, lh) -> {
				if (ex.empty) return null;
				var b = ex.band(by + ly, lh, cx, cx + w);
				var next = ex.nextBelow(by + ly, lh);
				return {offset: b.left - bx, width: b.right - b.left, next: next - by};
			};
			ls.placeFloat = (b, ly) -> float(b, by + ly);
			ls.placeAbsolute = (b, ax, ay) -> absolute(b, ax, ay);
			var r = words.layout(box, w, ls, frag, bl + pl, bt + pt, pctBase);
			if (r.lines > 0) {
				empty = false;
				atTop = false;
				y = r.height;
				baseline = r.baseline;
			}
		} else {
			var c = box.first;
			while (c != null) {
				var cs = c.style;
				// (out of flow: a float placed beside the floats before it, an absolutely positioned box's static place kept)
				if (c.floating) {
					float(c, cy + y + (atTop ? 0 : pos + neg));
					c = c.next;
					continue;
				}
				if (c.absolute) {
					absolute(c, bl + pl, bt + pt + y + (atTop ? 0 : pos + neg));
					c = c.next;
					continue;
				}
				// (where its border box will be: its top margins as they will collapse, or clearance, §9.5.2)
				var strut = predict(c, w);
				var py = atTop ? 0 : y + Math.max(pos, strut.pos) + Math.min(neg, strut.neg);
				var clr = cs.keyword("clear");
				var cleared = false;
				if ((clr == "left" || clr == "right" || clr == "both") && !ex.empty) {
					var floor = ex.clear(clr) - cy;
					if (floor > py) {
						py = floor;
						cleared = true;
					}
				}
				var space2 = childSpace(w);
				space2.top = cy + py;
				// (a formatting context's root beside floats: in the room they leave, §9.5)
				var shift = 0.0;
				if (formattingRoot(c) && !ex.empty) {
					// (down past the floats while its margins and set width don't fit beside them)
					var cm = c.style.model();
					var need = res(cm.margin[1], w) + res(cm.margin[3], w);
					var sw = size(cm.width, w, cm.borderBox, 0);
					if (!Math.isNaN(sw)) need += cm.borderBox ? sw : sw + bpxOf(c, w) else if (c.kind == TableWrapper || c.kind == BlockReplaced) {
						// (a table, a replaced element: its own width, no narrower)
						if (c.context != null) c.context.intrinsic(c, space) else intrinsic(c, space);
						need += c.minContent;
					}
					var band = ex.band(cy + py, 1, cx, cx + w);
					while (band.right - band.left < need && (band.left > cx || band.right < cx + w)) {
						var next = ex.nextBelow(cy + py, 1);
						if (next == Math.POSITIVE_INFINITY) break;
						py = next - cy;
						cleared = true;
						band = ex.band(cy + py, 1, cx, cx + w);
					}
					space2.top = cy + py;
					if (band.left > cx || band.right < cx + w) {
						space2.width = Math.max(0, band.right - band.left);
						space2.left = band.left;
						shift = band.left - cx;
					}
				}
				var cf = child(c, space2);
				// (the margins before it: with clearance its own don't join them, §9.5.2)
				var prePos = pos, preNeg = neg;
				pos = Math.max(pos, c.topPositive);
				neg = Math.min(neg, c.topNegative);
				var off = offset(c, w, pctBase);
				if (c.through && !cleared) {
					frags.adopt(frag, cf, bl + pl + shift + c.marginLeft + off.x, bt + pt + y + (atTop ? 0 : pos + neg) + off.y);
					pos = Math.max(pos, c.bottomPositive);
					neg = Math.min(neg, c.bottomNegative);
					c = c.next;
					continue;
				}
				var at = y;
				if (cleared) {
					if (atTop) {
						topPos = Math.max(topPos, prePos);
						topNeg = Math.min(topNeg, preNeg);
					}
					atTop = false;
					at = py;
				} else if (atTop) {
					topPos = Math.max(topPos, pos);
					topNeg = Math.min(topNeg, neg);
					atTop = false;
				} else
					at = y + pos + neg;
				frags.adopt(frag, cf, bl + pl + shift + c.marginLeft + off.x, bt + pt + at + off.y);
				empty = false;
				var b = frags.baseline(cf);
				if (!Math.isNaN(b)) baseline = at + b + off.y;
				y = at + frags.height(cf);
				pos = c.bottomPositive;
				neg = c.bottomNegative;
				c = c.next;
			}
		}
		var content = 0.0;
		var bottomPos = mb > 0 ? mb : 0.0, bottomNeg = mb < 0 ? mb : 0.0;
		if (atTop) {
			topPos = Math.max(topPos, pos);
			topNeg = Math.min(topNeg, neg);
		} else if (bottomCollapses) {
			content = y;
		} else
			content = Math.max(0, y + pos + neg);
		// (a formatting context's root's auto height takes its floats in, §10.6.7)
		if (root && !ex.empty) content = Math.max(content, ex.lowest() - cy);
		var h = clampHeight(s, space.height, bpy, autoHeight ? content : heightSpec);
		box.through = false;
		// (its top and bottom margins adjoin: no content, border or padding, a zero or auto height, §8.3.1)
		if (atTop && empty && !root && bb == 0 && pb == 0 && (autoHeight || heightSpec == 0) && h == 0) {
			box.through = true;
		} else if (!atTop && bottomCollapses && h == content) {
			bottomPos = Math.max(bottomPos, pos);
			bottomNeg = Math.min(bottomNeg, neg);
		}
		box.topPositive = topPos;
		box.topNegative = topNeg;
		box.bottomPositive = bottomPos;
		box.bottomNegative = bottomNeg;
		frags.resize(frag, w + bpx, h + bpy);
		// (a scroll container's too: its last line's, as CSS Align 3 and browsers have it now, not CSS 2.1's bottom edge)
		if (!Math.isNaN(baseline)) frags.setBaseline(frag, bt + pt + baseline);
		// (the absolutely positioned boxes this is the containing block of: its padding box, the root's
		// the initial containing block, §10.1)
		if (box.parent == null) {
			var ix = -box.marginLeft, iy = -(topPos + topNeg);
			place(fixed, frag, space, ix, iy, space.width, space.height);
			place(positioned, frag, space, ix, iy, space.width, space.height);
		} else if (owner)
			place(positioned, frag, space, bl, bt, w + pl + pr, h + pt + pb);
		// (a box whose layout left absolutely positioned boxes outside it is not reused from the cache)
		var leaked = (space.positioned != null && space.positioned.boxes.length > escaped) || (space.fixed != null && space.fixed.boxes.length > escapedFixed);
		box.flags = leaked ? box.flags | Box.ESCAPES : box.flags & ~Box.ESCAPES;
		return frag;
	}

	static function bpxOf(b:Box, cb:Float):Float {
		var m = b.style.model();
		return m.border[1] + m.border[3] + res(m.padding[1], cb) + res(m.padding[3], cb);
	}

	// (in-flow and block-level: what makes a block container's contents blocks, not lines)
	static inline function inFlowBlock(b:Box):Bool
		return b.blockLevel && !b.floating && !b.absolute;

	static function hasInFlowBlock(box:Box):Bool {
		var c = box.first;
		while (c != null) {
			if (inFlowBlock(c)) return true;
			c = c.next;
		}
		return false;
	}

	// (a container whose children are all floats or absolutely positioned: laid out as blocks)
	static function onlyOutOfFlow(box:Box):Bool {
		var c = box.first;
		while (c != null) {
			if (!c.floating && !c.absolute) return false;
			c = c.next;
		}
		return true;
	}

	// (the top margins that will collapse into a child's: its own and its first in-flow descendants' while
	// nothing parts them, before it is laid out)
	static function predict(c:Box, cb:Float):{pos:Float, neg:Float} {
		var pos = 0.0, neg = 0.0;
		var b = c;
		while (b != null) {
			var m = b.style.model();
			var v = res(m.margin[0], cb);
			if (v > 0) pos = Math.max(pos, v) else neg = Math.min(neg, v);
			if (formattingRoot(b) || m.border[0] > 0 || res(m.padding[0], cb) > 0) break;
			var f = b.first;
			if (f == null || !inFlowBlock(f)) break;
			b = f;
		}
		return {pos: pos, neg: neg};
	}

	// ---- absolutely positioned boxes (§10.3.7, §10.6.4)

	// (each laid out in a containing block at cbx, cby of cbw by cbh in owner's border box)
	function place(list:Positioned, owner:Int, space:Space, cbx:Float, cby:Float, cbw:Float, cbh:Float) {
		var frags = space.fragments;
		var k = 0;
		while (k < list.boxes.length) {
			var b = list.boxes[k];
			var from = frags.absolute(list.fragments[k]), to = frags.absolute(owner);
			var sx = from.x - to.x + list.xs[k] - cbx, sy = from.y - to.y + list.ys[k] - cby;
			var f = positionedBox(b, space, sx, sy, cbw, cbh);
			frags.adopt(owner, f.fragment, cbx + f.x, cby + f.y);
			k++;
		}
	}

	// (its border box's place in its containing block, given its static place there: CSS 2.1's equations)
	function positionedBox(b:Box, space:Space, sx:Float, sy:Float, cbw:Float, cbh:Float):{fragment:Int, x:Float, y:Float} {
		var s = b.style.model();
		var pl = res(s.padding[3], cbw), pr = res(s.padding[1], cbw), pt = res(s.padding[0], cbw), pb = res(s.padding[2], cbw);
		var bpx = pl + pr + s.border[1] + s.border[3], bpy = pt + pb + s.border[0] + s.border[2];
		var left = auto(b.style.len("left"), cbw), right = auto(b.style.len("right"), cbw);
		var top = auto(b.style.len("top"), cbh), bottom = auto(b.style.len("bottom"), cbh);
		var ml = auto(s.margin[3], cbw), mr = auto(s.margin[1], cbw), mt = auto(s.margin[0], cbw), mb = auto(s.margin[2], cbw);
		var w = b.kind == BlockReplaced || b.kind == InlineReplaced ? replacedSize(b, cbw, cbh, bpx, bpy).w : size(s.width, cbw, s.borderBox, bpx);
		var minW = size(s.minWidth, cbw, s.borderBox, bpx), maxW = size(s.maxWidth, cbw, s.borderBox, bpx);
		var rtl = b.parent != null && b.parent.style.rtl;
		function shrink(avail:Float):Float {
			if (b.context != null) b.context.intrinsic(b, space) else intrinsic(b, space);
			return Math.min(Math.max(b.minContent, avail), b.maxContent) - bpx;
		}
		function horizontal(w:Float):Float {
			var l = left, r = right, a = ml, c = mr;
			if (Math.isNaN(l) && Math.isNaN(w) && Math.isNaN(r)) {
				if (Math.isNaN(a)) a = 0;
				if (Math.isNaN(c)) c = 0;
				if (rtl) {
					r = cbw - sx;
					w = shrink(cbw - r - a - c);
					l = cbw - r - a - c - w - bpx;
				} else {
					l = sx;
					w = shrink(cbw - l - a - c);
				}
			} else if (!Math.isNaN(l) && !Math.isNaN(w) && !Math.isNaN(r)) {
				var rest = cbw - l - r - w - bpx;
				if (Math.isNaN(a) && Math.isNaN(c)) {
					a = c = rest / 2;
					if (a < 0) {
						if (rtl) {
							c = 0;
							a = rest;
						} else {
							a = 0;
							c = rest;
						}
					}
				} else if (Math.isNaN(a))
					a = rest - c
				else if (Math.isNaN(c)) c = rest - a;
			} else {
				if (Math.isNaN(a)) a = 0;
				if (Math.isNaN(c)) c = 0;
				if (Math.isNaN(l) && Math.isNaN(w)) {
					w = shrink(cbw - r - a - c);
					l = cbw - r - a - c - w - bpx;
				} else if (Math.isNaN(l) && Math.isNaN(r)) {
					if (rtl) {
						r = cbw - sx;
						l = cbw - r - a - c - w - bpx;
					} else
						l = sx;
				} else if (Math.isNaN(w) && Math.isNaN(r)) {
					w = shrink(cbw - l - a - c);
				} else if (Math.isNaN(l)) {
					l = cbw - r - a - c - w - bpx;
				} else if (Math.isNaN(w)) {
					w = Math.max(0, cbw - l - r - a - c - bpx);
				}
			}
			ml = a;
			mr = c;
			left = l;
			return Math.max(0, w);
		}
		var used = horizontal(w);
		if (!Math.isNaN(maxW) && used > maxW) used = horizontal(maxW);
		if (!Math.isNaN(minW) && used < minW) used = horizontal(minW);
		var cs = space.child(cbw, cbh);
		cs.fixedWidth = used + bpx;
		cs.exclusions = null;
		cs.left = 0;
		cs.top = 0;
		b.cacheFragment = -1;
		var f = child(b, cs);
		var frags = space.fragments;
		// (vertical: the height its content gave, or what top and bottom leave)
		var h = frags.height(f) - bpy;
		var spec = size(s.height, cbh, s.borderBox, bpy);
		var t = top, bt = bottom, a = mt, c = mb;
		if (Math.isNaN(t) && Math.isNaN(bt)) {
			if (Math.isNaN(a)) a = 0;
			t = sy;
		} else if (!Math.isNaN(t) && !Math.isNaN(bt) && !Math.isNaN(spec)) {
			var rest = cbh - t - bt - spec - bpy;
			// (equal auto margins, negative too: §10.6.4 has no rule against it, unlike §10.3.7)
			if (Math.isNaN(a) && Math.isNaN(c)) a = rest / 2 else if (Math.isNaN(a)) a = rest - c;
		} else {
			if (Math.isNaN(a)) a = 0;
			if (Math.isNaN(c)) c = 0;
			if (Math.isNaN(t) && !Math.isNaN(bt)) t = cbh - bt - a - c - h - bpy else if (!Math.isNaN(t) && !Math.isNaN(bt) && Math.isNaN(spec)) {
				var stretched = clampHeight(s, cbh, bpy, Math.max(0, cbh - t - bt - a - c - bpy));
				frags.resize(f, frags.width(f), stretched + bpy);
			}
		}
		return {fragment: f, x: left + ml, y: t + a};
	}

	// (a new block formatting context's root: no margin collapses across it, §8.3.1, §9.4.1)
	static function formattingRoot(box:Box):Bool {
		var s = box.style;
		return box.parent == null || box.kind != Block || s.clips || s.inner == BoxStyle.FLOW_ROOT || box.floating || box.absolute;
	}

	// The content width, the used side margins on the box (§10.3.3; shrink-to-fit §10.3.9).
	function width(box:Box, s:BoxStyle, space:Space, bpx:Float):Float {
		var cb = space.width;
		var ml = auto(s.margin[3], cb), mr = auto(s.margin[1], cb);
		var minW = Math.max(0, size(s.minWidth, cb, s.borderBox, bpx));
		var maxW = size(s.maxWidth, cb, s.borderBox, bpx);
		if (Math.isNaN(minW)) minW = 0;
		var w:Float;
		if (!Math.isNaN(space.fixedWidth)) {
			box.marginLeft = Math.isNaN(ml) ? 0 : ml;
			box.marginRight = Math.isNaN(mr) ? 0 : mr;
			return Math.max(0, space.fixedWidth - bpx);
		}
		var spec = size(s.width, cb, s.borderBox, bpx);
		// (a table's caption is laid out as a block in its table's width)
		if (box.blockLevel && box.kind != InlineBlock && !box.floating && !box.absolute || box.style.part == BoxStyle.CAPTION) {
			var rtl = box.parent != null && box.parent.style.rtl;
			w = solve(box, spec, ml, mr, cb, bpx, rtl);
			if (!Math.isNaN(maxW) && w > maxW) w = solve(box, maxW, ml, mr, cb, bpx, rtl);
			if (w < minW) w = solve(box, minW, ml, mr, cb, bpx, rtl);
			return Math.max(0, w);
		}
		box.marginLeft = Math.isNaN(ml) ? 0 : ml;
		box.marginRight = Math.isNaN(mr) ? 0 : mr;
		if (Math.isNaN(spec)) {
			intrinsic(box, space);
			var available = cb - box.marginLeft - box.marginRight;
			spec = Math.min(Math.max(box.minContent, available), box.maxContent) - bpx;
		}
		w = spec;
		if (!Math.isNaN(maxW) && w > maxW) w = maxW;
		if (w < minW) w = minW;
		return Math.max(0, w);
	}

	// (CSS 2.1 §10.3.3's equation for a width, NaN: auto, and the margins, NaN: auto)
	public static function solve(box:Box, w:Float, ml:Float, mr:Float, cb:Float, bpx:Float, rtl:Bool):Float {
		if (!Math.isNaN(w) && w + bpx + (Math.isNaN(ml) ? 0 : ml) + (Math.isNaN(mr) ? 0 : mr) > cb) {
			if (Math.isNaN(ml)) ml = 0;
			if (Math.isNaN(mr)) mr = 0;
		}
		if (Math.isNaN(w)) {
			if (Math.isNaN(ml)) ml = 0;
			if (Math.isNaN(mr)) mr = 0;
			w = cb - ml - mr - bpx;
		} else if (Math.isNaN(ml) && Math.isNaN(mr)) {
			ml = mr = (cb - w - bpx) / 2;
		} else if (Math.isNaN(ml)) {
			ml = cb - w - bpx - mr;
		} else if (Math.isNaN(mr)) {
			mr = cb - w - bpx - ml;
		} else if (rtl) {
			ml = cb - w - bpx - mr;
		} else
			mr = cb - w - bpx - ml;
		box.marginLeft = ml;
		box.marginRight = mr;
		return w;
	}

	// (a height clamped by min-height and max-height, §10.7)
	static function clampHeight(s:BoxStyle, cbh:Float, bpy:Float, h:Float):Float {
		var maxH = size(s.maxHeight, cbh, s.borderBox, bpy);
		if (!Math.isNaN(maxH) && h > maxH) h = maxH;
		var minH = size(s.minHeight, cbh, s.borderBox, bpy);
		if (!Math.isNaN(minH) && h < minH) h = minH;
		return h < 0 ? 0 : h;
	}

	// ---- replaced elements (§10.3.2, §10.6.2)

	function replaced(box:Box, space:Space):Int {
		var s = box.style.model();
		var cb = space.width;
		var pl = res(s.padding[3], cb), pr = res(s.padding[1], cb), pt = res(s.padding[0], cb), pb = res(s.padding[2], cb);
		var bpx = pl + pr + s.border[1] + s.border[3], bpy = pt + pb + s.border[0] + s.border[2];
		var size = replacedSize(box, space.width, space.height, bpx, bpy);
		var ml = auto(s.margin[3], cb), mr = auto(s.margin[1], cb);
		if (box.blockLevel) solve(box, size.w, ml, mr, cb, bpx, box.parent != null && box.parent.style.rtl) else {
			box.marginLeft = Math.isNaN(ml) ? 0 : ml;
			box.marginRight = Math.isNaN(mr) ? 0 : mr;
		}
		var mt = res(s.margin[0], cb), mb = res(s.margin[2], cb);
		box.topPositive = mt > 0 ? mt : 0;
		box.topNegative = mt < 0 ? mt : 0;
		box.bottomPositive = mb > 0 ? mb : 0;
		box.bottomNegative = mb < 0 ? mb : 0;
		box.through = false;
		return space.fragments.add(Fragments.BOX, box, size.w + bpx, size.h + bpy);
	}

	public static function replacedSize(box:Box, cbw:Float, cbh:Float, bpx:Float, bpy:Float):{w:Float, h:Float} {
		var s = box.style.model();
		var iw = box.image == null ? 0.0 : box.image.width, ih = box.image == null ? 0.0 : box.image.height;
		var ratio = ih > 0 ? iw / ih : Math.NaN;
		var w = size(s.width, cbw, s.borderBox, bpx), h = size(s.height, cbh, s.borderBox, bpy);
		if (Math.isNaN(w) && Math.isNaN(h)) {
			w = iw;
			h = ih;
		} else if (Math.isNaN(w))
			w = Math.isNaN(ratio) ? iw : h * ratio
		else if (Math.isNaN(h)) h = Math.isNaN(ratio) || ratio == 0 ? ih : w / ratio;
		var maxW = size(s.maxWidth, cbw, s.borderBox, bpx), minW = size(s.minWidth, cbw, s.borderBox, bpx);
		var maxH = size(s.maxHeight, cbh, s.borderBox, bpy), minH = size(s.minHeight, cbh, s.borderBox, bpy);
		if (!Math.isNaN(maxW) && w > maxW) w = maxW;
		if (!Math.isNaN(minW) && w < minW) w = minW;
		if (!Math.isNaN(maxH) && h > maxH) h = maxH;
		if (!Math.isNaN(minH) && h < minH) h = minH;
		return {w: Math.max(0, w), h: Math.max(0, h)};
	}

	// ---- intrinsic sizes (min-content and max-content, border box)

	public function intrinsic(box:Box, space:Space) {
		if (!Math.isNaN(box.minContent)) return;
		var s = box.style.model();
		var bpx = fixed(s.padding[1]) + fixed(s.padding[3]) + s.border[1] + s.border[3];
		var min = 0.0, max = 0.0;
		var w = switch s.width {
			case Px(v): s.borderBox ? Math.max(v, bpx) : v + bpx;
			case _: Math.NaN;
		}
		if (!Math.isNaN(w)) {
			min = max = w;
		} else if (box.kind == BlockReplaced || box.kind == InlineReplaced) {
			min = max = replacedSize(box, Math.NaN, Math.NaN, 0, 0).w + bpx;
		} else if (box.first != null && !box.first.blockLevel) {
			var r = words.intrinsic(box, space);
			min = r.min + bpx;
			max = r.max + bpx;
		} else {
			var c = box.first;
			while (c != null) {
				if (c.context != null) c.context.intrinsic(c, space) else intrinsic(c, space);
				var cs = c.style.model();
				var m = fixed(cs.margin[1]) + fixed(cs.margin[3]);
				min = Math.max(min, c.minContent + m);
				max = Math.max(max, c.maxContent + m);
				c = c.next;
			}
			min += bpx;
			max += bpx;
		}
		switch s.maxWidth {
			case Px(v):
				var v = s.borderBox ? v : v + bpx;
				if (min > v) min = v;
				if (max > v) max = v;
			case _:
		}
		switch s.minWidth {
			case Px(v):
				var v = s.borderBox ? v : v + bpx;
				if (min < v) min = v;
				if (max < v) max = v;
			case _:
		}
		box.minContent = min;
		box.maxContent = Math.max(min, max);
	}

	// ---- lengths

	// (a percentage of an indefinite base, and auto: 0)
	public static inline function res(l:Len, base:Float):Float {
		var v = Lens.resolve(l, base, 0);
		return Math.isNaN(v) ? 0 : v;
	}

	// (auto: NaN)
	public static inline function auto(l:Len, base:Float):Float
		return Lens.resolve(l, base, Math.NaN);

	public static function fixed(l:Len):Float
		return switch l {
			case Px(v): v;
			case _: 0;
		}

	// (a size as a content size: border-box's less padding and border; auto or indefinite: NaN)
	public static function size(l:Len, base:Float, borderBox:Bool, bp:Float):Float {
		var v = Lens.resolve(l, base, Math.NaN);
		return Math.isNaN(v) || !borderBox ? v : Math.max(0, v - bp);
	}

	// A fragment's first baseline from its top (its first line's, through its first boxes; NaN: none):
	// a table cell's and a table's, where CSS 2.1 §17.5.3 aligns rows.
	public static function firstBaseline(f:Fragments, id:Int):Float {
		var c = f.first(id);
		while (c >= 0) {
			switch f.kind(c) {
				case Fragments.LINE:
					return f.y(c) + f.baseline(c);
				case Fragments.BOX:
					var b = firstBaseline(f, c);
					if (!Math.isNaN(b)) return f.y(c) + b;
				case _:
			}
			c = f.next(c);
		}
		return Math.NaN;
	}

	// A relatively positioned box's offset (§9.4.3): left over right (right in
	// right-to-left), top over bottom; a percentage of an indefinite height is 0.
	public static function offset(box:Box, cbw:Float, cbh:Float):{x:Float, y:Float} {
		var s = box.style;
		if (s.position != "relative") return ZERO;
		var left = s.len("left"), right = s.len("right"), top = s.len("top"), bottom = s.len("bottom");
		var rtl = box.parent != null && box.parent.style.rtl;
		var x = 0.0, y = 0.0;
		if (!Lens.isAuto(left) && !(rtl && !Lens.isAuto(right))) x = res(left, cbw) else if (!Lens.isAuto(right)) x = -res(right, cbw);
		if (!Lens.isAuto(top)) y = res(top, cbh) else if (!Lens.isAuto(bottom)) y = -res(bottom, cbh);
		return {x: x, y: y};
	}

	static final ZERO = {x: 0.0, y: 0.0};
}
