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

	public function new() {}

	public var length(get, never):Int;

	inline function get_length():Int
		return count;

	// order: the cascade's order of appearance (the order added)
	public function add(selector:CssSelector, value:T) {
		var e = new CssIndexed(selector, value, count++);
		var last = selector.compounds[selector.compounds.length - 1];
		var id = null, cls = null, tag = null, attr = null, kinds:Null<Array<String>> = null, isRoot = false;
		for (s in last)
			switch s {
				case Id(n) if (id == null): id = n;
				case Class(n) if (cls == null): cls = n;
				case Type(n, _) if (tag == null): tag = n;
				case Attribute(n, NoNamespace, _, _, _) if (attr == null): attr = n;
				case Pseudo(Link | AnyLink) if (kinds == null): kinds = ["a", "area"];
				case Pseudo(Root): isRoot = true;
				case Pseudo(Is(list)) if (kinds == null): kinds = types(list);
				default:
			}
		// (in one bucket, or in the tag buckets of :is()'s types or a link's:
		// an element has one tag, so it finds the entry once)
		if (id != null) push(ids, Css.lower(id), e) else if (cls != null) push(classes, Css.lower(cls), e) else if (tag != null) push(tags,
			Css.lower(tag), e) else if (kinds != null) for (k in kinds) push(tags, k, e) else if (isRoot) roots.push(e) else if (attr != null) {
			var k = Css.lower(attr);
			if (!attributes.exists(k)) attributeNames.push({written: attr, lower: k});
			push(attributes, k, e);
		} else universal.push(e);
	}

	// (:is()'s arguments' types when each is a type alone, lowercased, each once; else null)
	static function types(list:Array<CssSelector>):Null<Array<String>> {
		var out = [];
		for (x in list)
			switch x.compounds {
				case [[Type(n, _)]] if (x.pseudo == null):
					var k = Css.lower(n);
					if (!out.contains(k)) out.push(k);
				default:
					return null;
			}
		return out.length == 0 ? null : out;
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
	public function matching(el:Element, out:Array<CssIndexed<T>>, ?bloom:CssBloom, ?scope:Element) {
		scratch.resize(0);
		candidates(el, scratch);
		var from = out.length;
		for (e in scratch) {
			visited++;
			if (bloom != null && !bloom.mightMatch(e.selector)) {
				rejected++;
				continue;
			}
			if (CssMatcher.matches(e.selector, el, scope)) {
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
