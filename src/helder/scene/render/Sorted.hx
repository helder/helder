package helder.scene.render;

// A stable merge sort of a list's first n, bottom up: the draw list and the
// shadow casters are gathered in their store's order each frame, which
// need not be near their sorted one (an insertion sort's n²). tmp: kept
// by the caller, grown here; after(a, b): a goes after b.
class Sorted {
	@:generic public static function sort<T>(a:Array<T>, n:Int, tmp:Array<T>, after:T->T->Bool) {
		if (n < 2) return;
		while (tmp.length < n)
			tmp.push(a[0]);
		var from = a, to = tmp, w = 1;
		while (w < n) {
			var lo = 0;
			while (lo < n) {
				var mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n;
				var i = lo, j = mid, k = lo;
				while (i < mid && j < hi)
					to[k++] = after(from[i], from[j]) ? from[j++] : from[i++];
				while (i < mid)
					to[k++] = from[i++];
				while (j < hi)
					to[k++] = from[j++];
				lo = hi;
			}
			var t = from;
			from = to;
			to = t;
			w *= 2;
		}
		if (from != a)
			for (k in 0...n)
				a[k] = from[k];
	}
}
