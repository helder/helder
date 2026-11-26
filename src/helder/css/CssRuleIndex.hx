package helder.css;

import helder.css.CssSelector;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// Selectors (each with the caller's value: a rule, a declaration block)
// indexed by their rightmost compound, as browsers do: by its id, else a
// class, else its type, else an attribute's name, else in the universal
// bucket. Matching an element visits its own buckets alone (its id's, its
// classes', its tag's, those of the attributes it has, the universal one),
// rejects with the ancestors' Bloom filter what cannot match, and matches
// the rest. :is() of types alone and :link go by their types, :root
// apart. Keys are ASCII-lowercased, so quirks mode's classes and IDs
// and HTML's tags find their rules; CssMatcher decides the case. An
// attribute selector with a namespace goes to the universal bucket.
class CssRuleIndex<T> {
	final ids = new Map<String, Array<CssIndexed<T>>>();
	final classes = new Map<String, Array<CssIndexed<T>>>();
	final tags = new Map<String, Array<CssIndexed<T>>>();
	final attributes = new Map<String, Array<CssIndexed<T>>>();
	// (each attribute bucket's names: as written and lowercased, for hasAttributeNS)
	final attributeNames:Array<{written:String, lower:String}> = [];
	final universal:Array<CssIndexed<T>> = [];
	final roots:Array<CssIndexed<T>> = [];
	var count = 0;
	final scratch:Array<CssIndexed<T>> = [];
	final seen:Array<String> = [];

	// what matching did since made or reset: entries visited, rejected by the Bloom filter, matched
	public var visited(default, null) = 0;
	public var rejected(default, null) = 0;
	public var matched(default, null) = 0;
	// the selectors that are not local (CssSelector.local) the last matching
	// tried past the Bloom filter, and whether each matched: what a style
	// shared with another element must match there alike (Stylo's revalidation)
	public final revalidate:Array<CssSelector> = [];
	public final revalidated:Array<Bool> = [];

	public function new() {}

	public var length(get, never):Int;

	inline function get_length():Int
		return count;

	// order: the cascade's order of appearance (the order added)
	public function add(selector:CssSelector, value:T) {
		var e = new CssIndexed(selector, value, count++);
		switch selector.bucket {
			case ById(k): push(ids, k, e);
			case ByClass(k): push(classes, k, e);
			case ByTag(keys): for (k in keys) push(tags, k, e);
			case ByRoot: roots.push(e);
			case ByAttribute(name):
				var k = Css.lower(name);
				if (!attributes.exists(k)) attributeNames.push({written: name, lower: k});
				push(attributes, k, e);
			case Anywhere: universal.push(e);
		}
	}

	static function push<T>(m:Map<String, Array<CssIndexed<T>>>, k:String, e:CssIndexed<T>) {
		var a = m.get(k);
		if (a == null) m.set(k, a = []);
		a.push(e);
	}

	// the entries el's buckets hold, into out (not matched)
	public function candidates(el:Element, out:Array<CssIndexed<T>>) {
		var id = el.getAttributeNS(null, "id");
		if (id != null && id != "") append(ids.get(Css.lower(id)), out);
		var cls = el.getAttributeNS(null, "class");
		if (cls != null && classes.keys().hasNext()) {
			var n = cls.length, k = 0;
			seen.resize(0);
			while (k < n) {
				while (k < n && space(cls.fastCodeAt(k)))
					k++;
				var start = k;
				while (k < n && !space(cls.fastCodeAt(k)))
					k++;
				if (k == start) continue;
				// (class="a a": its bucket once)
				var key = Css.lower(cls.substring(start, k));
				if (seen.contains(key)) continue;
				seen.push(key);
				append(classes.get(key), out);
			}
		}
		append(tags.get(Css.lower(el.localName)), out);
		for (a in attributeNames)
			if (el.hasAttributeNS(null, a.written) || (a.lower != a.written && el.hasAttributeNS(null, a.lower))) append(attributes.get(a.lower), out);
		if (roots.length > 0 && el.parentNode != null && el.parentNode.nodeType == Node.DOCUMENT_NODE) append(roots, out);
		append(universal, out);
	}

	static inline function append<T>(a:Null<Array<CssIndexed<T>>>, out:Array<CssIndexed<T>>)
		if (a != null) for (e in a) out.push(e);

	// the entries whose selector matches el, in the order added, into out;
	// bloom: el's ancestors (null: none checked); scope: :scope's element
	public function matching(el:Element, out:Array<CssIndexed<T>>, ?bloom:CssBloom, ?scope:Element, ?cache:CssMatcher.CssHasCache) {
		scratch.resize(0);
		candidates(el, scratch);
		var from = out.length;
		revalidate.resize(0);
		revalidated.resize(0);
		for (e in scratch) {
			visited++;
			if (bloom != null && !bloom.mightMatch(e.selector)) {
				rejected++;
				continue;
			}
			var yes = CssMatcher.matches(e.selector, el, scope, cache);
			if (!e.selector.local) {
				revalidate.push(e.selector);
				revalidated.push(yes);
			}
			if (yes) {
				matched++;
				out.push(e);
			}
		}
		// (each entry in one bucket: sorted by order, no duplicates)
		if (out.length - from > 1) {
			var part = out.splice(from, out.length - from);
			part.sort((a, b) -> a.order - b.order);
			for (e in part)
				out.push(e);
		}
	}

	// every element under root (itself not, unless an element) in tree
	// order with the entries it matches, the Bloom filter kept as it goes:
	// f's array is reused, copy what is kept
	public function walk(root:Node, f:(Element, Array<CssIndexed<T>>) -> Void, ?scope:Element) {
		var bloom = CssBloom.of(root.nodeType == Node.ELEMENT_NODE ? cast root : null), out = [];
		function visit(el:Element) {
			out.resize(0);
			matching(el, out, bloom, scope);
			f(el, out);
		}
		// (an explicit stack: a tree as deep as its markup)
		var n = root.nodeType == Node.ELEMENT_NODE ? root : root.firstChild;
		var entered:Array<Element> = [];
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) {
				var el:Element = cast n;
				visit(el);
				if (el.firstChild != null) {
					bloom.push(el);
					entered.push(el);
					n = el.firstChild;
					continue;
				}
			}
			// (to the next node: up past finished elements, popping them)
			while (n != null && n != root && n.nextSibling == null) {
				n = n.parentNode;
				if (n != null && entered.length > 0 && entered[entered.length - 1] == n) {
					entered.pop();
					bloom.pop();
				}
			}
			n = n == null || n == root ? null : n.nextSibling;
		}
	}

	public function resetStats() {
		visited = rejected = matched = 0;
	}

	static inline function space(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 12 || c == 13;
}

// an indexed selector: its value and its order of appearance
class CssIndexed<T> {
	public final selector:CssSelector;
	public final value:T;
	public final order:Int;

	public function new(selector:CssSelector, value:T, order:Int) {
		this.selector = selector;
		this.value = value;
		this.order = order;
	}
}
