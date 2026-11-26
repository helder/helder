package helder.css;

import haxe.io.Bytes;
import helder.dom.Element;

using StringTools;

// The ancestors of the element being matched, as a counting Bloom filter
// (WebKit's SelectorFilter, Stylo's StyleBloom): each ancestor's tag, id and
// classes (CssHash's) counted in 4,096 one-byte counters, two a hash. A walk
// pushes an element before its children are matched and pops it after; a
// selector whose ancestor hashes (CssSelector.hashes) are not all in it
// cannot match, so most descendant and child selectors are rejected before
// matching. A counter that reaches 255 stays there (never wrongly no).
class CssBloom {
	static inline var BITS = 12;
	static inline var SIZE = 1 << BITS;
	static inline var MASK = SIZE - 1;

	final counts = Bytes.alloc(SIZE);
	// (the hashes pushed, and how many each element pushed: popped as pushed)
	final hashes:Array<Int> = [];
	final pushed:Array<Int> = [];

	public function new() {}

	// how many elements are pushed
	public var depth(get, never):Int;

	inline function get_depth():Int
		return pushed.length;

	// el's ancestors pushed, outermost first (a filter for one element, no walk)
	public static function of(el:Null<Element>):CssBloom {
		var b = new CssBloom(), chain = [], p = el == null ? null : el.parentElement;
		while (p != null) {
			chain.push(p);
			p = p.parentElement;
		}
		var k = chain.length;
		while (k > 0)
			b.push(chain[--k]);
		return b;
	}

	// the filter made el's ancestors' (for elements met in any order, as a
	// lazy cascade meets them: the ancestors shared with the last element
	// stay, the others popped and pushed; in tree order, few). The tree
	// must not have changed since the last call: reset() if it has
	// (CssStyles.forget does).
	public function moveTo(el:Element) {
		// (in tree order, without a walk up: a sibling of the last element
		// changes nothing, its child pushes one, going back up pops to the
		// parent found in the chain)
		var p = el.parentElement, top = chain.length == 0 ? null : chain[chain.length - 1];
		if (p == top) return;
		if (p != null && p.parentElement == top) {
			chain.push(p);
			push(p);
			return;
		}
		var k = chain.length - 1;
		while (k >= 0 && chain[k] != p)
			k--;
		if (k >= 0 || p == null) {
			while (chain.length > k + 1) {
				chain.pop();
				pop();
			}
			return;
		}
		ancestors.resize(0);
		var p = el.parentElement;
		while (p != null) {
			ancestors.push(p);
			p = p.parentElement;
		}
		// (ancestors outermost last; the chain pushed outermost first)
		var shared = 0, n = ancestors.length;
		while (shared < chain.length && shared < n && chain[shared] == ancestors[n - 1 - shared])
			shared++;
		while (chain.length > shared) {
			chain.pop();
			pop();
		}
		for (k in shared...n) {
			var a = ancestors[n - 1 - k];
			chain.push(a);
			push(a);
		}
	}

	// empty again (after the tree changed under moveTo's chain)
	public function reset() {
		while (pushed.length > 0)
			pop();
		chain.resize(0);
	}

	// (moveTo's: what it pushed, and its scratch)
	final chain:Array<Element> = [];
	final ancestors:Array<Element> = [];

	public function push(el:Element) {
		var from = hashes.length;
		hashes.push(CssHash.of(el.localName));
		var id = el.getAttributeNS(null, "id");
		if (id != null && id != "") hashes.push(CssHash.of(id));
		var cls = el.getAttributeNS(null, "class");
		if (cls != null) {
			var n = cls.length, k = 0;
			while (k < n) {
				while (k < n && space(cls.fastCodeAt(k)))
					k++;
				var start = k;
				while (k < n && !space(cls.fastCodeAt(k)))
					k++;
				if (k > start) hashes.push(CssHash.range(cls, start, k));
			}
		}
		for (i in from...hashes.length)
			add(hashes[i]);
		pushed.push(hashes.length - from);
	}

	// the last element pushed taken out
	public function pop() {
		var n = pushed.pop();
		for (_ in 0...n)
			remove(hashes.pop());
	}

	public inline function mightHave(h:Int):Bool
		return counts.get(h & MASK) != 0 && counts.get((h >>> BITS) & MASK) != 0;

	// false: s cannot match an element whose ancestors these are
	public function mightMatch(s:CssSelector):Bool {
		for (h in s.hashes)
			if (!mightHave(h)) return false;
		return true;
	}

	inline function add(h:Int) {
		bump(h & MASK, 1);
		bump((h >>> BITS) & MASK, 1);
	}

	inline function remove(h:Int) {
		bump(h & MASK, -1);
		bump((h >>> BITS) & MASK, -1);
	}

	inline function bump(i:Int, d:Int) {
		var c = counts.get(i);
		if (c != 255) counts.set(i, c + d);
	}

	static inline function space(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 12 || c == 13;
}
