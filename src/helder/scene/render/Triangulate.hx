package helder.scene.render;

// Polygons with holes into triangles, by ear clipping (Mapbox's earcut,
// ISC, ported without its z-order hash: shapes and glyphs have tens to
// hundreds of points): each hole bridged into its outline from its
// leftmost point to a point of the outline it sees, then ears cut, the
// polygon's local self-intersections cured and, where no ear is left,
// split in two. For Geometry.extrude's caps (and so text's).
//
//   points   x, y pairs: the outline, then each hole (holes' starts in holes)
//   returns  triangles as indices of points, counter-clockwise for y up
class Triangulate {
	public static function polygon(points:Array<Float>, ?holes:Array<Int>):Array<Int> {
		var hasHoles = holes != null && holes.length > 0;
		var outerLen = hasHoles ? holes[0] * 2 : points.length;
		var out:Array<Int> = [];
		var outer = linked(points, 0, outerLen, true);
		if (outer == null || outer.next == outer.prev) return out;
		if (hasHoles) outer = eliminateHoles(points, holes, outer);
		earcutLinked(outer, out, 0);
		return out;
	}

	// a ring of nodes over points start to end (x, y floats), turned to the winding asked
	static function linked(data:Array<Float>, start:Int, end:Int, clockwise:Bool):Null<EarNode> {
		var last:Null<EarNode> = null;
		if (clockwise == (signedArea(data, start, end) > 0)) {
			var i = start;
			while (i < end) {
				last = insert(Std.int(i / 2), data[i], data[i + 1], last);
				i += 2;
			}
		} else {
			var i = end - 2;
			while (i >= start) {
				last = insert(Std.int(i / 2), data[i], data[i + 1], last);
				i -= 2;
			}
		}
		if (last != null && equals(last, last.next)) {
			remove(last);
			last = last.next;
		}
		return last;
	}

	// (earcut's: positive for clockwise in y-down numbers)
	static function signedArea(data:Array<Float>, start:Int, end:Int):Float {
		var sum = 0.0, j = end - 2, i = start;
		while (i < end) {
			sum += (data[j] - data[i]) * (data[i + 1] + data[j + 1]);
			j = i;
			i += 2;
		}
		return sum;
	}

	static function filterPoints(start:EarNode, ?end:EarNode):EarNode {
		if (end == null) end = start;
		var p = start, again;
		do {
			again = false;
			if (!p.steiner && (equals(p, p.next) || area(p.prev, p, p.next) == 0)) {
				remove(p);
				p = end = p.prev;
				if (p == p.next) break;
				again = true;
			} else
				p = p.next;
		} while (again || p != end);
		return end;
	}

	static function earcutLinked(ear:Null<EarNode>, out:Array<Int>, pass:Int) {
		if (ear == null) return;
		var stop = ear;
		while (ear.prev != ear.next) {
			var prev = ear.prev, next = ear.next;
			if (isEar(ear)) {
				out.push(prev.i);
				out.push(ear.i);
				out.push(next.i);
				remove(ear);
				ear = next.next;
				stop = next.next;
				continue;
			}
			ear = next;
			if (ear == stop) {
				if (pass == 0) earcutLinked(filterPoints(ear), out, 1);
				else if (pass == 1) {
					ear = cureLocalIntersections(filterPoints(ear), out);
					earcutLinked(ear, out, 2);
				} else if (pass == 2) splitEarcut(ear, out);
				break;
			}
		}
	}

	static function isEar(ear:EarNode):Bool {
		var a = ear.prev, b = ear, c = ear.next;
		if (area(a, b, c) >= 0) return false;
		var p = ear.next.next;
		while (p != ear.prev) {
			if (pointInTriangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y) && area(p.prev, p, p.next) >= 0) return false;
			p = p.next;
		}
		return true;
	}

	static function cureLocalIntersections(start:EarNode, out:Array<Int>):EarNode {
		var p = start;
		do {
			var a = p.prev, b = p.next.next;
			if (!equals(a, b) && intersects(a, p, p.next, b) && locallyInside(a, b) && locallyInside(b, a)) {
				out.push(a.i);
				out.push(p.i);
				out.push(b.i);
				remove(p);
				remove(p.next);
				p = start = b;
			}
			p = p.next;
		} while (p != start);
		return filterPoints(p);
	}

	static function splitEarcut(start:EarNode, out:Array<Int>) {
		var a = start;
		do {
			var b = a.next.next;
			while (b != a.prev) {
				if (a.i != b.i && isValidDiagonal(a, b)) {
					var c = splitPolygon(a, b);
					a = filterPoints(a, a.next);
					c = filterPoints(c, c.next);
					earcutLinked(a, out, 0);
					earcutLinked(c, out, 0);
					return;
				}
				b = b.next;
			}
			a = a.next;
		} while (a != start);
	}

	static function eliminateHoles(data:Array<Float>, holes:Array<Int>, outer:EarNode):EarNode {
		var queue:Array<EarNode> = [];
		for (k in 0...holes.length) {
			var start = holes[k] * 2, end = k < holes.length - 1 ? holes[k + 1] * 2 : data.length;
			var list = linked(data, start, end, false);
			if (list == null) continue;
			if (list == list.next) list.steiner = true;
			queue.push(leftmost(list));
		}
		queue.sort((a, b) -> a.x < b.x ? -1 : a.x > b.x ? 1 : 0);
		for (h in queue)
			outer = eliminateHole(h, outer);
		return outer;
	}

	static function eliminateHole(hole:EarNode, outer:EarNode):EarNode {
		var bridge = findHoleBridge(hole, outer);
		if (bridge == null) return outer;
		var reverse = splitPolygon(bridge, hole);
		filterPoints(reverse, reverse.next);
		return filterPoints(bridge, bridge.next);
	}

	// (David Eberly's: a point of the outline the hole's leftmost point sees)
	static function findHoleBridge(hole:EarNode, outer:EarNode):Null<EarNode> {
		var p = outer, hx = hole.x, hy = hole.y, qx = Math.NEGATIVE_INFINITY;
		var m:Null<EarNode> = null;
		do {
			if (hy <= p.y && hy >= p.next.y && p.next.y != p.y) {
				var x = p.x + (hy - p.y) * (p.next.x - p.x) / (p.next.y - p.y);
				if (x <= hx && x > qx) {
					qx = x;
					m = p.x < p.next.x ? p : p.next;
					if (x == hx) return m;
				}
			}
			p = p.next;
		} while (p != outer);
		if (m == null) return null;
		var stop = m, mx = m.x, my = m.y, tanMin = Math.POSITIVE_INFINITY;
		p = m;
		do {
			if (hx >= p.x && p.x >= mx && hx != p.x
				&& pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, p.x, p.y)) {
				var tan = Math.abs(hy - p.y) / (hx - p.x);
				if (locallyInside(p, hole) && (tan < tanMin || (tan == tanMin && (p.x > m.x || (p.x == m.x && sectorContainsSector(m, p)))))) {
					m = p;
					tanMin = tan;
				}
			}
			p = p.next;
		} while (p != stop);
		return m;
	}

	static function sectorContainsSector(m:EarNode, p:EarNode):Bool
		return area(m.prev, m, p.prev) < 0 && area(p.next, m, m.next) < 0;

	static function leftmost(start:EarNode):EarNode {
		var p = start, l = start;
		do {
			if (p.x < l.x || (p.x == l.x && p.y < l.y)) l = p;
			p = p.next;
		} while (p != start);
		return l;
	}

	static inline function pointInTriangle(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, px:Float, py:Float):Bool
		return (cx - px) * (ay - py) >= (ax - px) * (cy - py) && (ax - px) * (by - py) >= (bx - px) * (ay - py)
			&& (bx - px) * (cy - py) >= (cx - px) * (by - py);

	static function isValidDiagonal(a:EarNode, b:EarNode):Bool
		return a.next.i != b.i && a.prev.i != b.i && !intersectsPolygon(a, b)
			&& (locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b) && (area(a.prev, a, b.prev) != 0 || area(a, b.prev, b) != 0)
				|| equals(a, b) && area(a.prev, a, a.next) > 0 && area(b.prev, b, b.next) > 0);

	static inline function area(p:EarNode, q:EarNode, r:EarNode):Float
		return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);

	static inline function equals(a:EarNode, b:EarNode):Bool
		return a.x == b.x && a.y == b.y;

	static function intersects(p1:EarNode, q1:EarNode, p2:EarNode, q2:EarNode):Bool {
		var o1 = sign(area(p1, q1, p2)), o2 = sign(area(p1, q1, q2)), o3 = sign(area(p2, q2, p1)), o4 = sign(area(p2, q2, q1));
		if (o1 != o2 && o3 != o4) return true;
		if (o1 == 0 && onSegment(p1, p2, q1)) return true;
		if (o2 == 0 && onSegment(p1, q2, q1)) return true;
		if (o3 == 0 && onSegment(p2, p1, q2)) return true;
		if (o4 == 0 && onSegment(p2, q1, q2)) return true;
		return false;
	}

	static inline function onSegment(p:EarNode, q:EarNode, r:EarNode):Bool
		return q.x <= Math.max(p.x, r.x) && q.x >= Math.min(p.x, r.x) && q.y <= Math.max(p.y, r.y) && q.y >= Math.min(p.y, r.y);

	static inline function sign(v:Float):Int
		return v > 0 ? 1 : v < 0 ? -1 : 0;

	static function intersectsPolygon(a:EarNode, b:EarNode):Bool {
		var p = a;
		do {
			if (p.i != a.i && p.next.i != a.i && p.i != b.i && p.next.i != b.i && intersects(p, p.next, a, b)) return true;
			p = p.next;
		} while (p != a);
		return false;
	}

	static function locallyInside(a:EarNode, b:EarNode):Bool
		return area(a.prev, a, a.next) < 0 ? area(a, b, a.next) >= 0 && area(a, a.prev, b) >= 0 : area(a, b, a.prev) < 0 || area(a, a.next, b) < 0;

	static function middleInside(a:EarNode, b:EarNode):Bool {
		var p = a, inside = false, px = (a.x + b.x) / 2, py = (a.y + b.y) / 2;
		do {
			if (((p.y > py) != (p.next.y > py)) && p.next.y != p.y && (px < (p.next.x - p.x) * (py - p.y) / (p.next.y - p.y) + p.x)) inside = !inside;
			p = p.next;
		} while (p != a);
		return inside;
	}

	// (a and b joined by a diagonal: the ring split in two, b2 on the second)
	static function splitPolygon(a:EarNode, b:EarNode):EarNode {
		var a2 = new EarNode(a.i, a.x, a.y), b2 = new EarNode(b.i, b.x, b.y);
		var an = a.next, bp = b.prev;
		a.next = b;
		b.prev = a;
		a2.next = an;
		an.prev = a2;
		b2.next = a2;
		a2.prev = b2;
		bp.next = b2;
		b2.prev = bp;
		return b2;
	}

	static function insert(i:Int, x:Float, y:Float, last:Null<EarNode>):EarNode {
		var p = new EarNode(i, x, y);
		if (last == null) {
			p.prev = p;
			p.next = p;
		} else {
			p.next = last.next;
			p.prev = last;
			last.next.prev = p;
			last.next = p;
		}
		return p;
	}

	static function remove(p:EarNode) {
		p.next.prev = p.prev;
		p.prev.next = p.next;
	}
}

private class EarNode {
	public final i:Int;
	public final x:Float;
	public final y:Float;
	public var prev:EarNode;
	public var next:EarNode;
	public var steiner = false;

	public function new(i:Int, x:Float, y:Float) {
		this.i = i;
		this.x = x;
		this.y = y;
		prev = this;
		next = this;
	}
}
