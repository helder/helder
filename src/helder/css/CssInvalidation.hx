package helder.css;

import helder.css.CssSelector;
import helder.dom.Element;
import helder.dom.ElementState;

using StringTools;

// Invalidation sets, as Blink's RuleFeatureSet makes them: for each class,
// id, attribute name and state bit some selector depends on, which
// elements may match differently when it changes on an element E (flags):
// E itself (SELF), its descendants (SUBTREE), its next sibling (NEXT) or
// all its later siblings (LATER, each with its subtree), all its siblings
// with their subtrees (SIBLINGS: :nth-child(of S)'s counts), or the whole
// document (DOCUMENT). A feature's flags come from where it sits: in the
// subject compound SELF, in one a child or descendant combinator follows
// SUBTREE, in one a sibling combinator follows NEXT or LATER; inside :is(),
// :where() or :not() where that compound sits. A top-level compound's
// feature keeps the ids, classes and tag the compound also requires (its
// guard, as Blink's sets do): a change on an element without them cannot
// change what the compound matches, so `.row:focus-within .actions` set
// on <body> invalidates nothing.
//
// Conservative, and what it costs: anything inside :has() invalidates the
// document; a child inserted or removed restyles its parent's subtree when
// a selector counts siblings (:nth-*, :first-child..., + and ~) or reads
// :empty; an attribute change always restyles its element (presentational
// hints, the style attribute); pseudo-classes read from ancestors' attributes
// (:lang, :dir, :disabled in a fieldset, contenteditable) restyle the subtree.
class CssInvalidation {
	public static inline var SELF = 1;
	public static inline var SUBTREE = 2;
	public static inline var NEXT = 4;
	public static inline var LATER = 8;
	public static inline var SIBLINGS = 16;
	public static inline var DOCUMENT = 32;

	final classes = new Map<String, Feature>();
	final ids = new Map<String, Feature>();
	final attributes = new Map<String, Feature>();
	// (each ElementState bit's, by the bit's index)
	final states:Array<Feature> = [for (_ in 0...16) new Feature()];

	// what a child inserted or removed restyles of its parent's: SUBTREE (siblings counted), SELF (:empty)
	public var structure(default, null) = 0;
	// what a text's change restyles of its parent (:empty, a textarea's validity)
	public var text(default, null) = 0;

	public function new() {}

	public static function of(selectors:Iterable<CssSelector>):CssInvalidation {
		var i = new CssInvalidation();
		for (s in selectors)
			i.add(s);
		return i;
	}

	public function add(s:CssSelector)
		complex(s, SELF);

	// a change of these on el: the flags of what to restyle (old: its
	// class and id before a change of them, for the guards: what el had
	// counts as what it has)
	public function forClass(name:String, el:Element, ?oldClass:String):Int
		return flags(classes.get(Css.lower(name)), el, oldClass, null);

	public function forId(id:String, el:Element, ?oldId:String):Int
		return flags(ids.get(Css.lower(id)), el, null, oldId);

	public function forAttribute(localName:String, el:Element):Int
		return flags(attributes.get(Css.lower(localName)), el, null, null);

	public function forState(changed:Int, el:Element):Int {
		var f = 0;
		for (k in 0...states.length)
			if (changed & (1 << k) != 0) f |= flags(states[k], el, null, null);
		return f;
	}

	static function flags(feature:Null<Feature>, el:Element, oldClass:Null<String>, oldId:Null<String>):Int {
		if (feature == null) return 0;
		var f = feature.any;
		for (g in feature.guarded)
			if (f & g.f != g.f && g.allows(el, oldClass, oldId)) f |= g.f;
		return f;
	}

	// (a selector inside a compound whose flags are outer: SELF for a
	// top-level one; nested: inside :is(), :not(), :has()..., whose
	// features keep no guard)
	function complex(s:CssSelector, outer:Int, nested = false) {
		var last = s.compounds.length - 1;
		for (k in 0...s.compounds.length) {
			if (k < last) switch s.combinators[k] {
				case NextSibling | SubsequentSibling: structure |= SUBTREE;
				default:
			}
			var own = k == last ? SELF : switch s.combinators[k] {
				case Child | Descendant: SUBTREE;
				case NextSibling: allAncestral(s, k + 1) ? NEXT : LATER;
				case SubsequentSibling: LATER;
			}
			var f = combine(own, outer);
			for (x in s.compounds[k])
				simple(x, f, nested ? null : s.compounds[k]);
		}
	}

	// (whether every combinator from k on is a child or descendant one)
	static function allAncestral(s:CssSelector, k:Int):Bool {
		for (j in k...s.combinators.length)
			if (s.combinators[j] == NextSibling || s.combinators[j] == SubsequentSibling) return false;
		return true;
	}

	// (an inner selector's flags inside a compound whose flags are outer:
	// what changes for E's descendants stays in E's subtree; for its
	// siblings, their subtrees, and their later siblings if outer moves on)
	static function combine(inner:Int, outer:Int):Int {
		if (outer & DOCUMENT != 0 || inner & DOCUMENT != 0) return DOCUMENT;
		if (inner == SELF) return outer;
		if (inner & (NEXT | LATER | SIBLINGS) != 0) return outer & (NEXT | LATER | SIBLINGS) != 0 ? LATER | SIBLINGS : inner;
		return SUBTREE;
	}

	// (compound: the one x is in, for its guard; null: no guard)
	function simple(x:CssSimple, f:Int, compound:Null<CssCompound>) {
		var g = compound == null ? null : Guard.of(compound, x);
		switch x {
			case Id(n): put(ids, n, f, g);
			case Class(n): put(classes, n, f, g);
			case Attribute(n, _, _, _, _): put(attributes, n, f, g);
			case Type(_, _) | Universal(_):
			case Pseudo(p): pseudo(p, f, g);
		}
	}

	function pseudo(p:CssPseudoClass, f:Int, g:Null<Guard>)
		switch p {
			case Is(l) | Where(l) | Not(l):
				for (s in l)
					complex(s, f, true);
			case Has(l):
				// (conservative: anything inside :has() restyles the document)
				for (s in l)
					complex(s, DOCUMENT, true);
				structure |= DOCUMENT;
				text |= DOCUMENT;
			case NthChild(_, of) | NthLastChild(_, of):
				structure |= SUBTREE;
				if (of != null) for (s in of)
					complex(s, s.compounds.length == 1 ? combine(SIBLINGS, f) | SIBLINGS : DOCUMENT, true);
			case NthOfType(_) | NthLastOfType(_) | FirstChild | LastChild | OnlyChild | FirstOfType | LastOfType | OnlyOfType:
				structure |= SUBTREE;
			case Empty:
				structure |= SELF | f;
				text |= SELF | f;
			case State(bits, _):
				state(bits, f, g);
			case Checked:
				state(ElementState.CHECKED | ElementState.CHECKED_DIRTY, f, g);
				attrs(["checked", "type"], f, g);
				// (an option's selected attribute changes its select's other options' selectedness, in any optgroup)
				attrs(["selected"], DOCUMENT, null);
			case Indeterminate:
				state(ElementState.INDETERMINATE, f, g);
				attrs(["value"], f, g);
			case Default:
				attrs(["checked", "selected", "type"], f, g);
			case Required | Optional:
				attrs(["required"], f, g);
			case Valid | Invalid:
				// (a select's validity reads its options': no guard)
				state(ElementState.CHECKED | ElementState.CHECKED_DIRTY, f, null);
				attrs(["required", "value", "checked", "type", "disabled"], f, null);
				attrs(["selected"], DOCUMENT, null);
				structure |= SELF | f;
				text |= SELF | f;
			case PlaceholderShown:
				attrs(["placeholder", "value", "type"], f, g);
				text |= SELF | f;
			case Link | AnyLink:
				attrs(["href"], f, g);
			// (read from ancestors' attributes: their subtrees, no guard)
			case Lang(_):
				attrs(["lang"], f | SUBTREE, null);
			case Dir(_):
				attrs(["dir"], f | SUBTREE, null);
			case Enabled | Disabled:
				attrs(["disabled", "type"], f | SUBTREE, null);
			case ReadOnly | ReadWrite:
				attrs(["readonly", "disabled", "type", "contenteditable"], f | SUBTREE, null);
			case Root | Scope | Defined | Never(_):
		}

	function state(bits:Int, f:Int, g:Null<Guard>)
		for (k in 0...states.length)
			if (bits & (1 << k) != 0) states[k].add(f, g);

	function attrs(names:Array<String>, f:Int, g:Null<Guard>)
		for (n in names)
			put(attributes, n, f, g);

	static function put(m:Map<String, Feature>, name:String, f:Int, g:Null<Guard>) {
		var k = Css.lower(name), feature = m.get(k);
		if (feature == null) m.set(k, feature = new Feature());
		feature.add(f, g);
	}
}

// (a feature's flags: those with no guard, and those with each guard,
// guards that say the same merged)
private class Feature {
	public var any = 0;
	public final guarded:Array<Guard> = [];

	public function new() {}

	public function add(f:Int, g:Null<Guard>) {
		if (g == null || g.empty()) {
			any |= f;
			return;
		}
		for (x in guarded)
			if (x.key == g.key) {
				x.f |= f;
				return;
			}
		g.f = f;
		guarded.push(g);
	}
}

// (what else a compound requires of an element: its tag, ids and classes, lowercased)
private class Guard {
	public final tag:Null<String>;
	public final ids:Array<String>;
	public final classes:Array<String>;
	public final key:String;
	public var f = 0;

	function new(tag:Null<String>, ids:Array<String>, classes:Array<String>) {
		this.tag = tag;
		this.ids = ids;
		this.classes = classes;
		key = (tag ?? "") + "#" + ids.join("#") + "." + classes.join(".");
	}

	// (the compound's but the feature itself)
	public static function of(compound:CssCompound, feature:CssSimple):Guard {
		var tag = null, ids = [], classes = [];
		for (x in compound) {
			if (x == feature) continue;
			switch x {
				case Type(n, _): tag = Css.lower(n);
				case Id(n): ids.push(Css.lower(n));
				case Class(n): classes.push(Css.lower(n));
				default:
			}
		}
		return new Guard(tag, ids, classes);
	}

	public inline function empty():Bool
		return tag == null && ids.length == 0 && classes.length == 0;

	public function allows(el:Element, oldClass:Null<String>, oldId:Null<String>):Bool {
		if (tag != null && Css.lower(el.localName) != tag) return false;
		if (ids.length > 0) {
			var id = Css.lower(el.getAttributeNS(null, "id") ?? ""), old = oldId == null ? null : Css.lower(oldId);
			for (i in ids)
				if (i != id && i != old) return false;
		}
		if (classes.length > 0) {
			var now = Css.lower(el.getAttributeNS(null, "class") ?? ""), was = oldClass == null ? "" : Css.lower(oldClass);
			for (c in classes)
				if (!has(now, c) && !has(was, c)) return false;
		}
		return true;
	}

	static function has(list:String, c:String):Bool {
		var n = list.length, m = c.length, k = 0;
		while (k < n) {
			while (k < n && space(list.fastCodeAt(k)))
				k++;
			var start = k;
			while (k < n && !space(list.fastCodeAt(k)))
				k++;
			if (k - start == m && list.substr(start, m) == c) return true;
		}
		return false;
	}

	static inline function space(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 12 || c == 13;
}

